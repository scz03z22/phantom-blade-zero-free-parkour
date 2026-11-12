-- Owned SideRunning UI only. Called by existing game-thread lifecycle updates.
-- No hooks, timers, global enumeration, lazy-widget creation, or UObject cache.
-- Component display flags survive late user-widget creation; each apply also
-- reacquires the current user widget so replacements/animation opacity reset
-- are suppressed. These are local writes, not a promise about render ordering.
local M={}
local CLASS='BlueprintGeneratedClass /Game/RenewalContent/Actors/SpecialMove/BP_ASM_SideRunning.BP_ASM_SideRunning_C'
local function finite(v) return type(v)=='number' and v==v and math.abs(v)<math.huge end
local function valid(o) local ok,v=pcall(function() return o and o:IsValid() end);return ok and v==true end
local function name(o) assert(valid(o),'object unavailable');local n=o:GetFullName();assert(type(n)=='string' and n~='','object name unavailable');return n end
local function world_of(o)
 for _=1,32 do local n=name(o);if n:sub(1,6)=='World ' then return n end;o=o:GetOuter() end
 error('World outer not found')
end
function M.new(H,log,state)
 assert(type(state)=='table','native owned pool required')
 -- Only primitive diagnostic/timing records persist. No widget is retained.
 local last_enum,seen_users,seen_components,errors={},{},{},{}
 local function emit(s) pcall(log or function() end,'v18_1_owned_side_ui '..s) end
 local function once(key,why)
  if not errors[key] then errors[key]=true;emit('unavailable field='..key..' reason='..tostring(why):gsub('[\r\n]',' '):sub(1,400)) end
 end
 local function checked(actor)
  local id=name(actor);assert(type(state.pool)=='table','native pool unavailable')
  local entry
  for _,e in ipairs(state.pool) do if e.volume==id then entry=e;break end end
  assert(entry,'actor not in owned pool')
  assert(entry.class_full_name==CLASS and name(actor:GetClass())==CLASS,'owned concrete class mismatch')
  local p,w=H.GetPlayer(),H.GetWorld()
  assert(name(p)==state.player and name(w)==state.world,'current player/world differs from owned pool')
  assert(world_of(p)==state.world and world_of(actor)==state.world,'owned UI World mismatch')
  return id,p
 end
 -- force_enum=true at spawn/construction/move/OnInteract boundaries. Normal
 -- inspection calls can omit it: local enumeration is limited to 10Hz while
 -- direct Widget/WidgetB refreshes occur on every existing lifecycle sample.
 local function apply(actor,force_enum)
  local report={components=0,users=0,pending_users=0,errors=0,enumerated=false}
  local ok,id,p=pcall(checked,actor)
  if not ok then once('identity',id);return false,tostring(id) end
  local visited={}
  local function attempt(label,fn)
   local yes,result=pcall(fn)
   if not yes then report.errors=report.errors+1;once(id..'.'..label,result) end
   return yes,result
  end
  local function component(c,source)
   if not valid(c) then return end
   local cid=name(c);if visited[cid] then return end
   -- No propagation: an attached component from a different actor is untouched.
   assert(name(c:GetOwner())==id,'component is not owned by selected actor')
   checked(actor);visited[cid]=true
   local hidden=attempt(source..'.visibility',function() c:SetVisibility(false,false) end)
   attempt(source..'.hidden',function() c:SetHiddenInGame(true,false) end)
   attempt(source..'.tint',function() c:SetTintColorAndOpacity({R=1,G=1,B=1,A=0}) end)
   if hidden then report.components=report.components+1 end
   if not seen_components[cid] then seen_components[cid]=true;emit('component actor='..id..' source='..source..' component='..cid) end
   attempt(source..'.user',function()
    local user=c:GetUserWidgetObject()
    if not valid(user) then report.pending_users=report.pending_users+1;return end
    local uid=name(user)
    -- An assigned UUserWidget may be outered to GameInstance rather than its
    -- WidgetComponent. Ownership evidence is the fresh exact component slot.
    checked(actor);assert(name(c:GetOwner())==id and name(c:GetUserWidgetObject())==uid,'widget association changed')
    user:SetRenderOpacity(0)
    -- UMG_enums.hpp: ESlateVisibility.Collapsed = 1.
    user:SetVisibility(1)
    report.users=report.users+1
    if seen_users[cid]~=uid then seen_users[cid]=uid;emit('user actor='..id..' component='..cid..' user='..uid..' opacity=0 collapsed=true') end
   end)
  end
  for _,key in ipairs({'Widget','WidgetB'}) do attempt('direct.'..key,function() component(actor[key],key) end) end
  local time_ok,now=pcall(function() local t=H.GetGameplayStatics():GetRealTimeSeconds(p);assert(finite(t),'time unavailable');return t end)
  if not time_ok then once(id..'.time',now);now=nil end
  local last=last_enum[id]
  local should_enum=force_enum==true or last==nil or (now and (now<last or now-last>=.1))
  if should_enum then
   -- If the clock is unavailable, enumerate only once unless explicitly forced.
   last_enum[id]=now or 0
   attempt('actor_local_components',function()
    checked(actor)
    local klass=StaticFindObject('/Script/UMG.WidgetComponent');assert(valid(klass),'WidgetComponent class unavailable')
    local all=actor:K2_GetComponentsByClass(klass);assert(all~=nil,'local component array unavailable')
    local methods_ok,get_count,for_each=pcall(function() return all.GetArrayNum,all.ForEach end)
    if methods_ok and type(get_count)=='function' and type(for_each)=='function' then
     local count=all:GetArrayNum();assert(finite(count) and count>=0 and count%1==0 and count<=64,'local widget count invalid/out of bound')
     local read=0
     all:ForEach(function(_,ref)
      read=read+1;assert(read<=count,'local widget enumeration exceeds count')
      attempt('local.'..read,function() component(ref:get(),'local.'..read) end)
     end)
     assert(read==count,'local widget enumeration incomplete')
    else
     -- K2_GetComponentsByClass returns a plain Lua object list on this build.
     -- Validate its complete shape before reading any local-list component.
     assert(type(all)=='table','unsupported local widget array representation')
     local count,max_index=0,0
     for key,value in next,all do
      assert(type(key)=='number' and finite(key) and key>=1 and key%1==0 and key<=64,'local widget Lua list has unexpected key')
      count=count+1;assert(count<=64,'local widget Lua list exceeds bound')
      assert(valid(value),'local widget Lua list contains invalid component')
      max_index=math.max(max_index,key)
     end
     assert(count==max_index,'local widget Lua list is sparse')
     local read=0
     for i,c in ipairs(all) do
      read=read+1;assert(read<=count,'local widget Lua list changed during iteration')
      attempt('local.'..i,function() component(c,'local.'..i) end)
     end
     assert(read==count,'local widget Lua list enumeration incomplete')
    end
    report.enumerated=true
   end)
  end
  return true,report
 end
 return {apply=apply}
end
return M
