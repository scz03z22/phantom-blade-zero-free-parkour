-- STAGED ONLY. The caller runs tick/toggle on the game thread. No timers,
-- hooks, I/O, key binding or UObject caching here. Current implementation
-- supports ONLY confirmed PBZGEVolume GE_Kill, not every death mechanism.
local M={}
function M.new(controller,adapter,options)
 assert(type(controller)=='table' and type(controller.enable)=='function' and type(controller.disable)=='function')
 assert(type(adapter)=='table' and type(adapter.snapshot)=='function')
 options=options or {};local interval=options.interval_seconds or 3
 assert(type(interval)=='number' and interval>=1 and interval<=30,'invalid scan interval')
 local mode='off';local next_scan=nil;local last_time=nil
 local function status() return mode end
 local function toggle()
  if mode=='off'then mode='enabled';next_scan=nil;return 'enabled_pending_scan' end
  if mode=='enabled' or mode=='write_uncertain'then mode='restoring';next_scan=nil;return 'restoring' end
  if mode=='restoring'then next_scan=nil;return 'restore_retry_requested' end
  if mode=='world_changed_unresolved'then mode='restoring';next_scan=nil;return 'restore_retry_requested' end
  error('unknown runtime mode')
 end
 local function tick(now)
  assert(type(now)=='number' and now==now and math.abs(now)<math.huge,'invalid clock')
  if mode=='off'then last_time=now;return {status='off'}end
  if mode=='write_uncertain' or mode=='world_changed_unresolved'then return {status=mode,mode=mode}end
  if last_time and now<last_time then next_scan=nil end;last_time=now
  if next_scan and now<next_scan then return {status='waiting',mode=mode}end
  next_scan=now+interval
  local good,snapshot=pcall(adapter.snapshot)
  if not good then next_scan=now+3;return {status='snapshot_unavailable',mode=mode,reason=tostring(snapshot):sub(1,240)}end
  local op=mode=='enabled' and controller.enable or controller.disable
  local ok,result=pcall(op,snapshot)
  if not ok then mode='write_uncertain';return {status='operation_error',mode=mode,reason=tostring(result):sub(1,240)}end
  assert(type(result)=='table' and type(result.status)=='string','invalid controller result')
  if result.status=='world_changed_unresolved'then mode='world_changed_unresolved'
  elseif result.status=='write_uncertain'then mode='write_uncertain'
  elseif mode~='enabled' and result.status=='restored'then mode='off';next_scan=nil
  elseif mode=='restoring' then next_scan=now+((result.applied and #result.applied>0) and 0.5 or 3)
  elseif result.status=='scan_pending' then next_scan=now+0.5 end
  result.mode=mode;result.unknown_effect_count=snapshot.unknown_effect_count;return result
 end
 return {toggle=toggle,tick=tick,status=status}
end
return M
