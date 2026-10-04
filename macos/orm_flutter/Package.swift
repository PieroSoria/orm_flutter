// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "orm_flutter",
    platforms: [.macOS("12.0")],
    products: [.library(name: "orm-flutter", targets: ["orm_flutter"])],
    dependencies: [.package(name: "FlutterFramework", path: "../FlutterFramework")],
    targets: [
        .target(
            name: "orm_flutter",
            dependencies: [.product(name: "FlutterFramework", package: "FlutterFramework")],
            resources: [.copy("Engines")]
        )
    ]
)
