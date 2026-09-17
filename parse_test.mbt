///|
/// GPX 解析器的黑盒测试。

///|
fn contains_code(diags : Array[@moongpx.Diagnostic], code : String) -> Bool {
  for d in diags {
    if d.code == code {
      return true
    }
  }
  false
}

///|
test "最小合法文档" {
  let src = "<gpx version=\"1.1\" creator=\"moongpx\"></gpx>"
  match @moongpx.parse_gpx(src) {
    Ok(g) => {
      assert_eq(g.version, "1.1")
      assert_eq(g.creator, "moongpx")
      assert_eq(g.metadata is None, true)
      assert_eq(g.waypoints.length(), 0)
    }
    Err(d) => fail(@moongpx.format_diagnostics(d))
  }
}

///|
test "自闭合根元素也可解析" {
  let src = "<gpx version=\"1.1\" creator=\"x\"/>"
  match @moongpx.parse_gpx(src) {
    Ok(g) => assert_eq(g.creator, "x")
    Err(d) => fail(@moongpx.format_diagnostics(d))
  }
}

///|
test "version 必须是固定值 1.1" {
  for v in ["1.0", "1.10", "1.1.0", "2.0", ""] {
    let src = "<gpx version=\"" + v + "\" creator=\"x\"></gpx>"
    match @moongpx.parse_gpx(src) {
      Ok(_) => fail("version=\"" + v + "\" 应被拒绝")
      Err(d) => assert_true(contains_code(d, @moongpx.code_version_not_1_1))
    }
  }
}

///|
test "缺少 version" {
  let src = "<gpx creator=\"x\"></gpx>"
  match @moongpx.parse_gpx(src) {
    Ok(_) => fail("缺 version 应被拒绝")
    Err(d) => assert_true(contains_code(d, @moongpx.code_version_missing))
  }
}

///|
test "缺少 creator" {
  let src = "<gpx version=\"1.1\"></gpx>"
  match @moongpx.parse_gpx(src) {
    Ok(_) => fail("缺 creator 应被拒绝")
    Err(d) => assert_true(contains_code(d, @moongpx.code_creator_missing))
  }
}

///|
test "根元素不是 gpx" {
  let src = "<foo version=\"1.1\" creator=\"x\"></foo>"
  match @moongpx.parse_gpx(src) {
    Ok(_) => fail("非 gpx 根元素应被拒绝")
    Err(d) => assert_true(contains_code(d, @moongpx.code_root_not_gpx))
  }
}

///|
test "根子元素顺序：trk 出现在 wpt 之前" {
  let src = "<gpx version=\"1.1\" creator=\"x\"><trk><trkseg/></trk><wpt lat=\"1\" lon=\"2\"/></gpx>"
  match @moongpx.parse_gpx(src) {
    Ok(_) => fail("顺序错误应被拒绝")
    Err(d) => assert_true(contains_code(d, @moongpx.code_root_order))
  }
}

///|
test "根子元素顺序：metadata 必须在最前" {
  let src = "<gpx version=\"1.1\" creator=\"x\"><wpt lat=\"1\" lon=\"2\"/><metadata></metadata></gpx>"
  match @moongpx.parse_gpx(src) {
    Ok(_) => fail("metadata 后置应被拒绝")
    Err(d) => assert_true(contains_code(d, @moongpx.code_root_order))
  }
}

///|
test "metadata 子元素顺序错误" {
  let src = "<gpx version=\"1.1\" creator=\"x\"><metadata><desc>d</desc><name>n</name></metadata></gpx>"
  match @moongpx.parse_gpx(src) {
    Ok(_) => fail("metadata 乱序应被拒绝")
    Err(d) => assert_true(contains_code(d, @moongpx.code_metadata_order))
  }
}

///|
test "metadata 出现两次" {
  let src = "<gpx version=\"1.1\" creator=\"x\"><metadata></metadata><metadata></metadata></gpx>"
  match @moongpx.parse_gpx(src) {
    Ok(_) => fail("重复 metadata 应被拒绝")
    Err(d) => assert_true(contains_code(d, @moongpx.code_metadata_duplicate))
  }
}

