-- Experimental game-thread adapter for parkour_motion_exit_v10. Never cache
-- UObjects across calls. A ticket must name an actor created by this mod.
-- No hooks or scheduler are installed here. All reads and writes require the
-- caller to be on the game thread. SDK/out-parameter access is unverified.
local M={}
function M.new(H,log,ticket)
 assert(type(ticket)=='table' and type(ticket.player_id)=='string' and type(ticket.world_id)=='string' and type(ticket.owned_volume_id)=='string')
 log=log or function() end
 local pending_end=nil
 local last_ability_error,last_floor_error=nil,nil
 local function valid(o)
  local ok,v=pcall(function() return o and o:IsValid() end);return ok and v==true
 end
 local function object_name(o)
  if o==nil then return nil end
  local ok,isvalid=pcall(function() return o:IsValid() end)
  assert(ok and type(isvalid)=='boolean','object validity unavailable')
  if not isvalid then return nil end
  local n=o:GetFullName();assert(type(n)=='string' and n~='');return n
 end
 local function bool(v)
  if type(v)=='boolean' then return v end
  if v==0 then return false elseif v==1 then return true end
  error('boolean property unavailable')
 end
 local function diagnostic_classes()
  for _,pair in ipairs({{'native','/Script/AdvancedSpecialMove.SpecialMoveAbilityBase'},
    {'asm_candidate','/AdvancedSpecialMove/GA/Base/GA_ASM_Base.GA_ASM_Base_C'}}) do
   local ok,o=pcall(StaticFindObject,pair[2]);local name=ok and valid(o) and object_name(o) or 'not_loaded_or_path_unresolved'
   log('motion_probe_class_'..pair[1]..'='..name)
  end
 end
 pcall(diagnostic_classes)
 local function family(a)
  local c=a:GetClass();local depth=0
  while valid(c) and depth<64 do
   local n=c:GetFName():ToString();assert(type(n)=='string','class name unavailable')
   if n=='SpecialMoveAbilityBase' then return 'native' end
   if n=='GA_ASM_Base_C' then return 'asm' end
   if n=='GameplayAbility' then return 'other' end
   c=c:GetSuperStruct();depth=depth+1
  end
  error('ability superclass chain incomplete')
 end
 local function each(array,fn,label)
  assert(array~=nil,label..' unavailable')
  local expected=array:GetArrayNum()
  assert(type(expected)=='number' and expected>=0 and expected%1==0,label..' size unavailable')
  local count=0
  array:ForEach(function(_,entry)
   count=count+1;local value=entry:get();assert(value~=nil,label..' item unavailable');fn(value)
  end)
  assert(count==expected,label..' enumeration incomplete')
  return count
 end
 local function abilities(p,player_id,find_id)
  local component=p.SpecialMove.AbilitySystemComponent
  assert(valid(component),'player ability system unavailable')
  local container=component.ActivatableAbilities;assert(container~=nil,'ability container unavailable')
  local result,seen,target={}, {},nil
  each(container.Items,function(spec)
   local count=spec.ActiveCount
   assert(type(count)=='number' and count>=0 and count%1==0,'ability ActiveCount unavailable')
   if count==0 then return end
   local definition=spec.Ability;assert(valid(definition),'active spec ability unavailable')
   local kind=family(definition)
   if kind=='other' then return end
   local active_instances=0
   local function inspect(a)
    assert(valid(a),'active spec instance invalid')
    if not bool(a.bIsActive) then return end
    local name=object_name(a);local avatar=object_name(a:GetAvatarActorFromActorInfo())
    assert(avatar==player_id,'active ability avatar mismatch or unavailable')
    if not seen[name] then
     seen[name]=true;active_instances=active_instances+1
     local volume=nil
     if kind=='native' then
      assert(object_name(a.Character)==player_id,'active ability character mismatch')
      volume=object_name(a.CurrentSpecialMoveVolume);assert(volume,'active ability volume unavailable')
     end
     result[#result+1]={id=name,player_id=avatar,volume_id=volume,active=true}
     if name==find_id then target=a end
    end
   end
   each(spec.NonReplicatedInstances,inspect,'nonreplicated instances')
   each(spec.ReplicatedInstances,inspect,'replicated instances')
   assert(active_instances==count,'active special-move count/instance mismatch')
  end,'ability specs')
  return result,target
 end
 local function floor_probe(movement,pos)
  -- CharacterMovement's own floor query uses its collision rules; a visibility
  -- line trace alone cannot rule out pawn-only collision. Unknown output fails
  -- closed. A blocking hit is treated conservatively as a potential floor.
  local out={}
  movement:K2_FindFloor({X=pos.X,Y=pos.Y,Z=pos.Z},out)
  local blocking=bool(out.bBlockingHit)
  if not blocking then return false end
  bool(out.bWalkableFloor) -- verify complete struct, even on a steep hit
  return true
 end
 local function sample()
  local p=H.GetPlayer();local world=H.GetWorld()
  if not valid(p) or not valid(world) then return nil end
  local ok,s=pcall(function()
   local name=object_name(p);local wid=object_name(world)
   local q=p:K2_GetActorLocation();local movement=p.CharacterMovement
   assert(valid(movement),'movement unavailable')
   local sm=p.SpecialMove;assert(valid(sm),'special move component unavailable')
   local volume=object_name(sm.CurrentSpecialMoveVolume)
   local interact=p.PBZInteract;assert(valid(interact),'interaction component unavailable')
   local interaction=object_name(interact.CurrentInteractActor)
   local s={player_id=name,world_id=wid,time=H.GetGameplayStatics():GetRealTimeSeconds(p),z=q.Z,
     mode=movement.MovementMode,volume_id=volume,interaction_id=interaction,interact_clear=interaction==nil}
   local abok,ab=pcall(abilities,p,name);s.abilities_complete=abok
   if abok then s.abilities=ab;last_ability_error=nil else
    s.abilities={};local msg=tostring(ab);if msg~=last_ability_error then log('motion_probe_abilities_unavailable='..msg);last_ability_error=msg end
   end
   local floorok,floor=pcall(floor_probe,movement,q)
   if floorok then s.floor_walkable=floor;last_floor_error=nil else
    local msg=tostring(floor);if msg~=last_floor_error then log('motion_probe_floor_unavailable='..msg);last_floor_error=msg end
   end
   local animok,montage=pcall(function() return object_name(p.Mesh:GetAnimInstance():GetCurrentActiveMontage()) end)
   s.montage_id=animok and (montage or 'none') or 'unavailable'
   -- Socket names verified on the live Hun_Skin_Skeleton. These are ankle/
   -- foot-bone plane distances, not proof that the sole has valid wall IK.
   if ticket.wall and ticket.wall_normal then
    local feetok,feet=pcall(function()
     local n=ticket.wall_normal;local w=ticket.wall
     local length=math.sqrt(n.X*n.X+n.Y*n.Y+n.Z*n.Z);assert(length>.5)
     local result={}
     for _,side in ipairs({'l','r'}) do
      local socket=FName('foot_'..side..'_Socket')
      assert(p.Mesh:DoesSocketExist(socket),'foot socket missing')
      local f=p.Mesh:GetSocketLocation(socket)
      result[side]=((f.X-w.X)*n.X+(f.Y-w.Y)*n.Y+(f.Z-w.Z)*n.Z)/length
     end
     return result
    end)
    if feetok then s.foot_plane_distance=feet end
   end
   return s
  end)
  if not ok then log('motion_probe_sample_unavailable='..tostring(s));return nil end
  return s
 end
 local function is_ticket(p,w,v) return p==ticket.player_id and w==ticket.world_id and v==ticket.owned_volume_id end
 local function end_special_move(id,p,w,v)
  if not is_ticket(p,w,v) or pending_end then return false end
  local s=sample()
  if not s or s.player_id~=p or s.world_id~=w or s.volume_id~=v or not s.abilities_complete
   or (s.interaction_id~=nil and s.interaction_id~=v) then return false end
  local found=0
  for _,a in ipairs(s.abilities) do
   if a.active and a.player_id==p then
    if a.id~=id or a.volume_id~=v then return false end
    found=found+1
   end
  end
  if found~=1 then return false end
  local ok,result=pcall(function()
   local player=H.GetPlayer();local _,a=abilities(player,p,id);assert(valid(a));assert(bool(a.bIsActive))
   assert(object_name(a.Character)==p and object_name(a:GetAvatarActorFromActorInfo())==p and object_name(a.CurrentSpecialMoveVolume)==v)
   -- Record attempt before invocation so an exception cannot repeat the call.
   pending_end=id;a:EndSpecialMove();return true
  end)
  if not ok then log('motion_probe_end_failed='..tostring(result));return false end
  return result==true
 end
 local function set_falling(p,w,v,id)
  if not is_ticket(p,w,v) or pending_end~=id then return false end
  local s=sample()
  if not s or s.player_id~=p or s.world_id~=w or s.volume_id~=nil or s.mode~=5
   or not s.abilities_complete or not s.interact_clear or s.floor_walkable~=false then return false end
  for _,a in ipairs(s.abilities) do if a.active and a.player_id==p then return false end end
  local ok,err=pcall(function()
   local player=H.GetPlayer();local world=H.GetWorld()
   assert(object_name(player)==p and object_name(world)==w)
   player.CharacterMovement:SetMovementMode(3,0)
  end)
  pending_end=nil
  if not ok then log('motion_probe_falling_failed='..tostring(err));return false end
  return true
 end
 return {sample=sample,end_special_move=end_special_move,set_falling=set_falling,log=log}
end
return M
