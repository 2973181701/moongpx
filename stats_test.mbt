///|
/// 轨迹统计的黑盒测试。
///
/// 重点验证两个容易做错的约定：
/// 1. 跨 `trkseg` 不相连
/// 2. 爬升阈值能过滤掉 GPS 高程噪声

///|
fn assert_near(
  actual : Double,
  expected : Double,
  tol : Double,
  label : String,
) -> Unit raise {
  let d = if actual > expected { actual - expected } else { expected - actual }
  if d > tol {
    fail("\{label}：期望 \{expected} ± \{tol}，实际 \{actual}")
  }
}

///|
fn pt_at(
  lat : Double,
  lon : Double,
  ele : Double?,
  time : String?,
) -> @moongpx.Waypoint raise {
  let la = match @moongpx.Latitude::from_double(lat) {
    Ok(v) => v
    Err(e) => fail("lat \{lat}：\{e.message()}")
  }
  let lo = match @moongpx.Longitude::from_double(lon) {
    Ok(v) => v
    Err(e) => fail("lon \{lon}：\{e.message()}")
  }
  @moongpx.Waypoint::new(la, lo).with_ele(ele).with_time(time)
}

///|
fn pt(lat : Double, lon : Double) -> @moongpx.Waypoint raise {
  pt_at(lat, lon, None, None)
}

///|
fn ele_series(values : Array[Double]) -> Array[@moongpx.Waypoint] raise {
  let out : Array[@moongpx.Waypoint] = []
  for v in values {
    out.push(pt_at(0.0, 0.0, Some(v), None))
  }
  out
}

///|
fn track_of(segs : Array[Array[@moongpx.Waypoint]]) -> @moongpx.Track {
  let segments : Array[@moongpx.TrackSegment] = []
  for s in segs {
    segments.push(@moongpx.TrackSegment::new(s))
  }
  @moongpx.Track::new(segments)
}

// ── haversine_m ──

///|
test "相同点距离为 0" {
  assert_near(
    @moongpx.haversine_m(pt(31.23, 121.47), pt(31.23, 121.47)),
    0.0,
    0.000001,
    "同点",
  )
}

///|
test "赤道上 1 度经度约 111.195 km" {
  // 球体模型：2πR/360，R = 6371008.8
  let d = @moongpx.haversine_m(pt(0.0, 0.0), pt(0.0, 1.0))
  assert_near(d, 111194.93, 1.0, "1 度经度")
}

///|
test "经线上 1 度纬度约 111.195 km" {
  let d = @moongpx.haversine_m(pt(0.0, 0.0), pt(1.0, 0.0))
  assert_near(d, 111194.93, 1.0, "1 度纬度")
}

///|
test "距离与方向无关" {
  let a = pt(31.23, 121.47)
  let b = pt(31.5, 121.8)
  assert_near(
    @moongpx.haversine_m(a, b),
    @moongpx.haversine_m(b, a),
    0.000000001,
    "对称性",
  )
}

///|
test "高纬度处 1 度经度的地面距离更短" {
  // 经线收敛：同样 1 度经度，在 60°N 的地面距离约为赤道的一半
  let equator = @moongpx.haversine_m(pt(0.0, 0.0), pt(0.0, 1.0))
  let at60 = @moongpx.haversine_m(pt(60.0, 0.0), pt(60.0, 1.0))
  assert_near(at60, equator * 0.5, equator * 0.02, "60°N 收敛")
}

// ── path_distance_m ──

///|
test "路径长度逐段相加" {
  let pts = [pt(0.0, 0.0), pt(0.0, 1.0), pt(0.0, 2.0)]
  assert_near(@moongpx.path_distance_m(pts), 111194.93 * 2.0, 2.0, "两段")
}

///|
test "空点集与单点集的距离为 0" {
  assert_eq(@moongpx.path_distance_m([]), 0.0)
  assert_eq(@moongpx.path_distance_m([pt(1.0, 1.0)]), 0.0)
}

// ── climb_m：阈值过滤 ──

