///|
/// GPX 序列化：数据模型 → 合规的 GPX 1.1 XML 文本。
///
/// 四条设计红线：
///
///   1. **输出顺序严格按 schema**。`xsd:sequence` 要求子元素顺序固定，
///      乱序文档在严格校验器下会被拒——序列化器不能"随便排"。
///   2. **数字一律走 `format_decimal`**。绝不输出指数记法，
///      `xsd:decimal` 的词法里没有 `e`。
///   3. **文本与属性必须转义**。`&` `<` `>` `"` 不转义直接产出非法 XML。
///      另外 `\r` 要转成 `&#13;`——XML 解析器会把字面 CR 规范化成 LF，
///      不转义就等于静默改数据。
///   4. **`extensions` 原样回写、绝不转义**。它的内容是**已经合法的原始 XML**，
///      再转义一次会变成 `&lt;foo/&gt;` 这种字面文本，数据直接被破坏。

///|
/// GPX 1.1 的官方命名空间 URI。
///
/// schema 是 `elementFormDefault="qualified"`，所以合规文档的元素
/// **必须**在这个命名空间里。序列化时默认带上它。
pub let gpx_namespace : String = "http://www.topografix.com/GPX/1/1"

///|
/// 生成 `depth` 层缩进（每层 2 空格）。
fn indent_str(depth : Int) -> String {
  let out : Array[Char] = []
  let mut i = 0
  while i < depth * 2 {
    out.push(' ')
    i = i + 1
  }
  String::from_array(out)
}

///|
fn push_all(out : Array[Char], s : String) -> Unit {
  for ch in s {
    out.push(ch)
  }
}

///|
/// 元素**文本内容**的转义。
///
/// 用码点比较而不是字符字面量匹配，与 `geo.mbt` 的风格保持一致，
/// 也避免任何 Char 模式语法上的歧义。
fn escape_text(s : String) -> String {
  let out : Array[Char] = []
  for ch in s {
    match ch.to_int() {
      0x26 => push_all(out, "&amp;") // &
      0x3C => push_all(out, "&lt;") // <
      0x3E => push_all(out, "&gt;") // >
      0x0D => push_all(out, "&#13;") // CR：必须转义，否则被规范化为 LF
      _ => out.push(ch)
    }
  }
  String::from_array(out)
}

///|
/// **属性值**的转义。
///
/// 比文本多转义引号；制表符与换行也必须转义——XML 的属性值规范化
/// 会把字面 tab / 换行折成空格，不转义就会静默改变数据。
fn escape_attr(s : String) -> String {
  let out : Array[Char] = []
  for ch in s {
    match ch.to_int() {
      0x26 => push_all(out, "&amp;") // &
      0x3C => push_all(out, "&lt;") // <
      0x3E => push_all(out, "&gt;") // >
      0x22 => push_all(out, "&quot;") // "
      0x27 => push_all(out, "&apos;") // '
      0x0D => push_all(out, "&#13;") // CR
      0x0A => push_all(out, "&#10;") // LF
      0x09 => push_all(out, "&#9;") // TAB
      _ => out.push(ch)
    }
  }
  String::from_array(out)
}

///|
/// 写一个元素：先看 `body` 是否为空，空则自闭合。
///
/// 所有复合元素都走这个函数，保证"空元素写法"在全文档内一致。
fn emit_container(
  out : Array[String],
  depth : Int,
  tag : String,
  attrs : Array[(String, String)],
  body : Array[String],
) -> Unit {
  out.push(indent_str(depth))
  out.push("<" + tag)
  for p in attrs {
    out.push(" " + p.0 + "=\"" + escape_attr(p.1) + "\"")
  }
  if body.length() == 0 {
    out.push("/>\n")
  } else {
    out.push(">\n")
    for s in body {
      out.push(s)
    }
    out.push(indent_str(depth))
    out.push("</" + tag + ">\n")
  }
}

///|
/// 简单文本子元素。
///
/// **空字符串等同于缺失**：不写这个元素。
/// 这是刻意的取舍——解析器把 `<name></name>` 读成 `None`，
/// 若序列化器把 `Some("")` 写成 `<name></name>`，
/// 往返就会不对称。统一成"空即缺失"，往返才能严格成立。
fn emit_text_el(
  out : Array[String],
  depth : Int,
  name : String,
  value : String?,
) -> Unit {
  match value {
    Some(v) =>
      if v != "" {
        out.push(indent_str(depth))
        out.push("<" + name + ">")
        out.push(escape_text(v))
        out.push("</" + name + ">\n")
      }
    None => ()
  }
}

///|
/// `xsd:decimal` 子元素。走 `format_decimal`，永不输出指数记法。
fn emit_decimal_el(
  out : Array[String],
  depth : Int,
  name : String,
  value : Double?,
) -> Unit {
  match value {
    Some(v) => emit_text_el(out, depth, name, Some(format_decimal(v)))
    None => ()
  }
}

