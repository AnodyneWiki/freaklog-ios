// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "FreakLogCore",
    defaultLocalization: "en",
    platforms: [.iOS(.v16), .watchOS(.v10)],
    products: [
        .library(name: "FreakLogCore", targets: ["FreakLogCore"]),
    ],
    targets: [
        .target(
            name: "FreakLogCore",
            resources: [
                .process("Resources"),
            ]
        ),
        .testTarget(
            name: "FreakLogCoreTests",
            dependencies: ["FreakLogCore"]
        ),
    ]
)
