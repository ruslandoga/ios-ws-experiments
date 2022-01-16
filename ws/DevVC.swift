#if DEBUG
import UIKit
import os
//
//struct Event: Codable {
//  let id: String
//  let name: String
//}
//
//struct Event2: Codable {
//  let id: Int
//}
//
//struct CallRequest: Encodable {
//  let id: String
//}
//
//struct Profile: Decodable {
//  let name: String
//}
//
//struct CallResponse: Decodable {
//  let id: String
//  let iceServers: [URL]
//  let profile: Profile
//  let date: Date?
//  let point: CGPoint?
//}

//let req = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: timeout)
//URLSession.shared.dataTask(with: req) { <#Data?#>, <#URLResponse?#>, <#Error?#> in
//  <#code#>
//}
 
//fileCache.get(voicemail.url, for: voicemail.key) { [weak self] result in
//  switch result {
//  case let .success(data): self?.play(audio: data)
//  case let .failure(error): print("error", error)
//  }
//}
//
//final class FileCache {
//  private let lockQueue = DispatchQueue(label: "filecache.lock.queue")
//  private var callbacks = [String: [(Result<Data, Swift.Error>) -> Void]]()
//  private let root: URL
//
//  enum Error: Swift.Error {
//    case network
//  }
//  // TODO timeout
//  func get(_ url: URL, for key: String, callback: @escaping (Result<Data, Swift.Error>) -> Void) {
//    let keyURL = root.appendingPathComponent(key)
//
//    lockQueue.async { [weak self] in
//      guard let self = self else { return }
//
//      // data already cached
//      if let data = FileManager.default.contents(atPath: keyURL.path) {
//        callback(.success(data))
//      } else {
//        if var callbacks = self.callbacks[key] {
//          callbacks.append(callback)
//          return
//        }
//
//        self.callbacks[key] = [callback]
//
//        // or just use URLCache
//        let task = URLSession.shared.dataTask(with: url) { data, resp, error in
//          self.lockQueue.async { [weak self] in
//            guard let self = self else { return }
//            guard let callbacks = self.callbacks.removeValue(forKey: key) else { return }
//
//            if let error = error {
//              callbacks.forEach { $0(.failure(error)) }
//              return
//            }
//
//            guard let resp = resp as? HTTPURLResponse else {
//              callbacks.forEach { $0(.failure(Error.network)) }
//              return
//            }
//
//            guard resp.statusCode == 200 else {
//              callbacks.forEach { $0(.failure(Error.network)) }
//              return
//            }
//
//            guard let data = data else {
//              callbacks.forEach { $0(.failure(Error.network)) }
//              return
//            }
//
//            callbacks.forEach { $0(.success(data)) }
//
//            do {
//              try data.write(to: keyURL) // TODO .atomic
//            } catch {
//              // TODO
//              print("error wtiring \(data) to \(keyURL) for url=\(url) and key=\(key)", error)
//            }
//          }
//        }
//
//        // can also return progress
//        task.resume()
//      }
//    }
//  }
//
//  init(root: URL) {
//    self.root = root
//  }
//}

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
  
  // I need to learn more about timers, how to schedule them from background using runloop, when it can fail etc
  // I need to learn more about dispatch queues, self capture etc
  // check that github gist about gcd
  // learn about thread sanitizer https://twitter.com/twannl/status/1192781427978493952?s=20
  // watch that wwdc session on gcd
  // check out firebase crashlytics
  // https://developer.apple.com/videos/play/wwdc2018/414/
  // https://developer.apple.com/videos/play/wwdc2021/10203
  // https://developer.apple.com/videos/play/wwdc2020/10078
  // https://developer.apple.com/videos/play/wwdc2018/412
  // https://developer.apple.com/videos/play/wwdc2018/416
  // https://developer.apple.com/videos/play/wwdc2018/401
  // https://developer.apple.com/videos/play/wwdc2017/406
  private func run() {
    print("\n[RUN]")
    
    let lockQueue = DispatchQueue(label: "name.lock.queue")
    
    (1...100).forEach { i in lockQueue.async { print(i, Thread.current) } }
    
//    let timeout = DispatchWorkItem {
//      print("current thread is", Thread.current)
//    }
//
//    lockQueue.asyncAfter(deadline: .now() + 1, execute: timeout)
//    lockQueue.async { timeout.cancel() }
//
//    // TODO why disconnecting twice?
//    socket = Socket(url: URL(string: "ws://localhost:4000/ws")!, token: "some-token", queue: lockQueue)
    
//    socket.push("like", payload: ["id": 123]) { [weak self] (result: Result<LikeResponse, PushError>) in
//      self?.socket.push("like2", payload: ["id": 234]) { (result: Result<LikeResponse, PushError>) in
//
//      }
//    }
    
//    socket.push("echo", payload: ["id": 123]) { (result: Result<[String: Int], PushError>) in
//      print("echo", result)
//    }
//
//    socket.push("timeout", payload: [123], timeout: 0.2) { (result: Result<LikeResponse, PushError>) in
//      // should get decoding error here?
//      print("timeout", result)
//    }
//
//    DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
//      self.socket = nil
//
//      lockQueue.async {
//        print("disconnected")
//      }
//    }
  }
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
