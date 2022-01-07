import Foundation

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
      fatalError("invalid packet length")
    }
  }
}

fileprivate enum ReplyStatus: String, Codable {
  case ok, error
}

struct ReplyError: Error {
  let code: UInt
  let reason: String
}

extension ReplyError: Decodable {
  init(from decoder: Decoder) throws {
    var container = try decoder.unkeyedContainer()
    code = try container.decode(UInt.self)
    reason = try container.decode(String.self)
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

// TODO buffer (to persist pushes when conn is not open),
// TODO reconnect timer (probably goes into the transport)
// TODO push timeout (socket.push(..., timeout: 5) { (result: ...) in result = .failure(TimeoutError)})
final class Socket {
  private var ref: UInt = 0
  private let decoder = JSONDecoder()
  private let encoder = JSONEncoder()
  private let pushInfo = PushInfo()
  private let transport: SocketTransport

  enum ConnectionState {
    case closed
    case open
    case disconnected
  }
  
  private(set) var state: ConnectionState = .closed
  
  init(transport: SocketTransport) {
    decoder.userInfo[.init(rawValue: "push")!] = pushInfo
    
    self.transport = transport
    // once connected, empty the buffer
    transport.onOpen = { [weak self] in self?.state = .open }
    // once connection closed, if state is not disconnected, create reconnection timer? or do it in the transport?
    transport.onClose = { [weak self] in self?.state = .closed }
    transport.onData = { [weak self] data in self?.receive(data) }
    // TODO transport.onError = { [weak self] }
  }
  
  // TODO convinience init(url: URL)
  
  deinit {
    disconnect()
  }
  
  func connect() {
    guard state == .closed else { return }
    transport.connect()
  }
  
  func disconnect() {
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

  func push<E: Encodable, T: Decodable>(_ event: String, payload: E, callback: @escaping (Result<T, Error>) -> ()) throws {
    ref &+= 1
    
    // if timeout given, create a timer that fires and calls callback with timeout error and removes reply from pushInfo.replies
    
    pushInfo.replies[ref] = { container in
      let status = try container.decode(ReplyStatus.self)
      
      // clear timer from firing here, needs to be done in the same queue?
      
      switch status {
      case .ok:
        let payload = try container.decode(T.self)
        callback(.success(payload))
        
      case .error:
        let error = try container.decode(ReplyError.self)
        callback(.failure(error))
      }
    }
    
    // if not connected, add to buffer
    // if connected, send
    let data = try encoder.encode(Request(ref: ref, event: event, payload: payload))
    transport.send(data)
  }
  
  private func receive(_ data: Data) {
    do {
      _ = try decoder.decode(Packet.self, from: data)
    } catch {
      print("receive error", error)
    }
  }
}

protocol SocketTransport: AnyObject {
  var onOpen: (() -> Void)? { get set }
  var onData: ((Data) -> Void)? { get set }
  var onError: ((Error) -> Void)? { get set }
  var onClose: (() -> Void)? { get set }
  
  func connect()
  func disconnect()
  func send(_ data: Data)
}

final class URLSessionWebSocketTransport: NSObject, SocketTransport {
  var onOpen: (() -> Void)?
  var onData: ((Data) -> Void)?
  var onError: ((Error) -> Void)?
  var onClose: (() -> Void)?
  
  private let url: URL
  private var session: URLSession?
  private var task: URLSessionWebSocketTask?
  
  // TODO headers with auth
  init(url: URL) {
    self.url = url
  }
  
  deinit {
    task?.cancel()
  }
  
  // reset reconnection attempts
  func connect() {
    // TODO delegateQueue? What should it be?
    session = URLSession(configuration: .default, delegate: self, delegateQueue: OperationQueue())
    task = session?.webSocketTask(with: url)
    task?.resume()
  }
  
  // stop reconnection
  func disconnect() {
    task?.cancel()
  }
  
  func send(_ data: Data) {
    task?.send(.string(.init(data: data, encoding: .utf8)!)) { error in
      // TODO wat do
    }
  }
}

extension URLSessionWebSocketTransport: URLSessionWebSocketDelegate {
  // stop reconnection
  func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
    onOpen?()
    receive()
  }
  
  private func receive() {
    task?.receive { [weak self] result in
      switch result {
      case let .success(message):
        switch message {
        case let .string(text):
          let data = text.data(using: .utf8)!
          self?.onData?(data)
        
        case .data:
          () // TODO
        
        @unknown default:
          () // TODO
        }
        
        self?.receive()
        
      // start reconnection?
      case let .failure(error):
        self?.onError?(error)
        self?.onClose?()
      }
    }
  }

  // start reconnection?
  func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
    if let error = error { onError?(error) }
    onClose?()
  }
  
  // start reconnection?
  // TODO don't ignore close code
  func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
    onClose?()
  }
}
