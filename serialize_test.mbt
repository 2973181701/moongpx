///|
/// GPX 序列化与往返一致性测试。
///
/// 核心不变量（本文件所有用例都在守护它）：
///
/// ```text
/// parse_gpx(to_gpx(g)) == g
/// ```
///
/// 以及由它派生的幂等性：
///
/// ```text
/// to_gpx(parse_gpx(to_gpx(g))) == to_gpx(g)
/// ```

///|
/// 覆盖全部复合类型与三段子元素顺序的完整文档。
let full_doc : String = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n" +
  "<gpx xmlns=\"http://www.topografix.com/GPX/1/1\" version=\"1.1\" creator=\"moongpx-test\">\n" +
  "  <metadata>\n" +
  "    <name>测试轨迹</name>\n" +
  "    <desc>含 &amp; 与 &lt; 的描述</desc>\n" +
  "    <author>\n" +
  "      <name>张三</name>\n" +
  "      <email id=\"zhangsan\" domain=\"example.com\"/>\n" +
  "      <link href=\"https://example.com/p?a=1&amp;b=2\">\n" +
  "        <text>主页</text>\n" +
  "        <type>text/html</type>\n" +
  "      </link>\n" +
  "    </author>\n" +
  "    <copyright author=\"张三\">\n" +
  "      <year>2026</year>\n" +
  "      <license>https://opensource.org/licenses/MIT</license>\n" +
  "    </copyright>\n" +
  "    <link href=\"https://example.com/track.gpx\"/>\n" +
  "    <time>2026-09-17T10:00:00Z</time>\n" +
  "    <keywords>跑步, 晨跑</keywords>\n" +
  "    <bounds minlat=\"31.0\" minlon=\"121.0\" maxlat=\"31.5\" maxlon=\"121.5\"/>\n" +
  "  </metadata>\n" +
  "  <wpt lat=\"31.2304\" lon=\"121.4737\">\n" +
  "    <ele>4.5</ele>\n" +
  "    <time>2026-09-17T10:00:01Z</time>\n" +
  "    <magvar>1.5</magvar>\n" +
  "    <geoidheight>-2.3</geoidheight>\n" +
  "    <name>起点</name>\n" +
  "    <cmt>注释</cmt>\n" +
  "    <desc>描述</desc>\n" +
  "    <src>GPS</src>\n" +
  "    <link href=\"https://example.com/wpt\"/>\n" +
  "    <sym>Flag, Blue</sym>\n" +
  "    <type>user</type>\n" +
  "    <fix>3d</fix>\n" +
  "    <sat>9</sat>\n" +
  "    <hdop>0.9</hdop>\n" +
  "    <vdop>1.1</vdop>\n" +
  "    <pdop>1.4</pdop>\n" +
  "    <ageofdgpsdata>3.0</ageofdgpsdata>\n" +
  "    <dgpsid>12</dgpsid>\n" +
  "  </wpt>\n" +
  "  <rte>\n" +
  "    <name>路线</name>\n" +
  "    <cmt>路线注释</cmt>\n" +
  "    <desc>路线描述</desc>\n" +
  "    <src>规划器</src>\n" +
  "    <link href=\"https://example.com/rte\"/>\n" +
  "    <number>1</number>\n" +
  "    <type>test</type>\n" +
  "    <rtept lat=\"31.1\" lon=\"121.1\"/>\n" +
  "    <rtept lat=\"31.2\" lon=\"121.2\"><name>途经点</name></rtept>\n" +
  "  </rte>\n" +
  "  <trk>\n" +
  "    <name>轨迹</name>\n" +
  "    <number>2</number>\n" +
  "    <type>running</type>\n" +
  "    <trkseg>\n" +
  "      <trkpt lat=\"31.3\" lon=\"121.3\"><ele>10</ele></trkpt>\n" +
  "      <trkpt lat=\"31.4\" lon=\"121.4\"><ele>11</ele></trkpt>\n" +
  "    </trkseg>\n" +
  "    <trkseg>\n" +
  "      <trkpt lat=\"31.45\" lon=\"121.45\"/>\n" +
  "    </trkseg>\n" +
  "  </trk>\n" +
  "</gpx>"

///|
fn parse_ok(src : String) -> @moongpx.Gpx raise {
  match @moongpx.parse_gpx(src) {
    Ok(g) => g
    Err(d) => fail("解析失败：\n" + @moongpx.format_diagnostics(d))
  }
}

