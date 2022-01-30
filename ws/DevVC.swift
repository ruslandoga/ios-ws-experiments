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
    
//    let queue = OperationQueue()
//    queue.underlyingQueue = lockQueue
//
//    let pairs = [(2, 3), (5, 3), (1, 7), (12, 34), (99, 99)]
//
//    pairs.forEach { pair in
//      let op = AsyncSumOperation(lhs: pair.0, rhs: pair.1)
//
//      op.completionBlock = {
//        print("\(pair.0) + \(pair.1) = \(op.result!)")
//      }
//
//      queue.addOperation(op)
//    }

//    lockQueue.async {
//      print("1")
//      for _ in 1...10000 {
//        self.counter += 1
//      }
//      print("2")
//    }
//
//    DispatchQueue.main.async {
//      print("3")
//      for _ in 1...10000 {
//        self.counter += 1
//      }
//      print("4")
//    }
  }
}

final class AsyncSumOperation: AsyncOperation {
  let rhs: Int
  let lhs: Int
  var result: Int?
  
  init(lhs: Int, rhs: Int) {
    self.rhs = rhs
    self.lhs = lhs
    super.init()
  }
  
  override func main() {
    Thread.sleep(forTimeInterval: 2)
    self.result = self.lhs + self.rhs
    self.state = .finished
  }
}

typealias ImageOperationCompletion = (Data?, URLResponse?, Error?) -> Void

final class NetworkImageOperation: AsyncOperation {
  var image: UIImage?
  
  private let url: URL
  private let completion: ImageOperationCompletion?
  
  init(url: URL, completion: ImageOperationCompletion? = nil) {
    self.url = url
    self.completion = completion
    super.init()
  }
  
  convenience init?(string: String, completion: ImageOperationCompletion? = nil) {
    guard let url = URL(string: string) else { return nil }
    self.init(url: url, completion: completion)
  }
  
  override func main() {
    URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
      guard let self = self else { return }
      defer { self.state = .finished }
      
      if let completion = self.completion {
        completion(data, response, error)
        return
      }
      
      guard error == nil, let data = data else { return }
      self.image = UIImage(data: data)
    }.resume()
  }
}

func callbacks() {
  listUsers { result in
    guard case let .success(users) = result else { return }
    
    loadAvatars(for: users) { result in
      guard case let .success(usersAndAvatars) = result else { return }
      DispatchQueue.main.async { print(usersAndAvatars) }
    }
  }
  
  // listUsers().then { users in loadAvatars(for: users) }
}

struct User {
  let name: String
}

func listUsers(callback: @escaping (Result<[User], Error>) -> Void) {
  DispatchQueue.main.async {
    let users = [User(name: "1"), User(name: "2")]
    callback(.success(users))
  }
}

func loadAvatars(for users: [User], callback: @escaping (Result<[(User, UIImage?)], Error>) -> Void) {
  DispatchQueue.main.async {
    let usersAndAvatars = users.map { user in (user, UIImage(data: Data())) }
    callback(.success(usersAndAvatars))
  }
}

//func duration(_ block: () -> Void) -> TimeInterval {
//  let start = Date()
//  block()
//  return Date().timeIntervalSince(start)
//}

class AsyncOperation: Operation {
  enum State: String {
    case ready, executing, finished
    
    fileprivate var keyPath: String {
      "is\(rawValue.capitalized)"
    }
  }
  
  var state = State.ready {
    willSet {
      willChangeValue(forKey: newValue.keyPath)
      willChangeValue(forKey: state.keyPath)
    }
    
    didSet {
      didChangeValue(forKey: oldValue.keyPath)
      didChangeValue(forKey: state.keyPath)
    }
  }
  
  override var isReady: Bool {
    super.isReady && state == .ready
  }
  
  override var isExecuting: Bool {
    state == .executing
  }
  
  override var isFinished: Bool {
    state == .finished
  }
  
  override var isAsynchronous: Bool {
    true
  }
  
  override func start() {
    if isCancelled {
      state = .finished
      return
    }
    
    main()
    state = .executing
  }
}

//
//final class TiltShiftOperation: Operation {
//  private static let context = CIContext()
//  var outputImage: UIImage?
//
//  private let inputImage: UIImage
//
//  init(image: UIImage) {
//    inputImage = image
//    super.init()
//  }
//
//  override func main() {
//    print("running main")
//    sleep(2)
//    outputImage = inputImage
//  }
//}

extension DispatchQueue {
  static func ensureMain(_ block: @escaping () -> Void) {
    if Thread.isMainThread {
      block()
    } else {
      main.async(execute: block)
    }
  }
}

//Promise { resolve, reject in
//  resolve(123)
//}.then { i in
//  print(i)
//}

//typealias Resolve<T> = (T) -> Void
//typealias Reject<Error> = (Error) -> Void
//
//final class Promise<T> {
//  private let block: (Resolve<T>, Reject<Error>) -> Void
//  private var next: Promise?
//
//  init(_ block: @escaping (Resolve<T>, Reject<Error>) -> Void) {
//    let resolve: Resolve<T> = { result in (result) }
//    let reject: Reject<Error> = { error in }
//  }
//
//  func then<T>(_ block: @escaping (Resolve<T>, Reject<Error>)) -> Promise<T> {
//    let promise = Promise(block)
//    next = promise
//    return promise
//  }
//}

func retry(attempts: UInt = 2, block: @escaping (@escaping (Bool) -> Void) -> Void) {
  guard attempts > 0 else { return }
  
  block { again in
    if again {
      retry(attempts: attempts - 1, block: block)
    }
  }
}
#endif
