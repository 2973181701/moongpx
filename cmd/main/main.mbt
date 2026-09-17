///|
/// moongpx 可运行示例。
///
/// 跑法：moon run cmd/main
///
/// 演示三件事：
///   1. 坐标解析与范围校验（含那个不对称的经纬度边界）
///   2. 严格 xsd:decimal —— 指数记法必须被拒
///   3. 序列化时的指数陷阱 —— 输出必须永远是合法 GPX
///   4. 解析真实文档、诊断行列号
///   5. 序列化 + 往返一致性（模型 → 文本 → 模型，必须完全相等）

///|
fn show_lat(text : String) -> Unit {
  match @moongpx.Latitude::from_string(text) {
    Ok(lat) =>
      println(
        "  lat \"\{text}\" → 合法，回写为 \"\{lat.to_gpx_string()}\"",
      )
    Err(e) => println("  lat \"\{text}\" → 拒绝：\{e.message()}")
  }
}

///|
fn show_lon(text : String) -> Unit {
  match @moongpx.Longitude::from_string(text) {
    Ok(lon) =>
      println(
        "  lon \"\{text}\" → 合法，回写为 \"\{lon.to_gpx_string()}\"",
      )
    Err(e) => println("  lon \"\{text}\" → 拒绝：\{e.message()}")
  }
}

