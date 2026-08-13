// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "LangKeys",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "LangKeys", path: "Sources/LangKeys")
    ]
)
