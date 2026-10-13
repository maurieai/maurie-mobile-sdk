// swift-tools-version:5.9
// The manifest Xcode reads when an app adds this repository as a package (Swift Package Manager only looks at the
// root). The sources are the iOS SDK in ios/; ios/Package.swift is the same package with its tests, for development.
import PackageDescription

let package = Package(
    name: "MaurieChat",
    platforms: [.iOS(.v15)],
    products: [
        .library(name: "MaurieChat", targets: ["MaurieChat"]),
    ],
    targets: [
        .target(name: "MaurieChat", path: "ios/Sources/MaurieChat"),
    ]
)
