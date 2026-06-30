# Zvec Swift v0.5.1 完整桥接

## Summary

- 在空仓库中创建 SwiftPM 包，面向 Swift 6.1、iOS 16+、macOS 13+，支持 Apple ARM64 真机、模拟器和 Apple Silicon Mac。
- 绑定上游 `alibaba/zvec` v0.5.1（固定 commit `d25f3a45523bb11fece05f88ca373216c3fc5f78`），采用 `CZvec` 原始 C 模块 + `Zvec` 类型安全高层 API 两层结构。
- 通过预编译动态 `CZvec.xcframework` 分发；完整覆盖配置、Schema、全部字段类型、索引、CRUD、Schema 演进、向量/全文/分组/多路混合查询、统计与生命周期。
- 设计依据为上游 [v0.5.1 C API](https://github.com/alibaba/zvec/blob/v0.5.1/src/include/zvec/c_api.h)、[官方数据操作文档](https://zvec.org/en/docs/data-operations/)及官方 Rust 绑定采用的 RAII、强类型错误和分层 FFI 模式。[官方 Rust SDK](https://github.com/zvec-ai/zvec-rust)

## Public API

- `ZvecRuntime`
  - 同步及异步 `initialize(configuration:)`、`shutdown()`。
  - `version`、`isInitialized`、`capabilities`。
  - 初始化前校验原生库至少为 0.5.1；全局配置只允许首次初始化时设置，符合上游“一次初始化、不可运行时重配”的要求。[配置文档](https://zvec.org/en/docs/config/)
- 值类型、全部 `Sendable`：
  - `Configuration`、`LogConfiguration`、`CollectionOptions`。
  - `DataType`、`Metric`、`Quantization`、`IndexConfiguration`。
  - `FieldSchema`、`CollectionSchema`、`CollectionStatistics`。
  - `Document`、`ZvecValue`、`SparseVector`、`WriteSummary`、`DocumentWriteResult`。
  - `VectorQuery`、`GroupByVectorQuery`、`FullTextQuery`、`MultiQuery`、`SubQuery`、`Reranker`及各索引查询参数。
- `ZvecValue` 明确区分：
  - 标量、字符串、`Data`。
  - FP16/FP32/FP64、Int4/Int8/Int16、二进制密集向量。
  - FP16/FP32 稀疏向量。
  - 所有数组类型和显式 `.null`；字段缺失与字段为 null 保持不同语义。
- Schema 同时提供常规构造器和 result-builder DSL：

  ```swift
  let schema = try CollectionSchema("demo") {
      VectorField("embedding", type: .float32, dimensions: 4,
                  index: .hnsw(metric: .cosine))
      Field("title", type: .string,
            index: .fullText(tokenizer: .standard))
  }
  ```

- `Collection` 为线程安全、RAII 管理的 `final class`：
  - `create(at:schema:options:)`、`open(at:options:)`、幂等 `close()`。
  - CRUD、详细逐条写入结果、按过滤器删除、fetch。
  - create/drop index、add/drop/alter column、flush、optimize、stats、schema/options 查询。
  - 普通向量、group-by、FTS、多路 RRF/weighted 查询。
  - 每项原生数据库操作均提供同名同步和 `async` 重载。
- 所有高层失败使用 Swift 6 typed throws：`throws(ZvecError)`。
  - 保留原生错误码、消息、源文件、函数及行号。
  - 增加 Swift 侧 `.closed`、`.cancelled`、`.incompatibleNativeVersion`。
  - 未知原生枚举值使用 `.unknown(rawValue:)` 保持前向兼容。
- `CZvec` 保持公开，供高级使用者访问完整原始 C API；高层 API 不暴露 malloc、裸指针或手动 destroy。

## Implementation Changes

- SwiftPM 结构：
  - `Package.swift` 定义二进制目标 `CZvec`、库目标 `Zvec`、测试和示例。
  - `Sources/Zvec` 包含值模型、C 编解码、资源句柄、Collection、查询、并发及错误映射。
  - Jieba 的两个字典文件作为 SwiftPM resources 随包分发，并在初始化前自动注册，保证中文 FTS 开箱可用。
- FFI 与资源安全：
  - 内部使用 noncopyable owned-handle 封装、`borrowing`/`consuming` 表达所有权转移，并在 `deinit` 中调用对应 destroy/free。
  - 公共 Schema、Document、Query 保持纯 Swift 值类型；每次调用临时转换为 C 对象，结果立即深拷贝回 Swift 后释放原生内存。
  - 集中实现字符串数组、字节缓冲区、稀疏向量及特殊数组编码，避免各 API 重复裸指针逻辑。
- 并发模型：
  - 每个 Collection 使用内部并发队列；只读查询可并行，写入、DDL、flush/optimize 和 close 使用 barrier。
  - 同步与异步入口复用同一底层实现，避免行为漂移和嵌套 `queue.sync` 死锁。
  - 异步操作在专用队列执行，不阻塞 Swift cooperative executor；取消在入队前和原生调用返回后检查。上游没有中止 API，因此已进入 C++ 的操作继续完成，结果被丢弃并返回 `.cancelled`。
  - `close()` 等待在途操作结束；关闭后所有调用稳定返回 `.closed`。
- XCFramework：
  - 构建 `ios-arm64`、`ios-arm64-simulator`、`macos-arm64` 三个动态 framework slice，统一模块名和 install name 为 `CZvec`。
  - 校正 framework `Info.plist`、module map、`@rpath/CZvec.framework/CZvec`，再用 `xcodebuild -create-xcframework` 合并。
  - Apple 平台保留 HNSW、IVF、Flat、Invert、FTS；公开 Vamana/DiskANN 类型以保持 v0.5.1 API 完整，但在 Apple 上明确抛出 `.notSupported`，因为上游仅在 Linux x86_64 启用 DiskANN。
- 发布采用两阶段流程，消除 SwiftPM checksum 循环依赖：
  1. 固定上游 commit 构建并发布 `native-v0.5.1` Release，资产为 `CZvec.xcframework.zip`。
  2. 计算 `swift package compute-checksum`，写入 `Package.swift`，URL 固定为 `https://github.com/lurenyang418/zvec-swift/releases/download/native-v0.5.1/CZvec.xcframework.zip`。
  3. 验证远程依赖后发布 Swift 包 tag `v0.5.1`。
- CI 检查 SwiftFormat/SwiftLint 只读模式、Swift 6 严格并发、构建、单元/集成测试、DocC、二进制 ABI 和示例 App。保留 Apache-2.0 LICENSE、NOTICE 及第三方声明。

## Test Plan

- 编解码单元测试覆盖每种 `ZvecValue`、空值、空数组、UTF-8、嵌入 NUL 的二进制、FP16、Int4 奇偶维度、稀疏索引和值数量不匹配。
- 集成测试覆盖初始化/关闭、Schema DSL 与普通构造器、创建/重开 collection、全部 CRUD、逐文档错误、filter delete、fetch、flush、optimize、统计和 Schema 演进。
- 查询测试覆盖 HNSW/IVF/Flat 参数、过滤、输出字段、include-vector、半径搜索、FTS、中文 Jieba、group-by、稠密/稀疏 MultiQuery、RRF 和 weighted rerank。
- 生命周期测试覆盖重复 close、关闭后调用、初始化版本不兼容、原生错误详情、临时 C 对象释放以及 Document 序列化/反序列化。
- 并发压力测试使用 `TaskGroup` 并行查询、写入与 close；运行 Thread Sanitizer 检查 Swift 侧竞态和 use-after-free。
- XCFramework 验证每个 slice 的架构、平台标记、导出 C 符号、install name、module import、签名兼容性；分别构建并运行 macOS CLI、iOS 模拟器测试 App，并执行 iOS 真机无签名 archive smoke test。
- Release CI 从公开 URL 创建一个全新临时 Swift 包，仅依赖发布版本，验证 checksum、下载、链接和最小插入查询流程。

## Assumptions

- Swift SDK 与上游版本同步，首个公开版本为 `v0.5.1`；原生资产 tag 为 `native-v0.5.1`。
- 第一版仅支持 Apple ARM64，不承诺 Intel Mac、x86_64 模拟器或 Linux Swift。
- 过滤条件沿用上游字符串表达式，不在 v0.5.1 发明额外 Swift 查询 DSL。
- “完整 v0.5.1”指完整公开数据库能力和全部数据类型；冗余的 C 内存管理辅助函数通过 `CZvec` 暴露，但不复制成高层 Swift API。
