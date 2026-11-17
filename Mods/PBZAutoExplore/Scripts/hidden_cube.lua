-- Additional narrow F9 target. No component references survive a completed pass.
local M={}
local function valid(o)local ok,v=pcall(function()return o and o:IsValid()end);return ok and v==true end
local function address(o)local ok,v=pcall(function()return o:GetAddress()end);return ok and tostring(v) or nil end
function M.matches(actor,component,previously_verified)
 if not valid(actor) or not valid(component) then return false end
 if actor.bHidden~=true and component.bHiddenInGame~=true then return false end
 local profile=component:GetCollisionProfileName():ToString()
 if profile~='Profile_LA_InvisibleWall' and not (previously_verified and profile=='Custom') then return false end
 local mesh=component.StaticMesh
 return valid(mesh) and mesh:GetFullName()=='StaticMesh /Engine/BasicShapes/Cube.Cube'
end
return M
