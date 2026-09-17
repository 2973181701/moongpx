///|
/// 轨迹统计。
///
/// 从已解析的点序列算出距离、爬升、包围盒这类**派生量**。
/// 本模块只读 `Track` / `Waypoint`，不碰 XML。
///
/// 两个容易被做错、这里必须先讲清楚的约定：
///
/// 1. **跨 `trkseg` 不相连**。`trkseg` 表示 GPS 信号中断后重新捕获，
///    两个 segment 之间的直线位移不是真实运动轨迹，计入距离会凭空多出一大截。
///    所以距离和爬升都是**逐 segment 计算再累加**。
/// 2. **爬升必须带阈值**。GPS 高程噪声通常在几米量级，直接累加相邻点高差
///    会把来回抖动放大成几百米的虚假"爬升"——这是开源实现里最常见的 bug。

///|
/// 平均地球半径（IUGG 推荐值），单位米。
///
/// 地球是椭球，任何单一半径都是近似。这个值在几百公里尺度内的误差
/// 远小于 GPS 本身的误差，对轨迹统计够用。
pub let earth_radius_m : Double = 6371008.8

///|
/// 默认的爬升阈值（米）。
///
/// 低于这个幅度的高程变化被视为噪声，不计入累计爬升/下降。
/// `climb_m` 传 `0.0` 可关闭过滤（等价于朴素累加）。
pub let default_climb_threshold_m : Double = 3.0

///|
/// 半正矢公式算出的两点大圆距离，单位米。
///
/// 比余弦定理数值稳定——在两点非常接近时（轨迹点通常就是这种情况）
/// 余弦定理会因浮点精度丢失有效位。
pub fn haversine_m(a : Waypoint, b : Waypoint) -> Double {
  let d2r = 0.017453292519943295
  let lat1 = a.lat.to_double() * d2r
  let lon1 = a.lon.to_double() * d2r
  let lat2 = b.lat.to_double() * d2r
  let lon2 = b.lon.to_double() * d2r
  let s1 = @math.sin((lat2 - lat1) / 2.0)
  let s2 = @math.sin((lon2 - lon1) / 2.0)
  let h = s1 * s1 + @math.cos(lat1) * @math.cos(lat2) * s2 * s2
  // 浮点误差可能让 h 略微超出 [0, 1]，asin 会给出 NaN
  let clamped = h.min(1.0).max(0.0)
  2.0 * earth_radius_m * @math.asin(clamped.sqrt())
}

///|
/// 一串点的路径总长（米），逐段相加。
pub fn path_distance_m(points : Array[Waypoint]) -> Double {
  let mut total = 0.0
  let mut i = 1
  while i < points.length() {
    total = total + haversine_m(points[i - 1], points[i])
    i = i + 1
  }
  total
}

///|
/// 累计爬升与下降（米），返回 `(爬升, 下降)`。
///
/// `threshold > 0` 时启用**滞后过滤**：高程变化先累积到 `pending`，
/// 只有累积量超过阈值才计入总数并清零。方向反转时先结算再重新累积。
/// 这样 3 米上 3 米下的来回抖动会被抵消掉，而真实的一次 50 米爬升不会。
///
/// `threshold <= 0` 退化为朴素累加（每一步的高差都直接计入）。
/// 没有 `ele` 的点被跳过，不影响累积。
pub fn climb_m(
  points : Array[Waypoint],
  threshold : Double,
) -> (Double, Double) {
  let mut ascend = 0.0
  let mut descend = 0.0
  let mut pending = 0.0
  let mut prev : Double? = None
  let filter = threshold > 0.0
  for p in points {
    match p.ele {
      Some(e) => {
        match prev {
          Some(pe) =>
            if filter {
              pending = pending + (e - pe)
              if pending >= threshold {
                ascend = ascend + pending
                pending = 0.0
              } else if pending <= 0.0 - threshold {
                descend = descend - pending
                pending = 0.0
              }
            } else {
              let d = e - pe
              if d > 0.0 {
                ascend = ascend + d
              } else {
                descend = descend - d
              }
            }
          None => ()
        }
        prev = Some(e)
      }
      None => ()
    }
  }
  // 收尾：最后一段没凑够阈值的残余，只有超过阈值才计入
  if filter {
    if pending >= threshold {
      ascend = ascend + pending
    } else if pending <= 0.0 - threshold {
      descend = descend - pending
    }
  }
  (ascend, descend)
}

