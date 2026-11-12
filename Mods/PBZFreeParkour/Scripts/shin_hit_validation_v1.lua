-- Validate a positive-distance wall hit without trusting a conflicting
-- bStartPenetrating bit. 'support' requires separately verified blocking.
local M={}
local function f(x) return type(x)=='number' and x==x and math.abs(x)<math.huge end
local function vec(v) return type(v)=='table' and f(v.X) and f(v.Y) and f(v.Z) end
function M.classify(s)
 if type(s)~='table' or not vec(s.origin) or not vec(s.dest) then return 'unknown' end
 if s.found==false then return 'clear' end
 if s.found~=true or not f(s.time) or s.time<=.01 or s.time>1 or not vec(s.point)
   or not vec(s.normal) or not vec(s.wall_normal) then return 'unknown' end
 local dx,dy,dz=s.dest.X-s.origin.X,s.dest.Y-s.origin.Y,s.dest.Z-s.origin.Z
 local ex,ey,ez=s.origin.X+dx*s.time,s.origin.Y+dy*s.time,s.origin.Z+dz*s.time
 local err=(s.point.X-ex)^2+(s.point.Y-ey)^2+(s.point.Z-ez)^2
 local dot=s.normal.X*s.wall_normal.X+s.normal.Y*s.wall_normal.Y
 if err>25 or dot<.5 or math.abs(s.normal.Z)>.72 then return 'unknown' end
 if s.blocks~=true then return 'unknown' end
 return 'support'
end
return M
