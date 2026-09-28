// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "UIBoard",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "UIBoardCore"),
        .executableTarget(name: "UIBoard", dependencies: ["UIBoardCore"]),
        .testTarget(name: "UIBoardCoreTests", dependencies: ["UIBoardCore"], resources: [.copy("Fixtures")]),
    ]
)
