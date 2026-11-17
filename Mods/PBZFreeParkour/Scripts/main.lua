-- Lite: automatically enables after a valid player/input baseline.
-- Double jump uses keyboard Space or the gamepad jump button. No toggle keys.
local scripts=assert(debug.getinfo(1,'S').source:match('^@(.+[\\/])[^\\/]+$'),'script directory unavailable')
local base_helpers=require('UEHelpers')
local H=base_helpers
local enabled=false
local runtime,session,frame,prior_ground=nil,nil,nil,nil
local identity,last_time,ready_after=nil,nil,nil
local previous_arm,previous_space,input_ready=false,false,false
local persistent_state={} -- primitive Lua data only; shared across reloads
local suspended=nil
local faulted=false
local fault_identity,fault_time,fault_drain_failures,fault_drain_blocked=nil,nil,0,false
local fault_recoveries,fault_probe_ticks=0,0
local FAULT_RECOVERY_LIMIT=3
local function log(msg) print('[PBZ-PARKOUR] '..tostring(msg)..'\n') end
local jump_input=assert(loadfile(scripts..'parkour_input.lua'))().new(log)
local function status(msg) end
-- perf4: private facade. Falls back to the shared helper if it cannot be built.
local begin_scope,end_scope=function() end,function() end
do
 local ok,fast=pcall(function() return assert(loadfile(scripts..'pbz_fast_helpers.lua'))().new(base_helpers,log) end)
 if ok and type(fast)=='table' then H=fast;begin_scope,end_scope=fast.begin_scope,fast.end_scope
 else log('fast_player_lookup unavailable='..tostring(fast)) end
end
local host_ticks=0
local function valid(o) local ok,v=pcall(function() return o and o:IsValid() end);return ok and v end
local function stop_session()
 local old=session;session=nil;frame=nil;prior_ground=nil
 if old then pcall(old.stop) end
end
local function stop_runtime(reason)
 if runtime then local ok,err=pcall(runtime.stop,reason);if not ok then log('runtime_stop_error='..tostring(err)) end end
end
local function make_runtime()
 local module=assert(loadfile(scripts..'parkour_runtime_v10.lua'))()
 return assert(module.new(H,log,persistent_state))
end
local function reload()
 if runtime and runtime.busy() then return false,'finishing' end
 local next_runtime=make_runtime()
 local controller=assert(loadfile(scripts..'double_jump_controller_v10.lua'))()
 local sessions=assert(loadfile(scripts..'double_jump_session_v10.lua'))()
 -- Publish atomically only after every constructor and module load succeeds.
 runtime=next_runtime
 return true,{controller=controller,sessions=sessions}
end
local modules=nil
local function create_session()
 assert(modules and runtime,'v10 modules unavailable')
 local env={sample=function() return frame end,start_action=function(initial,current) return runtime.start_action(initial,current) end,
  log=log,on_action=function(t) ready_after=t+4 end}
 session=modules.sessions.new(modules.controller.new(),env,{cooldown=4,ready_after=ready_after})
 log('session_ready player='..tostring(identity)..' ready_after='..tostring(ready_after))
end
local function fault(reason)
 fault_identity,fault_time=identity,last_time
 fault_drain_failures,fault_drain_blocked=0,false
 enabled=false;faulted=true;stop_session();stop_runtime('fault');modules=nil
 identity,last_time,ready_after=nil,nil,nil
 previous_arm,previous_space,input_ready=false,false,false
 status('v10 disabled: error; inspect double_jump_lab.log');log('fault='..tostring(reason))
end
local function suspend(reason)
 stop_session();stop_runtime(reason)
 identity,last_time,ready_after=nil,nil,nil
 previous_arm,previous_space,input_ready=false,false,false
 if suspended~=reason then log('suspended='..reason);suspended=reason end
end
local function check_session(event)
 if session and session.active() then return true end
 if event=='unavailable' then suspend('session_unavailable') else fault('session_'..tostring(event)) end
 return false
