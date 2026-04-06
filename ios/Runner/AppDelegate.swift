import FirebaseCore
import Flutter
import UIKit

/// Ensures `FirebaseApp.configure()` runs before any Firebase code (including +load /
/// plugin registration). `didFinishLaunching` is too late for some SDK paths on newer iOS.
@inline(__always)
private func configureFirebaseIfNeeded() {
  if FirebaseApp.app() == nil {
    FirebaseApp.configure()
  }
}

@main
@objc class AppDelegate: FlutterAppDelegate {
  override init() {
    super.init()
    configureFirebaseIfNeeded()
  }

  override func application(
    _ application: UIApplication,
    willFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
  ) -> Bool {
    configureFirebaseIfNeeded()
    return super.application(application, willFinishLaunchingWithOptions: launchOptions)
  }

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    configureFirebaseIfNeeded()
    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
