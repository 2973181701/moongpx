// moongpx —— GPX (GPS Exchange Format) 规范实现
//
// 模块元信息：https://docs.moonbitlang.com/en/latest/toolchain/moon/module.html

name = "2973181701/moongpx"

version = "0.1.0"

readme = "README.md"

repository = "https://github.com/2973181701/moongpx"

license = "Apache-2.0"

keywords = [ "gpx", "gps", "track", "wgs84", "geo", "xml", "parser" ]

preferred_target = "wasm-gc"

description = "A spec-compliant GPX (GPS Exchange Format) library for MoonBit: parse, validate, serialize and migrate GPX 1.0 / 1.1 with line-accurate diagnostics."

import {
  "Milky2018/xml@0.4.1",
}