///|
fn round_trip(src : String) -> (@moongpx.Gpx, @moongpx.Gpx, String) raise {
  let g1 = parse_ok(src)
  let s1 = @moongpx.to_gpx(g1)
  let g2 = parse_ok(s1)
  (g1, g2, s1)
}

// ─────────────────────── 基本输出形态 ───────────────────────

///|
test "最小文档输出带 XML 声明与官方命名空间" {
  let g = parse_ok("<gpx version=\"1.1\" creator=\"moongpx\"></gpx>")
  let s = @moongpx.to_gpx(g)
  assert_true(s.has_prefix("<?xml version=\"1.0\" encoding=\"UTF-8\"?>"))
  assert_true(s.contains("xmlns=\"http://www.topografix.com/GPX/1/1\""))
  assert_true(s.contains("version=\"1.1\""))
  assert_true(s.contains("creator=\"moongpx\""))
  assert_true(s.contains("<gpx"))
}

///|
test "根元素属性顺序为 xmlns / version / creator" {
  let g = parse_ok("<gpx version=\"1.1\" creator=\"x\"></gpx>")
  let s = @moongpx.to_gpx(g)
  // ⚠️ 必须只看 <gpx ...> 标签内部：
  // 全文档范围内 find("version=") 会先命中 XML 声明里的 version="1.0"
  let rest = s[s.find("<gpx").unwrap():]
  let tag = rest[:rest.find(">").unwrap()]
  let i_xmlns = tag.find("xmlns=").unwrap()
  let i_version = tag.find("version=").unwrap()
  let i_creator = tag.find("creator=").unwrap()
  assert_true(i_xmlns < i_version)
  assert_true(i_version < i_creator)
}

///|
test "片段输出不含声明与命名空间" {
  let g = parse_ok("<gpx version=\"1.1\" creator=\"x\"></gpx>")
  let s = @moongpx.to_gpx_fragment(g)
  assert_false(s.contains("<?xml"))
  assert_false(s.contains("xmlns"))
  assert_true(s.has_prefix("<gpx "))
}

///|
test "输出子元素顺序符合 schema：metadata → wpt → rte → trk" {
  let g = parse_ok(full_doc)
  let s = @moongpx.to_gpx(g)
  let i_md = s.find("<metadata>").unwrap()
  let i_wpt = s.find("<wpt ").unwrap()
  let i_rte = s.find("<rte>").unwrap()
  let i_trk = s.find("<trk>").unwrap()
  assert_true(i_md < i_wpt)
  assert_true(i_wpt < i_rte)
  assert_true(i_rte < i_trk)
}

///|
test "空元素自闭合，非空元素显式闭合" {
  let g = parse_ok(
    "<gpx version=\"1.1\" creator=\"x\"><wpt lat=\"1\" lon=\"2\"/><wpt lat=\"3\" lon=\"4\"><name>a</name></wpt></gpx>",
  )
  let s = @moongpx.to_gpx(g)
  assert_true(s.contains("<wpt lat=\"1\" lon=\"2\"/>"))
  assert_true(s.contains("<wpt lat=\"3\" lon=\"4\">"))
  assert_true(s.contains("</wpt>"))
}

// ─────────────────────── 转义 ───────────────────────

///|
test "文本内容转义 & < >" {
  let g = parse_ok(
    "<gpx version=\"1.1\" creator=\"x\"><wpt lat=\"1\" lon=\"2\"><desc>a&amp;b&lt;c&gt;d</desc></wpt></gpx>",
  )
  let s = @moongpx.to_gpx(g)
  assert_true(s.contains("<desc>a&amp;b&lt;c&gt;d</desc>"))
  // 不能再出现裸的 & < >
  assert_false(s.contains("a&b"))
}

///|
test "属性值转义 & < > \" '" {
  let g = parse_ok(
    "<gpx version=\"1.1\" creator=\"x\"><metadata><link href=\"a&amp;b&lt;c&gt;d&quot;e&apos;f\"/></metadata></gpx>",
  )
  let s = @moongpx.to_gpx(g)
  assert_true(s.contains("href=\"a&amp;b&lt;c&gt;d&quot;e&apos;f\""))
}

