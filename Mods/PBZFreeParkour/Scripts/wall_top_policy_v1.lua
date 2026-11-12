-- Select the measured top using the player's current walkable slope.
-- Input is a collision-profile query result, not visual/render geometry.
local M={}
local function finite(v)return type(v)=='number' and v==v and math.abs(v)<math.huge end
function M.select(hit,base_z,walkable_z)
 if not finite(base_z) or not finite(walkable_z) or walkable_z<=0 or walkable_z>1 then
  return nil,'invalid_limits'
 end
 if type(hit)~='table' or hit.hit~=true or hit.blocking~=true then return nil,'unmeasured_top' end
 local point,normal=hit.point,hit.normal
 if type(point)~='table' or type(normal)~='table' or not finite(point.Z) or not finite(normal.Z) then
  return nil,'invalid_geometry'
 end
 if normal.Z<walkable_z then return nil,'steep_surface' end
 local height=point.Z-base_z
 if height<100 or height>800 then return nil,'out_of_range' end
 return height,'measured_top'
end
-- Prefer the native 150 cm depth, then choose a supported nearby destination.
-- The caller must move the owned endpoint to the returned depth before dispatch.
-- Adjacent samples are evidence of local support, not a full surface mesh.
function M.select_samples(samples,base_z,walkable_z)
 if type(samples)~='table' then return nil,'missing_samples' end
 if not finite(walkable_z) or walkable_z<=0 or walkable_z>1 then return nil,'invalid_limits' end
 local max_gradient=math.sqrt(1-walkable_z*walkable_z)/walkable_z
 for _,depth in ipairs({150,120,180,90,210,60}) do
  for _,target in ipairs(samples) do
   if target.depth==depth then
    local height=M.select(target.hit,base_z,walkable_z)
    if height then
     for _,s in ipairs(samples) do
      if finite(s.depth) then
       local delta=math.abs(s.depth-depth)
       local other=M.select(s.hit,base_z,walkable_z)
       if delta>0 and delta<=30.001 and other and math.abs(other-height)<=delta*max_gradient+5 then
        return height,'measured_endpoint_supported',depth
       end
      end
     end
    end
   end
  end
 end
 return nil,'no_supported_endpoint'
end
-- Unknown tops use a synthetic native endpoint only to start climbing. Stop
-- before its native end-motion window, rather than after CloudStep_End starts.
-- The 300 cm guard is conservative relative to the observed ~165 cm transition;
-- bounded lookahead accounts for fast root-motion ascent between host samples.
function M.unknown_finish_guard(z,top_z,velocity_z,previous_z,previous_time,time)
 if not finite(z) or not finite(top_z) or not finite(time) then return true,'invalid_guard_sample',nil end
 local speed=finite(velocity_z) and math.max(0,velocity_z) or 0
 if finite(previous_z) and finite(previous_time) and time>previous_time then
  local dt=time-previous_time
  if dt<=.5 then speed=math.max(speed,(z-previous_z)/dt) end
 end
 local margin=300+math.min(180,speed*.15)
 return z>=top_z-margin,'unverified_pre_finish_margin',margin
end
return M
