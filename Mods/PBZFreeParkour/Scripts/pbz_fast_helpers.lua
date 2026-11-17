-- Private UEHelpers facade for this mod only. The shared UEHelpers is not modified.
--
-- Why: shared UEHelpers.GetPlayerController() runs FindAllOf('PlayerController') on
-- every call, and GetPlayer()/GetWorld() each call it. FindAllOf walks the whole
-- object array. The parkour host asks for the player/world several times per 30 ms tick.
--
-- What this does
-- 1. Scope memo: between begin_scope() and end_scope() (one host tick) the controller
--    is resolved once. Nothing is kept after end_scope(); Pawn and World are read
--    afresh on every call, exactly as before.
-- 2. Enumeration-free lookup: GameInstance.LocalPlayers[1].PlayerController, three
--    property reads. It is only trusted after it has been compared with the original
--    FindAllOf result for the same controller address, and it is re-compared every
--    VERIFY_EVERY resolutions and whenever the address changes. A mismatch disables
--    it for the session and every call goes back to the original helper.
-- No engine object is retained between ticks: only an address number and counters.
local M={}
M.VERIFY_EVERY=300
M.MAX_FAST_ERRORS=3
function M.new(base,log)
 assert(type(base)=='table' and type(base.GetPlayerController)=='function','UEHelpers unavailable')
 log=log or function() end
 local H=setmetatable({}, {__index=base})
 local active,cached=false,nil
 local mode='unverified' -- unverified | trusted | disabled
 local verified_address,since_verify,fast_errors=nil,0,0
 local stats={resolves=0,memo_hits=0,fast_used=0,base_calls=0,verifications=0,fallbacks=0}
 local function valid(o)
  local ok,v=pcall(function() return o and o:IsValid() end)
  return ok and v==true
 end
 local function address(o)
  local ok,v=pcall(function() return o:GetAddress() end)
  if ok and v~=nil then return tostring(v) end
 end
 local function base_controller()
  stats.base_calls=stats.base_calls+1
  return base.GetPlayerController()
 end
 local function disable(reason)
  if mode~='disabled' then
   mode='disabled';verified_address=nil
   pcall(log,'fast_player_lookup disabled reason='..tostring(reason)..'; using UEHelpers enumeration')
  end
 end
 local function fast_controller()
  local gi=base.GetGameInstance()
  if not valid(gi) then return nil end
  local players=gi.LocalPlayers
  if players==nil then return nil end
  local count=players:GetArrayNum()
  if type(count)~='number' or count<1 then return nil end
  local lp=players[1]
  if not valid(lp) then return nil end
  local pc=lp.PlayerController
  if not valid(pc) then return nil end
  return pc
 end
 local function resolve()
  stats.resolves=stats.resolves+1
  if mode=='disabled' or type(base.GetGameInstance)~='function' then return base_controller() end
  local ok,pc=pcall(fast_controller)
  if not ok then
   fast_errors=fast_errors+1
   if fast_errors>=M.MAX_FAST_ERRORS then disable('property_chain_error: '..tostring(pc)) end
   stats.fallbacks=stats.fallbacks+1
   return base_controller()
  end
  if pc==nil then
   -- No local player controller through the property chain (menus, travel).
   -- The original helper decides; nothing is learned from this.
   stats.fallbacks=stats.fallbacks+1
   return base_controller()
  end
  fast_errors=0
  local a=address(pc)
  since_verify=since_verify+1
  if mode=='trusted' and a~=nil and a==verified_address and since_verify<M.VERIFY_EVERY then
   stats.fast_used=stats.fast_used+1
   return pc
  end
  -- First use, changed controller, or periodic re-check: compare with the original.
  local reference=base_controller()
  stats.verifications=stats.verifications+1
  since_verify=0
  if not valid(reference) then
   -- The original found nothing. Stay conservative and return its answer.
   mode='unverified';verified_address=nil
   return reference
  end
  local ra=address(reference)
  if a==nil or ra==nil or a~=ra then
   disable('mismatch fast='..tostring(a)..' reference='..tostring(ra))
   return reference
  end
  if mode~='trusted' or verified_address~=a then
   pcall(log,'fast_player_lookup verified; GameInstance.LocalPlayers[1].PlayerController matches UEHelpers; recheck_every='..M.VERIFY_EVERY)
  end
  mode='trusted';verified_address=a
  return reference
 end
 function H.begin_scope() cached=nil;active=true end
 function H.end_scope() cached=nil;active=false end
 function H.GetPlayerController()
  if active and cached~=nil and valid(cached) then
   stats.memo_hits=stats.memo_hits+1
   return cached
  end
  local pc=resolve()
  if active then cached=pc end
  return pc
 end
 function H.GetPlayer()
  local c=H.GetPlayerController()
  if valid(c) and c.Pawn then return c.Pawn end
  return CreateInvalidObject()
 end
 function H.GetWorld()
  local c=H.GetPlayerController()
  if valid(c) then return c:GetWorld() end
  return base.GetWorld()
 end
 function H.fast_lookup_state()
  local copy={mode=mode};for k,v in pairs(stats) do copy[k]=v end
  return copy
 end
 return H
end
return M
