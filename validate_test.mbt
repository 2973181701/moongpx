///|
/// 独立校验入口 `validate_gpx` 的黑盒测试。
///
/// 重点验证三件事：
/// 1. **warning 只在 validate 里出现**——`parse_gpx` 成功路径上会丢掉它们
/// 2. **不中断**——一个文件里的多个问题（error + warning 混合）一次性全部报出
/// 3. **分级**——`Error` = 违反 schema，`Warning` = 合法但可疑

///|
fn has_code(diags : Array[@moongpx.Diagnostic], code : String) -> Bool {
  for d in diags {
    if d.code == code {
      return true
    }
  }
  false
}

///|
fn count_code(diags : Array[@moongpx.Diagnostic], code : String) -> Int {
  let mut n = 0
  for d in diags {
    if d.code == code {
      n = n + 1
    }
  }
  n
}

///|
fn count_sev(
  diags : Array[@moongpx.Diagnostic],
  sev : @moongpx.Severity,
) -> Int {
  let mut n = 0
  for d in diags {
    if d.severity == sev {
      n = n + 1
    }
  }
  n
}

///|
fn doc(body : String) -> String {
  "<gpx version=\"1.1\" creator=\"moongpx\">" + body + "</gpx>"
}

///|
fn doc_md(md : String, body : String) -> String {
  "<gpx version=\"1.1\" creator=\"moongpx\"><metadata>" +
  md +
  "</metadata>" +
  body +
  "</gpx>"
}

// ── 基线：干净文档 ──

///|
test "干净文档：空数组，is_valid 为真" {
  let src = doc("<wpt lat=\"1.5\" lon=\"2.5\"></wpt>")
  let diags = @moongpx.validate_gpx(src)
  assert_eq(diags.length(), 0)
  assert_eq(@moongpx.is_valid_gpx(src), true)
  assert_eq(@moongpx.has_schema_errors(src), false)
}

///|
test "干净文档：报告不会返回空串" {
  let src = doc("<wpt lat=\"1.5\" lon=\"2.5\"></wpt>")
  let r = @moongpx.validate_gpx_report(src)
  assert_eq(r.length() > 0, true)
  assert_eq(r.has_prefix("没有问题"), true)
}

///|
test "最小空文档也算干净" {
  let src = "<gpx version=\"1.1\" creator=\"x\"></gpx>"
  assert_eq(@moongpx.is_valid_gpx(src), true)
}

// ── W1001 bounds 顺序 ──

///|
test "W1001 bounds 的 min 大于 max" {
  let src = doc_md(
    "<bounds minlat=\"20\" minlon=\"0\" maxlat=\"10\" maxlon=\"10\"/>", "",
  )
  let diags = @moongpx.validate_gpx(src)
  assert_eq(has_code(diags, @moongpx.code_bounds_order), true)
  assert_eq(count_sev(diags, @moongpx.Error), 0)
  // 警告不应导致解析失败
  assert_eq(@moongpx.parse_gpx(src) is Ok(_), true)
}

// ── W1002 时间不单调 ──

///|
test "W1002 同一 trkseg 内时间倒流" {
  let src = doc(
    "<trk><trkseg>" +
    "<trkpt lat=\"1\" lon=\"1\"><time>2020-01-01T00:00:10Z</time></trkpt>" +
    "<trkpt lat=\"2\" lon=\"2\"><time>2020-01-01T00:00:05Z</time></trkpt>" +
    "</trkseg></trk>",
  )
  let diags = @moongpx.validate_gpx(src)
  assert_eq(has_code(diags, @moongpx.code_time_not_monotonic), true)
  // 时间递增是正常的，同一个点不会被误判为重复
  assert_eq(has_code(diags, @moongpx.code_duplicate_point), false)
}

///|
test "时间递增不报 W1002" {
  let src = doc(
    "<trk><trkseg>" +
    "<trkpt lat=\"1\" lon=\"1\"><time>2020-01-01T00:00:05Z</time></trkpt>" +
    "<trkpt lat=\"2\" lon=\"2\"><time>2020-01-01T00:00:10Z</time></trkpt>" +
    "</trkseg></trk>",
  )
  assert_eq(
    has_code(@moongpx.validate_gpx(src), @moongpx.code_time_not_monotonic),
    false,
  )
}

///|
test "W1002 跨时区也能正确比较" {
  // 09:00+08:00 == 01:00Z，时间其实在倒退，字符串比较会看不出来
  let src = doc(
    "<trk><trkseg>" +
    "<trkpt lat=\"1\" lon=\"1\"><time>2020-01-01T09:00:00+08:00</time></trkpt>" +
    "<trkpt lat=\"2\" lon=\"2\"><time>2020-01-01T00:30:00Z</time></trkpt>" +
    "</trkseg></trk>",
  )
  assert_eq(
    has_code(@moongpx.validate_gpx(src), @moongpx.code_time_not_monotonic),
    true,
  )
}

// ── W1003 相邻点重合 ──

