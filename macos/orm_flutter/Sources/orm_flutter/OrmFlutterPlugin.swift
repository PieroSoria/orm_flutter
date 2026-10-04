import Cocoa
import FlutterMacOS

public class OrmFlutterPlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "orm_flutter/desktop", binaryMessenger: registrar.messenger)
    registrar.addMethodCallDelegate(OrmFlutterPlugin(), channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard call.method == "enginePaths" else { result(FlutterMethodNotImplemented); return }
    var paths: [String: String] = [:]
    #if SWIFT_PACKAGE
    let bundle = Bundle.module
    for engine in ["query-engine", "schema-engine"] {
      if let url = bundle.url(forResource: "prisma-\(engine)", withExtension: nil, subdirectory: "Engines") {
        paths[engine] = url.path
      }
    }
    #else
    let owner = Bundle(for: OrmFlutterPlugin.self)
    guard let bundleURL = owner.url(forResource: "orm_flutter_engines", withExtension: "bundle")
          ?? Bundle.main.url(forResource: "orm_flutter_engines", withExtension: "bundle"),
          let bundle = Bundle(url: bundleURL) else {
      result(FlutterError(code: "MISSING_ENGINES", message: "orm_flutter engine resource bundle is missing. Rebuild the macOS app.", details: nil))
      return
    }
    for engine in ["query-engine", "schema-engine"] {
      if let url = bundle.url(forResource: "prisma-\(engine)", withExtension: nil) { paths[engine] = url.path }
    }
    #endif
    result(paths)
  }
}
