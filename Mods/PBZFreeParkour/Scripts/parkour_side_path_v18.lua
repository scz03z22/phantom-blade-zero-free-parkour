-- Pure straight-wall path candidate. No engine API, collision mutation, or action.
--
-- Path.plan(spec, trace) returns status=ready|too_short|invalid|error, start, finish,
-- usable_distance_cm, stop_reason, probe_count, and accepted_samples. Only 'ready'
-- is a candidate path. Even a ready path requires live revalidation while running.
-- Geometry sampling does not prove an unsampled thin hole cannot exist.
--
-- Required spec: center, capsule_radius, capsule_half_height, wall_point,
-- wall_normal, along_wall. Vectors are finite {X,Y,Z} value tables.
-- Optional limits (cm/degrees): step_cm=50 (<=50), max_distance_cm=800 (<=800),
-- min_distance_cm=100 (>=100), max_normal_change_deg=20 (<=20),
-- max_plane_deviation_cm=20, max_abs_normal_z=.5. These are research limits.
--
-- trace('wall', q) -> {ok=true,hit=true,blocking=true,point={...},normal={...}}
--                 or {ok=true,hit=false}. The caller must validate solid/Pawn
--                 wall semantics; this module does not infer them from class names.
-- trace('capsule', q) -> {ok=true,blocked=false|true}.
-- An exception, ok~=true, or malformed result is ERROR, never a missing wall.
-- q: from, to, center=to, expected_wall_point, wall_normal, direction,
-- capsule_radius, capsule_half_height, distance_cm, step_distance_cm, ignore.
-- 'wall' at distance 0 rechecks the initial contact; all subsequent positions
-- check wall support then a capsule sweep from the last accepted position.
-- ignore is passed through by identity; the caller supplies all filtering.
-- Queries are value copies except ignore. Do not cache engine objects in this file.
local M={}
local EPS=1e-7
local DEFAULTS={step_cm=50,max_distance_cm=800,min_distance_cm=100,
 max_normal_change_deg=20,max_plane_deviation_cm=20,max_abs_normal_z=.5}

local function finite(n)
 return type(n)=='number' and n==n and n>-math.huge and n<math.huge
end
local function vector(v)
 if type(v)~='table' or not finite(v.X) or not finite(v.Y) or not finite(v.Z) then return nil end
 return {X=v.X,Y=v.Y,Z=v.Z}
end
local function copy(v)
 if type(v)~='table' then return v end
 local r={};for k,x in pairs(v) do r[k]=copy(x) end;return r
end
local function dot(a,b) return a.X*b.X+a.Y*b.Y+a.Z*b.Z end
local function sub(a,b) return {X=a.X-b.X,Y=a.Y-b.Y,Z=a.Z-b.Z} end
local function add_scaled(a,b,d)
 return vector({X=a.X+b.X*d,Y=a.Y+b.Y*d,Z=a.Z+b.Z*d})
end
local function unit(v)
 local m=math.max(math.abs(v.X),math.abs(v.Y),math.abs(v.Z))
 if m<EPS then return nil end
 local x,y,z=v.X/m,v.Y/m,v.Z/m;local q=math.sqrt(x*x+y*y+z*z)
 return {X=x/q,Y=y/q,Z=z/q}
end
local function angle(a,b) return math.acos(math.max(-1,math.min(1,dot(a,b))))*180/math.pi end
local function invalid(reason)
 return {status='invalid',stop_reason=reason,usable_distance_cm=0,probe_count=0,accepted_samples={}}
end

