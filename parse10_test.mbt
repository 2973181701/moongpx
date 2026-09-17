///|
/// GPX 1.0 解析与升级的黑盒测试。
///
/// 重点验证 1.0 → 1.1 的**迁移映射**是否真的做了转换，
/// 而不只是把元素读进来（email 拆分、url→link、course/speed→extensions）。

///|
fn diag_has_code(diags : Array[@moongpx.Diagnostic], code : String) -> Bool {
  for d in diags {
    if d.code == code {
      return true
    }
  }
  false
}

///|
fn parse10_ok(src : String) -> @moongpx.Gpx raise {
  match @moongpx.parse_gpx_1_0(src) {
    Ok(g) => g
    Err(d) => fail("1.0 解析失败：\n" + @moongpx.format_diagnostics(d))
  }
}

///|
let full_1_0 : String = "<gpx version=\"1.0\" creator=\"test\">" +
  "<name>轨迹名</name><desc>描述</desc>" +
  "<author>张三</author><email>zhangsan@example.com</email>" +
  "<url>http://example.com</url><urlname>示例</urlname>" +
  "<time>2020-01-01T00:00:00Z</time><keywords>徒步,测试</keywords>" +
  "<bounds minlat=\"0\" minlon=\"0\" maxlat=\"10\" maxlon=\"10\"/>" +
  "<wpt lat=\"1\" lon=\"2\"><ele>100</ele><name>起点</name></wpt>" +
  "<trk><name>主轨迹</name><trkseg>" +
  "<trkpt lat=\"1\" lon=\"2\"><ele>100</ele><time>2020-01-01T00:00:00Z</time>" +
  "<course>45.5</course><speed>1.25</speed></trkpt>" +
  "</trkseg></trk></gpx>"

// ── 基线 ──

///|
test "最小 1.0 文档" {
  let g = parse10_ok("<gpx version=\"1.0\" creator=\"x\"></gpx>")
  assert_eq(g.creator, "x")
  assert_eq(g.waypoints.length(), 0)
}

///|
test "解析结果已升级为 1.1 模型" {
  let g = parse10_ok("<gpx version=\"1.0\" creator=\"x\"></gpx>")
  // 迁移是单向的：产出的模型一定是 1.1，可以直接交给 to_gpx
  assert_eq(g.version, "1.1")
}

///|
test "version 不是 1.0 会被拒" {
  let src = "<gpx version=\"1.1\" creator=\"x\"></gpx>"
  match @moongpx.parse_gpx_1_0(src) {
    Ok(_) => fail("1.0 入口不该接受 version=1.1")
    Err(d) => assert_true(diag_has_code(d, @moongpx.code_version_not_1_0))
  }
}

///|
test "1.0 文档走 1.1 入口会被拒——两个入口互不越界" {
  let src = "<gpx version=\"1.0\" creator=\"x\"></gpx>"
  match @moongpx.parse_gpx(src) {
    Ok(_) => fail("1.1 入口不该接受 version=1.0")
    Err(d) => assert_true(diag_has_code(d, @moongpx.code_version_not_1_1))
  }
}

///|
test "creator 必填" {
  match @moongpx.parse_gpx_1_0("<gpx version=\"1.0\"></gpx>") {
    Ok(_) => fail("缺 creator 应被拒")
    Err(d) => assert_true(diag_has_code(d, @moongpx.code_creator_missing))
  }
}

// ── 根级元数据 → Metadata ──

///|
test "1.0 的根级元数据被收进 metadata" {
  let g = parse10_ok(full_1_0)
  match g.metadata {
    None => fail("应由根级元素合成 metadata")
    Some(m) => {
      assert_eq(m.name, Some("轨迹名"))
      assert_eq(m.desc, Some("描述"))
      assert_eq(m.time, Some("2020-01-01T00:00:00Z"))
      assert_eq(m.keywords, Some("徒步,测试"))
      assert_eq(m.bounds is None, false)
    }
  }
}

