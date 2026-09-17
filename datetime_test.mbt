///|
/// `xsd:dateTime` 的可比较性测试。
///
/// 重点是**时区等价**与**跨月/跨闰年**的天数计算——
/// 这两个地方算错不会报错，只会静默给出错误的时间顺序。

///|
fn epoch(text : String) -> Double raise {
  match @moongpx.datetime_to_epoch(text) {
    Some(v) => v
    None => fail("无法解析为 epoch：\{text}")
  }
}

///|
test "纪元基准：1970-01-01T00:00:00Z 为 0" {
  assert_eq(epoch("1970-01-01T00:00:00Z"), 0.0)
  assert_eq(epoch("1970-01-01T00:00:00+00:00"), 0.0)
}

///|
test "已知绝对天数：2000-01-01 为 946684800 秒" {
  assert_eq(epoch("2000-01-01T00:00:00Z"), 946684800.0)
}

///|
test "闰年 2 月 29 日可解析且天数正确" {
  // 2000 是 400 的倍数 → 闰年，2 月有 29 天
  assert_eq(
    epoch("2000-03-01T00:00:00Z") - epoch("2000-02-28T00:00:00Z"),
    172800.0,
  )
  // 1900 是世纪年但不是 400 的倍数 → 平年
  assert_eq(
    epoch("1900-03-01T00:00:00Z") - epoch("1900-02-28T00:00:00Z"),
    86400.0,
  )
}

///|
test "时区折算：同一时刻的不同写法必须相等" {
  assert_eq(epoch("2026-09-17T10:00:00Z"), epoch("2026-09-17T18:00:00+08:00"))
  assert_eq(epoch("2026-09-17T10:00:00Z"), epoch("2026-09-17T11:00:00+01:00"))
  assert_eq(epoch("2026-09-17T10:00:00Z"), epoch("2026-09-17T05:00:00-05:00"))
}

///|
test "字符串字典序会骗人，数值比较不会" {
  // 字典序上这个字符串更大，但两者其实是同一时刻
  assert_true("2026-09-17T18:00:00+08:00" > "2026-09-17T10:00:00Z")
  assert_eq(
    @moongpx.datetime_compare(
      "2026-09-17T18:00:00+08:00", "2026-09-17T10:00:00Z",
    ),
    Some(0),
  )
}

///|
test "跨日期边界的时区折算" {
  // 2026-09-17T23:00:00-08:00 = 2026-09-18T07:00:00Z
  assert_eq(epoch("2026-09-17T23:00:00-08:00"), epoch("2026-09-18T07:00:00Z"))
}

///|
test "不带时区时按 UTC 处理" {
  assert_eq(epoch("2026-09-17T10:00:00"), epoch("2026-09-17T10:00:00Z"))
}

///|
test "小数秒参与比较" {
  assert_eq(
    @moongpx.datetime_compare(
      "2026-09-17T10:00:00.000Z", "2026-09-17T10:00:00.500Z",
    ),
    Some(-1),
  )
  assert_eq(
    epoch("2026-09-17T10:00:00.500Z") - epoch("2026-09-17T10:00:00.000Z"),
    0.5,
  )
}

///|
test "比较：早 / 晚 / 相等" {
  assert_eq(
    @moongpx.datetime_compare("2026-01-01T00:00:00Z", "2027-01-01T00:00:00Z"),
    Some(-1),
  )
  assert_eq(
    @moongpx.datetime_compare("2027-01-01T00:00:00Z", "2026-01-01T00:00:00Z"),
    Some(1),
  )
  assert_eq(
    @moongpx.datetime_compare("2026-06-01T00:00:00Z", "2026-06-01T00:00:00Z"),
    Some(0),
  )
}

///|
test "非法字面量的 epoch 为 None" {
  assert_eq(@moongpx.datetime_to_epoch("2026-09-17"), None)
  assert_eq(@moongpx.datetime_to_epoch("2026-09-17T25:00:00Z"), None)
  assert_eq(@moongpx.datetime_to_epoch("不是时间"), None)
}

///|
test "1 月与 2 月的天数基准（Hinnant 算法最易漏的一步）" {
  // 若漏掉 `m <= 2 时年份减 1`，1970-01-01 会算出 365 而不是 0
  assert_eq(epoch("1970-01-01T00:00:00Z"), 0.0)
  assert_eq(epoch("1970-02-01T00:00:00Z"), 31.0 * 86400.0)
  // 1970-03-01：1 月 31 + 2 月 28
  assert_eq(epoch("1970-03-01T00:00:00Z"), 59.0 * 86400.0)
  assert_eq(epoch("1970-12-31T00:00:00Z"), 364.0 * 86400.0)
}
