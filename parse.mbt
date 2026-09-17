///|
/// GPX 解析：XML 事件流 → GPX 数据模型。
///
/// 分两步：
///   1. 把 XML 事件流搭成轻量节点树（保留源码偏移，用于切 `extensions` 原文）
///   2. 把节点树映射为 GPX 模型，同时校验 schema 约束
///
/// 所有约束违例都进诊断列表，**不抛异常**——一个文件里可能有多个问题，
/// 调用方需要一次拿到全部。

///|
/// 带源码位置的属性。
priv struct XAttr {
  name : String
  value : String
  line : Int
  column : Int
}

///|
/// 轻量 XML 节点。
priv struct XNode {
  name : String
  attrs : Array[XAttr]
  children : Array[XNode]
  texts : Array[String]
  line : Int
  column : Int
  /// 起始标签**结束**处的 offset（UTF-16 码元），用于切内部原文
  open_end : Int
  /// 结束标签**开始**处的 offset；自闭合元素等于 `open_end`
  close_start : Int
}

///|
/// 构建中的栈元素。
priv struct PendingNode {
  name : String
  attrs : Array[XAttr]
  children : Array[XNode]
  texts : Array[String]
  line : Int
  column : Int
  open_end : Int
}

///|
/// 单个 `Char` 占几个 UTF-16 码元。
///
/// ⚠️ 关键：`@xml` 的 `offset` 是 **UTF-16 码元**偏移，不是码点偏移
/// （实测：含 emoji 的文本 `String::length()` 与最终 offset 一致，而码点数少 1）。
/// 按码点切原文会切出乱码。
fn u16_width(ch : Char) -> Int {
  if ch.to_int() > 0xFFFF {
    2
  } else {
    1
  }
}

///|
/// 按 UTF-16 码元偏移切出子串。
fn slice_u16(s : String, a : Int, b : Int) -> String {
  if a >= b {
    return ""
  }
  let out : Array[Char] = []
  let mut pos = 0
  for ch in s {
    let w = u16_width(ch)
    if pos >= a && pos + w <= b {
      out.push(ch)
    }
    pos = pos + w
  }
  String::from_array(out)
}

///|
fn to_xattrs(el : @xml.XmlElement) -> Array[XAttr] {
  let out : Array[XAttr] = []
  for a in el.attributes {
    out.push({
      name: a.name,
      value: a.value,
      line: a.span.start.line,
      column: a.span.start.column,
    })
  }
  out
}

///|
/// 事件流 → 节点树。
fn build_xml_tree(events : Array[@xml.Event]) -> Array[XNode] {
  let roots : Array[XNode] = []
  let stack : Array[PendingNode] = []
  for ev in events {
    match ev.kind {
      @xml.EventKind::Start(el) =>
        stack.push({
          name: el.name,
          attrs: to_xattrs(el),
          children: [],
          texts: [],
          line: ev.span.start.line,
          column: ev.span.start.column,
          open_end: ev.span.end.offset,
        })
      @xml.EventKind::Empty(el) => {
        let node : XNode = {
          name: el.name,
          attrs: to_xattrs(el),
          children: [],
          texts: [],
          line: ev.span.start.line,
          column: ev.span.start.column,
          open_end: ev.span.start.offset,
          close_start: ev.span.start.offset,
        }
        if stack.length() == 0 {
          roots.push(node)
        } else {
          stack[stack.length() - 1].children.push(node)
        }
      }
      @xml.EventKind::End(_) =>
        if stack.length() > 0 {
          let top = stack[stack.length() - 1]
          let _ = stack.pop()
          let node : XNode = {
            name: top.name,
            attrs: top.attrs,
            children: top.children,
            texts: top.texts,
            line: top.line,
            column: top.column,
            open_end: top.open_end,
            close_start: ev.span.start.offset,
          }
          if stack.length() == 0 {
            roots.push(node)
          } else {
            stack[stack.length() - 1].children.push(node)
          }
        }
      @xml.EventKind::Text(t) =>
        if stack.length() > 0 {
          stack[stack.length() - 1].texts.push(t)
        }
      @xml.EventKind::CData(t) =>
        if stack.length() > 0 {
          stack[stack.length() - 1].texts.push(t)
        }
      _ => ()
    }
  }
  roots
}

///|
fn attr_of(node : XNode, name : String) -> XAttr? {
  for a in node.attrs {
    if a.name == name {
      return Some(a)
    }
  }
  None
}