///|
/// 一串点的包围盒。点集为空时返回 `None`。
///
/// 直接复用各点已校验过的 `Latitude` / `Longitude`，不重新做范围校验——
/// 输入既然是合法的 `Waypoint`，其极值必然仍在合法区间内。
pub fn bounds_of(points : Array[Waypoint]) -> Bounds? {
  let mut min_lat : Latitude? = None
  let mut max_lat : Latitude? = None
  let mut min_lon : Longitude? = None
  let mut max_lon : Longitude? = None
  for p in points {
    match (min_lat, max_lat, min_lon, max_lon) {
      (None, None, None, None) => {
        min_lat = Some(p.lat)
        max_lat = Some(p.lat)
        min_lon = Some(p.lon)
        max_lon = Some(p.lon)
      }
      (Some(a), Some(b), Some(c), Some(d)) => {
        if p.lat.to_double() < a.to_double() {
          min_lat = Some(p.lat)
        }
        if p.lat.to_double() > b.to_double() {
          max_lat = Some(p.lat)
        }
        if p.lon.to_double() < c.to_double() {
          min_lon = Some(p.lon)
        }
        if p.lon.to_double() > d.to_double() {
          max_lon = Some(p.lon)
        }
      }
      // 四个变量总是同时置位，这里只是让模式穷尽
      _ => ()
    }
  }
  match (min_lat, max_lat, min_lon, max_lon) {
    (Some(a), Some(b), Some(c), Some(d)) =>
      Some({ min_lat: a, min_lon: c, max_lat: b, max_lon: d, })
    _ => None
  }
}

///|
/// 一条轨迹的统计结果。
pub struct TrackStats {
  /// 轨迹点总数（所有 segment 合计）。
  point_count : Int
  /// 总距离（米）。跨 `trkseg` 不相连。
  distance_m : Double
  /// 累计爬升（米），已按默认阈值过滤高程噪声。
  ascend_m : Double
  /// 累计下降（米）。
  descend_m : Double
  /// 最低高程（米）。所有点都没有 `ele` 时为 `None`。
  min_ele : Double?
  /// 最高高程（米）。
  max_ele : Double?
  /// 包围盒。轨迹没有点时返回 `None`。
  bounds : Bounds?
  /// 最早的时间。不是"第一个点"——时间可能不单调，这里取真正的最小值。
  start_time : String?
  /// 最晚的时间。
  end_time : String?
  /// 起止时间差（秒）。时间缺失或无法解析时为 `None`。
  duration_s : Double?
} derive(Eq, Debug)

///|
/// 取两个 `xsd:dateTime` 中较早的一个。无法比较时保守返回 `a`。
fn earlier_of(a : String, b : String) -> String {
  match datetime_compare(a, b) {
    Some(c) => if c <= 0 { a } else { b }
    None => a
  }
}

///|
/// 取两个 `xsd:dateTime` 中较晚的一个。
fn later_of(a : String, b : String) -> String {
  match datetime_compare(a, b) {
    Some(c) => if c >= 0 { a } else { b }
    None => a
  }
}

///|
/// 两个时间之间的秒数。任一为 `None` 或无法解析时区时返回 `None`。
fn duration_between(a : String?, b : String?) -> Double? {
  match (a, b) {
    (Some(x), Some(y)) =>
      match (datetime_to_epoch(x), datetime_to_epoch(y)) {
        (Some(px), Some(py)) => Some(py - px)
        _ => None
      }
    _ => None
  }
}

///|
/// 统计一条轨迹。
///
/// 距离与爬升**逐 `trkseg` 计算再累加**，不跨段相连（见模块顶部说明）。
pub fn track_stats(track : Track) -> TrackStats {
  let mut total_distance = 0.0
  let mut ascend = 0.0
  let mut descend = 0.0
  let mut count = 0
  let mut min_ele : Double? = None
  let mut max_ele : Double? = None
  let mut earliest : String? = None
  let mut latest : String? = None
  let all_points : Array[Waypoint] = []
  for seg in track.segments {
    let pts = seg.points
    count = count + pts.length()
    total_distance = total_distance + path_distance_m(pts)
    let (a, d) = climb_m(pts, default_climb_threshold_m)
    ascend = ascend + a
    descend = descend + d
    for p in pts {
      all_points.push(p)
      match p.ele {
        Some(e) => {
          min_ele = match min_ele {
            None => Some(e)
            Some(m) => Some(if e < m { e } else { m })
          }
          max_ele = match max_ele {
            None => Some(e)
            Some(m) => Some(if e > m { e } else { m })
          }
        }
        None => ()
      }
      match p.time {
        Some(t) => {
          earliest = match earliest {
            None => Some(t)
            Some(e) => Some(earlier_of(e, t))
          }
          latest = match latest {
            None => Some(t)
            Some(l) => Some(later_of(l, t))
          }
        }
        None => ()
      }
    }
  }
  {
    point_count: count,
    distance_m: total_distance,
    ascend_m: ascend,
    descend_m: descend,
    min_ele,
    max_ele,
    bounds: bounds_of(all_points),
    start_time: earliest,
    end_time: latest,
    duration_s: duration_between(earliest, latest),
  }
}

///|
/// 一条轨迹的总距离（米）。等价于 `track_stats(t).distance_m`，但少建一个对象。
pub fn track_distance_m(track : Track) -> Double {
  let mut total = 0.0
  for seg in track.segments {
    total = total + path_distance_m(seg.points)
  }
  total
}
