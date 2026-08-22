import Flutter
import UIKit

enum QingxuTab: String, CaseIterable, Hashable {
  case inbox
  case today
  case upcoming
  case anytime
  case logbook

  var title: String {
    switch self {
    case .inbox: return "收集箱"
    case .today: return "今天"
    case .upcoming: return "计划"
    case .anytime: return "随时"
    case .logbook: return "日志"
    }
  }

  var systemImage: String {
    switch self {
    case .inbox: return "tray"
    case .today: return "sun.max"
    case .upcoming: return "calendar"
    case .anytime: return "circle"
    case .logbook: return "checkmark.circle"
    }
  }
}

final class NativeNavigationBridge {
  private var channel: FlutterMethodChannel?
  private weak var tabBarController: QingxuTabBarController?
  private var selectedTab = QingxuTab.today

  func connect(to messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(
      name: "one.darker.qingxu/navigation",
      binaryMessenger: messenger
    )
    channel.setMethodCallHandler { [weak self] call, result in
      guard call.method == "setSelectedTab" else {
        result(FlutterMethodNotImplemented)
        return
      }
      guard
        let rawValue = call.arguments as? String,
        let tab = QingxuTab(rawValue: rawValue)
      else {
        result(
          FlutterError(
            code: "invalid_tab",
            message: "Flutter requested an unsupported native tab.",
            details: call.arguments
          )
        )
        return
      }

      DispatchQueue.main.async {
        self?.selectedTab = tab
        self?.tabBarController?.select(tab)
      }
      result(nil)
    }
    self.channel = channel
  }

  func install(tabBarController: QingxuTabBarController) {
    self.tabBarController = tabBarController
    tabBarController.select(selectedTab)
  }

  func userSelected(_ tab: QingxuTab) {
    selectedTab = tab
    channel?.invokeMethod("selectTab", arguments: tab.rawValue)
  }
}

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  let navigationBridge = NativeNavigationBridge()

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    navigationBridge.connect(to: engineBridge.applicationRegistrar.messenger())
  }
}
