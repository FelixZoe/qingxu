import Flutter
import UIKit

class SceneDelegate: FlutterSceneDelegate {
  override func scene(
    _ scene: UIScene,
    willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions
  ) {
    super.scene(scene, willConnectTo: session, options: connectionOptions)

    guard
      let flutterViewController = window?.rootViewController as? FlutterViewController,
      let appDelegate = UIApplication.shared.delegate as? AppDelegate
    else {
      return
    }

    let tabBarController = QingxuTabBarController(
      flutterViewController: flutterViewController,
      navigationBridge: appDelegate.navigationBridge
    )
    appDelegate.navigationBridge.install(tabBarController: tabBarController)
    window?.rootViewController = tabBarController
    window?.makeKeyAndVisible()
  }
}

/// Uses Apple's standard tab bar on every supported iOS version.
///
/// When built with the iOS 26 SDK, UIKit automatically gives this tab bar the
/// native Liquid Glass appearance. Earlier systems keep their standard native
/// tab bar, without a custom blur or a hand-drawn glass imitation.
final class QingxuTabBarController: UITabBarController, UITabBarControllerDelegate {
  private let flutterViewController: FlutterViewController
  private let navigationBridge: NativeNavigationBridge
  private let tabs = QingxuTab.allCases

  init(
    flutterViewController: FlutterViewController,
    navigationBridge: NativeNavigationBridge
  ) {
    self.flutterViewController = flutterViewController
    self.navigationBridge = navigationBridge
    super.init(nibName: nil, bundle: nil)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    delegate = self
    tabBar.tintColor = UIColor(red: 0.91, green: 0.72, blue: 0.25, alpha: 1)

    viewControllers = tabs.map { tab in
      let controller = FlutterTabContentController()
      controller.tabBarItem = UITabBarItem(
        title: tab.title,
        image: UIImage(systemName: tab.systemImage),
        selectedImage: UIImage(systemName: "\(tab.systemImage).fill")
          ?? UIImage(systemName: tab.systemImage)
      )
      return controller
    }

    select(.today)
  }

  func select(_ tab: QingxuTab) {
    loadViewIfNeeded()
    guard
      let index = tabs.firstIndex(of: tab),
      let contentController = viewControllers?[index] as? FlutterTabContentController
    else {
      return
    }

    selectedIndex = index
    contentController.embed(flutterViewController)
  }

  func tabBarController(
    _ tabBarController: UITabBarController,
    didSelect viewController: UIViewController
  ) {
    guard
      let index = viewControllers?.firstIndex(where: { $0 === viewController }),
      let contentController = viewController as? FlutterTabContentController
    else {
      return
    }

    contentController.embed(flutterViewController)
    navigationBridge.userSelected(tabs[index])
  }
}

private final class FlutterTabContentController: UIViewController {
  private weak var embeddedViewController: FlutterViewController?
  private var embeddedConstraints: [NSLayoutConstraint] = []

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .systemBackground
  }

  func embed(_ flutterViewController: FlutterViewController) {
    guard embeddedViewController !== flutterViewController else { return }

    if let currentHost = flutterViewController.parent as? FlutterTabContentController {
      currentHost.detach(flutterViewController)
    } else if flutterViewController.parent != nil {
      flutterViewController.willMove(toParent: nil)
      flutterViewController.view.removeFromSuperview()
      flutterViewController.removeFromParent()
    } else {
      flutterViewController.view.removeFromSuperview()
    }

    addChild(flutterViewController)
    flutterViewController.view.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(flutterViewController.view)
    embeddedConstraints = [
      flutterViewController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      flutterViewController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      flutterViewController.view.topAnchor.constraint(equalTo: view.topAnchor),
      flutterViewController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
    ]
    NSLayoutConstraint.activate(embeddedConstraints)
    flutterViewController.didMove(toParent: self)
    embeddedViewController = flutterViewController
  }

  private func detach(_ flutterViewController: FlutterViewController) {
    guard embeddedViewController === flutterViewController else { return }

    flutterViewController.willMove(toParent: nil)
    NSLayoutConstraint.deactivate(embeddedConstraints)
    embeddedConstraints.removeAll()
    flutterViewController.view.removeFromSuperview()
    flutterViewController.removeFromParent()
    embeddedViewController = nil
  }
}
