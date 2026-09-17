# moongpx

[![CI](https://github.com/2973181701/moongpx/actions/workflows/ci.yml/badge.svg)](https://github.com/2973181701/moongpx/actions/workflows/ci.yml)
[![mooncakes.io](https://img.shields.io/badge/mooncakes.io-v0.1.0-blue)](https://mooncakes.io/package/2973181701/moongpx)

> MoonBit 的 GPX（GPS Exchange Format）规范实现：解析、校验、序列化、版本迁移。

GPX 是 GPS 轨迹的**通用交换格式**。Strava、Garmin（佳明）、两步路、咕咚、高德、
各类户外运动手表导出的轨迹文件，基本都是 GPX。

这个库让你能在 MoonBit 里**读、写、校验、转换**这些文件——严格按官方 XML Schema 实现，
纯函数，不联网、不读写文件。

---

## 状态

**v0.1.0 已发布**（D1–D8 全部完成：坐标类型 + 完整模型 + 解析器 + 序列化 +
独立校验 + GPX 1.0 迁移 + 轨迹统计 + 发布 mooncakes.io）

| 模块 | 状态 |
|---|---|
| 坐标 / 数值类型（`latitudeType` / `longitudeType` / `degreesType` / `dgpsStationType`） | ✅ 已完成 |
| 根元素 + `metadata` + 子元素顺序校验 | ✅ 已完成 |
| `wpt` / `rte` / `trk` / `trkseg` 完整模型（含 `wptType` 全部 19 字段） | ✅ 已完成 |
| `extensions` 无损保留（原始 XML 切片） | ✅ 已完成 |
| 带行列号的诊断 | ✅ 已完成 |
| 序列化 + 往返一致性 | ✅ 已完成 |
| 独立的 `validate_gpx`（只校验不建模，含 warning 级语义检查） | ✅ 已完成 |
| GPX 1.0 解析 + 升级为 1.1 模型 | ✅ 已完成 |
| 轨迹统计（距离 / 爬升 / 包围盒 / 时长） | ✅ 已完成 |

测试：`moon test` **167 / 167 通过**。

#### 测试向量的两种来源

| 来源 | 用例数 | 作用 |
|---|---|---|
| 依据 GPX 规范**手工构造** | 163 | 逐条覆盖 schema 约束的边界值与非法值 |
| **真实软件导出**的文件 | 4 | 验证「真实世界的文件能不能用」 |

`testdata/` 下是三个真实文件（来源与许可见 `testdata/SOURCES.md`）：
Runkeeper App 导出的 GPX 1.1（带 Garmin 私有扩展）、GPSBabel 导出的 GPX 1.0（含非 ASCII 地名）、
以及 GPSBabel 导出的 36 KB 长轨迹（296 个轨迹点）。由 `tools/gen_realworld.py` 嵌入
`realworld_test.mbt`，不随 `moon add` 分发。

其中那个 36 KB 的长轨迹**故意保留了它的一处不合规**：文件把 `<time>` 写在了 `<sym>` 之后，
违反 `wpt` 的子元素顺序（GPSBabel 的老问题）。多数解析器会静默接受并给出错误结果，
本库明确报 `E1013`——这条就有测试锁着。

### 已知限制

- **不支持带命名空间前缀的元素名**：`<g:gpx xmlns:g="...">` 会被判为"根元素不是 `<gpx>`"。
  默认命名空间（`xmlns="..."`，真实文件里的绝大多数写法）不受影响。
  彻底解决需要换用底层库的 `NamespaceReader`，见「依赖行为约定」
- `parse_gpx` 返回 `Err` 时，成功解析的部分会被丢弃。
  需要"列出全部问题"时用 `validate_gpx`，它会连同 warning 一起报出
- **GPX 1.0 → 1.1 是单向的**：反向 1.1 → 1.0 会丢 `extensions` 与
  `fix`/`sat` 等精度字段，本库不提供

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
| `xsd:dateTime` 带时区偏移 | `09:00+08:00` 与 `01:00Z` 是同一时刻，但字符串比较会得出相反的结论 |
| 相邻轨迹点完全重合 | 设备卡顿时常见，不做检查会让距离 / 配速统计凭空多出一段 |

前 8 条是**合规问题**（文档在校验器下不合格），后 2 条是**数据质量问题**
（文档合法，但算出来的结果不可信）。本库对两者分别给出 `Error` 与 `Warning`。

---

## 安装

```bash
moon add 2973181701/moongpx
```

- 包主页：<https://mooncakes.io/package/2973181701/moongpx>
- 当前版本：`0.1.0`（Apache-2.0）
- 唯一依赖：`Milky2018/xml@0.4.1`

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

### 校验

```moonbit
validate_gpx(String)        -> Array[Diagnostic]   // 全部诊断，空数组 = 干净
is_valid_gpx(String)        -> Bool                // 连 warning 都没有才算通过
has_schema_errors(String)   -> Bool                // 只看 error
validate_gpx_report(String) -> String              // 直接可打印的报告
diagnostics_of_severity(Array[Diagnostic], Severity) -> Array[Diagnostic]
```

和 `parse_gpx` 共用同一套检查，差别在**视角**：

| | `parse_gpx` | `validate_gpx` |
|---|---|---|
| 关心 | 能不能用 | 完不完美 |
| 有 error 时 | 返回 `Err`，丢掉已解析的部分 | 照常报出，连同 warning 一起 |
| 有 warning 时 | 成功路径上**丢弃** | 报出 |
| 返回 | `Result[Gpx, ...]` | `Array[Diagnostic]`（空 = 干净） |

**不会因为发现一个问题就停下**——一个文件里的多个问题会一次性全部报出。
唯一的例外是 XML 语法本身坏了，拿不到事件流，此时只能报一条 `E1000`。

```moonbit
let src = "<gpx version=\"1.1\" creator=\"x\">" +
  "<wpt lat=\"1\" lon=\"1\"><ele>99999</ele><fix>bogus</fix></wpt>" +
  "<trk><name>空的</name></trk></gpx>"
println(@moongpx.validate_gpx_report(src))
// 共 3 条（1 错误 / 2 警告）：
// 1:69  error    E1016  <fix> 取值非法："bogus"（只允许 none / 2d / 3d / dgps / pps，小写）
// 1:32  warning  W1005  <ele> = 99999 m 超出地球表面合理范围（约 -11000 ~ 9000 m），请确认单位是否为米
// 1:91  warning  W1006  <trk> 没有任何 <trkseg>
```

上面的文档里 `<ele>` 和 `<trk>` 只是可疑，所以 `parse_gpx` 照样返回 `Ok`——
想看到它们必须用 `validate_gpx`：

```moonbit
let ok_but_suspicious = "<gpx version=\"1.1\" creator=\"x\"><wpt lat=\"1\" lon=\"1\"><ele>99999</ele></wpt></gpx>"

@moongpx.parse_gpx(ok_but_suspicious) is Ok(_)   // true —— 文档合法
@moongpx.has_schema_errors(ok_but_suspicious)    // false
@moongpx.is_valid_gpx(ok_but_suspicious)         // false —— 但有可疑之处
@moongpx.validate_gpx(ok_but_suspicious).length()  // 1
```

`moon run cmd/main` 里有完整的 11 段可运行演示（坐标区间 → 数值格式 → 解析 →
序列化 → 往返一致 → 诊断 → 独立校验 → 一次报出全部问题 → 1.0 迁移 → 轨迹统计）。

实际用法通常是「先校验，再决定要不要解析」：

```moonbit
if @moongpx.has_schema_errors(src) {
  // 不合格，把问题列给用户看，不往下走
  println(@moongpx.validate_gpx_report(src))
} else {
  // 合格；warning 只是提醒，照常解析
  match @moongpx.parse_gpx(src) { Ok(g) => use(g), Err(_) => () }
}
```

### GPX 1.0 与版本迁移

```moonbit
parse_gpx_1_0(String) -> Result[Gpx, Array[Diagnostic]]  // 解析 1.0 并升级为 1.1 模型
parse_gpx_any(String) -> Result[Gpx, Array[Diagnostic]]  // 按 version 属性自动分派
detect_gpx_version(String) -> String?                    // 只读 version 属性，不校验
```

GPX 1.0（2004）与 1.1 不兼容，而且**不是子集关系**：

| 差异 | GPX 1.0 | GPX 1.1 |
|---|---|---|
| 元数据位置 | `name` `desc` `author` `email` `url` `urlname` `time` `keywords` `bounds` 直接挂在根下 | 全部包在 `<metadata>` 里 |
| 链接 | `<url>` + `<urlname>` | `<link href>` + `<link><text>` |
| 作者 | `<author>` 与 `<email>` 都是纯文本 | `personType`（含 name / email / link） |
| 邮箱 | 完整地址 `me@example.com` | 拆成 `id` + `domain` 两个必填属性 |
| 朝向 / 速度 | `<course>` `<speed>` 是 trkpt 的正式子元素 | 没有（改放 `extensions`） |
| 命名空间 | `.../GPX/1/0` | `.../GPX/1/1` |

迁移映射：

| 1.0 | → 1.1 |
|---|---|
| 根级 `name` `desc` `time` `keywords` `bounds` | `metadata` 对应字段 |
| `<author>张三</author>` | `metadata.author.name` |
| `<email>me@example.com</email>` | `Email { id: "me", domain: "example.com" }`（按第一个 `@` 拆） |
| `<url>` + `<urlname>` | `Link { href, text }` |
| trkpt 的 `<course>` / `<speed>` | `Waypoint.extensions` 原文 |

`parse_gpx_1_0` 返回的模型 `version` 固定是 `"1.1"`——**迁移是单向的**。
反向 1.1 → 1.0 会丢 `extensions` 与精度字段，本库不做。

两个入口互不越界：`parse_gpx` 只接受 1.1，`parse_gpx_1_0` 只接受 1.0。
拿到的文件版本不确定时用 `parse_gpx_any`。

实现上 1.0 是**独立解析路径**（`parse10.mbt`），没有给 1.1 的解析函数加
版本分支——后者会让每个函数都拖着一个 `match`，且有误伤 1.1 的风险。

### 轨迹统计

```moonbit
haversine_m(Waypoint, Waypoint) -> Double       // 半正矢大圆距离
path_distance_m(Array[Waypoint]) -> Double
track_distance_m(Track) -> Double
climb_m(Array[Waypoint], Double) -> (Double, Double)   // (爬升, 下降)
bounds_of(Array[Waypoint]) -> Bounds?
track_stats(Track) -> TrackStats
```

两个约定：

1. **跨 `trkseg` 不相连**。`trkseg` 表示 GPS 信号中断后重新捕获，
   段间位移不是真实运动轨迹，计入距离会凭空多出一大截。
2. **爬升必须带阈值**。GPS 高程噪声在几米量级，朴素累加相邻点高差
   会把来回抖动放大成几百米的假爬升——这是开源实现里最常见的 bug。
   `climb_m` 默认阈值 3 m，传 `0.0` 可关闭过滤。

```moonbit
let s = @moongpx.track_stats(track)
// s.distance_m / s.ascend_m / s.descend_m / s.min_ele / s.max_ele
// s.bounds / s.start_time / s.end_time / s.duration_s
```

`start_time` / `end_time` 取的是**真正的最早/最晚**，不是首尾点——
轨迹时间可能不单调（见 `W1002`），直接取首尾会算错。
时长按 `xsd:dateTime` 的时区折算后相减。

### 数据模型

`Gpx` / `Metadata` / `Waypoint` / `Route` / `Track` / `TrackSegment` /
`Link` / `Person` / `Email` / `Copyright` / `Bounds`，
字段与官方 schema 一一对应。

`Waypoint` 覆盖 `wptType` 的全部 19 个字段（`ele` `time` `magvar` `geoidheight`
`name` `cmt` `desc` `src` `link` `sym` `type` `fix` `sat` `hdop` `vdop` `pdop`
`ageofdgpsdata` `dgpsid` `extensions`）。

模型字段是**只读**的：包外既不能写结构体字面量，也不能改字段——
所以程序化生成 GPX 要走构造函数：

```moonbit
Waypoint::new(lat, lon).with_ele(Some(10.0)).with_time(Some("2020-01-01T00:00:00Z"))
TrackSegment::new(points)
Track::new(segments)
Bounds::new(min_lat, min_lon, max_lat, max_lon)
Gpx::new(creator)
```

（给字段加 `mut` 这条路走不通：MoonBit 的 `unused_mut` 只看包内是否真的
写入过该字段，加不加 `pub` 都是错误级。构造函数是唯一解。）

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
| `E1017` | `version` 不是 `"1.0"`（`parse_gpx_1_0` 专用） |

**警告级**（不违反 schema，但语义可疑——不会被 `parse_gpx` 当成失败原因）：

| 代码 | 含义 |
|---|---|
| `W1001` | `bounds` 的 `min` 大于 `max` |
| `W1002` | 同一 `trkseg` 内后一个点的时间早于前一个点 |
| `W1003` | 相邻两个点的 `lat` / `lon` / `ele` 完全相同 |
| `W1004` | `fix` 与 `sat` 自相矛盾（如 `fix=none` 却 `sat=9`） |
| `W1005` | `ele` 超出地球表面合理范围（约 -11000 ~ 9000 m） |
| `W1006` | `trk` / `trkseg` / `rte` 没有任何点 |
| `W1007` | 点位落在 `metadata/bounds` 声明的范围之外 |

`W1002` 的时间比较会**折算时区**——`09:00+08:00` 与 `01:00Z` 被认作同一时刻，
不会因为字符串长得不一样就判错。

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

### `Error` 与 `Warning`：一条明确的界线

GPX 的约束分两类，混在一起会让调用方无所适从。本库的判定标准是：

> **Error** = 把这份文档丢进官方 XSD 校验器，它会判不合格。
> **Warning** = 校验器会放行，但人看一眼就知道有问题。

举几个对照：

| 现象 | 级别 | 为什么 |
|---|---|---|
| `<wpt>` 缺 `lat` 属性 | Error | schema 里 `lat` 是 `use="required"` |
| `<fix>bogus</fix>` | Error | `fixType` 是枚举，没有这个值 |
| `<ele>99999</ele>` | Warning | `xsd:decimal` 接受任意小数，schema 不管物理合理性 |
| `<fix>none</fix>` 配 `<sat>9</sat>` | Warning | 两个字段各自合法，放一起才荒谬 |
| 轨迹点时间倒流 | Warning | schema 里 `time` 只是可选字段，没有任何顺序约束 |
| `<trk>` 里没有 `<trkseg>` | Warning | `trkseg` 的 `minOccurs` 是 0 |

这条界线带来一个直接后果：**warning 绝不能让 `parse_gpx` 失败**。
一个海拔写着 99999 的文件依然是合法 GPX，拒绝解析它是越权。
所以 warning 只在 `validate_gpx` 里出现，`parse_gpx` 成功路径上会丢掉它们。

反过来说，这也意味着**只用 `parse_gpx` 会漏掉数据质量问题**。
处理别人给的文件时，正确的顺序是先 `validate_gpx` 扫一遍，再决定要不要用。

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
