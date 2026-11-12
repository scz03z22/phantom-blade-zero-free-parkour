-- Persistent host delegates to this module. All calls are on its game-thread loop.
-- F8 reloads modules only when busy()==false. Shared state never stores UObjects.
local M={}
local scripts=assert(debug.getinfo(1,'S').source:match('^@(.+[\\/])[^\\/]+$'),'script directory unavailable')
local function module(name) return assert(loadfile(scripts..name))() end
local finish_montage='AnimMontage /PBZCombatAsset/ActorData/Players/Hun/Montage/SpecialMove/CloudStep/Hun_Unarmed_CloudStep_End_Montage.Hun_Unarmed_CloudStep_End_Montage'
-- This is an exception deadline, not the clip's claimed duration. Ordinary
-- release/edge decisions defer to the native ending once it has been observed.
local finish_timeout=4.0
function M.new(H,log,shared)
 shared=shared or {};shared.short_pool=shared.short_pool or {};shared.long_pool=shared.long_pool or {}
 local cfg=module('parkour_config_v10.lua')
 assert(type(cfg.hold_threshold)=='number' and cfg.hold_threshold>=.1 and cfg.hold_threshold<=.35)
 local engine=module('double_jump_engine_v16_1.lua').new(H,log,nil,shared.short_pool,{short_height=cfg.short_height})
 local Chain=module('parkour_native_wallrun_v18_4.lua')
 local Probe=module('parkour_motion_probe_v10.lua')
 local Exit=module('parkour_motion_exit_v10.lua')
 local chain=Chain.new(H,log,shared.long_pool)
 local Diagnostics=module('parkour_hold_diagnostics_v16_2.lua')
 local profile_floor_hit=module('profile_floor_hit_v1.lua')
 local profile_floor_trace=module('profile_floor_trace_v1.lua').new(profile_floor_hit)
 local wall_top_policy=module('wall_top_policy_v1.lua')
 local boost_z=cfg.finish_boost_z or 0
 assert(type(boost_z)=='number' and boost_z==boost_z and boost_z>=0 and boost_z<=120,'invalid finish boost')
 local run=nil
 local ui_refresh_reported=false
 local tail=nil
 local last_probe,last_seen=0,nil
 -- The host rebuilds Sessions after each native action and reloads modules on
 -- F8. Keep the one-action-per-flight latch with the shared primitive state.
 local function observe_flight(s)
  if shared.air_player~=s.player_id or shared.air_world~=s.world_id then
   shared.air_player,shared.air_world=s.player_id,s.world_id
   shared.air_consumed=false
  elseif s.mode==1 and not run then
   shared.air_consumed=false
  end
 end
 local function consume_flight(s)
  shared.air_player,shared.air_world=s.player_id,s.world_id
  shared.air_consumed=true
 end
 local color={R=0,G=0,B=0,A=0}
 local function valid(o) local ok,r=pcall(function() return o and o:IsValid() end);return ok and r end
 local function finish(reason)
  log('v10_runtime_finish='..reason)
  if run and run.kind=='hold' then
   local now=last_seen or run.started
   tail={player_id=run.ticket.player_id,world_id=run.ticket.world_id,since=now,until_time=now+3,last=-1,
    mantle_attempted=run.mantle_attempt and run.mantle_attempt.attempted==true,
    unverified=run.endpoint_verified==false,stop_reason=run.stop_reason}
   log('v16_1_tail_started reason='..tostring(reason)..' until='..tostring(tail.until_time))
  end
  run=nil
 end
 local function current_matches(s,t)
  return s and s.player_id==t.player_id and s.world_id==t.world_id and s.time>=t.time
 end
 local function request_stop(reason)
  if run then
   run.stop_reason=run.stop_reason or reason
   if reason=='disabled' or reason=='sample_lost' then run.boost_inhibited=true end
   if reason=='disabled' and run.kind=='short' then
    -- An explicit F8-off may refresh only the read-only lifecycle probe even
    -- while busy. This lets a corrected reflection adapter prove cleanup,
    -- without discarding ownership or starting a new action.
    local ok,adapter=pcall(function() return module('parkour_motion_probe_v10.lua').new(H,log,run.ticket) end)
    if ok then
     run.exit.stop();run.exit_finished=true;run.probe=adapter
     log('v10_cleanup_probe_refreshed')
    else log('v10_cleanup_probe_refresh_failed='..tostring(adapter)) end
   elseif reason=='disabled' and run.kind=='hold' then
    -- Same primitive ownership survives this diagnostic adapter refresh.
    -- It may inspect/cancel the current attempt, never prepare/start another.
    local ok,adapter=pcall(function() return module('parkour_native_wallrun_v18_4.lua').new(H,log,shared.long_pool) end)
    if ok then chain=adapter;log('v15_hold_cleanup_adapter_refreshed')
    else log('v15_hold_cleanup_adapter_refresh_failed='..tostring(adapter)) end
   end
  end
  if reason=='disabled' then
   -- One final force pass, including an idle owned pool. The disabled idle
   -- host subsequently stops ticking; this does not claim off-mode polling.
   local ok,why=pcall(function()
    local inspected,s=chain.inspect_player()
    if inspected and type(s)=='table' then chain.refresh_owned_ui(s,true) end
   end)
   if not ok and not ui_refresh_reported then
    ui_refresh_reported=true;log('v18_4_owned_ui_refresh_error='..tostring(why))
   end
  end
 end
 local function short_start(initial,s)
  local ok,ticket=engine.start_action(initial,s)
  if ok~=true then log('v10_short_rejected='..tostring(ticket));return false,ticket end
  local adapter=Probe.new(H,log,ticket)
  -- One read-only snapshot per short-action tick drives both apex tracking and
  -- runtime cleanup. Final writes still use the real adapter, which re-resolves
  -- and revalidates ownership immediately before EndSpecialMove/SetMovementMode.
  local frame={snapshot=nil}
  local exit_env={sample=function() return frame.snapshot end,log=adapter.log,
   end_special_move=adapter.end_special_move,set_falling=adapter.set_falling}
  run={kind='short',ticket=ticket,probe=adapter,frame=frame,started=s.time,
   exit=Exit.new(exit_env,{min_rise=35,settle_samples=2}),
   exit_started=false,exit_finished=false,seen_active=false,last_montage=nil}
  consume_flight(s)
  log('v10_short_dispatched expected=Hun_Wall_Run_Up_Low_RunStart_Montage geometry_height='..tostring(ticket.height)..' verified=false')
  return true
 end
 local function long_start(initial,s)
  local p=H.GetPlayer();if not valid(p) then return false,'hold player unavailable' end
  local inspected,ready=chain.inspect_player()
  if not inspected or not ready or ready.complete~=true then
   log('v15_hold_preflight_incomplete='..tostring(ready and ready.error or ready))
   return false,'ordinary ASM lifecycle preflight unavailable'
  end
  if not ready.ordinary_spec_count or ready.ordinary_spec_count<1 then
   return false,'ordinary ASM ability not present in player ASC'
  end
  if ready.all_special_active_count~=0 or not ready.interact_clear then
   return false,'another special move or interaction active'
  end
  local solid,solid_reason,ignored=engine.recheck_solid_contact(s)
  if not solid then log('v16_1_hold_solid_rejected='..tostring(solid_reason));return false,solid_reason end
  s=solid
  local cap=p.CapsuleComponent;local n=s.wall_normal;local w=s.wall
  local half,radius=cap:GetScaledCapsuleHalfHeight(),cap:GetScaledCapsuleRadius()
  local floor=s.ground.pos.Z-half
  local normal_len=math.sqrt(n.X*n.X+n.Y*n.Y)
  if normal_len<.7 then return false,'hold wall normal invalid' end
  local nx,ny=n.X/normal_len,n.Y/normal_len
  local sys=H.GetKismetSystemLibrary()
  local walkable_z=p.CharacterMovement.WalkableFloorZ
  local profile=cap:GetCollisionProfileName()
  -- Bounded start-time queries. Unknown tops allow contact-guided climbing,
  -- but not an automatic native finish toward a fictional landing.
  local samples,summary={},{}
  for _,depth in ipairs({60,90,120,150,180,210}) do
   local tx,ty=w.X-nx*depth,w.Y-ny*depth
   local hit=profile_floor_trace(sys,p,cap,{X=tx,Y=ty,Z=floor+850},
    {X=tx,Y=ty,Z=floor+80},profile,ignored,color,nil,walkable_z)
   samples[#samples+1]={depth=depth,hit=hit}
   local height,reason=wall_top_policy.select(hit,floor,walkable_z)
   summary[#summary+1]=tostring(depth)..':'..tostring(height or reason)..':nz='..tostring(hit.normal and hit.normal.Z)
  end
  log('hold_top_samples '..table.concat(summary,','))
  local top_height,top_reason,top_depth=wall_top_policy.select_samples(samples,floor,walkable_z)
  local endpoint_verified=top_height~=nil
  if not endpoint_verified then
   -- Native volume requires a height. This is ONLY a bounded climbing limit;
   -- update() preempts the ending window, never treating this as a wall top.
   top_height,top_depth=800,150
   log('hold_top_unverified mode=contact_climb limit_cm=800 native_finish_allowed=false reason='..tostring(top_reason))
  else
   log('hold_top_selected source='..top_reason..' height_cm='..tostring(top_height)
    ..' walkable_z='..tostring(walkable_z)..' depth_cm='..tostring(top_depth))
  end
  local spawn={X=w.X,Y=w.Y,Z=floor+50000};local spawn_hit={}
  if sys:CapsuleTraceSingle(p,spawn,{X=spawn.X,Y=spawn.Y,Z=spawn.Z+1},300,1000,0,false,ignored,0,spawn_hit,true,color,color,0) then
   return false,'isolated hold spawn obstructed'
  end
  local spec={confirmed_wall=true,spawn_nonoverlap_verified=true,height_m=top_height/100,align_move_direction=true,
   expected_world_end_z=floor+top_height,
   endpoint_forward_cm=top_depth,
   expected_world_end={X=w.X-nx*top_depth,Y=w.Y-ny*top_depth,Z=floor+top_height},
   world_position={X=w.X,Y=w.Y,Z=floor},rotation={Pitch=0,Yaw=math.deg(math.atan(-ny,-nx)),Roll=0}}
  local prepared,why=chain.prepare(p,spec)
  if not prepared then log('v15_long_prepare_rejected='..tostring(why));return false,why end
  local started,ticket=chain.start()
  if started~=true then log('v15_long_start_rejected='..tostring(ticket));return false,ticket end
  -- Once OnInteract has been attempted, keep ownership even if dispatch threw.
  -- Native side effects cannot safely be treated as a rejected, reusable input.
  run={kind='hold',ticket={player_id=s.player_id,world_id=s.world_id,time=s.time,owned_volume_id=ticket.volume,attempt_id=ticket.attempt_id},
   started=s.time,normal={X=nx,Y=ny},wall={X=w.X,Y=w.Y,Z=w.Z},initial_z=s.ground.pos.Z,top_z=floor+top_height,
   endpoint_verified=endpoint_verified,guard_z=s.ground.pos.Z,guard_time=s.time,
   last_z=s.ground.pos.Z,last_progress=s.time,seen_active=false,last_montage=nil,
   stop_reason=ticket.dispatch_uncertain and 'dispatch_uncertain' or nil,cancelled=false}
  consume_flight(s)
  log('v15_long_dispatched top_z='..tostring(run.top_z)..' verified=false uncertain='..tostring(ticket.dispatch_uncertain))
  return true
 end
 local support_policy=module('parkour_support_samples_v1.lua')
 local shin_policy=module('shin_sensor_v1.lua')
 local shin_hit_validation=module('shin_hit_validation_v1.lua')
 local mantle_clearance=module('mantle_clearance_v1.lua')
 local mantle_handoff=module('mantle_handoff_v1.lua')
 log('shin_mantle_candidate_v10_loaded adaptive_endpoint=true unmeasured_mode=contact_climb early_unknown_finish_guard=true')
 -- Diagnostic only: this makes no component and never moves the player.
 -- Length is an initial approximation until an upright pose can be measured.
 local function sample_shin_sensor(s,r)
  local p=H.GetPlayer();assert(valid(p),'player unavailable')
  local mesh,cap=p.Mesh,p.CapsuleComponent;assert(valid(mesh) and valid(cap),'mesh/capsule unavailable')
  local names={'calf_l','calf_r'};local sys=H.GetKismetSystemLibrary()
  local ignored,why=engine.build_spline_ignore_list(s);assert(ignored,why or 'ignore unavailable')
  local length=math.max(80,math.min(200,cap:GetScaledCapsuleHalfHeight()*1.45))
  local results={};local supported=false;local unknown=false
  local tip_results={};local tip_supported=false;local tip_unknown=false
  for _,bone in ipairs(names) do
   local socket=FName(bone);assert(mesh:DoesSocketExist(socket),'bone unavailable: '..bone)
   local calf=mesh:GetSocketLocation(socket)
   assert(calf and type(calf.X)=='number' and type(calf.Y)=='number' and type(calf.Z)=='number','bone location unavailable')
   -- Begin outside the visible wall where possible, then scan through the
   -- calf anchor to its virtual front. Overlap still fails closed.
   local origin={X=calf.X+r.normal.X*65,Y=calf.Y+r.normal.Y*65,Z=calf.Z}
   local dest={X=calf.X-r.normal.X*length,Y=calf.Y-r.normal.Y*length,Z=calf.Z};local hit={}
   local ok,found=pcall(function()return sys:LineTraceSingle(p,origin,dest,0,false,ignored,0,hit,true,color,color,0)end)
   if not ok or type(found)~='boolean' then unknown=true;results[#results+1]=bone..':unknown'
   elseif found then
    local verified,status=pcall(function()
     local v,n=hit.ImpactPoint,hit.ImpactNormal
     local c=hit.Component:Get();assert(valid(c),'component unresolved')
     local blocking=c:GetCollisionResponseToChannel(cap:GetCollisionObjectType())==2
       and cap:GetCollisionResponseToChannel(c:GetCollisionObjectType())==2
     return shin_hit_validation.classify({origin=origin,dest=dest,found=true,time=hit.Time,
      point={X=v.X,Y=v.Y,Z=v.Z},normal={X=n.X,Y=n.Y,Z=n.Z},
      wall_normal={X=r.normal.X,Y=r.normal.Y,Z=0},blocks=blocking})
    end)
    if verified and status=='support' then supported=true;results[#results+1]=bone..':wall'
    else
     unknown=true;local profile_label='unavailable'
     local profile_ok,profile_result=pcall(function()
      local profile=cap:GetCollisionProfileName();local profile_name=profile:ToString()
      assert(profile_name~='' and profile_name:lower()~='none' and profile_name:lower()~='custom','unsuitable profile')
      local ph={}
      local found_profile=sys:LineTraceSingleByProfile(p,origin,dest,profile,false,ignored,0,ph,true,color,color,0)
      if found_profile~=true then return 'no_profile_hit' end
      local v,n=ph.ImpactPoint,ph.ImpactNormal;assert(v and n,'missing profile geometry')
      local geometry=shin_hit_validation.classify({origin=origin,dest=dest,found=true,time=ph.Time,
       point={X=v.X,Y=v.Y,Z=v.Z},normal={X=n.X,Y=n.Y,Z=n.Z},
       wall_normal={X=r.normal.X,Y=r.normal.Y,Z=0},blocks=true})
      return profile_name..':'..geometry..':component_unverified'
     end)
     if profile_ok then profile_label=profile_result end
     results[#results+1]=bone..':unknown('..tostring(status)..';profile='..tostring(profile_label)..')'
    end
   else results[#results+1]=bone..':clear' end
   -- Query a small sphere at the front end. This is a query, not a spawned
   -- collision component; an initial overlap is expected and meaningful.
   local tip_hit={};local tip_end={X=dest.X,Y=dest.Y,Z=dest.Z+.1}
   local used_profile=false
   local sphere_ok,sphere_hit=pcall(function()
    local profile_ok,profile=pcall(function()return cap:GetCollisionProfileName()end)
    local pname_ok,pname=pcall(function()return profile:ToString():lower()end)
    if profile_ok and pname_ok and pname~='' and pname~='none' and pname~='custom' then
     used_profile=true
     return sys:SphereTraceSingleByProfile(p,dest,tip_end,12,profile,false,ignored,0,tip_hit,true,color,color,0)
    end
    return sys:SphereTraceSingle(p,dest,tip_end,12,0,false,ignored,0,tip_hit,true,color,color,0)
   end)
   if not sphere_ok or type(sphere_hit)~='boolean' then tip_unknown=true;tip_results[#tip_results+1]=bone..':unknown_query'
   elseif not sphere_hit then tip_results[#tip_results+1]=bone..':clear'
   else
    local resolved,blocking=pcall(function()
     local c=tip_hit.Component:Get();assert(valid(c),'component unresolved')
     local pawn_channel=cap:GetCollisionObjectType();local object_channel=c:GetCollisionObjectType()
     return c:GetCollisionResponseToChannel(pawn_channel)==2 and cap:GetCollisionResponseToChannel(object_channel)==2
    end)
    if not resolved and used_profile then
     tip_supported=true;tip_results[#tip_results+1]=bone..':profile_blocked_component_unverified'
    elseif not resolved then tip_unknown=true;tip_results[#tip_results+1]=bone..':unknown_component'
    elseif blocking then tip_supported=true;tip_results[#tip_results+1]=bone..':blocked'
    else tip_unknown=true;tip_results[#tip_results+1]=bone..':nonblocking_hit' end
   end
  end
  local valid_sample=supported or tip_supported or (not unknown and not tip_unknown)
  local sample_hit=nil
  if supported or tip_supported then sample_hit=true elseif not unknown and not tip_unknown then sample_hit=false end
  r.shin_sensor_state,r.shin_sensor_result=shin_policy.update(r.shin_sensor_state,
   {valid=valid_sample,time=s.time,hit=sample_hit})
  -- Both confirmed tip outcomes are eligible, per player choice. Unknown
  -- results never count; a stable observation is not proof of a ledge.
  local tip_state=tip_supported and 'blocked' or (not tip_unknown and 'clear' or nil)
  if not tip_state then r.tip_state=nil;r.tip_state_since=nil;r.tip_ready_at=nil
  else
   if r.tip_state~=tip_state then r.tip_state=tip_state;r.tip_state_since=s.time end
   if s.time-r.tip_state_since>=.18 then r.tip_ready_at=s.time end
  end
  log('shin_sensor_v1 result='..r.shin_sensor_result..' length_cm='..tostring(length)..' rays='..table.concat(results,',')..' tips='..table.concat(tip_results,','))
 end
 local function try_sensor_mantle(s,r,observed,space_down,enabled)
  if r.endpoint_verified==false then return end
  if not r.tip_ready_at or not enabled or not space_down or s.mode~=3 or s.time<r.tip_ready_at or s.time-r.tip_ready_at>.5
   or r.stop_reason=='disabled' or r.stop_reason=='sample_lost' then return end
  local good,why=pcall(function()
   local p=H.GetPlayer();assert(valid(p),'player unavailable')
   local cap=p.CapsuleComponent;assert(valid(cap),'capsule unavailable')
   local gravity=p.CharacterMovement.GravityScale
   assert(type(gravity)=='number' and gravity==gravity and gravity>0,'fall gravity unavailable')
   local walkable_z=p.CharacterMovement.WalkableFloorZ
   assert(type(walkable_z)=='number' and walkable_z==walkable_z and walkable_z>0 and walkable_z<=1,'walkable slope unavailable')
   local reactor,count=nil,0;local components=FindAllOf('SMotionReactorComponent')
   assert(type(components)=='table','mantle components unavailable')
   for _,component in ipairs(components) do
    local ok,belongs=pcall(function()return valid(component) and component:GetOwner():GetFullName()==r.ticket.player_id end)
    if ok and belongs then reactor=component;count=count+1 end
   end
   assert(count==1,'mantle component not unique')
   local max_front=reactor.TraversalConfig.MaxFrontHeight
   assert(type(max_front)=='number' and max_front==max_front and max_front>0 and max_front<=250,'mantle height unavailable')
   local ignored=assert(engine.build_spline_ignore_list(s),'wall filter unavailable')
   local profile=cap:GetCollisionProfileName();local profile_name=profile:ToString():lower()
   assert(profile_name~='' and profile_name~='none' and profile_name~='custom','profile unavailable')
   local sys=H.GetKismetSystemLibrary()
   local api={walkable_z=walkable_z,max_front_height=max_front,floor=function(a,b)
    return profile_floor_trace(sys,p,cap,a,b,profile,ignored,color,log,walkable_z)
   end,sweep=function(a,b,rad,half)
    local hit={};local yes=sys:CapsuleTraceSingleByProfile(p,a,b,rad,half,profile,false,ignored,0,hit,true,color,color,0)
    assert(type(yes)=='boolean','sweep unavailable')
    if yes then
     log('shin_mantle_landing_blocked time='..tostring(hit.Time)..' penetrating='..tostring(hit.bStartPenetrating)
      ..' center_z='..tostring(a.Z)..' normal_z='..tostring(hit.ImpactNormal and hit.ImpactNormal.Z))
    end
    return not yes
   end}
   local q=s.ground.pos;local clearance,reason=mantle_clearance.check(q,{X=r.normal.X,Y=r.normal.Y,Z=0},
    cap:GetScaledCapsuleRadius(),cap:GetScaledCapsuleHalfHeight(),api)
   if not clearance then log('shin_mantle_rejected='..tostring(reason)..' walkable_z='..tostring(walkable_z)..' max_front='..tostring(max_front));return end
   local ticket={player_id=r.ticket.player_id,world_id=r.ticket.world_id,
    direction={X=-r.normal.X,Y=-r.normal.Y,Z=0}}
   observed.sensor_signal=true;observed.landing_verified=clearance.landing_verified
   observed.landing_clear=clearance.landing_clear;observed.path_clear=false
   r.mantle_attempt=r.mantle_attempt or {}
   local attempted,detail=mantle_handoff.try_once(H,FindAllOf,ticket,observed,r.mantle_attempt)
   local result=type(detail)=='table' and ('invoked='..tostring(detail.invoked)..' uncertain='..tostring(detail.uncertain)..' error='..tostring(detail.error)) or tostring(detail)
   log('shin_mantle_attempt='..tostring(attempted)..' tip='..tostring(r.tip_state)..' detail='..result..' verified=false')
   if attempted and type(detail)=='table' then
    log('shin_mantle_native_before '..tostring(detail.before))
    log('shin_mantle_native_after '..tostring(detail.after))
   end
  end)
  if not good then log('shin_mantle_unavailable='..tostring(why)) end
 end
 local function reached_edge(s,r)
  local p=H.GetPlayer();if not valid(p) then return 'player_lost' end
  local ignored,why=engine.build_spline_ignore_list(s)
  if not ignored then log('v16_1_hold_edge_ignore_unavailable='..tostring(why));return 'edge_ignore_unavailable' end
  local q=s.ground.pos;local cap=p.CapsuleComponent
  local half,radius=cap:GetScaledCapsuleHalfHeight(),cap:GetScaledCapsuleRadius()
  local sys=H.GetKismetSystemLibrary();local forward=radius+65
  local tangent={X=-r.normal.Y,Y=r.normal.X};local samples,hits={},{}
  for i,point in ipairs({{0,20},{0,65},{0,110},{-18,20},{18,20}}) do
   local x=q.X+tangent.X*point[1];local y=q.Y+tangent.Y*point[1]
   local origin={X=x,Y=y,Z=q.Z-half+point[2]}
   local dest={X=x-r.normal.X*forward,Y=y-r.normal.Y*forward,Z=origin.Z}
   local hit={}
   local yes=sys:LineTraceSingle(p,origin,dest,0,false,ignored,0,hit,true,color,color,0)
   assert(type(yes)=='boolean','support trace returned unknown value')
   if yes then
    local n=hit.ImpactNormal;assert(n and type(n.Z)=='number' and n.Z==n.Z,'support normal unavailable')
    samples[i]=math.abs(n.Z)<.72
   else samples[i]=false end
   hits[i]=samples[i] and '1' or '0'
  end
  local result=support_policy(samples,s.time,r.support_lost_since,.36)
  r.support_lost_since=result.lost_since
  log('v18_5_support status='..result.status..' samples='..table.concat(hits,'')..' z='..tostring(q.Z))
  local ceiling={};local above={X=q.X,Y=q.Y,Z=q.Z+35}
  if sys:CapsuleTraceSingle(p,q,above,math.max(radius-6,1),math.max(half-6,1),0,false,ignored,0,ceiling,true,color,color,0)
   and ceiling.ImpactNormal and ceiling.ImpactNormal.Z<-.4 then
   -- Read the already-performed sweep; never run an additional trace here.
   local ok,details=pcall(function()
    local point=ceiling.ImpactPoint;local normal=ceiling.ImpactNormal
    local c=ceiling.Component and ceiling.Component:Get()
    local id=valid(c) and c:GetFullName() or 'unresolved'
    assert(point and type(point.X)=='number' and type(point.Y)=='number' and type(point.Z)=='number','hit point unavailable')
    return string.format('point=%.2f,%.2f,%.2f normal=%.3f,%.3f,%.3f player=%.2f,%.2f,%.2f radius=%.1f half=%.1f component=%s',
     point.X,point.Y,point.Z,normal.X,normal.Y,normal.Z,q.X,q.Y,q.Z,radius,half,id)
   end)
   log('obstacle_ceiling_sample '..(ok and details or ('unavailable='..tostring(details))))
   return 'ceiling'
  end
  if result.status=='lost' and q.Z>r.initial_z+50 then
   local dest={X=q.X-r.normal.X*forward,Y=q.Y-r.normal.Y*forward,Z=q.Z-half+20}
   local floor={}
   if sys:LineTraceSingle(p,{X=dest.X,Y=dest.Y,Z=q.Z+half},
     {X=dest.X,Y=dest.Y,Z=q.Z-half-50},0,false,ignored,0,floor,true,color,color,0)
     and floor.ImpactPoint and floor.ImpactNormal and floor.ImpactNormal.Z>=.72
     and floor.ImpactPoint.Z<=q.Z-half+30 then return 'top_reached' end
   return 'wall_lost'
  end
 end
 local function update(s,space_down,enabled)
  if not s then request_stop('sample_lost');return end
  -- This services inactive owned volumes whenever the host is ticking. The host
  -- supplies its existing sample; no new key hook, loop, or player write.
  local ui_ok,ui_why=pcall(chain.refresh_owned_ui,s,false)
  if not ui_ok and not ui_refresh_reported then
   ui_refresh_reported=true;log('v18_4_owned_ui_refresh_error='..tostring(ui_why))
  end
  observe_flight(s)
  if last_seen and s.time<last_seen then
   if run and run.ticket.player_id==s.player_id and run.ticket.world_id==s.world_id then
    -- Same live owner with a rewound world clock is NOT proof of action end.
    -- Rebase watchdogs and retain busy while the ordinary clip ends, or while
    -- the native hold adapter verifies and cancels its exact owned ability.
    run.ticket.time=s.time;run.started=s.time;run.stop_reason='clock_rewound';run.boost_inhibited=true
    run.last_progress=s.time;run.cancel_time=run.cancelled and s.time or nil
    if run.finishing_at then run.finishing_at=s.time end
    run.last_cancel_attempt=nil;run.last_foot_log=nil;run.last_foot_error_log=nil;run.last_edge_probe=nil;run.last_shin_probe=nil;run.shin_sensor_state=nil;run.tip_state=nil;run.tip_state_since=nil;run.tip_ready_at=nil;run.support_lost_since=nil
    if run.kind=='short' then run.exit.stop();run.exit_finished=true;run.last_foot_log=nil end
    last_probe=s.time-.1;log('v10_clock_rewound_pending_cleanup')
   else
    if run and run.kind=='hold' then chain.quarantine('clock_and_identity_changed') end
    finish('clock_and_identity_changed')
   end
   last_seen=s.time;return
  end
  last_seen=s.time
  if tail then
   if s.player_id~=tail.player_id or s.world_id~=tail.world_id or s.time<tail.since or s.time>tail.until_time then
    tail=nil
   elseif not run and s.time-tail.last>=.12 then
    tail.last=s.time
    local good,why=pcall(function()
     local read,observed=chain.inspect_player()
     if tail.mantle_attempted and read and observed then
      local montage=tostring(observed.active_montage)
      local signature=montage..':'..tostring(observed.mode)
      if signature~=tail.last_mantle_state then
       tail.last_mantle_state=signature
       log('shin_mantle_after_request montage='..montage..' mode='..tostring(observed.mode)..' z='..tostring(s.ground.pos.Z))
      end
     end
     if tail.unverified and s.time-tail.since<=1.2 then
      log('unverified_hold_tail elapsed='..tostring(s.time-tail.since)..' z='..tostring(s.ground.pos.Z)
       ..' vz='..tostring(s.velocity and s.velocity.Z)..' mode='..tostring(s.mode)..' stop='..tostring(tail.stop_reason))
     end
     Diagnostics.transition(log,s,read and observed or nil,'post_hold')
    end)
    if not good then log('v16_1_tail_unavailable='..tostring(why)) end
   end
  end
  if not run then
   local good,why=pcall(Diagnostics.baseline,H,log,s)
   if not good then log('v16_1_baseline_unavailable='..tostring(why)) end
   return
  end
  if not current_matches(s,run.ticket) then
   if run.kind=='hold' then chain.quarantine('identity_or_clock_changed') end
   finish('identity_or_clock_changed');return
  end
  -- Sample the release edge before throttling observations: a release followed
  -- by another press must never continue the old hold.
  if run.kind=='hold' then
   if not enabled then run.stop_reason=run.stop_reason or 'disabled';run.boost_inhibited=true
   elseif space_down==false then run.stop_reason=run.stop_reason or 'space_released' end
  end
  local probe_interval=.03
  if s.time-last_probe<probe_interval then return end
  last_probe=s.time
  local r=run
  if r.kind=='short' then
   local observed=r.probe.sample()
   r.frame.snapshot=observed
   if not r.exit_started and not r.exit_finished and cfg.apex_exit_enabled then
    local started,why=r.exit.start(r.ticket)
    if started then r.exit_started=true;log('v10_apex_tracking_started')
    elseif s.time-r.started>.9 then r.exit_finished=true;log('v10_apex_unavailable='..tostring(why)) end
   elseif r.exit_started and not r.exit_finished then
    local event=r.exit.update()
    if event~='tracking' and event~='awaiting_cleanup' and event~='end_requested' then
     r.exit_finished=true;log('v10_apex_result='..tostring(event))
    end
   end
   if observed then
    if observed.montage_id~=r.last_montage then log('v10_short_actual_montage='..tostring(observed.montage_id));r.last_montage=observed.montage_id end
    if observed.foot_plane_distance and (not r.last_foot_log or s.time-r.last_foot_log>=.12) then
     r.last_foot_log=s.time
     log(string.format('v10_foot_plane t=%.3f z=%.1f left=%.1f right=%.1f',observed.time,observed.z,
      observed.foot_plane_distance.l,observed.foot_plane_distance.r))
    end
    if observed.abilities_complete then
     local active,other=false,false
     for _,a in ipairs(observed.abilities) do
      if a.player_id==s.player_id and a.active then
       if a.volume_id==r.ticket.owned_volume_id then active=true else other=true end
      end
     end
     if active then r.seen_active=true end
     if not active and not other and r.seen_active and observed.interact_clear
       and observed.montage_id=='none' and (observed.mode==1 or observed.mode==3) then finish('short_ended');return end
    end
   end
   -- The ordinary native clip is bounded. Don't pretend a timeout proves it
   -- ended; wait for an ordinary grounded/falling state and no matching montage.
   if s.time-r.started>5 and observed and (observed.mode==1 or observed.mode==3)
      and observed.abilities_complete and observed.montage_id=='none'
      and observed.interact_clear then
    local any_active=false
    for _,a in ipairs(observed.abilities) do if a.player_id==s.player_id and a.active then any_active=true end end
    if not any_active then
     log('v10_short_idle_cached_volume='..tostring(observed.volume_id))
     finish('short_native_idle_confirmed');return
    end
   end
  else
   local ok,observed=chain.inspect()
   if not ok then
    r.boost_inhibited=true
    if s.time-r.started>1 then r.stop_reason=r.stop_reason or 'inspection_failed' end
   else
    if observed.active_montage~=r.last_montage then log('v10_hold_actual_montage='..tostring(observed.active_montage));r.last_montage=observed.active_montage end
    if observed.active_count==1 then r.seen_active=true end
    if observed.phase=='inactive' then
     try_sensor_mantle(s,r,observed,space_down,enabled)
     finish('hold_inactive_confirmed');return
    end
    if r.endpoint_verified==false and r.seen_active and not r.cancelled and not r.stop_reason
      and observed.active_count==1 and observed.other_active_count==0
      and observed.active_montage~=finish_montage then
     local stop,reason,margin=wall_top_policy.unknown_finish_guard(s.ground.pos.Z,r.top_z,
      s.velocity and s.velocity.Z,r.guard_z,r.guard_time,s.time)
     if stop then
      r.stop_reason=reason;r.boost_inhibited=true
      log('unverified_hold_preempt z='..tostring(s.ground.pos.Z)..' target_z='..tostring(r.top_z)
       ..' margin_cm='..tostring(margin)..' montage='..tostring(observed.active_montage))
     end
    end
    r.guard_z=s.ground.pos.Z;r.guard_time=s.time
    if not r.finishing_at and observed.active_montage==finish_montage
      and r.seen_active and observed.other_active_count==0 then
     if r.endpoint_verified==false then
      r.stop_reason=r.stop_reason or 'unverified_native_finish'
      r.boost_inhibited=true
     else
      r.finishing_at=s.time
      log('v16_hold_finishing_enter time='..tostring(s.time)..' prior_stop='..tostring(r.stop_reason))
     end
    end
    -- A refreshed adapter can discover that cancellation was already attempted.
    -- Preserve the at-most-once native call even if its original return was lost.
    if observed.cancel_dispatched==true and not r.cancelled then
     r.cancelled=true;r.cancel_time=s.time
    end
   end
   if not r.last_direction_log or s.time-r.last_direction_log>=.12 then
    r.last_direction_log=s.time
    local good,why=pcall(Diagnostics.sample,H,log,r,s.time,ok and observed or nil,s)
    if not good then log('v16_hold_diagnostics_failed='..tostring(why)) end
   end
   if s.ground.pos.Z>r.last_z+1 then r.last_progress=s.time end
   r.last_z=s.ground.pos.Z
   if r.seen_active and not r.cancelled
    and (not r.last_shin_probe or s.time-r.last_shin_probe>=.12) then
    r.last_shin_probe=s.time
    local shin_ok,shin_err=pcall(sample_shin_sensor,s,r)
    if not shin_ok then r.shin_sensor_state=nil;log('shin_sensor_v1 error='..tostring(shin_err)) end
   end
   if r.seen_active and not r.stop_reason and not r.finishing_at
    and (not r.last_edge_probe or s.time-r.last_edge_probe>=.12) then
    r.last_edge_probe=s.time
    local ok,edge=pcall(reached_edge,s,r)
    if ok then r.stop_reason=edge else r.stop_reason='edge_query_failed';log('v15_hold_edge_error='..tostring(edge)) end
   end
   -- Read socket-to-wall distances only; do not claim this supplies foot IK.
   if not r.last_foot_log or s.time-r.last_foot_log>=.12 then
    r.last_foot_log=s.time
    local feet_ok,feet_err=pcall(function()
     local mesh=H.GetPlayer().Mesh
     local left=mesh:GetSocketLocation(FName('foot_l_Socket'));local right=mesh:GetSocketLocation(FName('foot_r_Socket'))
     local function distance(v) return (v.X-r.wall.X)*r.normal.X+(v.Y-r.wall.Y)*r.normal.Y end
     log(string.format('v15_hold_feet time=%.3f z=%.1f left=%.1f right=%.1f',s.time,s.ground.pos.Z,distance(left),distance(right)))
    end)
    if not feet_ok and (not r.last_foot_error_log or s.time-r.last_foot_error_log>=1) then
     r.last_foot_error_log=s.time;log('v15_hold_feet_unavailable='..tostring(feet_err))
    end
   end
   if not r.finishing_at then
    if r.endpoint_verified==false and s.ground.pos.Z>=r.top_z then r.stop_reason=r.stop_reason or 'unverified_climb_limit' end
    if s.time-r.last_progress>1.2 then r.stop_reason=r.stop_reason or 'no_vertical_progress' end
    if s.time-r.started>cfg.max_hold_seconds then r.stop_reason=r.stop_reason or 'test_watchdog' end
   elseif s.time-r.finishing_at>=finish_timeout and not r.finishing_timed_out then
    r.finishing_timed_out=true;r.stop_reason='finishing_timeout'
    log('v16_hold_finishing_timeout elapsed='..tostring(s.time-r.finishing_at)..' montage='..tostring(ok and observed.active_montage or 'unreadable'))
   end
   -- Finishing is latched across release, F8-off, missing observations and a
   -- subsequent native montage. Only complete native idle releases ownership.
   -- Clock rewind retains the original exceptional cleanup behavior; timeout
   -- uses the existing fresh-identity cancellation and unknown-busy handling.
   -- One small velocity increment only after the native ending has itself
   -- returned to falling. The adapter rechecks the exact owned attempt and
   -- current upward velocity. It never launches or forces a movement mode.
   local boost_stop_ok=r.stop_reason==nil or r.stop_reason=='space_released'
   if boost_z>0 and enabled and not r.boost_inhibited and not r.finish_boost_done
    and r.finishing_at and not r.finishing_timed_out and not r.cancelled and boost_stop_ok
    and ok and observed.active_montage==finish_montage
    and observed.active_count==1 and observed.other_active_count==0 then
    local called,attempted,detail=pcall(chain.boost_finish_up,boost_z,r.ticket)
    if not called then
     -- Unknown failure may have occurred after the native call; do not retry.
     r.finish_boost_done=true
     log('v16_2_finish_boost_call_error_no_retry='..tostring(attempted))
    elseif attempted then
     r.finish_boost_done=true
     log('v16_2_finish_boost_attempted delta_vz='..tostring(boost_z)..' time='..tostring(s.time)
      ..' attempt_id='..tostring(r.ticket.attempt_id)..' uncertain='..tostring(detail and detail.uncertain))
    elseif detail~=r.last_boost_wait then
     r.last_boost_wait=detail
     log('v16_2_finish_boost_wait='..tostring(detail))
    end
   end
   local allow_cancel=not r.finishing_at or r.finishing_timed_out or r.stop_reason=='clock_rewound'
   if allow_cancel and r.stop_reason and not r.cancelled and (not r.last_cancel_attempt or s.time-r.last_cancel_attempt>=.15) then
    r.last_cancel_attempt=s.time
    local sent,why=chain.cancel()
    if sent then r.cancelled=true;r.cancel_time=s.time;log('v10_hold_stop_requested='..r.stop_reason)
    elseif s.time-r.started>2 and not r.reported then
     -- Refusal means no native cancel was dispatched. Keep inspecting and
     -- revalidating at a bounded rate; a later readable instance may be stopped.
     chain.quarantine('cannot_confirm_cancel:'..tostring(why))
     log('v10_hold_unresolved='..tostring(why));r.reported=true
    end
   end
   if r.cancelled and s.time-r.cancel_time>2 then
    -- Busy remains true when lifecycle is unknown. Prevent reloading or another
    -- action until identity reset/restart, rather than reusing an active actor.
    if not r.reported then chain.quarantine('exit_unconfirmed');log('v10_hold_exit_unconfirmed; new actions blocked');r.reported=true end
   end
  end
 end
 local function start_action(initial,s)
  if run then return false,'previous action still pending/active' end
  if not initial or not s or not s.contact or not s.wall or not s.wall_normal then return false,'fresh wall required' end
  observe_flight(s)
  if shared.air_consumed then return false,'this airborne episode already consumed' end
  local second_time=s.second_press_time or s.time
  if type(second_time)~='number' or second_time~=second_time or math.abs(second_time)==math.huge
    or second_time>s.time or s.time-second_time>10.000001 then return false,'invalid second press time' end
  local function vector(v)
   if type(v)~='table' then return false end
   for _,key in ipairs({'X','Y','Z'}) do
    local x=v[key];if type(x)~='number' or x~=x or math.abs(x)==math.huge then return false end
   end
   return true
  end
  if not vector(s.wall) or not vector(s.wall_normal) or not vector(initial.pos) then return false,'complete finite wall/origin required' end
  if s.mode~=3 and not (s.mode==1 and s.trigger_kind=='ground_push_double') then
   return false,'ordinary air or double grounded contact required'
  end
  -- Verify lifecycle observability BEFORE dispatch. A reflection mismatch must
  -- reject the attempt, not create a native action we can never prove ended.
  local preflight=Probe.new(H,log,{player_id=s.player_id,world_id=s.world_id,owned_volume_id='PBZJumpLab-preflight'}).sample()
  if not preflight or preflight.player_id~=s.player_id or preflight.world_id~=s.world_id
    or not preflight.abilities_complete then
   return false,'ability lifecycle preflight unavailable; no native action dispatched'
  end
  for _,a in ipairs(preflight.abilities) do
   if a.player_id==s.player_id and a.active then return false,'another special move is active' end
  end
  local released=s.second_released==true or s.space_down==false
  local hold=cfg.hold_enabled and not released
  if hold and (s.space_down~=true or s.time-second_time+.0000001<cfg.hold_threshold) then
   return false,'hold decision not ready; session must defer before dispatch'
  end
  log(string.format('v15_contact_dispatch kind=%s wait=%.3f released=%s hold=%s',tostring(s.trigger_kind),
   s.time-second_time,tostring(released),tostring(hold)))
  if hold then return long_start(initial,s) end
  return short_start(initial,s)
 end
 local ready,baseline=pcall(function()
  local p,w=H.GetPlayer(),H.GetWorld()
  if not valid(p) or not valid(w) then return nil end
  return Probe.new(H,log,{player_id=p:GetFullName(),world_id=w:GetFullName(),owned_volume_id='PBZJumpLab-readonly-baseline'}).sample()
 end)
 log('v10_baseline_abilities_complete='..tostring(ready and baseline and baseline.abilities_complete or false))
 local ok,available,asm=pcall(function() return chain.inspect_player() end)
 log('v15_baseline_asm complete='..tostring(ok and available and asm and asm.complete)
  ..' ordinary_specs='..tostring(ok and available and asm and asm.ordinary_spec_count)
  ..' error='..tostring(ok and asm and asm.error or (not ok and available or 'none')))
 log('v10_runtime_loaded version='..cfg.version..' hold_enabled='..tostring(cfg.hold_enabled)..' apex_exit='..tostring(cfg.apex_exit_enabled))
 return {sample=engine.sample,update=update,start_action=start_action,busy=function() return run~=nil end,
  stop=request_stop,label=function() return cfg.version..'; hold='..tostring(cfg.hold_enabled)..'; apex='..tostring(cfg.apex_exit_enabled) end}
end
return M
