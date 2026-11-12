-- Adapter-driven candidate. This module itself knows no Unreal APIs.
-- adapter.apply(action, snapshot) MUST re-resolve and revalidate identity,
-- ownership, actual response, player/world and safety immediately before
-- writing, then read back; only return 'applied' after confirmed readback.
-- 'not_applied' means a verified no-write. For explicit verify_only actions,
-- 'verified_original' confirms identity/response without calling a setter.
-- This contract is not yet implemented for the live game. Not release-ready.
local M={}
function M.new(policy,adapter,options)
 assert(type(policy)=='table' and type(policy.disable)=='function' and type(policy.restore)=='function')
 assert(type(adapter)=='table' and type(adapter.apply)=='function','adapter unavailable')
 options=options or {};local radius=options.radius_cm or 3000;local margin=options.margin_cm or 300
 local journal=nil
 local function clone(v,depth)
  assert((depth or 0)<16,'snapshot nesting exceeded')
  if type(v)~='table'then assert(type(v)=='string' or type(v)=='number' or type(v)=='boolean','nonprimitive');return v end
  assert(getmetatable(v)==nil,'nonprimitive table');local o={}
  for k,x in pairs(v)do assert(type(k)=='string' or type(k)=='number','invalid key');o[k]=clone(x,(depth or 0)+1)end
  return o
 end
 local function report(status)
  return {status=status,applied={},uncertain={},not_applied={},pending={},conflicts={},skipped={}}
 end
 local function apply(a,s)
  local ok,result,detail=pcall(adapter.apply,clone(a),clone(s))
  if ok and (result=='applied' or result=='not_applied' or (a.verify_only==true and result=='verified_original')) then return result,tostring(detail or '') end
  return 'uncertain',tostring(ok and result or result):sub(1,300)
 end
 local function enable(s)
  local r=report('scanned')
  if journal and #journal.entries==0 then journal=nil end
  if journal then
   for _,entry in ipairs(journal.entries)do
    if entry.write_state~='verified'then r.status='write_uncertain';return r end
   end
  end
  if journal and (s.world_id~=journal.world_id or s.world_address~=journal.world_address or s.channel~=journal.channel) then
   r.status='world_changed_unresolved';return r
  end
  local p=policy.disable(s,radius,margin);r.skipped=clone(p.skipped)
  if not journal then journal={world_id=s.world_id,world_address=s.world_address,channel=s.channel,entries={}} end
  local owned,owned_actor,owned_brush={},{},{}
  for _,e in ipairs(journal.entries)do owned[e.key]=true;owned_actor[e.actor_id]=true;owned_brush[e.brush_id]=true end
  local attempts=0
  for _,action in ipairs(p.actions)do
   if owned[action.key] then
    r.conflicts[#r.conflicts+1]={key=action.key,reason='owned_response_changed_or_reappeared'}
   elseif owned_actor[action.actor_id] or owned_brush[action.brush_id] then
    r.conflicts[#r.conflicts+1]={key=action.key,reason='owned_path_replaced_or_reloaded'}
   else
    if attempts>=1 then r.status='scan_pending';break end
    attempts=attempts+1
    if #journal.entries>=512 then r.status='journal_capacity_reached';break end
    -- Journal before attempting: an exception after an engine write must never
    -- be mistaken for a verified no-write. Records contain primitives only.
    local e=clone(action);e.write_state='attempting';journal.entries[#journal.entries+1]=e;owned[e.key]=true;owned_actor[e.actor_id]=true;owned_brush[e.brush_id]=true
    local result,detail=apply(action,s)
    if result=='applied'then e.write_state='verified';r.applied[#r.applied+1]=e.key
    elseif result=='not_applied'then journal.entries[#journal.entries]=nil;owned[e.key]=nil;owned_actor[e.actor_id]=nil;owned_brush[e.brush_id]=nil;r.not_applied[#r.not_applied+1]={key=e.key,reason=detail}
    else e.write_state='uncertain';r.uncertain[#r.uncertain+1]={key=e.key,reason=detail};r.status='write_uncertain';break end
   end
  end
  return r
 end
 local function disable(s)
  local r=report('restoring')
  if not journal or #journal.entries==0 then journal=nil;r.status='restored';return r end
  if s.world_id~=journal.world_id or s.world_address~=journal.world_address or s.channel~=journal.channel then
   r.status='world_changed_unresolved';return r
  end
  local p=policy.restore(s,journal,margin);r.pending=clone(p.pending);r.conflicts=clone(p.conflicts)
  local restored={}
  local attempts=0
  for _,action in ipairs(p.actions)do
   if attempts>=1 then break end
   attempts=attempts+1
   local result,detail=apply(action,s)
   if result=='applied' or result=='verified_original'then restored[action.key]=true;r.applied[#r.applied+1]=action.key
   elseif result=='not_applied'then r.not_applied[#r.not_applied+1]={key=action.key,reason=detail}
   else r.uncertain[#r.uncertain+1]={key=action.key,reason=detail};r.status='write_uncertain';break end
  end
  local retained={};for _,e in ipairs(journal.entries)do if not restored[e.key]then retained[#retained+1]=e end end
  journal.entries=retained
  if #retained==0 then journal=nil;r.status='restored'
  elseif r.status~='write_uncertain'then r.status='restore_pending'end
  return r
 end
 local function state()return journal and clone(journal) or nil end
 return {enable=enable,disable=disable,state=state}
end
return M
