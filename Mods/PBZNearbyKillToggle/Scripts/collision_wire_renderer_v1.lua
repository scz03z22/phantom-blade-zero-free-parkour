-- One bounded procedural display actor; invoke only on the existing game thread.
-- NEW DISPLAY GEOMETRY ONLY, not a detector and not game collision geometry.
-- No hooks, loops, shared cache, file IO, or changes to existing game objects.
-- segments: dense Lua list {{a={X,Y,Z},b={X,Y,Z}}, ...}, world coordinates.
-- options: {anchor=FVector, width_cm=1.5, lifespan_seconds=180}; max 1800 seconds.
local BASIC='/Engine/BasicShapes/BasicShapeMaterial.BasicShapeMaterial'
local DEFAULT='/Engine/EngineMaterials/DefaultMaterial.DefaultMaterial'
local EMISSIVE='/Engine/ArtTools/RenderToTexture/Materials/Debug/M_Emissive_Color.M_Emissive_Color'
local function finite(x)return type(x)=='number'and x==x and math.abs(x)<math.huge end
local function valid(o)local ok,v=pcall(function()return o and o:IsValid()end);return ok and v==true end
local function name(o)assert(valid(o),'invalid object');local n=o:GetFullName();assert(type(n)=='string'and n~='','unknown name');return n end
local function address(o)local a=o:GetAddress();assert(finite(a)and a>0,'unknown object address');return string.format('%.0f',a)end
local function vec(v)assert(v and finite(v.X)and finite(v.Y)and finite(v.Z),'nonfinite/unknown vector');return {X=v.X,Y=v.Y,Z=v.Z}end
local function add(a,b)return {X=a.X+b.X,Y=a.Y+b.Y,Z=a.Z+b.Z}end
local function sub(a,b)return {X=a.X-b.X,Y=a.Y-b.Y,Z=a.Z-b.Z}end
local function scale(a,t)return {X=a.X*t,Y=a.Y*t,Z=a.Z*t}end
local function dot(a,b)return a.X*b.X+a.Y*b.Y+a.Z*b.Z end
local function cross(a,b)return {X=a.Y*b.Z-a.Z*b.Y,Y=a.Z*b.X-a.X*b.Z,Z=a.X*b.Y-a.Y*b.X}end
local function unit(v)local n=math.sqrt(dot(v,v));assert(finite(n)and n>1e-8,'degenerate direction');return scale(v,1/n),n end
local function dense(a)
 assert(type(a)=='table','segments must be a dense Lua list');local n,m=0,0
 for k in next,a do assert(type(k)=='number'and k%1==0 and k>=1 and k<=1000,'segment count/key exceeds cap');n=n+1;m=math.max(m,k)end
 assert(n==m and n>=1 and n<=1000,'empty/sparse/oversize segments');return n
end
local function world_of(a)local l=a:GetLevel();assert(valid(l),'unknown actor Level');return name(l.OwningWorld),address(l.OwningWorld)end
local function message(e)return tostring(e):gsub('[\r\n]',' '):sub(1,300)end

