-- Read-only, one-shot existing-game-thread geometry collection; no drawing,
-- setters, asset loads, spawn, hooks, timers, file IO, or UObject cache.
-- Actual reflected convex topology only. Bounds are solely the 30m broadphase.
local MAX_ENUM,MAX_REGIONS,MAX_VERTICES,MAX_INDICES,MAX_EDGES=600,8,2048,8192,8192
local EFFECTS={
 ['BlueprintGeneratedClass /Game/PBZContent/Blueprint/Ability/GameplayEffects/GE_Kill.GE_Kill_C']=true}

local function finite(x)return type(x)=='number'and x==x and math.abs(x)<math.huge end
local function integer(x,lo,hi)return finite(x)and x%1==0 and x>=lo and x<=hi end
local function valid(o)local ok,v=pcall(function()return o and o:IsValid()end);return ok and v==true end
local function name(o)assert(valid(o),'invalid object');local n=o:GetFullName();assert(type(n)=='string'and n~='','unknown name');return n end
local function addr(o)local a=o:GetAddress();assert(integer(a,1,9007199254740991),'unknown address');return string.format('%.0f',a)end
local function vector(v)assert(v and finite(v.X)and finite(v.Y)and finite(v.Z),'unknown vector');return {X=v.X,Y=v.Y,Z=v.Z}end
local function transform(t)
 assert(t,'unknown transform');local q=t.Rotation;assert(q and finite(q.X)and finite(q.Y)and finite(q.Z)and finite(q.W),'unknown quaternion')
 return {Translation=vector(t.Translation),Scale3D=vector(t.Scale3D),Rotation={X=q.X,Y=q.Y,Z=q.Z,W=q.W}}
end
local function dense(a,limit)
 assert(type(a)=='table','unknown list');local n,m=0,0
 for k in next,a do assert(integer(k,1,limit),'invalid or over-limit list key');n=n+1;m=math.max(m,k)end
 assert(n==m and n<=limit,'sparse or over-limit list');return n
end
local function array(a,limit,decode)
 assert(a~=nil,'unknown array');local ok,n=pcall(function()return a:GetArrayNum()end);local out={}
 if ok then
  assert(integer(n,0,limit),'array over limit or unknown count');local count=0
  a:ForEach(function(_,ref)
   count=count+1;assert(count<=n,'array changed while reading')
   local wrapped,value=pcall(function()return ref:get()end)
   out[count]=decode(wrapped and value or ref)
  end)
  assert(count==n,'incomplete array');return out
 end
 n=dense(a,limit);for i=1,n do out[i]=decode(a[i])end;return out
end
local function owningworld(a)local l=a:GetLevel();assert(valid(l),'unknown Level');return name(l.OwningWorld),addr(l.OwningWorld)end
local function bounds(a)
 local o,e={X=0/0,Y=0/0,Z=0/0},{X=0/0,Y=0/0,Z=0/0};a:GetActorBounds(false,o,e,false);o,e=vector(o),vector(e)
 assert(e.X>=0 and e.Y>=0 and e.Z>=0,'negative extent');return {origin=o,extent=e}
end
local function distance(p,b)local s=0;for _,k in ipairs({'X','Y','Z'})do local d=math.max(0,math.abs(p[k]-b.origin[k])-b.extent[k]);s=s+d*d end;return math.sqrt(s)end
local function errtext(e)return tostring(e):gsub('[\r\n]',' '):sub(1,300)end

