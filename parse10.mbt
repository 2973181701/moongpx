///|
/// GPX 1.0 解析，并升级为 1.1 数据模型。
///
/// GPX 1.0（2004）与 1.1 不兼容，而且**不是简单的子集关系**：
///
/// | 差异 | GPX 1.0 | GPX 1.1 |
/// |---|---|---|
/// | 元数据位置 | `name` `desc` `author` `email` `url` `urlname` `time` `keywords` `bounds` **直接挂在根下** | 全部包在 `<metadata>` 里 |
/// | 链接 | `<url>` + `<urlname>` | `<link href>` + `<link><text>` |
/// | 作者 | `<author>` 与 `<email>` 都是纯文本 | `personType`（含 name / email / link） |
/// | 邮箱 | 完整地址 `me@example.com` | 拆成 `id` + `domain` 两个必填属性 |
/// | 朝向 / 速度 | `<course>` `<speed>` 是 trkpt 的正式子元素 | 没有（改放 `extensions`） |
/// | 命名空间 | `.../GPX/1/0` | `.../GPX/1/1` |
///
/// 因为差异是"字段换了一套"而不是"少几个字段"，本模块**不复用 1.1 的解析函数**，
/// 而是独立解析后统一产出 1.1 模型。理由：复用会让 1.1 的每个解析函数都拖着
/// 版本分支，既脏又容易在改 1.0 时误伤 1.1。
///
/// 迁移是**单向**的（1.0 → 1.1）。反向 1.1 → 1.0 会丢信息
/// （`extensions`、`fix`/`sat` 等精度字段无处安放），本库不提供。

// ── 1.0 的子元素顺序表 ──
//
// 都来自 GPX 1.0 官方 schema 的 sequence 定义。

///|
let root_ranks_1_0 : Array[(String, Int)] = [
  ("name", 0),
  ("desc", 1),
  ("author", 2),
  ("email", 3),
  ("url", 4),
  ("urlname", 5),
  ("time", 6),
  ("keywords", 7),
  ("bounds", 8),
  ("wpt", 9),
  ("rte", 10),
  ("trk", 11),
]

///|
/// 1.0 的 `wpt` / `rtept`：位置 → 描述，没有精度段。
let wpt_ranks_1_0 : Array[(String, Int)] = [
  ("ele", 0),
  ("time", 1),
  ("name", 2),
  ("cmt", 3),
  ("desc", 4),
  ("src", 5),
  ("url", 6),
  ("urlname", 7),
  ("sym", 8),
  ("type", 9),
]

///|
/// 1.0 的 `trkpt` 比 `wpt` 更短，而且多了 `course` / `speed`。
let trkpt_ranks_1_0 : Array[(String, Int)] = [
  ("ele", 0),
  ("time", 1),
  ("course", 2),
  ("speed", 3),
]

///|
/// 1.0 的 `rte` / `trk` 共有段。
let route_like_ranks_1_0 : Array[(String, Int)] = [
  ("name", 0),
  ("cmt", 1),
  ("desc", 2),
  ("src", 3),
  ("url", 4),
  ("urlname", 5),
  ("number", 6),
  ("rtept", 7),
  ("trkseg", 7),
]

