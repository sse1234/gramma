import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "gramma.icloud")!
    let channel = FlutterMethodChannel(
      name: "gramma/icloud", binaryMessenger: registrar.messenger())
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "containerPath":
        // The ubiquity container of ADR 0014's Apple transport; resolving
        // it may touch the network, so never on the main thread.
        DispatchQueue.global(qos: .userInitiated).async {
          let url = FileManager.default
            .url(forUbiquityContainerIdentifier: nil)?
            .appendingPathComponent("Documents")
          if let url = url {
            try? FileManager.default.createDirectory(
              at: url, withIntermediateDirectories: true)
          }
          DispatchQueue.main.async { result(url?.path) }
        }
      case "prepare":
        // Foreign op-logs may sit as undownloaded ".icloud" placeholders;
        // ask the system for them and wait briefly so the Rust engine
        // reads real files.
        let path = call.arguments as? String ?? ""
        DispatchQueue.global(qos: .userInitiated).async {
          let fm = FileManager.default
          let root = URL(fileURLWithPath: path)
          func placeholders() -> [URL] {
            guard
              let entries = fm.enumerator(
                at: root, includingPropertiesForKeys: nil)
            else { return [] }
            return entries.compactMap { $0 as? URL }
              .filter { $0.lastPathComponent.hasSuffix(".icloud") }
          }
          for url in placeholders() {
            try? fm.startDownloadingUbiquitousItem(at: url)
          }
          for _ in 0..<30 {
            if placeholders().isEmpty { break }
            Thread.sleep(forTimeInterval: 0.1)
          }
          DispatchQueue.main.async { result(true) }
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }
}
