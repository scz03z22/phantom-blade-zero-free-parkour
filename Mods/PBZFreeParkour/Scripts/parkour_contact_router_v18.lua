-- Pure research candidate. Never reads engine objects, consumes input, or starts an action.
-- Body orientation, not camera orientation, determines the long-hold route.
--
-- M.classify(snapshot, options) -> {status='selected'|'wait', reason, ...}
-- snapshot: contact == true, body_forward={X,Y,Z}, wall_normal={X,Y,Z}.
-- Optional move_input / velocity are diagnostic vectors only. They cannot override
-- body orientation or turn an absent contact into an eligible contact.
--
-- M.new(options):update(snapshot) -> selected / locked / wait result.
-- The stateful wrapper also requires nonempty player_id/world_id and finite time.
-- Call it only for the current long-hold action attempt. A selected route is locked
-- until ended/landed, reset(), identity change, or time rewind. An observed airborne
-- -> grounded transition also clears it; initially grounded is allowed for the
-- existing ground-contact double press. Explicit ended/landed samples never select.
-- A lost contact does not erase the lock, but current_contact=false and
-- new_selection=false do NOT authorize starting/restarting an action. Downstream
-- execution must still validate its current contact/ownership/lifecycle.
-- External jump/pre-input buffering stays entirely with the existing Session.
--
-- UE coordinates: X forward, Y right, Z up. side_left / side_right name the SIDE
-- OF THE BODY ON WHICH THE WALL LIES, not the movement direction or camera side.
-- along_wall is the normalized horizontal projection of body_forward onto the
-- wall plane; it is never inferred from input/velocity. These thresholds are
-- initial research parameters, not live gameplay validation.
local M = {}

local EPS = 1e-8
local DEG_EPS = 1e-7
local DEFAULTS = {
    front_max_deg = 35,
    side_min_deg = 50,
    side_max_deg = 100,
    min_tangent_projection = 0.35,
    -- Reject a floor/ceiling-like normal even if its XY projection is nonzero.
    -- This is a shape sanity check, not a replacement for a verified wall query.
    max_abs_normal_z = 0.5,
}

local function finite(n)
    return type(n) == 'number' and n == n and n > -math.huge and n < math.huge
end

local function vec(v)
    if type(v) ~= 'table' or not finite(v.X) or not finite(v.Y) or not finite(v.Z) then
        return nil
    end
    return {X=v.X, Y=v.Y, Z=v.Z}
end

local function copy(t)
    if type(t) ~= 'table' then return t end
    local r = {}
    for k,v in pairs(t) do r[k] = copy(v) end
    return r
end

local function length_xy(v)
    -- Scaling avoids overflow for otherwise finite input coordinates.
    local m = math.max(math.abs(v.X), math.abs(v.Y))
    if m < EPS then return nil end
    local x,y = v.X/m,v.Y/m
    local q = math.sqrt(x*x+y*y)
    return {X=x/q,Y=y/q,Z=0}, m*q
end

local function unit(v)
    local m = math.max(math.abs(v.X),math.abs(v.Y),math.abs(v.Z))
    if m < EPS then return nil end
    local x,y,z = v.X/m,v.Y/m,v.Z/m
    local q = math.sqrt(x*x+y*y+z*z)
    return {X=x/q,Y=y/q,Z=z/q}
end

local function dot_xy(a,b) return a.X*b.X+a.Y*b.Y end
local function clamp(n,a,b) return math.max(a,math.min(b,n)) end

local function options(o)
    if o ~= nil and type(o) ~= 'table' then error('router options must be a table') end
    local c = copy(DEFAULTS)
    for k,v in pairs(o or {}) do
        if c[k] == nil then error('unknown router option: '..tostring(k)) end
        if not finite(v) then error('nonfinite router option: '..k) end
        c[k] = v
    end
    assert(c.front_max_deg>=0 and c.front_max_deg<c.side_min_deg,
        'front angle must be below side minimum')
    assert(c.side_min_deg<=c.side_max_deg and c.side_max_deg<=180,
        'invalid side angle interval')
    assert(c.min_tangent_projection>0 and c.min_tangent_projection<=1,
        'invalid tangent projection minimum')
    assert(c.max_abs_normal_z>=0 and c.max_abs_normal_z<1,
        'invalid wall normal Z limit')
    return c
end

local function diagnostic(v,tangent,toward)
    if v == nil then return {provided=false} end
    local p = vec(v)
    if not p then return {provided=true,readable=false} end
    local direction,speed = length_xy(p)
    local r = {provided=true,readable=true,vector=p,speed_xy=speed or 0}
    if direction then
        r.toward_wall_dot = dot_xy(direction,toward)
        if tangent then r.along_wall_dot = dot_xy(direction,tangent) end
    end
    return r