///|
test "metadata 完整字段" {
  let src = "<gpx version=\"1.1\" creator=\"x\">" +
    "<metadata>" +
    "<name>晨跑</name>" +
    "<desc>早上跑的</desc>" +
    "<author><name>张三</name><email id=\"zhangsan\" domain=\"example.com\"/></author>" +
    "<copyright author=\"张三\"><year>2026</year><license>MIT</license></copyright>" +
    "<link href=\"https://example.com\"><text>站点</text><type>text/html</type></link>" +
    "<time>2026-09-17T01:00:00Z</time>" +
    "<keywords>跑步,健身</keywords>" +
    "<bounds minlat=\"31.0\" minlon=\"121.0\" maxlat=\"31.5\" maxlon=\"121.5\"/>" +
    "</metadata></gpx>"
  match @moongpx.parse_gpx(src) {
    Ok(g) =>
      match g.metadata {
        Some(m) => {
          assert_eq(m.name, Some("晨跑"))
          assert_eq(m.desc, Some("早上跑的"))
          assert_eq(m.time, Some("2026-09-17T01:00:00Z"))
          assert_eq(m.keywords, Some("跑步,健身"))
          match m.author {
            Some(p) => {
              assert_eq(p.name, Some("张三"))
              match p.email {
                Some(e) => {
                  assert_eq(e.id, "zhangsan")
                  assert_eq(e.domain, "example.com")
                }
                None => fail("email 丢失")
              }
            }
            None => fail("author 丢失")
          }
          match m.copyright {
            Some(c) => {
              assert_eq(c.author, "张三")
              assert_eq(c.year, Some("2026"))
            }
            None => fail("copyright 丢失")
          }
          assert_eq(m.links.length(), 1)
          assert_eq(m.links[0].href, "https://example.com")
          assert_eq(m.links[0].text, Some("站点"))
          assert_eq(m.links[0].mime_type, Some("text/html"))
          match m.bounds {
            Some(b) => {
              assert_eq(b.min_lat.to_double(), 31.0)
              assert_eq(b.max_lon.to_double(), 121.5)
            }
            None => fail("bounds 丢失")
          }
        }
        None => fail("metadata 丢失")
      }
    Err(d) => fail(@moongpx.format_diagnostics(d))
  }
}

///|
test "wpt 三段顺序错误（ele 在 name 之后）" {
  let src = "<gpx version=\"1.1\" creator=\"x\">" +
    "<wpt lat=\"1\" lon=\"2\"><name>n</name><ele>5</ele></wpt></gpx>"
  match @moongpx.parse_gpx(src) {
    Ok(_) => fail("wpt 乱序应被拒绝")
    Err(d) => assert_true(contains_code(d, @moongpx.code_wpt_order))
  }
}

///|
test "wpt 三段顺序正确" {
  let src = "<gpx version=\"1.1\" creator=\"x\">" +
    "<wpt lat=\"31.23\" lon=\"121.47\"><ele>5</ele><time>2026-09-17T01:00:00Z</time>" +
    "<name>起点</name><sym>Flag</sym><fix>3d</fix><sat>8</sat><hdop>1.2</hdop>" +
    "<dgpsid>7</dgpsid></wpt></gpx>"
  match @moongpx.parse_gpx(src) {
    Ok(g) => {
      assert_eq(g.waypoints.length(), 1)
      let w = g.waypoints[0]
      assert_eq(w.lat.to_double(), 31.23)
      assert_eq(w.lon.to_double(), 121.47)
      assert_eq(w.ele, Some(5.0))
      assert_eq(w.name, Some("起点"))
      assert_eq(w.sym, Some("Flag"))
      assert_eq(w.fix, Some(@moongpx.Fix3d))
      assert_eq(w.sat, Some(8))
      assert_eq(w.hdop, Some(1.2))
      match w.dgps_id {
        Some(v) => assert_eq(v.to_int(), 7)
        None => fail("dgpsid 丢失")
      }
    }
    Err(d) => fail(@moongpx.format_diagnostics(d))
  }
}

///|
test "fix 枚举大小写敏感" {
  let src = "<gpx version=\"1.1\" creator=\"x\"><wpt lat=\"1\" lon=\"2\"><fix>2D</fix></wpt></gpx>"
  match @moongpx.parse_gpx(src) {
    Ok(_) => fail("fix=\"2D\" 应被拒绝（schema 是小写）")
    Err(d) => assert_true(contains_code(d, @moongpx.code_invalid_fix))
  }
}

///|
test "wpt 缺少 lat / lon" {
  let src = "<gpx version=\"1.1\" creator=\"x\"><wpt lon=\"2\"/></gpx>"
  match @moongpx.parse_gpx(src) {
    Ok(_) => fail("缺 lat 应被拒绝")
    Err(d) =>
      assert_true(contains_code(d, @moongpx.code_missing_required_attribute))
  }
}

///|
test "wpt 坐标越界（经度 180）" {
  let src = "<gpx version=\"1.1\" creator=\"x\"><wpt lat=\"1\" lon=\"180\"/></gpx>"
  match @moongpx.parse_gpx(src) {
    Ok(_) => fail("lon=180 应被拒绝")
    Err(d) => assert_true(contains_code(d, @moongpx.code_invalid_decimal))
  }
}

