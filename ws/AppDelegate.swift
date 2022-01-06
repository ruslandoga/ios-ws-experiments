import UIKit

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
  private lazy var rootController: UINavigationController = {
    UINavigationController()
  }()
  
  var window: UIWindow?
  
  func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
    window = UIWindow(frame: UIScreen.main.bounds)
    window?.makeKeyAndVisible()
    window?.rootViewController = rootController
    
    let url = URL(string: "ws://localhost:4000/ws")!
    let transport = URLSessionWebSocketTransport(url: url)
    let socket = Socket(transport: transport)
    socket.connect()
    
    let vc = ViewController(socket: socket)
    rootController.setViewControllers([vc], animated: false)
    
    return true
  }
}
