import Foundation

enum PushError: Error {
  case timeout
  case reply(code: UInt, reason: String)
}

extension PushError: LocalizedError {
  var errorDescription: String? {
    switch self {
    case .timeout: return "push timed out"
    case let .reply(code: code, reason: reason): return "backend replied with error: code=\(code) reason=\(reason)"
    }
  }
}

enum SocketConnectionState {
  case closed
  case open
}

final class Socket {
  private var ref: UInt = 0
  private let decoder = JSONDecoder()
  private let encoder = JSONEncoder()
  private let pushInfo = PushInfo()
  private let transport: SocketTransport
  private var buffer = [UInt: Data]()
  
  var onError: (Error) -> ()
  
  var connection: SocketConnectionState {
    transport.connectionState
  }
  
  init(transport: SocketTransport, onError: @escaping (Error) -> ()) {
    self.onError = onError
    
    decoder.userInfo[.init(rawValue: "push")!] = pushInfo
    decoder.dateDecodingStrategy = .iso8601
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    
    self.transport = transport
    transport.onOpen = { [weak self] in self?.emptyBuffer() }
    transport.onData = { [weak self] data in self?.receive(data) }
    transport.onError = onError
    transport.connect()
  }
  
  convenience init(url: URL, onError: @escaping (Error) -> ()) {
    self.init(transport: URLSessionWebSocketTransport(req: .init(url: url)), onError: onError)
  }
  
  convenience init(url: URL, token: String, onError: @escaping (Error) -> ()) {
    self.init(url: url, headers: ["authorization": "Bearer \(token)"], onError: onError)
  }
  
  convenience init(url: URL, headers: [String: String], onError: @escaping (Error) -> ()) {
    var req = URLRequest(url: url)
    headers.forEach { header in req.addValue(header.value, forHTTPHeaderField: header.key) }
    let transport = URLSessionWebSocketTransport(req: req)
    self.init(transport: transport, onError: onError)
  }
  
  deinit {
    transport.disconnect()
  }

  func on<T: Decodable>(_ event: String, callback: @escaping (T) -> ()) {
    pushInfo.subscriptions[event] = { container in
      let payload = try container.decode(T.self)
      callback(payload)
    }
  }
  
  func off(_ event: String) {
    pushInfo.subscriptions[event] = nil
  }

  func push<E: Encodable, T: Decodable>(_ event: String, payload: E, timeout: TimeInterval? = 5, callback: @escaping (Result<T, PushError>) -> ()) {
    ref &+= 1
    let ref = ref
    
    var timer: Timer?
    
    if let timeout = timeout {
      // TODO use own queue
      timer = Timer.scheduledTimer(withTimeInterval: timeout, repeats: false) { [weak self] _ in
        guard let self = self else { return }
        self.pushInfo.replies[ref] = nil
        self.buffer[ref] = nil
        callback(.failure(.timeout))
      }
    }
    
    pushInfo.replies[ref] = { container in
      let status = try container.decode(ReplyStatus.self)
      
      // TODO needs to be some serial queue?
      timer?.invalidate()
      
      switch status {
      case .ok:
        let payload = try container.decode(T.self)
        callback(.success(payload))
        
      case .error:
        var errorContainer = try container.nestedUnkeyedContainer()
        let code = try errorContainer.decode(UInt.self)
        let reason = try errorContainer.decode(String.self)
        callback(.failure(.reply(code: code, reason: reason)))
      }
    }

    let request = Request(ref: ref, event: event, payload: payload)
    
    do {
      let data = try encoder.encode(request)
      sendElseBuffer(data, for: ref)
    } catch {
      onError(error)
    }
  }
  
  private func sendElseBuffer(_ data: Data, for ref: UInt) {
    transport.send(data) { [weak self] error in
      if error != nil {
        self?.buffer[ref] = data
      }
    }
  }
  
  private func emptyBuffer() {
    for (ref, data) in buffer {
      transport.send(data) { [weak self] error in
        if error == nil {
          self?.buffer[ref] = nil
        }
      }
    }
  }
  
  private func receive(_ data: Data) {
    do {
      _ = try decoder.decode(Packet.self, from: data)
    } catch {
      onError(error)
    }
  }
}

fileprivate struct Request<T: Encodable> {
  let ref: UInt
  let event: String
  let payload: T
}

extension Request: Encodable {
  func encode(to encoder: Encoder) throws {
    var container = encoder.unkeyedContainer()
    try container.encode(ref)
    try container.encode(event)
    try container.encode(payload)
  }
}

enum PackerError: Error {
  case invalidLength
}

extension PackerError: LocalizedError {
  var errorDescription: String? {
    switch self {
    case .invalidLength: return "received packet of invalid length"
    }
  }
}

