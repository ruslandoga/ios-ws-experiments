#if DEBUG
import UIKit
import os

struct Event: Codable {
  let id: String
  let name: String
}

struct Event2: Codable {
  let id: Int
}

struct CallRequest: Encodable {
  let id: String
}

struct Profile: Decodable {
  let name: String
}

struct CallResponse: Decodable {
  let id: String
  let iceServers: [URL]
  let profile: Profile
  let date: Date?
  let point: CGPoint?
}

class DevVC: UIViewController {
  var socket: Socket!
  
  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .white
    run()
  }
  
  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
  }
  
  @objc func injected() {
    run()
  }
  
  // TODO https://stackoverflow.com/questions/60110667/urlsessionwebsockettask-fatal-error-only-one-of-message-or-error-should-be-nil
  private func run() {
    print("\n\n🏁🏁🏁 START")
    let url = URL(string: "ws://localhost:4000/ws")!
    // TODO handle failed auth:
    // socket = Socket(url: url)
    // socket.onError = { [weak self] error in if let error = error as AuthError { self?.logout() } }
    // or socket.onClose = { [weak self] code in if code == 403 { self?.logout() } }
    // or socket.on("forbidden") { [weak self] (e: Forbidden) in self?.logout() }
    // socket.connect()
    // or socket.connect { [weak self] error in if error == .forbidden { self?.logout() } }
    // Socket(..., onConnect: { error in ... })
    socket = Socket(url: url, token: "some-token", onError: { error in
      print("[‼️‼️‼️] [Socket]", error)
    })
    // socket.onError = { error in }
    
    socket.on("event") { (e: Event) in print(e.id) }
    socket.on("event2") { (e: Event2) in print(e.id) }
    
    socket.push("echo", payload: Event(id: "456", name: "John")) { (result: Result<Event, PushError>) in
      print("echo", result)
    }
    
    socket.push("error", payload: ["id": 123]) { (result: Result<Empty, PushError>) in
      print("error", result)
    }
    
    socket.push("unhandled", payload: ["id": 123]) { (result: Result<Empty, PushError>) in
      print("unhandled", result)
    }
    
    socket.push("crash", payload: ["id"]) { (result: Result<Empty, PushError>) in
      print("crash", result)
    }
    
    retry { [weak self] again in
      self?.socket.push("empty", payload: ["id": 123]) { (result: Result<Empty, PushError>) in
        print("empty", result)
        
        switch result {
        case .failure(.timeout): again(true)
        default: again(false)
        }
      }
    }
    
    socket.push("timeout", payload: ["id": 123]) { (result: Result<Empty, PushError>) in
      print("timeout", result)
    }
    
    socket.push("call", payload: CallRequest(id: "123")) { [weak socket] (result: Result<CallResponse, PushError>) in
      print("call 123", result)
      
      if case .success = result {
        socket?.push("call", payload: CallRequest(id: "234")) { (result: Result<CallResponse, PushError>) in
          print("call 234", result)
        }
      }
    }
  }
}

func retry(attempts: UInt = 2, block: @escaping (@escaping (Bool) -> Void) -> Void) {
  guard attempts > 0 else { return }
  
  block { again in
    if again { retry(attempts: attempts - 1, block: block) }
  }
}
#endif