///|
fn lat_attr(node : XNode, diags : Array[Diagnostic]) -> Latitude? {
  match require_attr(node, "lat", diags) {
    Some(a) =>
      match Latitude::from_string(a.value) {
        Ok(v) => Some(v)
        Err(e) => {
          diags.push(
            Diagnostic::error(
              code_invalid_decimal,
              "属性 lat：\{e.message()}",
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
fn lon_attr(node : XNode, diags : Array[Diagnostic]) -> Longitude? {
  match require_attr(node, "lon", diags) {
    Some(a) =>
      match Longitude::from_string(a.value) {
        Ok(v) => Some(v)
        Err(e) => {
          diags.push(
            Diagnostic::error(
              code_invalid_decimal,
              "属性 lon：\{e.message()}",
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
/// 1.0 的 `<url>` + `<urlname>` → 1.1 的 `link`。
///
/// 两个元素都可选，但**只要有一个存在就产出一个 link**——
/// `urlname` 单独出现（没写 url）时 href 为空串，这比丢掉它更符合"无损"原则。
fn links_from_url(node : XNode, links : Array[Link]) -> Array[Link] {
  let url = simple_text_child(node, "url")
  let urlname = simple_text_child(node, "urlname")
  match (url, urlname) {
    (None, None) => links
    (u, n) => {
      let href = match u {
        Some(v) => v
        None => ""
      }
      links.push({ href, text: n, mime_type: None, })
      links
    }
  }
}

///|
fn parse_waypoint_1_0(
  node : XNode,
  diags : Array[Diagnostic],
  ranks : Array[(String, Int)],
) -> Waypoint? {
  check_order(
    node.children,
    ranks,
    diags,
    code_wpt_order,
    "<\{node.name}> 的子元素顺序",
  )
  match lat_attr(node, diags) {
    None => None
    Some(lat) =>
      match lon_attr(node, diags) {
        None => None
        Some(lon) => {
          let links : Array[Link] = []
          let links = links_from_url(node, links)
          // 1.0 的 trkpt 有 course / speed，1.1 模型没有这两个字段，
          // 按 1.1 的通行做法写进 extensions（原始文本，可无损往返）
          let course = decimal_child(node, "course", diags)
          let speed = decimal_child(node, "speed", diags)
          let extensions = course_speed_extensions(course, speed)
          Some({
            lat,
            lon,
            ele: decimal_child(node, "ele", diags),
            time: datetime_child(node, "time", diags),
            magvar: None,
            geoid_height: None,
            name: simple_text_child(node, "name"),
            cmt: simple_text_child(node, "cmt"),
            desc: simple_text_child(node, "desc"),
            src: simple_text_child(node, "src"),
            links,
            sym: simple_text_child(node, "sym"),
            wpt_type: simple_text_child(node, "type"),
            fix: None,
            sat: None,
            hdop: None,
            vdop: None,
            pdop: None,
            age_of_dgps_data: None,
            dgps_id: None,
            extensions,
          })
        }
      }
  }
}

///|
/// 把 `course` / `speed` 拼成 1.1 的 `extensions` 原文。
fn course_speed_extensions(course : Double?, speed : Double?) -> String? {
  match (course, speed) {
    (None, None) => None
    (Some(c), None) => Some("<course>" + format_decimal(c) + "</course>")
    (None, Some(s)) => Some("<speed>" + format_decimal(s) + "</speed>")
    (Some(c), Some(s)) =>
      Some(
        "<course>" +
        format_decimal(c) +
        "</course><speed>" +
        format_decimal(s) +
        "</speed>",
      )
  }
}

///|
fn parse_route_1_0(node : XNode, diags : Array[Diagnostic]) -> Route {
  check_order(
    node.children,
    route_like_ranks_1_0,
    diags,
    code_rte_order,
    "<rte> 的子元素顺序",
  )
  let points : Array[Waypoint] = []
  for c in children_named(node, "rtept") {
    match parse_waypoint_1_0(c, diags, wpt_ranks_1_0) {
      Some(p) => points.push(p)
      None => ()
    }
  }
  let links : Array[Link] = []
  let links = links_from_url(node, links)
  {
    name: simple_text_child(node, "name"),
    cmt: simple_text_child(node, "cmt"),
    desc: simple_text_child(node, "desc"),
    src: simple_text_child(node, "src"),
    links,
    number: match simple_text_child(node, "number") {
      Some(t) => parse_nonneg_int(t)
      None => None
    },
    route_type: simple_text_child(node, "type"),
    extensions: None,
    points,
  }
}

///|
fn parse_track_1_0(node : XNode, diags : Array[Diagnostic]) -> Track {
  check_order(
    node.children,
    route_like_ranks_1_0,
    diags,
    code_trk_order,
    "<trk> 的子元素顺序",
  )
  let segments : Array[TrackSegment] = []
  for c in children_named(node, "trkseg") {
    let points : Array[Waypoint] = []
    for p in children_named(c, "trkpt") {
      match parse_waypoint_1_0(p, diags, trkpt_ranks_1_0) {
        Some(w) => points.push(w)
        None => ()
      }
    }
    segments.push({ points, extensions: None, })
  }
  let links : Array[Link] = []
  let links = links_from_url(node, links)
  {
    name: simple_text_child(node, "name"),
    cmt: simple_text_child(node, "cmt"),
    desc: simple_text_child(node, "desc"),
    src: simple_text_child(node, "src"),
    links,
    number: match simple_text_child(node, "number") {
      Some(t) => parse_nonneg_int(t)
      None => None
    },
    track_type: simple_text_child(node, "type"),
    extensions: None,
    segments,
  }
}

///|
/// 1.0 的邮箱是完整地址文本，1.1 拆成 `id` + `domain` 两个必填属性。
///
/// 按**第一个** `@` 拆分。没有 `@` 时整个串当 id、domain 留空——
/// 这是非法邮箱，但拆不出来的部分不该被静默丢弃。
fn parse_email_1_0(text : String) -> Email {
  // 逐字符找第一个 @。不用切片是因为 String 的下标是字节序，
  // 而 Char 与字节不一定一一对应
  let chars : Array[Char] = []
  for ch in text {
    chars.push(ch)
  }
  let mut at = -1
  let mut i = 0
  while i < chars.length() && at < 0 {
    if chars[i] == '@' {
      at = i
    }
    i = i + 1
  }
  if at < 0 {
    return { id: text, domain: "", }
  }
  let id_chars : Array[Char] = []
  let domain_chars : Array[Char] = []
  let mut j = 0
  while j < at {
    id_chars.push(chars[j])
    j = j + 1
  }
  j = at + 1
  while j < chars.length() {
    domain_chars.push(chars[j])
    j = j + 1
  }
  {
    id: String::from_array(id_chars),
    domain: String::from_array(domain_chars),
  }
}

///|
/// 从 1.0 根元素收集元数据，产出 1.1 的 `Metadata`。
fn parse_metadata_1_0(root : XNode, diags : Array[Diagnostic]) -> Metadata {
  let email = match child_named(root, "email") {
    Some(c) =>
      match text_of(c) {
        Some(t) => Some(parse_email_1_0(t))
        None => None
      }
    None => None
  }
  // 1.0 的 <author> 是纯文本，拆到 1.1 的 personType.name
  let author = match child_named(root, "author") {
    Some(c) =>
      match text_of(c) {
        Some(t) => Some({ name: Some(t), email, link: None, })
        None => None
      }
    None =>
      match email {
        // 只有邮箱没有作者名时，也建一个 person 把邮箱挂上去
        Some(_) => Some({ name: None, email, link: None, })
        None => None
      }
  }
  let links : Array[Link] = []
  let links = links_from_url(root, links)
  {
    name: simple_text_child(root, "name"),
    desc: simple_text_child(root, "desc"),
    author,
    copyright: None,
    links,
    time: datetime_child(root, "time", diags),
    keywords: simple_text_child(root, "keywords"),
    bounds: match child_named(root, "bounds") {
      Some(c) => parse_bounds(c, diags)
      None => None
    },
    extensions: None,
  }
}

///|
/// 探测文档的 `version` 属性值。无法解析时返回 `None`。
///
/// 只用来做入口分派，不校验取值是否合法——那是各解析入口的事。
pub fn detect_gpx_version(src : String) -> String? {
  let events = @xml.Reader::from_string(src).read_events_until_eof() catch {
    _ => return None
  }
  let roots = build_xml_tree(events)
  if roots.length() == 0 {
    return None
  }
  match attr_of(roots[0], "version") {
    Some(a) => Some(a.value)
    None => None
  }
}

///|
/// 解析 GPX 1.0 文档，并升级为 1.1 数据模型。
///
/// 返回的 `Gpx.version` 固定是 `"1.1"`——**迁移是单向的**。
/// 想原样输出 1.0 请用别的工具，本库不做 1.1 → 1.0（会丢 `extensions`
/// 与精度字段）。
///
/// 与 `parse_gpx` 一样：成功路径上的 warning 会被丢弃，
/// 要完整诊断用 `validate_gpx`。
pub fn parse_gpx_1_0(src : String) -> Result[Gpx, Array[Diagnostic]] {
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
  match attr_of(root, "version") {
    Some(a) =>
      if a.value != "1.0" {
        diags.push(
          Diagnostic::error(
            code_version_not_1_0,
            "version 必须是 \"1.0\"（GPX 1.0 文档），实际是 \"\{a.value}\"",
            a.line,
            a.column,
          ),
        )
      }
    None =>
      diags.push(
        Diagnostic::error(
          code_version_missing,
          "<gpx> 缺少必填属性 version",
          root.line,
          root.column,
        ),
      )
  }
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
  check_order(
    root.children,
    root_ranks_1_0,
    diags,
    code_root_order,
    "<gpx> 的子元素顺序",
  )
  if has_errors(diags) {
    return Err(diags)
  }
  let waypoints : Array[Waypoint] = []
  for c in children_named(root, "wpt") {
    match parse_waypoint_1_0(c, diags, wpt_ranks_1_0) {
      Some(w) => waypoints.push(w)
      None => ()
    }
  }
  let routes : Array[Route] = []
  for c in children_named(root, "rte") {
    routes.push(parse_route_1_0(c, diags))
  }
  let tracks : Array[Track] = []
  for c in children_named(root, "trk") {
    tracks.push(parse_track_1_0(c, diags))
  }
  if has_errors(diags) {
    return Err(diags)
  }
  Ok({
    version: "1.1",
    creator,
    metadata: Some(parse_metadata_1_0(root, diags)),
    waypoints,
    routes,
    tracks,
    extensions: None,
  })
}

///|
/// 自动探测版本：1.0 走 `parse_gpx_1_0`，否则走 `parse_gpx`（1.1）。
///
/// 探测依据是根元素的 `version` 属性。拿不到（比如 XML 本身坏了）
/// 时退化为按 1.1 解析，由 1.1 的逻辑报出真正的问题。
pub fn parse_gpx_any(src : String) -> Result[Gpx, Array[Diagnostic]] {
  match detect_gpx_version(src) {
    Some("1.0") => parse_gpx_1_0(src)
    _ => parse_gpx(src)
  }
}
