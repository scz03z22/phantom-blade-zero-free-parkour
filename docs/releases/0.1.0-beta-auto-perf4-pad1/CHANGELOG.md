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
