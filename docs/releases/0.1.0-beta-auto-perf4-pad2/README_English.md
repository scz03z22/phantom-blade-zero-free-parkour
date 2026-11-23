# Free Parkour / Auto Explore — experimental build

Version: 0.1.0-beta-auto-perf4-pad2. Features activate automatically after installation; no activation hotkeys are required.

## What's new

This update fixes a widget error in the upward wall-climb script. If a component list still contains an invalid widget component after loading a save or changing areas, the script skips that entry and continues processing the valid components.

All 35 existing UI regression groups and the new invalid-component regression passed. In game, the script encountered and skipped invalid entries twice, on loading the save and on returning from Ximeng to Xigu. The original assertion did not recur. After the round trip, the tap wall kick and held climb both ran with scripted jump input and returned to normal walking. No crash occurred in these tests. The cause of the reported crash remains unconfirmed.

This is an experimental exploration mod. Many visible surfaces in the game have no physical collision. You may fall through scenery, leave the playable map, or become unable to return. This mod does not add missing level collision. Keep a save backup; an existing Traversing Talisman can help you return. The package includes the Lua source code.

## Features and controls

- Automatic wall parkour: jump toward a solid wall, then press jump again (keyboard Space / bottom face button: Xbox A, PlayStation Cross). Tap the second press for a single wall kick and flip; hold it for repeated upward wall kicks. Buffered second presses and angled contact remain supported. Release jump to end the continuous action. Keyboard and controller may be mixed; overlapping holds count as one hold and end only when both are released.
- Repeated kicks use the game's original upward parkour animation. Near a ledge or protrusion, forward probes and landing/path checks attempt to transition to the original hand-assisted vault. Large overhangs, irregular geometry and missing collision can still prevent climbing. Horizontal wall running is disabled in this build.
- Recognized invisible walls have their Pawn collision response disabled: BP_SplineWall actors, plus hidden engine basic Cubes using Profile_LA_InvisibleWall. Visible level geometry is not removed. Other invisible-wall types may remain. The Pawn channel can also affect enemies and NPCs.
- Loaded volumes explicitly using GE_Kill have their Pawn collision response disabled. This is not universal death immunity: other damage, falling rules, scripted deaths and unidentified hazards are not covered.
- Traversing Talisman use does not deduct Item_Traversing. You must already own the item. The mod does not grant it or refill other inventory items.

Environment changes are processed in batches. Allow a few seconds after loading or teleporting; a large number of new objects can take longer. There are no toggle or restoration hotkeys. Runtime collision changes end when the game is fully closed.

## Installation