///|
fn child_named(node : XNode, name : String) -> XNode? {
  for c in node.children {
    if c.name == name {
      return Some(c)
    }
  }
  None
}

///|
fn children_named(node : XNode, name : String) -> Array[XNode] {
  let out : Array[XNode] = []
  for c in node.children {
    if c.name == name {
      out.push(c)
    }
  }
  out
}

///|
/// 元素的文本内容（直接子文本节点拼接）。空元素返回 `None`。
fn text_of(node : XNode) -> String? {
  if node.texts.length() == 0 {
    return None
  }
  Some(node.texts.join(""))
}

///|
/// `extensions` 的**原始内部 XML**，用于无损往返。
fn raw_inner(src : String, node : XNode) -> String {
  slice_u16(src, node.open_end, node.close_start)
}

///|
/// 按 schema 的 `xsd:sequence` 校验子元素排列。
///
/// 规则：把每个元素名映射到一个序号，序号必须**单调不减**。
/// 这样既能拦住真正的乱序，又能允许 `link*` 这类重复出现的元素。
fn check_order(
  children : Array[XNode],
  ranks : Array[(String, Int)],
  diags : Array[Diagnostic],
  code : String,
  context : String,
) -> Unit {
  let mut max_rank = -1
  let mut max_name = ""
  for c in children {
    let mut rank : Int? = None
    for pair in ranks {
      if pair.0 == c.name {
        rank = Some(pair.1)
      }
    }
    match rank {
      Some(r) =>
        if r < max_rank {
          diags.push(
            Diagnostic::error(
              code,
              "元素 <\{c.name}> 出现在 <\{max_name}> 之后，违反 schema 规定的顺序（\{context}）",
              c.line,
              c.column,
            ),
          )
        } else {
          max_rank = r
          max_name = c.name
        }
      None => ()
    }
  }
}

///|
fn require_attr(
  node : XNode,
  name : String,
  diags : Array[Diagnostic],
) -> XAttr? {
  match attr_of(node, name) {
    Some(a) => Some(a)
    None => {
      diags.push(
        Diagnostic::error(
          code_missing_required_attribute,
          "<\{node.name}> 缺少必填属性 \{name}",
          node.line,
          node.column,
        ),
      )
      None
    }
  }
}

///|
fn decimal_attr(
  node : XNode,
  name : String,
  diags : Array[Diagnostic],
) -> Double? {
  match require_attr(node, name, diags) {
    Some(a) =>
      match parse_decimal(a.value) {
        Ok(v) => Some(v)
        Err(e) => {
          diags.push(
            Diagnostic::error(
              code_invalid_decimal,
              "属性 \{name}：\{e.message()}",
              a.line,
              a.column,
            ),
          )
          None
        }
      }
    None => None
  }
}

///|
fn decimal_child(
  node : XNode,
  name : String,
  diags : Array[Diagnostic],
) -> Double? {
  match child_named(node, name) {
    Some(c) =>
      match text_of(c) {
        Some(t) =>
          match parse_decimal(t) {
            Ok(v) => Some(v)
            Err(e) => {
              diags.push(
                Diagnostic::error(
                  code_invalid_decimal,
                  "<\{name}>：\{e.message()}",
                  c.line,
                  c.column,
                ),
              )
              None
            }
          }
        None => None
      }
    None => None
  }
}

///|
fn datetime_child(
  node : XNode,
  name : String,
  diags : Array[Diagnostic],
) -> String? {
  match child_named(node, name) {
    Some(c) =>
      match text_of(c) {
        Some(t) =>
          if is_valid_datetime(t) {
            Some(t)
          } else {
            diags.push(
              Diagnostic::error(
                code_invalid_datetime,
                "<\{name}> 不是合法的 xsd:dateTime：\"\{t}\"",
                c.line,
                c.column,
              ),
            )
            None
          }
        None => None
      }
    None => None
  }
}

// ─────────────────────────── 复合类型 ───────────────────────────

///|
fn parse_link(node : XNode, diags : Array[Diagnostic]) -> Link? {
  match require_attr(node, "href", diags) {
    Some(href) =>
      Some({
        href: href.value,
        text: match child_named(node, "text") {
          Some(c) => text_of(c)
          None => None
        },
        mime_type: match child_named(node, "type") {
          Some(c) => text_of(c)
          None => None
        },
      })
    None => None
  }
}

///|
fn parse_email(node : XNode, diags : Array[Diagnostic]) -> Email? {
  let id = require_attr(node, "id", diags)
  let domain = require_attr(node, "domain", diags)
  match (id, domain) {
    (Some(i), Some(d)) => Some({ id: i.value, domain: d.value, })
    _ => None
  }
}

