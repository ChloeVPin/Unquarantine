// swift-tools-version: 6.4

import PackageDescription

let package = Package(
    name: "Unquarantine",
    platforms: [
        .macOS(.v27)
    ],
    targets: [
        .executableTarget(
            name: "Unquarantine",
            path: "Sources/Unquarantine",
            exclude: ["Resources/unq.icon"]
        ),
        .executableTarget(
            name: "UnquarantineWatcher",
            path: "Sources/UnquarantineWatcher"
        )
    ],
    swiftLanguageModes: [.v5]
)
