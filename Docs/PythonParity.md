# Python v0.5.1 capability parity

This matrix compares `zvec-swift` with the public database API in Alibaba Zvec's Python binding at v0.5.1. It is a capability guide, not a promise to reproduce Python naming or Python-specific runtime behavior.

| Area | Python v0.5.1 | zvec-swift | Status / boundary |
| --- | --- | --- | --- |
| Runtime initialize/shutdown/version | Yes | `ZvecRuntime`, `ZvecVersion` | Supported |
| Runtime configuration getter | No reliable native getter | Not exposed | Native state cannot be reconstructed safely |
| Scalar, array and dense-vector types | Yes | All public C data types | Supported |
| Sparse FP16/FP32 document values | Yes | Yes | Supported |
| Collection create/open/close/destroy | Yes | Sync and async | Supported |
| Collection path and closed state | `path`, `is_closed` | `location`, `isClosed` | Supported |
| Schema/options/statistics | Yes | Yes | Supported |
| Flush and optimize | Yes | Yes | Supported |
| Insert/update/upsert/delete | Single and batch | Single and batch, summary and detailed results | Supported |
| Fetch | Single/list input, missing IDs omitted | Single, batch, and ordered `fetchResults` | Supported |
| Delete by filter | Yes | Yes | Supported |
| Filter-only query | Query without vector/FTS | `browse` | Supported; bounded result, not a cursor |
| Dense vector query | Yes | `VectorQuery` | Supported |
| Query using an existing document ID | Yes | `VectorQuery(documentID:)` | Supported for dense-vector fields |
| Sparse vector query | FP16/FP32 | Float32 `SubQuery` | Partial; current C API only exposes Float32 sparse subquery payloads |
| FTS natural-language match | `match_string` | `.match` | Supported |
| FTS advanced expression | `query_string` | `.query` | Supported |
| Multi-query | Yes | `MultiQuery` | Supported |
| RRF/weighted rerank | Native fast path | `Reranker` | Supported |
| Python model/callback reranker | Python extension | No direct class parity | Language-layer extension; a future Swift protocol must not bind the core package to an ML framework |
| Group-by vector query | Native API | `GroupByVectorQuery` | Supported through the narrow Apple shim |
| Add/alter/drop column | Yes | Yes | Supported |
| Create/drop index | Yes | Yes | Supported indexes listed below |
| Per-operation DDL/index/optimize options | Python C++ binding | Not exposed | Current public C API does not carry these option objects |
| HNSW | Yes | Yes | Supported |
| IVF | Yes | Yes | Supported |
| Flat | Yes | Yes | Supported |
| Inverted / FTS indexes | Yes | Yes | Supported |
| HNSW RabitQ | Python C++ binding | Not exposed | Missing from the v0.5.1 public C index enum |
| Vamana / DiskANN | Linux x86_64 | API type only | Not supported on Apple by upstream v0.5.1 |
| Indexed sparse vectors | Platform dependent | Rejected on Apple | Upstream v0.5.1 can abort while creating these indexes on Apple; brute-force sparse query remains available |
| Embedding providers/models | `python/zvec/extension` | Not included | Explicitly out of scope for the general database package |

## Design rules

- A missing native feature is reported as unsupported; the Swift layer does not emulate transactions, cursor pagination, index algorithms, or native options.
- `browse` uses the native scalar-only search path. Its `limitReached` value means more documents may exist; result order and continuation are not guaranteed.
- Query-by-ID fetches and resolves the source vector inside one Collection read operation. Sparse query-by-ID remains unavailable until the C API can encode the corresponding payload safely.
- Embedding support, if built later, belongs in a separate package that depends on `Zvec`.
