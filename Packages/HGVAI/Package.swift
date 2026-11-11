// swift-tools-version: 6.2
import PackageDescription

/// On-device AI for HGV Hours: a small open model (Qwen) run with Apple's MLX on the iPhone's GPU.
/// Wrapped here so the app only sees a tiny API and the MLX packages stay in one place.
let package = Package(
    name: "HGVAI",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "HGVAI", targets: ["HGVAI"])],
    dependencies: [
        .package(url: "https://github.com/ml-explore/mlx-swift-lm", .upToNextMinor(from: "3.32.3"), traits: []),
        .package(url: "https://github.com/huggingface/swift-huggingface", from: "0.9.0"),
        .package(url: "https://github.com/huggingface/swift-transformers", from: "1.3.0"),
    ],
    targets: [
        .target(name: "HGVAI", dependencies: [
            .product(name: "MLXLLM", package: "mlx-swift-lm"),
            .product(name: "MLXLMCommon", package: "mlx-swift-lm"),
            .product(name: "MLXHuggingFace", package: "mlx-swift-lm"),
            .product(name: "HuggingFace", package: "swift-huggingface"),
            .product(name: "Tokenizers", package: "swift-transformers"),
        ]),
        .testTarget(name: "HGVAITests", dependencies: ["HGVAI"]),
    ]
)
