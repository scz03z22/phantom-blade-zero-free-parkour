local scripts=assert(debug.getinfo(1,'S').source:match('^@(.+[\\/])[^\\/]+$'),'script directory unavailable')
-- Independent v18.1 ordinary ASM SideRunning candidate; not installed by this file.
-- Game-thread calls only. State/pool/tickets contain primitives, never UObjects.
-- Geometry requires explicit current-session probe evidence. No asset loads,
-- GiveAbility, overlap callbacks, manual montage/timeline/state events or boost.
local M={}
function M.new(H,log,state)
 state=state or {};state.pool=state.pool or {}
 local function emit(s) pcall(log or function() end,'native_siderun_v18_1 '..s) end
 local owned_ui
 do
  local ok,result=pcall(function()
   return assert(loadfile(scripts..'parkour_owned_side_ui_v18_1.lua'))().new(H,log,state)
  end)
  if ok then owned_ui=result else emit('owned_ui_module_unavailable='..tostring(result)) end
 end
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
 local function rotation(v) assert(v and finite(v.Pitch) and finite(v.Yaw) and finite(v.Roll),'rotation unreadable');return {Pitch=v.Pitch,Yaw=v.Yaw,Roll=v.Roll} end
 local function xyz(v) return v and string.format('%.4f,%.4f,%.4f',v.X,v.Y,v.Z) or 'unavailable' end
 local function distance2(a,b) return (a.X-b.X)^2+(a.Y-b.Y)^2+(a.Z-b.Z)^2 end
 local function copy(v)
  local kind=type(v)
  assert(kind=='table' or kind=='string' or kind=='number' or kind=='boolean' or kind=='nil','nonprimitive value')
  if kind~='table' then if kind=='number' then assert(finite(v),'nonfinite value') end;return v end
  local out={};for k,value in pairs(v) do assert(type(k)=='string' or type(k)=='number','invalid primitive key');out[k]=copy(value) end;return out
 end
 local function each(array,fn,label,limit)
  assert(array~=nil,label..' unavailable');local expected=array:GetArrayNum()
  assert(finite(expected) and expected>=0 and expected%1==0 and expected<=(limit or 4096),label..' count unreadable/out of bound')
  local count=0;array:ForEach(function(_,ref) count=count+1;local v=ref:get();assert(v~=nil,label..' item missing');fn(v) end)
  assert(count==expected,label..' enumeration incomplete')
 end
 local function world_of(o)
  for _=1,32 do assert(valid(o),'outer chain ended before World');local n=name(o);if n:sub(1,6)=='World ' then return n end;o=o:GetOuter() end
  error('outer chain exceeds 32')
 end
 local function class_has(c,expected)
  for _=1,64 do
   if not valid(c) then return false end
   local n=c:GetFName():ToString();assert(type(n)=='string','class name unreadable')
   if n==expected then return true end
   c=c:GetSuperStruct()
  end
  error('class chain incomplete')
 end
 local function family(a)
  local c=a:GetClass();local ordinary,excluded=false,false
  for _=1,64 do
   assert(valid(c),'ability class chain incomplete')
   local n=c:GetFName():ToString();assert(type(n)=='string','class name unreadable')
   if n=='GA_ASM_SideRunning_C' then ordinary=true end
   if n=='GA_ASM_SideRunning_JumpInFromSideRunning_C' then excluded=true end
   if n=='SpecialMoveAbilityBase' then return 'native',false end
   if n=='GA_ASM_Base_C' then return 'asm',ordinary and not excluded end
   if n=='GameplayAbility' then return 'other',false end
   c=c:GetSuperStruct()
  end
  error('ability class chain incomplete')
 end
 local function volume_of(a) return name(a.SideRunning) end
 local function diagnostics(a)
  local out,errors={},{}
  local function read(k,f) local ok,v=pcall(f);if ok then out[k]=v else errors[#errors+1]=k..':'..tostring(v) end end
  read('wall_on_right',function() return bool(a.InBoxA_WallOnRight) end)
  read('start_launch',function() return point(a.StartLaunchVelocity) end)
  read('old_gravity',function() local v=a.OldGravityScale;assert(finite(v),'gravity unreadable');return v end)
  read('target_rotation',function() return rotation(a.TargetRotation) end)
  read('modifier_rotation',function() assert(valid(a.RotModifier),'modifier unavailable');return rotation(a.RotModifier.TargetRotation) end)
  if #errors>0 then out.errors=table.concat(errors,';') end;return out
 end
 -- Exact montage names from this ability's actual timelines, never substrings.
 -- This does not invoke a timeline or imply that an arbitrary state callback is
 -- an authorized native transition. Optional missing data remains explicit.
 local TIMELINES={Start_L='start',Start_R='start',Start_L_Far='start',Start_R_Far='start',
  Loop_L='loop',Loop_R='loop',FinishOut_L='finish',FinishOut_R='finish',
  InterruptOut_L='interrupt',InterruptOut_R='interrupt',JumpOut_L='jump',JumpOut_R='jump'}
 local function montage_inventory(a)
  local out={start={},loop={},finish={},interrupt={},jump={},ending={},timelines={},errors={},complete=true}
  local function actions(arr,group,label)
   each(arr,function(ev)
    local action=ev.Action;assert(valid(action),'timeline action unavailable')
    local c=action:GetClass();local m
    if class_has(c,'LGAAction_PlayMontage') then m=action.MontageToPlay
    elseif class_has(c,'LGAAction_PlayMontage_Base') then m=action.DynamicMontage end
    local id=name(m);if id then
     assert(id:sub(1,12)=='AnimMontage ','timeline montage has unexpected class')
     out[group][id]=true
    end
   end,label,256)
  end
  for key,group in pairs(TIMELINES) do
   local ok,why=pcall(function()
    local timeline=a[key];if not valid(timeline) then return end
    out.timelines[key]=name(timeline);actions(timeline.Actions,group,key..'.Actions')
    each(timeline.RoleLayers,function(layer) actions(layer.Actions,group,key..'.Role.Actions') end,key..'.RoleLayers',32)
   end)
   if not ok then out.complete=false;out.errors[#out.errors+1]=key..':'..tostring(why) end
  end
  for _,group in ipairs({'finish','interrupt','jump'}) do
   for id in pairs(out[group]) do
    if out.loop[id] or out.start[id] then out.complete=false;out.errors[#out.errors+1]='ambiguous ending montage: '..id
    else out.ending[id]=out.ending[id] and (out.ending[id]..'|'..group) or group end
   end
  end
  return out
 end
 local function scan(p,pid)
  local sm=p.SpecialMove;assert(valid(sm) and name(sm:GetOwner())==pid,'native SM owner mismatch')
  local asc=sm.AbilitySystemComponent;assert(valid(asc),'player ASC unavailable')
  local out={abilities_complete=true,ordinary_spec_count=0,ordinary_instances={},special_abilities={},all_special_active_count=0,asc_id=name(asc)}
  local objects,seen={},{}
  each(asc.ActivatableAbilities.Items,function(spec)
   local count=spec.ActiveCount;assert(finite(count) and count>=0 and count%1==0,'spec ActiveCount unreadable')
   local def=spec.Ability;assert(valid(def),'spec definition unavailable');local kind,ordinary=family(def)
   if ordinary then out.ordinary_spec_count=out.ordinary_spec_count+1 end
   if kind=='other' or (count==0 and not ordinary) then return end
   local active_count=0;local local_seen={}
   local function instance(a)
    assert(valid(a),'ability instance unavailable');local id=name(a)
    if local_seen[id] then return end;local_seen[id]=true
    local active=bool(a.bIsActive);local row={id=id,ability=id,active=active,ordinary=ordinary,family=kind}
    if active then
     assert(not seen[id],'active ability appears in multiple specs');seen[id]=true
     assert(name(a:GetAvatarActorFromActorInfo())==pid,'active ability avatar mismatch')
     assert(name(a:GetAbilitySystemComponentFromActorInfo())==name(asc),'active ability ASC mismatch')
     row.player_id=pid;row.asc_id=name(asc);active_count=active_count+1
     if ordinary then
      local ik,io=family(a);assert(ik=='asm' and io,'ordinary side instance class mismatch')
      row.volume_id=volume_of(a);row.diagnostics=diagnostics(a)
     elseif kind=='native' then row.volume_id=name(a.CurrentSpecialMoveVolume) end
     out.special_abilities[#out.special_abilities+1]=row;out.all_special_active_count=out.all_special_active_count+1;objects[id]=a
    elseif ordinary then
     local ok,v=pcall(volume_of,a);row.volume_readable=ok;if ok then row.volume_id=v end
    end
    if ordinary then out.ordinary_instances[#out.ordinary_instances+1]=row end
   end
   each(spec.NonReplicatedInstances,instance,'NonReplicatedInstances')
   each(spec.ReplicatedInstances,instance,'ReplicatedInstances')
   assert(active_count==count,'active spec/instance count mismatch')
  end,'ActivatableAbilities.Items')
  out.ordinary_spec_found=out.ordinary_spec_count>0;out.side_spec_count=out.ordinary_spec_count;out.side_spec_found=out.ordinary_spec_found;return out,objects
 end
 local function read_player()
  local ok,result,objects=pcall(function()
   local p,w=H.GetPlayer(),H.GetWorld();assert(valid(p) and valid(w),'player/world unavailable')
   local pid,wid=name(p),name(w);assert(world_of(p)==wid,'player World mismatch')
   local time=H.GetGameplayStatics():GetRealTimeSeconds(p);assert(finite(time),'time unreadable')
   local s={variant='ordinary_side_asm',player=pid,player_id=pid,world_id=wid,time=time,
    abilities_complete=false,references_readable=false,montage_readable=false,ordinary_spec_found=false}
   local abok,ab,found=pcall(scan,p,pid)
   if abok then for k,v in pairs(ab) do s[k]=v end else s.ability_error=tostring(ab) end
   local refsok,refs=pcall(function()
    local sm=p.SpecialMove;assert(valid(sm) and name(sm:GetOwner())==pid,'native component owner mismatch')
    local asm=p.ASM_SpecialMoveComponent;assert(valid(asm) and name(asm:GetOwner())==pid,'ASM component owner mismatch')
    local interact=p.PBZInteract;assert(valid(interact) and name(interact:GetOwner())==pid,'interaction owner mismatch')
    return {native_volume=name(sm.CurrentSpecialMoveVolume),asm_volume=name(asm.CurSpecialMoveVolume),side_volume=name(asm.CurSideRunningVolume),
     side_in_box_a=bool(asm.SideRunningIsInBoxA),in_side_volume=bool(asm.IsInSideRunningVolume),
     interaction=name(interact.CurrentInteractActor),interacting=name(interact.InteractingActor),asm_component_id=name(asm)}
   end)
   if refsok then
    s.references_readable=true;s.current_refs=refs;s.references={};s.asm_component_id=refs.asm_component_id
    for _,k in ipairs({'native_volume','asm_volume','side_volume','interaction','interacting'}) do if refs[k] then s.references[refs[k]]=true end end
    s.interaction_id=refs.interaction;s.interacting_id=refs.interacting;s.interact_clear=refs.interaction==nil and refs.interacting==nil
   else s.reference_error=tostring(refs) end
   local modeok,mode=pcall(function() local m=p.CharacterMovement;assert(valid(m) and name(m:GetOwner())==pid,'movement owner mismatch');assert(finite(m.MovementMode),'mode unreadable');return m.MovementMode end)
   s.mode_readable=modeok;if modeok then s.mode=mode else s.mode_error=tostring(mode) end
   local animok,montage=pcall(function() return name(p.Mesh:GetAnimInstance():GetCurrentActiveMontage()) end)
   s.montage_readable=animok;if animok then s.active_montage=montage or 'none' else s.montage_error=tostring(montage) end
   s.complete=s.abilities_complete and s.references_readable and s.mode_readable and s.montage_readable
   if not s.complete then
    local errors={};for _,k in ipairs({'ability_error','reference_error','mode_error','montage_error'}) do if s[k] then errors[#errors+1]=k..'='..s[k] end end
    s.error=table.concat(errors,'; ')
   end
   return s,abok and found or nil
  end)
  if not ok then return nil,nil,tostring(result) end;return result,objects
 end
 local actor_named,apply_owned_ui,refresh_owned_ui
 local ui_baseline_done=false
 local function inspect_player()
  local s,_,err=read_player();if not s then return false,err end
  if s.complete and not ui_baseline_done then
   ui_baseline_done=true
   local ok,result=refresh_owned_ui(s)
   emit('ui_baseline_refresh accepted='..tostring(ok)..' detail='..tostring(type(result)=='table' and result.applied or result))
  end
  return true,s
 end
 local function entry() for _,e in ipairs(state.pool) do if e.volume==state.volume then return e end end end
 local function selected_snapshot()
  local e=entry();if not e then return nil,nil,nil,'no selected owned side volume' end
  local s,objects,err=read_player();if not s then return nil,nil,nil,err end
  if s.player_id~=state.player or s.world_id~=state.world then return nil,nil,nil,'player/world changed' end
  return e,s,objects
 end
 local function matching(e,s)
  local found={};local other=0
  for _,a in ipairs(s.special_abilities or {}) do
   if a.ordinary and (a.volume_id==e.volume or (a.id==e.ability and a.volume_id==nil)) then found[#found+1]=a else other=other+1 end
  end
  return found,other
 end
 apply_owned_ui=function(actor,force)
  if not owned_ui then return false end
  local ok,accepted=pcall(owned_ui.apply,actor,force)
  if not ok then emit('owned_ui_apply_error='..tostring(accepted));return false end
  return accepted==true
 end
 local function inspect()
  local e,s,objects,err=selected_snapshot();if not e then return false,err end
  if not s.complete then e.idle_count=0;return false,s.error or 'incomplete lifecycle evidence' end
  if e.last_time and s.time<e.last_time then e.idle_count=0;e.dispatched_at=s.time;e.first_observed_at=s.time;e.last_time=s.time;return false,'clock rewound; observation restarted' end
  local new_sample=not e.last_time or s.time>e.last_time;e.last_time=s.time;e.first_observed_at=e.first_observed_at or s.time
  local owned,other=matching(e,s)
  -- Reuse current call's freshly enumerated ability/ASM reference, not a stored
  -- UObject or per-frame global actor scan. Fallback lookup is bounded to 4 Hz.
  local uiactor
  if #owned==1 and owned[1].volume_id==e.volume then
   local ok,a=pcall(function() return objects[owned[1].id].SideRunning end)
   if ok and valid(a) and name(a)==e.volume then uiactor=a end
  elseif s.current_refs.side_volume==e.volume then
   local ok,a=pcall(function() return H.GetPlayer().ASM_SpecialMoveComponent.CurSideRunningVolume end)
   if ok and valid(a) and name(a)==e.volume then uiactor=a end
  end
  if not uiactor and (not e.ui_last_lookup or s.time<e.ui_last_lookup or s.time-e.ui_last_lookup>=.25) then
   e.ui_last_lookup=s.time;local ok,a=pcall(actor_named,e);if ok and valid(a) then uiactor=a end
  end
  if uiactor then apply_owned_ui(uiactor,false) end
  if #owned==1 then
   if e.ability and e.ability~=owned[1].id then e.phase='quarantined';state.phase=e.phase;e.idle_count=0;return false,'owned ability instance changed' end
   e.ability=owned[1].id;e.seen_active=true
   if not e.side_observation_logged then
    e.side_observation_logged=true
    emit('native_side_observed attempt='..e.attempt_id..' selected='..tostring(e.selected_side)
     ..' ability_wall_on_right='..tostring(owned[1].diagnostics and owned[1].diagnostics.wall_on_right)
     ..' ASM_box_a='..tostring(s.current_refs.side_in_box_a)..' side_volume='..tostring(s.current_refs.side_volume))
   end
   if not e.montage_inventory and owned[1].volume_id==e.volume then
    local ok,inventory=pcall(montage_inventory,objects[owned[1].id])
    e.montage_inventory=ok and inventory or {complete=false,ending={},errors={tostring(inventory)}}
    emit('montage_inventory attempt='..e.attempt_id..' complete='..tostring(e.montage_inventory.complete))
   end
  end
  local ending=e.montage_inventory and e.montage_inventory.ending or {}
  -- FinishOut can end the ability before its non-stopping montage finishes.
  -- A known owned attempt therefore retains its exact tail even after bIsActive
  -- clears. Foreign active moves/interactions never receive that ownership.
  local refs_clear=true
  for _,key in ipairs({'asm_volume','side_volume','interaction','interacting'}) do local value=s.current_refs[key];if value and value~=e.volume then refs_clear=false end end
  local attributable=#owned==1 or (e.seen_active and #owned==0 and refs_clear)
  local native_end=attributable and other==0 and ending[s.active_montage] or false
  if native_end and not e.finishing then
   e.finishing=true;e.finishing_at=s.time;e.ending_kind=native_end;e.ending_montage=s.active_montage
   if e.phase=='running' then e.phase='finishing';state.phase=e.phase end
   emit('finishing_enter attempt='..e.attempt_id..' kind='..tostring(native_end)..' montage='..s.active_montage)
  end
  local idle=#owned==0 and other==0 and s.active_montage=='none' and (s.mode==1 or s.mode==3) and s.interact_clear
  local can_confirm=e.phase=='running' or e.phase=='finishing' or e.phase=='cancelling' or e.phase=='quarantined'
  local old_enough=e.seen_active or s.time-(e.dispatched_at or e.first_observed_at)>=.8
  if can_confirm and idle and old_enough then
   if new_sample then e.idle_count=(e.idle_count or 0)+1 end
   if e.idle_count>=2 then e.inactive_reason=e.seen_active and 'ended_confirmed' or 'never_started_confirmed';e.phase='inactive';state.phase='inactive';emit('inactive_confirmed reason='..e.inactive_reason..' volume='..e.volume) end
  else e.idle_count=0 end
  s.volume=e.volume;s.attempt_id=e.attempt_id;s.phase=e.phase;s.active_count=#owned;s.other_active_count=other;s.unknown_active_count=0
  s.abilities=s.ordinary_instances;s.inactive_reason=e.inactive_reason;s.seen_active=e.seen_active==true
  s.cancel_dispatched=e.cancel_attempted==true;s.dispatch_uncertain=e.dispatch_uncertain==true
  s.ending_montages=copy(ending);s.ending_assets_complete=e.montage_inventory and e.montage_inventory.complete or false
  s.ending_asset_errors=e.montage_inventory and copy(e.montage_inventory.errors) or {}
  s.native_ending_active=native_end~=false;s.finishing=e.finishing==true;s.ending_kind=e.ending_kind;s.ending_montage=e.ending_montage
  s.finish_request_attempted=e.finish_request_attempted==true;s.finish_request_uncertain=e.finish_request_uncertain==true;s.finish_request_error=e.finish_request_error
  s.selected_side=e.selected_side
  if #owned==1 then
   s.observed_wall_on_right=owned[1].diagnostics and owned[1].diagnostics.wall_on_right
   if type(s.observed_wall_on_right)=='boolean' then s.side_selection_matches=s.observed_wall_on_right==(e.selected_side=='A') and s.current_refs.side_in_box_a==(e.selected_side=='A') end
  end
  return true,s
 end
 actor_named=function(e)
  local all=FindAllOf(e.class_name);assert(all==nil or type(all)=='table','side actor enumeration unavailable')
  for _,a in ipairs(all or {}) do
   if valid(a) and name(a)==e.volume then
    assert(world_of(a)==state.world,'owned actor World mismatch')
    assert(name(a:GetClass())==e.class_full_name,'owned actor class changed');return a
   end
  end
 end
 refresh_owned_ui=function(current)
  if not current then local s,_,err=read_player();if not s then return false,err end;current=s end
  if current.player_id~=state.player or current.world_id~=state.world then return true,{applied=0,skipped='no owned pool in current context'} end
  if #state.pool>2 then return false,'owned side pool exceeds expected maximum two' end
  local report={checked=0,applied=0,errors={}}
  for _,candidate in ipairs(state.pool) do
   report.checked=report.checked+1
   local ok,actor=pcall(actor_named,candidate)
   if ok and valid(actor) then
    if apply_owned_ui(actor,true) then report.applied=report.applied+1 else report.errors[#report.errors+1]='UI apply refused: '..tostring(candidate.volume) end
   else report.errors[#report.errors+1]='owned actor unavailable: '..tostring(candidate.volume) end
  end
  return true,report
 end
 local function owned_component(actor,key)
  local c=actor[key];assert(valid(c),key..' unavailable');assert(name(c:GetOwner())==name(actor),key..' owner mismatch');return c
 end
 local function suppress(actor)
  for _,k in ipairs({'BoxA','BoxB'}) do local b=owned_component(actor,k);b:SetGenerateOverlapEvents(false);b:SetCollisionEnabled(0);assert(b:GetCollisionEnabled()==0,k..' still enabled') end
  apply_owned_ui(actor,true)
 end
 local PARAMS={'WallLength','CanWalkWallHeight','TrigerWidth','TrigerLength','TrigerHeight','CanInteractDistance'}
 local function validate_geometry(spec,s)
  assert(type(spec)=='table' and spec.confirmed_wall==true and spec.spawn_nonoverlap_verified==true,'verified solid wall/nonoverlap required')
  local g=spec.geometry
  assert(type(g)=='table' and g.mapping_verified==true,'side geometry pending current probe verification')
  assert(g.player_id==s.player_id and g.world_id==s.world_id,'side geometry player/world evidence mismatch')
  assert(type(g.probe_id)=='string' and g.probe_id~='','side geometry probe id required')
  assert(type(g.class_path)=='string' and g.class_path:sub(1,1)=='/' and type(g.class_name)=='string' and g.class_name~='','exact observed side class path/name required')
  assert(type(g.class_full_name)=='string' and g.class_full_name~='','exact observed side class full name required')
  assert(spec.side=='A' or spec.side=='B','selected side A/B required')
  assert(vector(spec.world_position),'side world position required');rotation(spec.rotation)
  assert(g.selection_mode=='on_interact_only' or g.selection_mode=='native_set_cur_side_then_interact','side native selection strategy unavailable')
  assert(type(g.parameters)=='table','side parameter mapping unavailable')
  for _,k in ipairs(PARAMS) do assert(finite(g.parameters[k]) and g.parameters[k]>0 and g.parameters[k]<=100000,'side parameter invalid: '..k) end
  assert(type(g.expected)=='table','side expected geometry required')
  for _,suffix in ipairs({'A','B'}) do
   local side=g.expected[suffix];assert(type(side)=='table','expected side missing')
   for _,k in ipairs({'start_world','end_world','move_forward','direction_forward'}) do assert(vector(side[k]),'expected side geometry missing: '..suffix..'.'..k) end
   assert(distance2(side.start_world,side.end_world)>1,'side segment has no travel distance')
  end
  -- Avoid carrying arbitrary objects/functions from caller into persistent state.
  return copy(g)
 end
 local function geometry_read(actor,g)
  local out={}
  for _,suffix in ipairs({'A','B'}) do
   local start=owned_component(actor,'StartPosition'..suffix);local ending=owned_component(actor,'EndPositionStatic'..suffix)
   local direction=owned_component(actor,'Direction'..suffix);local arrow=owned_component(actor,'MoveDirection'..suffix)
   local row={start_world=point(start:K2_GetComponentLocation()),end_world=point(ending:K2_GetComponentLocation()),
    start_relative=point(start.RelativeLocation),end_relative=point(ending.RelativeLocation),move_forward=point(arrow:GetForwardVector()),
    direction_forward=point(direction:GetForwardVector()),move_rotation=rotation(arrow:K2_GetComponentRotation()),direction_rotation=rotation(direction:K2_GetComponentRotation())}
   local expected=g.expected[suffix]
   for _,k in ipairs({'start_world','end_world'}) do assert(distance2(row[k],expected[k])<=1,'constructed side position differs: '..suffix..'.'..k) end
   for _,k in ipairs({'move_forward','direction_forward'}) do assert(distance2(row[k],expected[k])<=.0001,'constructed side direction differs: '..suffix..'.'..k) end
   out[suffix]=row
  end
  return out
 end
 local function abort_prepared(e,reason)
  if e and not e.dispatched then e.phase='inactive';e.inactive_reason='not_dispatched';state.phase='inactive' end
  return false,reason
 end
 local function can_reuse(candidate,s,actor)
  if not s.references[candidate.volume] then return true,false end
  -- A cached ASM side pointer is not an active ability. Reusing our own fully
  -- observed idle volume avoids a two-attempt ceiling without clearing player
  -- fields or moving an actor still participating in any live special move.
  if candidate.inactive_reason~='ended_confirmed' and candidate.inactive_reason~='never_started_confirmed' then return false end
  if not s.complete or s.all_special_active_count~=0 or s.active_montage~='none' or not s.interact_clear or (s.mode~=1 and s.mode~=3) then return false end
  for _,key in ipairs({'native_volume','interaction','interacting'}) do if s.current_refs[key]==candidate.volume then return false end end
  local ok,why=pcall(function()
   for _,k in ipairs({'BoxA','BoxB'}) do
    local box=owned_component(actor,k)
    assert(box:GetCollisionEnabled()==0 and bool(box:GetGenerateOverlapEvents())==false,'cached side reuse requires disabled boxes')
   end
  end)
  if not ok then emit('cached_asm_reuse_refused reason='..tostring(why));return false end
  return true,true
 end
 local function prepare(p,spec)
  local s,_,err=read_player();if not s then return false,err end
  if not valid(p) or name(p)~=s.player_id then return false,'player mismatch' end
  if not s.complete or not s.ordinary_spec_found then return false,'ordinary side ability/ASM preflight incomplete' end
  if s.all_special_active_count~=0 or not s.interact_clear then return false,'another special move or interaction active' end
  local gate,g=pcall(validate_geometry,spec,s);if not gate then return false,tostring(g) end
  if state.world~=s.world_id or state.player~=s.player_id then state.pool={};state.world=s.world_id;state.player=s.player_id;state.volume=nil;state.phase=nil end
  if state.phase=='prepared' or state.phase=='running' or state.phase=='finishing' or state.phase=='cancelling' or state.phase=='quarantined' then return false,'prior attempt not confirmed inactive' end
  local actor,e,reused
  local ok,why=pcall(function()
   local cl=StaticFindObject(g.class_path);assert(valid(cl),'observed side class not loaded')
   assert(name(cl)==g.class_full_name and cl:GetFName():ToString()==g.class_name,'loaded side class differs from probe')
   assert(class_has(cl,'BP_ASM_SideRunning_Base_C'),'observed class is not ordinary ASM side volume')
   for _,candidate in ipairs(state.pool) do
    if candidate.phase=='inactive' and not candidate.unsafe_setup and candidate.class_full_name==g.class_full_name then
     local a=actor_named(candidate)
     if a then local allowed,cached=can_reuse(candidate,s,a);if allowed then
      actor=a;e=candidate;reused=true
      if cached then emit('cached_asm_reuse volume='..candidate.volume..' prior='..candidate.inactive_reason..' complete_idle=true boxes_disabled=true') end
      break
     end end
    end
   end
   local w,r=point(spec.world_position),rotation(spec.rotation)
   if not actor then
    assert(#state.pool<2,'no reusable unreferenced owned side volume')
    local currentw=H.GetWorld();assert(name(currentw)==s.world_id and name(H.GetPlayer())==s.player_id,'player/world changed before spawn')
    actor=currentw:SpawnActor(cl,{X=w.X,Y=w.Y,Z=w.Z+50000},r);assert(valid(actor),'side volume spawn failed')
    e={volume=name(actor),class_name=g.class_name,class_full_name=g.class_full_name,class_path=g.class_path,phase='inactive'}
    state.pool[#state.pool+1]=e;reused=false
   end
   assert(world_of(actor)==s.world_id and name(actor:GetClass())==g.class_full_name,'spawned side actor identity mismatch')
   state.volume=e.volume;e.dispatched=false;e.cancel_attempted=false;e.ability=nil;e.seen_active=false
   local serial=state.attempt_serial or 0;assert(finite(serial) and serial>=0 and serial%1==0 and serial<9007199254740990,'attempt serial unavailable')
   state.attempt_serial=serial+1;e.attempt_id=state.attempt_serial;e.probe_id=g.probe_id;e.selected_side=spec.side
   e.dispatched_at=nil;e.first_observed_at=nil;e.last_time=nil;e.idle_count=0;e.inactive_reason=nil;e.dispatch_uncertain=false
   e.dispatch_error=nil;e.cancel_error=nil;e.finishing=false;e.finishing_at=nil;e.ending_kind=nil;e.ending_montage=nil;e.montage_inventory=nil;e.side_observation_logged=false;e.ui_last_lookup=nil
   e.finish_request_attempted=false;e.finish_request_uncertain=false;e.finish_request_error=nil;e.original_endpoint=nil;e.requested_endpoint=nil;e.finish_request_time=nil
   e.setup_attempted=false;e.setup_uncertain=false;e.setup_error=nil;e.setup_before=nil;e.setup_after=nil;e.setup_rollback=nil;e.helper_after=nil
   e.side_flag_attempted=false;e.side_flag_uncertain=false;e.side_flag_before=nil;e.side_flag_after=nil;e.side_flag_error=nil
   e.selection_mode=g.selection_mode;e.player_asm_setup='none';e.geometry_contract=g
   suppress(actor)
   for _,k in ipairs(PARAMS) do actor[k]=g.parameters[k] end
   actor.NeedInteractAsGroup=false
   actor:DoConstruction();suppress(actor)
   actor:K2_SetActorLocation(w,false,{},true);actor:K2_SetActorRotation(r,true);suppress(actor)
   assert(distance2(point(actor:K2_GetActorLocation()),w)<1,'side actor placement failed')
   local actual_r=rotation(actor:K2_GetActorRotation())
   for _,k in ipairs({'Pitch','Yaw','Roll'}) do assert(math.abs((actual_r[k]-r[k]+180)%360-180)<1,'side actor rotation failed') end
   e.geometry=geometry_read(actor,g);e.prepared_position=w;e.prepared_rotation=r
   assert(name(H.GetPlayer())==s.player_id and name(H.GetWorld())==s.world_id,'player/world changed during side prepare')
   emit('prepared_geometry volume='..e.volume..' side='..e.selected_side..' probe='..e.probe_id
    ..' start='..xyz(e.geometry[e.selected_side].start_world)..' end='..xyz(e.geometry[e.selected_side].end_world)..' selection='..e.selection_mode)
  end)
  if not ok then
   if e then e.unsafe_setup=true;e.phase='inactive';e.inactive_reason='prepare_failed_not_dispatched';state.phase='inactive';pcall(suppress,actor) end
   emit('prepare_failed='..tostring(why));return false,tostring(why)
  end
  e.phase='prepared';e.unsafe_setup=false;state.phase='prepared'
  return true,{variant='ordinary_side_asm',player=s.player_id,volume=e.volume,attempt_id=e.attempt_id,reused=reused,
   side=e.selected_side,start_world=copy(e.geometry[e.selected_side].start_world),end_world=copy(e.geometry[e.selected_side].end_world),geometry_verified=true,
   selection_verified=false,selection_mode=e.selection_mode,probe_id=e.probe_id}
 end
 local function start()
  local e=entry();if not e or e.phase~='prepared' then return false,'no prepared side attempt' end
  local s,_,err=read_player()
  if not s or s.player_id~=state.player or s.world_id~=state.world then return abort_prepared(e,err or 'player/world changed') end
  if not s.complete or not s.ordinary_spec_found then return abort_prepared(e,'side lifecycle preflight incomplete') end
  if s.all_special_active_count~=0 or not s.interact_clear then return abort_prepared(e,'another special move or interaction active') end
  local ok,actor=pcall(actor_named,e);if not ok or not valid(actor) then return abort_prepared(e,'owned side volume unavailable: '..tostring(actor)) end
  local setupok,why=pcall(function()
   for _,k in ipairs({'BoxA','BoxB'}) do assert(owned_component(actor,k):GetCollisionEnabled()==0,k..' enabled before dispatch') end
   geometry_read(actor,e.geometry_contract)
   assert(name(H.GetPlayer())==state.player and name(H.GetWorld())==state.world,'player/world changed before dispatch')
   assert(e.player_asm_setup=='none','side setup already attempted')
   assert(e.selection_mode=='on_interact_only' or e.selection_mode=='native_set_cur_side_then_interact','unverified side setup strategy')
  end)
  if not setupok then return abort_prepared(e,tostring(why)) end
  local function result(setup_only)
   return {player=state.player,player_id=state.player,world=state.world,world_id=state.world,volume=e.volume,attempt_id=e.attempt_id,
    variant='ordinary_side_asm',verified=false,dispatch_uncertain=e.dispatch_uncertain,dispatch_error=e.dispatch_error,
    selection_verified=false,setup_only=setup_only==true,setup_attempted=e.setup_attempted==true,setup_uncertain=e.setup_uncertain==true}
  end
  if e.selection_mode=='native_set_cur_side_then_interact' then
   -- This exact native helper is an explicit experiment, not assumed proven
   -- initialization. Local snapshots may hold UObjects only for this call;
   -- persistent setup_before/setup_after contain names and booleans only.
   local p=H.GetPlayer();local asm=p.ASM_SpecialMoveComponent;local interact=p.PBZInteract
   local function snapshot()
    assert(name(H.GetPlayer())==state.player and name(H.GetWorld())==state.world,'side setup context changed')
    assert(valid(asm) and name(asm)==s.asm_component_id and name(asm:GetOwner())==state.player,'side setup ASM ownership changed')
    assert(valid(interact) and name(interact:GetOwner())==state.player,'side setup interaction ownership changed')
    local current={CurSpecialMoveVolume=asm.CurSpecialMoveVolume,CurSideRunningVolume=asm.CurSideRunningVolume,
     SideRunningIsInBoxA=bool(asm.SideRunningIsInBoxA),IsInSideRunningVolume=bool(asm.IsInSideRunningVolume)}
    return current,{asm_volume=name(current.CurSpecialMoveVolume),side_volume=name(current.CurSideRunningVolume),
     side_in_box_a=current.SideRunningIsInBoxA,in_side_volume=current.IsInSideRunningVolume,
     interaction=name(interact.CurrentInteractActor),interacting=name(interact.InteractingActor)}
   end
   local beforeok,before,before_ids=pcall(snapshot)
   if not beforeok then return abort_prepared(e,tostring(before)) end
   local arrowok,arrow=pcall(owned_component,actor,'MoveDirection'..e.selected_side)
   if not arrowok then return abort_prepared(e,tostring(arrow)) end
   e.setup_before=copy(before_ids);e.setup_attempted=true;e.player_asm_setup='native_set_cur_side_then_interact'
   emit('selection_setup_begin attempt='..e.attempt_id..' side='..e.selected_side..' previous_side='..tostring(before_ids.side_volume)
    ..' previous_asm='..tostring(before_ids.asm_volume)..' previous_box_a='..tostring(before_ids.side_in_box_a))
   local invoked,invoke_error=pcall(function() actor:SetCurSideRunningVolume(asm,arrow) end)
   local readok,after,after_ids=pcall(snapshot)
   if readok then e.setup_after=copy(after_ids);e.helper_after=copy(after_ids) end
   local post,_,posterr=read_player()
   local function idle_post(view)
    return view and view.complete and view.player_id==state.player and view.world_id==state.world
     and view.asm_component_id==s.asm_component_id and view.all_special_active_count==0 and view.interact_clear
   end
   local helper_ready=invoked and readok and after_ids.side_volume==e.volume and idle_post(post)
   emit('selection_helper_readback attempt='..e.attempt_id..' side='..e.selected_side..' invoked='..tostring(invoked)
    ..' readable='..tostring(readok)..' side_volume='..tostring(readok and after_ids.side_volume or nil)
    ..' box_a_uncorrected='..tostring(readok and after_ids.side_in_box_a)..' in_side_uncorrected='..tostring(readok and after_ids.in_side_volume)
    ..' post_complete='..tostring(post and post.complete)..' post_active='..tostring(post and post.all_special_active_count)
    ..' post_interact_clear='..tostring(post and post.interact_clear)..' post_error='..tostring(posterr or (post and post.error))
    ..' ready='..tostring(helper_ready==true))
   local verified=false
   if helper_ready then
    -- The helper's exact implementation is unavailable. Do not claim it sets
    -- the A/B flag: explicitly supply the selected flag only under a new full
    -- idle/ownership check, within the same snapshot/CAS rollback transaction.
    local setok,seterr=pcall(function()
     local current,ids=snapshot()
     assert(ids.side_volume==e.volume,'side flag current side volume changed')
     for _,key in ipairs({'asm_volume','side_volume','side_in_box_a','in_side_volume','interaction','interacting'}) do
      assert(ids[key]==after_ids[key],'side flag helper readback changed: '..key)
     end
     local latest,_,latesterr=read_player();assert(idle_post(latest),latesterr or (latest and latest.error) or 'side flag idle evidence changed')
     assert(latest.current_refs.side_volume==e.volume,'side flag fresh side ownership changed')
     local expected=e.selected_side=='A'
     e.side_flag_before=current.SideRunningIsInBoxA
     if current.SideRunningIsInBoxA~=expected then
      e.side_flag_attempted=true -- BEFORE setter: an exception may follow a side effect.
      asm.SideRunningIsInBoxA=expected
     end
     e.side_flag_after=bool(asm.SideRunningIsInBoxA)
     assert(e.side_flag_after==expected,'explicit side flag readback mismatch')
    end)
    if not setok then e.side_flag_error=tostring(seterr);e.side_flag_uncertain=e.side_flag_attempted==true end
    -- Capture the post-set state for compare-before-rollback, including the
    -- case where a setter threw after it had already changed the property.
    readok,after,after_ids=pcall(snapshot)
    if readok then e.setup_after=copy(after_ids);e.side_flag_after=after_ids.side_in_box_a end
    post,_,posterr=read_player()
    verified=setok and readok and after_ids.side_volume==e.volume and after_ids.side_in_box_a==(e.selected_side=='A') and idle_post(post)
    emit('selection_sideflag attempt='..e.attempt_id..' selected='..e.selected_side..' before='..tostring(e.side_flag_before)
     ..' after='..tostring(e.side_flag_after)..' attempted='..tostring(e.side_flag_attempted)..' uncertain='..tostring(e.side_flag_uncertain)
     ..' post_complete='..tostring(post and post.complete)..' post_active='..tostring(post and post.all_special_active_count)
     ..' post_interact_clear='..tostring(post and post.interact_clear)..' verified='..tostring(verified==true)..' error='..tostring(e.side_flag_error))
   end
   if not verified then
    local rollbackok,rollbackerr=pcall(function()
     local live,_,err2=read_player();assert(live and live.complete,err2 or 'setup rollback evidence incomplete')
     assert(live.player_id==state.player and live.world_id==state.world and live.all_special_active_count==0 and live.interact_clear,'setup rollback activity/context changed')
     local current,ids=snapshot()
     for _,key in ipairs({'asm_volume','side_volume'}) do
      assert(ids[key]==before_ids[key] or ids[key]==e.volume,'setup rollback foreign reference: '..key)
     end
     assert(ids.interaction==before_ids.interaction and ids.interacting==before_ids.interacting,'setup rollback interaction changed')
     if readok then
      for _,key in ipairs({'asm_volume','side_volume','side_in_box_a','in_side_volume'}) do assert(ids[key]==after_ids[key],'setup rollback readback changed: '..key) end
     else
      -- Without an after snapshot boolean mutations cannot be safely attributed.
      assert(ids.side_in_box_a==before_ids.side_in_box_a and ids.in_side_volume==before_ids.in_side_volume,'setup rollback unknown boolean side effects')
     end
     for _,key in ipairs({'CurSpecialMoveVolume','CurSideRunningVolume'}) do
      local old=before[key];local old_id=name(old)
      local original_id
      if key=='CurSpecialMoveVolume' then original_id=before_ids.asm_volume else original_id=before_ids.side_volume end
      assert(old_id==original_id,'setup rollback previous actor no longer valid')
      if old_id then assert(world_of(old)==state.world,'setup rollback old volume World mismatch') end
      if name(current[key])~=old_id then asm[key]=old end
     end
     if current.SideRunningIsInBoxA~=before.SideRunningIsInBoxA then asm.SideRunningIsInBoxA=before.SideRunningIsInBoxA end
     if current.IsInSideRunningVolume~=before.IsInSideRunningVolume then asm.IsInSideRunningVolume=before.IsInSideRunningVolume end
     local _,restored=snapshot()
     for _,key in ipairs({'asm_volume','side_volume','side_in_box_a','in_side_volume','interaction','interacting'}) do assert(restored[key]==before_ids[key],'setup rollback verification failed: '..key) end
    end)
    e.setup_rollback={attempted=true,verified=rollbackok,error=not rollbackok and tostring(rollbackerr) or nil}
    local why2=not invoked and tostring(invoke_error) or e.side_flag_error or not readok and tostring(after) or posterr or (post and post.error) or 'native side selection readback/preflight failed'
    e.setup_error=tostring(why2)
    emit('selection_setup_failed attempt='..e.attempt_id..' reason='..e.setup_error..' rollback_verified='..tostring(rollbackok))
    if invoked and rollbackok and not e.side_flag_uncertain then e.player_asm_setup='rolled_back';return abort_prepared(e,e.setup_error) end
    -- Native helper exceptions, unknown/refused rollback, or new active moves
    -- retain an accepted uncertain ownership ticket. They are never safe retries.
    e.setup_uncertain=true;e.dispatched=true;e.dispatched_at=s.time;e.phase='quarantined';state.phase=e.phase
    e.dispatch_uncertain=true;e.dispatch_error=e.setup_error;return true,result(true)
   end
   emit('selection_setup_readback attempt='..e.attempt_id..' side_volume='..tostring(after_ids.side_volume)
    ..' box_a='..tostring(after_ids.side_in_box_a)..' in_side='..tostring(after_ids.in_side_volume)..' native_behavior_verified=false')
  end
  e.dispatched=true;e.dispatched_at=s.time;e.phase='running';state.phase='running';e.idle_count=0
  local invoked,invoke_error=pcall(function() actor:OnInteract(H.GetPlayer()) end)
  local cleaned,cleanup_error=pcall(suppress,actor)
  if not invoked or not cleaned then e.phase='quarantined';state.phase=e.phase;e.dispatch_uncertain=true;e.dispatch_error=tostring(not invoked and invoke_error or cleanup_error) end
  emit('interact_dispatched volume='..e.volume..' attempt='..e.attempt_id..' uncertain='..tostring(e.dispatch_uncertain))
  return true,result(false)
 end
 local function cancel(options)
  local e,s,objects,err=selected_snapshot();if not e then return false,err end
  if e.cancel_attempted then return false,'cancel already dispatched; awaiting observed cleanup' end
  if not e.dispatched or e.phase=='inactive' or e.phase=='prepared' then return false,'no dispatched side attempt' end
  if not s.complete then return false,'lifecycle evidence incomplete' end
  local owned,other=matching(e,s)
  if #owned~=1 or other~=0 then return false,'expected one exact owned side ability and no other special move' end
  local row=owned[1]
  if e.ability and e.ability~=row.id then return false,'owned ability identity changed' end
  if row.player_id~=s.player_id or row.asc_id~=s.asc_id then return false,'side ability avatar/ASC identity mismatch' end
  for _,key in ipairs({'asm_volume','side_volume','interaction','interacting'}) do local value=s.current_refs[key];if value and value~=e.volume then return false,'conflicting current reference: '..key end end
  local ability=objects and objects[row.id];if not valid(ability) then return false,'exact side instance unavailable' end
  if not e.montage_inventory then
   local invok,inv=pcall(montage_inventory,ability)
   if not invok then return false,'ending montage inventory unreadable: '..tostring(inv) end
   e.montage_inventory=inv
  end
  local ending=e.montage_inventory.ending[s.active_montage]
  local emergency=type(options)=='table' and options.emergency==true and type(options.reason)=='string' and options.reason~=''
  if (e.finishing or ending) and not emergency then return false,'native side finish in progress; ordinary cancellation deferred' end
  if emergency then emit('emergency_cancel reason='..options.reason) end
  e.ability=row.id;e.seen_active=true;e.cancel_attempted=true;e.phase='cancelling';state.phase=e.phase
  local ok,why=pcall(function() ability:K2_CancelAbility() end)
  if not ok then e.phase='quarantined';state.phase=e.phase;e.cancel_error=tostring(why) end
  emit('cancel_dispatched ability='..e.ability..' uncertain='..tostring(not ok))
  return true,{ability=e.ability,verified=false,dispatch_uncertain=not ok,dispatch_error=not ok and tostring(why) or nil}
 end
 -- Guarded endpoint experiment. It asks the native loop's own beyond-end logic
 -- to finish; it never calls StateEndIn/LoopOut or mutates player movement. An
 -- observed construction mapping must first identify the travel tangent source.
 local function request_finish(ticket)
  local checked,e,ending,target,before=pcall(function()
   local selected,s,objects,err=selected_snapshot();assert(selected,err)
   assert(type(ticket)=='table','side finish exact ticket required')
   assert(ticket.player==state.player and ticket.world_id==state.world and ticket.volume==selected.volume
    and finite(ticket.attempt_id) and ticket.attempt_id==selected.attempt_id,'side finish ticket identity mismatch')
   assert(selected.dispatched and selected.phase=='running','side finish requires running owned attempt')
   assert(not selected.cancel_attempted,'side cancellation already attempted')
   assert(not selected.finishing,'native side finish already observed')
   assert(not selected.finish_request_attempted,'side endpoint finish already attempted; no retry')
   assert(s.complete,'side finish incomplete lifecycle evidence')
   assert(not selected.last_time or s.time>=selected.last_time,'side finish clock rewound')
   local owned,other=matching(selected,s)
   assert(#owned==1 and other==0 and s.all_special_active_count==1,'side finish requires one exact owned active ability')
   local row=owned[1]
   assert(row.volume_id==selected.volume,'side finish current volume missing or changed')
   assert(not selected.ability or selected.ability==row.id,'side finish active instance changed')
   assert(row.player_id==s.player_id and row.asc_id==s.asc_id,'side finish avatar/ASC mismatch')
   for _,key in ipairs({'asm_volume','side_volume','interaction','interacting'}) do
    local value=s.current_refs[key];assert(value==nil or value==selected.volume,'side finish conflicting current reference: '..key)
   end
   local ability=objects[row.id];assert(valid(ability),'side finish exact instance unavailable')
   if not selected.montage_inventory then selected.montage_inventory=montage_inventory(ability) end
   assert(selected.montage_inventory.complete,'side finish timeline inventory incomplete')
   assert(selected.montage_inventory.loop[s.active_montage]==true,'side finish waiting for exact native loop montage')
   local g=selected.geometry_contract
   assert(g.tangent_verified==true and (g.tangent_source=='move_forward' or g.tangent_source=='direction_forward'),
    'side finish tangent mapping pending geometry probe')
   local side=selected.selected_side;local locked=point(selected.geometry[side][g.tangent_source])
   local length=math.sqrt(locked.X*locked.X+locked.Y*locked.Y)
   assert(length>.99 and math.abs(locked.Z)<.01,'side finish requires verified horizontal tangent')
   local tangent={X=locked.X/length,Y=locked.Y/length,Z=0}
   local actor=actor_named(selected);assert(valid(actor),'side finish owned actor unavailable')
   local endpoint=owned_component(actor,'EndPositionStatic'..side)
   local live_source=owned_component(actor,(g.tangent_source=='move_forward' and 'MoveDirection' or 'Direction')..side)
   assert(distance2(point(live_source:GetForwardVector()),locked)<=.0001,'side finish owned tangent changed')
   local original=point(endpoint:K2_GetComponentLocation())
   assert(distance2(original,selected.geometry[side].end_world)<=1,'side finish endpoint changed before request')
   local p,w=H.GetPlayer(),H.GetWorld();assert(name(p)==s.player_id and name(w)==s.world_id and world_of(p)==s.world_id,'side finish current context changed')
   local location=point(p:K2_GetActorLocation())
   local desired={X=location.X-tangent.X*20,Y=location.Y-tangent.Y*20,Z=original.Z}
   return selected,endpoint,desired,{time=s.time,endpoint=original,actor_position=point(actor:K2_GetActorLocation()),
    player_position=location,tangent=tangent,ability=row.id,actor=actor}
  end)
  if not checked then return false,tostring(e) end
  -- Mark before setter. A throw can happen after the endpoint already changed;
  -- return an accepted uncertain request so runtime waits instead of retrying.
  e.finish_request_attempted=true;e.finish_request_time=before.time;e.original_endpoint=before.endpoint;e.requested_endpoint=target
  local invoked,why=pcall(function()
   ending:K2_SetWorldLocation(target,false,{},true)
   assert(name(ending:GetOwner())==e.volume,'side finish endpoint owner changed')
   assert(distance2(point(ending:K2_GetComponentLocation()),target)<=1,'side finish endpoint setter readback mismatch')
   assert(distance2(point(before.actor:K2_GetActorLocation()),before.actor_position)<=.01,'side finish moved parent actor')
  end)
  e.finish_request_uncertain=not invoked;e.finish_request_error=not invoked and tostring(why) or nil
  emit('finish_endpoint_requested attempt='..e.attempt_id..' original='..xyz(before.endpoint)..' target='..xyz(target)
   ..' tangent='..xyz(before.tangent)..' uncertain='..tostring(not invoked)..' native_transition_verified=false')
  return true,{attempted=true,uncertain=not invoked,verified=false,attempt_id=e.attempt_id,volume=e.volume,
   original_endpoint=copy(before.endpoint),requested_endpoint=copy(target),error=e.finish_request_error}
 end
 local function quarantine(reason) local e=entry();if not e then return false,'no selected side volume' end;e.phase='quarantined';state.phase=e.phase;e.idle_count=0;emit('quarantine='..tostring(reason));return true end
 return {prepare=prepare,start=start,inspect=inspect,cancel=cancel,quarantine=quarantine,inspect_player=inspect_player,
  request_finish=request_finish,request_finish_exact=request_finish,refresh_owned_ui=refresh_owned_ui}
end
return M
