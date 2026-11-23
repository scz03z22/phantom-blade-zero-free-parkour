# 0.1.0-beta-auto-perf4-pad2 (2026-11-24)

## 中文

本次更新修复了向上蹬墙脚本处理界面组件时的一处报错。读档或切换场景后，如果组件列表里还留有已失效的组件，脚本会跳过它并继续处理其余有效组件，避免本轮扫描被中断。

35 组原有界面回归测试和新增的失效组件用例通过。实机读档及从西盟返回溪谷时，两次识别并跳过了失效组件，未再出现对应断言。跨图往返后，短按上翻和长按连蹬均通过脚本模拟跳跃输入触发，并恢复正常行走。测试中未闪退，玩家报告的那次闪退根因仍未确认。

## English

This update fixes a widget error in the upward wall-climb script. If a component list still contains an invalid widget component after loading a save or changing areas, the script skips that entry and continues processing the valid components.

All 35 existing UI regression groups and the new invalid-component regression passed. In game, the script encountered and skipped invalid entries twice, on loading the save and on returning from Ximeng to Xigu. The original assertion did not recur. After the round trip, the tap wall kick and held climb both ran with scripted jump input and returned to normal walking. No crash occurred in these tests. The cause of the reported crash remains unconfirmed.

# 0.1.0-beta-auto-perf4-pad1

- Add keyboard OR gamepad jump input. Defaults: Space and Gamepad_FaceButton_Bottom (Xbox A / PlayStation Cross).
- Both the host input gate and grounded contact-query wake-up use the same bindings.
- Preserve double-press, airborne pre-input, short/hold selection, release and startup/context baselines.
- Add input_bindings.lua for explicit rebinding; keys must match the game's received jump input.
- Cache jump FKey values. No new game-thread loop, actor enumeration or collision scan.
- 26 offline checks passed. Real hardware-controller play and pad1 live FPS remain unverified.
- All features still activate automatically; perf4 optimizations and AutoExplore are unchanged.

# 0.1.0-beta-auto-perf4

- Automatic activation of vertical parkour, recognized invisible-wall removal, GE_Kill volume disabling and Traversing Talisman no-cost behavior.
- Reduced repeated player/world lookups and unnecessary grounded wall scans.
- Reused owned parkour resources and component paths.
- Kept upward parkour resources available across garbage collection; added bounded late-load verification and identity-aware recovery.
- Fixed rechecks within the late-verification window; progressively spaced futile automatic lookups. Exceptional recovery/backoff cases are covered by offline tests, not a claim of measured normal-play FPS gains.
- Removed repeated postponement on an invalid old class object. The final live build loaded once (about 55 ms) after travel, then showed no frames above 20 ms during its 206-second static capture. Initial loading costs remain.
- No activation hotkeys, restoration queue, debug key bindings, performance recorder or debug overlay included.
- Existing limitations remain: missing level collision, unrecognized blockers/hazards, difficult overhangs and possible action-start or streaming stalls.

This is an experimental automatic variant, not a claim of universally higher FPS. Detailed local benchmark evidence is retained separately from the distributable package.
