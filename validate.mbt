///|
/// 独立校验：只要诊断，不要模型。
///
/// 与 `parse_gpx` 共用同一套检查逻辑（`parse_gpx_core`），差别在**视角**：
///
/// | | `parse_gpx` | `validate_gpx` |
/// |---|---|---|
/// | 关心 | 能不能用 | 完不完美 |
/// | 有 error 时 | 返回 `Err`，丢掉已解析的部分 | 照常报出，连同 warning 一起 |
/// | 有 warning 时 | 成功路径上**丢弃** | 报出 |
/// | 返回 | `Result[Gpx, ...]` | `Array[Diagnostic]`（空 = 干净） |
///
/// 为什么要单独一个入口：真实场景里 "这个文件有什么问题" 和
/// "把这个文件读进来" 是两个需求。用 `parse_gpx` 做前者会丢信息——
/// 文档合法但有可疑之处时，你什么也看不到。

///|
/// 校验 GPX 文档，返回**全部**诊断（error + warning）。
///
/// - 返回空数组：文档干净
/// - 非空：按发现顺序排列，每条带 1-based 行列号
///
/// **不会因为发现一个错误就停下**——一个文件里的多个问题会一次性全部报出。
/// 唯一的例外是 XML 语法本身坏了（拿不到事件流），此时只能报一条 `E1000`。
pub fn validate_gpx(src : String) -> Array[Diagnostic] {
  let (_, diags) = parse_gpx_core(src)
  diags
}

///|
/// 文档是否**完全合格**：既没有 error，也没有 warning。
///
/// 这是最严格的口径。如果只想判断"能不能解析"，用 `parse_gpx(...).is_ok()`。
pub fn is_valid_gpx(src : String) -> Bool {
  validate_gpx(src).length() == 0
}

///|
/// 文档是否存在**违反 schema** 的问题（不看 warning）。
pub fn has_schema_errors(src : String) -> Bool {
  has_errors(validate_gpx(src))
}

///|
/// 按级别筛出诊断。
pub fn diagnostics_of_severity(
  diags : Array[Diagnostic],
  severity : Severity,
) -> Array[Diagnostic] {
  let out : Array[Diagnostic] = []
  for d in diags {
    if d.severity == severity {
      out.push(d)
    }
  }
  out
}

///|
/// 校验并格式化成人话，便于直接打印或写进报告。
///
/// 没有问题时返回一句明确的"没问题"，而不是空字符串——
/// 空字符串会让调用方分不清"干净"和"忘了填"。
pub fn validate_gpx_report(src : String) -> String {
  let diags = validate_gpx(src)
  if diags.length() == 0 {
    return "没有问题：文档符合 GPX 1.1 schema，且未发现可疑之处。"
  }
  let errors = diagnostics_of_severity(diags, Error).length()
  let warnings = diagnostics_of_severity(diags, Warning).length()
  "共 \{diags.length()} 条（\{errors} 错误 / \{warnings} 警告）：\n" +
  format_diagnostics(diags)
}
