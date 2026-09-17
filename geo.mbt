///|
/// GPX 坐标与数值类型。
///
/// 对应 GPX 1.1 schema 的 `latitudeType` / `longitudeType` / `degreesType` /
/// `dgpsStationType` 四个简单类型。
///
/// 规范来源：https://www.topografix.com/GPX/1/1/gpx.xsd
///
/// **最容易被做错的一点**：纬度和经度的边界规则**不对称**——
/// 纬度是闭区间 `[-90, 90]`，经度是半开区间 `[-180, 180)`。
/// `lat="90"` 合法，`lon="180"` 非法。

///|
/// 坐标 / 数值的解析与范围校验失败原因。
///
/// 每个变体都携带**原始文本**，方便调用方直接拿去做报错信息。
pub(all) enum GeoError {
  /// 不是合法的 `xsd:decimal` 字面量。
  /// 注意：指数记法（`1e2`）、`NaN`、`INF` 都属于**非法**——
  /// 它们是 `xsd:double` 的词法形式，不是 `xsd:decimal`。
  NotADecimal(String)
  /// 纬度超出闭区间 `[-90, 90]`。
  LatitudeOutOfRange(String)
  /// 经度超出半开区间 `[-180, 180)`。
  LongitudeOutOfRange(String)
  /// 角度超出半开区间 `[0, 360)`。
  DegreesOutOfRange(String)
  /// DGPS 基站 ID 超出闭区间 `[0, 1023]`。
  DgpsStationOutOfRange(String)
} derive(Eq, Debug)

///|
/// 人类可读的错误描述。
pub fn GeoError::message(self : GeoError) -> String {
  match self {
    NotADecimal(t) => "not a valid xsd:decimal literal: \{t}"
    LatitudeOutOfRange(t) => "latitude out of range [-90, 90]: \{t}"
    LongitudeOutOfRange(t) => "longitude out of range [-180, 180): \{t}"
    DegreesOutOfRange(t) => "degrees out of range [0, 360): \{t}"
    DgpsStationOutOfRange(t) => "dgps station id out of range [0, 1023]: \{t}"
  }
}

///|
/// 取字符串的 Unicode 码点数组。
///
/// ⚠️ 不能用 `s.length()` 配合下标——`length()` 按 UTF-16 码元计数，
/// 而迭代按码点，两者混用会在非 BMP 字符上出错。
fn codes_of(s : String) -> Array[Int] {
  let arr : Array[Int] = []
  for ch in s {
    arr.push(ch.to_int())
  }
  arr
}

///|
fn is_ascii_space(c : Int) -> Bool {
  c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0D
}

///|
fn is_digit_code(c : Int) -> Bool {
  c >= 0x30 && c <= 0x39
}

///|
/// `xsd:decimal` 的 whitespace facet 是 `collapse`：首尾空白折叠掉。
/// 由于 decimal 本身不含空白字符，这一步等价于 trim。
fn collapse_space(text : String) -> String {
  let codes = codes_of(text)
  let n = codes.length()
  let mut start = 0
  let mut end = n
  while start < end && is_ascii_space(codes[start]) {
    start = start + 1
  }
  while end > start && is_ascii_space(codes[end - 1]) {
    end = end - 1
  }
  let out : Array[Char] = []
  for i = start; i < end; i = i + 1 {
    match Int::to_char(codes[i]) {
      Some(ch) => out.push(ch)
      None => ()
    }
  }
  String::from_array(out)
}

///|
/// 校验码点序列是否符合 `xsd:decimal` 的词法规则：
///
/// ```text
/// (\+|-)? ( [0-9]+ (\.[0-9]*)? | \.[0-9]+ )
/// ```
///
/// 明确**拒绝**：指数记法、`NaN`、`INF`、空串、多个小数点、
/// 只有符号或只有小数点。
fn is_decimal_lexical(codes : Array[Int]) -> Bool {
  let n = codes.length()
  if n == 0 {
    return false
  }
  let mut i = 0
  // 可选符号
  if codes[0] == 0x2B || codes[0] == 0x2D {
    i = 1
  }
  if i >= n {
    return false
  }
  // 整数部分
  let int_start = i
  while i < n && is_digit_code(codes[i]) {
    i = i + 1
  }
  let int_digits = i - int_start
  if i == n {
    // 纯整数形式，如 "-90"
    return int_digits > 0
  }
  // 必须是小数点
  if codes[i] != 0x2E {
    return false
  }
  i = i + 1
  // 小数部分
  let frac_start = i
  while i < n && is_digit_code(codes[i]) {
    i = i + 1
  }
  let frac_digits = i - frac_start
  if i != n {
    // 小数部分之后还有字符 → 非法（拦住指数记法、NaN 之类）
    return false
  }
  // 整数部分和小数部分至少有一位数字：".5" 合法，"." 非法
  int_digits + frac_digits > 0
}

