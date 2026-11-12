-- STAGED ONLY; do not load in a running game until isolated integration review.
-- Snapshot and per-write validation for killzone_controller_v2. No persistent
-- UObject refs: exact refs live only inside one function invocation. The caller
-- must schedule on the game thread and keep the controller journal alive.
local M={}
local GE='BlueprintGeneratedClass /Game/PBZContent/Blueprint/Ability/GameplayEffects/GE_Kill.GE_Kill_C'
local function finite(x)return type(x)=='number' and x==x and math.abs(x)<math.huge end
local function valid(o)local ok,v=pcall(function()return o and o:IsValid()end);return ok and v==true end
local function name(o)assert(valid(o),'invalid object');local n=o:GetFullName();assert(type(n)=='string' and n~='','unknown name');return n end
local function addr(o)local n=o:GetAddress();assert(finite(n) and n>0 and n%1==0 and n<=9007199254740991,'invalid address');return string.format('%.0f',n)end
local function vec(v)assert(v and finite(v.X) and finite(v.Y) and finite(v.Z),'invalid vector');return {X=v.X,Y=v.Y,Z=v.Z}end
local function owning(o)local l=o:GetLevel();assert(valid(l),'level unavailable');return name(l.OwningWorld),addr(l.OwningWorld)end
local function dense(a,limit)
 assert(type(a)=='table','unsupported object enumeration');local n,max=0,0
 for k in next,a do assert(type(k)=='number' and k%1==0 and k>=1 and k<=limit,'invalid enumeration');n=n+1;max=math.max(max,k)end
 assert(n==max,'incomplete enumeration');return n
end
local function distance(p,b)
 local d2=0;for _,k in ipairs({'X','Y','Z'})do local d=math.max(0,math.abs(p[k]-b.origin[k])-b.extent[k]);d2=d2+d*d end;return math.sqrt(d2)