return function(H,log)
 local report={version='death_volume_geometry_v1',read_only=true,scan_finished=false,data_complete=false,truncated=false,
  regions={},errors={},total_edges=0,radius_cm=3000,scan_scope='loaded_exact_PBZGEVolume_GE_Kill_only',
  geometry_semantics='reflected_BrushBodySetup_convex_triangle_edges_not_AABB_not_live_Chaos_validation',
  counts={enumerated=0,same_world=0,effect_match=0,nearby=0,ready=0,unsupported=0,unknown=0}}
 local function emit(s)pcall(log or function()end,'death_volume_geometry_v1 '..s)end
 local ok,why=pcall(function()
  local p,w=H.GetPlayer(),H.GetWorld();local pid,wid,pa,wa=name(p),name(w),addr(p),addr(w)
  -- This collector is synchronous and read-only. Keep local references only
  -- for this call; validate them per row, and reacquire current player/world
  -- before publishing. Avoid four global controller searches for each actor.
  local function identity(fresh)
   assert(name(p)==pid and addr(p)==pa and name(w)==wid and addr(w)==wa,'captured identity changed')
   if fresh then
    local current_p,current_w=H.GetPlayer(),H.GetWorld()
    assert(name(current_p)==pid and addr(current_p)==pa and name(current_w)==wid and addr(current_w)==wa,'identity changed')
   end
   local pw,pwa=owningworld(p);assert(pw==wid and pwa==wa,'player owning World mismatch')
  end
  identity(true);report.world_id=wid;report.player_id=pid;report.position=vector(p:K2_GetActorLocation())
  local cap=p.CapsuleComponent;assert(valid(cap)and name(cap:GetOwner())==pid and addr(cap:GetOwner())==pa,'unknown capsule owner')
  local channel=cap:GetCollisionObjectType();assert(integer(channel,0,31),'unknown capsule channel');report.player_channel=channel
  local mathlib=H.GetKismetMathLibrary();assert(valid(mathlib),'KismetMathLibrary unavailable')
  local actors=FindAllOf('PBZGEVolume');local n=dense(actors,MAX_ENUM);report.counts.enumerated=n
  local candidates,seen={},{}
  for i=1,n do
   identity();local a=actors[i]
   local aok,ae=pcall(function()
    local id=name(a);assert(not seen[id],'duplicate actor');seen[id]=true
    local c=a:GetClass();assert(c:GetFName():ToString()=='PBZGEVolume','non-exact PBZGEVolume class')
    local aw,awa=owningworld(a);if aw~=wid or awa~=wa then return end
    report.counts.same_world=report.counts.same_world+1
    local effect=name(a.GEClass);if not EFFECTS[effect]then return end
    report.counts.effect_match=report.counts.effect_match+1
    local b=bounds(a);local d=distance(report.position,b);if d>3000 then return end
    report.counts.nearby=report.counts.nearby+1;candidates[#candidates+1]={actor=a,id=id,effect=effect,bounds=b,distance_cm=d}
   end)
   if not aok then report.errors[#report.errors+1]={stage='enumerate',index=i,reason=errtext(ae)}end
  end
  table.sort(candidates,function(a,b)if a.distance_cm==b.distance_cm then return a.id<b.id end;return a.distance_cm<b.distance_cm end)
  if #candidates>MAX_REGIONS then report.truncated=true end
  for i=1,math.min(#candidates,MAX_REGIONS)do
   identity();local cand=candidates[i];local a=cand.actor
   local row={id=cand.id,effect=cand.effect,bounds=cand.bounds,distance_cm=cand.distance_cm,status='unknown',convexes={},
    triangle_index_base=0,edge_index_base=1,collision_enabled='unknown',player_response='unknown'}
   report.regions[#report.regions+1]=row
   local gok,ge=pcall(function()
    local brush=a.BrushComponent;assert(valid(brush)and name(brush:GetOwner())==cand.id and addr(brush:GetOwner())==addr(a),'unknown Brush ownership')
    assert(brush:GetClass():GetFName():ToString()=='BrushComponent','non-exact Brush class');row.brush_id=name(brush)
    local body=brush.BrushBodySetup;row.body_id=name(body)
    local tf=brush:K2_GetComponentToWorld();local tfok,tfc=pcall(transform,tf)
    row.component_transform=tfok and tfc or 'unknown'
    row.build_scale=vector(body.BuildScale3D)
    assert(math.abs(row.build_scale.X-1)<1e-6 and math.abs(row.build_scale.Y-1)<1e-6 and math.abs(row.build_scale.Z-1)<1e-6,'unsupported non-unit BuildScale3D requires native cooking-scale validation')
    local flag=body.CollisionTraceFlag;assert(integer(flag,0,3),'unknown CollisionTraceFlag');row.collision_trace_flag=flag
    assert(flag~=3,'unsupported ComplexAsSimple: convex data is not selected actual collision')
    local en=brush:GetCollisionEnabled();local rp=brush:GetCollisionResponseToChannel(channel)
    assert(integer(en,0,5)and integer(rp,0,2),'unknown component collision response');row.collision_enabled=en;row.player_response=rp
    local vertex_count,index_count,edge_count=0,0,0;row.raw_convexes={}
    row.convexes=array(body.AggGeom.ConvexElems,128,function(elem)
     local localtf=elem.Transform;local lok,ltc=pcall(transform,localtf)
     local item={transform=lok and ltc or 'unknown',source_vertices={},world_vertices={},triangle_indices={},edges={}}
     row.raw_convexes[#row.raw_convexes+1]=item
     item.source_vertices=array(elem.VertexData,MAX_VERTICES-vertex_count,vector);vertex_count=vertex_count+#item.source_vertices
     assert(#item.source_vertices>=4,'unsupported empty/incomplete convex VertexData')
     item.triangle_indices=array(elem.IndexData,MAX_INDICES-index_count,function(v)assert(integer(v,0,#item.source_vertices-1),'invalid triangle index');return v end)
     index_count=index_count+#item.triangle_indices
     assert(#item.triangle_indices>=12 and #item.triangle_indices%3==0,'unsupported empty/incomplete triangle IndexData')
     assert(tfok and lok,'unknown transform primitive fields; raw local geometry retained only')
     -- UE performs both transform applications; no manual Euler/quaternion guess.
     for vi,v in ipairs(item.source_vertices)do
      local cv=vector(mathlib:TransformLocation(localtf,v));item.world_vertices[vi]=vector(mathlib:TransformLocation(tf,cv))
     end
     local edges={}
     for j=1,#item.triangle_indices,3 do
      local x,y,z=item.triangle_indices[j]+1,item.triangle_indices[j+1]+1,item.triangle_indices[j+2]+1
      assert(x~=y and y~=z and z~=x,'unsupported degenerate triangle')
      for _,pair in ipairs({{x,y},{y,z},{z,x}})do
       local lo,hi=math.min(pair[1],pair[2]),math.max(pair[1],pair[2]);local key=lo..':'..hi
       if not edges[key]then edges[key]=true;edge_count=edge_count+1
        assert(report.total_edges+edge_count<=MAX_EDGES,'total edge limit exceeded');item.edges[#item.edges+1]={lo,hi}
       end
      end
     end
     return item
    end)
    assert(#row.convexes>0,'unsupported no convex geometry; AABB not substituted')
    identity();row.vertex_count=vertex_count;row.index_count=index_count;row.edge_count=edge_count
    row.status='geometry_ready';row.raw_convexes=nil;report.total_edges=report.total_edges+edge_count
   end)
   if not gok then
    row.reason=errtext(ge);row.status=(row.reason:find('unsupported',1,true)or row.reason:find('limit',1,true))and'unsupported'or'unknown'
    if row.reason:find('limit',1,true)then report.truncated=true end
    -- Partial extraction is not eligible for display as a complete collision volume.
    row.convexes={};report.errors[#report.errors+1]={stage='geometry',id=row.id,reason=row.reason}
   end
   if row.status=='geometry_ready'then report.counts.ready=report.counts.ready+1 else report.counts[row.status]=report.counts[row.status]+1 end
   emit('region status='..row.status..' id='..row.id..' edges='..tostring(row.edge_count or 0)..' reason='..tostring(row.reason or 'none'))
  end
  identity(true);report.scan_finished=true;report.data_complete=#report.errors==0 and not report.truncated
 end)
 if not ok then report.abort_reason=errtext(why);report.errors[#report.errors+1]={stage='snapshot',reason=report.abort_reason}end
 emit('summary scan_finished='..tostring(report.scan_finished)..' data_complete='..tostring(report.data_complete)..' ready='..report.counts.ready..' edges='..report.total_edges..' truncated='..tostring(report.truncated))
 return report
end
