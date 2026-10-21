// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Yap",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Yap", targets: ["Yap"]),
    ],
    targets: [
        // Pure, testable logic: voice detection, turn tracking, nudge policy.
        .target(name: "YapCore"),
        // The menu bar app: audio capture, meeting detection, UI.
        .executableTarget(name: "Yap", dependencies: ["YapCore"]),
        .testTarget(name: "YapCoreTests", dependencies: ["YapCore"]),
    ]
)
