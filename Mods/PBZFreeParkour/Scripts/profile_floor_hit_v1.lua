-- Candidate validation for an unresolved hit from a collision-profile trace.
-- This proves query geometry only; it cannot name the hit object.
local M={}
local function f(x)return type(x)=='number' and x==x and math.abs(x)<math.huge end
local function vec(v)return type(v)=='table' and f(v.X) and f(v.Y) and f(v.Z)end
function M.reason(s)
 if type(s)~='table' or s.profile_query~=true or s.hit~=true or not vec(s.a) or not vec(s.b)
  or not f(s.time) or not vec(s.point) or not vec(s.normal) then return 'unreadable' end
 if s.time<=.01 or s.time>1 then return 'time_out_of_range' end
 local limit=s.min_normal_z or .72
 if not f(limit) or limit<=0 or limit>1 then return 'invalid_walkable_threshold' end
 if s.normal.Z<limit then return 'not_walkable_normal' end
 local x=s.a.X+(s.b.X-s.a.X)*s.time
 local y=s.a.Y+(s.b.Y-s.a.Y)*s.time
 local z=s.a.Z+(s.b.Z-s.a.Z)*s.time
 if (s.point.X-x)^2+(s.point.Y-y)^2+(s.point.Z-z)^2>25 then return 'point_time_mismatch' end
 return 'ok'
end
function M.check(s)return M.reason(s)=='ok'end
return M
