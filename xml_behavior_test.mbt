///|
/// 锁住我们对 `Milky2018/xml` 的行为假设。
///
/// 这些不是"测别人的库"，而是**固定我们自己依赖的前提**：
/// 一旦升级 `xml` 版本后这些用例挂了，说明我们的解析/序列化逻辑
/// 会随之出错，必须重新评估，而不是等到线上才发现。
///
/// 每一条都在 `README.md` 的「依赖行为约定」里对应说明。

///|
test "依赖行为：默认命名空间被自动剥离" {
  // 这是最常见的真实 GPX 写法。@xml 会把 xmlns 摘掉，
  // 所以根元素名仍是 "gpx" —— 我们的 parse_gpx 依赖这一点。
  let src = "<gpx xmlns=\"http://www.topografix.com/GPX/1/1\" version=\"1.1\" creator=\"x\"><wpt lat=\"1\" lon=\"2\"><name>a</name></wpt></gpx>"
  let g = match @moongpx.parse_gpx(src) {
    Ok(g) => g
    Err(d) => fail(@moongpx.format_diagnostics(d))
  }
  assert_eq(g.waypoints.length(), 1)
}

///|
test "已知边界：带前缀的元素名不被剥离" {
  // ⚠️ 这是**已知限制**，不是期望行为。
  // @xml 的 Reader 不解析命名空间前缀，`<g:gpx>` 的 name 就是字面 "g:gpx"。
  // 因此使用前缀写法的 GPX 文档目前会被判为"根元素不是 gpx"。
  // 用 Reader 之外的 NamespaceReader 可以解决，留待后续版本。
  let src = "<g:gpx xmlns:g=\"http://www.topografix.com/GPX/1/1\" version=\"1.1\" creator=\"x\"></g:gpx>"
  match @moongpx.parse_gpx(src) {
    Ok(_) =>
      fail(
        "当前实现不应接受前缀写法（若已支持请更新此用例与 README）",
      )
    Err(d) => assert_true(d[0].code == @moongpx.code_root_not_gpx)
  }
}

///|
test "依赖行为：预定义实体被解码" {
  // 解析侧解码 → 序列化侧必须转义，两侧配对才成立。
  let src = "<gpx version=\"1.1\" creator=\"x\"><wpt lat=\"1\" lon=\"2\"><desc>a&amp;b&lt;c&gt;d&quot;e</desc></wpt></gpx>"
  let g = match @moongpx.parse_gpx(src) {
    Ok(g) => g
    Err(d) => fail(@moongpx.format_diagnostics(d))
  }
  match g.waypoints[0].desc {
    Some(t) => assert_eq(t, "a&b<c>d\"e")
    None => fail("desc 丢失")
  }
}

///|
test "依赖行为：数字字符引用 &#13; 被解码为 CR" {
  // 关键：因为解析器会把 &#13; 还原成 CR，
  // 序列化器就必须把 CR 再转义回 &#13;，否则被 XML 的换行规范化折成 LF。
  let src = "<gpx version=\"1.1\" creator=\"x\"><wpt lat=\"1\" lon=\"2\"><desc>x&#13;y</desc></wpt></gpx>"
  let g = match @moongpx.parse_gpx(src) {
    Ok(g) => g
    Err(d) => fail(@moongpx.format_diagnostics(d))
  }
  match g.waypoints[0].desc {
    Some(t) => {
      assert_eq(t.length(), 3)
      assert_true(t.contains("\r"))
    }
    None => fail("desc 丢失")
  }
}

///|
test "依赖行为：CDATA 内容被取出为纯文本" {
  // 结果是：CDATA 经过一次序列化后变成转义文本（字节不同、值相同）。
  // 往返一致性比较的是**模型**，所以不受影响。
  let src = "<gpx version=\"1.1\" creator=\"x\"><wpt lat=\"1\" lon=\"2\"><name><![CDATA[a<b]]></name></wpt></gpx>"
  let g = match @moongpx.parse_gpx(src) {
    Ok(g) => g
    Err(d) => fail(@moongpx.format_diagnostics(d))
  }
  match g.waypoints[0].name {
    Some(t) => assert_eq(t, "a<b")
    None => fail("name 丢失")
  }
  let s = @moongpx.to_gpx(g)
  assert_true(s.contains("<name>a&lt;b</name>"))
}

///|
test "依赖行为：Double::to_string 会输出指数记法" {
  // 这是 format_decimal 存在的**唯一理由**。
  // 若哪天 MoonBit 改成不用指数，此用例会失败——那是好事，提醒我们简化实现。
  assert_eq(1.0e-7.to_string(), "1e-7")
  assert_eq(1.0e21.to_string(), "1e+21")
  // 而 format_decimal 必须把它展开
  assert_eq(@moongpx.format_decimal(1.0e-7), "0.0000001")
  assert_eq(@moongpx.format_decimal(1.0e21), "1000000000000000000000")
}

///|
test "依赖行为：Double::to_string 对整数值省略小数点" {
  assert_eq(90.0.to_string(), "90")
  assert_eq(@moongpx.format_decimal(90.0), "90")
}
