-- Pure classification of measured near-foot support. No engine access or movement.
-- nil/unknown is not a miss; errors must be handled by the caller, never treated
-- as an uninterrupted wall or as proof of an edge.
local function finite(v) return type(v)=='number' and v==v and math.abs(v)<math.huge end
return function(samples,now,previous,grace)
 assert(type(samples)=='table' and #samples>=1 and #samples<=8,'invalid support samples')
 assert(finite(now) and finite(grace) and grace>=0 and grace<=1,'invalid support timing')
 if previous~=nil then assert(finite(previous) and previous<=now,'invalid previous miss time') end
 for i=1,#samples do
  local x=samples[i]
  assert(type(x)=='boolean','unknown support result')
  if x then return {status='supported',lost_since=nil} end
 end
 local since=previous or now
 if now-since<grace then return {status='grace',lost_since=since} end
 return {status='lost',lost_since=since}
end
