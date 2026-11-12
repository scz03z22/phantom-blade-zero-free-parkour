-- Native construction mapping observed 2026-11-08 07:48:18Z on this game build.
-- Concrete BP_ASM_SideRunning: 15 and 8 WallLength values independently measured.
-- Length endpoints are -L*100; start offset=200cm, standoff=80cm, local Z=250cm.
-- DirectionA/B +X faces wall; MoveDirectionA=-Y, B=+Y along wall.
-- This proves constructed geometry only. Native dispatch/animation still needs
-- its own exact-instance observation; a mapping does not claim gameplay success.
local M={}
local CLASS='/Game/RenewalContent/Actors/SpecialMove/BP_ASM_SideRunning.BP_ASM_SideRunning_C'
local BASE='/AdvancedSpecialMove/BP/Actor/SpecialMoveVolume/BP_ASM_SideRunning_Base.BP_ASM_SideRunning_Base_C'
local preload_attempted={}
local color={R=0,G=0,B=0,A=0}
local function finite(x) return type(x)=='number' and x==x and math.abs(x)<math.huge end
local function vec(v) return type(v)=='table' and finite(v.X) and finite(v.Y) and finite(v.Z) end
local function valid(o) local ok,v=pcall(function() return o and o:IsValid() end);return ok and v==true end
local function name(o) assert(valid(o),'object unavailable');local n=o:GetFullName();assert(type(n)=='string' and n~='','name unavailable');return n end
local function world_of(o)
 for _=1,32 do local n=name(o);if n:sub(1,6)=='World ' then return n end;o=o:GetOuter() end
 error('object World outer unavailable')
end
local function identity(H,pid,wid)
 local p,w=H.GetPlayer(),H.GetWorld()
 assert(name(p)==pid and name(w)==wid and world_of(p)==wid,'side spec identity changed')
 return p,w
end
local function concrete_class()
 local cl=StaticFindObject(CLASS)
 assert(valid(cl) and name(cl)=='BlueprintGeneratedClass '..CLASS,'observed concrete side class not loaded')
 local base=cl:GetSuperStruct()
 for _=1,24 do
  if not valid(base) then break end
  if name(base)=='BlueprintGeneratedClass '..BASE then return cl end
  base=base:GetSuperStruct()
 end
 error('concrete side class Base inheritance mismatch')
end
-- F8 initialization only, on the game thread. No spawn or player/ASC write.
-- make() deliberately never loads an asset during the input/action path.
function M.preload(H)
 local ok,result=pcall(function()
  local p,w=H.GetPlayer(),H.GetWorld();local pid,wid=name(p),name(w);identity(H,pid,wid)
  local cl=StaticFindObject(CLASS);local loaded_now=false
  if not valid(cl) then
   assert(not preload_attempted[wid],'side class load already attempted for this World')
   preload_attempted[wid]=true;LoadAsset(CLASS);loaded_now=true
  end
  cl=concrete_class();identity(H,pid,wid)
  return {class_path=CLASS,class_full_name=name(cl),player_id=pid,world_id=wid,loaded_now=loaded_now}
 end)
 if not ok then return false,tostring(result) end
 return true,result
