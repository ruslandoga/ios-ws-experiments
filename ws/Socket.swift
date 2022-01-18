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
  private let queue: DispatchQueue
  private let lock = NSRecursiveLock()
  private var buffer = [UInt: Data]()
  
  var connection: SocketConnectionState {
    transport.connectionState
  }
  
  init(transport: SocketTransport, queue: DispatchQueue) {
    self.queue = queue
    
    decoder.userInfo[.init(rawValue: "push")!] = pushInfo
    decoder.dateDecodingStrategy = .iso8601
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    
    self.transport = transport
    // callbacks run on queue (URLSession.delegateQueue.underlyingQueue = queue)
    transport.onOpen = { [weak self] in self?.emptyBuffer() }
    transport.onData = { [weak self] data in self?.receive(data) }
    transport.connect()
  }
  
  convenience init(url: URL, queue: DispatchQueue) {
    self.init(url: url, headers: [:], queue: queue)
  }
  
  convenience init(url: URL, token: String, queue: DispatchQueue) {
    self.init(url: url, headers: ["authorization": "Bearer \(token)"], queue: queue)
  }
  
  convenience init(url: URL, headers: [String: String], queue: DispatchQueue) {
    var req = URLRequest(url: url)
    headers.forEach { header in req.addValue(header.value, forHTTPHeaderField: header.key) }
    
    let delegateQueue = OperationQueue()
    delegateQueue.underlyingQueue = queue
    let session = URLSession(configuration: .default, delegate: nil, delegateQueue: delegateQueue)
    let transport = URLSessionWebSocketTransport(req: req, session: session, queue: queue)
    
    self.init(transport: transport, queue: queue)
  }
  
  deinit {
    transport.disconnect()
  }
  
  func on<T: Decodable>(_ event: String, callback: @escaping (T) -> ()) {
    lock.lock()
    
    pushInfo.subscriptions[event] = { container in
      let payload = try container.decode(T.self)
      callback(payload)
    }
    
    lock.unlock()
  }
  
  func off(_ event: String) {
    lock.lock()
    pushInfo.subscriptions[event] = nil
    lock.unlock()
  }
  
  func push<E: Encodable, T: Decodable>(_ event: String, payload: E, timeout: TimeInterval? = 5, callback: @escaping (Result<T, PushError>) -> ()) {
    queue.async {
      self.ref &+= 1
      let ref = self.ref
      
      var timeoutWorkItem: DispatchWorkItem?
      
      if let timeout = timeout {
        let item = DispatchWorkItem { [weak self] in
          guard let self = self else { return }
          self.pushInfo.replies[ref] = nil
          self.buffer[ref] = nil
          callback(.failure(.timeout))
        }
        
        self.queue.asyncAfter(deadline: .now() + timeout, execute: item)
        timeoutWorkItem = item
      }
      
      // `reply` closure is already executed on queue (URLSession.delegateQueue.underlyingQueue = queue)
      self.pushInfo.replies[ref] = { container in
        timeoutWorkItem?.cancel()
        let status = try container.decode(ReplyStatus.self)
        
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
        let data = try self.encoder.encode(request)

        // try send, buffer in case of error
        self.transport.send(data) { [weak self] error in
          if error != nil {
            // TODO if timeoutWorkItem has run, don't store data to buffer
            // maybe can use operation queue for this
            self?.buffer[ref] = data
          }
        }
      } catch {
        // TODO
        print("encoding error", error)
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
      // TODO
      print("decoding error", error)
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
  private var reconnectItem: DispatchWorkItem?
  private var pingItem: DispatchWorkItem?

  private let req: URLRequest
  private let session: URLSession
  private let queue: DispatchQueue
  // private let lock = NSRecursiveLock()
  private var task: URLSessionWebSocketTask?
  
  init(req: URLRequest, session: URLSession, queue: DispatchQueue) {
    self.req = req
    self.session = session
    self.queue = queue
    super.init()
  }
  
//  deinit {
//    disconnect()
//  }
  
  func connect() {
    queue.async { [weak self] in
      guard let self = self else { return }
      guard self.task == nil else { return }
    
      if let reconnectItem = self.reconnectItem {
        reconnectItem.cancel()
        self.reconnectDelay = initialReconnectDelay
      }
      
      self.reconnect()
    }
  }
  
  private func reconnect() {
    logger.debug("[websocket] connecting ...")
    
    task = session.webSocketTask(with: req)
    task?.delegate = self
    task?.priority = 1
    
    receive()
    
    task?.resume()
  }
  
  func disconnect() {
    logger.debug("[websocket] disconnecting ...")
    
    reconnectItem?.cancel()
    pingItem?.cancel()
    
    task?.cancel(with: .normalClosure, reason: nil)
    task = nil
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
  
  private func scheduleNextPing() {
    let item = DispatchWorkItem { [weak self] in
      print("sending ping")
      self?.task?.sendPing { error in
        if let error = error {
          self?.onError?(error)
        }
        
        self?.scheduleNextPing()
      }
    }
    
    queue.asyncAfter(deadline: .now() + 45, execute: item)
    pingItem = item
  }
}

extension URLSessionWebSocketTransport: URLSessionWebSocketDelegate {
  func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
    reconnectItem?.cancel()
    reconnectDelay = initialReconnectDelay
    
    scheduleNextPing()
    
    connectionState = .open
    onOpen?()
  }
  
  func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
    pingItem?.cancel()
    
    connectionState = .closed
    onClose?()
    
    self.task = nil
    
    reconnectDelay *= 2
    reconnectDelay = min(5, reconnectDelay)

    // schedules next reconnect
    let item = DispatchWorkItem { [weak self] in
      print("reconnecting")
      self?.reconnect()
    }
    
    queue.asyncAfter(deadline: .now() + reconnectDelay, execute: item)
    reconnectItem = item
  }
}