///|
test "朴素累加（threshold=0）把每一次高差都计入" {
  let (a, d) = @moongpx.climb_m(ele_series([0.0, 10.0, 20.0, 10.0, 0.0]), 0.0)
  assert_near(a, 20.0, 0.000000001, "爬升")
  assert_near(d, 20.0, 0.000000001, "下降")
}

///|
test "阈值能抵消亚阈值抖动" {
  // ±1 m 的高程噪声来回抖，朴素累加会算出 2 m 爬升 + 2 m 下降
  let (a_noisy, d_noisy) = @moongpx.climb_m(
    ele_series([0.0, 1.0, 0.0, 1.0, 0.0]),
    0.0,
  )
  assert_near(a_noisy, 2.0, 0.000000001, "未过滤的爬升")
  assert_near(d_noisy, 2.0, 0.000000001, "未过滤的下降")
  // 阈值 3 m：抖动累积量始终没到 3，全部被抵消
  let (a, d) = @moongpx.climb_m(ele_series([0.0, 1.0, 0.0, 1.0, 0.0]), 3.0)
  assert_near(a, 0.0, 0.000000001, "过滤后的爬升")
  assert_near(d, 0.0, 0.000000001, "过滤后的下降")
}

///|
test "真实爬升不会被阈值吃掉" {
  let (a, d) = @moongpx.climb_m(ele_series([0.0, 1.0, 3.0, 5.0, 10.0]), 3.0)
  assert_near(a, 10.0, 0.000000001, "爬升")
  assert_near(d, 0.0, 0.000000001, "下降")
}

///|
test "方向反转时先结算再重新累积" {
  let (a, d) = @moongpx.climb_m(ele_series([0.0, 10.0, 0.0]), 3.0)
  assert_near(a, 10.0, 0.000000001, "爬升")
  assert_near(d, 10.0, 0.000000001, "下降")
}

///|
test "净下降" {
  let (a, d) = @moongpx.climb_m(ele_series([10.0, 5.0, 0.0]), 3.0)
  assert_near(a, 0.0, 0.000000001, "爬升")
  assert_near(d, 10.0, 0.000000001, "下降")
}

///|
test "没有 ele 的点被跳过" {
  let pts = [
    pt_at(0.0, 0.0, Some(0.0), None),
    pt(0.0, 0.0),
    pt_at(0.0, 0.0, Some(50.0), None),
  ]
  let (a, d) = @moongpx.climb_m(pts, 3.0)
  assert_near(a, 50.0, 0.000000001, "爬升")
  assert_near(d, 0.0, 0.000000001, "下降")
}

// ── bounds_of ──

///|
test "空点集没有包围盒" {
  assert_eq(@moongpx.bounds_of([]) is None, true)
}

///|
test "单点包围盒的四角重合" {
  match @moongpx.bounds_of([pt(31.23, 121.47)]) {
    None => fail("单点应能算出包围盒")
    Some(b) => {
      assert_near(b.min_lat.to_double(), 31.23, 0.000000001, "min_lat")
      assert_near(b.max_lat.to_double(), 31.23, 0.000000001, "max_lat")
      assert_near(b.min_lon.to_double(), 121.47, 0.000000001, "min_lon")
      assert_near(b.max_lon.to_double(), 121.47, 0.000000001, "max_lon")
    }
  }
}

///|
test "多点包围盒取极值" {
  let pts = [pt(10.0, 20.0), pt(-5.0, 30.0), pt(3.0, 5.0)]
  match @moongpx.bounds_of(pts) {
    None => fail("应能算出包围盒")
    Some(b) => {
      assert_near(b.min_lat.to_double(), -5.0, 0.000000001, "min_lat")
      assert_near(b.max_lat.to_double(), 10.0, 0.000000001, "max_lat")
      assert_near(b.min_lon.to_double(), 5.0, 0.000000001, "min_lon")
      assert_near(b.max_lon.to_double(), 30.0, 0.000000001, "max_lon")
    }
  }
}

// ── track_stats ──

