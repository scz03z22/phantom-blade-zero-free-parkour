-- Automatic, session-only collision changes. No restore journal or audit loop.
-- Queue identities contain strings only; EndPlay cancels work before unload.
local M={}
local GE='BlueprintGeneratedClass /Game/PBZContent/Blueprint/Ability/GameplayEffects/GE_Kill.GE_Kill_C'
local function valid(o)local ok,v=pcall(function()return o and o:IsValid()end);return ok and v==true end
local function path(o)return o:GetFullName():match('^%S+ (.+)$')end
local function address(o)return tostring(o:GetAddress())end
function M.new(log,matcher)
 local q,head,tail={},1,0
 local pending,delayed,known={},{},{}
 local tick,waiting,errors,writes,events=0,0,0,0,0
 local active=false
 local function push(x,delay)
  if delay then local t=tick+delay;delayed[t]=delayed[t]or{};table.insert(delayed[t],x);waiting=waiting+1
  else tail=tail+1;q[tail]=x end
 end
 local function enqueue(a,kind,settle)
  local p=path(a);if not p or not p:find(':PersistentLevel.',1,true)then return end
  local ad=address(a);local prev=pending[p]
  if prev and prev.address==ad then return end
  if prev then prev.cancelled=true end
  local x={path=p,address=ad,kind=kind,until_tick=tick+35}
  pending[p]=x;push(x,settle and 5 or nil)
 end
 local function process(x)
  if x.cancelled then return 'gone' end
  local a=StaticFindObject(x.path)
  if not valid(a)or address(a)~=x.address then return 'gone' end
  local c
  if x.kind=='kill' then
   local effect=a.GEClass
   if not valid(effect)then return end
   if effect:GetFullName()~=GE then return 'reject' end
   c=a.BrushComponent
  elseif x.kind=='cube' then c=a.StaticMeshComponent
  else c=a.DynamicMeshComponent end
  if not valid(c)then return end
  local ca=address(c)
  if x.kind=='cube' then
   local mesh=c.StaticMesh
   if not valid(mesh)then return end
   if mesh:GetFullName()~='StaticMesh /Engine/BasicShapes/Cube.Cube'then return 'reject' end
   local k=known[x.path]
   if not matcher(a,c,k and k.actor==x.address and k.component==ca)then return end
  end
  local response=c:GetCollisionResponseToChannel(2)
  if response~=0 and response~=1 and response~=2 then error('invalid response')end
  -- Walls affect only Block. Confirmed GE_Kill brushes also use Overlap.
  if response==2 or (x.kind=='kill' and response==1)then
   if x.kind=='cube'then known[x.path]={actor=x.address,component=ca}end
   c:SetCollisionResponseToChannel(2,0)
   assert(c:GetCollisionResponseToChannel(2)==0,'collision readback failed')
   writes=writes+1
   if x.kind=='kill'then log('kill_ignored '..x.path)end
  end
  return 'verified'
 end
 local function step()
  tick=tick+1
  local due=delayed[tick];delayed[tick]=nil
  if due then for _,x in ipairs(due)do waiting=waiting-1;push(x)end end
  if head>tail then return end
  local started=os.clock()
  for i=1,32 do
   if head>tail or(i>1 and os.clock()-started>=.002)then break end
   local x=q[head];q[head]=nil;head=head+1
   local ok,result=pcall(process,x)
   if not ok then errors=errors+1;if errors<=8 then log('work_error '..tostring(result))end end
   if not x.cancelled and result~='gone'and result~='reject'and tick<x.until_tick then push(x,10)
   elseif pending[x.path]==x then pending[x.path]=nil end
  end
  if head>tail then
   q={};head=1;tail=0
   if waiting==0 then log(string.format('queue_idle writes=%d events=%d errors=%d',writes,events,errors))end
  end
 end
 local function begin()
  if active then return true end
  -- Initial enumeration only. Later maps arrive through BeginPlay.
  local snapshot={}
  for _,s in ipairs({{'BP_SplineWall_C','spline'},{'StaticMeshActor','cube'},{'PBZGEVolume','kill'}})do
   for _,a in ipairs(FindAllOf(s[1])or{})do if valid(a)then snapshot[#snapshot+1]={a,s[2]}end end
  end
  for _,s in ipairs(snapshot)do enqueue(s[1],s[2],false)end
  active=true;log('auto_enabled snapshot='..#snapshot..'; no_restore; no_periodic_enumeration');return true
 end
 local function notify(param)
  if not active then return end
  local a=param:get();if not valid(a)then return end
  local cl=a:GetClass():GetFName():ToString()
  local kind=cl=='BP_SplineWall_C'and'spline'or cl=='StaticMeshActor'and'cube'or cl=='PBZGEVolume'and'kill'
  if kind then events=events+1;enqueue(a,kind,true)end
 end
 local function endplay(param)
  if not active then return end
  local a=param:get();if not valid(a)then return end
  local cl=a:GetClass():GetFName():ToString()
  if cl~='BP_SplineWall_C'and cl~='StaticMeshActor'and cl~='PBZGEVolume'then return end
  local p=path(a);local ad=address(a);local x=pending[p]
  if x and x.address==ad then x.cancelled=true;pending[p]=nil end
  if known[p]and known[p].actor==ad then known[p]=nil end
 end
 return {begin=begin,step=step,notify=notify,endplay=endplay,
  stats=function()return{writes=writes,events=events,errors=errors,pending=tail-head+1+waiting}end}
end
return M