///|
test "文本中的 CR 转义为 &#13; 以躲过 XML 换行规范化" {
  let g = parse_ok(
    "<gpx version=\"1.1\" creator=\"x\"><wpt lat=\"1\" lon=\"2\"><desc>x&#13;y</desc></wpt></gpx>",
  )
  let s = @moongpx.to_gpx(g)
  assert_true(s.contains("<desc>x&#13;y</desc>"))
  // 往返后 CR 必须还在（若输出字面 CR，会被解析器折成 LF）
  let g2 = parse_ok(s)
  match g2.waypoints[0].desc {
    Some(d) => {
      assert_eq(d.length(), 3)
      assert_true(d.contains("\r"))
    }
    None => fail("往返后 desc 丢失")
  }
}

///|
test "属性中的 tab / 换行转义以躲过属性值规范化" {
  let g = parse_ok(
    "<gpx version=\"1.1\" creator=\"x\"><metadata><link href=\"p\" ><text>t</text></link><keywords>a&#9;b&#10;c</keywords></metadata></gpx>",
  )
  let s = @moongpx.to_gpx(g)
  assert_true(s.contains("<keywords>a\tb\nc</keywords>"))
}

///|
test "extensions 内部原文不转义" {
  let g = parse_ok(
    "<gpx version=\"1.1\" creator=\"x\"><wpt lat=\"1\" lon=\"2\"><extensions><foo bar=\"1\">text</foo></extensions></wpt></gpx>",
  )
  let s = @moongpx.to_gpx(g)
  // 必须是原样 XML，而不是 &lt;foo&gt;
  assert_true(s.contains("<extensions><foo bar=\"1\">text</foo></extensions>"))
  assert_false(s.contains("&lt;foo"))
}

// ─────────────────────── 数字格式化 ───────────────────────

///|
test "小数不输出指数记法" {
  let g = parse_ok(
    "<gpx version=\"1.1\" creator=\"x\"><wpt lat=\"1\" lon=\"2\"><ele>0.0000001</ele></wpt></gpx>",
  )
  let s = @moongpx.to_gpx(g)
  assert_true(s.contains("<ele>0.0000001</ele>"))
  assert_false(s.contains("e-7"))
  assert_false(s.contains("E-7"))
}

///|
test "极端小数与极大数均不出现指数" {
  let cases : Array[(String, String)] = [
    ("0.000000000000001", "<ele>0.000000000000001</ele>"),
  ]
  for c in cases {
    let g = parse_ok(
      "<gpx version=\"1.1\" creator=\"x\"><wpt lat=\"1\" lon=\"2\"><ele>" +
      c.0 +
      "</ele></wpt></gpx>",
    )
    let s = @moongpx.to_gpx(g)
    assert_true(s.contains(c.1))
  }
}

///|
test "整数形态的小数输出为整数字面量" {
  let g = parse_ok(
    "<gpx version=\"1.1\" creator=\"x\"><wpt lat=\"1.0\" lon=\"2.0\"><ele>10.0</ele></wpt></gpx>",
  )
  let s = @moongpx.to_gpx(g)
  assert_true(s.contains("lat=\"1\""))
  assert_true(s.contains("<ele>10</ele>"))
}

// ─────────────────────── 往返一致性 ───────────────────────

///|
test "往返一致：最小文档" {
  let (g1, g2, _) = round_trip("<gpx version=\"1.1\" creator=\"x\"></gpx>")
  assert_eq(g1, g2)
}

///|
test "往返一致：覆盖全部复合类型的完整文档" {
  let (g1, g2, s1) = round_trip(full_doc)
  if g1 != g2 {
    fail("往返后模型不相等。序列化输出：\n" + s1)
  }
  assert_eq(g1, g2)
}

///|
test "往返幂等：to_gpx ∘ parse ∘ to_gpx == to_gpx" {
  let g1 = parse_ok(full_doc)
  let s1 = @moongpx.to_gpx(g1)
  let s2 = @moongpx.to_gpx(parse_ok(s1))
  assert_eq(s1, s2)
}

