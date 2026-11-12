-- Optional F6 viewer within PBZNearbyKillToggle; independent from F7 state.
return function(H,log,dir,toggle_key)
 local keyname='F6'
 local ok,err=pcall(function()
  local cfg=assert(loadfile(dir..'keybindings.lua'))()
  if cfg.display==nil then return end
  assert(type(cfg.display)=='string','display must be a key name')
  local n=cfg.display:upper();local number=tonumber(n:match('^F(%d+)$'))
  assert(number and number>=1 and number<=12 and n=='F'..number and type(Key[n])=='number','invalid display key')
  assert(n~=tostring(cfg.toggle or 'F7'):upper(),'display and toggle keys must differ')
  keyname=n
 end)
 if not ok then log('display_key_invalid; using F6: '..tostring(err))end
 assert(Key[keyname]~=toggle_key,'display key conflicts with kill-zone toggle; choose different keys')
 local collect=assert(loadfile(dir..'death_volume_geometry_v1.lua'))()
 local render=assert(loadfile(dir..'collision_wire_renderer_v1.lua'))()
 local viewer=assert(loadfile(dir..'killzone_display_v1.lua'))().new(H,log,collect,render)
 RegisterKeyBind(Key[keyname],viewer.request_toggle)
 assert(LoopInGameThreadWithDelay(500,viewer.tick),'display game-thread loop unavailable')
 log('display_v1_loaded key='..keyname..'; off by default; GE_Kill convex edges only; radius=30m; refresh=5s')
end
