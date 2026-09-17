# 测试数据来源

本目录存放**真实世界导出的 GPX 文件**，用于回归测试——区别于
`*_test.mbt` 里依据规范手工构造的测试向量。

## 来源

均取自 Python GPX 库 [gpxpy](https://github.com/tkrajina/gpxpy) 的测试集
（`test_files/` 目录），**Apache-2.0 许可**，与本项目同许可。

| 文件 | 由谁导出 | 版本 | 规模 | 覆盖的场景 |
|---|---|---|---|---|
| `gpx_with_garmin_extension.gpx` | **Runkeeper**（`creator="Runkeeper - http://www.runkeeper.com"`，运动 App） | 1.1 | 597 B / 1 个 `wpt` | 私有 `extensions`（Garmin TrackPointExtension 命名空间前缀）无损保留 |
| `unicode.gpx` | **GPSBabel**（`creator="GPSBabel - http://www.gpsbabel.org"`，通用 GPS 转换工具） | 1.0 | 1.5 KB / 6 个 `wpt` | 非 ASCII 文本（重音字符、CJK）在 1.0 下的往返 |
| `cerknicko-jezero.gpx` | **GPSBabel**（同上） | 1.0 | 36 KB / 296 个 `trkpt` + 7 个 `wpt` | 真实长轨迹：GPX 1.0 → 1.1 升级 + 距离 / 爬升统计 |

## 为什么是这三个

它们不是"看起来像"真实文件的构造样本，而是**真实软件产出的字节**：
`creator` 属性里写明生成者，且带有真实世界文件才有的特征——
`xsi:schemaLocation`、私有扩展命名空间、非 ASCII 地名、上千个轨迹点的长序列。

`moon add` 安装本库时**不会**包含此目录（`moon package` 只打包 `.mbt` 源码），
它仅用于本仓库的测试与回归。

## 许可

原始文件 © gpxpy 项目，Apache-2.0。引用时保留来源标注。
