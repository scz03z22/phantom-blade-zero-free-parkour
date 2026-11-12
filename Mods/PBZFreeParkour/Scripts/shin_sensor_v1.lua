-- Pure hysteresis for a non-blocking probe. No engine calls or actions.
local M={}
function M.update(state,s)
 state=state or {}
 if type(s)~='table' or s.valid~=true or type(s.time)~='number' or s.time~=s.time then
  return {supported=false,missing_since=nil},'unknown'
 end
 if state.last_time and s.time<state.last_time then state={supported=false} end
 state.last_time=s.time
 if s.hit==true then state.supported=true;state.missing_since=nil;return state,'supported' end
 if s.hit~=false then state.supported=false;state.missing_since=nil;return state,'unknown' end
 if not state.supported then return state,'unarmed' end
 state.missing_since=state.missing_since or s.time
 if s.time-state.missing_since<.25 then return state,'grace' end
 state.supported=false;state.missing_since=nil
 return state,'support_lost_candidate'
end
return M
