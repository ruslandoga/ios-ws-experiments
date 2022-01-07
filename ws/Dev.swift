#if DEBUG
import UIKit

class Dev {
  var navController: UINavigationController
  static var shared: Dev!
  
  init(navController: UINavigationController) {
    self.navController = navController
  }
  
  func run() {
    let vc = DevVC()
    navController.setViewControllers([], animated: false)
    navController.setViewControllers([vc], animated: false)
  }
}
#endif