end
function M.new(H,options)
 assert(type(H)=='table','helpers unavailable');options=options or {}
 local margin=options.margin_cm or 300
 assert(finite(margin) and margin>=300 and margin<=10000,'invalid safety margin')
 local function context()
  local p,w=H.GetPlayer(),H.GetWorld();local pid,wid,pa,wa=name(p),name(w),addr(p),addr(w)
  local pw,pwa=owning(p);assert(pw==wid and pwa==wa,'player world mismatch')
  local cap=p.CapsuleComponent;assert(name(cap:GetOwner())==pid and addr(cap:GetOwner())==pa,'capsule owner mismatch')
  local movement=p.CharacterMovement;assert(name(movement:GetOwner())==pid and addr(movement:GetOwner())==pa,'movement owner mismatch')
  assert(movement.MovementMode==1,'player not standing or walking')
  local velocity=vec(p:GetVelocity());assert(velocity.X^2+velocity.Y^2+velocity.Z^2<=100,'player moving')
  local half,rad=cap:GetScaledCapsuleHalfHeight(),cap:GetScaledCapsuleRadius()
  assert(finite(half) and half>0 and finite(rad) and rad>0,'capsule dimensions unavailable')
  assert(margin>=math.max(half+100,rad+100),'configured margin too small for capsule')
  local health=p.AttributeSetBase.Health.CurrentValue;assert(finite(health) and health>0,'health unavailable/dead')
  local death,state=p['Death Component'],p['Actor State Component']
  assert(name(death:GetOwner())==pid and addr(death:GetOwner())==pa,'death component owner mismatch')
  assert(name(state:GetOwner())==pid and addr(state:GetOwner())==pa,'state component owner mismatch')
  assert(state:InExactState(death['Dead State Tag'])==false,'dead state unknown/dead')
  local ch=cap:GetCollisionObjectType();assert(type(ch)=='number' and ch%1==0 and ch>=0 and ch<=31,'invalid channel')
  return {complete=true,world_id=wid,world_address=wa,player_id=pid,player_address=pa,channel=ch,position=vec(p:K2_GetActorLocation()),rows={}}
 end
 local function same(a,b)
  for _,k in ipairs({'world_id','world_address','player_id','player_address','channel'})do assert(a[k]==b[k],'context changed: '..k)end
 end
 -- A complete scan selects candidates; a write re-resolves only its exact
 -- actor path. Never keep UObject references between game-thread callbacks.
 local function inspect(a,s)
  local aw,awa=owning(a)
  assert(aw==s.world_id and awa==s.world_address,'target world mismatch')
  assert(valid(a.GEClass) and name(a.GEClass)==GE,'target effect changed')
  local id,aa=name(a),addr(a)
  local cl=a:GetClass():GetFName():ToString();assert(cl=='PBZGEVolume','unexpected target class')
  local c=a.BrushComponent;local cid,ca=name(c),addr(c)
  assert(name(c:GetOwner())==id and addr(c:GetOwner())==aa,'brush owner mismatch')
  local cc=c:GetClass():GetFName():ToString();assert(cc=='BrushComponent','unexpected brush class')
  local response=c:GetCollisionResponseToChannel(s.channel);assert(response==0 or response==1 or response==2,'response unavailable')
  local o,e={X=0/0,Y=0/0,Z=0/0},{X=0/0,Y=0/0,Z=0/0};a:GetActorBounds(false,o,e,false);o,e=vec(o),vec(e)
  assert(e.X>=0 and e.Y>=0 and e.Z>=0,'invalid bounds')
  return {actor_id=id,actor_address=aa,actor_class=cl,brush_id=cid,brush_address=ca,brush_class=cc,
   brush_owner_id=id,brush_owner_address=aa,world_id=aw,world_address=awa,ge_class=GE,response=response,bounds={origin=o,extent=e}},c
 end
 local function capture()
  local s=context();s.unknown_effect_count=0;local all=FindAllOf('PBZGEVolume');assert(all~=nil,'volume enumeration unavailable; empty result not proven');dense(all,600);local seen={}
  for _,a in ipairs(all)do
   assert(valid(a),'invalid enumerated volume; snapshot incomplete')
   local aw,awa=owning(a)
   if aw==s.world_id and awa==s.world_address then
    local effect=a.GEClass
    if not valid(effect)then s.unknown_effect_count=s.unknown_effect_count+1
    elseif name(effect)==GE then
     local row=inspect(a,s);assert(not seen[row.actor_id],'ambiguous actor path');seen[row.actor_id]=true
     s.rows[#s.rows+1]=row
    end
   end
  end
  same(s,context());return s
 end
 local function exact(action,s)
  assert(type(action.actor_id)=='string','invalid target path')
  local path=assert(action.actor_id:match('^PBZGEVolume (/.+)$'),'unexpected target path')
  local a=StaticFindObject(path);assert(valid(a),'exact actor unavailable')
  local row,c=inspect(a,s)
  for _,k in ipairs({'actor_id','actor_address','brush_id','brush_address'})do
   assert(row[k]==action[k],'exact identity changed: '..k)
  end
  assert(action.key==row.actor_id..'@'..row.actor_address..'|'..row.brush_id..'@'..row.brush_address,'target key mismatch')
  return row,c
 end
 local function snapshot()local s=capture();return s end
 local function apply(action,planned)
  local attempted=false
  local ok,result=pcall(function()
   assert(type(action)=='table' and type(planned)=='table','invalid request')
   local fresh=context();same(planned,fresh)
   local row,c=exact(action,fresh)
   assert(row.response==action.expected_response,'response changed')
   assert(action.desired_response==0 or action.desired_response==1 or action.desired_response==2,'invalid desired response')
   assert(distance(fresh.position,row.bounds)>margin,'player too close to current volume')
   if action.bounds then assert(distance(fresh.position,action.bounds)>margin,'player too close to saved volume')end
   assert(name(c)==row.brush_id and addr(c)==row.brush_address,'brush identity changed')
   same(fresh,context())
   if action.verify_only==true then
    assert(action.expected_response==action.desired_response,'invalid verification action')
    return 'verified_original'
   end
   attempted=true
   c:SetCollisionResponseToChannel(fresh.channel,action.desired_response)
   local after=context();same(fresh,after)
   local checked,current=exact(action,after)
   assert(checked.response==action.desired_response,'response readback mismatch')
   same(after,context())
   return 'applied'
  end)
  if ok then return result end
  return attempted and 'uncertain' or 'not_applied',tostring(result):gsub('[\r\n]',' '):sub(1,240)
 end
 local function verify_lookup()
  local s=capture();local checked=0
  for i,row in ipairs(s.rows)do
   if i>3 then break end
   row.key=row.actor_id..'@'..row.actor_address..'|'..row.brush_id..'@'..row.brush_address
   exact(row,s);checked=checked+1
  end
  same(s,context())
  return checked,#s.rows
 end
 return {snapshot=snapshot,apply=apply,verify_lookup=verify_lookup}
end
return M
