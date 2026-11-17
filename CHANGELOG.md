# Changelog

## 0.1.0-beta-auto-perf4-pad1

- Add keyboard OR gamepad jump input. Defaults: Space and Gamepad_FaceButton_Bottom (Xbox A / PlayStation Cross).
- Both the host input gate and grounded contact-query wake-up use the same bindings.
- Preserve double-press, airborne pre-input, short/hold selection, release and startup/context baselines.
- Add input_bindings.lua for explicit rebinding; keys must match the game's received jump input.
- Cache jump FKey values. No new game-thread loop, actor enumeration or collision scan.
- 26 offline checks passed. Real hardware-controller play and pad1 live FPS remain unverified.
- All features still activate automatically; perf4 optimizations and AutoExplore are unchanged.

## 0.1.0-beta-auto-perf4

- Automatic activation of vertical parkour, recognized invisible-wall removal, GE_Kill volume disabling and Traversing Talisman no-cost behavior.
- Reduced repeated player/world lookups and unnecessary grounded wall scans.
- Reused owned parkour resources and component paths.
- Kept upward parkour resources available across garbage collection; added bounded late-load verification and identity-aware recovery.
- Fixed rechecks within the late-verification window; progressively spaced futile automatic lookups. Exceptional recovery/backoff cases are covered by offline tests, not a claim of measured normal-play FPS gains.
- Removed repeated postponement on an invalid old class object. The final live build loaded once (about 55 ms) after travel, then showed no frames above 20 ms during its 206-second static capture. Initial loading costs remain.
- No activation hotkeys, restoration queue, debug key bindings, performance recorder or debug overlay included.
- Existing limitations remain: missing level collision, unrecognized blockers/hazards, difficult overhangs and possible action-start or streaming stalls.

This is an experimental automatic variant, not a claim of universally higher FPS. Detailed local benchmark evidence is retained separately from the distributable package.

## 0.1.0-beta-perf1 — 2026-11-12

与 [Nexus 首次公开测试版](https://www.nexusmods.com/phantombladezero/mods/1089) 对应的源码快照。

- 包含短按蹬墙翻身、长按连蹬、附近即死区显示与开关、指定空气墙开关、改键配置和开关音效。
- 性能候选改进：F8 静止停扫及资源准备早退、F7 分批精确处理、F9 批处理时间预算、F6 同次几何收集中的玩家／世界查找复用。
- 静止开关性能已有对照；动作中性能、复杂地点、长时间运行和死亡／读档／换图等仍需继续验证。
- 异常上升、复杂房檐失败和场景碰撞缺失仍是已知问题；未开放横向跑墙和空中锁链互动。
- 上传 GitHub 时仅整理仓库、说明和校验材料，没有修改 48 个已发布 Lua 文件。

Source snapshot matching the first public Nexus experimental release. Includes tap/hold parkour, nearby kill-zone tools, selected barrier toggles, rebindable function keys and audio feedback. Performance changes reduce repeated idle work and bound/batch supported processing. Stationary measurements are not a full stability guarantee. Known movement and missing-collision problems remain. No gameplay source changed during repository preparation.
