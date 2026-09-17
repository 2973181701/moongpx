# moongpx

> MoonBit 的 GPX（GPS Exchange Format）规范实现：解析、校验、序列化、版本迁移。

GPX 是 GPS 轨迹的**通用交换格式**。Strava、Garmin（佳明）、两步路、咕咚、高德、
各类户外运动手表导出的轨迹文件，基本都是 GPX。

这个库让你能在 MoonBit 里**读、写、校验、转换**这些文件——严格按官方 XML Schema 实现，
纯函数，不联网、不读写文件。

---

## 状态

**v0.1.0 开发中**（D1–D5 已完成：坐标类型 + 完整模型 + 解析器 + 序列化）

| 模块 | 状态 |
|---|---|
| 坐标 / 数值类型（`latitudeType` / `longitudeType` / `degreesType` / `dgpsStationType`） | ✅ 已完成 |
| 根元素 + `metadata` + 子元素顺序校验 | ✅ 已完成 |
| `wpt` / `rte` / `trk` / `trkseg` 完整模型（含 `wptType` 全部 19 字段） | ✅ 已完成 |
| `extensions` 无损保留（原始 XML 切片） | ✅ 已完成 |
| 带行列号的诊断 | ✅ 已完成（解析阶段） |
| 序列化 + 往返一致性 | ✅ 已完成 |
| 独立的 `validate_gpx`（只校验不建模） | ⬜ 计划中 |
| GPX 1.0 解析 + 1.0 ↔ 1.1 迁移 | ⬜ 计划中 |

测试：`moon test` **78 / 78 通过**。

### 已知限制（当前开发版）

- **不支持带命名空间前缀的元素名**：`<g:gpx xmlns:g="...">` 会被判为"根元素不是 `<gpx>`"。
  默认命名空间（`xmlns="..."`，真实文件里的绝大多数写法）不受影响。
  彻底解决需要换用底层库的 `NamespaceReader`，见「依赖行为约定」
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
| 回写时 `&` 不转义 / `extensions` 被二次转义 | 前者产出非法 XML，后者把用户的私有扩展数据变成字面文本 |
| 回写时 `\r` 不转义成 `&#13;` | 被 XML 换行规范化折成 LF，数据静默改变 |

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

### 序列化

```moonbit
to_gpx(Gpx)          -> String   // 带 XML 声明与官方命名空间的完整文档
to_gpx_fragment(Gpx) -> String   // 不带声明与命名空间，便于嵌入别的 XML
```

输出**严格按 schema 的元素顺序**，数字一律走 `format_decimal`（不含指数记法），
文本与属性自动转义。可直接作为 `.gpx` 文件使用。

```moonbit
let gpx = match @moongpx.parse_gpx(src) {
  Ok(g) => g
  Err(d) => { println(@moongpx.format_diagnostics(d)); return }
}
println(@moongpx.to_gpx(gpx))
```

```xml
<?xml version="1.0" encoding="UTF-8"?>
<gpx xmlns="http://www.topografix.com/GPX/1/1" version="1.1" creator="moongpx">
  <metadata>
    <name>测试轨迹</name>
    <bounds minlat="31" minlon="121" maxlat="31.5" maxlon="121.5"/>
  </metadata>
  <wpt lat="31.2304" lon="121.4737">
    <name>起点</name>
  </wpt>
</gpx>
```

**往返一致性**是硬保证：

```moonbit
parse_gpx(to_gpx(g)) == g          // 模型完全相等
to_gpx(parse_gpx(to_gpx(g))) == to_gpx(g)   // 幂等
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

### 转义：不是「把特殊字符换掉」那么简单

| 位置 | 必须转义 | 原因 |
|---|---|---|
| 文本内容 | `&` `<` `>` | 不转义直接产出非法 XML |
| 属性值 | `&` `<` `>` `"` `'` | 同上，且引号会提前结束属性 |
| 文本内容 | `\r` → `&#13;` | XML 解析器把字面 CR **规范化成 LF**，不转义等于静默改数据 |
| 属性值 | `\t` `\n` → `&#9;` `&#10;` | 属性值规范化把字面 tab/换行**折成空格** |
| `extensions` 内部 | **什么都不转义** | 那里已经是合法 XML，再转一次会变成 `&lt;foo/&gt;` 字面文本 |

最后一行是**最容易写错**的地方：`extensions` 保存的是原始 XML 切片，
必须原样回写。本库有专门的用例（`extensions 内部原文不转义`）守着它。

### 「空字符串 ≡ 缺失」

解析器把 `<name></name>` 读成 `None`（没有文本节点）。若序列化器把 `Some("")`
写成 `<name></name>`，往返就不对称了。所以统一约定：**空字符串等同于缺失，不输出该元素**。
这样 `parse → to_gpx → parse` 才能严格相等。

---

## 依赖行为约定

XML 词法层的行为直接决定本库的正确性。以下几条**不是"测别人的库"，
而是固定我们自己的前提**，写在 `xml_behavior_test.mbt` 里：

| 依赖行为 | 对本库的影响 |
|---|---|
| 默认命名空间 `xmlns="..."` 被自动剥离 | 根元素名仍是 `gpx`，正常解析 |
| **命名空间前缀不剥离**（`<g:gpx>` → 名字是 `"g:gpx"`） | 已知限制，见上文 |
| 预定义实体 `&amp;` `&lt;` `&quot;` 被解码 | 序列化侧必须转义，两侧配对 |
| 数字字符引用 `&#13;` 被解码为 CR | 序列化侧必须把 CR 转义回 `&#13;` |
| CDATA 内容被取出为纯文本 | 一次序列化后变成转义文本（值相同、字节不同） |
| `Double::to_string` 对 `1e-7` / `1e+21` 输出指数 | 这是 `format_decimal` 存在的唯一理由 |
| `Double::to_string` 对整数值省略小数点（`90.0` → `"90"`） | 往返比较的是模型，不受影响 |

升级 `Milky2018/xml` 版本后这些用例若失败，说明本库的解析或序列化会随之出错，
必须重新评估，而不是等到线上才发现。

---

## 已知边界

- **不做**地图渲染、不涉及瓦片或可视化
- **不做**坐标系转换（WGS84 → GCJ-02 / BD-09）——那是坐标系规范，不是 GPX 规范
- **不做**二进制格式（FIT）、不做 TCX / KML 互转
- **不联网**、**不读写文件**（调用方自己把文本传进来）
- 底层 XML 库是 document-buffered，**超大文件（>100 MB）会整体载入内存**
- **不支持带命名空间前缀的元素名**（`<g:gpx>`）；默认命名空间正常
- **不做** XML 数字签名校验（GPX 1.1 schema 允许，但实际文件几乎不用）

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

### 关于 CI

CI 配置放在 `ci/ci.yml`，**不在** `.github/workflows/` 下。启用只需一条命令：

```bash
mkdir -p .github/workflows && cp ci/ci.yml .github/workflows/ci.yml
```

为什么要绕这一下：GitHub 不允许 OAuth App 在没有 `workflow` scope 的情况下
创建或修改工作流文件（无论走 git push 还是 Contents API，都会被拒）。
把配置文件放在普通目录里可以让它**照常纳入版本控制、可审阅**，
等 CI 权限就绪后复制过去即可生效，不必重写历史。

内容本身是完整的：`moon check` → `moon fmt --check` → `moon test` → `moon run cmd/main`。

---

## 许可证

Apache-2.0
