dofile( "$SURVIVAL_DATA/Scripts/game/survival_collections.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/survival_constants.lua" )

MinerbotWaypointManager = class()

function MinerbotWaypointManager.server_onCreate( self )
	g_minerbotWaypointManager = self
	self.sv = {}
	self.sv.worldCellWaypoints = {}
end


--[[ Manager ]]
function MinerbotWaypointManager.Sv_OnCellLoaded( x, y, world )
	if g_minerbotWaypointManager then
		g_minerbotWaypointManager:sv_onCellLoaded( x, y, world )
	end
end

function MinerbotWaypointManager.sv_onCellLoaded( self, x, y, world )
	local worldId = world.id
	local cellKey = CellKey( x, y )

	local waypointNodes = sm.cell.getNodesByTag( x, y, "MINERBOTWAYPOINT" )
	self.sv.worldCellWaypoints[worldId] = self.sv.worldCellWaypoints[worldId] or {}
	self.sv.worldCellWaypoints[worldId][cellKey] = {}
	local waypoints = self.sv.worldCellWaypoints[worldId][cellKey]
	for _, node in ipairs( waypointNodes ) do
		waypoints[#waypoints+1] = { position = node.position }
	end
end

function MinerbotWaypointManager.Sv_OnCellUnloaded( x, y, world )
	if g_minerbotWaypointManager then
		g_minerbotWaypointManager:sv_onCellUnloaded( x, y, world )
	end
end

function MinerbotWaypointManager.sv_onCellUnloaded( self, x, y, world )
	local worldId = world.id
	local cellKey = CellKey( x, y )

	local waypoints = self.sv.worldCellWaypoints[worldId] and self.sv.worldCellWaypoints[worldId][cellKey] or nil
	if waypoints then
		self.sv.worldCellWaypoints[worldId][cellKey] = nil
	end
end

function MinerbotWaypointManager.Sv_GetWaypoint( worldPosition, world )
	if g_minerbotWaypointManager then
		return g_minerbotWaypointManager:sv_getWaypoint( worldPosition, world )
	end
	return nil
end

function MinerbotWaypointManager.sv_getWaypoint( self, worldPosition, world )
	local bestPoint = { distance2 = math.huge, waypoint = nil }

	local worldId = world.id
	local xCenterCell, xFrac = math.modf( worldPosition.x / 64 )
	local yCenterCell, yFrac = math.modf( worldPosition.y / 64 )

	-- Also check bordering cells. Edge is 25% of the cell size
	local xMinOffset = xFrac <= 0.25 and -1 or 0
	local xMaxOffset = xFrac >= 0.75 and 1 or 0
	local yMinOffset = yFrac <= 0.25 and -1 or 0
	local yMaxOffset = yFrac >= 0.75 and 1 or 0
	for x = xCenterCell + xMinOffset, xCenterCell + xMaxOffset do
		for y = yCenterCell + yMinOffset, yCenterCell + yMaxOffset do
			local cellKey = CellKey( x, y )
			local waypoints = self.sv.worldCellWaypoints[worldId] and self.sv.worldCellWaypoints[worldId][cellKey] or nil
			if waypoints then
				for _, waypoint in ipairs( waypoints ) do
					local distance2 = ( waypoint.position - worldPosition ):length2()
					if distance2 <= bestPoint.distance2 then
						bestPoint = { distance2 = distance2, waypoint = waypoint }
					end
				end
			end
		end
	end

	return bestPoint.waypoint
end