///|
test "email 整串地址被拆成 id + domain" {
  let g = parse10_ok(full_1_0)
  match g.metadata {
    None => fail("应有 metadata")
    Some(m) =>
      match m.author {
        None => fail("应有 author")
        Some(p) =>
          match p.email {
            None => fail("应有 email")
            Some(e) => {
              assert_eq(e.id, "zhangsan")
              assert_eq(e.domain, "example.com")
            }
          }
      }
  }
}

///|
test "author 纯文本变成 personType.name" {
  let g = parse10_ok(full_1_0)
  match g.metadata {
    None => fail("应有 metadata")
    Some(m) =>
      match m.author {
        None => fail("应有 author")
        Some(p) => assert_eq(p.name, Some("张三"))
      }
  }
}

///|
test "只有 email 没有 author 时也会建 person" {
  let g = parse10_ok(
    "<gpx version=\"1.0\" creator=\"x\"><email>a@b.com</email></gpx>",
  )
  match g.metadata {
    None => fail("应有 metadata")
    Some(m) =>
      match m.author {
        None => fail("仅 email 也应建出 person，否则邮箱会丢")
        Some(p) => {
          assert_eq(p.name, None)
          match p.email {
            None => fail("应有 email")
            Some(e) => {
              assert_eq(e.id, "a")
              assert_eq(e.domain, "b.com")
            }
          }
        }
      }
  }
}

///|
test "没有 @ 时整个串当 id，不静默丢弃" {
  let g = parse10_ok(
    "<gpx version=\"1.0\" creator=\"x\"><email>malformed</email></gpx>",
  )
  match g.metadata {
    None => fail("应有 metadata")
    Some(m) =>
      match m.author {
        None => fail("应有 author")
        Some(p) =>
          match p.email {
            None => fail("应有 email")
            Some(e) => {
              assert_eq(e.id, "malformed")
              assert_eq(e.domain, "")
            }
          }
      }
  }
}

///|
test "url + urlname 升级为 link" {
  let g = parse10_ok(full_1_0)
  match g.metadata {
    None => fail("应有 metadata")
    Some(m) => {
      assert_eq(m.links.length(), 1)
      assert_eq(m.links[0].href, "http://example.com")
      assert_eq(m.links[0].text, Some("示例"))
    }
  }
}

///|
test "只有 urlname 时 link 的 href 为空串而不是丢掉" {
  let g = parse10_ok(
    "<gpx version=\"1.0\" creator=\"x\"><urlname>示例</urlname></gpx>",
  )
  match g.metadata {
    None => fail("应有 metadata")
    Some(m) => {
      assert_eq(m.links.length(), 1)
      assert_eq(m.links[0].href, "")
      assert_eq(m.links[0].text, Some("示例"))
    }
  }
}

// ── 点位 ──

///|
test "wpt 的位置与描述字段" {
  let g = parse10_ok(full_1_0)
  assert_eq(g.waypoints.length(), 1)
  assert_eq(g.waypoints[0].ele, Some(100.0))
  assert_eq(g.waypoints[0].name, Some("起点"))
  assert_eq(g.waypoints[0].lat.to_double(), 1.0)
  assert_eq(g.waypoints[0].lon.to_double(), 2.0)
}

///|
test "trkpt 的 course / speed 保留进 extensions" {
  let g = parse10_ok(full_1_0)
  let pt = g.tracks[0].segments[0].points[0]
  assert_eq(pt.extensions, Some("<course>45.5</course><speed>1.25</speed>"))
}

///|
test "只有 course 时只生成 course" {
  let g = parse10_ok(
    "<gpx version=\"1.0\" creator=\"x\"><trk><trkseg>" +
    "<trkpt lat=\"1\" lon=\"2\"><course>90</course></trkpt>" +
    "</trkseg></trk></gpx>",
  )
  assert_eq(
    g.tracks[0].segments[0].points[0].extensions,
    Some("<course>90</course>"),
  )
}

///|
test "没有 course/speed 时 extensions 是 None" {
  let g = parse10_ok(
    "<gpx version=\"1.0\" creator=\"x\"><trk><trkseg>" +
    "<trkpt lat=\"1\" lon=\"2\"><ele>5</ele></trkpt>" +
    "</trkseg></trk></gpx>",
  )
  assert_eq(g.tracks[0].segments[0].points[0].extensions, None)
}

