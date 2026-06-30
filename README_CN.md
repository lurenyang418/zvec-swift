# Zvec Swift

简体中文 | [English](README.md)

[Alibaba Zvec](https://github.com/alibaba/zvec) 的安全、符合 Swift 习惯的 Swift 6.1 桥接。

> 状态：当前按 Zvec v0.5.1 开发；首个正式 tag 发布前，公开 API 尚不稳定。

## 能力

- 以 Swift 值类型和 typed throws 封装完整 Zvec C API。
- 支持稠密/稀疏向量、标量、数组、全文检索及混合检索。
- Apple 平台支持 HNSW、IVF、Flat、倒排与 FTS 索引。
- 同时提供同步与 Swift Concurrency API，并安全管理 Collection 生命周期。
- 通过预编译 `CZvec.xcframework` 由 SwiftPM 分发，使用者无需安装 CMake。

## 环境

- Swift 6.1 / Xcode 16.4+
- Apple Silicon macOS 13+
- arm64 iOS 16+ 真机或 Apple Silicon 模拟器

上游仅在 Linux x86_64 启用 DiskANN/Vamana；Swift API 保留相应类型，但 Apple 平台会明确返回不支持错误。

## 安装

```swift
.package(url: "https://github.com/lurenyang418/zvec-swift.git", from: "0.5.1")
```

快速示例和开发命令参见 [英文 README](README.md)，完整设计约束参见 [plan.md](plan.md)，贡献流程参见 [CONTRIBUTING.md](CONTRIBUTING.md)。

## 相关链接

- [Zvec 官方仓库](https://github.com/alibaba/zvec)
- [Zvec 文档](https://zvec.org/en/docs/)
- [Zvec API Reference](https://zvec.org/api-reference/)
- [本项目 Issues](https://github.com/lurenyang418/zvec-swift/issues)
- [安全策略](SECURITY.md)

## 许可证

Apache License 2.0。详见 [LICENSE](LICENSE) 与 [NOTICE](NOTICE)。