///|
fn parse_person(node : XNode, diags : Array[Diagnostic]) -> Person? {
  Some({
    name: match child_named(node, "name") {
      Some(c) => text_of(c)
      None => None
    },
    email: match child_named(node, "email") {
      Some(c) => parse_email(c, diags)
      None => None
    },
    link: match child_named(node, "link") {
      Some(c) => parse_link(c, diags)
      None => None
    },
  })
}

///|
fn parse_copyright(node : XNode, diags : Array[Diagnostic]) -> Copyright? {
  match require_attr(node, "author", diags) {
    Some(author) =>
      Some({
        author: author.value,
        year: match child_named(node, "year") {
          Some(c) => text_of(c)
          None => None
        },
        license: match child_named(node, "license") {
          Some(c) => text_of(c)
          None => None
        },
      })
    None => None
  }
}

///|
fn parse_bounds(node : XNode, diags : Array[Diagnostic]) -> Bounds? {
  let min_lat_v = decimal_attr(node, "minlat", diags)
  let min_lon_v = decimal_attr(node, "minlon", diags)
  let max_lat_v = decimal_attr(node, "maxlat", diags)
  let max_lon_v = decimal_attr(node, "maxlon", diags)
  let min_lat = match min_lat_v {
    Some(v) =>
      match Latitude::from_double(v) {
        Ok(x) => Some(x)
        Err(e) => {
          diags.push(
            Diagnostic::error(
              code_invalid_decimal,
              "minlat：\{e.message()}",
              node.line,
              node.column,
            ),
          )
          None
        }
      }
    None => None
  }
  let min_lon = match min_lon_v {
    Some(v) =>
      match Longitude::from_double(v) {
        Ok(x) => Some(x)
        Err(e) => {
          diags.push(
            Diagnostic::error(
              code_invalid_decimal,
              "minlon：\{e.message()}",
              node.line,
              node.column,
            ),
          )
          None
        }
      }
    None => None
  }
  let max_lat = match max_lat_v {
    Some(v) =>
      match Latitude::from_double(v) {
        Ok(x) => Some(x)
        Err(e) => {
          diags.push(
            Diagnostic::error(
              code_invalid_decimal,
              "maxlat：\{e.message()}",
              node.line,
              node.column,
            ),
          )
          None
        }
      }
    None => None
  }
  let max_lon = match max_lon_v {
    Some(v) =>
      match Longitude::from_double(v) {
        Ok(x) => Some(x)
        Err(e) => {
          diags.push(
            Diagnostic::error(
              code_invalid_decimal,
              "maxlon：\{e.message()}",
              node.line,
              node.column,
            ),
          )
          None
        }
      }
    None => None
  }
  match (min_lat, min_lon, max_lat, max_lon) {
    (Some(a), Some(b), Some(c), Some(d)) => {
      // schema 不强制 min ≤ max，但语义上必须成立 —— 作为警告报告
      if a.to_double() > c.to_double() {
        diags.push(
          Diagnostic::warning(
            code_bounds_order,
            "bounds 的 minlat(\{a.to_gpx_string()}) 大于 maxlat(\{c.to_gpx_string()})",
            node.line,
            node.column,
          ),
        )
      }
      if b.to_double() > d.to_double() {
        diags.push(
          Diagnostic::warning(
            code_bounds_order,
            "bounds 的 minlon(\{b.to_gpx_string()}) 大于 maxlon(\{d.to_gpx_string()})",
            node.line,
            node.column,
          ),
        )
      }
      Some({ min_lat: a, min_lon: b, max_lat: c, max_lon: d, })
    }
    _ => None
  }
}

///|
/// `metadata` 子元素顺序。
let metadata_ranks : Array[(String, Int)] = [
  ("name", 0),
  ("desc", 1),
  ("author", 2),
  ("copyright", 3),
  ("link", 4),
  ("time", 5),
  ("keywords", 6),
  ("bounds", 7),
  ("extensions", 8),
]

