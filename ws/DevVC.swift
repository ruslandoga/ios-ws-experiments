#if DEBUG
import UIKit

class DevVC: UIViewController {
  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .white
  }
  
  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
  }
  
  @objc func injected() {
    do {
      try run()
    } catch {
      print("ERROR", error)
    }
  }
}

struct Event: Decodable {
  let id: String
}

var socket: Socket?

func run() throws {
  let url = URL(string: "ws://localhost:4000/ws")!
  
  socket?.disconnect()
  socket = Socket(transport: URLSessionWebSocketTransport(url: url))
  socket?.connect()
  
  try socket?.push("echo", payload: ["id": "12341234"]) { (result: Result<Event, Error>) in
    print(result)
  }
  
  socket?.on("event") { (event: Event) in
    print(event.id)
  }
}
#endif
