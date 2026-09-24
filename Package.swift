// swift-tools-version: 6.2
import PackageDescription

let package = Package(name: "Magnetite", platforms: [.macOS(.v26)],
                      targets: [.target(name: "MagnetiteCore"), .executableTarget(name: "Magnetite", dependencies: ["MagnetiteCore"])], swiftLanguageModes: [.v5])