///|
fn main {
  println("=== 1. 纬度是闭区间 [-90, 90] ===")
  show_lat("31.2304")
  show_lat("90")
  show_lat("-90")
  show_lat("90.0001")

  println("")
  println("=== 2. 经度是半开区间 [-180, 180) —— 两端不对称 ===")
  show_lon("121.4737")
  show_lon("-180")
  show_lon("179.9999")
  show_lon("180")
  println(
    "  ↑ 注意：纬度 90 合法，但经度 180 非法。这是 GPX 最容易被做错的地方。",
  )

  println("")
  println("=== 3. xsd:decimal 不接受指数记法 ===")
  for text in ["1e2", "1e-7", "NaN", "INF", "31.2304"] {
    match @moongpx.parse_decimal(text) {
      Ok(v) => println("  \"\{text}\" → \{v}")
      Err(e) => println("  \"\{text}\" → 拒绝：\{e.message()}")
    }
  }

  println("")
  println(
    "=== 4. 序列化陷阱：Double 会输出指数，但 GPX 不允许 ===",
  )
  for v in [1.0e-7, 1.0e21, 2.5e-3, 31.2304] {
    println(
      "  \{v} → 原始 \{v.to_string()} → 合规 \{@moongpx.format_decimal(v)}",
    )
  }
  println(
    "  ↑ 若直接用 Double::to_string，lat=\"0.0000001\" 会被回写成 \"1e-7\"，产出非法文档。",
  )

  println("")
  println("=== 5. 解析一个真实 GPX 文档 ===")
  let doc = "<gpx version=\"1.1\" creator=\"moongpx demo\">" +
    "<metadata><name>晨跑</name><time>2026-09-17T01:00:00Z</time>" +
    "<bounds minlat=\"31.1\" minlon=\"121.1\" maxlat=\"31.3\" maxlon=\"121.3\"/></metadata>" +
    "<trk><name>早跑</name><trkseg>" +
    "<trkpt lat=\"31.1\" lon=\"121.1\"><ele>4</ele></trkpt>" +
    "<trkpt lat=\"31.2\" lon=\"121.2\"><ele>6</ele></trkpt>" +
    "<trkpt lat=\"31.3\" lon=\"121.3\"><ele>9</ele></trkpt>" +
    "</trkseg></trk></gpx>"
  match @moongpx.parse_gpx(doc) {
    Ok(gpx) => {
      println("  解析成功")
      println("  version = \{gpx.version}   creator = \{gpx.creator}")
      match gpx.metadata {
        Some(m) =>
          match m.name {
            Some(n) => println("  metadata.name = \{n}")
            None => println("  metadata.name = 无")
          }
        None => println("  metadata = 无")
      }
      println("  轨迹数 = \{gpx.tracks.length()}")
      if gpx.tracks.length() > 0 {
        let segs = gpx.tracks[0].segments
        println(
          "  轨迹段数 = \{segs.length()}   点数 = \{segs[0].points.length()}",
        )
        let mut total = 0.0
        for i = 1; i < segs[0].points.length(); i = i + 1 {
          let a = segs[0].points[i - 1]
          let b = segs[0].points[i]
          total = total + distance_m(a, b)
        }
        println("  轨迹总长 = \{total} m")
      }
    }
    Err(diags) => println(@moongpx.format_diagnostics(diags))
  }

  println("")
  println("=== 7. 序列化：模型 → 合规 GPX 文本 ===")
  let doc2 = "<gpx version=\"1.1\" creator=\"moongpx demo\">" +
    "<metadata><name>晨跑 &amp; 夜跑</name>" +
    "<bounds minlat=\"31.1\" minlon=\"121.1\" maxlat=\"31.3\" maxlon=\"121.3\"/></metadata>" +
    "<wpt lat=\"31.2304\" lon=\"121.4737\"><ele>0.0000001</ele><desc>a&lt;b</desc></wpt>" +
    "<trk><name>早跑</name><trkseg>" +
    "<trkpt lat=\"31.1\" lon=\"121.1\"><ele>4</ele></trkpt>" +
    "</trkseg></trk>" +
    "<extensions><myext vendor=\"acme\">私有数据</myext></extensions>" +
    "</gpx>"
  match @moongpx.parse_gpx(doc2) {
    Ok(g) => {
      let out = @moongpx.to_gpx(g)
      println(out)
      println(
        "  ↑ 注意三处：① <ele> 输出 0.0000001 而不是 1e-7；" +
        "② 文本里的 & 被转义成 &amp;；③ extensions 原样保留未被转义。",
      )
      println("")
      match @moongpx.parse_gpx(out) {
        Ok(g2) =>
          println(
            "  往返一致性 parse(to_gpx(g)) == g ：\{if g == g2 { "成立" } else { "失败" }}",
          )
        Err(d) =>
          println("  往返后解析失败：\{@moongpx.format_diagnostics(d)}")
      }
    }
    Err(d) => println(@moongpx.format_diagnostics(d))
  }

  println("")
  println("=== 8. 一份有问题的文档 —— 诊断带行列号 ===")
  let bad = "<gpx version=\"1.0\" creator=\"x\">\n" +
    "  <wpt lon=\"180\"/>\n" +
    "  <trk><trkseg/></trk>\n" +
    "  <wpt lat=\"1\" lon=\"2\"/>\n" +
    "</gpx>"
  match @moongpx.parse_gpx(bad) {
    Ok(_) => println("  不该成功")
    Err(diags) => {
      println("  共 \{diags.length()} 条诊断：")
      for d in diags {
        println("    \{d.to_string()}")
      }
    }
  }

  println("")
  println(
    "=== 9. 独立校验：warning 不阻塞解析，但会被记下来 ===",
  )
  let suspicious = "<gpx version=\"1.1\" creator=\"x\">" +
    "<wpt lat=\"1\" lon=\"1\"><ele>99999</ele></wpt>" +
    "<trk><name>空的</name></trk></gpx>"
  match @moongpx.parse_gpx(suspicious) {
    Ok(_) => println("  parse_gpx   → Ok（文档合法，可以正常用）")
    Err(d) =>
      println("  parse_gpx   → Err: \{@moongpx.format_diagnostics(d)}")
  }
  println("  is_valid_gpx      = \{@moongpx.is_valid_gpx(suspicious)}")
  println("  has_schema_errors = \{@moongpx.has_schema_errors(suspicious)}")
  println(
    "  validate_gpx      = \{@moongpx.validate_gpx(suspicious).length()} 条：",
  )
  for d in @moongpx.validate_gpx(suspicious) {
    println("    \{d.to_string()}")
  }

  println("")
  println(
    "=== 10. 一次报出全部问题（error 与 warning 混合，不中断） ===",
  )
  let mixed = "<gpx version=\"1.1\" creator=\"x\">" +
    "<wpt lat=\"1\" lon=\"1\"><ele>99999</ele><fix>bogus</fix></wpt>" +
    "<trk><name>空的</name></trk></gpx>"
  println(@moongpx.validate_gpx_report(mixed))

  println("")
  println("示例结束。")
}

///|
fn distance_m(a : @moongpx.Waypoint, b : @moongpx.Waypoint) -> Double {
  let r = 6371008.8
  let d2r = 0.017453292519943295
  let lat1 = a.lat.to_double()
  let lon1 = a.lon.to_double()
  let lat2 = b.lat.to_double()
  let lon2 = b.lon.to_double()
  let dlat = (lat2 - lat1) * d2r
  let dlon = (lon2 - lon1) * d2r
  let sdlat = @math.sin(dlat / 2.0)
  let sdlon = @math.sin(dlon / 2.0)
  let h = sdlat * sdlat +
    @math.cos(lat1 * d2r) * @math.cos(lat2 * d2r) * sdlon * sdlon
  2.0 * r * @math.asin(h.sqrt())
}