end

local function classify(s,c)
    local r = {status='wait',new_selection=false,reason='invalid_snapshot'}
    if type(s) ~= 'table' then return r end
    if s.contact ~= true then r.reason='no_current_contact';return r end
    local f,n = vec(s.body_forward),vec(s.wall_normal)
    if not f then r.reason='invalid_body_forward';return r end
    if not n then r.reason='invalid_wall_normal';return r end
    local body = length_xy(f)
    if not body then r.reason='body_forward_has_no_horizontal_direction';return r end
    local normal = unit(n)
    if not normal then r.reason='zero_wall_normal';return r end
    if math.abs(normal.Z)>c.max_abs_normal_z then
        r.reason='normal_not_wall_like';return r
    end
    local nh = length_xy(normal)
    if not nh then r.reason='wall_normal_has_no_horizontal_direction';return r end
    local toward = {X=-nh.X,Y=-nh.Y,Z=0}
    local angle = math.acos(clamp(dot_xy(body,toward),-1,1))*180/math.pi
    local d = dot_xy(body,nh)
    local projected = {X=body.X-d*nh.X,Y=body.Y-d*nh.Y,Z=0}
    local tangent,projection = length_xy(projected)
    projection = projection or 0
    r.angle_deg=angle
    r.body_forward=f
    r.body_forward_xy=body
    r.wall_normal=normal
    r.wall_normal_xy=nh
    r.toward_wall=toward
    r.tangent_projection=projection
    r.move_input=diagnostic(s.move_input,tangent,toward)
    r.velocity=diagnostic(s.velocity,tangent,toward)
    r.current_contact=true
    if angle<=c.front_max_deg+DEG_EPS then
        r.route='vertical'
    elseif angle<c.side_min_deg-DEG_EPS then
        r.reason='angle_gray_zone';return r
    elseif angle>c.side_max_deg+DEG_EPS then
        r.reason='body_facing_away_from_wall';return r
    elseif not tangent or projection<c.min_tangent_projection then
        r.reason='insufficient_tangent_projection';return r
    else
        -- Cross(body,toward).Z is positive for a wall to the actor's right in UE.
        local side = body.X*toward.Y-body.Y*toward.X
        if math.abs(side)<EPS then r.reason='ambiguous_wall_side';return r end
        r.route = side>0 and 'side_right' or 'side_left'
        r.along_wall=tangent
    end
    r.status='selected'
    r.new_selection=true
    r.reason='body_angle_selected'
    return r
end

function M.classify(s,o) return classify(s,options(o)) end

function M.new(o)
    local c=options(o)
    local selected,player_id,world_id,last_time,seen_airborne
    local last_reset_reason='initial'
    local api={}
    local function clear(reason)
        selected=nil;seen_airborne=false;last_reset_reason=reason
    end
    local function wait(reason)
        return {status='wait',reason=reason,new_selection=false,last_reset_reason=last_reset_reason}
    end
    local function identity(v) return type(v)=='string' and v~='' end
    function api:reset(reason)
        clear(type(reason)=='string' and reason~='' and reason or 'explicit_reset')
        player_id=nil;world_id=nil;last_time=nil
    end
    function api:peek() return selected and copy(selected) or nil end
    function api:update(s)
        if type(s)~='table' or not identity(s.player_id) or not identity(s.world_id)
            or not finite(s.time) then
            self:reset('invalid_context_or_time')
            return wait('invalid_context_or_time')
        end
        if player_id and (player_id~=s.player_id or world_id~=s.world_id) then
            clear('identity_changed')
            player_id=s.player_id;world_id=s.world_id;last_time=s.time
            return wait('identity_changed')
        end
        if last_time and s.time<last_time then
            clear('clock_rewound');last_time=s.time
            return wait('clock_rewound')
        end
        player_id=s.player_id;world_id=s.world_id;last_time=s.time
        if s.ended==true then clear('action_ended');return wait('action_ended') end
        if s.landed==true or (seen_airborne and s.airborne==false) then
            clear('landed');return wait('landed')
        end
        if s.airborne==true then seen_airborne=true end
        if selected then
            local r=copy(selected)
            r.status='locked';r.reason='action_selection_locked';r.new_selection=false
            -- Current contact is deliberately separate from the selection snapshot.
            -- A locked route alone is never evidence that the current wall is valid.
            r.current_contact=s.contact==true
            r.current_wall_normal=vec(s.wall_normal)
            r.current_body_forward=vec(s.body_forward)
            return r
        end
        local r=classify(s,c)
        if r.status=='selected' then
            r.selected_at=s.time;r.player_id=s.player_id;r.world_id=s.world_id
            selected=copy(r)
        end
        return r
    end
    return api
end

return M
