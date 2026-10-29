-- World-bound helper used by server admin commands. The game script has no
-- world context, so shape creation is bounced through this scriptable object.

SmserverSpawner = class()
SmserverSpawner.isSaveObject = false

local BlockedShapeUuids = {
	["3d127db0-da28-4483-86fd-3eeed20fb85d"] = true,
}

function SmserverSpawner.sv_e_spawnPart( self, params )
	if type( params ) ~= "table" or params.uuid == nil or params.position == nil then
		return
	end
	if not sm.shape.uuidExists( params.uuid ) then
		return
	end
	if BlockedShapeUuids[tostring( params.uuid )] or ( smserver_isBlockedItem and smserver_isBlockedItem( params.uuid ) ) then
		return
	end
	local rotation = params.rotation or sm.quat.identity()
	local dynamic = params.dynamic
	if dynamic == nil then
		dynamic = true
	end
	return sm.shape.createPart( params.uuid, params.position, rotation, dynamic, true )
end
