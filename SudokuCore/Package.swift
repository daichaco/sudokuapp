// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SudokuCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "SudokuCore", targets: ["SudokuCore"])],
    targets: [
        .target(
            name: "SudokuCore",
            // 画像認識は Debug ビルドだと極端に遅い(テンプレート照合)ので、Debug でも最適化する
            swiftSettings: [.unsafeFlags(["-O"], .when(configuration: .debug))]
        ),
        .testTarget(name: "SudokuCoreTests", dependencies: ["SudokuCore"]),
    ],
    swiftLanguageModes: [.v5]
)
