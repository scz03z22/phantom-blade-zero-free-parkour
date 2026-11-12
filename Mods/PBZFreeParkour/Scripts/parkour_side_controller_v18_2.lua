-- Side-running candidate: per-attempt direction is fixed. One native adapter
-- owns the full start/loop/finish lifecycle; no actor teleport or montage replay.
local M={}
local scripts=assert(debug.getinfo(1,'S').source:match('^@(.+[\\/])[^\\/]+$'),'script directory unavailable')
local function module(n) return assert(loadfile(scripts..n))() end
local function valid(o) local ok,v=pcall(function() return o and o:IsValid() end);return ok and v==true end
local function dot(a,b) return a.X*b.X+a.Y*b.Y+a.Z*b.Z end
local function sub(a,b) return {X=a.X-b.X,Y=a.Y-b.Y,Z=a.Z-b.Z} end
local function finite(n) return type(n)=='number' and n==n and math.abs(n)<math.huge end
local function point(v)
 assert(type(v)=='table' and finite(v.X) and finite(v.Y) and finite(v.Z),'side vector unavailable')
 return {X=v.X,Y=v.Y,Z=v.Z}
end
function M.new(H,log,state,cfg)
 local chain=module('parkour_native_siderun_v18_1.lua').new(H,log,state)
 local Geometry=module('parkour_side_geometry_v18.lua')
 local Spec=module('parkour_side_spec_v18.lua')
 -- Asset loading is confined to construction/F8, never the jump dispatch path.
 -- A side-only preload failure must not fault the existing short/vertical mode.
 if cfg.defer_side_preload~=true and type(Spec.preload)=='function' then
  local called,ready,why=pcall(Spec.preload,H)
  pcall(log,'v18_side_asset_preload called='..tostring(called)..' ready='..tostring(ready==true)
   ..' reason='..tostring(called and why or ready))
 end
 local baseline_called,baseline_ok,baseline=pcall(chain.inspect_player)
 pcall(log,'v18_side_baseline complete='..tostring(baseline_called and baseline_ok and type(baseline)=='table' and baseline.complete==true)
  ..' side_specs='..tostring(type(baseline)=='table' and (baseline.side_spec_count or baseline.ordinary_spec_count) or nil)
  ..' error='..tostring(not baseline_called and baseline_ok or (type(baseline)=='table' and baseline.error or baseline)))
 local engine=module('double_jump_engine_v16_1.lua').new(H,log,nil,{}, {short_height=cfg.short_height})
 local run=nil
 local function stop(reason)
  if run then run.stop_reason=run.stop_reason or reason end
 end
 local function start(initial,s,selection,ignored)
  if run then return false,'side action pending' end
  local inspected,ready=chain.inspect_player()
  if not inspected or not ready or ready.complete~=true then return false,'side lifecycle preflight unavailable' end
  if (ready.side_spec_count or ready.ordinary_spec_count or 0)<1 then return false,'side ability not in player ASC' end
  if ready.all_special_active_count~=0 or not ready.interact_clear then return false,'another special move or interaction active' end
  local ok,plan=pcall(Geometry.plan,H,s,selection,ignored,cfg,log)
  if not ok then log('v18_side_path_error='..tostring(plan));return false,'side path unavailable' end
  if plan.status~='ready' then return false,'side path: '..tostring(plan.stop_reason) end
  local made,spec=Spec.make(H,s,selection,plan,ignored)
  if not made then return false,spec end
  -- Snapshot the planned state before any native dispatch. In particular, a
  -- later Lua/logging exception cannot erase ownership of a possible OnInteract.
  local planned={player=s.player_id,world=s.world_id,started=s.time,last_time=s.time,
   route=selection.route,angle=selection.angle_deg,tangent=point(selection.along_wall),normal=point(selection.wall_normal_xy),
   origin=point(plan.start),endpoint=point(plan.finish),length=plan.usable_distance_cm,progress=0,last_progress=s.time}
  local prepared,why=chain.prepare(H.GetPlayer(),spec)
  if not prepared then return false,why end
  local ticket={player=s.player_id,player_id=s.player_id,world=s.world_id,world_id=s.world_id}
  if type(why)=='table' then for k,v in pairs(why) do ticket[k]=v end end
  planned.ticket=ticket;run=planned
  local invoked,called,result=pcall(chain.start)
  if invoked and called==false then run=nil;return false,result end
  if invoked and called==true and type(result)=='table' then ticket=result;run.ticket=ticket
  else
   ticket.dispatch_uncertain=true
   ticket.dispatch_error=not invoked and tostring(called) or 'invalid native start result'
   pcall(chain.quarantine,'start_outcome_unknown')
  end
  run.stop_reason=ticket.dispatch_uncertain and 'dispatch_uncertain' or nil
  local logged,log_error=pcall(log,'v18_side_dispatched route='..run.route..' angle='..tostring(run.angle)..' length='..run.length
   ..' owned='..tostring(ticket.volume)..' uncertain='..tostring(ticket.dispatch_uncertain)..' verified=false')
  if not logged then
   ticket.dispatch_uncertain=true;ticket.dispatch_error='post-dispatch log failed: '..tostring(log_error)
   run.stop_reason='dispatch_uncertain';pcall(chain.quarantine,'post_dispatch_log_failed')
  end
  return true,ticket
 end
 local function edge(s,r)
  local ignored,why=engine.build_spline_ignore_list(s);assert(ignored,why)
  local trace,radius,half,q=Geometry.query(H,s,ignored)
  local support=trace('wall',{center=q,wall_normal=r.normal})
  assert(type(support)=='table' and support.ok==true and type(support.hit)=='boolean','side support query unavailable')
  if not support.hit then return 'wall_lost' end
  assert(type(support.blocking)=='boolean','side support blocking state unavailable')
  if not support.blocking then return 'wall_not_blocking' end
  local n=point(support.normal);local size=math.sqrt(n.X*n.X+n.Y*n.Y+n.Z*n.Z)
  if size<.1 or dot(n,r.normal)/size<math.cos(math.rad(20)) then return 'wall_turned' end
  local ahead={X=q.X+r.tangent.X*45,Y=q.Y+r.tangent.Y*45,Z=q.Z}
  local swept=trace('capsule',{from=q,to=ahead})
  assert(type(swept)=='table' and swept.ok==true and type(swept.blocked)=='boolean','side forward query unavailable')
  if swept.blocked then return 'forward_blocked' end
  return nil
 end
 local function update(s,space_down,enabled)
  if not run then return end
  local r=run
  if not s then stop('sample_lost');return end
  if s.player_id~=r.player or s.world_id~=r.world then
   chain.quarantine('identity_changed');log('v18_side_abandoned_old_world');run=nil;return
  end
  if not finite(s.time) then stop('sample_time_unavailable');return end
  if s.time<r.last_time then
   -- Clock uncertainty outranks an earlier release and bypasses the native-end
   -- wait. Otherwise an old future end_requested timestamp can defer cleanup.
   r.stop_reason='clock_rewound';r.started=s.time;r.last_progress=s.time;r.last_probe=nil
   r.last_edge=nil;r.last_cancel=nil;r.last_exit_try=nil;if r.finishing then r.finishing=s.time end
  end
  r.last_time=s.time
  if not enabled then stop('disabled') elseif space_down==false then stop('space_released') end
  if r.last_probe and s.time-r.last_probe<.03 then return end;r.last_probe=s.time
  local read,ok,observed=pcall(chain.inspect)
  if read and ok==true and type(observed)=='table' and observed.complete==true then
   if observed.active_montage~=r.last_montage then
    r.last_montage=observed.active_montage
    log('v18_side_actual_montage='..tostring(r.last_montage)..' mode='..tostring(observed.mode))
   end
   if observed.active_count==1 then r.seen_active=true end
   if observed.phase=='inactive' and observed.active_count==0 and observed.other_active_count==0
    and observed.active_montage=='none' and (observed.mode==1 or observed.mode==3) and observed.interact_clear==true then
    log('v18_side_finished reason='..tostring(observed.inactive_reason)..' progress_cm='..tostring(r.progress)..' stop='..tostring(r.stop_reason)..' elapsed='..tostring(s.time-r.started))
    run=nil;return
   end
   if (observed.native_ending_active or observed.finishing) and not r.finishing then
    r.finishing=s.time;log('v18_side_finishing_enter time='..s.time..' stop='..tostring(r.stop_reason)..' progress_cm='..tostring(r.progress)..' elapsed='..tostring(s.time-r.started))
   end
   if observed.cancel_dispatched then r.cancelled=true end
   if observed.finish_request_attempted and not r.end_requested then r.end_requested=s.time end
  elseif s.time-r.started>1 then stop('inspection_failed') end
  if s.ground and s.ground.pos then
   local pos=point(s.ground.pos)
   local progress=dot(sub(pos,r.origin),r.tangent)
   if progress>r.progress+2 then r.last_progress=s.time end
   r.progress=progress
  end
  if not r.finishing then
   if r.progress>=r.length then stop('path_end') end
   if r.seen_active and not r.stop_reason and (not r.last_edge or s.time-r.last_edge>=.12) then
    r.last_edge=s.time;local good,why=pcall(edge,s,r)
    if not good then stop('edge_query_failed');log('v18_side_edge_error='..tostring(why)) elseif why then stop(why) end
   end
   if s.time-r.last_progress>1.2 then stop('no_along_wall_progress') end
   if s.time-r.started>(cfg.side_max_seconds or 10) then stop('watchdog') end
  elseif s.time-r.finishing>(cfg.side_finish_timeout or 4) then
   r.finish_timeout=true;r.stop_reason='finishing_timeout'
  end
  -- Prefer an adapter's guarded native endpoint exit. An ordinary release is
  -- latched even if the player presses Space again while waiting for the tail.
  if r.stop_reason and not r.finishing and not r.end_requested and not r.cancelled
   and (not r.last_exit_try or s.time-r.last_exit_try>=.15) then
   r.last_exit_try=s.time
   if type(chain.request_finish)=='function' and r.stop_reason~='clock_rewound' then
    local called,sent,detail=pcall(chain.request_finish,r.ticket)
    if not called or sent~=false then
     -- An exceptional/unknown endpoint write might already have happened.
     -- Retain the attempt and never issue that write again.
     r.end_requested=s.time
     if not called or sent~=true then pcall(chain.quarantine,'finish_request_outcome_unknown') end
     log('v18_side_native_end_requested reason='..r.stop_reason..' uncertain='..tostring(not called or sent~=true))
    else log('v18_side_native_end_wait='..tostring(detail)) end
   end
  end
  local native_exit_wait=r.end_requested and not r.finishing and r.stop_reason~='clock_rewound' and s.time-r.end_requested<1.0
  local protect_tail=r.finishing and not r.finish_timeout and r.stop_reason~='clock_rewound'
  if r.stop_reason and not protect_tail and not native_exit_wait and not r.cancelled
   and (not r.last_cancel or s.time-r.last_cancel>=.15) then
   r.last_cancel=s.time
   local emergency=r.finish_timeout or r.stop_reason=='clock_rewound'
   local called,sent,why=pcall(chain.cancel,emergency and {emergency=true,reason=r.stop_reason} or nil)
   if not called or sent~=false then
    r.cancelled=true
    if not called or sent~=true then pcall(chain.quarantine,'cancel_outcome_unknown') end
    log('v18_side_cancel_requested reason='..r.stop_reason..' uncertain='..tostring(not called or sent~=true))
   elseif not r.cancel_refusal_logged then r.cancel_refusal_logged=true;log('v18_side_cancel_pending='..tostring(why)) end
  end
 end
 return {start=start,update=update,stop=stop,busy=function() return run~=nil end}
end
return M
