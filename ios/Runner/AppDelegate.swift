import Flutter
import UIKit

// Deliberately using the classic FlutterAppDelegate lifecycle rather
// than the newer UIScene-based one (default in `flutter create` output
// since Flutter 3.41) — the classic pattern has been stable for years
// and is still fully supported; the UIScene migration was actively
// rolling out at the time this file was written, which made it the
// riskier choice to hand-write without Xcode to verify against.
@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
