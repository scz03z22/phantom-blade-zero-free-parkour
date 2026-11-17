# PBZ Free Parkour / 影之刃零自由跑酷

**Current source / 当前源码：`0.1.0-beta-auto-perf4-pad1`**

- [Nexus Mods：下载与发布说明 / Downloads](https://www.nexusmods.com/phantombladezero/mods/1089)
- [与 Nexus 一致的安装包 / Published ZIP](dist/PBZ_AutoExplore_0.1.0-beta-auto-perf4-pad1.zip) · [SHA-256](dist/PBZ_AutoExplore_0.1.0-beta-auto-perf4-pad1.zip.sha256)
- [更新记录 / Changelog](CHANGELOG.md) · [源码使用权限 / Source permissions](PERMISSIONS.md)
- [本版原始包内说明与清单 / Release documentation and manifest](docs/releases/0.1.0-beta-auto-perf4-pad1/)

`Mods/` 的 41 个运行文件直接取自已发布 ZIP，逐字节核对一致。本次 GitHub 同步未修改游戏逻辑。旧按键版源码保留在 Git 历史，旧包位于 `dist/`；旧说明位于 `docs/release-snapshot/`，不适用于当前自动版。

The 41 runtime files in `Mods/` match the published ZIP byte for byte. This sync does not change gameplay code. The old hotkey source remains in Git history; its ZIP and documentation are retained separately. Install only the current `PBZFreeParkour` and `PBZAutoExplore` modules together, without the old duplicate modules.

## 自动生效优化测试版 — 0.1.0-beta-auto-perf4-pad1

### 基础功能与快速上手

安装后进入存档即自动生效，不需按键开启：

- 自由跑酷：蹬墙上翻和连续向上蹬墙。

- 去空气墙：取消大部分常见、已识别类型的拦路空气墙，方便探索原本被阻挡的区域。

- 禁用即死区域：自动禁用已加载、明确识别的 GE_Kill 区域。角色进入这类区域时不再因该区域触发即死。

- 穿行符无消耗：使用背包中已有的穿行符时不消耗数量。（因为游戏中有大量地形只有贴图没有碰撞，极其容易掉进地形内部。掉进去时尽情使用穿行符吧）

### 跑酷触发方法

默认跳跃键：键盘空格；手柄 Xbox A／PlayStation ×（下方面键，实验适配）。

1. 蹬墙上翻：朝有实体碰撞的墙壁跳跃，碰墙后再次短按跳跃键，会尝试播放“蹬一下墙后翻身上升”的动作。
2. 连续向上蹬墙：同样先跳跃碰墙，再按第二次跳跃并保持按住，会持续向上蹬墙；可随时松开停止。抵达墙顶或遇到凸起时，会结合落脚点和通路检查尝试衔接手撑翻越。
3. 支持预输入：空中尚未碰墙时可以提前按第二下，之后触墙仍可触发；偏侧面接触也保留一定容错。

进入存档或传送后，环境处理会分批完成，请等待数秒。功能覆盖的是已识别目标，不会给没有碰撞的地形补上碰撞。

### 安装说明

### 首次安装

1. 完全退出游戏并备份存档。先下载并按照前置页面安装 UE4SS for Phantom Blade Zero：
https://www.nexusmods.com/phantombladezero/mods/13
2. 解压本模组，将包内 Mods 文件夹中的 PBZFreeParkour 和 PBZAutoExplore 两个文件夹复制到：
游戏目录\platform\steam\ue4ss\Mods\
正确示例：platform\steam\ue4ss\Mods\PBZFreeParkour\Scripts\main.lua
3. 确认两个模块中的 enabled.txt 均保留，不要多套一层 Mods。保留前置自带的 Mods\shared 文件夹，不要覆盖自己的 mods.txt。若 mods.txt 明确禁用了这两个模块，请调整相应条目。
4. 启动游戏并进入存档，等待初始化后即可按上面的跳跃操作使用。无需功能开关按键；本包不含 UE4SS。

### 已安装旧版：升级到本版

适用于旧按键完整版、旧 Lite 自动版，以及之前的自动生效测试版。

1. 回到可靠的实体地面，完全退出游戏；备份存档和旧模组文件夹。
2. 从 ue4ss\Mods 中移走旧 PBZFreeParkour、PBZAutoExplore 文件夹，再放入新版同名文件夹，避免旧脚本残留。不要把备份留在 Mods 中继续加载。
3. 同时移除或停用旧 PBZNoSplineWall、PBZNearbyKillToggle，以及其他提供相同功能的副本；这些功能已由本版接管，不要混装运行。
4. 保留正常工作的 UE4SS 前置、Mods\shared、自己的 mods.txt 和其他无关模组；已有兼容前置无需为这次升级重复安装。不要用旧脚本覆盖新版。自定义键位可按新版 input_bindings.lua 重新填写。
5. 检查新版两个模块的 enabled.txt 及 mods.txt 启用状态，重新启动游戏。之后跑酷、去空气墙、禁用已识别即死区域、穿行符无消耗均自动生效。

### 动作、改键与使用限制

两种动作均调用原版动画；连蹬沿用特殊蹬柱动作流程，在顶部或凸起附近结合前方探测、落脚和通路检查，尝试衔接原有手撑翻越。短按与长按的分界约为 0.18 秒，落稳后建议间隔约 4 秒再试。复杂屋檐不保证能翻过，少数地点仍可能异常上升。横向跑墙仍暂停提供：适用场地有限，且此前出现过退出后浮空／飞天问题。

支持通过 PBZFreeParkour\Scripts\input_bindings.lua 修改模组读取的跳跃键。默认 keyboard_jump = 'SpaceBar'、gamepad_jump = 'Gamepad_FaceButton_Bottom'。修改后需重启游戏，并与游戏内或 Steam Input 的跳跃绑定保持一致；模组不会自动同步游戏内改键。键盘与手柄可以混用。

手柄适配通过了 26 项离线检查，尚未使用实体手柄验证，欢迎反馈手柄型号、连接方式及操作情况。穿行符无消耗的完整背包使用流程仍待补测。

本自动版不提供运行中的功能关闭和碰撞恢复热键。需要恢复原版行为时，请回到安全实体地面，完全退出游戏，停用或移除 PBZFreeParkour 与 PBZAutoExplore 后重新启动。File archive 中已归档的旧按键版、Optional files 中的旧 Lite 是不同版本，不应与本版混装；它们的操作请参阅各自包内说明。

本 Mod 仍为娱乐探索性质的测试版，不会给场景补充碰撞。游戏中存在大量只有可见模型、没有实际碰撞的地方，开启这些功能后仍可能掉进地形、越出地图、卡住或影响任务流程。其他类型的空气墙、死亡机制及复杂地形尚未全部覆盖。Lua 源码完整包含在安装包中，欢迎大家共同定位并修补场景碰撞。

后续会继续优化性能、连续蹬墙和复杂地形上的动作衔接，并探索蹬墙升空后接跳斩／普通敌人空中处决；这些后续玩法尚未实装。

### 详细优化内容

这次更新主要减少了模组运行中的重复扫描、对象查找和资源加载，针对传送后连续蹬墙失效、反复出现周期性卡顿的问题进行了优化。部分场景的卡顿已有明显改善，但首次加载和地图流送仍可能产生短暂停顿。

- 调整环境处理方式：首次分批处理已加载的空气墙和即死区域，后续通过新对象加载事件补充处理，减少周期性全图扫描。

- 移除恢复队列：自动版不再维护手动关闭功能所需的碰撞恢复记录，减少相关管理开销。

- 减少重复查找：复用已验证的角色、世界及组件信息，在传送或角色变化后重新核验。

- 减少无用碰撞检测：地面没有跳跃请求时减少墙面扫描，保留跳跃、空中预输入和实际蹬墙所需的检测。

- 改善跑酷资源管理：减少连续蹬墙资源被回收后反复查找、重新加载的情况，修正部分传送后连续蹬墙失效的问题。

- 降低异常重试频率：持续加载失败时逐步延长重试间隔，避免高频失败查找造成反复卡顿。

- 控制手柄适配开销：沿用现有输入循环，不增加世界扫描或碰撞检测，并缓存跳跃按键数据。

空气墙功能针对 BP_SplineWall 和符合隐藏、基础 Cube、Profile_LA_InvisibleWall 条件的对象，不删除地图资源或普通可见模型碰撞。环境修改作用于 Pawn 通道，也可能影响敌人和 NPC。即死区域功能仅处理已识别的 GE_Kill 区域，不取消所有脚本死亡、KillZ 或坠落伤害。

在本机复现的一处传送后周期性卡顿场景中，约 206 秒内超过 20 毫秒的慢帧由旧版的 404 帧降至 0 帧，P99 帧时间由 31.61 毫秒降至 9.22 毫秒。这些数据来自手柄补丁之前的性能优化版，针对该异常场景，不代表所有电脑、地图都能获得相同改善。首次资源加载仍记录到约 55 毫秒的一次耗时，发生在正式静置采样之前；手柄补丁尚未重测实机帧率。

### 致谢与源码
UE4SS 由 UE4SS-RE 团队及贡献者开发，游戏适配包由 KintaroModding 发布。本模组使用生成式 AI 辅助编写代码和说明，结合玩家指导与实机反馈迭代。包内不含 UE4SS、DLL 或游戏动画资产。最新源码以本次下载包内的 Lua 文件为准。
项目仓库：https://github.com/scz03z22/phantom-blade-zero-free-parkour

---
## English

## Auto-Enabled Optimization Beta — 0.1.0-beta-auto-perf4-pad1

### Core features and quick start

Features activate automatically after installation when you load your save. No activation hotkeys are needed:

- Free parkour: a single wall kick/upward flip and continuous upward wall climbing.

- Invisible-wall removal: disables most common supported invisible barriers, letting you explore routes that were previously blocked.

- Instant-death-zone disabling: automatically disables loaded, explicitly identified GE_Kill zones. Entering these zones will no longer trigger their instant-death effect.

- No Traversing Talisman consumption: using a talisman already in your inventory does not reduce its quantity. (Many areas have visible scenery but no collision, making it very easy to fall inside the terrain. If that happens, feel free to use your Traversing Talisman!)

### How to trigger parkour

Default jump input: keyboard Space; Xbox A / PlayStation Cross (the bottom face button; experimental controller support).

1. Single wall kick/flip: jump toward a wall with actual collision, then tap jump again after making contact. This attempts a wall kick followed by an upward flip.
2. Continuous upward climbing: jump into the wall, then press jump again and keep the second press held to climb upward. Release at any time to stop. At a wall top or protrusion, landing and path checks attempt to transition into a hand-assisted vault.
3. Input buffering: you can press jump a second time while airborne before reaching the wall; later contact can still trigger the move. Some tolerance for angled contact is retained.

Environment processing runs in batches after loading a save or teleporting, so allow a few seconds. Only recognized targets are handled; the mod does not add collision to terrain that lacks it.

### Installation

### First-time installation

1. Fully exit the game and back up your save. Download and install UE4SS for Phantom Blade Zero according to its prerequisite page:
https://www.nexusmods.com/phantombladezero/mods/13
2. Extract this mod. Copy PBZFreeParkour and PBZAutoExplore from the archive's Mods folder into:
Game directory\platform\steam\ue4ss\Mods\
Correct example: platform\steam\ue4ss\Mods\PBZFreeParkour\Scripts\main.lua
3. Keep enabled.txt in both modules and do not add an extra Mods folder level. Preserve the prerequisite's Mods\shared folder and your own mods.txt. If mods.txt explicitly disables either module, adjust the corresponding entries.
4. Start the game, load your save and allow initialization to finish. Use the jump controls above; no feature-toggle keys are needed. UE4SS is not included.

### Upgrading from an older version

This applies to the old hotkey Full edition, old auto-enabled Lite edition, and earlier automatic test builds.

1. Return to reliable solid ground, fully exit the game, and back up your save and old mod folders.
2. Move the old PBZFreeParkour and PBZAutoExplore folders out of ue4ss\Mods, then install the new folders. Replace the folders rather than retaining old scripts. Keep backups outside Mods so they cannot load.
3. Remove or disable old PBZNoSplineWall, PBZNearbyKillToggle and other duplicate scripts providing the same features. This build supplies their functionality; do not run the editions together.
4. Keep your working UE4SS prerequisite, Mods\shared, mods.txt and unrelated mods. A compatible prerequisite does not need reinstalling for this update. Do not overwrite new scripts with old ones. Reapply custom jump bindings using the new input_bindings.lua.
5. Check enabled.txt and any relevant mods.txt entries for the two new modules, then restart. Parkour, supported barrier removal, identified death-zone disabling and no-consumption talismans activate automatically.

### Animations, rebinding and limitations

Both moves reuse original game animations. Continuous climbing uses the native special pillar-running sequence. Near a ledge or protrusion, forward probes and landing/path checks attempt to transition to the original hand-assisted vault. The tap/hold threshold is approximately 0.18 seconds; allow roughly four seconds after landing before trying again. Complex overhangs are not guaranteed to work, and occasional excessive upward movement remains possible. Horizontal wall running is still excluded because suitable locations were limited and exit-related floating/launching bugs occurred.

Rebind the mod's jump input in PBZFreeParkour\Scripts\input_bindings.lua. Defaults: keyboard_jump = 'SpaceBar' and gamepad_jump = 'Gamepad_FaceButton_Bottom'. Fully restart after editing and match the game's or Steam Input's jump binding. The mod does not automatically synchronize with in-game rebinding. Keyboard and controller can be mixed.

Controller support passed 26 offline checks but has not been tested with physical controller hardware. Reports with controller model, connection type and observed behavior are welcome. The complete inventory-use flow for the no-consumption Traversing Talisman feature also remains to be retested.

This automatic edition has no in-session feature-disable or collision-restoration hotkeys. To restore vanilla behavior, return to reliable solid ground, fully exit the game, disable or remove PBZFreeParkour and PBZAutoExplore, and restart. The archived legacy hotkey build in File archive and the old Lite build in Optional files are separate editions: do not install them together with this one. Their controls are documented in their own archives.

This remains an experimental exploration mod. It does not add missing scene collision. Many visible surfaces have no physical collision, so you can still fall through scenery, go out of bounds, get stuck or interfere with quest progression. Other barrier types, death mechanics and complex surfaces are not all covered. The archive includes the complete Lua source; community work to identify and repair missing scene collision is welcome.

Future work includes performance, continuous climbing and transitions over complex geometry, plus exploring plunging attacks/aerial executions against normal enemies after climbing. Those additional combat moves are not implemented yet.

### Detailed optimization changes

This update reduces repeated scans, object lookups and resource loading. It targets periodic stutter and cases where continuous wall climbing stops working after travel. Stutter has improved in a reproduced scenario, but initial loading and level streaming can still cause brief pauses.

- Environment processing: an initial batched pass handles loaded targets; new-object events supply later targets, reducing periodic full-world scans.

- No restoration queue: the automatic edition no longer maintains the collision-restoration records needed by manual feature toggles.

- Fewer repeated lookups: reuse validated player, world and component information, with revalidation after travel or player changes.

- Fewer unnecessary collision queries: reduce grounded wall scans without a jump request while retaining jump, airborne-buffer and active-climb checks.

- Improved parkour resource management: reduce repeated failed lookups and reloads after upward-climbing resources are garbage-collected, and address some post-travel climbing failures.

- Spaced failure retries: progressively wait longer after persistent loading failures instead of repeatedly performing expensive failed lookups.

- Bounded controller-input work: reuse the existing input loop and cache jump-key values; no extra world scans or collision probes are added.

Supported barriers are BP_SplineWall objects and hidden basic Cube objects matching Profile_LA_InvisibleWall. The mod does not delete map assets or remove ordinary visible-model collision. Changes affect the Pawn channel and can also affect enemies/NPCs. Death-zone handling targets identified GE_Kill volumes, not every scripted death, KillZ rule or fall-damage source.

In one reproduced post-travel periodic-stutter scenario on the test machine, frames above 20 ms fell from 404 to 0 over approximately 206 seconds, and P99 frame time improved from 31.61 ms to 9.22 ms. These measurements belong to the performance build before the controller patch and apply to that failure scenario; they are not a promise of the same improvement on every PC or map. One initial loader call still took about 55 ms before the stationary capture began. Live FPS has not been remeasured for the controller patch.

### Credits and source
UE4SS is developed by the UE4SS-RE team and contributors; the game-specific package is published by KintaroModding. Mod code and documentation were developed with generative AI assistance, player direction and gameplay feedback. No UE4SS binaries, DLLs or game animation assets are included. The Lua files in this download are the source for this update.
Project repository: https://github.com/scz03z22/phantom-blade-zero-free-parkour