///|
fn parse_metadata(
  src : String,
  node : XNode,
  diags : Array[Diagnostic],
) -> Metadata {
  check_order(
    node.children,
    metadata_ranks,
    diags,
    code_metadata_order,
    "metadata 的子元素顺序",
  )
  {
    name: match child_named(node, "name") {
      Some(c) => text_of(c)
      None => None
    },
    desc: match child_named(node, "desc") {
      Some(c) => text_of(c)
      None => None
    },
    author: match child_named(node, "author") {
      Some(c) => parse_person(c, diags)
      None => None
    },
    copyright: match child_named(node, "copyright") {
      Some(c) => parse_copyright(c, diags)
      None => None
    },
    links: {
      let out : Array[Link] = []
      for c in children_named(node, "link") {
        match parse_link(c, diags) {
          Some(l) => out.push(l)
          None => ()
        }
      }
      out
    },
    time: datetime_child(node, "time", diags),
    keywords: match child_named(node, "keywords") {
      Some(c) => text_of(c)
      None => None
    },
    bounds: match child_named(node, "bounds") {
      Some(c) => parse_bounds(c, diags)
      None => None
    },
    extensions: match child_named(node, "extensions") {
      Some(c) => Some(raw_inner(src, c))
      None => None
    },
  }
}

///|
/// `wptType` 子元素顺序（三段：位置 → 描述 → 精度）。
let wpt_ranks : Array[(String, Int)] = [
  ("ele", 0),
  ("time", 1),
  ("magvar", 2),
  ("geoidheight", 3),
  ("name", 4),
  ("cmt", 5),
  ("desc", 6),
  ("src", 7),
  ("link", 8),
  ("sym", 9),
  ("type", 10),
  ("fix", 11),
  ("sat", 12),
  ("hdop", 13),
  ("vdop", 14),
  ("pdop", 15),
  ("ageofdgpsdata", 16),
  ("dgpsid", 17),
  ("extensions", 18),
]

///|
fn simple_text_child(node : XNode, name : String) -> String? {
  match child_named(node, name) {
    Some(c) => text_of(c)
    None => None
  }
}

///|
fn parse_waypoint(
  src : String,
  node : XNode,
  diags : Array[Diagnostic],
) -> Waypoint? {
  check_order(
    node.children,
    wpt_ranks,
    diags,
    code_wpt_order,
    "<\{node.name}> 的子元素顺序",
  )
  let lat_a = require_attr(node, "lat", diags)
  let lon_a = require_attr(node, "lon", diags)
  let lat = match lat_a {
    Some(a) =>
      match Latitude::from_string(a.value) {
        Ok(v) => Some(v)
        Err(e) => {
          diags.push(
            Diagnostic::error(
              code_invalid_decimal,
              "lat：\{e.message()}",
              a.line,
              a.column,
            ),
          )
          None
        }
      }
    None => None
  }
  let lon = match lon_a {
    Some(a) =>
      match Longitude::from_string(a.value) {
        Ok(v) => Some(v)
        Err(e) => {
          diags.push(
            Diagnostic::error(
              code_invalid_decimal,
              "lon：\{e.message()}",
              a.line,
              a.column,
            ),
          )
          None
        }
      }
    None => None
  }
  match (lat, lon) {
    (Some(la), Some(lo)) => {
      let fix = match simple_text_child(node, "fix") {
        Some(t) =>
          match FixType::from_string(t) {
            Some(f) => Some(f)
            None => {
              let c = child_named(node, "fix")
              match c {
                Some(cc) =>
                  diags.push(
                    Diagnostic::error(
                      code_invalid_fix,
                      "<fix> 取值非法：\"\{t}\"（只允许 none / 2d / 3d / dgps / pps，小写）",
                      cc.line,
                      cc.column,
                    ),
                  )
                None => ()
              }
              None
            }
          }
        None => None
      }
      let magvar = match simple_text_child(node, "magvar") {
        Some(t) =>
          match Degrees::from_string(t) {
            Ok(v) => Some(v)
            Err(e) => {
              diags.push(
                Diagnostic::error(
                  code_invalid_decimal,
                  "magvar：\{e.message()}",
                  node.line,
                  node.column,
                ),
              )
              None
            }
          }
        None => None
      }
      let dgps_id = match simple_text_child(node, "dgpsid") {
        Some(t) =>
          match DgpsStationId::from_string(t) {
            Ok(v) => Some(v)
            Err(e) => {
              diags.push(
                Diagnostic::error(
                  code_invalid_decimal,
                  "dgpsid：\{e.message()}",
                  node.line,
                  node.column,
                ),
              )
              None
            }
          }
        None => None
      }
      let sat = match simple_text_child(node, "sat") {
        Some(t) =>
          match parse_nonneg_int(t) {
            Some(v) => Some(v)
            None => {
              diags.push(
                Diagnostic::error(
                  code_invalid_decimal,
                  "<sat> 必须是非负整数：\"\{t}\"",
                  node.line,
                  node.column,
                ),
              )
              None
            }
          }
        None => None
      }
      Some({
        lat: la,
        lon: lo,
        ele: decimal_child(node, "ele", diags),
        time: datetime_child(node, "time", diags),
        magvar,
        geoid_height: decimal_child(node, "geoidheight", diags),
        name: simple_text_child(node, "name"),
        cmt: simple_text_child(node, "cmt"),
        desc: simple_text_child(node, "desc"),
        src: simple_text_child(node, "src"),
        links: {
          let out : Array[Link] = []
          for c in children_named(node, "link") {
            match parse_link(c, diags) {
              Some(l) => out.push(l)
              None => ()
            }
          }
          out
        },
        sym: simple_text_child(node, "sym"),
        wpt_type: simple_text_child(node, "type"),
        fix,
        sat,
        hdop: decimal_child(node, "hdop", diags),
        vdop: decimal_child(node, "vdop", diags),
        pdop: decimal_child(node, "pdop", diags),
        age_of_dgps_data: decimal_child(node, "ageofdgpsdata", diags),
        dgps_id,
        extensions: match child_named(node, "extensions") {
          Some(c) => Some(raw_inner(src, c))
          None => None
        },
      })
    }
    _ => None
  }
}

