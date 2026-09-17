///|
/// GPX 1.1 数据模型。
///
/// 对应官方 schema 的复合类型：
/// `gpxType` / `metadataType` / `wptType` / `rteType` / `trkType` / `trksegType` /
/// `linkType` / `personType` / `emailType` / `copyrightType` / `boundsType`。
///
/// 规范来源：<https://www.topografix.com/GPX/1/1/gpx.xsd>

///|
/// `fix` 属性的枚举值。
///
/// ⚠️ 大小写敏感：schema 里是小写的 `none` / `2d` / `3d` / `dgps` / `pps`，
/// 写成 `2D` 是非法的。
pub(all) enum FixType {
  FixNone
  Fix2d
  Fix3d
  FixDgps
  FixPps
} derive(Eq, Debug)

///|
/// 从 schema 的字符串值解析。非法值返回 `None`。
pub fn FixType::from_string(text : String) -> FixType? {
  match text {
    "none" => Some(FixNone)
    "2d" => Some(Fix2d)
    "3d" => Some(Fix3d)
    "dgps" => Some(FixDgps)
    "pps" => Some(FixPps)
    _ => None
  }
}

///|
/// 转回 schema 的字符串值。
pub fn FixType::to_string(self : FixType) -> String {
  match self {
    FixNone => "none"
    Fix2d => "2d"
    Fix3d => "3d"
    FixDgps => "dgps"
    FixPps => "pps"
  }
}

///|
/// `link` 元素。`href` 属性**必填**。
pub struct Link {
  href : String
  text : String?
  /// schema 里字段名是 `type`，这里改名以避免与语言关键字混淆。
  mime_type : String?
} derive(Eq, Debug)

///|
/// `email` 元素。schema 把它拆成 `id` 和 `domain` 两个**都必填**的属性
/// （GPX 1.0 里是一个完整的 `<email>` 文本节点，1.1 改了）。
pub struct Email {
  id : String
  domain : String
} derive(Eq, Debug)

///|
/// `person` 元素，用于 `metadata/author`。
pub struct Person {
  name : String?
  email : Email?
  link : Link?
} derive(Eq, Debug)

///|
/// `copyright` 元素。`author` 属性**必填**。
pub struct Copyright {
  author : String
  /// `xsd:gYear`，原样保留文本形式（可能是负年份或带时区）。
  year : String?
  license : String?
} derive(Eq, Debug)

///|
/// `bounds` 元素。四个属性**全部必填**，且都经过坐标范围校验。
pub struct Bounds {
  min_lat : Latitude
  min_lon : Longitude
  max_lat : Latitude
  max_lon : Longitude
} derive(Eq, Debug)

///|
/// `metadata` 元素（GPX 1.1 新增；1.0 里这些字段直接挂在根下）。
pub struct Metadata {
  name : String?
  desc : String?
  author : Person?
  copyright : Copyright?
  links : Array[Link]
  /// `xsd:dateTime`，原样保留文本形式。
  time : String?
  keywords : String?
  bounds : Bounds?
  /// `extensions` 的**原始内部 XML 文本**，用于无损往返。
  extensions : String?
} derive(Eq, Debug)

///|
/// 航点 / 轨迹点（`wptType`）。
///
/// schema 规定子元素分三段且**顺序固定**：
/// 位置信息 → 描述信息 → 精度信息。
pub struct Waypoint {
  lat : Latitude
  lon : Longitude
  // —— 位置信息 ——
  ele : Double?
  time : String?
  magvar : Degrees?
  geoid_height : Double?
  // —— 描述信息 ——
  name : String?
  cmt : String?
  desc : String?
  src : String?
  links : Array[Link]
  sym : String?
  wpt_type : String?
  // —— 精度信息 ——
  fix : FixType?
  sat : Int?
  hdop : Double?
  vdop : Double?
  pdop : Double?
  age_of_dgps_data : Double?
  dgps_id : DgpsStationId?
  /// `extensions` 的**原始内部 XML 文本**，用于无损往返。
  extensions : String?
} derive(Eq, Debug)

///|
/// `rte` 元素。
pub struct Route {
  name : String?
  cmt : String?
  desc : String?
  src : String?
  links : Array[Link]
  number : Int?
  route_type : String?
  extensions : String?
  points : Array[Waypoint]
} derive(Eq, Debug)

///|
/// `trkseg` 元素。
pub struct TrackSegment {
  points : Array[Waypoint]
  extensions : String?
} derive(Eq, Debug)

///|
/// `trk` 元素。
pub struct Track {
  name : String?
  cmt : String?
  desc : String?
  src : String?
  links : Array[Link]
  number : Int?
  track_type : String?
  extensions : String?
  segments : Array[TrackSegment]
} derive(Eq, Debug)

///|
/// GPX 文档根（`gpxType`）。
pub struct Gpx {
  /// schema 规定固定为 `"1.1"`。
  version : String
  /// 创建该文档的软件名称或 URL，**必填**。
  creator : String
  metadata : Metadata?
  waypoints : Array[Waypoint]
  routes : Array[Route]
  tracks : Array[Track]
  extensions : String?
} derive(Eq, Debug)
