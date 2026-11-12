-- Call only from the game thread. Audio failure never changes gameplay state.
local M={}
M.paths={
 enabled='/Game/Wwise/Events/UI/UI_Plot/SFX_UI_Plot_RingBell_Second.SFX_UI_Plot_RingBell_Second',
 disabled='/Game/Wwise/Events/UI/UI_General/SFX_UI_General_Material_Sell.SFX_UI_General_Material_Sell',
}
function M.new(H,log)
 local attempted={}
 local function note(s) if type(log)=='function' then pcall(log,s) end end
 local function valid(o) local ok,v=pcall(function()return o and o:IsValid()end);return ok and v==true end
 local function play(kind,player)
  local ok,id=pcall(function()
   local path=assert(M.paths[kind],'unknown feedback kind')
   if not valid(player) then player=H.GetPlayer() end
   assert(valid(player),'player unavailable')
   local event=StaticFindObject(path)
   if not valid(event) and not attempted[path] then
    attempted[path]=true
    assert(type(LoadAsset)=='function','LoadAsset unavailable')
    LoadAsset(path)
    event=StaticFindObject(path)
   end
   assert(valid(event),'audio event unavailable: '..path)
   local audio=StaticFindObject('/Script/AkAudio.Default__AkGameplayStatics')
   assert(valid(audio),'AkGameplayStatics unavailable')
   local p=player:K2_GetActorLocation()
   assert(p and type(p.X)=='number' and type(p.Y)=='number' and type(p.Z)=='number','position unavailable')
   local playing=audio:PostEventAtLocation(event,{X=p.X,Y=p.Y,Z=p.Z},{Pitch=0,Yaw=0,Roll=0},player)
   assert(type(playing)=='number' and playing~=0,'invalid playing id')
   return playing
  end)
  if ok then note('toggle_feedback kind='..tostring(kind)..' playing_id='..tostring(id));return true end
  note('toggle_feedback_failed kind='..tostring(kind)..' reason='..tostring(id));return false
 end
 return {play=play}
end
return M