end
function M.make(H,s,selection,plan,ignored)
 local ok,result=pcall(function()
  assert(plan.status=='ready' and vec(plan.start) and vec(plan.finish),'verified side path required')
  assert(finite(plan.usable_distance_cm) and plan.usable_distance_cm>=100 and plan.usable_distance_cm<=800,'invalid side distance')
  assert(type(ignored)=='table','side ignores missing')
  assert(type(s.player_id)=='string' and s.player_id~='' and type(s.world_id)=='string' and s.world_id~='','side sample identity missing')
  local p,w=identity(H,s.player_id,s.world_id)
  concrete_class()
  local n,t=selection.wall_normal_xy,selection.along_wall
  assert(vec(n) and vec(t) and math.abs(n.Z)<.0001 and math.abs(t.Z)<.0001,'side basis missing')
  assert(math.abs(n.X*n.X+n.Y*n.Y-1)<.00001 and math.abs(t.X*t.X+t.Y*t.Y-1)<.00001,'side basis must be unit length')
  assert(math.abs(n.X*t.X+n.Y*t.Y)<.00001,'side basis must be orthogonal')
  local x={X=-n.X,Y=-n.Y,Z=0};local y={X=-x.Y,Y=x.X,Z=0}
  local side=selection.route=='side_right' and 'A' or selection.route=='side_left' and 'B' or nil
  assert(side,'side route required')
  local sign=side=='A' and -1 or 1
  assert(t.X*y.X*sign+t.Y*y.Y*sign>.999,'router/native tangent differs')
  local d=plan.usable_distance_cm;local length_cm=d+200
  -- Geometry planner has verified the native 80cm standoff path. Keep the
  -- native start at that position without forcing any player transform.
  local start=plan.start
  assert(vec(s.wall),'real wall point missing')
  local standoff=(start.X-s.wall.X)*n.X+(start.Y-s.wall.Y)*n.Y
  assert(finite(standoff) and math.abs(standoff-80)<=.1,'side path does not preserve measured 80cm native standoff')
  local planned_finish={X=start.X+t.X*d,Y=start.Y+t.Y*d,Z=start.Z}
  assert(vec(planned_finish) and math.abs(plan.finish.X-planned_finish.X)<=.1 and math.abs(plan.finish.Y-planned_finish.Y)<=.1
   and math.abs(plan.finish.Z-planned_finish.Z)<=.1,'side plan finish differs from verified tangent/distance')
  local wall_start={X=start.X-n.X*80,Y=start.Y-n.Y*80,Z=start.Z}
  local offset=side=='A' and -200 or d
  local origin={X=wall_start.X+t.X*offset,Y=wall_start.Y+t.Y*offset,Z=start.Z-250}
  assert(vec(origin),'nonfinite side origin')
  local function world(lx,ly,lz)
   local v={X=origin.X+x.X*lx+y.X*ly,Y=origin.Y+x.Y*lx+y.Y*ly,Z=origin.Z+lz}
   assert(vec(v),'nonfinite constructed endpoint');return v
  end
  local function forward(sign) return {X=y.X*sign,Y=y.Y*sign,Z=0} end
  local expected={
   A={start_world=world(-80,-200,250),end_world=world(0,-length_cm,250),move_forward=forward(-1),direction_forward=x},
   B={start_world=world(-80,-length_cm+200,250),end_world=world(0,0,250),move_forward=forward(1),direction_forward=x}}
  local chosen=expected[side].start_world
  assert((chosen.X-start.X)^2+(chosen.Y-start.Y)^2+(chosen.Z-start.Z)^2<.01,'side start alignment failed')
  local spawn={X=origin.X,Y=origin.Y,Z=origin.Z+50000};local dest={X=spawn.X,Y=spawn.Y,Z=spawn.Z+1}
  assert(vec(spawn) and vec(dest) and math.abs((spawn.Z-origin.Z)-50000)<.1,'isolated spawn coordinate precision unavailable')
  local sys=H.GetKismetSystemLibrary();assert(valid(sys),'side query library unavailable')
  local hit={};local blocked=sys:CapsuleTraceSingle(p,spawn,dest,3000,3500,0,false,ignored,0,hit,true,color,color,0)
  assert(blocked==false or blocked==0,'side isolated spawn not clear')
  if hit.bBlockingHit~=nil then assert(hit.bBlockingHit==false or hit.bBlockingHit==0,'side isolated query hit disagrees') end
  identity(H,s.player_id,s.world_id)
  return {confirmed_wall=true,spawn_nonoverlap_verified=true,side=side,world_position=origin,
   rotation={Pitch=0,Yaw=math.deg(math.atan(x.Y,x.X)),Roll=0},
   geometry={mapping_verified=true,player_id=s.player_id,world_id=s.world_id,
    probe_id='side_geometry_v18_20261108_164818',class_path=CLASS,
    class_full_name='BlueprintGeneratedClass '..CLASS,class_name='BP_ASM_SideRunning_C',
    selection_mode='native_set_cur_side_then_interact',tangent_verified=true,tangent_source='move_forward',
    parameters={WallLength=length_cm/100,CanWalkWallHeight=4,TrigerWidth=6,TrigerLength=8,TrigerHeight=2,CanInteractDistance=1000},
    expected=expected}}
 end)
 if not ok then return false,tostring(result) end
 return true,result
end
return M
