-- Experimental adapter; calls native detection, never forces a traversal.
-- It invokes the game's own traversal detection; this is not proof of a mantle.
local M={}
local function valid(o)local ok,v=pcall(function()return o and o:IsValid()end);return ok and v==true end
local function finite(v)return type(v)=='number' and v==v and math.abs(v)<math.huge end
local function name(o)assert(valid(o),'object unavailable');return o:GetFullName()end
local function result_snapshot(c)
 local fields={}
 for _,key in ipairs({'ActionType','bHasFrontTarget','bHasBackTarget','bHasFloorTarget','ObstacleHeight','ObstacleDepth','BackHeight'}) do
  local ok,value=pcall(function()return c.TraversalResult[key]end)
  fields[#fields+1]=key..'='..(ok and tostring(value) or 'unavailable')
 end
 return table.concat(fields,',')
end
function M.try_once(H,FindAllOf,ticket,observed,state)
 if type(state)~='table' or state.attempted then return false,'already_attempted' end
 if type(ticket)~='table' or type(observed)~='table' or observed.sensor_signal~=true
  or observed.landing_verified~=true or observed.landing_clear~=true
  or observed.phase~='inactive' or observed.complete~=true or observed.interact_clear~=true
  or observed.all_special_active_count~=0 or observed.active_montage~='none'
  or (observed.mode~=1 and observed.mode~=3) then return false,'preflight_failed' end
 if observed.player_id~=ticket.player_id or observed.world_id~=ticket.world_id then return false,'identity_changed' end
 local d=ticket.direction
 if type(d)~='table' or not finite(d.X) or not finite(d.Y) or not finite(d.Z)
  or math.abs(d.Z)>.01 or d.X*d.X+d.Y*d.Y<.8 or d.X*d.X+d.Y*d.Y>1.2 then return false,'direction_invalid' end
 local ok,p,w=pcall(function()return H.GetPlayer(),H.GetWorld()end)
 if not ok or not valid(p) or not valid(w) or name(p)~=ticket.player_id or name(w)~=ticket.world_id then return false,'player_or_world_changed' end
 local all_ok,items=pcall(FindAllOf,'SMotionReactorComponent')
 if not all_ok or type(items)~='table' then return false,'component_enumeration_failed' end
 local selected,count=nil,0
 for _,c in ipairs(items) do
  local match,yes=pcall(function()return valid(c) and name(c:GetOwner())==ticket.player_id end)
  if match and yes then selected=c;count=count+1 end
 end
 if count~=1 then return false,'component_not_unique' end
 -- Mark before invocation; a reflection error can occur after a native write.
 state.attempted=true
 local before=result_snapshot(selected)
 local invoked,why=pcall(function()selected:CheckJumpMantle({X=d.X,Y=d.Y,Z=0})end)
 return true,{invoked=invoked,uncertain=not invoked,error=not invoked and tostring(why) or nil,verified=false,
  before=before,after=result_snapshot(selected)}
end
return M