///|
fn parse_nonneg_int(text : String) -> Int? {
  let s = collapse_space(text)
  let codes = codes_of(s)
  if codes.length() == 0 {
    return None
  }
  let mut i = 0
  while i < codes.length() {
    if !is_digit_code(codes[i]) {
      return None
    }
    i = i + 1
  }
  Some(@string.parse_int(s)) catch {
    _ => None
  }
}

///|
/// `rte` / `trk` 的公共子元素顺序（两者相同）。
let route_like_ranks : Array[(String, Int)] = [
  ("name", 0),
  ("cmt", 1),
  ("desc", 2),
  ("src", 3),
  ("link", 4),
  ("number", 5),
  ("type", 6),
  ("extensions", 7),
  ("rtept", 8),
  ("trkseg", 8),
]

///|
fn parse_route(src : String, node : XNode, diags : Array[Diagnostic]) -> Route {
  check_order(
    node.children,
    route_like_ranks,
    diags,
    code_rte_order,
    "rte 的子元素顺序",
  )
  {
    name: simple_text_child(node, "name"),
    cmt: simple_text_child(node, "cmt"),
    desc: simple_text_child(node, "desc"),
    src: simple_text_child(node, "src"),
    links: {
      let out : Array[Link] = []
      for c in children_named(node, "link") {
        match parse_link(c, diags) {
          Some(l) => out.push(l)
          None => ()
        }
      }
      out
    },
    number: match simple_text_child(node, "number") {
      Some(t) => parse_nonneg_int(t)
      None => None
    },
    route_type: simple_text_child(node, "type"),
    extensions: match child_named(node, "extensions") {
      Some(c) => Some(raw_inner(src, c))
      None => None
    },
    points: {
      let out : Array[Waypoint] = []
      for c in children_named(node, "rtept") {
        match parse_waypoint(src, c, diags) {
          Some(w) => out.push(w)
          None => ()
        }
      }
      out
    },
  }
}

///|
fn parse_track_segment(
  src : String,
  node : XNode,
  diags : Array[Diagnostic],
) -> TrackSegment {
  {
    points: {
      let out : Array[Waypoint] = []
      for c in children_named(node, "trkpt") {
        match parse_waypoint(src, c, diags) {
          Some(w) => out.push(w)
          None => ()
        }
      }
      out
    },
    extensions: match child_named(node, "extensions") {
      Some(c) => Some(raw_inner(src, c))
      None => None
    },
  }
}

///|
fn parse_track(src : String, node : XNode, diags : Array[Diagnostic]) -> Track {
  check_order(
    node.children,
    route_like_ranks,
    diags,
    code_trk_order,
    "trk 的子元素顺序",
  )
  {
    name: simple_text_child(node, "name"),
    cmt: simple_text_child(node, "cmt"),
    desc: simple_text_child(node, "desc"),
    src: simple_text_child(node, "src"),
    links: {
      let out : Array[Link] = []
      for c in children_named(node, "link") {
        match parse_link(c, diags) {
          Some(l) => out.push(l)
          None => ()
        }
      }
      out
    },
    number: match simple_text_child(node, "number") {
      Some(t) => parse_nonneg_int(t)
      None => None
    },
    track_type: simple_text_child(node, "type"),
    extensions: match child_named(node, "extensions") {
      Some(c) => Some(raw_inner(src, c))
      None => None
    },
    segments: {
      let out : Array[TrackSegment] = []
      for c in children_named(node, "trkseg") {
        out.push(parse_track_segment(src, c, diags))
      }
      out
    },
  }
}

