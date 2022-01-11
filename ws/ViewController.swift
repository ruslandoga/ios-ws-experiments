import UIKit

enum Gender: String, Codable {
  case male = "M"
  case female = "F"
  case nonbinary = "N"
}

struct LikeBroadcast: Decodable {
  let from: UUID
  let name: String
  let gender: Gender
}

struct LikeResponse: Decodable {
  let matched: Bool
}

//struct CallResponse: Decodable {
//  let id: UUID
//}

struct Empty: Decodable {}

final class ViewController: UIViewController {
  private var socket: Socket
  
  init(socket: Socket) {
    self.socket = socket
    super.init(nibName: nil, bundle: nil)
  }
  
  @available (*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }
  
  deinit {
    // TODO bag?
    socket.off("like")
  }
  
  override func viewWillDisappear(_ animated: Bool) {
    super.viewWillDisappear(animated)
    socket.push("hang-up", payload: ["call": "123"]) { (result: Result<Empty, PushError>) in }
  }
  
  override func viewDidLoad() {
    super.viewDidLoad()
    
    let label1 = UILabel()
    let label2 = UILabel()
    
    socket.on("like") { (like: LikeBroadcast) in
      DispatchQueue.main.async {
        label1.text = like.name
      }
    }
    
    // TODO buffer
    socket.push("like", payload: ["id": "123"]) { (result: Result<LikeResponse, PushError>) in
      guard case let .success(like) = result else { return }

      DispatchQueue.main.async {
        label2.text = like.matched ? "matched" : "not matched"
      }
    }
    
    // TODO backoff reconnect
    // socket.connect()
    
//    try? socket.push("call", payload: ["id": "123"]) { [weak self] (result: Result<CallResponse, PushError>) in
//      guard let self = self else { return }
//      guard case let .success(call) = result else { return }
//      DispatchQueue.main.async { self.runCall(id: call.id) }
//    }
  }
  
  func runCall(id: UUID) {
    // or do this on call?
    // socket.push("join-call", payload: ["id": id]) { data in
      // sdp
    // }
  }
}
