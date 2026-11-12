-- Candidate: BP_SplineWall plus hidden Cube/Profile_LA_InvisibleWall; Pawn response only.
-- F9 restores responses changed by this mod; F9 again enables it.
local UEHelpers = require('UEHelpers')
local enabled = false
local changed = {}
local function log(s)
 if not s:match('^ignored ') and not s:match('^restored ') then
  print('[NOSPLINEWALL] '..s..'\n')
 end
end
local function valid(o)
 local ok,v=pcall(function() return o and o:IsValid() end);return ok and v
end
local function status(s) end
local scripts=assert(debug.getinfo(1,'S').source:match('^@(.+[\\/])[^\\/]+$'))
local cubes=assert(loadfile(scripts..'hidden_cube_walls_v1.lua'))().new(log)
local toggle_requests=0
local feedback=nil
local feedback_pending=nil
local function sound(kind)
 local ok,err=pcall(function()
  if not feedback then feedback=assert(loadfile(scripts..'toggle_feedback_v1.lua'))().new(UEHelpers,log) end
  feedback.play(kind)
 end)
 if not ok then log('toggle_feedback_error='..tostring(err)) end
end

local function scan()
 if not enabled then return end
 local p=UEHelpers.GetPlayer();if not valid(p) then return end
 local cap=p.CapsuleComponent;if not valid(cap) then return end
 local channel=cap:GetCollisionObjectType();if channel~=2 then status('unexpected player channel '..tostring(channel));return end
 cubes.scan()
 local actors=FindAllOf('BP_SplineWall_C') or {};local loaded,modified=0,0
 for _,actor in ipairs(actors) do
  local ok,err=pcall(function()
   if not valid(actor) then return end
   local name=actor:GetFullName();if not name:find(':PersistentLevel.',1,true) then return end
   local component=actor.DynamicMeshComponent;if not valid(component) then return end
   loaded=loaded+1
   local current=component:GetCollisionResponseToChannel(channel)
   local record=changed[name]
   if record and not valid(record.component) then changed[name]=nil;record=nil end
   if current==2 then
    if not record then changed[name]={component=component,channel=channel,original=current} end
    component:SetCollisionResponseToChannel(channel,0)
    if component:GetCollisionResponseToChannel(channel)==0 then modified=modified+1;log('ignored '..name) end
   end
  end)
  if not ok then log('scan_actor_error '..tostring(err)) end
 end
 local count=0;for _,record in pairs(changed) do if valid(record.component) then count=count+1 end end
 status('enabled=true\nloaded_spline_walls='..loaded..'\nchanged_live='..count..'\nchanged_this_scan='..modified)
 return true
end
local function restore()
 cubes.restore()
 local restored,errors=0,0
 for name,record in pairs(changed) do
  local ok,err=pcall(function()
   if valid(record.component) and record.component:GetCollisionResponseToChannel(record.channel)==0 then
    record.component:SetCollisionResponseToChannel(record.channel,record.original)
    assert(record.component:GetCollisionResponseToChannel(record.channel)==record.original,'readback mismatch')
    restored=restored+1;log('restored '..name)
   end
  end)
  if not ok then errors=errors+1;log('restore_error '..name..' '..tostring(err)) end
 end
 if errors==0 then changed={} end
 status('enabled=false\nrestored='..restored..'\nrestore_errors='..errors)
 log('disabled restored='..restored..' errors='..errors)
end

-- Release-only key configuration. Invalid settings retain the default key.
local pbz_toggle_name = 'F9'
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
if not pbz_key_ok then log('keybindings invalid or missing; using F9: '..tostring(pbz_key_error)) end
local pbz_toggle_key = Key[pbz_toggle_name]
log('toggle_key='..pbz_toggle_name..'; changes require a game restart')


-- Key callbacks only enqueue intent; all UObject work runs in one persistent
-- game-thread loop. Do not create transient ExecuteInGameThread callbacks.
RegisterKeyBind(pbz_toggle_key,function() toggle_requests=toggle_requests+1 end)
local scan_ticks=0
local function tick()
 local ok,err=pcall(function()
  if toggle_requests>0 then
   toggle_requests=toggle_requests-1
   if cubes.restoring() then
    log('toggle_deferred=cube_restore_in_progress; retry after completion')
   else
    enabled=not enabled
    if enabled then
     log('enabled by '..pbz_toggle_name)
     feedback_pending='enabled'
     if scan() then sound('enabled');feedback_pending=nil end
    else
     feedback_pending='disabled';restore()
    end
    scan_ticks=0
   end
  end
  -- Restore must continue even when the effect is disabled.
  if cubes.pending() then cubes.step() end
  if feedback_pending=='disabled' and not enabled and not cubes.pending() then
   local result=cubes.restore_result()
   if result and result.errors==0 and result.conflicts==0 and result.remaining==0 and next(changed)==nil then
    feedback_pending=nil;sound('disabled')
   elseif result then
    feedback_pending=nil;log('disable_feedback_withheld=restore_unconfirmed')
   end
  end
  scan_ticks=scan_ticks+1
  if scan_ticks>=30 then
   scan_ticks=0
   if enabled and scan() and feedback_pending=='enabled' then feedback_pending=nil;sound('enabled') end
  end
 end)
 if not ok then log('game_thread_tick_error '..tostring(err)) end
 return false
end
assert(type(LoopInGameThreadWithDelay)=='function','game-thread loop unavailable')
local loop_handle=LoopInGameThreadWithDelay(100,tick)
assert(loop_handle,'unable to install game-thread loop')
log('loaded; disabled by default; configured key toggles')
log('hidden_cube_candidate_v3_loaded; verified_Custom_retoggle=true; batch=64; persistent_game_thread=true')

log('toggle_audio_v1_loaded; disable_sound_after_restore')
