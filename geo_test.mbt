///|
/// 坐标与数值类型的黑盒测试。
/// 只通过公开 API 验证，不依赖内部实现。

///|
test "parse_decimal: 合法字面量" {
  for text in ["31.2304", "-90", "90", "90.", ".5", "-0.0", "+1.5", " 31.23 "] {
    match @moongpx.parse_decimal(text) {
      Ok(_) => ()
      Err(e) => fail("应接受 \{text}，却报 \{e.message()}")
    }
  }
}

///|
test "parse_decimal: 拒绝指数记法" {
  // xsd:decimal 不允许指数；1e2 是 xsd:double 的词法形式
  for text in ["1e2", "1E2", "1e-7", "1e+21", "2.5e3"] {
    match @moongpx.parse_decimal(text) {
      Ok(_) => fail("指数记法 \{text} 应被拒绝")
      Err(_) => ()
    }
  }
}

///|
test "parse_decimal: 拒绝 NaN / INF" {
  for text in ["NaN", "INF", "-INF", "Infinity", "nan"] {
    match @moongpx.parse_decimal(text) {
      Ok(_) => fail("\{text} 应被拒绝")
      Err(_) => ()
    }
  }
}

///|
test "parse_decimal: 拒绝畸形输入" {
  for
    text in [
      "", ".", "+", "-", "1.2.3", "abc", "1,5", "--1", "1 2", "１２３",
    ] {
    match @moongpx.parse_decimal(text) {
      Ok(_) => fail("畸形输入 \{text} 应被拒绝")
      Err(_) => ()
    }
  }
}

///|
test "Latitude: 闭区间两端都合法" {
  // 纬度是闭区间 [-90, 90] —— 两端都必须接受
  for text in ["90", "-90", "31.2304", "0", "89.9999", "-45.5"] {
    assert_true(@moongpx.Latitude::from_string(text) is Ok(_))
  }
}

///|
test "Latitude: 越界拒绝" {
  for text in ["90.0001", "-90.0001", "91", "121.4737"] {
    assert_true(@moongpx.Latitude::from_string(text) is Err(_))
  }
}

///|
test "Longitude: 上界排他 —— 180 必须非法" {
  // 这是 GPX 最容易被做错的地方：经度是半开区间 [-180, 180)
  for text in ["180", "180.0", "180.0001", "-180.0001", "181"] {
    assert_true(@moongpx.Longitude::from_string(text) is Err(_))
  }
  for text in ["179.9999", "-180", "121.4737", "0"] {
    assert_true(@moongpx.Longitude::from_string(text) is Ok(_))
  }
}

///|
test "Degrees: [0, 360) 半开区间" {
  for text in ["0", "359.999", "180"] {
    assert_true(@moongpx.Degrees::from_string(text) is Ok(_))
  }
  for text in ["360", "360.1", "-0.1", "-1"] {
    assert_true(@moongpx.Degrees::from_string(text) is Err(_))
  }
}

///|
test "DgpsStationId: [0, 1023] 闭区间整数" {
  for text in ["0", "1023", "12", "007"] {
    assert_true(@moongpx.DgpsStationId::from_string(text) is Ok(_))
  }
  for text in ["1024", "-1", "12.0", "1e3", ""] {
    assert_true(@moongpx.DgpsStationId::from_string(text) is Err(_))
  }
}

///|
test "DgpsStationId: 前导零按数值解析" {
  match @moongpx.DgpsStationId::from_string("007") {
    Ok(v) => assert_eq(v.to_int(), 7)
    Err(e) => fail("007 应可解析：\{e.message()}")
  }
}

///|
test "format_decimal: 绝不输出指数记法" {
  // MoonBit 的 Double::to_string 对 1e-7 / 1e+21 会输出指数，
  // 而 xsd:decimal 禁止指数 —— 必须展开
  assert_eq(@moongpx.format_decimal(1.0e-7), "0.0000001")
  assert_eq(@moongpx.format_decimal(1.0e21), "1000000000000000000000")
  assert_eq(@moongpx.format_decimal(1.0e-21), "0.000000000000000000001")
  assert_eq(@moongpx.format_decimal(2.5e-3), "0.0025")
}

///|
test "format_decimal: 常规值" {
  assert_eq(@moongpx.format_decimal(31.2304), "31.2304")
  assert_eq(@moongpx.format_decimal(-90.0), "-90")
  assert_eq(@moongpx.format_decimal(0.0), "0")
  assert_eq(@moongpx.format_decimal(121.4737), "121.4737")
}

///|
test "format_decimal 的输出必须能被 parse_decimal 接受" {
  // 这是往返一致性的地基：格式化结果必须始终是合法 xsd:decimal
  let values : Array[Double] = [
    0.0,
    -0.0,
    1.0,
    -1.0,
    31.2304,
    -90.0,
    90.0,
    179.9999,
    -180.0,
    1.0e-7,
    1.0e-21,
    1.0e21,
    1.0e-3,
    2.5e-3,
    1.0 / 3.0,
    1.0e-300,
  ]
  for v in values {
    let text = @moongpx.format_decimal(v)
    match @moongpx.parse_decimal(text) {
      Ok(back) =>
        if back != v {
          fail("往返失真：\{v} → \"\{text}\" → \{back}")
        }
      Err(e) =>
        fail(
          "format_decimal(\{v}) 产出 \"\{text}\"，却解析失败：\{e.message()}",
        )
    }
  }
}

///|
test "往返一致：坐标解析 → 格式化 → 再解析" {
  for text in ["31.2304", "-90", "90", "0", "89.9999", "-45.5"] {
    match @moongpx.Latitude::from_string(text) {
      Ok(lat) => {
        let out = lat.to_gpx_string()
        match @moongpx.Latitude::from_string(out) {
          Ok(again) => assert_eq(again.to_double(), lat.to_double())
          Err(e) =>
            fail("纬度往返失败：\{text} → \{out}：\{e.message()}")
        }
      }
      Err(e) => fail("纬度 \{text} 应可解析：\{e.message()}")
    }
  }
}

///|
test "往返一致：经度（含排他上界附近的极值）" {
  for text in ["121.4737", "-180", "179.9999", "0"] {
    match @moongpx.Longitude::from_string(text) {
      Ok(lon) => {
        let out = lon.to_gpx_string()
        match @moongpx.Longitude::from_string(out) {
          Ok(again) => assert_eq(again.to_double(), lon.to_double())
          Err(e) =>
            fail("经度往返失败：\{text} → \{out}：\{e.message()}")
        }
      }
      Err(e) => fail("经度 \{text} 应可解析：\{e.message()}")
    }
  }
}

///|
test "GeoError::message 能带出原始文本与区间" {
  match @moongpx.Longitude::from_string("180") {
    Ok(_) => fail("180 应被拒绝")
    Err(e) => {
      let msg = e.message()
      assert_true(msg.contains("180"))
      assert_true(msg.contains("[-180, 180)"))
    }
  }
}
