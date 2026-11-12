local scripts=assert(debug.getinfo(1,'S').source:match('^@(.+[\\/])[^\\/]+$'),'script directory unavailable')
-- Candidate ordinary ASM lifecycle adapter. Game-thread calls only.
-- Shared state contains primitives only. No GiveAbility, volume-init, timeline
-- mutation, Execution ability, forced montage, or forced movement-mode changes.
local M={}
function M.new(H,log,state)
 state=state or {};state.pool=state.pool or {}
 local CLASS='/Game/RenewalContent/Actors/SpecialMove/BP_ASM_UpRunning.BP_ASM_UpRunning_C'
 local function emit(s) pcall(log or function() end,'native_wallrun_v18_4 '..s) end
 local ui,ui_last_refresh,ui_baseline_done
 local ui_errors={}
 local function ui_error(key,why)
  if not ui_errors[key] then ui_errors[key]=true;emit('owned_ui_unavailable field='..key..' reason='..tostring(why):gsub('[\r\n]',' '):sub(1,400)) end
 end
 local ui_loaded,ui_result=pcall(function()
  local helper=assert(loadfile(scripts..'parkour_owned_up_ui_v18_4.lua'))()
  return helper.new(H,log,state)
 end)
 if ui_loaded then ui=ui_result else ui_error('helper_load',ui_result) end
 local refresh_owned_ui

 local FINISH_MONTAGE='AnimMontage /PBZCombatAsset/ActorData/Players/Hun/Montage/SpecialMove/CloudStep/Hun_Unarmed_CloudStep_End_Montage.Hun_Unarmed_CloudStep_End_Montage'
 local function finite(x) return type(x)=='number' and x==x and math.abs(x)<math.huge end
 local function valid(o) local ok,r=pcall(function() return o and o:IsValid() end);return ok and r==true end
 local function name(o)
  if o==nil then return nil end
  local ok,r=pcall(function() return o:IsValid() end);assert(ok and type(r)=='boolean','object validity unavailable')
  if not r then return nil end
  local n=o:GetFullName();assert(type(n)=='string' and n~='','object name unavailable');return n
 end
 local function bool(v) if type(v)=='boolean' then return v elseif v==0 then return false elseif v==1 then return true end;error('boolean unreadable') end
 local function vector(v) return v and finite(v.X) and finite(v.Y) and finite(v.Z) end
 local function point(v) assert(vector(v),'vector unreadable');return {X=v.X,Y=v.Y,Z=v.Z} end
 local function rotation(v)
  assert(v and finite(v.Pitch) and finite(v.Yaw) and finite(v.Roll),'rotation unreadable')
  return {Pitch=v.Pitch,Yaw=v.Yaw,Roll=v.Roll}
 end
 local function xyz(v) return v and string.format('%.4f,%.4f,%.4f',v.X,v.Y,v.Z) or 'unavailable' end
 local function pyr(v) return string.format('%.4f,%.4f,%.4f',v.Pitch,v.Yaw,v.Roll) end
 local function distance_squared(a,b) return (a.X-b.X)^2+(a.Y-b.Y)^2+(a.Z-b.Z)^2 end
 -- Optional owned-component correction only. No player, CDO, target or other
 -- actor is written. Parent/end world positions must remain within 0.1 cm.
 local function align_direction(actor,e,target)
  assert(name(actor)==e.volume,'direction alignment actor ownership mismatch')
  local d=actor.MoveDirection;assert(valid(d),'MoveDirection unavailable')
  assert(name(d:GetOwner())==e.volume,'MoveDirection owner mismatch')
  local ending=actor.EndPositionStatic;assert(valid(ending),'end component unavailable')
  local a={before_forward=point(d:GetForwardVector()),before_rotation=rotation(d:K2_GetComponentRotation()),
   before_actor=point(actor:K2_GetActorLocation()),before_end=point(ending:K2_GetComponentLocation()),
   target_rotation=rotation(target),verified=false}
  e.direction_alignment=a
  emit('direction_align_before volume='..e.volume..' forward='..xyz(a.before_forward)..' rotation='..pyr(a.before_rotation)
   ..' actor='..xyz(a.before_actor)..' end='..xyz(a.before_end)..' target_rotation='..pyr(a.target_rotation))
  -- Engine.hpp: void K2_SetWorldRotation(FRotator, bool, FHitResult&, bool).
  d:K2_SetWorldRotation(target,false,{},true)
  assert(name(d:GetOwner())==e.volume,'MoveDirection owner changed during alignment')
  a.after_forward=point(d:GetForwardVector());a.after_rotation=rotation(d:K2_GetComponentRotation())
  a.after_actor=point(actor:K2_GetActorLocation());a.after_end=point(ending:K2_GetComponentLocation())
  local pitch,yaw=math.rad(target.Pitch),math.rad(target.Yaw)
  local expected={X=math.cos(pitch)*math.cos(yaw),Y=math.cos(pitch)*math.sin(yaw),Z=math.sin(pitch)}
  local f=a.after_forward;local length=math.sqrt(f.X*f.X+f.Y*f.Y+f.Z*f.Z)
  a.forward_dot=length>0 and (f.X*expected.X+f.Y*expected.Y+f.Z*expected.Z)/length or 0
  a.actor_displacement_squared=distance_squared(a.before_actor,a.after_actor)
  a.end_displacement_squared=distance_squared(a.before_end,a.after_end)
  emit('direction_align_after volume='..e.volume..' forward='..xyz(a.after_forward)..' rotation='..pyr(a.after_rotation)
   ..' actor='..xyz(a.after_actor)..' end='..xyz(a.after_end)..' forward_dot='..tostring(a.forward_dot)
   ..' actor_shift_cm2='..tostring(a.actor_displacement_squared)..' end_shift_cm2='..tostring(a.end_displacement_squared))
  assert(a.actor_displacement_squared<=0.01,'MoveDirection alignment moved owned actor')
  assert(a.end_displacement_squared<=0.01,'MoveDirection alignment moved end position')
  assert(finite(a.forward_dot) and a.forward_dot>=0.999,'MoveDirection forward disagrees with requested rotation')
  a.verified=true
 end
 local function each(array,fn,label)
  assert(array~=nil,label..' unavailable');local expected=array:GetArrayNum()
  assert(finite(expected) and expected>=0 and expected%1==0,label..' count unreadable')
  local count=0;array:ForEach(function(_,ref) count=count+1;local v=ref:get();assert(v~=nil,label..' item missing');fn(v) end)
  assert(count==expected,label..' enumeration incomplete')
 end
 local function family(a)
  local c=a:GetClass();local ordinary=false;local depth=0
  while valid(c) and depth<64 do
   local n=c:GetFName():ToString();assert(type(n)=='string','class name unreadable')
   if n=='GA_ASM_UpRunning_C' then ordinary=true end
   if n=='SpecialMoveAbilityBase' then return 'native',false end
   if n=='GA_ASM_Base_C' then return 'asm',ordinary end
   if n=='GameplayAbility' then return 'other',false end
   c=c:GetSuperStruct();depth=depth+1
  end
  error('ability class chain incomplete')
 end
 local function volume_of(a)
  local up=name(a.UpRunningVolume);local cur=name(a['Cur Special Move Volume'])
  assert(not up or not cur or up==cur,'ordinary volume fields conflict')
  return up or cur
 end
 local function ability_diagnostics(a)
  local data,errors={},{}
  local function read(key,fn)
   local ok,value=pcall(fn)
   if ok then data[key]=value else errors[#errors+1]=key..':'..tostring(value) end
  end
  read('up_volume_top_z',function() local v=a.UpVolumeTopWorldHeight;assert(finite(v),'unreadable');return v end)
  read('short_obstacle_standard',function() local v=a.ShortObstacleStandard;assert(finite(v),'unreadable');return v end)
  read('target_rotation',function() return pyr(rotation(a.TargetRotation)) end)
  read('modifier_rotation',function() local m=a.RotModifier;assert(valid(m),'modifier unavailable');return pyr(rotation(m.TargetRotation)) end)
  if #errors>0 then data.errors=table.concat(errors,';') end
  return data
 end
 local function scan(p,pid)
  local asc=p.SpecialMove.AbilitySystemComponent;assert(valid(asc),'player ASC unavailable')
  local out={abilities_complete=true,ordinary_spec_count=0,ordinary_instances={},special_abilities={},all_special_active_count=0}
  local objects,seen={},{}
  each(asc.ActivatableAbilities.Items,function(spec)
   local count=spec.ActiveCount;assert(finite(count) and count>=0 and count%1==0,'spec ActiveCount unreadable')
   local definition=spec.Ability;assert(valid(definition),'spec ability definition unavailable')
   local kind,ordinary=family(definition)
   if ordinary then out.ordinary_spec_count=out.ordinary_spec_count+1 end
   if kind=='other' or (count==0 and not ordinary) then return end
   local active_count=0;local local_seen={}
   local function instance(a)
    assert(valid(a),'ability instance unavailable');local id=name(a)
    if local_seen[id] then return end;local_seen[id]=true
    local active=bool(a.bIsActive)
    local row={id=id,ability=id,active=active,ordinary=ordinary,family=kind}
    if active then
     assert(not seen[id],'active ability appears in multiple specs');seen[id]=true
     assert(name(a:GetAvatarActorFromActorInfo())==pid,'active ability avatar mismatch')
     assert(name(a:GetAbilitySystemComponentFromActorInfo())==name(asc),'active ability ASC mismatch')
     row.player_id=pid;active_count=active_count+1
     if ordinary then
      local ik,io=family(a);assert(ik=='asm' and io,'ordinary instance class mismatch')
      row.volume_id=volume_of(a)
      row.asm_component_id=name(a.SpecialMoveComponent)
      row.diagnostics=ability_diagnostics(a)
     elseif kind=='native' then row.volume_id=name(a.CurrentSpecialMoveVolume) end
     out.special_abilities[#out.special_abilities+1]=row
     out.all_special_active_count=out.all_special_active_count+1;objects[id]=a
    elseif ordinary then
     -- Ended instances may clear their avatar and volume; inactivity is read
     -- from the complete spec/instance chain, never inferred from a cleared volume.
     local ok,v=pcall(volume_of,a);row.volume_readable=ok;if ok then row.volume_id=v end
    end
    if ordinary then out.ordinary_instances[#out.ordinary_instances+1]=row end
   end
   each(spec.NonReplicatedInstances,instance,'NonReplicatedInstances')
   each(spec.ReplicatedInstances,instance,'ReplicatedInstances')
   assert(active_count==count,'active spec/instance count mismatch')
  end,'ActivatableAbilities.Items')
  out.ordinary_spec_found=out.ordinary_spec_count>0
  return out,objects
 end
 local function read_player()
  local ok,result,objects=pcall(function()
   local p,w=H.GetPlayer(),H.GetWorld();assert(valid(p) and valid(w),'player/world unavailable')
   local pid,wid=name(p),name(w);local time=H.GetGameplayStatics():GetRealTimeSeconds(p);assert(finite(time),'time unreadable')
   local s={variant='ordinary_asm',player=pid,player_id=pid,world_id=wid,time=time,abilities_complete=false,
    references_readable=false,montage_readable=false,ordinary_spec_found=false}
   local abok,ab,found=pcall(scan,p,pid)
   if abok then for k,v in pairs(ab) do s[k]=v end else s.ability_error=tostring(ab) end
   local refsok,refs=pcall(function()
    local sm=p.SpecialMove;assert(valid(sm),'native special-move component unavailable')
    local asm=p.ASM_SpecialMoveComponent;assert(valid(asm),'player ASM component unavailable')
    assert(name(asm:GetOwner())==pid,'ASM component owner mismatch')
    local interact=p.PBZInteract;assert(valid(interact),'interaction component unavailable')
    return {native_volume=name(sm.CurrentSpecialMoveVolume),asm_volume=name(asm.CurSpecialMoveVolume),
     interaction=name(interact.CurrentInteractActor),interacting=name(interact.InteractingActor),asm_component_id=name(asm)}
   end)
   if refsok then
    s.references_readable=true;s.current_refs=refs;s.references={};s.asm_component_id=refs.asm_component_id
    for _,k in ipairs({'native_volume','asm_volume','interaction','interacting'}) do if refs[k] then s.references[refs[k]]=true end end
    s.interaction_id=refs.interaction;s.interacting_id=refs.interacting
    s.interact_clear=refs.interaction==nil and refs.interacting==nil
   else s.reference_error=tostring(refs) end
   local modeok,mode=pcall(function() assert(valid(p.CharacterMovement),'movement unavailable');local m=p.CharacterMovement.MovementMode;assert(finite(m),'mode unreadable');return m end)
   s.mode_readable=modeok;if modeok then s.mode=mode else s.mode_error=tostring(mode) end
   local animok,montage=pcall(function() return name(p.Mesh:GetAnimInstance():GetCurrentActiveMontage()) end)
   s.montage_readable=animok;if animok then s.active_montage=montage or 'none' else s.montage_error=tostring(montage) end
   s.complete=s.abilities_complete and s.references_readable and s.mode_readable and s.montage_readable
   if not s.complete then
    local errors={};for _,k in ipairs({'ability_error','reference_error','mode_error','montage_error'}) do
     if s[k] then errors[#errors+1]=k..'='..s[k] end
    end;s.error=table.concat(errors,'; ')
   end
   return s,abok and found or nil
  end)
  if not ok then return nil,nil,tostring(result) end
  return result,objects
 end
 local function inspect_player()
  local s,_,err=read_player();if not s then return false,err end
  if s.complete and not ui_baseline_done then
   local ok,result=pcall(refresh_owned_ui,s,true)
   if ok and result then ui_baseline_done=true elseif not ok then ui_error('baseline',result) end
  end
  return true,s -- Completeness/errors are explicit; unknown is never an empty proof.
 end
 local function entry() for _,e in ipairs(state.pool) do if e.volume==state.volume then return e end end end
 local function selected_snapshot()
  local e=entry();if not e then return nil,nil,nil,'no selected owned volume' end
  local s,objects,err=read_player();if not s then return nil,nil,nil,err end
  if s.player_id~=state.player or s.world_id~=state.world then return nil,nil,nil,'player/world changed' end
  return e,s,objects
 end
 local function evidence_complete(s)
  return s.abilities_complete and s.references_readable and s.mode_readable and s.montage_readable
 end
 local function matching(e,s)
  local found={};local other=0
  for _,a in ipairs(s.special_abilities or {}) do
   if a.ordinary and (a.volume_id==e.volume or (a.id==e.ability and a.volume_id==nil)) then found[#found+1]=a
   else other=other+1 end
  end
  return found,other
 end
 local function inspect()
  local e,s,_,err=selected_snapshot();if not e then return false,err end
  local ui_ok,ui_why=pcall(refresh_owned_ui,s,false);if not ui_ok then ui_error('inspect',ui_why) end
  if not evidence_complete(s) then e.idle_count=0;return false,s.ability_error or s.reference_error or s.mode_error or s.montage_error or 'incomplete lifecycle evidence' end
  if e.last_time and s.time<e.last_time then
   e.idle_count=0;e.dispatched_at=s.time;e.first_observed_at=s.time;e.last_time=s.time
   return false,'clock rewound; observation restarted'
  end
  local new_sample=not e.last_time or s.time>e.last_time;e.last_time=s.time
  e.first_observed_at=e.first_observed_at or s.time
  local owned,other=matching(e,s)
  if #owned==1 then
   if e.ability and e.ability~=owned[1].id then e.phase='quarantined';state.phase=e.phase;e.idle_count=0;return false,'owned ability instance changed' end
   e.ability=owned[1].id;e.seen_active=true
  end
  local idle=#owned==0 and other==0 and s.active_montage=='none' and (s.mode==1 or s.mode==3) and s.interact_clear
  local can_confirm=e.phase=='running' or e.phase=='cancelling' or e.phase=='quarantined'
  local old_enough=e.seen_active or s.time-(e.dispatched_at or e.first_observed_at)>=.8
  if can_confirm and idle and old_enough then
   if new_sample then e.idle_count=(e.idle_count or 0)+1 end
   if e.idle_count>=2 then
    e.inactive_reason=e.seen_active and 'ended_confirmed' or 'never_started_confirmed'
    e.phase='inactive';state.phase='inactive';emit('inactive_confirmed reason='..e.inactive_reason..' volume='..e.volume)
   end
  else e.idle_count=0 end
  s.volume=e.volume;s.phase=e.phase;s.active_count=#owned;s.other_active_count=other;s.unknown_active_count=0
  s.abilities=s.ordinary_instances;s.inactive_reason=e.inactive_reason;s.seen_active=e.seen_active==true
  s.cancel_dispatched=e.cancel_attempted==true;s.dispatch_uncertain=e.dispatch_uncertain==true
  return true,s
 end
 local function all(class)
  local objects=FindAllOf(class);assert(type(objects)=='table',class..' enumeration unavailable');return objects
 end
 local function actor_named(id)
  for _,a in ipairs(all('BP_ASM_UpRunning_C')) do if valid(a) and name(a)==id then return a end end
 end
 -- Only owned UI is changed. No global WidgetComponent enumeration and no
 -- retained UObject references; the helper reacquires lazy users each apply.
 local function apply_owned_ui(actor,force)
  if not ui then return false,'owned UI helper unavailable' end
  local ok,accepted,detail=pcall(ui.apply,actor,force)
  if not ok then ui_error('apply_exception',accepted);return false,tostring(accepted) end
  if accepted~=true then ui_error('apply_refused',detail);return false,detail end
  return true,detail
 end
 refresh_owned_ui=function(current,force)
  if type(current)~='table' or not finite(current.time) then return false,'current UI sample unavailable' end
  if current.player_id~=state.player or current.world_id~=state.world then return false,'UI sample ownership mismatch' end
  local checked,pid,wid=pcall(function() return name(H.GetPlayer()),name(H.GetWorld()) end)
  if not checked or pid~=state.player or wid~=state.world then return false,'current UI player/world changed' end
  if type(state.pool)~='table' or #state.pool>2 then return false,'owned UI pool unavailable/out of bound' end
  local ids,count={},0
  for key,e in pairs(state.pool) do
   if type(key)~='number' or key%1~=0 or key<1 or key>2 or type(e)~='table'
    or type(e.volume)~='string' or e.volume=='' then return false,'owned UI pool malformed' end
   count=count+1;ids[e.volume]=true
  end
  if count~=#state.pool then return false,'owned UI pool sparse' end
  if count==0 then return true,{applied=0,enumerated=false} end
  if force~=true and ui_last_refresh and current.time>=ui_last_refresh and current.time-ui_last_refresh<.1 then
   return true,{applied=0,enumerated=false,throttled=true}
  end
  -- Mark before enumeration so reflection failure cannot cause 30Hz retries.
  ui_last_refresh=current.time
  local ok,actors=pcall(all,'BP_ASM_UpRunning_C')
  if not ok then ui_error('actor_enum',actors);return false,tostring(actors) end
  local report={applied=0,enumerated=true}
  for _,actor in ipairs(actors) do
   local matched,id=pcall(function() return name(actor) end)
   if matched and ids[id] then
    local exact,class_name=pcall(function() return name(actor:GetClass()) end)
    if exact and class_name=='BlueprintGeneratedClass '..CLASS then
     local applied=apply_owned_ui(actor,force==true)
     if applied then report.applied=report.applied+1 end
    else ui_error('actor_class:'..id,exact and 'unexpected actual class' or class_name) end
   end
  end
  return true,report
 end
 local function suppress(actor)
  local box=actor.Box;assert(valid(box),'ordinary wallrun box unavailable')
  box:SetGenerateOverlapEvents(false);box:SetCollisionEnabled(0);assert(box:GetCollisionEnabled()==0,'box still enabled')
  apply_owned_ui(actor,true)
 end
 local function abort_prepared(e,reason)
  if e and not e.dispatched then e.phase='inactive';e.inactive_reason='not_dispatched';state.phase='inactive' end
  return false,reason
 end
 local function prepare(p,spec)
  local s,_,err=read_player();if not s then return false,err end
  if not valid(p) or name(p)~=s.player_id then return false,'player mismatch' end
  if not evidence_complete(s) or not s.ordinary_spec_found then return false,'ordinary ability/ASM lifecycle preflight incomplete' end
  if s.all_special_active_count~=0 or not s.interact_clear then return false,'another special move or interaction active' end
  if type(spec)~='table' or spec.confirmed_wall~=true or spec.spawn_nonoverlap_verified~=true
   or not finite(spec.height_m) or spec.height_m<1 or spec.height_m>8 then return false,'verified wall/nonoverlap and height_m 1..8 required' end
  local w,r=spec.world_position,spec.rotation
  if not vector(w) or not r or not finite(r.Yaw) or not finite(r.Pitch) or not finite(r.Roll) then return false,'invalid pose' end
  if spec.expected_world_end_z~=nil and not finite(spec.expected_world_end_z) then return false,'invalid expected end height' end
  if spec.endpoint_forward_cm~=nil and (not finite(spec.endpoint_forward_cm) or spec.endpoint_forward_cm<60 or spec.endpoint_forward_cm>210) then
   return false,'invalid sampled endpoint depth'
  end
  if state.world~=s.world_id or state.player~=s.player_id then
   state.pool={};state.world=s.world_id;state.player=s.player_id;state.volume=nil;state.phase=nil
  end
  if state.phase=='prepared' or state.phase=='running' or state.phase=='cancelling' or state.phase=='quarantined' then return false,'prior attempt not confirmed inactive' end
  local actor,e,reused
  local ok,why=pcall(function()
   for _,candidate in ipairs(state.pool) do
    if candidate.phase=='inactive' and not candidate.unsafe_setup and not s.references[candidate.volume] then
     local a=actor_named(candidate.volume);if a then actor=a;e=candidate;reused=true;break end
    end
   end
   if not actor then
    assert(#state.pool<2,'no reusable unreferenced owned volume')
    local class=StaticFindObject(CLASS);assert(valid(class),'ordinary volume class not loaded')
    actor=H.GetWorld():SpawnActor(class,{X=w.X,Y=w.Y,Z=w.Z+50000},r);assert(valid(actor),'spawn failed')
    e={volume=name(actor),phase='inactive'};state.pool[#state.pool+1]=e;reused=false
   end
   state.volume=e.volume;e.dispatched=false;e.cancel_attempted=false;e.ability=nil;e.seen_active=false
   local serial=state.attempt_serial or 0
   assert(finite(serial) and serial>=0 and serial%1==0 and serial<9007199254740990,'attempt serial unavailable')
   state.attempt_serial=serial+1;e.attempt_id=state.attempt_serial
   e.finish_boost_attempted=false;e.finish_boost_uncertain=false;e.finish_boost_error=nil
   e.finish_boost_delta_z=nil;e.finish_boost_time=nil;e.finish_boost_velocity_before=nil
   e.dispatched_at=nil;e.first_observed_at=nil;e.last_time=nil;e.idle_count=0;e.inactive_reason=nil;e.dispatch_uncertain=false
   e.dispatch_error=nil;e.cancel_error=nil;e.move_direction=nil;e.move_direction_error=nil;e.actor_forward=nil;e.actor_forward_error=nil;e.direction_alignment=nil
   suppress(actor);actor.Height=spec.height_m;actor:DoConstruction();suppress(actor)
   actor:K2_SetActorLocation(w,false,{},true);actor:K2_SetActorRotation(r,true)
   local actual=point(actor:K2_GetActorLocation());assert((actual.X-w.X)^2+(actual.Y-w.Y)^2+(actual.Z-w.Z)^2<1,'actor move failed')
   local rot=actor:K2_GetActorRotation();assert(math.abs((rot.Yaw-r.Yaw+180)%360-180)<1,'actor rotation failed');suppress(actor)
   local ending=actor.EndPositionStatic;assert(valid(ending),'end component unavailable')
   if spec.endpoint_forward_cm~=nil then
    -- Only this mod's inactive, owned endpoint component is adjusted. Never
    -- move the character, a shared asset, or a running native ability.
    ending:K2_SetRelativeLocation({X=spec.endpoint_forward_cm,Y=0,Z=spec.height_m*100},false,{},true)
   end
   if spec.align_move_direction==true then align_direction(actor,e,r) end
   local ew=point(ending:K2_GetComponentLocation());local er=point(ending.RelativeLocation)
   local expected=spec.expected_world_end_z or w.Z+spec.height_m*100
   if spec.expected_world_end~=nil then
    local target=point(spec.expected_world_end)
    assert((ew.X-target.X)^2+(ew.Y-target.Y)^2+(ew.Z-target.Z)^2<=25,
     'constructed endpoint differs from sampled endpoint; not dispatched')
   end
   e.end_world=ew;e.end_relative=er;e.prepared_position=actual;e.height_m=spec.height_m
   local direction_ok,direction=pcall(function() local d=actor.MoveDirection;return point(d:GetForwardVector()) end)
   if direction_ok then e.move_direction=direction else e.move_direction_error=tostring(direction) end
   local forward_ok,forward=pcall(function() return point(actor:GetActorForwardVector()) end)
   if forward_ok then e.actor_forward=forward else e.actor_forward_error=tostring(forward) end
   emit(string.format('prepared_geometry volume=%s origin=%.1f,%.1f,%.1f end=%.1f,%.1f,%.1f relative=%.1f,%.1f,%.1f expected_z=%.1f move_direction=%s actor_forward=%s target_yaw=%.3f',
    e.volume,actual.X,actual.Y,actual.Z,ew.X,ew.Y,ew.Z,er.X,er.Y,er.Z,expected,xyz(e.move_direction),xyz(e.actor_forward),r.Yaw))
   assert(ew.Z>actual.Z+1 and math.abs(ew.Z-expected)<=100,'constructed end height differs from requested height')
  end)
  if not ok then
   if e then e.unsafe_setup=true;e.phase='inactive';e.inactive_reason='prepare_failed_not_dispatched';state.phase='inactive';pcall(suppress,actor) end
   emit('prepare_failed='..tostring(why));return false,tostring(why)
  end
  e.phase='prepared';e.unsafe_setup=false;state.phase='prepared'
  return true,{variant='ordinary_asm',player=s.player_id,volume=e.volume,attempt_id=e.attempt_id,height_m=e.height_m,
   end_world=e.end_world,end_relative_z=e.end_relative.Z,reused=reused,geometry_verified=true,
   move_direction=e.move_direction,actor_forward=e.actor_forward,direction_alignment=e.direction_alignment}
 end
 local function start()
  local e=entry();if not e or e.phase~='prepared' then return false,'no prepared attempt' end
  local s,_,err=read_player()
  if not s or s.player_id~=state.player or s.world_id~=state.world then return abort_prepared(e,err or 'player/world changed') end
  if not evidence_complete(s) or not s.ordinary_spec_found then return abort_prepared(e,'lifecycle preflight incomplete') end
  if s.all_special_active_count~=0 or not s.interact_clear then return abort_prepared(e,'another special move or interaction active') end
  local ok,actor=pcall(actor_named,e.volume)
  if not ok or not valid(actor) then return abort_prepared(e,'owned volume unavailable: '..tostring(actor)) end
  local boxok,boxclear=pcall(function() return valid(actor.Box) and actor.Box:GetCollisionEnabled()==0 end)
  if not boxok or not boxclear then return abort_prepared(e,'volume box enabled or unreadable') end
  -- Mark BEFORE the call. Once invoked, failure is uncertain dispatch and must
  -- remain observable by Runtime, never a false safe-to-retry return.
  e.dispatched=true;e.dispatched_at=s.time;e.phase='running';state.phase='running';e.idle_count=0
  local invoked,invoke_error=pcall(function() actor:OnInteract(H.GetPlayer()) end)
  local cleaned,cleanup_error=pcall(suppress,actor)
  if not invoked or not cleaned then
   e.phase='quarantined';state.phase=e.phase;e.dispatch_uncertain=true
   e.dispatch_error=tostring(not invoked and invoke_error or cleanup_error)
  end
  emit('interact_dispatched volume='..e.volume..' uncertain='..tostring(e.dispatch_uncertain))
  return true,{player=state.player,volume=e.volume,attempt_id=e.attempt_id,variant='ordinary_asm',verified=false,
   dispatch_uncertain=e.dispatch_uncertain,dispatch_error=e.dispatch_error,expected_montage='Hun_Unarmed_WallRun_Loop_Montage'}
 end
 local function cancel()
  local e,s,objects,err=selected_snapshot();if not e then return false,err end
  if e.cancel_attempted then return false,'cancel already dispatched; awaiting observed cleanup' end
  if not e.dispatched or e.phase=='inactive' or e.phase=='prepared' then return false,'no dispatched attempt' end
  if not evidence_complete(s) then return false,'lifecycle evidence incomplete' end
  local owned,other=matching(e,s)
  if #owned~=1 or other~=0 then return false,'expected one exact owned ordinary ability and no other special move' end
  local row=owned[1]
  if e.ability and e.ability~=row.id then return false,'owned ability identity changed' end
  if row.asm_component_id~=s.asm_component_id then return false,'ability ASM component owner mismatch' end
  if s.interaction_id and s.interaction_id~=e.volume then return false,'another interaction active' end
  if s.interacting_id and s.interacting_id~=e.volume then return false,'another interacting actor active' end
  if s.current_refs.asm_volume and s.current_refs.asm_volume~=e.volume then return false,'ASM current volume changed' end
  local ability=objects and objects[row.id];if not valid(ability) then return false,'exact instance unavailable' end
  e.ability=row.id;e.seen_active=true;e.cancel_attempted=true;e.phase='cancelling';state.phase=e.phase
  local ok,why=pcall(function() ability:K2_CancelAbility() end)
  if not ok then e.phase='quarantined';state.phase=e.phase;e.cancel_error=tostring(why) end
  emit('cancel_dispatched ability='..e.ability..' uncertain='..tostring(not ok))
  return true,{ability=e.ability,verified=false,dispatch_uncertain=not ok,dispatch_error=not ok and tostring(why) or nil}
 end
 local function boost_finish_up(delta_z,expected_ticket)
  if not finite(delta_z) or delta_z<=0 or delta_z>120 then return false,'finish boost delta_z must be finite in (0,120]' end
  if type(expected_ticket)~='table' then return false,'finish boost expected ticket required' end
  -- Unlike cancellation, an upward impulse requires current explicit ownership;
  -- a previously known ability with an already-cleared volume is insufficient.
  local checked,e,movement,before=pcall(function()
   local owned_entry,s,objects,err=selected_snapshot();assert(owned_entry,err)
   assert(owned_entry.dispatched and owned_entry.phase=='running' and state.phase=='running','finish boost requires dispatched running attempt')
   assert(not owned_entry.cancel_attempted,'finish boost cancellation already attempted')
   assert(not owned_entry.finish_boost_attempted,'finish boost already attempted')
   assert(expected_ticket.player_id==state.player and expected_ticket.world_id==state.world
    and expected_ticket.owned_volume_id==owned_entry.volume,'finish boost ticket ownership mismatch')
   assert(finite(expected_ticket.attempt_id) and expected_ticket.attempt_id==owned_entry.attempt_id,'finish boost attempt ticket mismatch')
   assert(evidence_complete(s),'finish boost lifecycle evidence incomplete')
   assert(not owned_entry.dispatched_at or s.time>=owned_entry.dispatched_at,'finish boost clock rewound')
   assert(not owned_entry.last_time or s.time>=owned_entry.last_time,'finish boost clock rewound')
   local owned,other=matching(owned_entry,s)
   assert(#owned==1 and other==0 and s.all_special_active_count==1,'finish boost requires one exact owned ability and no other special move')
   local row=owned[1]
   assert(row.volume_id==owned_entry.volume,'finish boost current ability volume missing or changed')
   assert(not owned_entry.ability or owned_entry.ability==row.id,'finish boost owned ability identity changed')
   assert(row.asm_component_id==s.asm_component_id,'finish boost ability ASM component mismatch')
   -- The native-special-move component can retain an ended short-action volume.
   -- A complete scan above proves no active native ability; log that cached ref
   -- instead of confusing it with this ordinary ASM's live volume ownership.
   for _,key in ipairs({'asm_volume','interaction','interacting'}) do
    local value=s.current_refs[key]
    assert(value==nil or value==owned_entry.volume,'finish boost conflicting current reference: '..key)
   end
   assert(s.active_montage==FINISH_MONTAGE,'finish boost current montage is not exact CloudStep_End')
   assert(s.mode==3,'finish boost requires native falling movement mode')
   local ability=objects and objects[row.id];assert(valid(ability),'finish boost exact active instance unavailable')
   local p,w=H.GetPlayer(),H.GetWorld()
   assert(valid(p) and valid(w) and name(p)==s.player_id and name(w)==s.world_id,'finish boost player/world changed before impulse')
   assert(name(p.SpecialMove:GetOwner())==s.player_id,'finish boost native component owner mismatch')
   assert(name(p.PBZInteract:GetOwner())==s.player_id,'finish boost interaction component owner mismatch')
   local move=p.CharacterMovement;assert(valid(move) and name(move:GetOwner())==s.player_id,'finish boost movement owner mismatch')
   assert(move.MovementMode==3,'finish boost native movement mode changed')
   local velocity=point(p:GetVelocity());assert(velocity.Z>0,'finish boost requires current upward native velocity')
   return owned_entry,move,{time=s.time,velocity=velocity,ability=row.id,native_volume=s.current_refs.native_volume}
  end)
  if not checked then return false,tostring(e) end
  -- Mark before invoking: an exception may occur after a native side effect.
  -- This primitive lock survives F8 adapter refresh and forbids a second impulse.
  e.finish_boost_attempted=true;e.finish_boost_time=before.time;e.finish_boost_delta_z=delta_z
  e.finish_boost_velocity_before=before.velocity
  local invoked,why=pcall(function() movement:AddImpulse({X=0,Y=0,Z=delta_z},true) end)
  e.finish_boost_uncertain=not invoked;e.finish_boost_error=not invoked and tostring(why) or nil
  emit('finish_boost_attempted attempt='..tostring(e.attempt_id)..' delta_v_z='..tostring(delta_z)
   ..' velocity_before='..xyz(before.velocity)..' cached_native_volume='..tostring(before.native_volume)..' uncertain='..tostring(not invoked))
  return true,{attempted=true,uncertain=not invoked,verified=false,attempt_id=e.attempt_id,
   ability=before.ability,volume=e.volume,time=before.time,delta_v_z=delta_z,velocity_before=before.velocity,
   cached_native_volume=before.native_volume,error=e.finish_boost_error}
 end
 local function quarantine(reason)
  local e=entry();if not e then return false,'no selected volume' end
  e.phase='quarantined';state.phase=e.phase;e.idle_count=0;emit('quarantine='..tostring(reason));return true
 end
 return {prepare=prepare,start=start,inspect=inspect,cancel=cancel,quarantine=quarantine,inspect_player=inspect_player,boost_finish_up=boost_finish_up,refresh_owned_ui=refresh_owned_ui}
end
return M
