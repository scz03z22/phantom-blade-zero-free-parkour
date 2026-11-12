-- Pure planning only: no Unreal API calls, timers, objects, side effects or writes.
-- Caller must freshly re-read and verify every identity/response immediately
-- before each write; this planner is not itself a runtime toggle.
local M={}
local GE='BlueprintGeneratedClass /Game/PBZContent/Blueprint/Ability/GameplayEffects/GE_Kill.GE_Kill_C'
local function finite(x)return type(x)=='number' and x==x and math.abs(x)<math.huge end
local function vec(v)
 assert(type(v)=='table' and finite(v.X) and finite(v.Y) and finite(v.Z),'invalid vector')
 return v
end
local function ident(s)assert(type(s)=='string' and s~='','missing identity');return s end
local function address(s)assert(type(s)=='string' and s:match('^[1-9]%d*$'),'invalid address');return s end
local function bounds(b)
 assert(type(b)=='table','missing bounds');vec(b.origin);vec(b.extent)
 assert(b.extent.X>=0 and b.extent.Y>=0 and b.extent.Z>=0,'invalid bounds');return b
end
local function dense(a,limit)
 assert(type(a)=='table' and getmetatable(a)==nil,'invalid array')
 local n,max=0,0
 for k in next,a do assert(type(k)=='number' and k%1==0 and k>=1 and k<=limit,'invalid array key');n=n+1;max=math.max(max,k) end
 assert(n==max,'sparse array');return n
end
local function distance(p,b)
 local sq=0
 for _,k in ipairs({'X','Y','Z'})do local d=math.max(0,math.abs(p[k]-b.origin[k])-b.extent[k]);sq=sq+d*d end
 return math.sqrt(sq)
end
local function component_key(x)
 return ident(x.actor_id)..'@'..address(x.actor_address)..'|'..ident(x.brush_id)..'@'..address(x.brush_address)
end
local function ctx(s)
 assert(type(s)=='table' and s.complete==true,'incomplete snapshot')
 ident(s.world_id);address(s.world_address);ident(s.player_id);address(s.player_address);vec(s.position)
 assert(type(s.channel)=='number' and s.channel>=0 and s.channel<=31 and s.channel%1==0,'invalid channel')
 dense(s.rows,512)
 return s
end
local function validrow(r,s)
 assert(type(r)=='table','invalid row');local key=component_key(r)
 assert(r.actor_class=='PBZGEVolume' and r.brush_class=='BrushComponent','unrecognized class')
 assert(r.world_id==s.world_id and r.world_address==s.world_address,'foreign world')
 assert(r.ge_class==GE,'unrecognized effect')
 assert(r.brush_owner_id==r.actor_id and r.brush_owner_address==r.actor_address,'brush owner mismatch')
 assert(r.response==0 or r.response==1 or r.response==2,'invalid response')
 bounds(r.bounds);return key
end
local function settings(radius,margin)
 assert(finite(radius) and radius>=300 and radius<=10000,'invalid radius')
 assert(finite(margin) and margin>=300 and margin<=radius,'invalid margin')
end
function M.disable(s,radius,margin)
 ctx(s);settings(radius,margin)
 local p={status='planned',actions={},skipped={},world_id=s.world_id,world_address=s.world_address,
  channel=s.channel,player_id=s.player_id,player_address=s.player_address}
 local seen,seen_actor,seen_brush={},{},{}
 for _,row in ipairs(s.rows)do
  local key=validrow(row,s);assert(not seen[key],'duplicate component');seen[key]=true
  assert(not seen_actor[row.actor_id] and not seen_brush[row.brush_id],'ambiguous actor or brush path')
  seen_actor[row.actor_id]=true;seen_brush[row.brush_id]=true
  local d=distance(s.position,row.bounds)
  if d<=radius then
   if d<=margin then p.skipped[#p.skipped+1]={key=key,reason='player_near_bounds'}
   elseif row.response==0 then p.skipped[#p.skipped+1]={key=key,reason='already_ignored_not_owned'}
   else
    p.actions[#p.actions+1]={key=key,actor_id=row.actor_id,actor_address=row.actor_address,brush_id=row.brush_id,
     brush_address=row.brush_address,ge_class=row.ge_class,original_response=row.response,
     expected_response=row.response,desired_response=0,bounds=row.bounds}
   end
  end
 end
 return p
end
-- journal contains only successfully verified writes owned by this toggle.
-- Missing/moved/unloaded objects remain pending; a different occupant at the
-- same address/path must not be treated as the original object.
function M.restore(s,journal,margin)
 ctx(s);assert(finite(margin) and margin>=300 and margin<=10000,'invalid margin')
 assert(type(journal)=='table','invalid journal');dense(journal.entries,512)
 assert(s.world_id==journal.world_id and s.world_address==journal.world_address and s.channel==journal.channel,'world/channel changed')
 local rows,seen,seen_actor,seen_brush={},{},{},{}
 for _,row in ipairs(s.rows)do
  local k=validrow(row,s);assert(not seen[k],'duplicate component');seen[k]=true
  assert(not seen_actor[row.actor_id] and not seen_brush[row.brush_id],'ambiguous actor or brush path')
  seen_actor[row.actor_id]=true;seen_brush[row.brush_id]=true;rows[k]=row
 end
 local p={status='planned',actions={},pending={},conflicts={}}
 local journal_seen={}
 for _,entry in ipairs(journal.entries)do
  local k=component_key(entry);assert(entry.key==k and not journal_seen[k],'invalid or duplicate journal identity');journal_seen[k]=true
  assert(entry.ge_class==GE and (entry.original_response==1 or entry.original_response==2),'invalid original response')
  bounds(entry.bounds)
  local row=rows[k]
  if not row then p.pending[#p.pending+1]={key=k,reason='object_unavailable_or_replaced'}
  elseif distance(s.position,row.bounds)<=margin or distance(s.position,entry.bounds)<=margin then
   p.pending[#p.pending+1]={key=k,reason='player_near_bounds'}
  elseif row.response==entry.original_response then
   p.actions[#p.actions+1]={key=k,actor_id=entry.actor_id,actor_address=entry.actor_address,brush_id=entry.brush_id,
    brush_address=entry.brush_address,expected_response=entry.original_response,desired_response=entry.original_response,
    bounds=entry.bounds,verify_only=true}
  elseif row.response~=0 then p.conflicts[#p.conflicts+1]={key=k,reason='response_changed_externally'}
  else p.actions[#p.actions+1]={key=k,actor_id=entry.actor_id,actor_address=entry.actor_address,brush_id=entry.brush_id,
    brush_address=entry.brush_address,expected_response=0,desired_response=entry.original_response,bounds=entry.bounds} end
 end
 return p
end
return M