///|
test "link 缺少 href" {
  let src = "<gpx version=\"1.1\" creator=\"x\"><metadata><link><text>t</text></link></metadata></gpx>"
  match @moongpx.parse_gpx(src) {
    Ok(_) => fail("link 缺 href 应被拒绝")
    Err(d) =>
      assert_true(contains_code(d, @moongpx.code_missing_required_attribute))
  }
}

///|
test "email 缺少 domain" {
  let src = "<gpx version=\"1.1\" creator=\"x\">" +
    "<metadata><author><email id=\"a\"/></author></metadata></gpx>"
  match @moongpx.parse_gpx(src) {
    Ok(_) => fail("email 缺 domain 应被拒绝")
    Err(d) =>
      assert_true(contains_code(d, @moongpx.code_missing_required_attribute))
  }
}

///|
test "bounds 四个属性全必填" {
  for
    attrs in [
      "minlon=\"1\" maxlat=\"2\" maxlon=\"3\"", "minlat=\"1\" maxlat=\"2\" maxlon=\"3\"",
      "minlat=\"1\" minlon=\"1\" maxlon=\"3\"", "minlat=\"1\" minlon=\"1\" maxlat=\"2\"",
    ] {
    let src = "<gpx version=\"1.1\" creator=\"x\"><metadata><bounds " +
      attrs +
      "/></metadata></gpx>"
    match @moongpx.parse_gpx(src) {
      Ok(_) => fail("bounds 缺属性应被拒绝：" + attrs)
      Err(d) =>
        assert_true(contains_code(d, @moongpx.code_missing_required_attribute))
    }
  }
}

///|
test "bounds 的 min > max 只给警告，不算错误" {
  let src = "<gpx version=\"1.1\" creator=\"x\">" +
    "<metadata><bounds minlat=\"35\" minlon=\"125\" maxlat=\"31\" maxlon=\"121\"/></metadata></gpx>"
  match @moongpx.parse_gpx(src) {
    Ok(g) =>
      match g.metadata {
        Some(m) => assert_true(m.bounds is Some(_))
        None => fail("metadata 丢失")
      }
    Err(d) =>
      fail(
        "min>max 不应导致解析失败：" + @moongpx.format_diagnostics(d),
      )
  }
}

///|
test "非法 time 被拒绝" {
  for
    t in [
      "2026-13-01T00:00:00Z", "2026-02-30T00:00:00Z", "2026-09-17 01:00:00Z", "2026-09-17T25:00:00Z",
      "26-09-17T01:00:00Z",
    ] {
    let src = "<gpx version=\"1.1\" creator=\"x\"><metadata><time>" +
      t +
      "</time></metadata></gpx>"
    match @moongpx.parse_gpx(src) {
      Ok(_) => fail("非法 dateTime 应被拒绝：" + t)
      Err(d) => assert_true(contains_code(d, @moongpx.code_invalid_datetime))
    }
  }
}

///|
test "合法 time 被接受" {
  for
    t in [
      "2026-09-17T01:00:00Z", "2026-09-17T01:00:00", "2026-09-17T01:00:00.123Z",
      "2026-09-17T01:00:00+08:00", "2024-02-29T00:00:00Z",
    ] {
    let src = "<gpx version=\"1.1\" creator=\"x\"><metadata><time>" +
      t +
      "</time></metadata></gpx>"
    match @moongpx.parse_gpx(src) {
      Ok(_) => ()
      Err(d) =>
        fail(
          "合法 dateTime 被拒：" +
          t +
          " → " +
          @moongpx.format_diagnostics(d),
        )
    }
  }
}

///|
test "extensions 无损保留（含中文与 emoji）" {
  let inner = "<gpxx:WaypointExtension><gpxx:Proximity>10</gpxx:Proximity>" +
    "<foo:note>晨跑🏃 加油</foo:note></gpxx:WaypointExtension>"
  let src = "<gpx version=\"1.1\" creator=\"x\"><wpt lat=\"1\" lon=\"2\">" +
    "<extensions>" +
    inner +
    "</extensions></wpt></gpx>"
  match @moongpx.parse_gpx(src) {
    Ok(g) => {
      assert_eq(g.waypoints.length(), 1)
      match g.waypoints[0].extensions {
        Some(raw) => assert_eq(raw, inner)
        None => fail("wpt/extensions 丢失")
      }
    }
    Err(d) => fail(@moongpx.format_diagnostics(d))
  }
}

