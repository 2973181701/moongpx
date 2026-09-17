///|
/// `xsd:dateTime` 校验。
///
/// GPX 里 `metadata/time`、`wpt/time` 都是 `xsd:dateTime`。
/// 这个类型有很多细节容易被忽略：年份至少 4 位、月日时分的范围、
/// 小数秒、时区（`Z` 或 `±hh:mm`）——**时区可以完全省略**，但一旦出现必须合法。

///|
fn read_digits_at(codes : Array[Int], pos : Int, count : Int) -> Int? {
  if pos + count > codes.length() {
    return None
  }
  let mut v = 0
  let mut i = 0
  while i < count {
    let c = codes[pos + i]
    if !is_digit_code(c) {
      return None
    }
    v = v * 10 + (c - 0x30)
    i = i + 1
  }
  Some(v)
}

///|
fn is_leap_year(y : Int) -> Bool {
  (y % 4 == 0 && y % 100 != 0) || y % 400 == 0
}

///|
fn days_in_month(y : Int, m : Int) -> Int {
  if m == 1 || m == 3 || m == 5 || m == 7 || m == 8 || m == 10 || m == 12 {
    31
  } else if m == 4 || m == 6 || m == 9 || m == 11 {
    30
  } else if m == 2 {
    if is_leap_year(y) {
      29
    } else {
      28
    }
  } else {
    0
  }
}

///|
/// 校验 `xsd:dateTime` 字面量。
///
/// 词法形式：
///
/// ```text
/// -? YYYY(YYYY*) '-' MM '-' DD 'T' hh ':' mm ':' ss ('.' s+)? ( 'Z' | ('+'|'-') hh ':' mm )?
/// ```
///
/// 注意：
/// - 年份**至少 4 位**，可以是负数（公元前）
/// - 分隔符 `T` 是**大写字母**，不接受空格
/// - 时区**可以省略**；省略时表示"无时区"
/// - 小数秒至少一位，位数不限
/// - 闰秒允许 `ss = 60`
pub fn is_valid_datetime(text : String) -> Bool {
  let codes = codes_of(text)
  let n = codes.length()
  let mut p = 0
  // 可选的负号（公元前）
  if p < n && codes[p] == 0x2D {
    p = p + 1
  }
  // 年份：至少 4 位数字
  let year_start = p
  while p < n && is_digit_code(codes[p]) {
    p = p + 1
  }
  let year_digits = p - year_start
  if year_digits < 4 {
    return false
  }
  let year = read_digits_at(codes, year_start, year_digits)
  let year = match year {
    Some(v) => v
    None => return false
  }
  // '-'
  if p >= n || codes[p] != 0x2D {
    return false
  }
  p = p + 1
  // 月
  let month = match read_digits_at(codes, p, 2) {
    Some(v) => v
    None => return false
  }
  p = p + 2
  if month < 1 || month > 12 {
    return false
  }
  if p >= n || codes[p] != 0x2D {
    return false
  }
  p = p + 1
  // 日
  let day = match read_digits_at(codes, p, 2) {
    Some(v) => v
    None => return false
  }
  p = p + 2
  if day < 1 || day > days_in_month(year, month) {
    return false
  }
  // 'T'
  if p >= n || codes[p] != 0x54 {
    return false
  }
  p = p + 1
  // 时
  let hour = match read_digits_at(codes, p, 2) {
    Some(v) => v
    None => return false
  }
  p = p + 2
  if hour > 23 {
    return false
  }
  if p >= n || codes[p] != 0x3A {
    return false
  }
  p = p + 1
  // 分
  let minute = match read_digits_at(codes, p, 2) {
    Some(v) => v
    None => return false
  }
  p = p + 2
  if minute > 59 {
    return false
  }
  if p >= n || codes[p] != 0x3A {
    return false
  }
  p = p + 1
  // 秒（允许闰秒 60）
  let second = match read_digits_at(codes, p, 2) {
    Some(v) => v
    None => return false
  }
  p = p + 2
  if second > 60 {
    return false
  }
  // 可选小数秒
  if p < n && codes[p] == 0x2E {
    p = p + 1
    let frac_start = p
    while p < n && is_digit_code(codes[p]) {
      p = p + 1
    }
    if p == frac_start {
      // 有小数点却没有任何数字
      return false
    }
  }
  // 可选时区
  if p < n {
    let c = codes[p]
    if c == 0x5A {
      // 'Z'
      p = p + 1
    } else if c == 0x2B || c == 0x2D {
      p = p + 1
      let tz_hour = match read_digits_at(codes, p, 2) {
        Some(v) => v
        None => return false
      }
      p = p + 2
      if p >= n || codes[p] != 0x3A {
        return false
      }
      p = p + 1
      let tz_min = match read_digits_at(codes, p, 2) {
        Some(v) => v
        None => return false
      }
      p = p + 2
      // XSD 的时区范围是 -14:00 ~ +14:00
      if tz_hour > 14 || tz_min > 59 {
        return false
      }
      if tz_hour == 14 && tz_min != 0 {
        return false
      }
    } else {
      return false
    }
  }
  // 必须恰好消费完
  p == n
}