///|
test "W1003 相邻轨迹点完全相同" {
  let src = doc(
    "<trk><trkseg>" +
    "<trkpt lat=\"1\" lon=\"1\"><ele>10</ele><time>2020-01-01T00:00:00Z</time></trkpt>" +
    "<trkpt lat=\"1\" lon=\"1\"><ele>10</ele><time>2020-01-01T00:00:01Z</time></trkpt>" +
    "</trkseg></trk>",
  )
  let diags = @moongpx.validate_gpx(src)
  assert_eq(has_code(diags, @moongpx.code_duplicate_point), true)
  assert_eq(has_code(diags, @moongpx.code_time_not_monotonic), false)
}

///|
test "经纬度相同但海拔不同不算重复点" {
  let src = doc(
    "<trk><trkseg>" +
    "<trkpt lat=\"1\" lon=\"1\"><ele>10</ele><time>2020-01-01T00:00:00Z</time></trkpt>" +
    "<trkpt lat=\"1\" lon=\"1\"><ele>20</ele><time>2020-01-01T00:00:01Z</time></trkpt>" +
    "</trkseg></trk>",
  )
  assert_eq(
    has_code(@moongpx.validate_gpx(src), @moongpx.code_duplicate_point),
    false,
  )
}

// ── W1004 fix 与 sat 矛盾 ──

///|
test "W1004 fix=none 却有卫星数" {
  let src = doc("<wpt lat=\"1\" lon=\"1\"><fix>none</fix><sat>9</sat></wpt>")
  assert_eq(
    has_code(@moongpx.validate_gpx(src), @moongpx.code_fix_sat_conflict),
    true,
  )
}

///|
test "W1004 fix=3d 却 sat=0" {
  let src = doc("<wpt lat=\"1\" lon=\"1\"><fix>3d</fix><sat>0</sat></wpt>")
  assert_eq(
    has_code(@moongpx.validate_gpx(src), @moongpx.code_fix_sat_conflict),
    true,
  )
}

///|
test "fix 与 sat 自洽时不报警" {
  for case in [("none", "0"), ("2d", "4"), ("3d", "9")] {
    let (f, s) = case
    let src = doc(
      "<wpt lat=\"1\" lon=\"1\"><fix>" + f + "</fix><sat>" + s + "</sat></wpt>",
    )
    assert_eq(
      has_code(@moongpx.validate_gpx(src), @moongpx.code_fix_sat_conflict),
      false,
    )
  }
}

// ── W1005 海拔不合理 ──

///|
test "W1005 海拔超出地球表面范围" {
  for ele in ["99999", "-20000"] {
    let src = doc("<wpt lat=\"1\" lon=\"1\"><ele>" + ele + "</ele></wpt>")
    let diags = @moongpx.validate_gpx(src)
    assert_eq(has_code(diags, @moongpx.code_elevation_implausible), true)
    // 只是可疑，不是不合规
    assert_eq(count_sev(diags, @moongpx.Error), 0)
  }
}

///|
test "W1005 珠峰与死海都在合理范围内" {
  for ele in ["8848.86", "-430.5", "0"] {
    let src = doc("<wpt lat=\"1\" lon=\"1\"><ele>" + ele + "</ele></wpt>")
    assert_eq(
      has_code(@moongpx.validate_gpx(src), @moongpx.code_elevation_implausible),
      false,
    )
  }
}

// ── W1006 空段 ──

///|
test "W1006 空的 trk / trkseg / rte" {
  let cases = [
    doc("<trk><name>x</name></trk>"),
    doc("<trk><trkseg></trkseg></trk>"),
    doc("<rte><name>x</name></rte>"),
  ]
  for src in cases {
    let diags = @moongpx.validate_gpx(src)
    assert_eq(has_code(diags, @moongpx.code_empty_segment), true)
    assert_eq(count_sev(diags, @moongpx.Error), 0)
  }
}

///|
test "空 trkseg 只报一条（trk 自身不重复报）" {
  let src = doc("<trk><trkseg></trkseg></trk>")
  assert_eq(
    count_code(@moongpx.validate_gpx(src), @moongpx.code_empty_segment),
    1,
  )
}

///|
test "有点的段不报 W1006" {
  let src = doc(
    "<trk><trkseg><trkpt lat=\"1\" lon=\"1\"></trkpt></trkseg></trk>" +
    "<rte><rtept lat=\"2\" lon=\"2\"></rtept></rte>",
  )
  assert_eq(
    has_code(@moongpx.validate_gpx(src), @moongpx.code_empty_segment),
    false,
  )
}

// ── W1007 点位越界 ──

///|
fn bounded(body : String) -> String {
  doc_md(
    "<bounds minlat=\"0\" minlon=\"0\" maxlat=\"10\" maxlon=\"10\"/>", body,
  )
}

///|
test "W1007 点位落在 bounds 之外" {
  let src = bounded("<wpt lat=\"50\" lon=\"50\"></wpt>")
  assert_eq(
    has_code(@moongpx.validate_gpx(src), @moongpx.code_out_of_bounds),
    true,
  )
}