///|
/// 解析 `xsd:decimal` 字面量。
///
/// GPX 的坐标、海拔、各类 dop 值都是这个类型。
pub fn parse_decimal(text : String) -> Result[Double, GeoError] {
  let s = collapse_space(text)
  if !is_decimal_lexical(codes_of(s)) {
    return Err(GeoError::NotADecimal(text))
  }
  let d = @string.parse_double(s) catch {
    _ => return Err(GeoError::NotADecimal(text))
  }
  if d.is_nan() || d.is_inf() {
    return Err(GeoError::NotADecimal(text))
  }
  Ok(d)
}

///|
fn index_of_e(codes : Array[Int]) -> Int {
  let n = codes.length()
  let mut i = 0
  while i < n {
    let c = codes[i]
    if c == 0x65 || c == 0x45 {
      return i
    }
    i = i + 1
  }
  -1
}

///|
fn codes_to_string(codes : Array[Int]) -> String {
  let out : Array[Char] = []
  for c in codes {
    match Int::to_char(c) {
      Some(ch) => out.push(ch)
      None => ()
    }
  }
  String::from_array(out)
}

///|
/// 把指数记法展开成纯十进制文本。
///
/// 例：`1e-7` → `0.0000001`；`1e+21` → `1000000000000000000000`。
/// 不涉及浮点运算，纯数字字符串搬移。
fn expand_exponent(text : String) -> String {
  let codes = codes_of(text)
  let epos = index_of_e(codes)
  if epos < 0 {
    return text
  }
  // 尾数部分（可能带符号与小数点）
  let mantissa = codes[:epos]
  // 指数部分
  let exp_codes = codes[epos + 1:]
  let mut exp = 0
  let mut ei = 0
  let mut exp_negative = false
  if ei < exp_codes.length() && (exp_codes[ei] == 0x2B || exp_codes[ei] == 0x2D) {
    exp_negative = exp_codes[ei] == 0x2D
    ei = ei + 1
  }
  while ei < exp_codes.length() && is_digit_code(exp_codes[ei]) {
    exp = exp * 10 + (exp_codes[ei] - 0x30)
    ei = ei + 1
  }
  if exp_negative {
    exp = -exp
  }
  // 拆出符号 / 整数位 / 小数位
  let mut mi = 0
  let mut negative = false
  if mi < mantissa.length() && mantissa[mi] == 0x2D {
    negative = true
    mi = mi + 1
  } else if mi < mantissa.length() && mantissa[mi] == 0x2B {
    mi = mi + 1
  }
  let digits : Array[Int] = []
  let mut int_len = 0
  let mut seen_dot = false
  while mi < mantissa.length() {
    let c = mantissa[mi]
    if c == 0x2E {
      seen_dot = true
    } else if is_digit_code(c) {
      digits.push(c)
      if !seen_dot {
        int_len = int_len + 1
      }
    }
    mi = mi + 1
  }
  // 小数点要移动到的位置
  let point = int_len + exp
  let out : Array[Int] = []
  if negative {
    out.push(0x2D)
  }
  if point <= 0 {
    out.push(0x30)
    out.push(0x2E)
    let mut z = 0
    while z < -point {
      out.push(0x30)
      z = z + 1
    }
    for c in digits {
      out.push(c)
    }
  } else if point >= digits.length() {
    for c in digits {
      out.push(c)
    }
    let mut z = digits.length()
    while z < point {
      out.push(0x30)
      z = z + 1
    }
  } else {
    let mut k = 0
    while k < point {
      out.push(digits[k])
      k = k + 1
    }
    out.push(0x2E)
    while k < digits.length() {
      out.push(digits[k])
      k = k + 1
    }
  }
  codes_to_string(out)
}

///|
/// 把 `Double` 格式化成**合法的 `xsd:decimal` 字面量**。
///
/// ⚠️ 不能直接用 `Double::to_string`：MoonBit 对 `1e-7`、`1e+21` 这类值会输出
/// 指数记法，而 `xsd:decimal` **不允许指数**。直接回写会产出非法 GPX 文档。
/// 这里把指数形式展开成纯十进制。
pub fn format_decimal(v : Double) -> String {
  expand_exponent(v.to_string())
}

///|
/// 纬度：**闭区间** `[-90, 90]`，两端都合法。
pub struct Latitude {
  value : Double
} derive(Eq, Debug)

