-- Only the verified, non-sellable Traversing Talisman. No inventory refill loop.
local M={}
function M.install(log)
 if PBZ_FREE_TRAVERSING then return end
 local path='/Script/ProjectPBZ.PBZBackPackSubsystem:RemovePropsFromBackPack'
 RegisterHook(path,function(ctx,num,item,broadcast)
  local ok,err=pcall(function()
   local id=item:get():ToString();local n=num:get()
   if id~='Item_Traversing' or type(n)~='number' or n<=0 then return end
   num:set(0)
   assert(num:get()==0,'count override failed')
   log('talisman_cost_blocked requested='..n)
  end)
  if not ok then log('item_hook_error '..tostring(err))end
 end,function()end)
 PBZ_FREE_TRAVERSING=true
 log('talisman_no_cost_loaded; exact_id=Item_Traversing; existing_item_required')
end
return M