///|
test "rte 的 rtept 与 number" {
  let g = parse10_ok(
    "<gpx version=\"1.0\" creator=\"x\"><rte><name>路线</name><number>3</number>" +
    "<rtept lat=\"1\" lon=\"2\"><name>A</name></rtept>" +
    "<rtept lat=\"3\" lon=\"4\"><name>B</name></rtept>" +
    "</rte></gpx>",
  )
  assert_eq(g.routes.length(), 1)
  assert_eq(g.routes[0].number, Some(3))
  assert_eq(g.routes[0].points.length(), 2)
  assert_eq(g.routes[0].points[1].name, Some("B"))
}

///|
test "1.0 的 wpt 不支持精度字段，读到也归 None" {
  // 1.0 schema 里 wpt 没有 <fix>，这里确认升级后的模型该字段确实是空的
  let g = parse10_ok(
    "<gpx version=\"1.0\" creator=\"x\"><wpt lat=\"1\" lon=\"2\"></wpt></gpx>",
  )
  assert_eq(g.waypoints[0].fix, None)
  assert_eq(g.waypoints[0].sat, None)
}

// ── 顺序校验 ──

///|
test "1.0 根元素顺序错会报 E1005" {
  // 1.0 里 wpt 必须排在元数据之后
  let src = "<gpx version=\"1.0\" creator=\"x\">" +
    "<wpt lat=\"1\" lon=\"2\"></wpt><name>后写的名字</name></gpx>"
  match @moongpx.parse_gpx_1_0(src) {
    Ok(_) => fail("顺序错应被拒")
    Err(d) => assert_true(diag_has_code(d, @moongpx.code_root_order))
  }
}

///|
test "1.0 的 wpt 子元素顺序错会报 E1013" {
  // 1.0 的 wpt 顺序是 ele → time → name
  let src = "<gpx version=\"1.0\" creator=\"x\">" +
    "<wpt lat=\"1\" lon=\"2\"><name>n</name><ele>1</ele></wpt></gpx>"
  match @moongpx.parse_gpx_1_0(src) {
    Ok(_) => fail("顺序错应被拒")
    Err(d) => assert_true(diag_has_code(d, @moongpx.code_wpt_order))
  }
}

// ── 自动分派 ──

///|
test "parse_gpx_any 对 1.0 走 1.0 入口" {
  let g = match
    @moongpx.parse_gpx_any(
      "<gpx version=\"1.0\" creator=\"x\"><name>n</name></gpx>",
    ) {
    Ok(g) => g
    Err(d) => fail(@moongpx.format_diagnostics(d))
  }
  // 走的是 1.0 路径：根级 <name> 被收进 metadata
  match g.metadata {
    None => fail("1.0 路径应合成 metadata")
    Some(m) => assert_eq(m.name, Some("n"))
  }
}

///|
test "parse_gpx_any 对 1.1 走 1.1 入口" {
  let g = match
    @moongpx.parse_gpx_any(
      "<gpx version=\"1.1\" creator=\"x\"><wpt lat=\"1\" lon=\"2\"></wpt></gpx>",
    ) {
    Ok(g) => g
    Err(d) => fail(@moongpx.format_diagnostics(d))
  }
  assert_eq(g.waypoints.length(), 1)
  // 1.1 没写 metadata，就不该凭空造一个
  assert_eq(g.metadata is None, true)
}

///|
test "detect_gpx_version 读出原始 version 字符串" {
  assert_eq(
    @moongpx.detect_gpx_version("<gpx version=\"1.0\" creator=\"x\"></gpx>"),
    Some("1.0"),
  )
  assert_eq(
    @moongpx.detect_gpx_version("<gpx version=\"1.1\" creator=\"x\"></gpx>"),
    Some("1.1"),
  )
  assert_eq(@moongpx.detect_gpx_version("<gpx creator=\"x\"></gpx>"), None)
  assert_eq(@moongpx.detect_gpx_version("不是 XML"), None)
}