///|
pub fn Latitude::from_double(v : Double) -> Result[Latitude, GeoError] {
  if v.is_nan() || v.is_inf() || v < -90.0 || v > 90.0 {
    return Err(GeoError::LatitudeOutOfRange(format_decimal(v)))
  }
  Ok({ value: v, })
}

///|
pub fn Latitude::from_string(text : String) -> Result[Latitude, GeoError] {
  match parse_decimal(text) {
    Ok(v) =>
      if v < -90.0 || v > 90.0 {
        Err(GeoError::LatitudeOutOfRange(text))
      } else {
        Ok({ value: v, })
      }
    Err(e) => Err(e)
  }
}

///|
pub fn Latitude::to_double(self : Latitude) -> Double {
  self.value
}

///|
pub fn Latitude::to_gpx_string(self : Latitude) -> String {
  format_decimal(self.value)
}

///|
/// 经度：**半开区间** `[-180, 180)`——上界排他，`180` 非法。
pub struct Longitude {
  value : Double
} derive(Eq, Debug)

///|
pub fn Longitude::from_double(v : Double) -> Result[Longitude, GeoError] {
  if v.is_nan() || v.is_inf() || v < -180.0 || v >= 180.0 {
    return Err(GeoError::LongitudeOutOfRange(format_decimal(v)))
  }
  Ok({ value: v, })
}

///|
pub fn Longitude::from_string(text : String) -> Result[Longitude, GeoError] {
  match parse_decimal(text) {
    Ok(v) =>
      if v < -180.0 || v >= 180.0 {
        Err(GeoError::LongitudeOutOfRange(text))
      } else {
        Ok({ value: v, })
      }
    Err(e) => Err(e)
  }
}

///|
pub fn Longitude::to_double(self : Longitude) -> Double {
  self.value
}

///|
pub fn Longitude::to_gpx_string(self : Longitude) -> String {
  format_decimal(self.value)
}

///|
/// 角度（GPX 里用于 `magvar`）：半开区间 `[0, 360)`。
pub struct Degrees {
  value : Double
} derive(Eq, Debug)

///|
pub fn Degrees::from_double(v : Double) -> Result[Degrees, GeoError] {
  if v.is_nan() || v.is_inf() || v < 0.0 || v >= 360.0 {
    return Err(GeoError::DegreesOutOfRange(format_decimal(v)))
  }
  Ok({ value: v, })
}

///|
pub fn Degrees::from_string(text : String) -> Result[Degrees, GeoError] {
  match parse_decimal(text) {
    Ok(v) =>
      if v < 0.0 || v >= 360.0 {
        Err(GeoError::DegreesOutOfRange(text))
      } else {
        Ok({ value: v, })
      }
    Err(e) => Err(e)
  }
}

///|
pub fn Degrees::to_double(self : Degrees) -> Double {
  self.value
}

///|
pub fn Degrees::to_gpx_string(self : Degrees) -> String {
  format_decimal(self.value)
}

///|
/// DGPS 基站 ID（GPX 的 `dgpsid`）：闭区间 `[0, 1023]` 整数。
pub struct DgpsStationId {
  value : Int
} derive(Eq, Debug)

///|
pub fn DgpsStationId::from_int(v : Int) -> Result[DgpsStationId, GeoError] {
  if v < 0 || v > 1023 {
    return Err(GeoError::DgpsStationOutOfRange(v.to_string()))
  }
  Ok({ value: v, })
}

///|
/// 从文本解析。必须是十进制整数，不接受 `12.0` 这类形式。
pub fn DgpsStationId::from_string(
  text : String,
) -> Result[DgpsStationId, GeoError] {
  let s = collapse_space(text)
  let codes = codes_of(s)
  if codes.length() == 0 {
    return Err(GeoError::NotADecimal(text))
  }
  let mut i = 0
  if codes[0] == 0x2B || codes[0] == 0x2D {
    i = 1
  }
  if i >= codes.length() {
    return Err(GeoError::NotADecimal(text))
  }
  let mut seen_digit = false
  while i < codes.length() {
    if !is_digit_code(codes[i]) {
      return Err(GeoError::NotADecimal(text))
    }
    seen_digit = true
    i = i + 1
  }
  if !seen_digit {
    return Err(GeoError::NotADecimal(text))
  }
  let v = @string.parse_int(s) catch {
    _ => return Err(GeoError::NotADecimal(text))
  }
  DgpsStationId::from_int(v)
}

///|
pub fn DgpsStationId::to_int(self : DgpsStationId) -> Int {
  self.value
}

///|
pub fn DgpsStationId::to_gpx_string(self : DgpsStationId) -> String {
  self.value.to_string()
}
