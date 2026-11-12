-- Experimental position-based playback for the ordinary checkpoint touch event.
-- Call play(player) from the game thread. No checkpoint methods are invoked.
local M = {}
M.event_path = '/Game/Wwise/Events/UI/UI_Plot/SFX_UI_Plot_RingBell_Second.SFX_UI_Plot_RingBell_Second'
M.library_path = '/Script/AkAudio.Default__AkGameplayStatics'

function M.new(H, log)
  local function note(msg)
    if type(log) == 'function' then pcall(log, msg) end
  end
  local function valid(obj)
    local ok, result=pcall(function() return obj and obj:IsValid() end)
    return ok and not not result
  end
  local function play(player)
    local ok, result=pcall(function()
      if not valid(player) and H and type(H.GetPlayer)=='function' then player=H.GetPlayer() end
      assert(valid(player), 'player/world context unavailable')
      local event=StaticFindObject(M.event_path)
      assert(valid(event), 'bell touch AkAudioEvent not loaded')
      local audio=StaticFindObject(M.library_path)
      assert(valid(audio), 'AkGameplayStatics default object unavailable')
      local pos=player:K2_GetActorLocation()
      assert(pos and type(pos.X)=='number' and type(pos.Y)=='number' and type(pos.Z)=='number', 'position unavailable')
      local id=audio:PostEventAtLocation(event,{X=pos.X,Y=pos.Y,Z=pos.Z},
        {Pitch=0,Yaw=0,Roll=0},player)
      assert(type(id)=='number' and id~=0, 'invalid or unavailable PlayingID: '..tostring(id))
      return id
    end)
    if not ok then note('bell_feedback_failed '..tostring(result));return false end
    note('bell_feedback_playing_id='..tostring(result))
    return true
  end
  return {play=play}
end
return M