///|
test "跨 trkseg 不相连" {
  // 两段都沿赤道各走 1 度（这样每段长度相同，便于口算），
  // 第二段整体跳到 10°E 以外。若把段间也连起来，总长会多出 9 度（约 1000 km）。
  let t = track_of([
    [pt(0.0, 0.0), pt(0.0, 1.0)],
    [pt(0.0, 10.0), pt(0.0, 11.0)],
  ])
  let seg_len = 111194.93
  assert_near(
    @moongpx.track_stats(t).distance_m,
    seg_len * 2.0,
    5.0,
    "总距离",
  )
}

///|
test "空轨迹的统计全是零值" {
  let s = @moongpx.track_stats(track_of([]))
  assert_eq(s.point_count, 0)
  assert_eq(s.distance_m, 0.0)
  assert_eq(s.ascend_m, 0.0)
  assert_eq(s.descend_m, 0.0)
  assert_eq(s.min_ele is None, true)
  assert_eq(s.max_ele is None, true)
  assert_eq(s.bounds is None, true)
  assert_eq(s.start_time is None, true)
  assert_eq(s.end_time is None, true)
  assert_eq(s.duration_s is None, true)
}

///|
test "完整统计：点数 / 距离 / 爬升 / 高程 / 包围盒" {
  let seg = [
    pt_at(0.0, 0.0, Some(10.0), None),
    pt_at(0.0, 1.0, Some(60.0), None),
    pt_at(0.0, 2.0, Some(20.0), None),
  ]
  let s = @moongpx.track_stats(track_of([seg]))
  assert_eq(s.point_count, 3)
  assert_near(s.distance_m, 111194.93 * 2.0, 5.0, "距离")
  assert_near(s.ascend_m, 50.0, 0.000000001, "爬升")
  assert_near(s.descend_m, 40.0, 0.000000001, "下降")
  assert_eq(s.min_ele, Some(10.0))
  assert_eq(s.max_ele, Some(60.0))
  match s.bounds {
    None => fail("应有包围盒")
    Some(b) => {
      assert_near(b.min_lon.to_double(), 0.0, 0.000000001, "min_lon")
      assert_near(b.max_lon.to_double(), 2.0, 0.000000001, "max_lon")
    }
  }
}

///|
test "起止时间取真正的极值，不是首尾点" {
  // 故意让时间倒流：第二个点更早
  let seg = [
    pt_at(0.0, 0.0, None, Some("2020-01-01T10:00:00Z")),
    pt_at(0.0, 1.0, None, Some("2020-01-01T09:00:00Z")),
    pt_at(0.0, 2.0, None, Some("2020-01-01T11:00:00Z")),
  ]
  let s = @moongpx.track_stats(track_of([seg]))
  assert_eq(s.start_time, Some("2020-01-01T09:00:00Z"))
  assert_eq(s.end_time, Some("2020-01-01T11:00:00Z"))
  assert_eq(s.duration_s, Some(7200.0))
}

///|
test "时长按时区折算，不看字符串字面" {
  // 09:00+08:00 就是 01:00Z
  let seg = [
    pt_at(0.0, 0.0, None, Some("2020-01-01T09:00:00+08:00")),
    pt_at(0.0, 1.0, None, Some("2020-01-01T03:00:00Z")),
  ]
  let s = @moongpx.track_stats(track_of([seg]))
  assert_eq(s.duration_s, Some(7200.0))
}

///|
test "时间无法解析时时长为 None，不影响其他统计" {
  let seg = [
    pt_at(0.0, 0.0, Some(0.0), Some("不是时间")),
    pt_at(0.0, 1.0, Some(10.0), Some("也不是")),
  ]
  let s = @moongpx.track_stats(track_of([seg]))
  assert_eq(s.duration_s, None)
  assert_eq(s.point_count, 2)
  assert_near(s.ascend_m, 10.0, 0.000000001, "爬升")
}

///|
test "track_distance_m 与 track_stats 的距离一致" {
  let t = track_of([[pt(0.0, 0.0), pt(0.0, 1.0)], [pt(1.0, 0.0), pt(1.0, 1.0)]])
  assert_near(
    @moongpx.track_distance_m(t),
    @moongpx.track_stats(t).distance_m,
    0.000001,
    "一致性",
  )
}
