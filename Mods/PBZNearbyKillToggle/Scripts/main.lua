-- STAGED RESEARCH PROTOTYPE, NOT RELEASED OR INSTALLED.
-- F7: independent nearby GE_Kill toggle. This exact entry point assumes no
-- other F7 handler; disable/remove the earlier PBZLocalKillToggle before use.
-- Only a later reviewed package may place these files in UE4SS Mods.
local H=require('UEHelpers')
local src=debug.getinfo(1,'S').source
local dir=type(src)=='string' and src:match('^@(.+[\\/])[^\\/]+$')
assert(dir,'mod script directory unavailable')
local function module(n)return assert(loadfile(dir..n))()end
local policy=module('killzone_selection_policy_v2.lua')
local adapter=module('killzone_unreal_adapter_v2.lua').new(H,{margin_cm=300})
local ctrl=module('killzone_controller_v2.lua').new(policy,adapter,{radius_cm=3000,margin_cm=300})
local rt=module('killzone_runtime_v2.lua').new(ctrl,adapter,{interval_seconds=10})
local function log(s)print('[PBZ-KILL-NEAR] '..tostring(s)..'\n')end
log('f7_perf_targeted_20261112 loaded; rescan=10s; batch=1; failed_retry=3s')
local feedback=nil
local feedback_pending=nil
local function sound(kind,p)
 local ok,err=pcall(function()
  if not feedback then feedback=module('toggle_feedback_v1.lua').new(H,log) end
  feedback.play(kind,p)
 end)
 if not ok then log('toggle_feedback_error='..tostring(err)) end
end
local last='' 
local function display(result)
 local line='status='..tostring(result.status)..' mode='..tostring(result.mode or rt.status())
 for _,field in ipairs({'applied','uncertain','not_applied','pending','conflicts','skipped'})do
  if type(result[field])=='table'then line=line..' '..field..'='..#result[field]end
 end
 if result.reason then line=line..' reason='..tostring(result.reason):sub(1,200)end
 if result.unknown_effect_count then line=line..' unknown_effect_count='..tostring(result.unknown_effect_count)end
 if line~=last then log(line);last=line end
end
local function update()
 local p=H.GetPlayer();if not p or not p:IsValid()then return end
 local now=H.GetGameplayStatics():GetRealTimeSeconds(p)
 local started=os.clock()
 local result=rt.tick(now)
 local elapsed_ms=(os.clock()-started)*1000
 if result.status~='waiting' and result.status~='off' then
  log(string.format('f7_perf_tick status=%s cpu_ms=%.2f',tostring(result.status),elapsed_ms))
 end
 display(result)
 if feedback_pending=='enabled' and rt.status()=='enabled' and result.status=='scanned' then
  feedback_pending=nil;sound('enabled',p)
 elseif feedback_pending=='disabled' and rt.status()=='off' and result.status=='restored' then
  feedback_pending=nil;sound('disabled',p)
 end
end

-- Release-only key configuration. Invalid settings retain the default key.
local pbz_toggle_name = 'F7'
local pbz_key_ok, pbz_key_error = pcall(function()
 local source = debug.getinfo(1,'S').source
 local directory = assert(source:match('^@(.+[\\/])[^\\/]+$'),'script directory unavailable')
 local settings = assert(loadfile(directory..'keybindings.lua'))()
 assert(type(settings)=='table' and type(settings.toggle)=='string','toggle must be a key name')
 local name = settings.toggle:upper()
 local number = tonumber(name:match('^F(%d+)$'))
 assert(number and number>=1 and number<=12 and name=='F'..number,'supported keys: F1 to F12')
 assert(type(Key[name])=='number','key is unavailable in this UE4SS build')
 pbz_toggle_name = name
end)
if not pbz_key_ok then log('keybindings invalid or missing; using F7: '..tostring(pbz_key_error)) end
local pbz_toggle_key = Key[pbz_toggle_name]
log('toggle_key='..pbz_toggle_name..'; changes require a game restart')

RegisterKeyBind(pbz_toggle_key,function()
 ExecuteInGameThread(function()
  local p=H.GetPlayer();if not p or not p:IsValid()then log('no player; key ignored');return end
  local ok,err=pcall(function()
   local result=rt.toggle();log(pbz_toggle_name..' '..result)
   if result=='enabled_pending_scan' then feedback_pending='enabled'
   elseif result=='restoring' or result=='restore_retry_requested' then feedback_pending='disabled' end
   update()
  end)
  if not ok then log('toggle/update error: '..tostring(err):sub(1,250))end
 end)
end)
assert(type(LoopInGameThreadWithDelay)=='function','persistent game-thread scheduler required')
local loop_handle=LoopInGameThreadWithDelay(250,function()
 if rt.status()~='off'then
  local ok,err=pcall(update);if not ok then log('update error: '..tostring(err):sub(1,250))end
 end
 return false
end)
assert(loop_handle,'unable to install persistent game-thread loop')
log('loaded; off by default; configured toggle; GE_Kill only; 30 m selection; not all death sources')

log('toggle_audio_v1_loaded; disable_sound_after_restore')

local display_ok,display_error=pcall(function() module('killzone_display_entry_v1.lua')(H,log,dir,pbz_toggle_key) end)
if not display_ok then log('display_init_failed='..tostring(display_error)) end
