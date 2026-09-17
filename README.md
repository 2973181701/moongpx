# moongpx

> MoonBit 的 GPX（GPS Exchange Format）规范实现：解析、校验、序列化、版本迁移。

GPX 是 GPS 轨迹的**通用交换格式**。Strava、Garmin（佳明）、两步路、咕咚、高德、
各类户外运动手表导出的轨迹文件，基本都是 GPX。

这个库让你能在 MoonBit 里**读、写、校验、转换**这些文件——严格按官方 XML Schema 实现，
纯函数，不联网、不读写文件。

---

## 状态

**v0.1.0 开发中**（D1–D4 已完成：坐标类型 + 完整模型 + 解析器）

| 模块 | 状态 |
|---|---|
| 坐标 / 数值类型（`latitudeType` / `longitudeType` / `degreesType` / `dgpsStationType`） | ✅ 已完成 |
| 根元素 + `metadata` + 子元素顺序校验 | ✅ 已完成 |
| `wpt` / `rte` / `trk` / `trkseg` 完整模型（含 `wptType` 全部 19 字段） | ✅ 已完成 |
| `extensions` 无损保留（原始 XML 切片） | ✅ 已完成 |
| 带行列号的诊断 | ✅ 已完成（解析阶段） |
| 序列化 + 往返一致性 | ⬜ 计划中 |
| 独立的 `validate_gpx`（只校验不建模） | ⬜ 计划中 |
| GPX 1.0 解析 + 1.0 ↔ 1.1 迁移 | ⬜ 计划中 |

### 已知限制（当前开发版）

- **尚无序列化**：只能解析，不能回写
- `parse_gpx` 返回 `Err` 时，成功解析的部分会被丢弃——完整的"只校验不中断"入口是计划中的 `validate_gpx`

---

## 为什么需要它

按规范正确处理 GPX，有一堆容易被忽略的坑：

| 坑 | 后果 |
|---|---|
| 根元素子元素**顺序被 schema 写死**（`metadata → wpt → rte → trk → extensions`） | 顺序错了就是非法文档，但多数解析器**不报错**，静默给出错误结果 |
| 经度上界是**排他的**（`-180 ≤ lon < 180`），纬度是**闭区间**（`-90 ≤ lat ≤ 90`） | 两端不对称：`lat="90"` 合法，`lon="180"` 非法 |
| `version` 是**固定值** `1.1` | 写 `1.10`、`1.1.0` 都非法 |
| `creator` 属性**必填** | 忘了就不合规 |
| `wpt`/`trkpt` 有 **19 个可选子元素且顺序固定** | 位置 → 描述 → 精度三段顺序错了静默失败 |
| `fix` 是枚举：`none`/`2d`/`3d`/`dgps`/`pps` | 写 `2D`（大写）非法 |
| `dgpsid` 范围 **0–1023** | 越界非法 |
| **GPX 1.0 与 1.1 不兼容** | 老设备导出的 1.0 文件用 1.1 解析器直接读不了 |

---

## 安装

```bash
moon add 2973181701/moongpx
```

---

## 快速上手

```moonbit
fn main {
  // 纬度：闭区间 [-90, 90]
  match @moongpx.Latitude::from_string("31.2304") {
    Ok(lat) => println(lat.to_gpx_string())   // "31.2304"
    Err(e) => println(e.message())
  }

  // 经度：半开区间 [-180, 180) —— 180 非法
  match @moongpx.Longitude::from_string("180") {
    Ok(_) => println("不应该到这里")
    Err(e) => println(e.message())
    // longitude out of range [-180, 180): 180
  }
}
```

---

## API

### 解析

```moonbit
parse_gpx(String) -> Result[Gpx, Array[Diagnostic]]
```

解析 GPX 文档。返回 `Ok(Gpx)` 表示结构完整且关键字段可用；
返回 `Err(诊断列表)` 表示存在无法继续的错误。

诊断**不抛异常**——一个文件里的多个问题会一次性全部报出来。

```moonbit
let src = "<gpx version=\"1.0\" creator=\"x\"><wpt lon=\"180\"/></gpx>"
match @moongpx.parse_gpx(src) {
  Ok(gpx) => println(gpx.creator)
  Err(diags) => println(@moongpx.format_diagnostics(diags))
}
// 1:6   error  E1003  version 必须是 "1.1"（schema 固定值），实际是 "1.0"
// 1:29  error  E1009  <wpt> 缺少必填属性 lat
```

### 数据模型

`Gpx` / `Metadata` / `Waypoint` / `Route` / `Track` / `TrackSegment` /
`Link` / `Person` / `Email` / `Copyright` / `Bounds`，
字段与官方 schema 一一对应。

`Waypoint` 覆盖 `wptType` 的全部 19 个字段（`ele` `time` `magvar` `geoidheight`
`name` `cmt` `desc` `src` `link` `sym` `type` `fix` `sat` `hdop` `vdop` `pdop`
`ageofdgpsdata` `dgpsid` `extensions`）。

### 诊断

```moonbit
pub(all) enum Severity { Error; Warning }

pub struct Diagnostic {
  severity : Severity
  code : String      // 稳定代码，如 "E1009"
  message : String
  line : Int         // 1-based
  column : Int       // 1-based
}

format_diagnostics(Array[Diagnostic]) -> String
has_errors(Array[Diagnostic]) -> Bool
```

