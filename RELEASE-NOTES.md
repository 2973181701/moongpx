# v0.1.0 — moongpx 首个公开版本

MoonBit 的 GPX（GPS Exchange Format）规范实现：解析、校验、序列化、版本迁移、轨迹统计。

## 安装

```bash
moon add 2973181701/moongpx
```

- 包主页：<https://mooncakes.io/package/2973181701/moongpx>
- 许可证：Apache-2.0
- 唯一依赖：`Milky2018/xml@0.4.1`（同为 Apache-2.0），仅作 XML 词法层

## 这个版本有什么

**解析与序列化**

- `parse_gpx` / `to_gpx` —— 文本 ↔ 结构体，往返一致性由测试锁定
- 完整数据模型：`gpx` / `metadata` / `wpt` / `rte` / `trk` / `trkseg` / `trkpt` / `link` / `person` / `email` / `copyright` / `bounds` / `extensions`
- `wptType` 全部 19 个可选子元素（外加 `lat`/`lon` 两个必填属性）
- `extensions` 原样保留，不丢失私有扩展

**校验**

- `validate_gpx` / `is_valid_gpx` / `has_schema_errors` —— 独立于解析的校验入口
- 24 个诊断码（17 个 error + 7 个 warning），全部带**行号与列号**
- 覆盖：元素顺序（schema 的 `<xsd:sequence>`）、坐标范围（含经度 `-180 ≤ lon < 180` 的排他上界）、
  `fix` 枚举、`dgpsid` 0–1023、`xsd:decimal` 不接受指数记法、必填属性

**GPX 1.0 → 1.1**

- `detect_gpx_version` / `parse_gpx_1_0` / `parse_gpx_any`
- 自动处理：`<url>`+`<urlname>` → `<link>`、`<email>` 整串拆成 `id`/`domain`、
  `<course>`/`<speed>` 转存 `extensions`、根级元数据收进 `<metadata>`

**轨迹统计**

- `track_stats` —— 点数、距离（半正矢）、累计爬升/下降（带 3 m 噪声阈值）、包围盒、起止时间与时长
- 两个已写进 README 的约定：跨 `trkseg` 不相连；爬升必须带阈值（否则 GPS 噪声会被放大成几百米假爬升）

## 测试

`moon test` **167 / 167**，两类来源：

| 来源 | 用例数 | 作用 |
|---|---|---|
| 依据规范手工构造 | 163 | 逐条覆盖 schema 约束的边界值与非法值 |
| 真实软件导出的文件 | 4 | 验证「真实世界的文件能不能用」 |

真实样本取自 Runkeeper App 与 GPSBabel 的导出文件（Apache-2.0，来源见 `testdata/SOURCES.md`）。
其中一份 GPSBabel 文件把 `<time>` 写在了 `<sym>` 之后，违反 `wpt` 的子元素顺序——
本库明确报 `E1013` 拒绝，而非静默接受后给出错误结果。

`--target js` 与 `--target wasm-gc` 均构建通过；每次 push 由 GitHub Actions 自动跑
`moon check` / `moon fmt --check` / `moon test` / `moon run cmd/main`。

## 已知限制

- **不支持带命名空间前缀的元素名**：`<g:gpx xmlns:g="...">` 会被判为"根元素不是 `<gpx>`"。
  默认命名空间（`xmlns="..."`）不受影响，这是真实文件的绝大多数写法
- **1.0 → 1.1 是单向的**：反向会丢 `extensions` 与 `fix`/`sat` 等精度字段，本库不提供
- 不做坐标系转换（WGS84 → GCJ-02 / BD-09）——那是坐标系规范，不是 GPX 规范
- 不做地图渲染、不涉及 FIT / TCX / KML
- 不联网、不读写文件，文本由调用方传入
- 底层 XML 库是 document-buffered，超大文件（>100 MB）会整体载入内存

## 与上一版的差异

首个公开版本。

---

## 本地运行

```bash
moon test           # 167 个测试
moon run cmd/main   # 11 段演示
```