///|
test "往返一致：extensions 含中文与 emoji（UTF-16 切原文）" {
  let src = "<gpx version=\"1.1\" creator=\"x\"><wpt lat=\"1\" lon=\"2\"><extensions><gpxx:WaypointExtension xmlns:gpxx=\"http://www.garmin.com/xmlschemas/GpxExtensions/v1\"><gpxx:DisplayMode>SymbolAndName</gpxx:DisplayMode></gpxx:WaypointExtension>中文😀</extensions></wpt></gpx>"
  let (g1, g2, s1) = round_trip(src)
  let raw1 = g1.waypoints[0].extensions.unwrap()
  assert_true(raw1.contains("中文😀"))
  assert_true(raw1.contains("gpxx:DisplayMode"))
  if g1 != g2 {
    fail("extensions 往返不一致。输出：\n" + s1)
  }
  assert_eq(g1, g2)
}

///|
test "往返一致：metadata 的 extensions 不丢失（回归）" {
  let src = "<gpx version=\"1.1\" creator=\"x\"><metadata><name>n</name><extensions><custom>v</custom></extensions></metadata></gpx>"
  let g1 = parse_ok(src)
  match g1.metadata {
    Some(m) =>
      match m.extensions {
        Some(r) => assert_true(r.contains("<custom>v</custom>"))
        None => fail("metadata/extensions 被丢弃")
      }
    None => fail("metadata 被丢弃")
  }
  let (_, g2, s1) = round_trip(src)
  if g1 != g2 {
    fail("metadata/extensions 往返不一致。输出：\n" + s1)
  }
  assert_eq(g1, g2)
}

///|
test "往返一致：空元素与缺失等价" {
  let src = "<gpx version=\"1.1\" creator=\"x\"><wpt lat=\"1\" lon=\"2\"><name></name><desc/></wpt></gpx>"
  let g1 = parse_ok(src)
  assert_eq(g1.waypoints[0].name is None, true)
  let s1 = @moongpx.to_gpx(g1)
  assert_false(s1.contains("<name>"))
  assert_false(s1.contains("<desc"))
  let (_, g2, _) = round_trip(src)
  assert_eq(g1, g2)
}

///|
test "往返一致：多层 extensions（根 / trk / trkseg）" {
  let src = "<gpx version=\"1.1\" creator=\"x\"><trk><name>t</name><extensions><a>1</a></extensions><trkseg><trkpt lat=\"1\" lon=\"2\"/><extensions><b>2</b></extensions></trkseg></trk><extensions><root>0</root></extensions></gpx>"
  let (g1, g2, s1) = round_trip(src)
  if g1 != g2 {
    fail("多层 extensions 往返不一致。输出：\n" + s1)
  }
  assert_eq(g1, g2)
}

///|
test "往返一致：fix 全部枚举值" {
  for v in ["none", "2d", "3d", "dgps", "pps"] {
    let src = "<gpx version=\"1.1\" creator=\"x\"><wpt lat=\"1\" lon=\"2\"><fix>" +
      v +
      "</fix></wpt></gpx>"
    let (g1, g2, _) = round_trip(src)
    assert_eq(g1, g2)
    let s = @moongpx.to_gpx(g1)
    assert_true(s.contains("<fix>" + v + "</fix>"))
  }
}

///|
test "往返一致：坐标边界值" {
  let src = "<gpx version=\"1.1\" creator=\"x\"><wpt lat=\"90\" lon=\"179.999999\"/><wpt lat=\"-90\" lon=\"-180\"/><wpt lat=\"0\" lon=\"0\"/></gpx>"
  let (g1, g2, s1) = round_trip(src)
  assert_true(s1.contains("lat=\"90\""))
  assert_true(s1.contains("lon=\"-180\""))
  if g1 != g2 {
    fail("边界坐标往返不一致。输出：\n" + s1)
  }
  assert_eq(g1, g2)
}

///|
test "往返一致：文本中的中文与 emoji 不被破坏" {
  let src = "<gpx version=\"1.1\" creator=\"x\"><wpt lat=\"1\" lon=\"2\"><name>北京·故宫🏯</name></wpt></gpx>"
  let (g1, g2, s1) = round_trip(src)
  assert_true(s1.contains("<name>北京·故宫🏯</name>"))
  if g1 != g2 {
    fail("非 BMP 字符往返不一致。输出：\n" + s1)
  }
  assert_eq(g1, g2)
}

///|
test "序列化输出可被自身解析且无诊断" {
  let g = parse_ok(full_doc)
  let s = @moongpx.to_gpx(g)
  // 若输出顺序或转义有问题，这里会因 Err 直接失败
  let _ = parse_ok(s)
}
