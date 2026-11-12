-- Read-only conservative checks for an automatic mantle candidate.
-- The query API is supplied by a game-thread adapter; no player movement.
local M={}
local function finite(x)return type(x)=='number' and x==x and math.abs(x)<math.huge end
local function v(p)return type(p)=='table' and finite(p.X) and finite(p.Y) and finite(p.Z)end
function M.check(q,n,radius,half,api)
 if not v(q) or not v(n) or not finite(radius) or not finite(half)
  or radius<=0 or half<=radius or type(api)~='table'
  or type(api.floor)~='function' or type(api.sweep)~='function' then return nil,'invalid_input' end
 local len=math.sqrt(n.X*n.X+n.Y*n.Y);if len<.7 then return nil,'invalid_normal' end
 local nx,ny=n.X/len,n.Y/len
 local ahead={X=q.X-nx*(radius+55),Y=q.Y-ny*(radius+55),Z=q.Z}
 local limit=api.walkable_z or .72
 local max_height=api.max_front_height or 70
 if not finite(limit) or limit<=0 or limit>1 or not finite(max_height) or max_height<=0 or max_height>250 then return nil,'invalid_movement_limits' end
 local floor=api.floor({X=ahead.X,Y=ahead.Y,Z=q.Z+half},
  {X=ahead.X,Y=ahead.Y,Z=q.Z-half-80})
 if type(floor)~='table' or floor.hit~=true or floor.blocking~=true or not v(floor.point)
  or not v(floor.normal) or floor.normal.Z<limit then return nil,'floor_unverified' end
 local dz=floor.point.Z-(q.Z-half)
 if dz>max_height or dz< -80 then return nil,'floor_height_out_of_range dz='..tostring(dz)..' max='..tostring(max_height) end
 -- This point is a feasibility sample, never a commanded player position.
 -- Account for a capsule's round bottom when checking sloping ground.
 local slope_lift=radius*(1/math.min(floor.normal.Z,1)-1)
 local destination={X=floor.point.X,Y=floor.point.Y,Z=floor.point.Z+half+slope_lift+8}
 local above={X=destination.X,Y=destination.Y,Z=destination.Z+1}
 if api.sweep(destination,above,radius,half)~=true then return nil,'landing_space_blocked' end
 -- Do not require a fictional vertical-then-horizontal route through an eave.
 -- CheckJumpMantle must perform native detection; we do not force its result.
 return {landing_verified=true,landing_clear=true,path_clear=false,
  destination=destination,floor=floor.point},'landing_clear_native_route_pending'
end
return M
