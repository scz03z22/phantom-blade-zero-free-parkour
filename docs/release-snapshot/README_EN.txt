PBZ Free Parkour — Phantom Blade Zero
Performance candidate / 0.1.0-beta-perf1 / 2026-11-12 (not uploaded)

[Default controls]
F6: Show/hide detected GE_Kill collision edges within about 30 meters, refreshed about every five seconds. This is not a viewer for all scenery collision. Red means a Pawn response is present; green means ignored or collision disabled.
F8: Toggle free parkour. A bell sound plays when enabled.
F9: Toggle removal of supported invisible barriers. Press again to restore the blocking responses changed by this mod.
F7: Toggle disabling of supported nearby instant-kill volumes. Press again to request restoration.
Space: First press jumps. Briefly press again for a single wall kick and upward flip; hold the second press for continuous upward wall running.
The four toggles are independent and start OFF whenever the game launches. Once enabled, they remain enabled across multiple attempts.
F6/F8/F7/F9 can be rebound as described below. Movement activation still uses Space.

F7/F8/F9 play the bell on enable and the sell sound after disable/restoration. F6 has no toggle sound.

[Beta warning and exploration risks — please read]
This is a beta mod, not complete or reliable support for unrestricted exploration.
Our out-of-bounds tests have found many visible scenery surfaces without effective collision. Players sometimes describe these as “textures without collision.” This does not necessarily mean there is no 3D mesh; the visible surface may simply provide no blocking or footing.
Using parkour, removing barriers or disabling kill volumes—especially beyond the original boundaries—can very easily send you inside scenery, leave you stuck, drop you out of the map or interfere with quests. This mod does not fill missing scenery collision. Disabling kill volumes is not invincibility.
A complete free-roaming experience will require a community effort to identify missing or unsuitable collision and investigate repairs or barriers that follow visible surfaces more closely. Locations, videos, game versions and technical suggestions are welcome. There is currently no reliable automatic repair for the whole map.
Back up your saves. Return to normal, safe solid ground before restoring barriers or kill volumes.

[Two implemented parkour actions]
1. Single wall kick and upward flip
Enable F8, jump near a solid surface that blocks the character, then briefly press Space again. Input buffering supports rapid double presses while already against a wall, double presses while pushing forward into it, and pressing again in the air before making wall contact. Some tolerance is allowed for angled contact; not every orientation or surface is accepted.
Releasing the second press within approximately 0.18 seconds selects the short action. It reuses the original low-wall running-start animation, Hun_Wall_Run_Up_Low_RunStart_Montage, which appears as one kick followed by an upward rotation. No new character animations are imported.
The action uses the game's original special-movement ability. The script attempts to remove excess apex hovering and return to falling, but reaching a standing position on a platform is not guaranteed.

2. Continuous upward wall running
Jump and press Space again, holding the second press for approximately 0.18 seconds or longer. Appropriate solid-wall contact and an available native ability are required.
This reuses the original BP_ASM_UpRunning / GA_ASM_UpRunning sequence: Hun_Unarmed_WallRun_Start_Montage for entry, Hun_Unarmed_WallRun_Loop_Montage for repeated steps, and potentially Hun_Unarmed_CloudStep_End_Montage for the native finish. Hun_Unarmed_WallRun_JumpOut_Forward_Montage may also play during exit, depending on the native state.
Keep holding Space to continue attempting the ascent. Releasing it, losing support, encountering overhead obstruction, making no upward progress, or disabling the mode can request an exit. A normal finishing sequence already in progress is allowed to complete where possible. Each ascent has an approximately 10-second guard limit; this is not unlimited climbing.
After an action ends and you land, wait roughly four seconds before trying again. Existing interactions or special moves may prevent activation. Both actions depend on collision queries, not image/texture recognition. Full-time foot-to-wall IK is not implemented.

[Handling eaves, beams and other protrusions]
The main change measures actual collision-supported tops and landing positions, then adjusts the native action's endpoint. At ascent start, collision is sampled at several depths behind the wall. The character's walkable-slope limit and neighboring support samples determine a candidate height and forward distance. The native finishing rotation then attempts to clear the edge.
A non-blocking query in front of the lower legs is also retained. A clear or solid-blocked sensor tip can permit an attempt to hand off to the character's native mantle component after the ascent ends, provided landing and clearance checks pass. This is supplementary and does not guarantee a mantle animation.
When a trustworthy top cannot be found, bounded climbing can still be attempted, but the mod exits before the synthetic endpoint's finishing window rather than treating an invented height as a real platform. No additional upward finishing impulse is applied.
This improves some locations. Wide eaves, complex projections and missing collision can still interrupt the action or leave the character falling back. Excess upward movement or “launching into the air” remains at some locations; its severity was reduced, not fully fixed. The mod does not guarantee a flip over every beam or protrusion.

