// swift-tools-version:5.1
import PackageDescription

let pkg = Package(name: "converter")

pkg.products = [
    .executable(name: "converter", targets: ["converter"])
]
pkg.dependencies = [
    .package(url: "https://github.com/apple/swift-argument-parser.git", Version(0,0,0)...Version(1_000_000,0,0))
]
pkg.targets = [
    .target(
        name: "converter",
        dependencies: [.product(name: "ArgumentParser", package: "swift-argument-parser")],
        path: ".",
        exclude: ["deps.json"],
        sources: ["main.swift"]
    )
]

#if swift(>=5) && os(macOS)
pkg.platforms = [
    .macOS("11.5")
]
#endif