///|
/// `extensions`：内容原样回写，**不转义、不缩进**。
///
/// 不缩进是刻意的：`extensions` 保留的是源码原文，任何重排都会破坏
/// "往返后原始文本逐字节相等"这条不变量。
fn emit_raw_extensions(out : Array[String], depth : Int, raw : String?) -> Unit {
  match raw {
    Some(r) => {
      out.push(indent_str(depth))
      out.push("<extensions>")
      out.push(r)
      out.push("</extensions>\n")
    }
    None => ()
  }
}

// ─────────────────────────── 复合类型 ───────────────────────────

///|
fn emit_link(out : Array[String], depth : Int, l : Link) -> Unit {
  let body : Array[String] = []
  emit_text_el(body, depth + 1, "text", l.text)
  emit_text_el(body, depth + 1, "type", l.mime_type)
  emit_container(out, depth, "link", [("href", l.href)], body)
}

///|
fn emit_email(out : Array[String], depth : Int, e : Email) -> Unit {
  emit_container(out, depth, "email", [("id", e.id), ("domain", e.domain)], [])
}

///|
fn emit_person(out : Array[String], depth : Int, p : Person) -> Unit {
  let body : Array[String] = []
  emit_text_el(body, depth + 1, "name", p.name)
  match p.email {
    Some(e) => emit_email(body, depth + 1, e)
    None => ()
  }
  match p.link {
    Some(l) => emit_link(body, depth + 1, l)
    None => ()
  }
  emit_container(out, depth, "author", [], body)
}

///|
fn emit_copyright(out : Array[String], depth : Int, c : Copyright) -> Unit {
  let body : Array[String] = []
  emit_text_el(body, depth + 1, "year", c.year)
  emit_text_el(body, depth + 1, "license", c.license)
  emit_container(out, depth, "copyright", [("author", c.author)], body)
}

///|
fn emit_bounds(out : Array[String], depth : Int, b : Bounds) -> Unit {
  emit_container(
    out,
    depth,
    "bounds",
    [
      ("minlat", b.min_lat.to_gpx_string()),
      ("minlon", b.min_lon.to_gpx_string()),
      ("maxlat", b.max_lat.to_gpx_string()),
      ("maxlon", b.max_lon.to_gpx_string()),
    ],
    [],
  )
}

///|
/// `metadata` 子元素顺序：name, desc, author, copyright, link*,
/// time, keywords, bounds, extensions。
fn emit_metadata(out : Array[String], depth : Int, m : Metadata) -> Unit {
  let body : Array[String] = []
  emit_text_el(body, depth + 1, "name", m.name)
  emit_text_el(body, depth + 1, "desc", m.desc)
  match m.author {
    Some(p) => emit_person(body, depth + 1, p)
    None => ()
  }
  match m.copyright {
    Some(c) => emit_copyright(body, depth + 1, c)
    None => ()
  }
  for l in m.links {
    emit_link(body, depth + 1, l)
  }
  emit_text_el(body, depth + 1, "time", m.time)
  emit_text_el(body, depth + 1, "keywords", m.keywords)
  match m.bounds {
    Some(b) => emit_bounds(body, depth + 1, b)
    None => ()
  }
  emit_raw_extensions(body, depth + 1, m.extensions)
  emit_container(out, depth, "metadata", [], body)
}

///|
/// `wptType` 子元素顺序：ele, time, magvar, geoidheight, name, cmt, desc,
/// src, link*, sym, type, fix, sat, hdop, vdop, pdop, ageofdgpsdata,
/// dgpsid, extensions。
fn emit_waypoint_body(out : Array[String], depth : Int, w : Waypoint) -> Unit {
  emit_decimal_el(out, depth, "ele", w.ele)
  emit_text_el(out, depth, "time", w.time)
  match w.magvar {
    Some(d) => emit_decimal_el(out, depth, "magvar", Some(d.to_double()))
    None => ()
  }
  emit_decimal_el(out, depth, "geoidheight", w.geoid_height)
  emit_text_el(out, depth, "name", w.name)
  emit_text_el(out, depth, "cmt", w.cmt)
  emit_text_el(out, depth, "desc", w.desc)
  emit_text_el(out, depth, "src", w.src)
  for l in w.links {
    emit_link(out, depth, l)
  }
  emit_text_el(out, depth, "sym", w.sym)
  emit_text_el(out, depth, "type", w.wpt_type)
  match w.fix {
    Some(f) => emit_text_el(out, depth, "fix", Some(f.to_string()))
    None => ()
  }
  match w.sat {
    Some(v) => emit_text_el(out, depth, "sat", Some(v.to_string()))
    None => ()
  }
  emit_decimal_el(out, depth, "hdop", w.hdop)
  emit_decimal_el(out, depth, "vdop", w.vdop)
  emit_decimal_el(out, depth, "pdop", w.pdop)
  emit_decimal_el(out, depth, "ageofdgpsdata", w.age_of_dgps_data)
  match w.dgps_id {
    Some(d) => emit_text_el(out, depth, "dgpsid", Some(d.to_gpx_string()))
    None => ()
  }
  emit_raw_extensions(out, depth, w.extensions)
}

