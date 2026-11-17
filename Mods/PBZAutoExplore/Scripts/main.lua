if PBZ_AUTOEXPLORE then return end
PBZ_AUTOEXPLORE=true
local H=require('UEHelpers')
local dir=assert(debug.getinfo(1,'S').source:match('^@(.+[\\/])[^\\/]+$'))
local function module(n)return assert(loadfile(dir..n))()end
local function log(s)print('[PBZ-AUTO] '..s..'\n')end
local env=module('environment.lua').new(log,module('hidden_cube.lua').matches)
local ready=false
local ticks=0
local function guarded(fn)return function(...)
 local ok,err=pcall(fn,...);if not ok then log('callback_error '..tostring(err))end
end end
RegisterBeginPlayPostHook(guarded(env.notify))
RegisterEndPlayPreHook(guarded(env.endplay))
local function tick()
 ticks=ticks+1
 if not ready and ticks%10==0 then
  local p=H.GetPlayer()
  if p and p:IsValid()and p.CapsuleComponent:IsValid()and p.CapsuleComponent:GetCollisionObjectType()==2 then
   ready=env.begin()
  end
 end
 env.step()
 return false
end
local safe_tick=guarded(tick)
assert(LoopInGameThreadWithDelay(100,function()safe_tick();return false end))
module('talisman.lua').install(log)
log('auto_explore_candidate1_loaded; walls+GE_Kill; no_hotkeys; no_restore')
