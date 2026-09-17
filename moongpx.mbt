///|
/// # moongpx
///
/// GPX（GPS Exchange Format）的规范实现。
///
/// 提供解析、校验、序列化与 GPX 1.0 / 1.1 版本迁移能力，依据官方 XML Schema：
/// <https://www.topografix.com/GPX/1/1/gpx.xsd>
///
/// 设计原则：纯函数，不联网、不读写文件。调用方把 GPX 文本传进来，
/// 本库返回结构化模型或诊断信息。
///
/// 当前版本已实现坐标与数值类型层（见 `geo.mbt`）。

///|
/// 库版本号，与 `moon.mod` 中的 `version` 保持一致。
pub fn version() -> String {
  "0.1.0"
}
