// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MotoMirror",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "MotoMirrorCore", targets: ["MotoMirrorCore"]),
        .executable(name: "MotoMirror", targets: ["MotoMirror"]),
        .executable(name: "motomirrorctl", targets: ["MotoMirrorCLI"])
    ],
    targets: [
        .target(name: "MotoMirrorCore"),
        .executableTarget(name: "MotoMirror", dependencies: ["MotoMirrorCore"]),
        .executableTarget(name: "MotoMirrorCLI", dependencies: ["MotoMirrorCore"]),
        .testTarget(name: "MotoMirrorCoreTests", dependencies: ["MotoMirrorCore"])
    ]
)
