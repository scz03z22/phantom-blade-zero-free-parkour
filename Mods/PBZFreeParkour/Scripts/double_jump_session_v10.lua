-- v18 hold-aware gate: retain pre-input for exact pre-dispatch body-angle waiting.
-- The engine supplies fresh nearby wall-query evidence.
-- A genuine second Space edge may precede contact anywhere in this same flight.
-- No direction input, movement displacement, facing or horizontal speed gate.
local M={}
function M.new(controller,env,options)
 options=options or {}
 local max_attempts,cooldown=options.max_attempts,options.cooldown or 4
 local hold_threshold=options.hold_threshold
 if hold_threshold==nil then hold_threshold=.18 end
 assert(type(hold_threshold)=='number' and hold_threshold>=0 and hold_threshold<=.35)
 local grace_window=options.grace_window or .25
 local retry_interval=options.retry_interval or .15
 assert(type(controller.retry)=='function','v13 controller retry API required')
 assert(type(retry_interval)=='number' and retry_interval>=.10 and retry_interval<=1)
 -- These exact failures occur before actor creation/mutation or native dispatch.
 -- Never retry exceptions, unknown failures, or an accepted call with no montage.
 local retryable={['ascent path blocked']=true,
  ['wall contact too far from current capsule']=true,
  ['no_non_spline_wall_contact']=true,
  ['side_angle_wait']=true}
 assert(max_attempts==nil or (type(max_attempts)=='number' and max_attempts>=1 and max_attempts%1==0))
 assert(options.ready_after==nil or type(options.ready_after)=='number')
 assert(type(cooldown)=='number' and cooldown>=0)
 assert(type(grace_window)=='number' and grace_window>=0 and grace_window<=.25)
 local active,initial,player_id,world_id=true,nil,nil,nil
 local attempts,ready_after,executing=0,options.ready_after,false
 local last_sample_time,second_released,retry_after=nil,false,nil
 local flight_consumed,consumed_player,consumed_world=false,nil,nil
 local EPS=.0000001
 local function log(msg) env.log(msg) end
 local function reset_input()
  initial,player_id,world_id=nil,nil,nil;second_released=false;retry_after=nil;controller.reset()
 end
 local function finish(reason) active=false;reset_input();log(reason) end
 local function sample()
  local s=env.sample()
  if not s or not s.player_id then finish('player_unavailable');return nil end
  if player_id and (s.player_id~=player_id or s.world_id~=world_id) then finish('player_changed');return nil end
  if flight_consumed and (s.player_id~=consumed_player or s.world_id~=consumed_world) then
   flight_consumed=false;finish('player_changed');return nil
  end
  assert(type(s.time)=='number' and s.time==s.time and math.abs(s.time)<math.huge,'invalid sample time')
  local backwards=last_sample_time and s.time<last_sample_time
  last_sample_time=s.time
  if backwards then
   reset_input();ready_after=nil;flight_consumed=false;consumed_player,consumed_world=nil,nil
   log('clock_reset');return s,true
  end
  if s.grounded and not s.airborne then flight_consumed=false;consumed_player,consumed_world=nil,nil end
  if controller.state()=='pending' and s.space_down==false then second_released=true end
  return s,false
 end
 local function finite(n) return type(n)=='number' and n==n and math.abs(n)<math.huge end
 local function vector(v)
  return type(v)=='table' and finite(v.X) and finite(v.Y) and finite(v.Z)
 end
 local function contact(s)
  if s.contact~=true or not vector(s.wall) or not vector(s.wall_normal) then return false end
  local n=s.wall_normal;local horizontal=n.X*n.X+n.Y*n.Y
  -- Reject missing, degenerate and floor-like normals. There is no comparison
  -- with player facing, WASD direction, input source or actual velocity.
  return horizontal>=.7^2 and math.abs(n.Z)/math.sqrt(horizontal+n.Z*n.Z)<.66
 end
 local function ground_contact(s)
  return not not (s.grounded and not s.airborne and contact(s))
 end
 local function press(prior_ground)
  if not active then return 'inactive' end
  if executing then return 'busy' end
  local s,time_reset=sample();if not s then return 'unavailable' end
  if time_reset then return 'time_reset' end
  if ready_after and s.time<ready_after then log('press=cooldown');return 'cooldown' end
  if not s.grounded and not s.airborne then reset_input();return 'movement_mode' end
  if flight_consumed and s.airborne then log('press=flight_consumed');return 'flight_consumed' end
  local grace,descending=false,false
  if controller.state()=='idle' and s.airborne then
   grace=not not (type(s.velocity_z)=='number' and s.velocity_z>0
    and prior_ground and prior_ground.grounded and prior_ground.ground
    and prior_ground.player_id==s.player_id and prior_ground.world_id==s.world_id
    and type(prior_ground.time)=='number' and s.time>=prior_ground.time
    and s.time-prior_ground.time<=grace_window+EPS)
   descending=not not (type(s.velocity_z)=='number' and s.velocity_z<=0 and contact(s))
   if not grace and not descending then log('press=not_grounded');return 'not_grounded' end
  end
  local touching=contact(s)
  local eligible=s.airborne and touching
  local result=controller.press(s.time,s.airborne,eligible,grace or descending,s.airborne,ground_contact(s))
  log('press='..result..' mode='..tostring(s.mode)..' contact='..tostring(touching)
   ..' first_descending='..tostring(descending)..' time='..tostring(s.time))
  if result=='armed' then
   second_released=false;retry_after=nil;initial=grace and prior_ground.ground or s.ground
   player_id,world_id=s.player_id,s.world_id
  elseif result=='queued' or result=='buffered' then second_released=s.space_down==false
  elseif result~='busy' then initial,player_id,world_id=nil,nil,nil;second_released=false;retry_after=nil end
  return result
 end
 local function update()
  if not active then return 'inactive' end
  if executing then return 'busy' end
  local s,time_reset=sample();if not s then return 'unavailable' end
  if time_reset then return 'time_reset' end
  if not s.grounded and not s.airborne then
   if controller.state()~='idle' then reset_input();log('update=movement_mode');return 'cancelled' end
   return 'none'
  end
  local retry_ready=not retry_after or s.time+EPS>=retry_after
  -- Classify the original second edge BEFORE accepting native dispatch.
  -- An earlier release is latched even if Space was pressed again. Landing and
  -- expiry still advance while deciding; no cooldown/flight is consumed here.
  local second_time=controller.second_press_time()
  local decision_ready=hold_threshold==0 or not second_time or second_released
   or s.space_down==false
   or (s.space_down==true and s.time-second_time+EPS>=hold_threshold)
  retry_ready=retry_ready and decision_ready
  -- Still advance landing/expiry on every frame while dispatch is deferred.
  local event=controller.tick(s.time,s.airborne,retry_ready and s.airborne and contact(s),
   s.airborne,retry_ready and ground_contact(s))
  if event=='start' then
   local context,kind=initial,controller.trigger_kind()
   local second_time=controller.second_press_time and controller.second_press_time() or nil
   local released=second_released
   executing=true
   local current={};for k,v in pairs(s) do current[k]=v end
   current.trigger_kind=kind -- ground_push_double is a legacy name for ground contact.
   current.second_press_time=second_time;current.second_released=released
   local ok,accepted,reason=pcall(env.start_action,context,current);executing=false
   if not ok then finish('action_error='..tostring(accepted));return 'action_error' end
   if accepted==false then
    if retryable[reason] then
     local rearmed=controller.retry(s.time,s.airborne)
     if rearmed=='retry_pending' then
      retry_after=s.time+retry_interval
      log(string.format('v13_preinput_deferred reason=%s second=%.3f next=%.3f',
       tostring(reason),second_time,retry_after))
      return 'deferred'
     end
    end
    reset_input();log('action_rejected='..tostring(reason));return 'action_rejected'
   end
   if accepted~=true then finish('action_error=invalid adapter result');return 'action_error' end
   reset_input()
   flight_consumed=true;consumed_player,consumed_world=s.player_id,s.world_id
   attempts=attempts+1;ready_after=s.time+cooldown;log('action_returned attempt='..attempts..' kind='..tostring(kind))
   if env.on_action then
    local notified,notice=pcall(env.on_action,s.time)
    if not notified then finish('action_error=cooldown notification '..tostring(notice));return 'action_error' end
   end
   if max_attempts and attempts>=max_attempts then active=false end
   return 'attempted'
  elseif event~='none' then
   initial,player_id,world_id=nil,nil,nil;second_released=false;retry_after=nil;log('update='..event)
  end
  return event
 end
 log('v15 input gate loaded; hold threshold='..tostring(hold_threshold)..'; ground pair=3s takeoff buffer=.40s air pre-input=one flight watchdog=10s; retry='..tostring(retry_interval)..'; no direction or displacement requirement')
 return {press=press,update=update,stop=function() finish('stopped') end,
  active=function() return active end,attempts=function() return attempts end,
  flight_consumed=function() return flight_consumed end}
end
return M