///|
test "W1007 轨迹点同样会被检查" {
  let src = bounded(
    "<trk><trkseg><trkpt lat=\"-30\" lon=\"5\"></trkpt></trkseg></trk>",
  )
  assert_eq(
    has_code(@moongpx.validate_gpx(src), @moongpx.code_out_of_bounds),
    true,
  )
}

///|
test "点位在 bounds 边界上不报警" {
  // 边界值视为包含：min 与 max 本身都不算越界
  for p in [("0", "0"), ("10", "10"), ("5", "5")] {
    let (lat, lon) = p
    let src = bounded("<wpt lat=\"" + lat + "\" lon=\"" + lon + "\"></wpt>")
    assert_eq(
      has_code(@moongpx.validate_gpx(src), @moongpx.code_out_of_bounds),
      false,
    )
  }
}

///|
test "没有声明 bounds 时不检查越界" {
  let src = doc("<wpt lat=\"50\" lon=\"50\"></wpt>")
  assert_eq(@moongpx.is_valid_gpx(src), true)
}

// ── 核心行为：不中断 + warning 不阻塞解析 ──

///|
test "多个问题一次性全部报出（error 与 warning 混合）" {
  let src = doc(
    "<wpt lat=\"1\" lon=\"1\"><ele>99999</ele><fix>bogus</fix></wpt>" +
    "<wpt lat=\"2\" lon=\"2\"><fix>none</fix><sat>9</sat></wpt>" +
    "<trk><name>empty</name></trk>",
  )
  let diags = @moongpx.validate_gpx(src)
  // E1016 非法 fix；W1005 海拔；W1004 fix/sat 矛盾；W1006 空 trk
  assert_eq(has_code(diags, @moongpx.code_invalid_fix), true)
  assert_eq(has_code(diags, @moongpx.code_elevation_implausible), true)
  assert_eq(has_code(diags, @moongpx.code_fix_sat_conflict), true)
  assert_eq(has_code(diags, @moongpx.code_empty_segment), true)
  assert_eq(diags.length(), 4)
  assert_eq(count_sev(diags, @moongpx.Error), 1)
  assert_eq(count_sev(diags, @moongpx.Warning), 3)
}

///|
test "只有 warning 时 parse_gpx 依然成功" {
  let src = doc("<wpt lat=\"1\" lon=\"1\"><ele>99999</ele></wpt>")
  let diags = @moongpx.validate_gpx(src)
  assert_eq(diags.length(), 1)
  assert_eq(count_sev(diags, @moongpx.Error), 0)
  // 解析不受影响
  assert_eq(@moongpx.parse_gpx(src) is Ok(_), true)
  // 但严格口径下不算"完全合格"
  assert_eq(@moongpx.is_valid_gpx(src), false)
  assert_eq(@moongpx.has_schema_errors(src), false)
}

///|
test "有 error 时 validate 照常报出，且不丢模型之外的信息" {
  let src = "<gpx version=\"1.0\" creator=\"x\"></gpx>"
  let diags = @moongpx.validate_gpx(src)
  assert_eq(has_code(diags, @moongpx.code_version_not_1_1), true)
  assert_eq(@moongpx.has_schema_errors(src), true)
  assert_eq(@moongpx.is_valid_gpx(src), false)
}

///|
test "XML 语法坏了只能报一条" {
  let src = "<gpx version=\"1.1\" creator=\"x\">"
  let diags = @moongpx.validate_gpx(src)
  assert_eq(has_code(diags, @moongpx.code_xml_parse_error), true)
  assert_eq(count_sev(diags, @moongpx.Error), 1)
}

// ── 工具函数 ──

///|
test "diagnostics_of_severity 按级别筛选" {
  let src = doc(
    "<wpt lat=\"1\" lon=\"1\"><ele>99999</ele><fix>bogus</fix></wpt>" +
    "<trk><name>empty</name></trk>",
  )
  let diags = @moongpx.validate_gpx(src)
  let errs = @moongpx.diagnostics_of_severity(diags, @moongpx.Error)
  let warns = @moongpx.diagnostics_of_severity(diags, @moongpx.Warning)
  assert_eq(errs.length(), 1)
  assert_eq(warns.length(), 2)
  assert_eq(errs.length() + warns.length(), diags.length())
}

///|
test "报告会同时给出条数与明细" {
  let src = doc("<wpt lat=\"1\" lon=\"1\"><ele>99999</ele></wpt>")
  let r = @moongpx.validate_gpx_report(src)
  assert_eq(r.has_prefix("共 1 条（0 错误 / 1 警告）"), true)
  assert_eq(r.has_prefix("没有问题"), false)
}

///|
test "每条诊断都带 1-based 行列号" {
  let src = doc("<wpt lat=\"1\" lon=\"1\"><ele>99999</ele></wpt>")
  let diags = @moongpx.validate_gpx(src)
  assert_eq(diags.length(), 1)
  assert_eq(diags[0].line >= 1, true)
  assert_eq(diags[0].column >= 1, true)
}
