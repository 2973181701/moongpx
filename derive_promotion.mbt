///|
/// 显式声明各类型的 `Eq` / `Debug` 方法提升。
///
/// ## 为什么需要这个文件
///
/// 本项目所有公开类型都用 `derive(Eq, Debug)` 自动派生相等性与调试输出。
/// 派生出的 impl 方法会被编译器**隐式**提升为该类型的普通方法——
/// 也就是说，外部可以直接写 `lat.equal(other)`，即使从未显式声明过。
///
/// 这个隐式提升行为已被 `moonbitlang/core` 标记为废弃
/// （诊断码 `implicit_impl_as_method`），**未来版本会移除**。
/// 一旦移除，本包将无法编译。
///
/// 显式写出 `extend` 声明即可消除告警，且**行为完全不变**——
/// 只是把原本隐式发生的事情写明。集中放在这个文件里，
/// 而不是散落到各个类型定义旁边，是为了让这层"兼容垫片"一眼可见：
/// 它没有任何业务语义，纯粹是编译器要求的显式声明。
///
/// ## 维护约定
///
/// **新增带 `derive(Eq, Debug)` 的公开类型时，必须在此处补上对应两行**，
/// 否则会重新引入 `implicit_impl_as_method` 告警。
///
/// 对应的 import（`moonbitlang/core/debug`）在 `moon.pkg` 中声明。
// ─────────────────────────────────────────────────────────────────────

///|
/// `model.mbt`
pub extend FixType with Eq::{not_equal, equal}

///|
pub extend FixType with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend Link with Eq::{not_equal, equal}

///|
pub extend Link with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend Email with Eq::{not_equal, equal}

///|
pub extend Email with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend Person with Eq::{not_equal, equal}

///|
pub extend Person with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend Copyright with Eq::{not_equal, equal}

///|
pub extend Copyright with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend Bounds with Eq::{not_equal, equal}

///|
pub extend Bounds with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend Metadata with Eq::{not_equal, equal}

///|
pub extend Metadata with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend Waypoint with Eq::{not_equal, equal}

///|
pub extend Waypoint with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend Route with Eq::{not_equal, equal}

///|
pub extend Route with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend TrackSegment with Eq::{not_equal, equal}

///|
pub extend TrackSegment with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend Track with Eq::{not_equal, equal}

///|
pub extend Track with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend Gpx with Eq::{not_equal, equal}

///|
pub extend Gpx with @moonbitlang/core/debug.Debug::{to_repr}

///|
/// `geo.mbt`
pub extend GeoError with Eq::{not_equal, equal}

///|
pub extend GeoError with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend Latitude with Eq::{not_equal, equal}

///|
pub extend Latitude with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend Longitude with Eq::{not_equal, equal}

///|
pub extend Longitude with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend Degrees with Eq::{not_equal, equal}

///|
pub extend Degrees with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend DgpsStationId with Eq::{not_equal, equal}

///|
pub extend DgpsStationId with @moonbitlang/core/debug.Debug::{to_repr}

///|
/// `diagnostic.mbt`
pub extend Severity with Eq::{not_equal, equal}

///|
pub extend Severity with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend Diagnostic with Eq::{not_equal, equal}

///|
pub extend Diagnostic with @moonbitlang/core/debug.Debug::{to_repr}

///|
/// `stats.mbt`
pub extend TrackStats with Eq::{not_equal, equal}

///|
pub extend TrackStats with @moonbitlang/core/debug.Debug::{to_repr}
