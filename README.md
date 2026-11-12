# PBZ Free Parkour / 影之刃零自由跑酷

## 默认快捷键

| 按键 | 功能 |
| --- | --- |
| F6 | 显示／隐藏附近已识别的即死区域线框 |
| F7 | 禁用／恢复附近已识别的即死区域；分批处理，有延迟 |
| F8 | 开启／关闭自由跑酷 |
| F9 | 开启／关闭指定类型空气墙的禁用效果，再按恢复 |

四个功能独立，启动游戏时默认关闭，可在各模块的 `Scripts/keybindings.lua` 改为不同的 F1–F12 单键。F7/F8/F9 开启播放铃声，关闭／恢复完成播放卖出物品声；F6 无开关音效。动作输入目前固定使用空格。

## 当前版本

**0.1.0-beta-perf1，娱乐与探索向测试版。**

- [Nexus Mods 下载与完整发布说明](https://www.nexusmods.com/phantombladezero/mods/1089)
- [本版本标签](https://github.com/scz03z22/phantom-blade-zero-free-parkour/tree/v0.1.0-beta-perf1)
- [中文详细说明（发布包冻结快照）](docs/release-snapshot/README_中文.txt)
- [English detailed instructions (release snapshot)](docs/release-snapshot/README_EN.txt)
- [性能测试范围与限制](docs/release-snapshot/PERFORMANCE.txt)
- [源码使用权限](PERMISSIONS.md)

本仓库的 `Mods/` 源码直接取自 N 网已发布的安装包，48 个 Lua 文件逐字节保持一致，没有在上传过程中修改游戏脚本。原安装包和 SHA-256 校验文件保存在 [`dist/`](dist/)。`docs/release-snapshot/` 保留原包说明、版本文件和清单，里面的“未上传／本地候选”是封包时的状态记录；该版本现已发布，当前发布状态以本 README 和 N 网页面为准。

## 已实装功能与限制

开启 F8 后，朝有实际碰撞的墙壁跳跃，再按第二次空格：

- **短按**：尝试蹬墙翻身／单蹬上翻。
- **持续按住**：尝试连续向上蹬墙，松开请求收尾；短按／长按阈值约 0.18 秒。

第二下支持一定预输入与侧向接触容错。连蹬复用原版特殊蹬柱动作，结合墙顶、支撑、落点、路径与小腿前方查询，尝试衔接原版收尾或手撑翻越。不是所有墙面、凸起或房檐都能成功；少数地点仍可能异常上升／飞天。单次连蹬有约 10 秒保护时限，结束落稳后建议等约 4 秒再试。

F6/F7 只针对附近约 30 米内已识别的 `GE_Kill` 区域，按区域边界距离选取。F6 红框表示角色碰撞响应仍存在，绿框表示响应忽略或碰撞关闭。F7 分批处理，请在正常地面站稳、距区域边界约 3 米以上操作并等待；离开范围不会自动恢复。它不取消所有死亡机制、KillZ、坠落伤害或其他伤害来源。

F9 仅修改以下已加载目标的 Pawn 通道响应：`BP_SplineWall_C.DynamicMeshComponent`，以及持久关卡中使用 `/Engine/BasicShapes/Cube.Cube`、Actor 或组件隐藏、配置为 `Profile_LA_InvisibleWall` 的 `StaticMeshActor`。修改后变成 `Custom` 的立方体，必须已在当前会话验证且对象身份匹配。F9 不限于附近 30 米，检查和恢复均分批进行；其他阻挡可能仍存在。

**越界后极易穿模、卡住、掉出地图或影响任务流程。** 很多可见场景表面没有可用碰撞，本模组不会补齐碰撞，也不会提供完整的全地图自由探索。请备份存档，恢复 F7/F9 前先回安全地面。横向跑墙和空中锁链互动均未开放。

性能优化主要验证了同一存档点的静止开关与组合帧时间，不能据此保证全游戏或动作中稳定。性能版 F7 实际区域写入、密集 F6 线框、长时间跑图、死亡／读档／换图及改键实机仍未完成全部复测。详见随包性能说明。后续方向包括连蹬与落点优化，以及蹬墙升空后接锁敌跳斩／空中处决；这些尚未实装。

## 安装

1. 完全退出游戏、备份存档，单独安装适配游戏的 [OFFICIAL UE4SS for PBZ](https://www.nexusmods.com/phantombladezero/mods/13)。本仓库和安装包均不含加载器或游戏动画资产。
2. 使用 N 网安装包或 `dist/` 中的 ZIP，将 `Mods/` 合并到游戏的 `platform/steam/ue4ss/`，不要多套一层 `Mods`，也不要覆盖自己的 `mods.txt`。
3. 应得到以下入口：

```text
platform/steam/ue4ss/Mods/PBZFreeParkour/Scripts/main.lua
platform/steam/ue4ss/Mods/PBZNearbyKillToggle/Scripts/main.lua
platform/steam/ue4ss/Mods/PBZNoSplineWall/Scripts/main.lua
```

三个模块可分别安装，均含 `enabled.txt`。请停用旧开发模块及同功能副本；已装独立 `PBZNoSplineWall` 的，备份后替换同名模块。跳跃请保持空格；手柄、自定义跳跃键与组合键尚未适配。

## 源码与校验

```text
Mods/PBZFreeParkour/        跑酷动作、接触判断、原版能力衔接与输入
Mods/PBZNearbyKillToggle/   附近 GE_Kill 区域的显示和分批开关
Mods/PBZNoSplineWall/       指定空气墙的 Pawn 响应开关与恢复
docs/release-snapshot/     安装包内的原始双语说明、性能记录及清单
dist/                      与 N 网一致的 ZIP 和 SHA-256
```

已发布 ZIP：`PBZ_Free_Parkour_v0.1.0-beta-perf1_candidate.zip`

```text
SHA256 8411677ab9b6974a8304ff583bcfdcc25ebc94d0889bba49ffd0969543aa5f16
```

源码开放供研究与非商业改进，请按 [PERMISSIONS.md](PERMISSIONS.md) 署名并链接原项目。反馈请附具体地点、游戏版本、按键过程、复现步骤与录像。

## 致谢与 AI 辅助说明

UE4SS 由 UE4SS-RE 团队及贡献者开发；游戏适配包由 KintaroxOe / KintaroModding 发布。模组代码和说明在玩家指导与实机反馈下使用生成式 AI 辅助完成。包内不含 UE4SS 二进制、DLL、存档或游戏资源。

---

## English

**Experimental UE4SS mod for Phantom Blade Zero — 0.1.0-beta-perf1.**

[Nexus download and full description](https://www.nexusmods.com/phantombladezero/mods/1089) · [Detailed English instructions](docs/release-snapshot/README_EN.txt) · [Permissions](PERMISSIONS.md)

| Key | Action |
| --- | --- |
| F6 | Show/hide identified nearby instant-death-zone wireframes |
| F7 | Disable/restore identified nearby zones; batched and delayed |
| F8 | Toggle free parkour |
| F9 | Toggle supported invisible-barrier changes and restore them |

All toggles are independent, off at startup and rebindable to separate F1–F12 keys in each module's `Scripts/keybindings.lua`. Enabling F7/F8/F9 plays a bell; disabling/restoration completion plays the item-selling sound. F6 is silent. Movement currently requires Space.

With F8 enabled, jump toward a wall with actual collision and press Space again. Tap the second press for a single wall kick/upward flip, or hold it for continuous upward wall running (approximately 0.18-second threshold). Limited input buffering and side-contact tolerance are supported. The mod reuses native game moves, including the special pillar-running sequence, and attempts a native ending or hand-supported vault after wall-top, support, landing and clearance checks.

Some eaves fail, and occasional excessive upward movement/launching remains. Climbing has an approximately 10-second guard limit; allow about four seconds after finishing and landing before retrying. Horizontal wall running and airborne chain interaction are excluded.

F6/F7 only target identified `GE_Kill` zones within approximately 30 metres by distance to their boundaries. F7 is not immediate: stand still on normal ground, roughly three metres or more from a zone boundary, and wait. Leaving the radius does not automatically restore disabled zones. Other death mechanisms, KillZ and damage remain possible.

F9 changes only the Pawn response of loaded `BP_SplineWall_C.DynamicMeshComponent` and narrowly selected hidden `/Engine/BasicShapes/Cube.Cube` actors in the persistent level with `Profile_LA_InvisibleWall`. Previously verified, identity-matching cubes may remain eligible after the profile becomes `Custom`; arbitrary Custom meshes are not targeted. F9 is not restricted to the 30-metre radius and does not remove every barrier.

**Visible geometry outside normal boundaries often lacks usable collision.** Clipping, getting stuck, falling out of the map and quest problems are possible. This mod does not repair scene collision or grant invincibility. Back up saves and return to safe ground before restoring F7/F9 changes.

Performance work was primarily measured with stationary toggles at one save point. Actual F7 writes in this revision, dense F6 rendering, active movement, long sessions, death/reload/map changes and live rebinding have not all been retested. See [PERFORMANCE.txt](docs/release-snapshot/PERFORMANCE.txt). Planned aerial attacks/executions and further climbing improvements are not implemented.

Install [OFFICIAL UE4SS for PBZ](https://www.nexusmods.com/phantombladezero/mods/13) separately, then merge the release archive's `Mods/` into `platform/steam/ue4ss/`. Do not overwrite your `mods.txt` or install duplicate modules. Each of the three modules includes `enabled.txt` and can be installed independently. Controllers and custom jump bindings are not adapted.

The 48 Lua files in `Mods/` are byte-identical to the published Nexus archive. The original ZIP and checksum are in `dist/`. Documents in `docs/release-snapshot/` preserve the packaging-time candidate status verbatim; the version is now published, as linked above. No gameplay code was changed for the GitHub upload. Non-commercial modifications and source reuse require credit and a link under [PERMISSIONS.md](PERMISSIONS.md).

UE4SS is developed by the UE4SS-RE team and contributors; the game-compatible package is published by KintaroxOe / KintaroModding. Code and documentation were produced with generative AI assistance under player direction and gameplay feedback. No loader binaries or game assets are bundled.
