-- Existing vertical movement with persistent owned-Up UI refresh; side motion unchanged.
-- All engine work is called by the existing single game-thread host.
local M={}
local scripts=assert(debug.getinfo(1,'S').source:match('^@(.+[\\/])[^\\/]+$'),'script directory unavailable')
local function module(name) return assert(loadfile(scripts..name))() end
function M.new(H,log,shared)
 shared=shared or {};shared.side_pool=shared.side_pool or {}
 local cfg=module('parkour_config_v10.lua')
 local base=module('parkour_runtime_vertical_v18_4.lua').new(H,log,shared)
 local Router=module('parkour_contact_router_v18.lua')
 local Side=module('parkour_side_controller_v18_2.lua').new(H,log,shared.side_pool,cfg)
 local engine=module('double_jump_engine_v16_1.lua').new(H,log,nil,shared.short_pool,{short_height=cfg.short_height})
 local diagnostics,diagnostic_error_logged
 local diag_ok,diag=pcall(function()
  return module('parkour_diagnostics_request_v18_4.lua').new(H,log)
 end)
 if diag_ok then diagnostics=diag else pcall(log,'v18_4_diagnostics_unavailable='..tostring(diag)) end
 local function finite(n) return type(n)=='number' and n==n and math.abs(n)<math.huge end
 local function vector(v)
  return type(v)=='table' and finite(v.X) and finite(v.Y) and finite(v.Z)
 end
 local function combined_error(method,bok,berr,sok,serr)
  if not bok or not sok then
   error('v18 '..method..' observer failure: base='..tostring(bok and 'ok' or berr)
    ..'; side='..tostring(sok and 'ok' or serr))
  end
 end
 -- Streaming or resource GC may unload a previously verified class.
 -- v18.3 uses separate primitive state and only retries verified-success loads.
 -- Initialization requires fresh grounded/ability/montage/interaction idle proof.
 -- Later checks also require Space up and neither controller owning an action.
 -- All work remains on the existing game-thread host, never start_action.
 shared.asset_preloads_v18_3=shared.asset_preloads_v18_3 or {vertical={},side={}}
 shared.asset_preloads_v18_3.short=shared.asset_preloads_v18_3.short or {}
 local preloads={}
 local init_ok,init_error=pcall(function()
  local Loader=module('parkour_asset_preload_v18_3.lua')
  local up=module('parkour_native_wallrun_v18_4.lua').new(H,log,{})
  preloads[1]=Loader.new(H,log,shared.asset_preloads_v18_3.vertical,up.inspect_player)
  preloads[2]=Loader.new(H,log,shared.asset_preloads_v18_3.short,up.inspect_player,
   {class_path=Loader.short_class_path})
  if cfg.side_enabled then
   local side_inspector=module('parkour_native_siderun_v18_1.lua').new(H,log,{})
   preloads[3]=Loader.new(H,log,shared.asset_preloads_v18_3.side,side_inspector.inspect_player,
    {class_path='/Game/RenewalContent/Actors/SpecialMove/BP_ASM_SideRunning.BP_ASM_SideRunning_C'})
  end
 end)
 if not init_ok then pcall(log,'v18_3_asset_loader_unavailable='..tostring(init_error)) end
 local last_asset_check,asset_identity,load_error_logged=nil,nil,false
 local function ensure_assets(context,now)
  -- Avoid an expensive failed class lookup while a nearby native interaction
  -- already forbids resource loading. No cached UObject or ready flag is used.
  local idle_ok,idle=pcall(function()
   local p=H.GetPlayer();if not p or not p:IsValid() then return false end
   if p.CharacterMovement.MovementMode~=1 then return false end
   local it=p.PBZInteract;if not it or not it:IsValid() then return false end
   for _,key in ipairs({'CurrentInteractActor','InteractingActor'}) do
    local actor=it[key]
    if actor~=nil then local v=actor:IsValid();if type(v)~='boolean' or v then return false end end
   end
   return true
  end)
  if not idle_ok or idle~=true then return end
  for index,loader in ipairs(preloads) do
   local ok,why,detail=pcall(loader.ensure,context,now)
   if not ok and not load_error_logged then
    load_error_logged=true;pcall(log,'v18_3_asset_loader_error='..tostring(why))
   end
   -- candidate5 keep-alive: the hold-run class was just loaded by this mod on proven
   -- grounded idle, so nothing in the map references it. Live logs show the engine
   -- purging it within a second of the first load after arriving in a map, whether that
   -- load ran at runtime construction or on the idle check. Attempted once per verified
   -- load, never retried on its own; a failure only leaves the old reload behaviour.
   if ok and index==1 and why==true and type(detail)=='table' and detail.loaded_now==true
    and type(base.warm_long_pool)=='function' then
    local called,warmed,reason=pcall(base.warm_long_pool)
    if not called or warmed~=true then pcall(log,'candidate5_keepalive skipped='..tostring(called and reason or warmed)) end
   end
  end
 end
 ensure_assets('runtime_init')
 local function update(s,space_down,enabled)
  -- Retain v16.2's flight/identity book-keeping; it has no owned action during a
  -- side run and cannot cancel or alter the side ability.
  local side_before=Side.busy()
  local consumed,player,world=shared.air_consumed,shared.air_player,shared.air_world
  local bok,berr=pcall(base.update,s,space_down,enabled)
  local sok,serr=pcall(Side.update,s,space_down,enabled)
  -- Base's grounded reset knows only its own run. A transient ground sample
  -- cannot free an owned side action's flight while side cleanup is pending.
  -- A real landing can clear normally on the next fully idle update.
  if (side_before or Side.busy()) and consumed==true and s
   and s.player_id==player and s.world_id==world then
   shared.air_player,shared.air_world,shared.air_consumed=player,world,true
  end
  -- Run both observers first, then let the host see a fault; never hide errors.
  combined_error('update',bok,berr,sok,serr)
  if s and type(s.player_id)=='string' and type(s.world_id)=='string' and finite(s.time) then
   local current=s.player_id..'|'..s.world_id
   if current~=asset_identity then asset_identity=current;last_asset_check=nil end
   if enabled==true and space_down==false and s.mode==1 and not base.busy() and not Side.busy()
    and (not last_asset_check or s.time<last_asset_check or s.time-last_asset_check>=.5) then
    last_asset_check=s.time;ensure_assets('enable_idle',s.time)
   end
  end
  if diagnostics then
   local good,why=pcall(diagnostics.update,s,space_down,enabled,base.busy() or Side.busy())
   if not good and not diagnostic_error_logged then
    diagnostic_error_logged=true;pcall(log,'v18_4_diagnostics_error='..tostring(why))
   end
  end
 end
 local function start_action(initial,s)
  if base.busy() or Side.busy() then return false,'previous action still pending/active' end
  if not initial or not s then return false,'fresh wall required' end
  local released=s.second_released==true or s.space_down==false
  if not cfg.side_enabled or not cfg.hold_enabled or released then return base.start_action(initial,s) end
  local second=s.second_press_time or s.time
  if not finite(s.time) or not finite(second) or second>s.time or s.time-second>10.000001 then
   return false,'invalid second press time'
  end
  if s.space_down~=true or s.time-second+.0000001<cfg.hold_threshold then
   return false,'hold decision not ready; session must defer before dispatch'
  end
  if s.mode~=3 and not (s.mode==1 and s.trigger_kind=='ground_push_double') then
   return false,'ordinary air or double grounded contact required'
  end
  if shared.air_consumed and shared.air_player==s.player_id and shared.air_world==s.world_id then
   return false,'this airborne episode already consumed'
  end
  -- The angle must refer to a fresh solid hit, after excluding BP_SplineWall.
  -- No decision is made using a stale cached wall or camera direction.
  local solid,why,ignored=engine.recheck_solid_contact(s)
  if not solid then return false,why end
  if type(solid)~='table' or type(solid.ground)~='table' or not vector(solid.ground.forward)
   or not vector(solid.wall_normal) then return false,'side route geometry unavailable' end
  local selection=Router.classify({contact=solid.contact,body_forward=solid.ground.forward,
   wall_normal=solid.wall_normal,move_input=solid.move_input,velocity=solid.velocity},cfg.side_angles)
  log('v18_contact_route route='..tostring(selection.route)..' angle='..tostring(selection.angle_deg)
   ..' reason='..tostring(selection.reason)..' player='..tostring(s.player_id))
  if selection.status~='selected' then
   if selection.reason=='angle_gray_zone' or selection.reason=='body_facing_away_from_wall' then
    return false,'side_angle_wait'
   end
   return false,'side route rejected: '..tostring(selection.reason)
  end
  if selection.route=='vertical' then return base.start_action(initial,solid) end
  -- Selection is captured by Side.start; subsequent body turning does not
  -- reclassify or change side. No fallback to vertical after a side rejection.
  local ok,detail=Side.start(initial,solid,selection,ignored)
  if ok==true then
   shared.air_player,shared.air_world,shared.air_consumed=s.player_id,s.world_id,true
  end
  return ok,detail
 end
 local function stop(reason)
  local bok,berr=pcall(base.stop,reason)
  local sok,serr=pcall(Side.stop,reason)
  combined_error('stop',bok,berr,sok,serr)
 end
 log('v18_4_wrapper_loaded side_enabled='..tostring(cfg.side_enabled))
 return {sample=base.sample,update=update,start_action=start_action,stop=stop,
  busy=function() return base.busy() or Side.busy() end,
  label=function() return cfg.version..'; short=kick; hold=body-angle; F8 persistent' end}
end
return M
