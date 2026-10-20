import Flutter
import Network
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  // App photos (HERO_IMAGES_REMOTE): Low Data Mode and free storage, asked
  // before downloading.
  private let pathMonitor = NWPathMonitor()
  // Starts as true (no downloads) until NWPathMonitor delivers its first
  // path, a moment after launch. If the app's first check (right after the
  // first frame) comes before that, it skips downloading this time and tries
  // again later (sign-in, a resume after 6 hours, the next launch). A known,
  // harmless race that errs on the side of saving data.
  private var lowDataMode = true

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    registerDeviceDataChannel()
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  private func registerDeviceDataChannel() {
    pathMonitor.pathUpdateHandler = { [weak self] path in
      let constrained = path.isConstrained
      DispatchQueue.main.async { self?.lowDataMode = constrained }
    }
    pathMonitor.start(queue: DispatchQueue(label: "fitflex.device_data"))
    guard let registrar = self.registrar(forPlugin: "FitFlexDeviceData") else { return }
    let channel = FlutterMethodChannel(
      name: "fitflex/device_data", binaryMessenger: registrar.messenger())
    channel.setMethodCallHandler { [weak self] call, result in
      switch call.method {
      case "reducedData":
        result(self?.lowDataMode ?? true)
      case "freeBytes":
        result(AppDelegate.freeBytes())
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private static func freeBytes() -> Int64? {
    let url = URL(fileURLWithPath: NSHomeDirectory())
    guard
      let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
      let free = values.volumeAvailableCapacityForImportantUsage
    else { return nil }
    return free
  }
}
