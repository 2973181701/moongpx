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

// ─────────────────── 可比较的时间表示 ───────────────────

///|
priv struct DtParts {
  year : Int
  month : Int
  day : Int
  hour : Int
  minute : Int
  second : Int
  /// 小数秒（秒的小数部分）
  frac : Double
  /// 时区偏移（分钟，东为正）。`None` 表示**该字面量没有时区**。
  tz : Int?
}

///|
/// 把 `xsd:dateTime` 拆成各部分。与 `is_valid_datetime` 词法一致，
/// 只是顺手把数值取出来而不做校验——调用方应先 `is_valid_datetime`。
fn parse_dt_parts(text : String) -> DtParts? {
  let codes = codes_of(text)
  let n = codes.length()
  let mut p = 0
  // 可选的负号（公元前）
  let mut negative = false
  if p < n && codes[p] == 0x2D {
    negative = true
    p = p + 1
  }
  let year_start = p
  while p < n && is_digit_code(codes[p]) {
    p = p + 1
  }
  let year_digits = p - year_start
  if year_digits < 4 {
    return None
  }
  let year_mag = match read_digits_at(codes, year_start, year_digits) {
    Some(v) => v
    None => return None
  }
  let year = if negative { -year_mag } else { year_mag }
  if p >= n || codes[p] != 0x2D {
    return None
  }
  p = p + 1
  let month = match read_digits_at(codes, p, 2) {
    Some(v) => v
    None => return None
  }
  p = p + 2
  if p >= n || codes[p] != 0x2D {
    return None
  }
  p = p + 1
  let day = match read_digits_at(codes, p, 2) {
    Some(v) => v
    None => return None
  }
  p = p + 2
  if p >= n || codes[p] != 0x54 {
    return None
  }
  p = p + 1
  let hour = match read_digits_at(codes, p, 2) {
    Some(v) => v
    None => return None
  }
  p = p + 2
  if p >= n || codes[p] != 0x3A {
    return None
  }
  p = p + 1
  let minute = match read_digits_at(codes, p, 2) {
    Some(v) => v
    None => return None
  }
  p = p + 2
  if p >= n || codes[p] != 0x3A {
    return None
  }
  p = p + 1
  let second = match read_digits_at(codes, p, 2) {
    Some(v) => v
    None => return None
  }
  p = p + 2
  // 小数秒：取前 9 位已远超 Double 的实用精度
  let mut frac = 0.0
  if p < n && codes[p] == 0x2E {
    p = p + 1
    let frac_start = p
    while p < n && is_digit_code(codes[p]) {
      p = p + 1
    }
    let mut scale = 0.1
    let mut i = frac_start
    while i < p && i < frac_start + 9 {
      frac = frac + (codes[i] - 0x30).to_double() * scale
      scale = scale * 0.1
      i = i + 1
    }
  }
  // 时区
  let mut tz : Int? = None
  if p < n {
    let c = codes[p]
    if c == 0x5A {
      tz = Some(0)
      p = p + 1
    } else if c == 0x2B || c == 0x2D {
      let neg = c == 0x2D
      p = p + 1
      let tz_hour = match read_digits_at(codes, p, 2) {
        Some(v) => v
        None => return None
      }
      p = p + 2
      if p >= n || codes[p] != 0x3A {
        return None
      }
      p = p + 1
      let tz_min = match read_digits_at(codes, p, 2) {
        Some(v) => v
        None => return None
      }
      p = p + 2
      let total = tz_hour * 60 + tz_min
      tz = Some(if neg { -total } else { total })
    } else {
      return None
    }
  }
  if p != n {
    return None
  }
  Some({ year, month, day, hour, minute, second, frac, tz, })
}

///|
/// 格里历日期 → 自 1970-01-01 起的天数（可为负）。
///
/// Howard Hinnant 的 civil-from-days 逆算法。⚠️ 关键第一步是
/// **`m <= 2` 时先把年份减 1**（把 3 月当成一年的起点），漏掉这一步
/// 会让 1970-01-01 算出 365 而不是 0——差整整一年，且不报错。
/// 地板除。MoonBit 的 `/` 是向零取整，负年份会算错一个 era（整整 400 年）。
fn floor_div(a : Int, b : Int) -> Int {
  let q = a / b
  let r = a % b
  if r != 0 && (r < 0) != (b < 0) {
    q - 1
  } else {
    q
  }
}

///|
fn days_from_civil(y0 : Int, m : Int, d : Int) -> Int {
  let y = if m <= 2 { y0 - 1 } else { y0 }
  let era = floor_div(y, 400)
  let yoe = y - era * 400
  let mp = (m + 9) % 12
  let doy = (153 * mp + 2) / 5 + d - 1
  let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
  era * 146097 + doe - 719468
}

///|
/// 把 `xsd:dateTime` 转成**可比较的数值**：自 Unix 纪元起的秒数。
///
/// 为什么需要它：判断"轨迹点的时间是否递增"不能靠字符串字典序——
/// `2026-09-17T10:00:00Z` 与 `2026-09-17T18:00:00+08:00` 是同一时刻，
/// 但字典序会认为后者更大。有时区时折算到 UTC 再比。
///
/// 无时区时**按 UTC 处理**（`xsd:dateTime` 允许省略时区，含义是"未知本地时"，
/// 本库不做猜测，只保证可比）。
///
/// 自己先做一遍词法校验，非法字面量返回 `None`
/// （`parse_dt_parts` 只抽数字、不查范围，必须先拦住 `25:00:00` 这类）。
pub fn datetime_to_epoch(text : String) -> Double? {
  if !is_valid_datetime(text) {
    return None
  }
  match parse_dt_parts(text) {
    None => None
    Some(p) => {
      let days = days_from_civil(p.year, p.month, p.day)
      let secs = days.to_double() * 86400.0 +
        p.hour.to_double() * 3600.0 +
        p.minute.to_double() * 60.0 +
        p.second.to_double() +
        p.frac
      match p.tz {
        Some(offset_min) => Some(secs - offset_min.to_double() * 60.0)
        None => Some(secs)
      }
    }
  }
}

///|
/// 两个 `xsd:dateTime` 的先后：`-1` = a 早于 b，`0` = 相等，`1` = a 晚于 b。
///
/// 任一方非法（或缺少可比信息）时返回 `None`——**不做猜测**。
pub fn datetime_compare(a : String, b : String) -> Int? {
  match (datetime_to_epoch(a), datetime_to_epoch(b)) {
    (Some(x), Some(y)) =>
      if x < y {
        Some(-1)
      } else if x > y {
        Some(1)
      } else {
        Some(0)
      }
    _ => None
  }
}