///|
/// 写一个点元素。`tag` 决定是 `wpt` / `rtept` / `trkpt`——三者共用
/// `wptType`，结构完全一致，只有元素名不同。
fn emit_waypoint(
  out : Array[String],
  depth : Int,
  tag : String,
  w : Waypoint,
) -> Unit {
  let body : Array[String] = []
  emit_waypoint_body(body, depth + 1, w)
  emit_container(
    out,
    depth,
    tag,
    [("lat", w.lat.to_gpx_string()), ("lon", w.lon.to_gpx_string())],
    body,
  )
}

///|
fn emit_route(out : Array[String], depth : Int, r : Route) -> Unit {
  let body : Array[String] = []
  emit_text_el(body, depth + 1, "name", r.name)
  emit_text_el(body, depth + 1, "cmt", r.cmt)
  emit_text_el(body, depth + 1, "desc", r.desc)
  emit_text_el(body, depth + 1, "src", r.src)
  for l in r.links {
    emit_link(body, depth + 1, l)
  }
  match r.number {
    Some(n) => emit_text_el(body, depth + 1, "number", Some(n.to_string()))
    None => ()
  }
  emit_text_el(body, depth + 1, "type", r.route_type)
  emit_raw_extensions(body, depth + 1, r.extensions)
  for p in r.points {
    emit_waypoint(body, depth + 1, "rtept", p)
  }
  emit_container(out, depth, "rte", [], body)
}

///|
/// `trkseg` 子元素顺序：trkpt*, extensions?。
fn emit_track_segment(
  out : Array[String],
  depth : Int,
  s : TrackSegment,
) -> Unit {
  let body : Array[String] = []
  for p in s.points {
    emit_waypoint(body, depth + 1, "trkpt", p)
  }
  emit_raw_extensions(body, depth + 1, s.extensions)
  emit_container(out, depth, "trkseg", [], body)
}

///|
fn emit_track(out : Array[String], depth : Int, t : Track) -> Unit {
  let body : Array[String] = []
  emit_text_el(body, depth + 1, "name", t.name)
  emit_text_el(body, depth + 1, "cmt", t.cmt)
  emit_text_el(body, depth + 1, "desc", t.desc)
  emit_text_el(body, depth + 1, "src", t.src)
  for l in t.links {
    emit_link(body, depth + 1, l)
  }
  match t.number {
    Some(n) => emit_text_el(body, depth + 1, "number", Some(n.to_string()))
    None => ()
  }
  emit_text_el(body, depth + 1, "type", t.track_type)
  emit_raw_extensions(body, depth + 1, t.extensions)
  for s in t.segments {
    emit_track_segment(body, depth + 1, s)
  }
  emit_container(out, depth, "trk", [], body)
}

// ─────────────────────────── 入口 ───────────────────────────

///|
/// 把 GPX 模型序列化为 XML 文本。
///
/// 根元素顺序严格按 schema：`metadata → wpt* → rte* → trk* → extensions`。
///
/// 输出带 XML 声明与官方命名空间，可直接作为 `.gpx` 文件使用。
/// 保证 `parse_gpx(to_gpx(g))` 与 `g` **完全相等**（见 `serialize_test.mbt`）。
pub fn to_gpx(gpx : Gpx) -> String {
  let out : Array[String] = []
  out.push("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n")
  let body : Array[String] = []
  match gpx.metadata {
    Some(m) => emit_metadata(body, 1, m)
    None => ()
  }
  for w in gpx.waypoints {
    emit_waypoint(body, 1, "wpt", w)
  }
  for r in gpx.routes {
    emit_route(body, 1, r)
  }
  for t in gpx.tracks {
    emit_track(body, 1, t)
  }
  emit_raw_extensions(body, 1, gpx.extensions)
  emit_container(
    out,
    0,
    "gpx",
    [
      ("xmlns", gpx_namespace),
      ("version", gpx.version),
      ("creator", gpx.creator),
    ],
    body,
  )
  out.join("")
}

///|
/// 不带 XML 声明与命名空间的紧凑输出，便于嵌入到别的 XML 文档里。
///
/// 根元素属性顺序与 `to_gpx` 一致，只是省掉了 `xmlns`。
pub fn to_gpx_fragment(gpx : Gpx) -> String {
  let out : Array[String] = []
  let body : Array[String] = []
  match gpx.metadata {
    Some(m) => emit_metadata(body, 1, m)
    None => ()
  }
  for w in gpx.waypoints {
    emit_waypoint(body, 1, "wpt", w)
  }
  for r in gpx.routes {
    emit_route(body, 1, r)
  }
  for t in gpx.tracks {
    emit_track(body, 1, t)
  }
  emit_raw_extensions(body, 1, gpx.extensions)
  emit_container(
    out,
    0,
    "gpx",
    [("version", gpx.version), ("creator", gpx.creator)],
    body,
  )
  out.join("")
}
