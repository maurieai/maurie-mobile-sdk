// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MaurieChat",
    platforms: [.iOS(.v15)],
    products: [
        .library(name: "MaurieChat", targets: ["MaurieChat"]),
    ],
    targets: [
        .target(name: "MaurieChat", path: "Sources/MaurieChat"),
        .testTarget(name: "MaurieChatTests", dependencies: ["MaurieChat"], path: "Tests/MaurieChatTests"),
    ]
)