///|
/// 根元素子元素顺序。
let root_ranks : Array[(String, Int)] = [
  ("metadata", 0),
  ("wpt", 1),
  ("rte", 2),
  ("trk", 3),
  ("extensions", 4),
]

///|
/// 解析 GPX 文档。
///
/// 返回 `Ok(Gpx)` 表示 XML 结构完整且坐标等关键字段可用；
/// 返回 `Err(诊断列表)` 表示存在无法继续的错误。
///
/// 无论成功失败，**警告级诊断**都可能在成功路径上被丢弃——
/// 需要完整诊断请用 `validate_gpx`（D6 实现）。
pub fn parse_gpx(src : String) -> Result[Gpx, Array[Diagnostic]] {
  let diags : Array[Diagnostic] = []
  let events = @xml.Reader::from_string(src).read_events_until_eof() catch {
    @xml.XmlError::At(error=kind, span~) => {
      diags.push(
        Diagnostic::error(
          code_xml_parse_error,
          "XML 解析失败：\{kind.to_string()}",
          span.start.line,
          span.start.column,
        ),
      )
      return Err(diags)
    }
  }
  let roots = build_xml_tree(events)
  if roots.length() == 0 {
    diags.push(
      Diagnostic::error(code_root_not_gpx, "文档没有根元素", 1, 1),
    )
    return Err(diags)
  }
  let root = roots[0]
  if root.name != "gpx" {
    diags.push(
      Diagnostic::error(
        code_root_not_gpx,
        "根元素必须是 <gpx>，实际是 <\{root.name}>",
        root.line,
        root.column,
      ),
    )
    return Err(diags)
  }
  // version：必填且固定为 "1.1"
  let version = match attr_of(root, "version") {
    Some(a) => {
      if a.value != "1.1" {
        diags.push(
          Diagnostic::error(
            code_version_not_1_1,
            "version 必须是 \"1.1\"（schema 固定值），实际是 \"\{a.value}\"",
            a.line,
            a.column,
          ),
        )
      }
      a.value
    }
    None => {
      diags.push(
        Diagnostic::error(
          code_version_missing,
          "<gpx> 缺少必填属性 version",
          root.line,
          root.column,
        ),
      )
      ""
    }
  }
  // creator：必填
  let creator = match attr_of(root, "creator") {
    Some(a) => a.value
    None => {
      diags.push(
        Diagnostic::error(
          code_creator_missing,
          "<gpx> 缺少必填属性 creator（创建该文档的软件名称或 URL）",
          root.line,
          root.column,
        ),
      )
      ""
    }
  }
  // 子元素顺序
  check_order(
    root.children,
    root_ranks,
    diags,
    code_root_order,
    "<gpx> 的子元素顺序",
  )
  // metadata 至多一次
  let metadata_nodes = children_named(root, "metadata")
  if metadata_nodes.length() > 1 {
    let second = metadata_nodes[1]
    diags.push(
      Diagnostic::error(
        code_metadata_duplicate,
        "<metadata> 最多只能出现一次",
        second.line,
        second.column,
      ),
    )
  }
  let metadata = match metadata_nodes.length() > 0 {
    true => Some(parse_metadata(src, metadata_nodes[0], diags))
    false => None
  }
  let waypoints : Array[Waypoint] = []
  for c in children_named(root, "wpt") {
    match parse_waypoint(src, c, diags) {
      Some(w) => waypoints.push(w)
      None => ()
    }
  }
  let routes : Array[Route] = []
  for c in children_named(root, "rte") {
    routes.push(parse_route(src, c, diags))
  }
  let tracks : Array[Track] = []
  for c in children_named(root, "trk") {
    tracks.push(parse_track(src, c, diags))
  }
  let gpx : Gpx = {
    version,
    creator,
    metadata,
    waypoints,
    routes,
    tracks,
    extensions: match child_named(root, "extensions") {
      Some(c) => Some(raw_inner(src, c))
      None => None
    },
  }
  if has_errors(diags) {
    Err(diags)
  } else {
    Ok(gpx)
  }
}
