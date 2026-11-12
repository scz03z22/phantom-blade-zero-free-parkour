-- Pure two-edge gate with pre-takeoff buffering and bounded dispatch retry.
-- ground_push_double is the legacy name for two grounded wall-contact edges.
-- ground_pending cannot execute while grounded; it waits for the first takeoff.
local M={}
function M.new(options)
 options=options or {}
 local window,buffer=options.window or 3,options.buffer_window or .40
 local air_window=options.air_window or 10
 assert(type(window)=='number' and window>0 and window<10)
 assert(type(buffer)=='number' and buffer>=0 and buffer<=.5)
 assert(type(air_window)=='number' and air_window>=window and air_window<=30)
 local state,first,second,saw_air,last_time,first_contact,kind,air_since='idle',nil,nil,false,nil,false,nil,nil
 local EPS=.0000001
 local function reset()
  state,first,second,saw_air,first_contact,kind,last_time,air_since='idle',nil,nil,false,false,nil,nil,nil
 end
 local function observe(now)
  assert(type(now)=='number' and now==now and math.abs(now)<math.huge,'missing input time')
  local backwards=last_time and now<last_time
  if backwards then reset() end
  last_time=now;return backwards
 end
 local function observe_air(now,airborne)
  if airborne then
   if not saw_air then air_since=now end
   saw_air=true
  end
 end
 local function armed_expired(now)
  if saw_air then return now-air_since>air_window+EPS end
  return now-first>window+EPS
 end
 local function pending_event(now,airborne)
  if not airborne and saw_air then reset();return 'landed' end
  -- Check the original grounded deadline BEFORE observing a first takeoff.
  -- A late frame/extra edge must not revive an already-expired ground buffer.
  if not saw_air and now-second>buffer+EPS then reset();return 'buffer_expired' end
  observe_air(now,airborne)
  if airborne then
   kind='air_double'
   if now-air_since>air_window+EPS then reset();return 'air_expired' end
  end
  return nil
 end
 local function tick(now,airborne,eligible,keep_buffer,ground_contact)
  if observe(now) then return 'time_reset' end
  if state=='armed' then
   if not airborne and saw_air then reset();return 'landed' end
   observe_air(now,airborne)
   if armed_expired(now) then reset();return 'expired' end
  elseif state=='pending' then
   local event=pending_event(now,airborne);if event then return event end
   if (airborne and eligible) or (not airborne and kind=='ground_push_double' and ground_contact) then
    state='running';return 'start'
   end
   -- Missing ground contact can recover within the original .40 s deadline.
   -- ground_pending never starts on ground, even if a wall arrives meanwhile.
   if airborne and keep_buffer==false then reset();return 'cancelled' end
  end
  return 'none'
 end
 local function press(now,airborne,eligible,allow_airborne_first,allow_buffer,ground_contact)
  if observe(now) then return 'time_reset' end
  if state=='running' then return 'busy' end
  if state=='pending' then
   if not airborne and saw_air then reset()
   else
    local event=pending_event(now,airborne);if event then return event end
    return 'busy'
   end
  end
  if state=='armed' then
   if saw_air and not airborne then reset()
   else
    observe_air(now,airborne)
    if armed_expired(now) then reset() end
   end
  end
  if state=='idle' then
   if airborne and not allow_airborne_first then return 'ignored_airborne_first' end
   state,first,saw_air,first_contact='armed',now,not not airborne,not airborne and not not ground_contact
   air_since=airborne and now or nil
   return 'armed'
  end
  if airborne and (eligible or allow_buffer) then
   state,second,saw_air,kind='pending',now,true,'air_double'
   return eligible and 'queued' or 'buffered'
  end
  if not airborne and not saw_air then
   state,second='pending',now
   kind=(first_contact and ground_contact) and 'ground_push_double' or 'ground_pending'
   return kind=='ground_push_double' and 'queued' or 'buffered'
  end
  reset();return 'rejected'
 end
 local function retry(now,airborne)
  if observe(now) then return 'time_reset' end
  if state~='running' then return 'not_running' end
  local event=pending_event(now,airborne);if event then return event end
  state='pending';return 'retry_pending'
 end
 return {press=press,tick=tick,retry=retry,reset=reset,state=function() return state end,
  trigger_kind=function() return kind end,second_press_time=function() return second end}
end
return M