fileprivate final class PushInfo {
  var subscriptions: [String: (inout UnkeyedDecodingContainer) throws -> Void] = [:]
  var replies: [UInt: (inout UnkeyedDecodingContainer) throws -> Void] = [:]
}

fileprivate struct Packet: Decodable {
  init(from decoder: Decoder) throws {
    var container = try decoder.unkeyedContainer()
    let info = decoder.userInfo[.init(rawValue: "push")!]! as! PushInfo
    
    switch container.count {
    case 2: // push
      let event = try container.decode(String.self)
      guard let subscription = info.subscriptions[event] else { return }
      try subscription(&container)

    case 3: // reply
      let ref = try container.decode(UInt.self)
      guard let reply = info.replies.removeValue(forKey: ref) else { return }
      try reply(&container)
    
    default:
      throw PackerError.invalidLength
    }
  }
}

fileprivate enum ReplyStatus: String, Codable {
  case ok, error
}

protocol SocketTransport: AnyObject {
  var onOpen: (() -> Void)? { get set }
  var onData: ((Data) -> Void)? { get set }
  var onError: ((Error) -> Void)? { get set }
  var onClose: (() -> Void)? { get set }
  
  var connectionState: SocketConnectionState { get }
  
  func connect()
  func disconnect()
  func send(_ data: Data, callback: @escaping (Error?) -> Void)
}

fileprivate let initialReconnectDelay: TimeInterval = 0.05

final class URLSessionWebSocketTransport: NSObject, SocketTransport {
  var onOpen: (() -> Void)?
  var onData: ((Data) -> Void)?
  var onError: ((Error) -> Void)?
  var onClose: (() -> Void)?

  private(set) var connectionState: SocketConnectionState = .closed
  private var reconnectDelay = initialReconnectDelay
  private var reconnectTimer: Timer?
  private var pingTimer: Timer?
  
  private let req: URLRequest
  private var task: URLSessionWebSocketTask?
  
  init(req: URLRequest) {
//    let queue = DispatchQueue(label: "asdf", qos: .userInitiated)
//    let oq = OperationQueue()
//    oq.underlyingQueue
    
    self.req = req
    // TODO delegateQueue? What should it be?
    // session = URLSession(configuration: .default, delegate: self, delegateQueue: OperationQueue())
    super.init()
  }
  
  deinit {
    disconnect()
  }

  func connect() {
    invalidateTimers()
    startWebSocketTask()
  }
  
  private func reconnect() {
    startWebSocketTask()
  }
  
  private func startWebSocketTask() {
    logger.debug("[websocket] connecting ...")
    
    task = URLSession.shared.webSocketTask(with: req)
    task?.delegate = self
    task?.priority = 1
    
    receive()
    
    task?.resume()
  }
  
  func disconnect() {
    logger.debug("[websocket] disconnecting ...")
    
    invalidateTimers()
    
    task?.cancel(with: .normalClosure, reason: nil)
    task = nil
  }
  
  private func scheduleReconnect() {
    logger.debug("[websocket] reconnecting ...")
    
    DispatchQueue.main.async {
      self.reconnectDelay *= 2
      self.reconnectDelay = min(5, self.reconnectDelay)
      self.reconnectTimer = Timer.scheduledTimer(withTimeInterval: self.reconnectDelay, repeats: false) { [weak self] _ in
        self?.reconnect()
      }
    }
  }
  
  private func invalidateReconnectTimer() {
    reconnectTimer?.invalidate()
    reconnectTimer = nil
    reconnectDelay = initialReconnectDelay
  }
  
  private func schedulePings() {
    DispatchQueue.main.async {
      self.pingTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
        self?.task?.sendPing { error in
          if let error = error {
            self?.onError?(error)
          }
        }
      }
    }
  }
  
  private func invalidatePingsTimer() {
    pingTimer?.invalidate()
    pingTimer = nil
  }
  
  private func invalidateTimers() {
    invalidateReconnectTimer()
    invalidatePingsTimer()
  }
  
  func send(_ data: Data, callback: @escaping (Error?) -> Void) {
    let text = String(data: data, encoding: .utf8)!
    task?.send(.string(text), completionHandler: callback)
  }
  
  private func receive() {
    task?.receive { [weak self] result in
      guard let self = self else { return }
      
      switch result {
      case let .success(message):
        if case let .string(text) = message {
          self.onData?(text.data(using: .utf8)!)
        }
        
        self.receive()

      case let .failure(error):
         self.onError?(error)
      }
    }
  }
}

extension URLSessionWebSocketTransport: URLSessionWebSocketDelegate {
  func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
    invalidateReconnectTimer()
    schedulePings()
    connectionState = .open
    onOpen?()
  }

  func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
    invalidatePingsTimer()
    connectionState = .closed
    onClose?()
    scheduleReconnect()
  }
}