诊断代码集中定义，便于测试断言与检索：

| 代码 | 含义 |
|---|---|
| `E1000` | XML 语法错误 |
| `E1001` | 根元素不是 `<gpx>` |
| `E1002` / `E1003` | `version` 缺失 / 不是 `"1.1"` |
| `E1004` | `creator` 缺失 |
| `E1005` / `E1006` | 根元素 / `metadata` 子元素顺序错误 |
| `E1007` | `metadata` 重复出现 |
| `E1009` | 缺少必填属性 |
| `E1010` / `E1011` | 非法 `xsd:dateTime` / `xsd:decimal` |
| `E1013` / `E1014` / `E1015` | `wpt` / `rte` / `trk` 子元素顺序错误 |
| `E1016` | `fix` 取值非法 |
| `W1001` | `bounds` 的 `min` 大于 `max`（不违反 schema，语义可疑） |

### 坐标类型

| 类型 | 区间 | 规范名 |
|---|---|---|
| `Latitude` | `[-90, 90]` 闭区间 | `latitudeType` |
| `Longitude` | `[-180, 180)` 半开 | `longitudeType` |
| `Degrees` | `[0, 360)` 半开 | `degreesType` |
| `DgpsStationId` | `[0, 1023]` 整数 | `dgpsStationType` |

每个类型都提供：

```moonbit
Latitude::from_string(String) -> Result[Latitude, GeoError]
Latitude::from_double(Double) -> Result[Latitude, GeoError]
Latitude::to_double(Self)     -> Double
Latitude::to_gpx_string(Self) -> String
```

### 数值工具

```moonbit
parse_decimal(String)   -> Result[Double, GeoError]   // 严格 xsd:decimal
format_decimal(Double)  -> String                     // 保证不含指数记法
```

### 错误

```moonbit
pub(all) enum GeoError {
  NotADecimal(String)
  LatitudeOutOfRange(String)
  LongitudeOutOfRange(String)
  DegreesOutOfRange(String)
  DgpsStationOutOfRange(String)
}

GeoError::message(Self) -> String
```

每个变体都携带**原始文本**，报错信息里能直接看到是哪个值出了问题。

---

## 设计取舍

### `xsd:decimal` 是严格的，不是「能解析成数字就行」

GPX 的坐标类型基于 `xsd:decimal`，它的词法形式是：

```text
(\+|-)? ( [0-9]+ (\.[0-9]*)? | \.[0-9]+ )
```

明确**不接受**指数记法（`1e2`）、`NaN`、`INF`——那些属于 `xsd:double`。
所以 `parse_decimal` 会拒绝它们，而不是丢给通用浮点解析器。

### 为什么需要 `format_decimal`

MoonBit 的 `Double::to_string` 对 `1e-7`、`1e+21` 这类值会输出**指数记法**：

```
1.0e-7   → "1e-7"      ← 非法 xsd:decimal
1.0e21   → "1e+21"     ← 非法 xsd:decimal
```

也就是说，一个 `lat="0.0000001"` 的合法输入，如果直接回写，会产出**非法 GPX 文档**。
`format_decimal` 把指数形式展开成纯十进制（`"0.0000001"`），保证输出始终合规。

### 复用生态 XML 解析器，不自造

XML 词法层依赖 [`Milky2018/xml`](https://github.com/moonbit-community/xml-mbt)（Apache-2.0）。
本库的价值在 XML 之上的 **GPX 语义层**：schema 约束、顺序校验、坐标语义、版本迁移。
这也是 Rust `gpx` crate、Python `gpxpy` 的一致做法。

### `extensions` 的无损保留：一个容易踩的坑

GPX 允许用 `extensions` 挂载任意命名空间的第三方数据（Garmin、Strava 都有自己的扩展）。
这些内容本库不解析，但**必须原样保留**，否则用户的私有数据就丢了。

实现方式是拿 XML 层的源码偏移量去切原始文本。这里有个陷阱：

> `@xml` 的 `offset` 是 **UTF-16 码元**偏移，不是 Unicode 码点偏移。

含 emoji 的文本 `String::length()` 与最终 offset 一致，而码点数会少 1。
**按码点切会切出乱码或吞掉相邻字符**，而且因为 XML 结构本身没坏，这个 bug 极难发现。

本库按码元宽度（`Char > 0xFFFF` 记 2）切分，并有含中文 + emoji 的回归用例锁住这个行为。

---

## 已知边界

- **不做**地图渲染、不涉及瓦片或可视化
- **不做**坐标系转换（WGS84 → GCJ-02 / BD-09）——那是坐标系规范，不是 GPX 规范
- **不做**二进制格式（FIT）、不做 TCX / KML 互转
- **不联网**、**不读写文件**（调用方自己把文本传进来）
- 底层 XML 库是 document-buffered，**超大文件（>100 MB）会整体载入内存**

---

## 规范依据

- GPX 1.1 Schema：<https://www.topografix.com/GPX/1/1/gpx.xsd>
- GPX 1.0 Schema：<https://www.topografix.com/GPX/1/0/gpx.xsd>

本项目为**原创实现**，依据上述公开标准编写，非移植任何第三方代码。

---

## 开发

```bash
moon check          # 类型检查
moon test           # 单元测试
moon fmt            # 格式化
moon run cmd/main   # 可运行示例
```

---

## 许可证

Apache-2.0
