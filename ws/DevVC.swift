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
  let lockQueue = DispatchQueue(label: "name.lock.queue", attributes: .concurrent)
  
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
  
  // ~~I need to learn more about timers, how to schedule them from background using runloop, when it can fail etc~~ just use dispatch queues .asyncAfter
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
  // try lock with thread sanitizer
  private func run() {
    print("\n[RUN]")
    
    let started = Date()
    let lock = NSRecursiveLock()
    
    (1...6_000_000).forEach { i in
      lock.lock()
      _ = i + 1
      lock.unlock()
    }
    
    let ended = Date()
    print("done in", ended.timeIntervalSince1970 - started.timeIntervalSince1970)
    
//    lockQueue.async {
//      print("here 1", Thread.current)
//
//      self.lockQueue.async {
//        self.lockQueue.async {
//          print("here 5", Thread.current)
//        }
//
//        print("here 3", Thread.current)
//      }
//
//      print("here 2", Thread.current)
//
//      self.lockQueue.async {
//        print("here 4", Thread.current)
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
