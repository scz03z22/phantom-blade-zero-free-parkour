-- Uses the same current-player profile as the contact engine. No query objects
-- are retained after the call. BP_SplineWall actors are excluded by the caller.
local M={}
local scripts=assert(debug.getinfo(1,'S').source:match('^@(.+[\\/])[^\\/]+$'),'script directory unavailable')
local Path=assert(loadfile(scripts..'parkour_side_path_v18.lua'))()
local color={R=0,G=0,B=0,A=0}
local function valid(o) local ok,v=pcall(function() return o and o:IsValid() end);return ok and v==true end
local function finite(v) return type(v)=='number' and v==v and math.abs(v)<math.huge end
local function point(v) assert(v and finite(v.X) and finite(v.Y) and finite(v.Z),'unreadable vector');return {X=v.X,Y=v.Y,Z=v.Z} end
function M.query(H,s,ignored)
 local function identity()
  local p,w=H.GetPlayer(),H.GetWorld()
  assert(valid(p) and valid(w) and p:GetFullName()==s.player_id and w:GetFullName()==s.world_id,'side query identity changed')
  return p,w
 end
 local p,w=identity()
 assert(type(ignored)=='table','side query ignore list unavailable')
 local cap=p.CapsuleComponent;assert(valid(cap) and cap:GetOwner():GetFullName()==s.player_id,'side capsule owner mismatch')
 local radius,half=cap:GetScaledCapsuleRadius(),cap:GetScaledCapsuleHalfHeight()
 assert(finite(radius) and finite(half) and radius>0 and half>=radius,'side capsule invalid')
 local profile,profile_name
 local ok=pcall(function() profile=cap:GetCollisionProfileName();profile_name=profile:ToString() end)
 local by_profile=ok and type(profile_name)=='string' and profile_name~='' and profile_name:lower()~='none' and profile_name:lower()~='custom'
 local sys=H.GetKismetSystemLibrary();assert(valid(sys),'side query library unavailable')
 local function boolean_result(v)
  if v==true or v==1 then return true end
  if v==false or v==0 then return false end
  error('side trace result unreadable')
 end
 local function trace(kind,q)
  identity()
  local hit={};local result
  if kind=='wall' then
   -- Query horizontally at capsule centre rather than below the feet.
   local c,n=point(q.center),point(q.wall_normal)
   local nlen=math.sqrt(n.X*n.X+n.Y*n.Y);assert(nlen>.5,'side query normal invalid')
   local reach=math.max(radius+45,105)
   local dest={X=c.X-n.X/nlen*reach,Y=c.Y-n.Y/nlen*reach,Z=c.Z}
   if by_profile then result=sys:LineTraceSingleByProfile(p,c,dest,profile,false,ignored,0,hit,true,color,color,0)
   else result=sys:LineTraceSingle(p,c,dest,0,false,ignored,0,hit,true,color,color,0) end
   identity();result=boolean_result(result)
   if not result then return {ok=true,hit=false} end
   return {ok=true,hit=true,blocking=hit.bBlockingHit==nil or hit.bBlockingHit==true or hit.bBlockingHit==1,
    point=point(hit.ImpactPoint),normal=point(hit.ImpactNormal)}
  end
  assert(kind=='capsule','unknown side trace kind')
  local from,to=point(q.from),point(q.to)
  local rr=math.max(radius-4,1);local hh=math.max(half-10,rr)
  if by_profile then result=sys:CapsuleTraceSingleByProfile(p,from,to,rr,hh,profile,false,ignored,0,hit,true,color,color,0)
  else result=sys:CapsuleTraceSingle(p,from,to,rr,hh,0,false,ignored,0,hit,true,color,color,0) end
  identity()
  return {ok=true,blocked=boolean_result(result)}
 end
 return trace,radius,half,point(p:K2_GetActorLocation()),by_profile and 'actual_capsule_profile' or 'channel0_unverified_pawn'
end
function M.plan(H,s,selection,ignored,cfg,log)
 local trace,radius,half,q,source=M.query(H,s,ignored)
 -- Native construction places StartPosition 80 cm outside the wall plane.
 -- Plan at that same Z-preserving offset, and verify the prospective start warp
 -- corridor. This function only queries; it never teleports the player.
 local n=point(s.wall_normal);local w=point(s.wall);local len=math.sqrt(n.X*n.X+n.Y*n.Y)
 assert(finite(len) and len>.5,'side start normal unavailable')
 n={X=n.X/len,Y=n.Y/len,Z=0}
 local current_distance=(q.X-w.X)*n.X+(q.Y-w.Y)*n.Y
 local center={X=q.X+n.X*(80-current_distance),Y=q.Y+n.Y*(80-current_distance),Z=q.Z}
 local cleared=trace('capsule',{from=q,to=center})
 local plan
 if cleared.blocked then
  plan={status='too_short',start=center,finish=point(center),usable_distance_cm=0,
   stop_reason='start_offset_blocked',probe_count=1,accepted_samples={}}
 else plan=Path.plan({center=center,capsule_radius=radius,capsule_half_height=half,
  wall_point=s.wall,wall_normal=s.wall_normal,along_wall=selection.along_wall,ignore=ignored,
  max_distance_cm=cfg.side_max_distance_cm or 800,min_distance_cm=cfg.side_min_distance_cm or 100,
  step_cm=cfg.side_step_cm or 50},trace)
  plan.probe_count=plan.probe_count+1
 end
 plan.original_center=point(q);plan.native_wall_clearance_cm=80
 plan.capsule_radius,plan.capsule_half_height=radius,half
 plan.query_source=source
 log('v18_side_path status='..tostring(plan.status)..' cm='..tostring(plan.usable_distance_cm)
  ..' stop='..tostring(plan.stop_reason)..' queries='..tostring(plan.probe_count)..' source='..source)
 return plan
end
return M
