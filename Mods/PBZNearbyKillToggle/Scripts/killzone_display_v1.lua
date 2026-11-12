-- F6 display only. All engine work runs in this module's persistent game-thread loop.
local M={}
local function valid(o)local ok,v=pcall(function()return o and o:IsValid()end);return ok and v==true end
local function addr(o)return string.format('%.0f',o:GetAddress())end
function M.new(H,log,collect,render)
 local enabled=false
 local requests=0
 local ticks=0
 local owned={}
 local signature=nil
 local last_status=nil
 local function note(s)if s~=last_status then log(s);last_status=s end end
 local function resolve(r)
  local path=assert(r.actor_id:match('^Actor (.+)$'),'not owned display Actor')
  local actor=StaticFindObject(path)
  if not valid(actor)then return nil end
  assert(actor:GetFullName()==r.actor_id and addr(actor)==r.actor_address,'display identity replaced')
  assert(actor:GetLevel().OwningWorld:GetFullName()==r.world_id,'display World mismatch')
  return actor
 end
 local function clear()
  local pending={}
  for _,r in ipairs(owned)do
   local ok,err=pcall(function()
    local a=resolve(r)
    if a then a:SetActorHiddenInGame(true);a:K2_DestroyActor() end
   end)
   if not ok then pending[#pending+1]=r;note('display_cleanup_pending='..tostring(err)) end
  end
  owned=pending;signature=nil
  return #owned==0
 end
 local function refresh()
  local p=H.GetPlayer();if not valid(p)then clear();return end
  local report=collect(H,function()end)
  if not report.scan_finished then clear();note('display_scan_unavailable');return end
  local groups={active={},ignored={}}
  local colors={active={R=1,G=.025,B=.025,A=1},ignored={R=.025,G=1,B=.25,A=1}}
  local parts={report.world_id or '',tostring(report.truncated)}
  local count,skipped,edges=0,0,0
  for _,r in ipairs(report.regions)do
   if r.status=='geometry_ready' and edges+(r.edge_count or 0)<=1000 then
    local kind=(r.player_response==0 or r.collision_enabled==0)and 'ignored'or 'active'
    parts[#parts+1]=r.id..':'..kind
    for _,convex in ipairs(r.convexes)do for _,edge in ipairs(convex.edges)do
     local a,b=convex.world_vertices[edge[1]],convex.world_vertices[edge[2]]
     groups[kind][#groups[kind]+1]={a=a,b=b}
     parts[#parts+1]=string.format('%.2f,%.2f,%.2f:%.2f,%.2f,%.2f',a.X,a.Y,a.Z,b.X,b.Y,b.Z)
    end end
    edges=edges+(r.edge_count or 0);count=count+1
   else skipped=skipped+1 end
  end
  local next_signature=table.concat(parts,'|')
  if signature==next_signature then
   local alive=true
   for _,r in ipairs(owned)do local a=resolve(r);if a then a:SetLifeSpan(60)else alive=false end end
   if alive then return end
  end
  if not clear()then enabled=false;return end
  for _,kind in ipairs({'active','ignored'})do
   if #groups[kind]>0 then
    local result=render(H,log,groups[kind],{width_cm=2,lifespan_seconds=60,color=colors[kind]})
    if not result.ok then clear();error('display render failed: '..tostring(result.reason)) end
    -- Retain identity strings only, never a live UObject reference.
    owned[#owned+1]={actor_id=result.actor_id,actor_address=result.actor_address,world_id=result.world_id}
   end
  end
  signature=next_signature
  note('display enabled; radius=30m regions='..count..' skipped='..skipped..' truncated='..tostring(report.truncated)..' edges='..edges..'; red=Pawn_response_present green=Pawn_ignore_or_collision_off')
 end
 local function tick()
  local ok,err=pcall(function()
   if requests>0 then
    requests=requests-1;enabled=not enabled;ticks=0
    if not enabled then clear();note('display disabled')else refresh()end
   elseif enabled then
    ticks=ticks+1
    if ticks>=10 then ticks=0;refresh()end
   elseif #owned>0 then clear() end
  end)
  if not ok then enabled=false;pcall(clear);note('display_error='..tostring(err))end
  return false
 end
 return {request_toggle=function()requests=requests+1 end,tick=tick}
end
return M
