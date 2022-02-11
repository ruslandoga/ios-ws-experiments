#if DEBUG
import UIKit
import os

class DevVC: UIViewController {
  var socket: Socket!
  let lockQueue = DispatchQueue(label: "name.lock.queue")
  var counter = 0
  
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
  
  private func run() {
    print("\n[RUN]")
    
    socket = Socket(url: URL(string: "ws://localhost:4000/ws")!, token: "token", queue: lockQueue)
    
    socket.onError = { error in print("🚷🚷🚷", error) }
    
    socket.onAuth = { [weak self] challenge in
      guard let self = self else { return }
      
      guard let httpResp = challenge.failureResponse as? HTTPURLResponse else {
        self.socket = nil
        return
      }
      
      print(httpResp)
      
      if let reason = httpResp.allHeaderFields["x-reason"] as? String {
        print(reason)
      }
      
      self.socket = nil
    }
    
    socket.on("event") { (event: Event) in
      print(event)
    }
    
//    socket.push("server-error", payload: ["ok": "ok"]) { (reply: Reply<Empty>) in
//      switch reply {
//      case let .success(data): ()
//      case .timeout: ()
//      case .fail(details: details): () // details = changeset.errors
//      case let .error(code: code, message: message): () // code = 1222 message = "database is unreachable"
////      case let .failure(error):
////        switch error {
////        case .timeout: ()
////        case let .fail
////        case let .reply(code: code, reason: reason): ()
////        }
////      }
//    }
    
    socket.connect()
  }
}

struct Event: Codable {
  let id: String
}

func retry(attempts: UInt = 2, block: @escaping (@escaping (Bool) -> Void) -> Void) {
  guard attempts > 0 else { return }
  
  block { again in
    if again {
      retry(attempts: attempts - 1, block: block)
    }
  }
}
#endif
