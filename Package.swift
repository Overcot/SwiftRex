// swift-tools-version:5.2
import PackageDescription

let package = Package(
    name: "SwiftRex",
    platforms: [.iOS(.v13), .macOS(.v10_15), .tvOS(.v13), .watchOS(.v6)],
    products: [
        .library(name: "CombineRex", targets: ["SwiftRex", "CombineRex"]),
        .library(name: "CombineRexDynamic", type: .dynamic, targets: ["SwiftRex", "CombineRex"]),
    ],
    dependencies: [
    ],
    targets: [
        .target(name: "SwiftRex", exclude: ["CodeGeneration/Templates"]),
        .target(name: "CombineRex", dependencies: ["SwiftRex"]),

        .testTarget(name: "SwiftRexTests", dependencies: ["SwiftRex"]),
        .testTarget(name: "CombineRexTests", dependencies: ["CombineRex"]),
    ],
    swiftLanguageVersions: [.v5]
)