[What F9 actually disables]
A. The Pawn-channel blocking response on DynamicMeshComponent components belonging to BP_SplineWall_C actors.
B. StaticMeshActor instances meeting all of these conditions: /Engine/BasicShapes/Cube.Cube mesh, hidden actor or component, and Profile_LA_InvisibleWall collision profile. This covers the hidden cube barriers/supports identified during testing.
Changing a response may cause the engine to rename the profile to Custom. Only previously verified cubes with a matching object identity in the current session remain eligible after that change. Arbitrary Custom-profile meshes are not included.
Objects are not deleted, and other collision channels are not changed. Matching loaded objects are checked approximately every three seconds and processed in batches. This is not a 30-meter-only feature. Newly streamed objects may take a short time to be handled.
Pressing F9 again restores the recorded Pawn responses. Allow time for batched restoration. The entire original profile is not forcibly reapplied, to avoid overwriting other channel settings.
This does not remove every invisible barrier. Other hidden shapes, unidentified blockers and coarse collision belonging to scenery meshes may remain. Visible scenery is not broadly disabled just because it blocks the player, but areas beyond the removed boundaries may still lack collision.

[F7 instant-kill volume toggle]
Only supported volumes explicitly using GE_Kill within approximately 30 meters of the character are selected, based on distance to their boundaries, with an initial scan request and rescans approximately every ten seconds. One region is processed per step, pending progress advances roughly every 0.5 seconds, and failed/no-progress retries wait about three seconds. Safety checks may defer operations; disabling is not instantaneous. It does not remove all death mechanisms, falling damage, KillZ or other damage sources.
Stand still on normal ground and stay roughly three meters away from the volume boundaries when toggling. Movement, being airborne or being too close may cause the operation to be refused or deferred. Leaving the 30-meter range does not automatically restore disabled volumes. Press F7 again to request restoration; if needed, stand still on safe ground and wait.

[Why horizontal wall running is disabled]
Testing found relatively few suitable long, straight walls, and a bug could leave the character floating or launching upward after a horizontal run ended. Horizontal wall running is therefore disabled in this initial beta. Remaining dependency files do not mean the feature is enabled. Airborne chain/rope interaction is also not included.

[Possible future work — not implemented]
• Combine a high wall jump with an attack input to attempt a jumping strike or plunging execution against nearby regular enemies. Native attack abilities, targets and landing conditions still need investigation.
• Improve continuous upward wall running: complex surfaces, protrusions, transitions, ending positions, excessive ascent, performance and stability.
• Explore scenery-collision repairs with the community to improve free roaming.
These are research directions, not included features or delivery-date commitments.

[Installation and rebinding]
1. Exit the game completely and back up your saves. Install a UE4SS build compatible with your current game separately. This archive contains no UE4SS binaries, DLLs or game animation assets.
   Dependency reference: https://www.nexusmods.com/phantombladezero/mods/13
2. Merge the archive's Mods folder into the game's platform\steam\ue4ss folder. Final paths should include:
   platform\steam\ue4ss\Mods\PBZFreeParkour\Scripts\main.lua
   platform\steam\ue4ss\Mods\PBZNearbyKillToggle\Scripts\main.lua
   platform\steam\ue4ss\Mods\PBZNoSplineWall\Scripts\main.lua
   Each module includes enabled.txt. Do not overwrite your mods.txt or create an extra nested Mods folder. Modules can be installed separately.
3. Disable old development modules or duplicate implementations, particularly PBZParkourZipTest and PBZKillZipTest. If the standalone PBZNoSplineWall is already installed, back it up and replace the same module rather than enabling another copy. Check whether an existing mods.txt disables these module names.
4. Edit Scripts\keybindings.lua in the relevant module, for example:
   return { toggle = 'F10' }
   Single F1–F12 keys are supported. For F7/F6, edit PBZNearbyKillToggle/Scripts/keybindings.lua: return { toggle = 'F7', display = 'F6' }. Use different keys for all four functions and avoid conflicts. Restart the game completely after saving. Invalid settings fall back to the default and log the reason. Alternate jump keys, controllers and key combinations are not supported; keep jump bound to Space.
5. There is no complete in-game status panel. UE4SS.log uses [PBZ-PARKOUR], [PBZ-KILL-NEAR] and [NOSPLINEWALL]. Other mods using the same keys or modifying the same collision/state can conflict.
6. To uninstall, return to a safe area, disable parkour and let the action finish, restore F7/F9 changes on normal ground, exit the game, then remove unwanted module folders. If restoration is uncertain, exit normally and restart from a safe save.

[Validation scope and credits]
This performance candidate does not replace the previous release ZIP. See PERFORMANCE.txt for measurements and limitations.
This round tested stationary frame times and individual/combined toggles at the same save point. F9 restored 381 spline components and 15 hidden cubes without reported errors or conflicts. There were no selected kill volumes within 30 meters, so actual F7 writes and dense F6 rendering still need live regression. Earlier player-confirmed movement behavior does not establish full regression of this performance candidate.
Syntax, dependency, integrity and six mocked regression suites passed. Movement performance, long sessions, death/reload/map transitions and live key rebinding are not fully validated. Existing occasional excessive ascent has not been fixed in this round.
UE4SS is a separate dependency. Lua source is included. UE4SS is developed by the UE4SS-RE team and contributors. This mod was developed with player direction, gameplay feedback and generative-AI assistance.