return function(H,log,segments,options)
 local out={version='collision_wire_renderer_v1',ok=false,status='rejected',display_geometry_only=true,
  source_interpretation='caller_supplied_segments_not_verified_collision',lifespan_seconds=180,
  color_mode='default_lit_material_color_unverified',errors={}}
 local actor,actor_id,actor_address
 local function emit()pcall(log or function()end,'collision_wire_renderer_v1 status='..out.status..' actor='..tostring(out.actor_id or 'none')..' segments='..tostring(out.segment_count or 0)..' reason='..tostring(out.reason or 'none'))end
 local ok,why=pcall(function()
  options=options or {};assert(type(options)=='table','invalid options')
  local lifetime=options.lifespan_seconds or 180;assert(finite(lifetime)and lifetime>=30 and lifetime<=1800,'lifespan outside 30..1800 seconds');out.lifespan_seconds=lifetime
  local width=options.width_cm or 1.5;assert(finite(width)and width>=1 and width<=2,'width outside 1..2cm')
  local tint=options.color
  if tint then
   for _,k in ipairs({'R','G','B','A'})do assert(finite(tint[k])and tint[k]>=0 and tint[k]<=1,'invalid tint')end
  end
  local n=dense(segments);local p,w=H.GetPlayer(),H.GetWorld();local pid,wid,pa,wa=name(p),name(w),address(p),address(w)
  local function identity()
   assert(name(H.GetPlayer())==pid and address(H.GetPlayer())==pa and name(H.GetWorld())==wid and address(H.GetWorld())==wa,'player/World identity changed')
   local pw,pwa=world_of(p);assert(pw==wid and pwa==wa,'player owning World mismatch')
  end
  identity();local anchor=vec(options.anchor or p:K2_GetActorLocation());out.anchor=anchor;out.world_id=wid;out.width_cm=width;out.segment_count=n
  local vertices,triangles,normals,uv,colors={},{},{},{},{}
  local function face(corners,indices,normal)
   local base=#vertices
   for i,j in ipairs(indices)do vertices[#vertices+1]=corners[j];normals[#normals+1]=vec(normal);uv[#uv+1]={X=(i==2 or i==3)and 1 or 0,Y=i>=3 and 1 or 0};colors[#colors+1]={R=255,G=255,B=255,A=255}end
   for _,v in ipairs({0,1,2,0,2,3})do triangles[#triangles+1]=base+v end
  end
  -- Validate and build the entire bounded batch before creating any Unreal object.
  for i=1,n do
   local s=segments[i];assert(type(s)=='table','invalid segment');local a,b=sub(vec(s.a),anchor),sub(vec(s.b),anchor)
   assert(dot(a,a)<=100000^2 and dot(b,b)<=100000^2,'endpoint exceeds 1km anchor bound')
   local d,len=unit(sub(b,a));assert(len>=0.1,'segment shorter than 0.1cm')
   local ref=math.abs(d.Z)<0.9 and {X=0,Y=0,Z=1}or {X=0,Y=1,Z=0}
   local u=unit(cross(d,ref));local v=cross(d,u);local uh,vh=scale(u,width/2),scale(v,width/2)
   local corners={sub(sub(a,uh),vh),add(sub(a,vh),uh),add(add(a,uh),vh),add(sub(a,uh),vh),
    sub(sub(b,uh),vh),add(sub(b,vh),uh),add(add(b,uh),vh),add(sub(b,uh),vh)}
   face(corners,{1,4,3,2},scale(d,-1));face(corners,{5,6,7,8},d)
   face(corners,{1,2,6,5},scale(v,-1));face(corners,{2,3,7,6},u)
   face(corners,{3,4,8,7},v);face(corners,{4,1,5,8},scale(u,-1))
  end
  local ac=StaticFindObject('/Script/Engine.Actor');local mc=StaticFindObject('/Script/ProceduralMeshComponent.ProceduralMeshComponent')
  assert(valid(ac)and valid(mc),'procedural display classes unavailable')
  local material,matpath
  for _,path in ipairs(tint and {EMISSIVE}or {BASIC,DEFAULT})do
   local good,m=pcall(function()local x=StaticFindObject(path);if not valid(x)then x=LoadAsset(path)end;return x end)
   if good and valid(m)then
    local id=name(m);assert(id=='Material '..path,'unexpected material object');material,matpath=m,path;break
   end
  end
  assert(valid(material),'known engine material unavailable');identity()
  actor=w:SpawnActor(ac,anchor,{Pitch=0,Yaw=0,Roll=0});actor_id=name(actor);actor_address=address(actor)
  out.actor_id=actor_id;out.actor_address=actor_address;out.status='spawned_pending'
  local aw,awa=world_of(actor);assert(aw==wid and awa==wa,'spawned actor World mismatch')
  -- Native lifespan is installed immediately, before component creation.
  actor:SetLifeSpan(lifetime);local lifespan=actor:GetLifeSpan();assert(finite(lifespan)and lifespan>=lifetime-1 and lifespan<=lifetime+0.01,'lifespan not verified');out.lifespan_readback_seconds=lifespan
  out.lifespan_verified=true;actor:SetActorEnableCollision(false);actor:SetActorHiddenInGame(false);identity()
  local t={Rotation={X=0,Y=0,Z=0,W=1},Translation={X=0,Y=0,Z=0},Scale3D={X=1,Y=1,Z=1}}
  local mesh=actor:AddComponentByClass(mc,false,t,false);assert(valid(mesh),'procedural display component failed')
  assert(name(mesh:GetOwner())==actor_id and address(mesh:GetOwner())==actor_address,'new component owner mismatch');out.component_id=name(mesh)
  mesh:SetCollisionEnabled(0);mesh:SetCollisionResponseToAllChannels(0);mesh:SetGenerateOverlapEvents(false)
  mesh:K2_SetWorldLocation(anchor,false,{},true);mesh:K2_SetWorldRotation({Pitch=0,Yaw=0,Roll=0},false,{},true)
  mesh:SetVisibleInSceneCaptureOnly(false);mesh:SetHiddenInGame(false,false);mesh:SetVisibility(true,false)
  mesh:SetCastShadow(false);mesh.bUseAsyncCooking=false
  mesh:CreateMeshSection(0,vertices,triangles,normals,uv,colors,{},false)
  mesh:SetCollisionEnabled(0);mesh:SetCollisionResponseToAllChannels(0);mesh:SetGenerateOverlapEvents(false)
  mesh:SetMaterial(0,material)
  local assigned=material
  if tint then
   -- Color/GlobalParameter=2/Index=-1 observed on the cooked companion instance.
   -- Create a new MID on this owned display component; never mutate source assets.
   assigned=mesh:CreateDynamicMaterialInstance(0,material,FName('None'))
   assert(valid(assigned)and assigned:GetClass():GetFName():ToString()=='MaterialInstanceDynamic','display MID unavailable')
   assert(name(assigned.Parent)==name(material),'display MID parent mismatch')
   local info={Name=FName('Color'),Association=2,Index=-1}
   assigned:SetVectorParameterValueByInfo(info,tint)
   local value=assigned:K2_GetVectorParameterValueByInfo(info)
   for _,k in ipairs({'R','G','B','A'})do assert(finite(value[k])and math.abs(value[k]-tint[k])<1e-5,'display tint readback mismatch')end
   mesh:SetMaterial(0,assigned)
   out.color={R=tint.R,G=tint.G,B=tint.B,A=tint.A};out.color_mode='owned_emissive_MID_Color_readback_verified'
  end
  assert(mesh:GetCollisionEnabled()==0 and mesh:GetGenerateOverlapEvents()==false,'display collision disable not verified')
  for ch=0,31 do assert(mesh:GetCollisionResponseToChannel(ch)==0,'display channel not ignored: '..ch)end
  assert(name(mesh:GetMaterial(0))==name(assigned),'material readback mismatch');assert(mesh:GetNumSections()==1,'unexpected mesh section count');identity()
  out.material_id=name(assigned);out.material_path=matpath;out.vertex_count=#vertices;out.triangle_count=#triangles/3
  out.collision_enabled=0;out.all_channels_ignored=true;out.overlap_events=false;out.status='display_actor_created';out.ok=true
 end)
 if not ok then
  out.reason=message(why);out.errors[#out.errors+1]=out.reason
  if actor_id then
   local clean,ce=pcall(function()
    assert(valid(actor)and name(actor)==actor_id and address(actor)==actor_address,'created actor identity unavailable')
    actor:K2_DestroyActor()
   end)
   out.cleanup_requested=clean;out.status=clean and'failed_cleanup_requested'or'uncertain_owned_display_actor'
   if not clean then out.cleanup_reason=message(ce)end
  end
 end
 emit();return out
end
