-- Initialization / idle-only exact asset preload. Existing game thread only.
-- No hooks, actors, abilities, collision, movement or timeline changes.
-- inspect_player is the existing ordinary adapter's read-only inspector.
-- State and returned reports contain primitives only; no UObject is retained.
local M={}
local UP='/Game/RenewalContent/Actors/SpecialMove/BP_ASM_UpRunning.BP_ASM_UpRunning_C'
local SIDE='/Game/RenewalContent/Actors/SpecialMove/BP_ASM_SideRunning.BP_ASM_SideRunning_C'
M.class_path=UP
M.side_class_path=SIDE
function M.new(H,log,state,inspect_player,options)
 assert(options==nil or type(options)=='table','preload options must be a table')
 local CLASS=options and options.class_path or UP
 assert(CLASS==UP or CLASS==SIDE,'preload class must be the confirmed UpRunning or SideRunning exact path')
 local CLASS_ID='BlueprintGeneratedClass '..CLASS
 state=state or {}
 assert(state.schema==nil or state.schema=='v18.3','preload state schema mismatch')
 assert(state.schema=='v18.3' or state.load_attempted~=true,'use a fresh v18.3 preload state')
 state.schema='v18.3'
 assert(state.class_path==nil or state.class_path==CLASS,'use separate preload state for each exact class')
 state.class_path=CLASS
 local function valid(o) local ok,v=pcall(function() return o and o:IsValid() end);return ok and v==true end
 local function finite(v) return type(v)=='number' and v==v and math.abs(v)<math.huge end
 local function name(o) assert(valid(o),'object unavailable');local n=o:GetFullName();assert(type(n)=='string' and n~='','object name unavailable');return n end
 local function identity()
  local p,w=H.GetPlayer(),H.GetWorld()
  return name(p),name(w)
 end
 local function report(ok,reason,fields)
  local r=fields or {};r.ready=ok==true;r.reason=reason;r.class_path=CLASS
  local key=tostring(r.ready)..'|'..reason..'|'..tostring(state.player)..'|'..tostring(state.world)
  if state.last_report~=key then
   state.last_report=key
   pcall(log or function() end,'v18_3_asset_preload ready='..tostring(r.ready)..' reason='..reason
    ..' attempted='..tostring(state.load_attempted==true)..' success='..tostring(state.success==true)
    ..' reload_count='..tostring(state.reload_count or 0)..' retry_blocked='..tostring(state.retry_blocked==true)..' player='..tostring(state.player)
    ..' world='..tostring(state.world)..' class='..CLASS)
  end
  return ok,r
 end
 local function lookup()
  local c=StaticFindObject(CLASS)
  if c==nil then return false end
  -- An IsValid exception is not evidence of GC. Let lookup's pcall report it.
  local is_valid=c:IsValid();assert(type(is_valid)=='boolean','class validity unreadable')
  if not is_valid then return false end
  assert(name(c)==CLASS_ID,'lookup returned wrong exact class')
  return true
 end
 local function preflight(pid,wid)
  -- Reject obvious idle blockers before enumerating every ability spec. This
  -- is only a cheap rejection; successful loads still need the full inspector
  -- and its post-load checks below. Retain no engine references between calls.
  local p=H.GetPlayer();assert(name(p)==pid,'preflight player changed')
  assert(p.CharacterMovement.MovementMode==1,'defer until grounded idle; no airborne asset load')
  local interact=p.PBZInteract;assert(valid(interact),'interaction component unavailable')
  local function absent(o)
   if o==nil then return true end
   local v=o:IsValid();assert(type(v)=='boolean','interaction validity unreadable')
   return not v
  end
  assert(absent(interact.CurrentInteractActor) and absent(interact.InteractingActor),'interaction is active (cheap preflight)')
  assert(type(inspect_player)=='function','ordinary inspector unavailable')
  local ok,s=inspect_player()
  assert(ok==true and type(s)=='table','ordinary inspector failed: '..tostring(s))
  assert(s.complete==true and s.abilities_complete==true and s.references_readable==true
   and s.mode_readable==true and s.montage_readable==true,'ordinary lifecycle evidence incomplete')
  assert(s.player_id==pid and s.world_id==wid,'inspected player/world changed')
  assert(finite(s.time),'fresh inspector time unavailable')
  assert(s.ordinary_spec_found==true and type(s.ordinary_spec_count)=='number' and s.ordinary_spec_count>0,
   'ordinary '..(CLASS==SIDE and 'SideRunning' or 'UpRunning')..' spec missing; no ability will be granted')
  assert(s.all_special_active_count==0,'special move is active')
  assert(s.interact_clear==true,'interaction is active')
  assert(s.active_montage=='none','montage is active')
  assert(s.mode==1,'defer until grounded idle; no airborne asset load')
  local p2,w2=identity();assert(p2==pid and w2==wid,'current player/world changed')
  return s
 end
 local function ensure(context)
  -- A caller cannot accidentally load from a jump/press/action callback.
  if context~='runtime_init' and context~='enable_idle' then
   return report(false,'initialization_context_required')
  end
  local idok,pid,wid=pcall(identity)
  if not idok then return report(false,'identity_unavailable: '..tostring(pid),{deferred=true}) end
  if state.player~=pid or state.world~=wid then
   state.player=pid;state.world=wid;state.load_attempted=false;state.last_report=nil
   state.load_uncertain=false;state.load_error=nil;state.ready=false
   state.success=false;state.reload_count=0;state.retry_blocked=false;state.last_load_time=nil
   state.cooldown_anchor_time=nil;state.last_observed_time=nil;state.load_in_progress=false
  end
  local foundok,found=pcall(lookup)
  if not foundok then state.ready=false;state.retry_blocked=true;return report(false,'lookup_failed: '..tostring(found)) end
  if found then
   state.ready=true
   return report(true,'already_loaded',{loaded_now=false,exact_class=CLASS_ID})
  end
  state.ready=false
  -- A failed/uncertain load or lookup is never treated as ordinary resource GC.
  if state.retry_blocked then return report(false,'retry_blocked',{uncertain=state.load_uncertain==true}) end
  if state.load_attempted and state.success~=true then return report(false,'previous_load_not_verified',{uncertain=state.load_uncertain==true}) end
  local pfok,pf=pcall(preflight,pid,wid)
  if not pfok then return report(false,'preflight_deferred: '..tostring(pf),{deferred=true}) end
  local is_reload=state.load_attempted==true
  if is_reload then
   if not finite(state.last_load_time) or not finite(state.cooldown_anchor_time) or not finite(state.last_observed_time) then
    state.retry_blocked=true;return report(false,'previous_success_timing_unavailable')
   end
   if pf.time<state.last_observed_time then
    -- Preserve the historical last_load_time; restart a complete cooldown in
    -- the new clock epoch instead of loading immediately or waiting forever.
    state.cooldown_anchor_time=pf.time;state.last_observed_time=pf.time
    return report(false,'clock_rewound_cooldown_reset',{deferred=true,retry_after=5})
   end
   state.last_observed_time=pf.time
   local elapsed=pf.time-state.cooldown_anchor_time
   if elapsed<5 then return report(false,'reload_cooldown',{deferred=true,retry_after=5-elapsed}) end
  end
  if type(LoadAsset)~='function' then return report(false,'LoadAsset_unavailable') end
  -- UE4SS's bundled summon_unloaded_assets.lua uses this exact global API.
  -- Mark before invoking it: exception may follow a resource side effect.
  state.load_attempted=true
  state.success=false;state.load_in_progress=true;state.last_load_time=pf.time
  state.last_observed_time=pf.time;state.cooldown_anchor_time=pf.time
  if is_reload then state.reload_count=(state.reload_count or 0)+1 end
  pcall(log or function() end,'v18_3_asset_preload load_attempt context='..context..' class='..CLASS
   ..' reload='..tostring(is_reload)..' reload_count='..tostring(state.reload_count or 0)..' time='..tostring(pf.time)
   ..' ordinary_specs='..tostring(pf.ordinary_spec_count)..' mode='..tostring(pf.mode)
   ..' player='..pid..' world='..wid)
  local loaded,err=pcall(LoadAsset,CLASS)
  state.load_in_progress=false
  if not loaded then state.load_uncertain=true;state.load_error=tostring(err);state.retry_blocked=true end
  -- The LoadAsset return value is not proof. Re-resolve the exact class.
  local postok,post=pcall(lookup)
  local same,pp,ww=pcall(identity)
  if not same or pp~=pid or ww~=wid then
   state.load_uncertain=true;state.retry_blocked=true
   return report(false,'identity_changed_during_load',{uncertain=true})
  end
  local idleok,idle=pcall(preflight,pid,wid)
  if not idleok then state.retry_blocked=true;return report(false,'post_load_preflight_changed: '..tostring(idle),{deferred=true,uncertain=not loaded}) end
  if not loaded then return report(false,'load_call_uncertain: '..tostring(err),{uncertain=true,exact_class_available=postok and post==true}) end
  if not postok then state.retry_blocked=true;return report(false,'post_load_lookup_failed: '..tostring(post)) end
  if not post then state.retry_blocked=true;return report(false,'exact_class_unavailable_after_load') end
  if idle.time<pf.time then state.retry_blocked=true;return report(false,'clock_rewound_during_load') end
  state.ready=true;state.success=true;state.cooldown_anchor_time=idle.time;state.last_observed_time=idle.time
  return report(true,'loaded_and_verified',{loaded_now=true,reloaded=is_reload,reload_count=state.reload_count or 0,
   exact_class=CLASS_ID,ordinary_spec_count=idle.ordinary_spec_count})
 end
 return {ensure=ensure}
end
return M
