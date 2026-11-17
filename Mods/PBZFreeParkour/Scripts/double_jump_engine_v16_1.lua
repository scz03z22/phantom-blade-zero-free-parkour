-- v16.1 candidate: v14 short/sample unchanged; opt-in hold-start spline exclusion.
-- v14 contact-only UE-facing short-action adapter. Native pose selection remains observed, not assumed. Call on game thread only.
-- No movement correction, key registration, timer, or asynchronous work here.
local M = {}
local scripts=assert(debug.getinfo(1,'S').source:match('^@(.+[\\/])[^\\/]+$'),'script directory unavailable')
function M.new(H, log, selector, shared, options)
  shared=shared or {}; options=options or {}
  local jump_input=assert(loadfile(scripts..'parkour_input.lua'))().new(log)
  local color={R=0,G=0,B=0,A=0}
  -- Store only identity strings and simple Lua flags, never UObject handles.
  -- Engine instance must live across F8 toggles to preserve this bounded pool.
  local pool,context=shared.pool or {},shared.context
  local function persist() shared.pool=pool;shared.context=context end
  local function valid(o)
    local ok,v=pcall(function() return o and o:IsValid() end)
    return ok and v
  end
  local previous_sample,previous_space=nil,nil
  local contact_activity_until=nil
  local idle_query_reported=false
  pcall(log,'idle_query_perf_20261112 loaded; airborne/input queries unchanged')
  pcall(log,'perf4_ground_move_scan=off; Space, airborne and the 2 s buffer still query')
  local read_errors={}
  local seen_profiles={}
  local function read_error_once(source,reason)
    local detail=tostring(reason);local key=source..'|'..detail
    if read_errors[key] then return end
    read_errors[key]=true
    pcall(log,'v12_contact_read_error source='..source..' reason='..detail)
  end
  local function number(x) return type(x)=='number' and x==x and math.abs(x)<math.huge end
  local function vector(v) return v and number(v.X) and number(v.Y) and number(v.Z) end
  -- This is a short spatial sweep, not an OnHit event or a velocity test.
  -- Resolved components must block the capsule in both directions. If Lua
  -- cannot resolve a native hit, retain the bounded spatial-query evidence
  -- without claiming that the Pawn collision response has been verified.
  local function blocking_component(hit,capsule)
    local ok,result,status=pcall(function()
      local weak=hit.Component
      assert(weak,'hit Component unavailable')
      local component=weak:Get()
      assert(valid(component),'hit Component:Get() did not resolve a valid component')
      local pawn_type=capsule:GetCollisionObjectType()
      local component_type=component:GetCollisionObjectType()
      assert(number(pawn_type) and number(component_type),'collision object channel unreadable')
      local pawn_response=component:GetCollisionResponseToChannel(pawn_type)
      assert(pawn_response==0 or pawn_response==1 or pawn_response==2,'component collision response unreadable')
      if pawn_response~=2 then return nil,'nonblocking' end
      local capsule_response=capsule:GetCollisionResponseToChannel(component_type)
      assert(capsule_response==0 or capsule_response==1 or capsule_response==2,'capsule collision response unreadable')
      if capsule_response~=2 then return nil,'nonblocking' end
      local id=component:GetFullName()
      assert(type(id)=='string' and id~='','component identity unreadable')
      return {component_id=id,pawn_object_type=pawn_type,component_object_type=component_type,
        pawn_response=pawn_response,capsule_response=capsule_response,contact_evidence='component_bidirectional_block'}
    end)
    if not ok then read_error_once('component_response',result);return nil,'unavailable' end
    return result,status
  end
  local function wall_contact(p,q,f,capsule,sys)
    if not vector(q) or not vector(f) then return nil end
    local flen=math.sqrt(f.X*f.X+f.Y*f.Y)
    if flen<.01 then return nil end
    local fx,fy=f.X/flen,f.Y/flen
    local radius=math.max(capsule:GetScaledCapsuleRadius()-2,1)
    local half=math.max(capsule:GetScaledCapsuleHalfHeight()-10,1)
    local profile_ok,profile,profile_name=pcall(function()
      local value=capsule:GetCollisionProfileName();local name=value:ToString()
      assert(type(name)=='string' and name~='','capsule profile name unreadable')
      return value,name
    end)
    if not profile_ok then read_error_once('capsule_profile',profile);profile=nil;profile_name='unavailable' end
    if profile_ok and not seen_profiles[profile_name] then
      seen_profiles[profile_name]=true;pcall(log,'v12_contact_profile name='..profile_name)
    end
    local use_profile=profile_ok and profile_name:lower()~='custom' and profile_name:lower()~='none'
    local query_source=use_profile and 'CapsuleTraceSingleByProfile/actual_capsule_profile/front_semicircle'
      or 'CapsuleTraceSingle/channel0/front_semicircle'
    local best=nil
    for _,degrees in ipairs({0,-45,45,-90,90}) do
      local angle=math.rad(degrees);local c,s=math.cos(angle),math.sin(angle)
      local dir={X=fx*c-fy*s,Y=fx*s+fy*c,Z=0};local hit={}
      local dest={X=q.X+dir.X*8,Y=q.Y+dir.Y*8,Z=q.Z};local yes
      if use_profile then
        yes=sys:CapsuleTraceSingleByProfile(p,q,dest,radius,half,profile,false,{},0,hit,true,color,color,0)
      else
        yes=sys:CapsuleTraceSingle(p,q,dest,radius,half,0,false,{},0,hit,true,color,color,0)
      end
      -- A channel-0 sweep can stop at a spline barrier which does not block
      -- the player. Retry only when the hit component's actual owner is a
      -- BP_SplineWall_C and its Pawn response is known not to block. The
      -- retry result goes through the original geometry and collision gates.
      if yes then
        local eligible,owner=pcall(function()
          local comp=hit.Component:Get()
          if not valid(comp) then return nil end
          local pt=capsule:GetCollisionObjectType()
          local response=comp:GetCollisionResponseToChannel(pt)
          if response~=0 and response~=1 then return nil end
          local actor=comp:GetOwner()
          if not valid(actor) or actor:GetClass():GetFName():ToString()~='BP_SplineWall_C' then return nil end
          return actor
        end)
        if eligible and owner then
          local retry={}
          if use_profile then
            yes=sys:CapsuleTraceSingleByProfile(p,q,dest,radius,half,profile,false,{owner},0,retry,true,color,color,0)
          else
            yes=sys:CapsuleTraceSingle(p,q,dest,radius,half,0,false,{owner},0,retry,true,color,color,0)
          end
          hit=retry
        end
      end
      local n,w=hit.ImpactNormal,hit.ImpactPoint
      local blocking=hit.bBlockingHit==nil or hit.bBlockingHit==true or hit.bBlockingHit==1
      if yes and blocking and vector(n) and vector(w) and math.abs(n.Z)<.66
        and n.X*fx+n.Y*fy<=.25 and n.X*n.X+n.Y*n.Y>.01 then
        local evidence,status=blocking_component(hit,capsule)
        if not evidence and status=='unavailable' then
          -- Custom profiles cannot be recreated by name. Restore the working
          -- channel-0 spatial fallback only for an actual, filtered native hit.
          -- A readable Ignore/Overlap response never reaches this branch.
          -- Unknown channel responses stay unknown, never invented as Block=2.
          evidence={component_id='unresolved',contact_evidence=use_profile
            and 'native_actual_profile_blocking_hit'
            or 'channel0_spatial_hit_unverified_pawn_response'}
        end
        if evidence then
          local distance=number(hit.Distance) and hit.Distance>=0 and hit.Distance or nil
          if not distance and number(hit.Time) and hit.Time>=0 and hit.Time<=1 then distance=hit.Time*8 end
          if not distance then distance=math.sqrt((w.X-q.X)^2+(w.Y-q.Y)^2+(w.Z-q.Z)^2) end
          if not best or distance<best.distance then
            evidence.distance=distance;evidence.hit_distance=number(hit.Distance) and hit.Distance or nil
            evidence.hit_time=number(hit.Time) and hit.Time or nil
            evidence.wall={X=w.X,Y=w.Y,Z=w.Z};evidence.normal={X=n.X,Y=n.Y,Z=n.Z}
            evidence.query_direction=dir;best=evidence
          end
        end
      end
    end
    return best,query_source,profile_name
  end
  -- WASD is diagnostic only; contact/action eligibility uses the actor's facing
  -- and physical wall queries, so left-stick movement needs no extra key gate.
  local function keyboard_input(p)
    local ok,dir,source=pcall(function()
      local controller=p:GetController()
      assert(valid(controller),'controller unavailable')
      local function down(key) return controller:IsInputKeyDown({KeyName=FName(key)}) end
      local forward=(down('W') and 1 or 0)-(down('S') and 1 or 0)
      local right=(down('D') and 1 or 0)-(down('A') and 1 or 0)
      if forward==0 and right==0 then return {X=0,Y=0,Z=0},'none' end
      local angle=controller:GetControlRotation().Yaw
      assert(type(angle)=='number','control yaw unavailable')
      local radians=math.rad(angle)
      local c,s=math.cos(radians),math.sin(radians)
      return {X=forward*c-right*s,Y=forward*s+right*c,Z=0},'keyboard'
    end)
    if not ok then return {X=0,Y=0,Z=0},'unavailable' end
    return dir,source
  end
  local function snapshot()
    local p=H.GetPlayer()
    if not valid(p) then previous_sample=nil;previous_space=nil;return nil end
    local capsule=p.CapsuleComponent
    if not valid(capsule) then previous_sample=nil;previous_space=nil;return nil end
    local q=p:K2_GetActorLocation(); local f=p:GetActorForwardVector()
    local sys=H.GetKismetSystemLibrary()
    local rot=p:K2_GetActorRotation();local velocity=p:GetVelocity();local movement,source=keyboard_input(p)
    local now,pid,wid=H.GetGameplayStatics():GetRealTimeSeconds(p),p:GetFullName(),H.GetWorld():GetFullName()
    local dx,dy,dz,dt=nil,nil,nil,nil
    local continuous=previous_sample and previous_sample.player_id==pid and previous_sample.world_id==wid
      and number(now) and now>previous_sample.time and vector(q)
    if continuous then
      dx=q.X-previous_sample.pos.X;dy=q.Y-previous_sample.pos.Y;dz=q.Z-previous_sample.pos.Z
      dt=now-previous_sample.time
    end
    -- Use the same logical jump as the host, including for grounded query wake-up.
    -- No new bind/timer. First sample/context change is still a baseline.
    local key_ok,space_down=pcall(function()
      local controller=p:GetController();assert(valid(controller),'controller unavailable')
      return jump_input.jump_down(controller)
    end)
    -- Grounded, stationary, key-up idle has no pending airborne interaction.
    -- Never reuse a cached hit. A key/movement/airborne sample queries immediately;
    -- keep queries for 2 seconds after input, including the grounded-double buffer.
    local mode=p.CharacterMovement.MovementMode
    local idle_known=number(now) and vector(velocity) and vector(movement)
      and key_ok and source~='unavailable'
    if not continuous or not contact_activity_until or (previous_sample and now<previous_sample.time) then
      contact_activity_until=number(now) and now+2 or nil
    end
    -- perf4: walking or being moved on the ground no longer counts as activity.
    -- Contact is only consumed on a tick with Space down, in the air, or while the
    -- two-edge gate is pending (at most .40 s after a Space edge on the ground);
    -- all three are inside the conditions below or the 2 s buffer they start.
    local active=not idle_known or mode~=1 or space_down==true
    if active and number(now) then contact_activity_until=now+2 end
    local should_query=active or not contact_activity_until or now<=contact_activity_until
    local wall,query_source,actual_profile=nil,'grounded_idle_no_query',nil
    if should_query then wall,query_source,actual_profile=wall_contact(p,q,f,capsule,sys) end
    if not should_query and not idle_query_reported then
      idle_query_reported=true;pcall(log,'idle_query_perf_20261112 grounded_idle_scans_suspended')
    end
    local contact=wall~=nil
    local key_edge=key_ok and continuous and previous_space==false and space_down==true
    if not key_ok then read_error_once('jump_input',space_down);previous_space=nil
    else previous_space=space_down end
    previous_sample=number(now) and vector(q) and {time=now,player_id=pid,world_id=wid,pos={X=q.X,Y=q.Y,Z=q.Z}} or nil
    if key_edge then
      local function value(v) return number(v) and string.format('%.4f',v) or 'unknown' end
      local n=wall and wall.normal or {};local d=wall and wall.query_direction or {}
      pcall(log,'v12_contact_key source=jump_rising query='..tostring(query_source)..' onhit=false'
        ..' actual_profile='..tostring(actual_profile)..' contact_evidence='..tostring(wall and wall.contact_evidence)
        ..' time='..value(now)..' mode='..tostring(p.CharacterMovement.MovementMode)..' contact='..tostring(contact)
        ..' pos='..value(q.X)..','..value(q.Y)..','..value(q.Z)
        ..' delta='..value(dx)..','..value(dy)..','..value(dz)..' dt='..value(dt)
        ..' velocity='..value(velocity.X)..','..value(velocity.Y)..','..value(velocity.Z)
        ..' wall_normal='..value(n.X)..','..value(n.Y)..','..value(n.Z)
        ..' toward_wall_delta='..value(wall and dx and -(dx*n.X+dy*n.Y))
        ..' toward_wall_velocity='..value(wall and -(velocity.X*n.X+velocity.Y*n.Y))
        ..' component='..tostring(wall and wall.component_id or 'none')
        ..' query_dir='..value(d.X)..','..value(d.Y)..','..value(d.Z)
        ..' pawn_response='..tostring(wall and wall.pawn_response)
        ..' capsule_response='..tostring(wall and wall.capsule_response)
        ..' pawn_type='..tostring(wall and wall.pawn_object_type)
        ..' component_type='..tostring(wall and wall.component_object_type))
    end
    return {time=now,player_id=pid,world_id=wid,dx=dx,dy=dy,dz=dz,dt=dt,
      velocity_z=velocity.Z,
      velocity={X=velocity.X,Y=velocity.Y,Z=velocity.Z},move_input=movement,input_source=source,
      mode=p.CharacterMovement.MovementMode, airborne=p.CharacterMovement.MovementMode==3, grounded=p.CharacterMovement.MovementMode==1, contact=contact,
      wall=wall and wall.wall or nil,wall_normal=wall and wall.normal or nil,
      component_id=wall and wall.component_id or nil,query_direction=wall and wall.query_direction or nil,
      pawn_response=wall and wall.pawn_response or nil,capsule_response=wall and wall.capsule_response or nil,
      pawn_object_type=wall and wall.pawn_object_type or nil,component_object_type=wall and wall.component_object_type or nil,
      query_source=query_source,actual_profile=actual_profile,contact_evidence=wall and wall.contact_evidence or nil,
      toward_wall_velocity=wall and -(velocity.X*wall.normal.X+velocity.Y*wall.normal.Y) or nil,
      toward_wall_displacement=wall and dx and -(dx*wall.normal.X+dy*wall.normal.Y) or nil,
      hit_distance=wall and wall.hit_distance or nil,hit_time=wall and wall.hit_time or nil,
      ground={pos={X=q.X,Y=q.Y,Z=q.Z},forward={X=f.X,Y=f.Y,Z=f.Z},
        rotation={Pitch=rot.Pitch,Yaw=rot.Yaw,Roll=rot.Roll}}}
  end
  local function action(initial,s)
    if not initial or not s.contact or not s.wall then return false,'lost wall or initial position' end
    local p=H.GetPlayer();assert(valid(p) and p:GetFullName()==s.player_id,'player changed')
    local mode=p.CharacterMovement.MovementMode
    local ground_push=mode==1 and s.trigger_kind=='ground_push_double' and s.contact
    if mode~=3 and not ground_push then return false,'not airborne or contact ground double' end
    if valid(p.PBZInteract.CurrentInteractActor) then return false,'existing interaction' end
    local cap=p.CapsuleComponent;assert(valid(cap),'capsule unavailable')
    local sys=H.GetKismetSystemLibrary();local world=H.GetWorld();assert(valid(world),'world unavailable')
    local n=s.wall_normal
    if not vector(n) or math.abs(n.Z)>=.66 then return false,'invalid wall normal' end
    local length=math.sqrt(n.X*n.X+n.Y*n.Y)
    if length<.1 then return false,'invalid horizontal wall normal' end
    local L,F,w=initial.pos,{X=-n.X/length,Y=-n.Y/length,Z=0},s.wall
    local target_rotation={Pitch=0,Yaw=math.deg(math.atan(F.Y,F.X)),Roll=0}
    local current=s.ground.pos
    local half,radius=cap:GetScaledCapsuleHalfHeight(),cap:GetScaledCapsuleRadius()
    if (current.X-w.X)^2+(current.Y-w.Y)^2>(radius+40)^2 then return false,'wall contact too far from current capsule' end
    -- User-selected simple mode: contact and two jump edges are sufficient.
    -- Do not require a reachable top, landing platform or a clear full ascent.
    -- Keep the previously observed Low_RunStart target parameters fixed.
    local floor=L.Z-half
    local height=options.short_height or 280
    assert(height>=150 and height<=450,'invalid short target height')
    -- A falling pawn can still be ending another special move. Never move its
    -- currently referenced volume even if that field is only a stale cache.
    local read_ok,current_volume=pcall(function() return p.SpecialMove.CurrentSpecialMoveVolume end)
    if not read_ok then return false,'cannot inspect current special-move volume' end
    local current_name=valid(current_volume) and current_volume:GetFullName() or nil
    local context_id=world:GetFullName()..'|'..p:GetFullName()
    if context~=context_id then pool={};context=context_id;shared.perf4_components=nil;persist() end
    -- perf4: `available` is only ever read with pooled names. Resolve those by exact
    -- path. If any is not found that way, enumerate the class exactly as before; a
    -- pooled actor that enumeration finds but the path missed turns the path form off.
    local available={}
    local direct=shared.perf4_actor_path_off~=true
    if direct then
      for _,pooled in ipairs(pool) do
        local path=type(pooled.name)=='string' and pooled.name:match('^BP_SpecialMove_UpRunning_C (.+)$')
        local found,o=false,nil
        if path then found,o=pcall(StaticFindObject,path) end
        if found and valid(o) and o:GetFullName()==pooled.name then available[pooled.name]=o else direct=false end
      end
    end
    if not direct then
      local by_path=available;available={}
      for _,candidate in ipairs(FindAllOf('BP_SpecialMove_UpRunning_C') or {}) do
        if valid(candidate) then available[candidate:GetFullName()]=candidate end
      end
      if shared.perf4_actor_path_off~=true then
        for _,pooled in ipairs(pool) do
          if available[pooled.name] and not by_path[pooled.name] then
            shared.perf4_actor_path_off=true;log('perf4_short_lookup actor_path_off; using enumeration');break
          end
        end
      end
    end
    local live={}
    for _,entry in ipairs(pool) do
      if available[entry.name] then live[#live+1]=entry end
    end
    pool=live;persist()
    local actor,entry=nil,nil
    for _,candidate in ipairs(pool) do
      if not candidate.quarantined and candidate.name~=current_name then
        actor=available[candidate.name];entry=candidate;break
      end
    end
    local newly_spawned=false
    if not actor then
      if #pool>=2 then return false,'no unused temporary actor available' end
      local class=StaticFindObject('/Game/RenewalContent/Actors/SpecialMove/Volume/BP_SpecialMove_UpRunning.BP_SpecialMove_UpRunning_C')
      -- Streaming/GC may remove this asset between the idle preload and input.
      -- No actor has been spawned or native action dispatched yet: reject only
      -- this attempt. The idle loader can prepare it after landing.
      if not valid(class) then return false,'short_asset_not_ready' end
      actor=world:SpawnActor(class,{X=w.X,Y=w.Y,Z=floor+50000},target_rotation)
      assert(valid(actor),'spawn failed')
      entry={name=actor:GetFullName(),quarantined=false};pool[#pool+1]=entry;persist()
      newly_spawned=true
    end
    local ok,err=pcall(function()
      local box=nil;local name=actor:GetFullName()
      -- perf4: the components of this mod-owned actor are remembered by exact full name
      -- from the previous use of the same actor. Names only: every use resolves again
      -- and re-checks name and owner. First use enumerates as before; the second use
      -- enumerates and must agree with the record; later uses resolve by path. Any
      -- disagreement turns this off for the session and the enumeration is used.
      -- The widget pass after HandleOnInteract always enumerates, as before.
      if type(shared.perf4_components)~='table' then shared.perf4_components={} end
      local record=shared.perf4_components[name]
      local trusted=shared.perf4_components_off==nil and type(record)=='table' and record.verified==true
      local function owned(full)
        local path=type(full)=='string' and full:match('^%S+ (.+)$');assert(path,'recorded name malformed')
        local c=StaticFindObject(path);assert(valid(c) and c:GetFullName()==full,'recorded component not found')
        local owner=c:GetOwner();assert(valid(owner) and owner:GetFullName()==name,'recorded component owner changed')
        return c
      end
      local function distrust(why)
        trusted=false;shared.perf4_components_off=tostring(why);log('perf4_short_lookup components_off reason='..tostring(why))
      end
      if trusted then
        local found,c=pcall(owned,record.box)
        if found and c:GetFullName():find('.BoxA',1,true) then box=c else distrust('box '..tostring(c)) end
      end
      if not box then
        for _,c in ipairs(FindAllOf('BoxComponent') or {}) do
          if valid(c) then local owner=c:GetOwner();if valid(owner) and owner:GetFullName()==name and c:GetFullName():find('.BoxA',1,true) then box=c;break end end
        end
      end
      assert(valid(box),'interaction box unavailable')
      box:SetGenerateOverlapEvents(false);box:SetCollisionEnabled(0)
      assert(box:GetCollisionEnabled()==0,'interaction box still active')
      local pre,pre_done={},false
      if trusted then
        local resolved={}
        local found,why=pcall(function() for i,full in ipairs(record.widgets) do resolved[i]=owned(full) end end)
        if found then for _,c in ipairs(resolved) do c:SetVisibility(false,true) end;pre_done=true
        else distrust('widget '..tostring(why)) end
      end
      if not pre_done then
        for _,c in ipairs(FindAllOf('WidgetComponent') or {}) do
          if valid(c) then local owner=c:GetOwner();if valid(owner) and owner:GetFullName()==name then c:SetVisibility(false,true);pre[#pre+1]=c:GetFullName() end end
        end
      end
      do -- move only after disabling the temporary actor's interaction box
        local out={}
        actor:K2_SetActorLocation({X=w.X,Y=w.Y,Z=floor},false,out,true)
        actor:K2_SetActorRotation(target_rotation,true)
        local actual=actor:K2_GetActorLocation()
        assert((actual.X-w.X)^2+(actual.Y-w.Y)^2+(actual.Z-floor)^2<1,'temporary actor failed to move')
        local rotation=actor:K2_GetActorRotation()
        local delta=(rotation.Yaw-target_rotation.Yaw+180)%360-180
        assert(math.abs(delta)<1,'temporary actor failed to rotate')
      end
      local spline=actor.EdgeSplineComponent
      assert(valid(spline) and spline:GetNumberOfSplinePoints()==3,'unexpected spline')
      local mid=spline:GetLocationAtSplinePoint(1,1);local edge={X=w.X-F.X*25,Y=w.Y-F.Y*25,Z=floor+height}
      actor.UpRunningTargetHeight=height
      for i=0,2 do
        local v=spline:GetLocationAtSplinePoint(i,1)
        spline:SetLocationAtSplinePoint(i,{X=v.X+edge.X-mid.X,Y=v.Y+edge.Y-mid.Y,Z=v.Z+edge.Z-mid.Z},1,false)
      end
      spline:UpdateSpline()
      local input=s.move_input or {X=0,Y=0,Z=0}
      local velocity=s.velocity or {X=0,Y=0,Z=0}
      local normal=s.wall_normal or {X=0,Y=0,Z=0}
      log('temporary_actor='..name..' reused='..tostring(not newly_spawned)..' pool_size='..#pool)
      log(string.format('action_begin height=%.1f landing=%s wall=%.1f,%.1f,%.1f origin=%.1f,%.1f,%.1f contact=%s normal=%.3f,%.3f,%.3f velocity=%.1f,%.1f,%.1f input_source=%s input=%.3f,%.3f,%.3f hit_distance=%s hit_time=%s',height,'unchecked',w.X,w.Y,w.Z,L.X,L.Y,L.Z,tostring(s.contact),normal.X,normal.Y,normal.Z,velocity.X,velocity.Y,velocity.Z,tostring(s.input_source),input.X,input.Y,input.Z,tostring(s.hit_distance),tostring(s.hit_time)))
      -- Arm selection only for this mod-owned interaction. The selector changes
      -- one matching timeline call, never global templates or montage assets.
      if selector then selector.begin(actor,p,s.time) end
      actor:HandleOnInteract(p)
      -- The game may re-show this temporary actor's interaction component.
      -- Restrict the override to UI owned by the newly spawned actor.
      local post={}
      for _,c in ipairs(FindAllOf('WidgetComponent') or {}) do
        local uiok,uierr=pcall(function()
          if not valid(c) then return end
          local owner=c:GetOwner()
          if not valid(owner) or owner:GetFullName()~=name then return end
          c:SetVisibility(false,true);post[#post+1]=c:GetFullName()
          local user=c:GetUserWidgetObject()
          if valid(user) then user:SetRenderOpacity(0);log('temporary_widget_opacity=0') end
        end)
        if not uiok then log('temporary_widget_error='..tostring(uierr)) end
      end
      if shared.perf4_components_off==nil then
        local function same(a,b)
          if type(a)~='table' or #a~=#b then return false end
          for i=1,#a do if a[i]~=b[i] then return false end end
          return true
        end
        local box_full=box:GetFullName()
        if not trusted and type(record)=='table' then
          if record.box==box_full and same(record.widgets,pre) then
            record.verified=true;log('perf4_short_lookup verified widgets='..#pre..' actor='..name)
          else distrust('second use of the actor differs from the first') end
        end
        if shared.perf4_components_off==nil then
          if type(record)~='table' then record={verified=false} end
          record.box=box_full;record.widgets=post;shared.perf4_components[name]=record
        end
      end
    end)
    if not ok then
      -- Don't destroy objects potentially retained by game interaction state.
      -- Failed setup/interaction is quarantined until it unloads.
      entry.quarantined=true;persist()
      error(err)
    end
    -- Do not destroy the actor while the game may still reference it.
    return true,{player_id=s.player_id,world_id=world:GetFullName(),owned_volume_id=entry.name,
      time=s.time,wall=s.wall,wall_normal=s.wall_normal,height=height}
  end

  -- v16.1 hold-only query helpers. Neither retains UObject references nor
  -- changes collision. Ignore lists are ephemeral caller-owned return values.
  local function object_world_id(object)
    local current=object
    for _=1,32 do
      if not valid(current) then return nil,'outer chain ended before World' end
      local name=current:GetFullName()
      assert(type(name)=='string','outer identity unavailable')
      if name:sub(1,6)=='World ' then return name end
      current=current:GetOuter()
    end
    return nil,'outer chain exceeded bound'
  end
  local function checked_identity(s)
    assert(type(s)=='table' and type(s.player_id)=='string' and type(s.world_id)=='string',
      'sample identity unavailable')
    local p,w=H.GetPlayer(),H.GetWorld()
    assert(valid(p) and valid(w),'player/world unavailable')
    assert(p:GetFullName()==s.player_id and w:GetFullName()==s.world_id,'player/world identity changed')
    local pid,why=object_world_id(p)
    assert(pid==s.world_id,'player outer world changed: '..tostring(why or pid))
    return p,w
  end
  local function build_spline_ignore_list(s)
    local ok,ignored=pcall(function()
      checked_identity(s)
      -- Official FindAllOf: nil means no non-default instances. Exceptions and
      -- unsupported return types are not equivalent to an empty enumeration.
      local enum_ok,actors=pcall(FindAllOf,'BP_SplineWall_C')
      assert(enum_ok,'spline enumeration failed: '..tostring(actors))
      assert(actors==nil or type(actors)=='table','spline enumeration returned unsupported type')
      local list={}
      if actors then
        for k,actor in pairs(actors) do
          assert(type(k)=='number' and k>=1 and k%1==0,'spline enumeration returned invalid index')
          local checked,alive=pcall(function() return actor and actor:IsValid() end)
          assert(checked,'spline actor validity unreadable')
          if alive then
            -- World Partition cell outer packages can have their own World;
            -- the live world's identity is the actor Level's OwningWorld.
            local level=actor:GetLevel();assert(valid(level),'spline actor world unavailable: level')
            local owner_world=level.OwningWorld;assert(valid(owner_world),'spline actor world unavailable: OwningWorld')
            local wid=owner_world:GetFullName();assert(type(wid)=='string' and wid~='','spline actor world unavailable: identity')
            if wid==s.world_id then list[#list+1]=actor end
          end
        end
      end
      checked_identity(s)
      return list
    end)
    if not ok then
      read_error_once('spline_ignore_list',ignored)
      return nil,'spline_ignore_unavailable: '..tostring(ignored)
    end
    return ignored,nil
  end
  local function recheck_solid_contact(s)
    local ok,updated,reason,ignored=pcall(function()
      local function identity() return checked_identity(s) end
      local p=identity();local cap=p.CapsuleComponent
      assert(valid(cap),'capsule unavailable')
      local q,f=p:K2_GetActorLocation(),p:GetActorForwardVector()
      assert(vector(q) and vector(f),'player geometry unavailable')
      local flen=math.sqrt(f.X*f.X+f.Y*f.Y)
      assert(flen>=.01,'player horizontal forward unavailable')
      local fx,fy=f.X/flen,f.Y/flen
      local cr,ch=cap:GetScaledCapsuleRadius(),cap:GetScaledCapsuleHalfHeight()
      assert(number(cr) and number(ch) and cr>0 and ch>0,'capsule size unavailable')
      local radius,half=math.max(cr-2,1),math.max(ch-10,1)
      local profile_ok,profile,profile_name=pcall(function()
        local value=cap:GetCollisionProfileName();local name=value:ToString()
        assert(type(name)=='string' and name~='','capsule profile name unreadable')
        return value,name
      end)
      if not profile_ok then read_error_once('capsule_profile',profile);profile=nil;profile_name='unavailable' end
      local use_profile=profile_ok and profile_name:lower()~='custom' and profile_name:lower()~='none'
      local query_source=use_profile and 'CapsuleTraceSingleByProfile/actual_capsule_profile/front_semicircle'
        or 'CapsuleTraceSingle/channel0/front_semicircle'
      local ignore,why=build_spline_ignore_list(s)
      assert(ignore,why)
      identity()
      local sys=H.GetKismetSystemLibrary();assert(valid(sys),'query library unavailable')
      local best=nil
      for _,degrees in ipairs({0,-45,45,-90,90}) do
        local angle=math.rad(degrees);local c,sine=math.cos(angle),math.sin(angle)
        local dir={X=fx*c-fy*sine,Y=fx*sine+fy*c,Z=0};local hit={}
        local dest={X=q.X+dir.X*8,Y=q.Y+dir.Y*8,Z=q.Z}
        local yes
        if use_profile then
          yes=sys:CapsuleTraceSingleByProfile(p,q,dest,radius,half,profile,false,ignore,0,hit,true,color,color,0)
        else
          yes=sys:CapsuleTraceSingle(p,q,dest,radius,half,0,false,ignore,0,hit,true,color,color,0)
        end
        local n,w=hit.ImpactNormal,hit.ImpactPoint
        local blocking=hit.bBlockingHit==nil or hit.bBlockingHit==true or hit.bBlockingHit==1
        if yes and blocking and vector(n) and vector(w) and math.abs(n.Z)<.66
          and n.X*fx+n.Y*fy<=.25 and n.X*n.X+n.Y*n.Y>.01 then
          local evidence,status=blocking_component(hit,cap)
          if not evidence and status=='unavailable' then
            evidence={component_id='unresolved',contact_evidence=use_profile
              and 'native_actual_profile_blocking_hit' or 'channel0_spatial_hit_unverified_pawn_response'}
          end
          if evidence then
            local distance=number(hit.Distance) and hit.Distance>=0 and hit.Distance or nil
            if not distance and number(hit.Time) and hit.Time>=0 and hit.Time<=1 then distance=hit.Time*8 end
            if not distance then distance=math.sqrt((w.X-q.X)^2+(w.Y-q.Y)^2+(w.Z-q.Z)^2) end
            if not best or distance<best.distance then
              evidence.distance=distance;evidence.hit_distance=number(hit.Distance) and hit.Distance or nil
              evidence.hit_time=number(hit.Time) and hit.Time or nil
              evidence.wall={X=w.X,Y=w.Y,Z=w.Z};evidence.normal={X=n.X,Y=n.Y,Z=n.Z}
              evidence.query_direction=dir;best=evidence
            end
          end
        end
      end
      identity()
      if not best then return nil,'no_non_spline_wall_contact',nil end
      local function copy(value,depth)
        local t=type(value)
        if t=='nil' or t=='number' or t=='string' or t=='boolean' then return value end
        assert(t=='table' and depth<16,'snapshot must contain only bounded scalar tables')
        local result={}
        for k,v in pairs(value) do
          assert(type(k)=='number' or type(k)=='string','invalid snapshot key')
          result[k]=copy(v,depth+1)
        end
        return result
      end
      local out=copy(s,0)
      local rot,velocity=p:K2_GetActorRotation(),p:GetVelocity()
      assert(number(rot.Pitch) and number(rot.Yaw) and number(rot.Roll) and vector(velocity),'player state unavailable')
      local now=H.GetGameplayStatics():GetRealTimeSeconds(p)
      assert(number(now) and (not number(s.time) or now>=s.time),'sample clock changed')
      local mode=p.CharacterMovement.MovementMode
      assert(number(mode),'movement mode unavailable')
      local movement,source=keyboard_input(p)
      out.time=now;out.mode=mode;out.airborne=mode==3;out.grounded=mode==1
      out.velocity={X=velocity.X,Y=velocity.Y,Z=velocity.Z};out.velocity_z=velocity.Z
      out.move_input=movement;out.input_source=source
      out.ground={pos={X=q.X,Y=q.Y,Z=q.Z},forward={X=f.X,Y=f.Y,Z=f.Z},
        rotation={Pitch=rot.Pitch,Yaw=rot.Yaw,Roll=rot.Roll}}
      out.contact=true;out.wall=best.wall;out.wall_normal=best.normal
      out.component_id=best.component_id;out.query_direction=best.query_direction
      out.pawn_response=best.pawn_response;out.capsule_response=best.capsule_response
      out.pawn_object_type=best.pawn_object_type;out.component_object_type=best.component_object_type
      out.hit_distance=best.hit_distance;out.hit_time=best.hit_time
      out.query_source=query_source..'/excluding_BP_SplineWall_C'
      out.actual_profile=profile_name;out.contact_evidence=best.contact_evidence
      out.toward_wall_velocity=-(velocity.X*best.normal.X+velocity.Y*best.normal.Y)
      -- No previous_sample/key-edge mutation. Old displacement does not describe
      -- this recheck's newly read origin and is deliberately not reinterpreted.
      out.dx=nil;out.dy=nil;out.dz=nil;out.dt=nil;out.toward_wall_displacement=nil
      out.solid_contact_rechecked=true;out.spline_walls_excluded=true;out.ignored_spline_count=#ignore
      out.source_sample_time=s.time
      pcall(log,'v16_1_hold_solid_recheck query='..out.query_source..' actual_profile='..tostring(profile_name)
        ..' ignored_spline_count='..#ignore..' contact_evidence='..tostring(out.contact_evidence)
        ..' component='..tostring(out.component_id)..' pawn_response='..tostring(out.pawn_response)
        ..' capsule_response='..tostring(out.capsule_response))
      identity()
      return out,nil,ignore
    end)
    if not ok then
      read_error_once('hold_solid_recheck',updated)
      return nil,'solid_contact_unavailable: '..tostring(updated),nil
    end
    return updated,reason,ignored
  end

  return {sample=snapshot,start_action=action,log=log,recheck_solid_contact=recheck_solid_contact,build_spline_ignore_list=build_spline_ignore_list}
end
return M
