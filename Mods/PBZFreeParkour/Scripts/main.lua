-- Research host: exactly one game-thread loop; F8 enables/disables, double
-- Space is handled by the independent v10 session. No engine work in timers.
local scripts=assert(debug.getinfo(1,'S').source:match('^@(.+[\\/])[^\\/]+$'),'script directory unavailable')
local H=require('UEHelpers')
local enabled=false
local runtime,session,frame,prior_ground=nil,nil,nil,nil
local identity,last_time,ready_after=nil,nil,nil
local previous_arm,previous_space,input_ready=false,false,false
local persistent_state={} -- primitive Lua data only; shared across reloads
local suspended=nil
local faulted=false
local fault_identity,fault_time,fault_drain_failures,fault_drain_blocked=nil,nil,0,false
local function log(msg) print('[PBZ-PARKOUR] '..tostring(msg)..'\n') end
local function status(msg) end
local function valid(o) local ok,v=pcall(function() return o and o:IsValid() end);return ok and v end
local pending_f8=false

-- Release-only key configuration. Invalid settings retain the default key.
local pbz_toggle_name = 'F8'
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
if not pbz_key_ok then log('keybindings invalid or missing; using F8: '..tostring(pbz_key_error)) end
local pbz_toggle_key = Key[pbz_toggle_name]
log('toggle_key='..pbz_toggle_name..'; changes require a game restart')

RegisterKeyBind(pbz_toggle_key,function() ExecuteInGameThread(function() if valid(H.GetPlayer()) then pending_f8=true end end) end)
local function notice(message)
 local ok,err=pcall(function()
  local p=H.GetPlayer();if valid(p) then H.GetKismetSystemLibrary():PrintString(p,message,true,false,{R=.3,G=1,B=.6,A=1},4,FName('PBZJumpLabMode')) end
 end)
 if not ok then log('notification_error='..tostring(err)) end
end
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
local feedback=nil
local function play_feedback(kind,p)
 local ok,err=pcall(function()
  if not feedback then feedback=assert(loadfile(scripts..'toggle_feedback_v1.lua'))().new(H,log) end
  feedback.play(kind,p)
 end)
 if not ok then log('toggle_feedback_error='..tostring(err)) end
end
local function check_session(event)
 if session and session.active() then return true end
 if event=='unavailable' then suspend('session_unavailable') else fault('session_'..tostring(event)) end
 return false
end
local function tick()
 local ok,err=pcall(function()
  local p=H.GetPlayer();if not valid(p) then suspend('player_unavailable');return end
  local input=p:GetController();if not valid(input) then suspend('controller_unavailable');return end
  local space_down=not not input:IsInputKeyDown({KeyName=FName('SpaceBar')})
  local arm_edge=input_ready and pending_f8
  pending_f8=false
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
   if not arm_edge then return end
   if still_busy then status('v10 disabled: fault cleanup pending; F8 cannot enable');return end
   local success,new_modules=reload();assert(success);modules=new_modules;faulted=false
   identity,last_time,ready_after=nil,nil,nil
   status('v10 disabled; recovered; F8 to enable');return
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
   if enabled then
    enabled=false;stop_session();stop_runtime('disabled')
    status('v10 disabled; action finishing if necessary; F8 to enable');log('toggle=disabled');play_feedback('disabled',p)
   else
    if runtime.busy() then
     status('v10 disabled; previous action finishing');log('enable_refused=finishing');notice('Parkour: previous action finishing')
    else
     local success,new_modules=reload();assert(success)
     modules=new_modules;enabled=true
     status('v10 enabled; '..tostring(runtime.label())..'; F8 to disable');log('toggle=enabled label='..tostring(runtime.label()))
     play_feedback('enabled',p)
    end
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
 if not ok then fault('tick_error='..tostring(err)) end
end
local initial_ok,initial=pcall(make_runtime)
if initial_ok then runtime=initial else log('initial_runtime_error='..tostring(initial)) end
assert(type(LoopInGameThreadWithDelay)=='function','game-thread loop unavailable')
local handle=LoopInGameThreadWithDelay(30,tick);assert(handle,'unable to install game-thread loop')
status('v10 loaded; disabled; F8 to enable')
log('v10 loaded; configured persistent toggle; double Space; loop_handle='..tostring(handle))
