-- Collision-profile floor query. Returned data is primitive only.
local M={}
local function valid(o)local ok,v=pcall(function()return o and o:IsValid()end);return ok and v==true end
function M.new(validator)
 assert(type(validator)=='table' and type(validator.check)=='function')
 return function(sys,p,cap,a,b,profile,ignored,color,log,walkable_z)
  local hit={}
  local yes=sys:LineTraceSingleByProfile(p,a,b,profile,false,ignored,0,hit,true,color,color,0)
  assert(type(yes)=='boolean','floor query unavailable')
  if not yes then return {hit=false} end
  local pt,n=hit.ImpactPoint,hit.ImpactNormal;assert(pt and n,'floor geometry unavailable')
  local point={X=pt.X,Y=pt.Y,Z=pt.Z};local normal={X=n.X,Y=n.Y,Z=n.Z}
  local resolved,blocking=pcall(function()
   local c=hit.Component:Get();assert(valid(c),'component unresolved')
   return c:GetCollisionResponseToChannel(cap:GetCollisionObjectType())==2
    and cap:GetCollisionResponseToChannel(c:GetCollisionObjectType())==2
  end)
  if not resolved then
   local sample={profile_query=true,hit=true,a=a,b=b,time=hit.Time,point=point,normal=normal,min_normal_z=walkable_z}
   blocking=validator.check(sample)
   if log then log(string.format('shin_mantle_floor_profile_only valid=%s reason=%s time=%s penetrating=%s start_z=%.1f end_z=%.1f point_z=%.1f normal_z=%.3f component_unverified=true',
    tostring(blocking),validator.reason(sample),tostring(hit.Time),tostring(hit.bStartPenetrating),a.Z,b.Z,point.Z,normal.Z)) end
  end
  return {hit=true,blocking=blocking==true,point=point,normal=normal}
 end
end
return M
