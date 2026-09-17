///|
/// 诊断系统。
///
/// GPX 的很多约束（元素顺序、必填属性、取值区间）都不会让 XML 解析器报错，
/// 只会静默产出一个**不合规但看起来正常**的文档。本模块把这些约束变成
/// 可枚举、可定位的诊断记录。
///
/// 每条诊断都带 **1-based 的行列号**，直接对应源文件中的位置。

///|
/// 诊断级别。
///
/// - `Error`：文档违反 schema，不合格
/// - `Warning`：不违反 schema，但明显可疑
pub(all) enum Severity {
  Error
  Warning
} derive(Eq, Debug)

///|
pub fn Severity::to_string(self : Severity) -> String {
  match self {
    Error => "error"
    Warning => "warning"
  }
}

///|
/// 一条诊断记录。
pub struct Diagnostic {
  severity : Severity
  /// 稳定的诊断代码，便于测试断言与用户检索。
  code : String
  message : String
  /// 1-based 行号。
  line : Int
  /// 1-based 列号。
  column : Int
} derive(Eq, Debug)

///|
pub fn Diagnostic::error(
  code : String,
  message : String,
  line : Int,
  column : Int,
) -> Diagnostic {
  { severity: Error, code, message, line, column, }
}

///|
pub fn Diagnostic::warning(
  code : String,
  message : String,
  line : Int,
  column : Int,
) -> Diagnostic {
  { severity: Warning, code, message, line, column, }
}

///|
/// 人类可读形式：`行:列  级别  代码  说明`
pub fn Diagnostic::to_string(self : Diagnostic) -> String {
  "\{self.line}:\{self.column}  \{self.severity.to_string()}  \{self.code}  \{self.message}"
}

///|
/// 诊断列表中是否存在错误级问题。
pub fn has_errors(diags : Array[Diagnostic]) -> Bool {
  for d in diags {
    if d.severity == Error {
      return true
    }
  }
  false
}

///|
/// 把诊断列表格式化成多行文本，每条一行。
pub fn format_diagnostics(diags : Array[Diagnostic]) -> String {
  let lines : Array[String] = []
  for d in diags {
    lines.push(d.to_string())
  }
  lines.join("\n")
}

///|
/// 诊断代码常量。
///
/// 集中在这里，避免各处写散落的魔法字符串，也方便测试与文档对照。
pub let code_root_not_gpx : String = "E1001"

///|
pub let code_version_missing : String = "E1002"

///|
pub let code_version_not_1_1 : String = "E1003"

///|
pub let code_creator_missing : String = "E1004"

///|
pub let code_root_order : String = "E1005"

///|
pub let code_metadata_order : String = "E1006"

///|
pub let code_metadata_duplicate : String = "E1007"

///|
pub let code_unexpected_attribute : String = "E1008"

///|
pub let code_missing_required_attribute : String = "E1009"

///|
pub let code_invalid_datetime : String = "E1010"

///|
pub let code_invalid_decimal : String = "E1011"

///|
pub let code_wpt_order : String = "E1013"

///|
pub let code_rte_order : String = "E1014"

///|
pub let code_trk_order : String = "E1015"

///|
pub let code_invalid_fix : String = "E1016"

///|
/// `version` 不是 `"1.0"`。`parse_gpx_1_0` 专用——
/// 与 `E1003`（不是 1.1）分开，报错信息能直接说清是哪个入口在要求什么。
pub let code_version_not_1_0 : String = "E1017"

// ── 警告级（不违反 schema，但语义可疑）──
//
// 判定标准：**错误** = 文档在校验器下不合格；**警告** = 合法但值得人看一眼。
// 警告绝不会被 `parse_gpx` 当成失败原因，只在 `validate_gpx` 里出现。

///|
/// `bounds` 的 `min` 大于 `max`。
pub let code_bounds_order : String = "W1001"

///|
/// 同一 `trkseg` 内后一个点的时间早于前一个点。
pub let code_time_not_monotonic : String = "W1002"

///|
/// 相邻两个轨迹点的 `lat` / `lon` / `ele` 完全相同。
pub let code_duplicate_point : String = "W1003"

///|
/// `fix` 与 `sat` 自相矛盾（如 `fix=none` 却 `sat=9`，或 `fix=3d` 却 `sat=0`）。
pub let code_fix_sat_conflict : String = "W1004"

///|
/// `ele` 超出地球表面的合理范围（约 -11000 ~ 9000 m）。
pub let code_elevation_implausible : String = "W1005"

///|
/// `trk` / `trkseg` / `rte` 没有任何点。
pub let code_empty_segment : String = "W1006"

///|
/// 点位落在 `metadata/bounds` 声明的范围之外。
pub let code_out_of_bounds : String = "W1007"

// ── XML 层 ──

///|
pub let code_xml_parse_error : String = "E1000"