end
local function tick()
 begin_scope()
 local ok,err=pcall(function()
  local p=H.GetPlayer();if not valid(p) then suspend('player_unavailable');return end
  local input=p:GetController();if not valid(input) then suspend('controller_unavailable');return end
  -- Keep the legacy space_down field name; it now means logical jump on either device.
  local space_down=jump_input.jump_down(input)
  local arm_edge=input_ready and not enabled and not faulted
  local space_edge=input_ready and space_down and not previous_space
  previous_arm,previous_space,input_ready=false,space_down,true
  if faulted then
   -- A stop request can be asynchronous. Drain only the same player/world and
   -- monotonic clock, with gameplay explicitly disabled. Never reload a busy
   -- runtime; repeated failures leave it quarantined and require a restart.
   local busy_ok,busy=pcall(function() return runtime and runtime.busy() end)
   if not busy_ok then busy=true;fault_drain_blocked=true end
   if busy and not fault_drain_blocked then
    local good,why=pcall(function()
     local s=runtime.sample()
     assert(s and s.player_id and s.world_id and type(s.time)=='number' and s.time==s.time and math.abs(s.time)<math.huge,'invalid drain snapshot')
     assert(fault_identity and s.player_id..'|'..s.world_id==fault_identity and fault_time and s.time>=fault_time,'drain identity or clock changed')
     s.space_down=space_down;runtime.update(s,space_down,false);fault_time=s.time
    end)
    if good then fault_drain_failures=0
    else
     fault_drain_failures=fault_drain_failures+1
     if fault_drain_failures==1 then log('fault_drain_error='..tostring(why)) end
     if fault_drain_failures>=3 then fault_drain_blocked=true;log('fault_drain_blocked; restart required') end
    end
   end
   if fault_drain_blocked then status('v10 disabled: cleanup unconfirmed; restart game required');return end
   local check_ok,still_busy=pcall(function() return runtime and runtime.busy() end)
   if not check_ok then status('v10 disabled: cleanup unconfirmed; restart game required');fault_drain_blocked=true;return end
   -- candidate5: the keyed edition leaves a fault when the user presses its toggle and
   -- nothing is busy. This edition has no key, so the same step is taken by itself, but
   -- only after the player or world identity differs from the one that faulted (travel,
   -- respawn), only when no action is still owned, and at most three times per session.
   -- Identity is read once per 30 host ticks while faulted; nothing else is added.
   if still_busy or fault_recoveries>=FAULT_RECOVERY_LIMIT or type(fault_identity)~='string' then return end
   fault_probe_ticks=fault_probe_ticks+1
   if fault_probe_ticks%30~=0 then return end
   local id_ok,current_id=pcall(function() return p:GetFullName()..'|'..H.GetWorld():GetFullName() end)
   if not id_ok or type(current_id)~='string' or current_id==fault_identity then return end
   fault_recoveries=fault_recoveries+1;faulted=false
   fault_identity,fault_time,fault_drain_failures=nil,nil,0
   identity,last_time,ready_after=nil,nil,nil
   log('fault_recovered count='..fault_recoveries..' of '..FAULT_RECOVERY_LIMIT..'; reason=identity_changed; enabling again as at startup')
   return
  end
  if not runtime then
   -- Disabled fault recovery may prepare a fresh read-only runtime. A held key
   -- is always baselined rather than enabling or initiating a jump.
   runtime=make_runtime();arm_edge=false;space_edge=false
  end
  -- Preserve input baselines, but avoid wall collision queries while disabled
  -- unless an action is still draining or the user requests a fresh enable.
  if not enabled and not arm_edge and not runtime.busy() then return end
  local current=runtime.sample()
  if not current or not current.player_id or not current.world_id then suspend('snapshot_unavailable');return end
  assert(type(current.time)=='number' and current.time==current.time and math.abs(current.time)<math.huge,'invalid sample time')
  current.space_down=space_down
  local current_identity=current.player_id..'|'..current.world_id
  local context_changed=identity~=nil and identity~=current_identity
  local rewound=last_time~=nil and current.time<last_time
  if context_changed or rewound then
   stop_session();stop_runtime(context_changed and 'context_changed' or 'time_rewound')
   identity,last_time,ready_after=nil,nil,nil;arm_edge=false;space_edge=false
   log('context_reset='..(context_changed and 'identity_changed' or 'time_rewound'))
   -- A runtime carrying old identity may only be replaced after cleanup.
   if not runtime.busy() then
    local success,new_modules=reload();assert(success);modules=new_modules
   else
    enabled=false;modules=nil;status('v10 disabled; previous action finishing')
   end
   identity,last_time=current_identity,current.time;suspended=nil
   return -- Never pass an old runtime's snapshot to a newly built runtime.
  end
  identity,last_time=current_identity,current.time;suspended=nil
  if arm_edge then
   if not runtime.busy() then
    local success,new_modules=reload();assert(success)
    modules=new_modules;enabled=true
    log('lite_auto_enabled label='..tostring(runtime.label()))
   end
   space_edge=false
  end
  -- Continue updating a disabled runtime until its owned action is finished.
  runtime.update(current,space_down,enabled)
  if not enabled then return end
  if runtime.busy() then stop_session();return end
  frame=current
  if not session then create_session();space_edge=false end
  local event=session.update();if not check_session(event) then return end
  if runtime.busy() then stop_session();return end
  if frame.grounded then prior_ground=frame end
  if space_edge then
   local result=session.press(prior_ground);if not check_session(result) then return end
   if result=='queued' then event=session.update();check_session(event) end
  end
 end)
 end_scope()
 host_ticks=host_ticks+1
 if host_ticks%9000==0 and H.fast_lookup_state then
  local f=H.fast_lookup_state()
  log(string.format('perf4_lookup ticks=%d mode=%s resolves=%d memo=%d fast=%d enumerations=%d verifications=%d fallbacks=%d',
   host_ticks,f.mode,f.resolves,f.memo_hits,f.fast_used,f.base_calls,f.verifications,f.fallbacks))
 end
 if not ok then fault('tick_error='..tostring(err)) end
end
local initial_ok,initial=pcall(make_runtime)
if initial_ok then runtime=initial else log('initial_runtime_error='..tostring(initial)) end
assert(type(LoopInGameThreadWithDelay)=='function','game-thread loop unavailable')
local handle=LoopInGameThreadWithDelay(30,tick);assert(handle,'unable to install game-thread loop')

log('fault_recovery=after_identity_change; limit='..FAULT_RECOVERY_LIMIT..' per session')
log('pad1_input_loaded; jump='..jump_input.describe()..'; auto_enable; no_toggle_keys')
log('lite_v0.1.0_loaded; auto_enable_on_player; no_hotkeys; perf4_fast_lookup='..tostring(H~=base_helpers)..'; loop_handle='..tostring(handle))
