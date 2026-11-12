-- Game-thread-only experimental apex exit controller. No engine access itself.
-- env.sample() must return fresh, complete identity/ability/floor evidence.
-- env.end_special_move(ability_id) and env.set_falling() must re-resolve and
-- validate objects on the game thread. This module never writes gravity.
local M={}
function M.new(env,options)
 options=options or {}
 local min_rise=options.min_rise or 5
 local epsilon=options.epsilon or 0.5
 local settle=options.settle_samples or 2
 local timeout=options.timeout or 5
 local cleanup_timeout=options.cleanup_timeout or 1
 assert(type(min_rise)=='number' and min_rise>0 and type(epsilon)=='number' and epsilon>=0)
 assert(type(settle)=='number' and settle>=2 and settle%1==0)
 assert(type(timeout)=='number' and timeout>0 and type(cleanup_timeout)=='number' and cleanup_timeout>0)
 local run=nil
 local function log(s) if env.log then env.log(s) end end
 local function finish(reason)
  run=nil;log('motion_exit_finished reason='..reason);return reason
 end
 local function get()
  local ok,s=pcall(env.sample)
  if not ok or type(s)~='table' then return nil end
  return s
 end
 local function num(x) return type(x)=='number' and x==x and x~=math.huge and x~=-math.huge end
 local function id(x) return type(x)=='string' and x~='' end
 -- completeness is explicit: an unavailable ability list is never interpreted
 -- as evidence that an ability ended. Duplicate matches are ambiguous.
 local function candidates(s,r)
  if s.abilities_complete~=true or type(s.abilities)~='table' then return nil,'ability_list_unavailable' end
  local matches={};local other_active=false
  for _,a in ipairs(s.abilities) do
   if type(a)~='table' or type(a.active)~='boolean' or not id(a.id) then return nil,'ability_evidence_invalid' end
   if a.active and a.player_id==r.player then
    if a.volume_id==r.volume then matches[#matches+1]=a else other_active=true end
   end
  end
  return matches,nil,other_active
 end
 local function sane(s,r)
  return s.player_id==r.player and s.world_id==r.world and num(s.time) and s.time>=r.last_time
    and num(s.z) and type(s.mode)=='number'
 end
 local function observe(s,phase)
  log(string.format('motion_exit phase=%s time=%.3f z=%.2f mode=%s montage=%s volume=%s',
   phase,s.time,s.z,tostring(s.mode),tostring(s.montage_id or 'none'),tostring(s.volume_id or 'none')))
 end
 local function start(ownership)
  if run then return false,'busy' end
  if type(ownership)~='table' or not id(ownership.player_id) or not id(ownership.world_id)
    or not id(ownership.owned_volume_id) then return false,'invalid_ownership' end
  local s=get();if not s then return false,'snapshot_unavailable' end
  local r={player=ownership.player_id,world=ownership.world_id,volume=ownership.owned_volume_id,last_time=s.time}
  if not sane(s,r) or s.volume_id~=r.volume then return false,'ownership_unverified' end
  local matching,err,other_active=candidates(s,r)
  if not matching then return false,err end
  if #matching~=1 or other_active then return false,'ability_not_unique' end
  r.ability=matching[1].id;r.started=s.time;r.start_z=s.z;r.previous_z=s.z;r.peak=s.z;r.still=0;r.phase='tracking'
  run=r;observe(s,'start');return true
 end
 local function update()
  if not run then return 'inactive' end
  local r=run;local s=get()
  if not s or not sane(s,r) then return finish('identity_time_or_snapshot_lost') end
  r.last_time=s.time;observe(s,r.phase)
  local matching,err,other_active=candidates(s,r)
  if not matching then return finish(err) end
  if r.phase=='tracking' then
   if s.time-r.started>timeout then return finish('tracking_timeout') end
   if s.volume_id~=r.volume or #matching~=1 or matching[1].id~=r.ability or other_active then return finish('ownership_changed') end
   if s.mode==1 then return finish('already_landed') end
   if s.z>r.peak then r.peak=s.z end
   if r.peak-r.start_z>=min_rise then
    if s.z-r.previous_z<=epsilon then r.still=r.still+1 else r.still=0 end
   end
   r.previous_z=s.z
   if r.still>=settle then
    -- The adapter must recheck exact identity + ownership immediately before
    -- calling the named instance. Mark first so no reentrant double call.
    r.phase='cleanup';r.ended_at=s.time
    local ok,result=pcall(env.end_special_move,r.ability,r.player,r.world,r.volume)
    if not ok or result~=true then return finish('end_call_failed_or_refused') end
    log('motion_exit_end_requested ability='..r.ability);return 'end_requested'
   end
   return 'tracking'
  end
  if s.time-r.ended_at>cleanup_timeout then return finish('cleanup_timeout') end
  if #matching>1 or other_active then return finish('cleanup_ambiguous') end
  if #matching==1 then
   if matching[1].id~=r.ability then return finish('new_ability') end
   return 'awaiting_cleanup'
  end
  -- Never interfere with a new game interaction or a different volume.
  if s.volume_id~=nil and s.volume_id~='' then
   if s.volume_id~=r.volume then return finish('volume_changed') end
   return 'awaiting_cleanup'
  end
  if s.interact_clear~=true then return finish('interaction_or_state_unknown') end
  if s.mode==1 then return finish('landed') end
  if s.mode==3 then return finish('already_falling') end
  -- floor_walkable=false must come from a real floor query, not mode~=1.
  if s.mode~=5 or s.floor_walkable~=false then return finish('fall_not_proven_safe') end
  local ok,result=pcall(env.set_falling,r.player,r.world,r.volume,r.ability)
  if not ok or result~=true then return finish('fall_call_failed_or_refused') end
  return finish('fall_requested')
 end
 local function stop() if not run then return 'inactive' end;return finish('stopped') end
 return {start=start,update=update,stop=stop}
end
return M
