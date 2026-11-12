# Changelog

## 0.1.0-beta-perf1 — 2026-11-12

与 [Nexus 首次公开测试版](https://www.nexusmods.com/phantombladezero/mods/1089) 对应的源码快照。

- 包含短按蹬墙翻身、长按连蹬、附近即死区显示与开关、指定空气墙开关、改键配置和开关音效。
- 性能候选改进：F8 静止停扫及资源准备早退、F7 分批精确处理、F9 批处理时间预算、F6 同次几何收集中的玩家／世界查找复用。
- 静止开关性能已有对照；动作中性能、复杂地点、长时间运行和死亡／读档／换图等仍需继续验证。
- 异常上升、复杂房檐失败和场景碰撞缺失仍是已知问题；未开放横向跑墙和空中锁链互动。
- 上传 GitHub 时仅整理仓库、说明和校验材料，没有修改 48 个已发布 Lua 文件。

Source snapshot matching the first public Nexus experimental release. Includes tap/hold parkour, nearby kill-zone tools, selected barrier toggles, rebindable function keys and audio feedback. Performance changes reduce repeated idle work and bound/batch supported processing. Stationary measurements are not a full stability guarantee. Known movement and missing-collision problems remain. No gameplay source changed during repository preparation.
