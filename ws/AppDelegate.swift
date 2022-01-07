import UIKit

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
  private lazy var rootController: UINavigationController = {
    UINavigationController()
  }()
  
  var window: UIWindow?
  
  func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
    #if DEBUG
    Bundle(path: "/Applications/InjectionIII.app/Contents/Resources/iOSInjection.bundle")?.load()
    #endif
    
    window = UIWindow(frame: UIScreen.main.bounds)
    window?.makeKeyAndVisible()
    window?.rootViewController = rootController
    
    Dev.shared = Dev(navController: rootController)
    Dev.shared.run()
    
    return true
  }
}
