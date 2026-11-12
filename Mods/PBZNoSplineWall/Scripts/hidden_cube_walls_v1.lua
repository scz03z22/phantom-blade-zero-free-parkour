-- Additional narrow F9 target. No component references survive a completed pass.
local M={}
local function valid(o)local ok,v=pcall(function()return o and o:IsValid()end);return ok and v==true end
local function address(o)local ok,v=pcall(function()return o:GetAddress()end);return ok and tostring(v) or nil end
function M.matches(actor,component,previously_verified)
 if not valid(actor) or not valid(component) then return false end
 if actor.bHidden~=true and component.bHiddenInGame~=true then return false end
 local profile=component:GetCollisionProfileName():ToString()
 if profile~='Profile_LA_InvisibleWall' and not (previously_verified and profile=='Custom') then return false end
 local mesh=component.StaticMesh
 return valid(mesh) and mesh:GetFullName()=='StaticMesh /Engine/BasicShapes/Cube.Cube'
end
function M.new(log)
 local journal,verified,queue,index,mode,stats,seen={},{},nil,1,nil,nil,nil
 local function begin(next_mode)
  queue=FindAllOf('StaticMeshActor') or {};index=1;mode=next_mode;seen={}
  stats={matched=0,modified=0,restored=0,conflicts=0,errors=0,unloaded=0}
 end
 local function process(actor)
  if not valid(actor) then return end
  if not actor:GetFullName():find(':PersistentLevel.',1,true) then return end
  local c=actor.StaticMeshComponent;if not valid(c)then return end
  local name=c:GetFullName();local record=journal[name]
  local addr=address(c)
  local known=verified[name]
  if known and known~=addr then verified[name]=nil;known=nil end
  if record or known then seen[name]=true end
  if mode=='restore' then
   if not record then return end
   if record.address and addr~=record.address then journal[name]=nil;stats.unloaded=stats.unloaded+1;return end
   local current=c:GetCollisionResponseToChannel(2)
   if current==0 then
    c:SetCollisionResponseToChannel(2,record.original)
    assert(c:GetCollisionResponseToChannel(2)==record.original,'cube restore readback mismatch')
    stats.restored=stats.restored+1
   elseif current~=record.original then stats.conflicts=stats.conflicts+1 end
   journal[name]=nil
   return
  end
  if not M.matches(actor,c,known~=nil) then return end
  -- SetCollisionResponseToChannel changes the profile to Custom in this game.
  -- Retain verified identity across F9 off/on, but never accept arbitrary Custom cubes.
  if addr then verified[name]=addr end
  seen[name]=true
  stats.matched=stats.matched+1
  local current=c:GetCollisionResponseToChannel(2)
  if record and record.address and addr~=record.address then journal[name]=nil;record=nil end
  if current~=2 then return end
  if not record then journal[name]={original=current,address=addr}end
  seen[name]=true
  c:SetCollisionResponseToChannel(2,0)
  assert(c:GetCollisionResponseToChannel(2)==0,'cube disable readback mismatch')
  stats.modified=stats.modified+1
  if stats.modified<=3 then log('cube_ignored '..name)end
 end
 local function step()
  if not queue then return end
  -- Bound expensive property reads/writes; no engine calls from timer threads.
  local started=os.clock()
  for n=1,64 do
   -- Yield between actors after 3 ms; always process at least one.
   -- A single native call cannot be preempted. The journal stays intact.
   if n>1 and os.clock()-started>=.003 then return end
   local actor=queue[index]
   if not actor then
    for name in pairs(journal)do if not seen[name] and stats.errors==0 then journal[name]=nil;stats.unloaded=stats.unloaded+1 end end
    if stats.errors==0 then for name in pairs(verified)do if not seen[name] then verified[name]=nil end end end
    local finished=mode
    queue=nil;mode=nil
    if finished=='restore' or stats.modified>0 or stats.errors>0 then
     log(string.format('cube_%s_complete matched=%d modified=%d restored=%d conflicts=%d errors=%d unloaded=%d',finished,stats.matched,stats.modified,stats.restored,stats.conflicts,stats.errors,stats.unloaded))
    end
    return
   end
   index=index+1
   local ok,err=pcall(process,actor)
   if not ok then stats.errors=stats.errors+1;if stats.errors<=3 then log('cube_'..mode..'_error '..tostring(err))end end
  end
 end
 return {
  scan=function()if not queue then begin('scan')end end,
  restore=function()begin('restore')end,
  step=step,
  restore_result=function()
   if queue or not stats then return nil end
   local remaining=0;for _ in pairs(journal) do remaining=remaining+1 end
   return {errors=stats.errors,conflicts=stats.conflicts,remaining=remaining}
  end,
  pending=function()return queue~=nil end,
  restoring=function()return mode=='restore'end,
 }
end
return M
