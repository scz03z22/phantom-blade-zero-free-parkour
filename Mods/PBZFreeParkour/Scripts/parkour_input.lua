-- Read one logical jump button from keyboard OR gamepad on the existing host.
-- No hooks, timers, object searches, or retained controller/UObject references.
-- FKeys are value structs, compiled once per reader instead of once per tick.
local M={}
local scripts=assert(debug.getinfo(1,'S').source:match('^@(.+[\\/])[^\\/]+$'),'script directory unavailable')
local defaults={keyboard_jump='SpaceBar',gamepad_jump='Gamepad_FaceButton_Bottom'}
function M.new(log,override)
 local cfg=override
 if cfg==nil then
  local ok,value=pcall(function() return assert(loadfile(scripts..'input_bindings.lua'))() end)
  if ok and type(value)=='table' then cfg=value
  else
   cfg={}
   if log then pcall(log,'pad1_input_config_fallback; using Space and bottom face button: '..tostring(value)) end
  end
 end
 assert(type(cfg)=='table','input bindings must be a table')
 local keys,names,seen={},{},{}
 for _,field in ipairs({'keyboard_jump','gamepad_jump'}) do
  local name=cfg[field]
  if name==nil then name=defaults[field] end
  if name~=false and (type(name)~='string' or #name<1 or #name>96 or not name:match('^[%w_]+$')) then
   if log then pcall(log,'pad1_input_invalid field='..field..'; using default') end
   name=defaults[field]
  end
  if name~=false and not seen[name] then
   seen[name]=true;names[#names+1]=name;keys[#keys+1]={KeyName=FName(name)}
  end
 end
 return {
  jump_down=function(controller)
   -- Short-circuit OR also avoids a duplicate edge when both devices are held.
   -- Releasing one device while the other stays down keeps the logical hold.
   for _,key in ipairs(keys) do
    local down=controller:IsInputKeyDown(key)
    assert(type(down)=='boolean','jump key state unreadable')
    if down then return true end
   end
   return false
  end,
  describe=function() return table.concat(names,'|') end,
 }
end
return M