1. Fully close the game and install a compatible UE4SS prerequisite for this game. UE4SS and its shared libraries are not bundled or replaced.
2. Locate `Game directory\platform\steam\ue4ss\Mods\`.
3. Back up and move out existing `PBZFreeParkour` and `PBZAutoExplore` folders. Copy the two folders inside this package's `Mods` directory into the location above.
4. Do not simultaneously enable `PBZNoSplineWall`, `PBZNearbyKillToggle`, an older Full/Lite version, or other scripts providing the same features. Replace complete folders to avoid leftover files. Do not create a nested `Mods\Mods` directory.
5. Start the game and load your save. Features activate automatically. This package does not register F6/F7/F8/F9 feature toggles. It defaults to keyboard Space and the bottom gamepad face button (Xbox A / PlayStation Cross). Keep UE4SS's existing `Mods\shared` folder intact.

Expected layout: `ue4ss\Mods\PBZFreeParkour\Scripts\main.lua`, with `PBZFreeParkour\enabled.txt` alongside its Scripts folder. PBZAutoExplore has the same layout.

Input check: this version still logs `pad1_input_loaded; jump=SpaceBar|Gamepad_FaceButton_Bottom`. `ue4ss\UE4SS.log` should include `candidate8_loader=no_postponement_for_invalid_object`; `lite_auto_enabled` confirms automatic parkour activation. Some internal legacy log labels still mention F8 or Lite; this package does not require an activation key.

Test environment: game build 302256-17280 and UE4SS 3.0.1 Beta (1ceefac8). Other game/prerequisite versions, input setups and mod combinations have not all been verified.

## Controller and rebinding

The left stick continues to use the game's own movement. Double-press jump: tap the second press for a single wall kick, or hold it for repeated upward kicks. The airborne second-press buffer also accepts controller input. The hold threshold remains approximately 0.18 seconds.

Edit `Mods\PBZFreeParkour\Scripts\input_bindings.lua` to set `keyboard_jump` and `gamepad_jump` independently. These are Unreal key names received by the game; defaults are `SpaceBar` and `Gamepad_FaceButton_Bottom`. Fully restart after editing and match the game's or Steam Input's jump binding. This mod does not automatically read or alter in-game rebinding. For example, use `Gamepad_RightShoulder` if you moved the game's jump to that shoulder button, or `J` for keyboard J. Set either entry to `false` to disable that input source.

The controller must already work in the game. If Steam Input translates a button to Space, the keyboard path also works. This mod does not install a controller driver. Button labels above describe the input received by the game.

This patch passed 26 offline checks covering tap/hold, grounded double-press, airborne buffering, mixed devices, release, player replacement and simulated post-travel resource loading. Physical-controller input has not been tested, and live FPS was not remeasured for pad1. There is no added loop, world enumeration or collision scan. In the idle simulation, each existing 30 ms tick adds at most two key queries and avoids two jump FName constructions. Live performance measurements below belong to the preceding perf4 build.

## Optimization changes

- Fewer repeated player/world lookups, with revalidation when identities change.
- Fewer unnecessary ground wall scans when there is no jump request; airborne input buffering remains.
- Reuse of owned parkour objects and validated component paths to reduce repeated enumeration.
- When the mod needs to load the upward parkour resource itself, it places an owned parkour volume high above the player, disables its trigger box and hides its interaction prompts. This keeps the resource available and reduces repeated loading after garbage collection.
- Delayed verification addresses the identified timing issue that can disable continuous climbing when a class is temporarily unavailable just after loading. The reproduced failure passes offline tests; this does not cover every resource-loading error.
- Repeated automatic lookups in persistent failure states progressively wait up to 60 seconds. Active parkour requests still perform their own resource checks. This defensive reduction has offline count evidence only.
- Invisible walls and GE_Kill volumes use an initial pass and new-object event queues, without recurring full-map scans or restoration journals.

These changes target script overhead and specific stalls. The comparisons so far have not established an average-FPS improvement, nor does this build eliminate all stutter. Initial resource loading, level streaming and complex action startup still have costs.

Measured on the test machine (same spot and camera, standing still for 206 seconds): once the old build's upward parkour loading became blocked, stalls occurred about every 0.5 seconds, totaling 404 frames above 20 ms. This build had none; P99 frame time changed from 31.61 to 9.22 ms, with a maximum of 17.83 ms. Captures began about 2.5 and 2.1 minutes after arrival, respectively, with one independent process per build. This difference applies to the reproduced failure state, not average FPS in general. This build's ordinary frames were not faster than the old build's ordinary frames.

Initial loading still has a cost after arriving in a map without a native upward wall-run point: this build recorded one loader call taking about 55 ms. The preceding build recorded nine repeated calls taking about 34–50 ms; after removing the repeated waiting branch, that pattern was not observed in this session. The 206-second static capture starts after initial loading and excludes that initial stall. Initial loading stutter has not been eliminated.

Saves: during testing the game's save registration was queried read-only. The wall-run volume the mod spawns is registered with the game's level actor manager. After that volume had been used and the game had been saved at a save point, the query showed no saved data for it, and the loaded save data held no entry for such runtime objects. This is an observation from one session in one map. It does not guarantee that saves are never affected; keep a save backup. One vanilla read-back was also done: a test save written after the mod had actually been used was loaded by the unmodified game without UE4SS; the file hash matched and the game entered the scene normally. This is a single smoke check and does not guarantee that no save is ever affected.

A first parkour attempt may be unavailable just after traveling while resources load; land, wait briefly and try again. A runtime error can disable parkour. There is bounded recovery after a map/player identity change (up to three attempts per game session; exceptional recovery rules have only been tested offline). Restart fully if it remains unavailable. This is not a guarantee that the mod cannot affect saves.

## Uninstall / rollback

Fully close the game, then move out PBZFreeParkour and PBZAutoExplore, or remove their enabled.txt files. Restarting clears this mod's runtime collision changes. To roll back, restore complete backed-up folders and avoid enabling both versions together.

For reports, include your game/prerequisite versions, exact location, input sequence and whether you recently teleported. A short video and UE4SS log are useful. Missing level collision and climbing on complex surfaces remain areas for future work.