function M.plan(spec,trace)
 if type(spec)~='table' then return invalid('invalid_spec') end
 if type(trace)~='function' then return invalid('trace_callback_required') end
 local center,wall_point,normal,direction=vector(spec.center),vector(spec.wall_point),
  vector(spec.wall_normal),vector(spec.along_wall)
 if not center or not wall_point or not normal or not direction then return invalid('invalid_geometry') end
 normal=unit(normal);direction=unit(direction)
 if not normal or not direction then return invalid('zero_normal_or_direction') end
 local radius,half=spec.capsule_radius,spec.capsule_half_height
 if not finite(radius) or not finite(half) or radius<=0 or half<radius then return invalid('invalid_capsule') end
 local cfg={}
 for k,v in pairs(DEFAULTS) do
  local n=spec[k];if n==nil then n=v end
  if not finite(n) then return invalid('invalid_limit_'..k) end
  cfg[k]=n
 end
 if cfg.step_cm<1 or cfg.step_cm>50 then return invalid('step_out_of_range') end
 if cfg.min_distance_cm<100 or cfg.max_distance_cm<cfg.min_distance_cm or cfg.max_distance_cm>800 then
  return invalid('distance_limits_out_of_range')
 end
 if cfg.max_normal_change_deg<0 or cfg.max_normal_change_deg>20 then return invalid('normal_limit_out_of_range') end
 if cfg.max_plane_deviation_cm<0 or cfg.max_plane_deviation_cm>50 then return invalid('plane_limit_out_of_range') end
 if cfg.max_abs_normal_z<0 or cfg.max_abs_normal_z>=1 then return invalid('normal_z_limit_out_of_range') end
 if math.abs(normal.Z)>cfg.max_abs_normal_z then return invalid('initial_normal_not_wall_like') end
 if math.abs(direction.Z)>EPS then return invalid('direction_not_horizontal') end
 -- Do not silently reproject a stale/wrong router direction onto a different wall.
 if math.abs(dot(direction,normal))>EPS then return invalid('direction_not_tangent') end
 direction.Z=0
 local out={status='too_short',start=copy(center),finish=copy(center),direction=copy(direction),
  wall_normal=copy(normal),usable_distance_cm=0,stop_reason='unplanned',probe_count=0,
  accepted_samples={},limits=copy(cfg)}
 local prior_normal=normal
 local function stop(reason,is_error,detail)
  out.stop_reason=reason;out.error=detail
  if is_error then out.status='error'
  elseif out.usable_distance_cm+EPS>=cfg.min_distance_cm then out.status='ready'
  else out.status='too_short' end
  return out
 end
 local function query(kind,from,to,d,step)
  local expected=add_scaled(wall_point,direction,d)
  if not expected then return nil,'nonfinite_expected_wall_point' end
  local q={from=copy(from),to=copy(to),center=copy(to),expected_wall_point=expected,
   wall_normal=copy(normal),direction=copy(direction),capsule_radius=radius,capsule_half_height=half,
   distance_cm=d,step_distance_cm=step,ignore=spec.ignore}
  out.probe_count=out.probe_count+1
  local ok,r=pcall(trace,kind,q)
  if not ok then return nil,kind..'_query_exception: '..tostring(r) end
  if type(r)~='table' or r.ok~=true then
   return nil,kind..'_query_unavailable: '..tostring(type(r)=='table' and r.error or r)
  end
  return r
 end
 local function check_wall(from,to,d,step)
  local r,err=query('wall',from,to,d,step)
  if not r then return nil,'wall_query_failed',err end
  if r.hit==false then return false,d==0 and 'initial_wall_missing' or 'wall_lost' end
  if r.hit~=true or type(r.blocking)~='boolean' then return nil,'malformed_wall_query' end
  if r.blocking~=true then return false,'wall_not_blocking' end
  local p,n=vector(r.point),vector(r.normal)
  if not p or not n then return nil,'malformed_wall_geometry' end
  n=unit(n);if not n then return nil,'zero_hit_normal' end
  if math.abs(n.Z)>cfg.max_abs_normal_z then return false,'normal_not_wall_like' end
  if angle(n,normal)>cfg.max_normal_change_deg+EPS or angle(n,prior_normal)>cfg.max_normal_change_deg+EPS then
   return false,'wall_normal_changed'
  end
  local offset=sub(p,wall_point)
  if not vector(offset) then return nil,'nonfinite_wall_offset' end
  local plane_distance=math.abs(dot(offset,normal))
  if not finite(plane_distance) then return nil,'nonfinite_wall_offset' end
  if plane_distance>cfg.max_plane_deviation_cm+EPS then return false,'wall_plane_shifted' end
  return {point=p,normal=n,plane_deviation_cm=plane_distance}
 end
 local first,why,detail=check_wall(center,center,0,0)
 if not first then return stop(why,first==nil,detail) end
 prior_normal=first.normal
 out.accepted_samples[1]={distance_cm=0,center=copy(center),wall_point=copy(first.point),normal=copy(first.normal)}
 local distance=0
 while distance<cfg.max_distance_cm-EPS do
  local next_distance=math.min(distance+cfg.step_cm,cfg.max_distance_cm)
  local step=next_distance-distance
  local target=add_scaled(center,direction,next_distance)
  if not target then return stop('nonfinite_path_endpoint',true) end
  local actual_step=dot(sub(target,out.finish),direction)
  if not finite(actual_step) or math.abs(actual_step-step)>.001 then
   return stop('path_coordinate_precision_lost',true)
  end
  local hit,reason,err=check_wall(out.finish,target,next_distance,step)
  if not hit then return stop(reason,hit==nil,err) end
  local sweep,sweep_error=query('capsule',out.finish,target,next_distance,step)
  if not sweep then return stop('capsule_query_failed',true,sweep_error) end
  if type(sweep.blocked)~='boolean' then return stop('malformed_capsule_query',true) end
  if sweep.blocked then return stop('capsule_blocked',false) end
  distance=next_distance;out.usable_distance_cm=distance;out.finish=copy(target);prior_normal=hit.normal
  out.accepted_samples[#out.accepted_samples+1]={distance_cm=distance,center=copy(target),
   wall_point=copy(hit.point),normal=copy(hit.normal)}
 end
 return stop('max_distance_reached',false)
end

return M