///|
test "根级 extensions 无损保留" {
  let inner = "<my:App xmlns:my=\"urn:x\"><my:v>1.5</my:v></my:App>"
  let src = "<gpx version=\"1.1\" creator=\"x\"><extensions>" +
    inner +
    "</extensions></gpx>"
  match @moongpx.parse_gpx(src) {
    Ok(g) =>
      match g.extensions {
        Some(raw) => assert_eq(raw, inner)
        None => fail("根级 extensions 丢失")
      }
    Err(d) => fail(@moongpx.format_diagnostics(d))
  }
}

///|
test "trk / trkseg / trkpt 完整解析" {
  let src = "<gpx version=\"1.1\" creator=\"x\"><trk><name>早跑</name><number>1</number>" +
    "<trkseg><trkpt lat=\"31.1\" lon=\"121.1\"><ele>4</ele></trkpt>" +
    "<trkpt lat=\"31.2\" lon=\"121.2\"><ele>5</ele></trkpt></trkseg>" +
    "<trkseg><trkpt lat=\"31.3\" lon=\"121.3\"/></trkseg></trk></gpx>"
  match @moongpx.parse_gpx(src) {
    Ok(g) => {
      assert_eq(g.tracks.length(), 1)
      let t = g.tracks[0]
      assert_eq(t.name, Some("早跑"))
      assert_eq(t.number, Some(1))
      assert_eq(t.segments.length(), 2)
      assert_eq(t.segments[0].points.length(), 2)
      assert_eq(t.segments[1].points.length(), 1)
      assert_eq(t.segments[1].points[0].lat.to_double(), 31.3)
    }
    Err(d) => fail(@moongpx.format_diagnostics(d))
  }
}

///|
test "rte / rtept 完整解析" {
  let src = "<gpx version=\"1.1\" creator=\"x\"><rte><name>路线</name>" +
    "<rtept lat=\"31.1\" lon=\"121.1\"/><rtept lat=\"31.2\" lon=\"121.2\"/></rte></gpx>"
  match @moongpx.parse_gpx(src) {
    Ok(g) => {
      assert_eq(g.routes.length(), 1)
      assert_eq(g.routes[0].name, Some("路线"))
      assert_eq(g.routes[0].points.length(), 2)
    }
    Err(d) => fail(@moongpx.format_diagnostics(d))
  }
}

///|
test "诊断带准确的行列号" {
  // 第 2 行的 wpt 缺 lat
  let src = "<gpx version=\"1.1\" creator=\"x\">\n  <wpt lon=\"2\"/>\n</gpx>"
  match @moongpx.parse_gpx(src) {
    Ok(_) => fail("应报错")
    Err(d) => {
      assert_true(d.length() > 0)
      assert_eq(d[0].line, 2)
      assert_eq(d[0].column, 3)
    }
  }
}

///|
test "XML 语法错误带行号" {
  let src = "<gpx version=\"1.1\" creator=\"x\">\n  <wpt lat=\"1\" lon=\"2\">\n</gpx>"
  match @moongpx.parse_gpx(src) {
    Ok(_) => fail("XML 不闭合应报错")
    Err(d) => {
      assert_true(contains_code(d, @moongpx.code_xml_parse_error))
      assert_true(d[0].line >= 1)
    }
  }
}

///|
test "错误信息里能看到原始值" {
  let src = "<gpx version=\"1.1\" creator=\"x\"><wpt lat=\"abc\" lon=\"2\"/></gpx>"
  match @moongpx.parse_gpx(src) {
    Ok(_) => fail("非法 lat 应被拒绝")
    Err(d) => {
      let text = @moongpx.format_diagnostics(d)
      assert_true(text.contains("abc"))
    }
  }
}

///|
test "has_errors 区分错误与警告" {
  let src = "<gpx version=\"1.1\" creator=\"x\"><wpt lat=\"1\" lon=\"2\"/></gpx>"
  match @moongpx.parse_gpx(src) {
    Ok(_) => ()
    Err(d) => fail(@moongpx.format_diagnostics(d))
  }
  let errs : Array[@moongpx.Diagnostic] = [
    @moongpx.Diagnostic::warning("W1", "w", 1, 1),
  ]
  assert_eq(@moongpx.has_errors(errs), false)
  errs.push(@moongpx.Diagnostic::error("E1", "e", 1, 1))
  assert_eq(@moongpx.has_errors(errs), true)
}

///|
test "诊断列表可格式化" {
  let diags : Array[@moongpx.Diagnostic] = [
    @moongpx.Diagnostic::error("E1", "出错了", 3, 7),
  ]
  let text = @moongpx.format_diagnostics(diags)
  assert_true(text.contains("3:7"))
  assert_true(text.contains("E1"))
  assert_true(text.contains("出错了"))
}
