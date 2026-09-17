"""把 testdata/ 里的真实 GPX 文件嵌入为 MoonBit 测试源码。"""
import os
import re

ROOT = r"D:\WorkBuddy_项目\moongpx"
TD = os.path.join(ROOT, "testdata")

FILES = [
    ("runkeeper_src", "gpx_with_garmin_extension.gpx"),
    ("unicode_src", "unicode.gpx"),
    ("cerknicko_src", "cerknicko-jezero.gpx"),
]

CREATOR = "GPSBabel - http://www.gpsbabel.org"


def embed(var, text):
    lines = text.split("\n")
    while lines and lines[-1].strip() == "":
        lines.pop()
    while lines and lines[0].strip() == "":
        lines.pop(0)
    out = ["let %s =" % var]
    for l in lines:
        out.append("  #|" + l)
    return "\n".join(out)


def read(fname):
    return open(os.path.join(TD, fname), encoding="utf-8").read()


# 从真实文件里抽出最长的一段轨迹（真实坐标，不是构造数据）
full = read("cerknicko-jezero.gpx")
trks = re.findall(r"<trk>.*?</trk>", full, re.S)
best = max(trks, key=lambda t: t.count("<trkpt"))
n_pts = best.count("<trkpt")
track_only = (
    '<gpx version="1.0" creator="%s" xmlns="http://www.topografix.com/GPX/1/0">\n'
    % CREATOR
    + best
    + "\n</gpx>\n"
)

parts = []
parts.append(
    """// 真实世界导出的 GPX 文件（来源与许可见 testdata/SOURCES.md）
//
// 与其余 *_test.mbt 中手工构造的测试向量不同，这里的输入是
// 真实软件（Runkeeper App / GPSBabel）产出的字节，用于验证
// 「真实文件能不能解析」，而不是「规范条文有没有实现」。
//
// 本文件由脚本从 testdata/ 生成，请勿手工编辑。"""
)

for var, fname in FILES:
    parts.append(embed(var, read(fname)))

parts.append(embed("cerknicko_trk_src", track_only))

parts.append(
    '''
test "真实文件 / Runkeeper 导出：GPX 1.1 + 私有扩展" {
  match @moongpx.parse_gpx(runkeeper_src) {
    Ok(g) => {
      assert_eq(g.version, "1.1")
      assert_eq(g.waypoints.length(), 1)
    }
    Err(diags) =>
      fail("Runkeeper 文件解析失败: " + @moongpx.format_diagnostics(diags))
  }
}

test "真实文件 / GPSBabel + Unicode：GPX 1.0 升级" {
  match @moongpx.parse_gpx_any(unicode_src) {
    Ok(g) => {
      assert_eq(g.waypoints.length(), 6)
    }
    Err(diags) =>
      fail("unicode 文件解析失败: " + @moongpx.format_diagnostics(diags))
  }
}

test "真实文件 / 不合规样本必须被拒绝（GPSBabel 的老问题）" {
  // 这个真实文件把 <time> 写在了 <sym> 之后，违反 wpt 的子元素顺序。
  // 多数解析器会静默接受并给出错误结果；本库必须明确报 E1013。
  match @moongpx.parse_gpx_any(cerknicko_src) {
    Ok(_) => fail("该文件不合规（wpt 子元素顺序错），不应被接受")
    Err(diags) => {
      let mut found = false
      for d in diags {
        if d.code == @moongpx.code_wpt_order {
          found = true
        }
      }
      assert_eq(found, true)
    }
  }
}

test "真实文件 / GPSBabel 轨迹段：%d 个真实坐标点" {
  match @moongpx.parse_gpx_any(cerknicko_trk_src) {
    Ok(g) => {
      assert_eq(g.tracks.length(), 1)
      let st = @moongpx.track_stats(g.tracks[0])
      assert_eq(st.point_count, %d)
      assert_eq(st.distance_m > 0.0, true)
    }
    Err(diags) =>
      fail("轨迹段解析失败: " + @moongpx.format_diagnostics(diags))
  }
}
'''
    % (n_pts, n_pts)
)

out = "\n\n///|\n\n".join(parts) + "\n"
p = os.path.join(ROOT, "realworld_test.mbt")
open(p, "w", encoding="utf-8", newline="\n").write(out)
print(
    "已生成 %s（%d 行）；轨迹段 %d 个真实点"
    % (p, out.count("\n") + 1, n_pts)
)
