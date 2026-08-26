// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Lithium",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "Lithium",
            path: "Sources/Lithium"
        )
    ]
)
