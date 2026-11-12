local scripts=assert(debug.getinfo(1,'S').source:match('^@(.+[\\/])[^\\/]+$'),'script directory unavailable')
return assert(loadfile(scripts..'bell_feedback_v8.lua'))()
