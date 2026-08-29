import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)
    let messenger = flutterViewController.engine.binaryMessenger
    registerICloudChannel(messenger: messenger)
    registerBookmarkChannel(messenger: messenger)

    super.awakeFromNib()
  }
}

/// The ubiquity container of ADR 0014's Apple transport. Under the App
/// Store sandbox (ADR 0027) the container must come from FileManager —
/// the Mobile Documents path of the unsandboxed era is out of reach.
private func registerICloudChannel(messenger: FlutterBinaryMessenger) {
  let channel = FlutterMethodChannel(
    name: "gramma/icloud", binaryMessenger: messenger)
  channel.setMethodCallHandler { call, result in
    switch call.method {
    case "containerPath":
      // Resolving may touch the network; never on the main thread.
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

/// Security-scoped bookmarks (ADR 0027): the sandbox grants access to a
/// user-picked sync folder only for the session; a bookmark carries the
/// grant across launches. Access, once started, is held for the app's
/// lifetime — the sync engine reads and writes the folder throughout.
private func registerBookmarkChannel(messenger: FlutterBinaryMessenger) {
  let channel = FlutterMethodChannel(
    name: "gramma/bookmarks", binaryMessenger: messenger)
  channel.setMethodCallHandler { call, result in
    switch call.method {
    case "create":
      let path = call.arguments as? String ?? ""
      do {
        let data = try URL(fileURLWithPath: path).bookmarkData(
          options: .withSecurityScope,
          includingResourceValuesForKeys: nil, relativeTo: nil)
        result(data.base64EncodedString())
      } catch {
        result(nil)
      }
    case "resolve":
      let encoded = call.arguments as? String ?? ""
      guard let data = Data(base64Encoded: encoded) else {
        result(nil)
        return
      }
      var stale = false
      guard
        let url = try? URL(
          resolvingBookmarkData: data, options: .withSecurityScope,
          relativeTo: nil, bookmarkDataIsStale: &stale),
        url.startAccessingSecurityScopedResource()
      else {
        result(nil)
        return
      }
      var reply: [String: String] = ["path": url.path]
      if stale,
        let fresh = try? url.bookmarkData(
          options: .withSecurityScope,
          includingResourceValuesForKeys: nil, relativeTo: nil)
      {
        reply["bookmark"] = fresh.base64EncodedString()
      }
      result(reply)
    default:
      result(FlutterMethodNotImplemented)
    }
  }
}
