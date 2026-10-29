TUNNEL_GRID_CELLS_PER_CHUNK = 3
TUNNEL_GRID_CELLS_PER_CHUNK = 3
TUNNEL_GRID_SIZE = CHUNK_SIZE / TUNNEL_GRID_CELLS_PER_CHUNK --= 5.33333

local SystemFromType = {
	["Cave"] = { ["Main"] = "Main", ["Vein"] = "Main" },
	["Elevator"] = { ["Main"] = "Main", ["Vein"] = "Main" },
	["TunnelPocket"] = { ["Main"] = "Main", ["Vein"] = "Main" },
	["TinyTunnelPocket"] = { ["Main"] = "Main", ["Vein"] = "Main" },
	["FreePocket"] = { ["Main"] = "Main", ["Vein"] = "Main" },
}

local NodeTypeRemap = {
	--["Elevator"] = { ["Main"] = "Ignore" },
	["TinyTunnelPocket"] = { ["Vein"] = "Ignore" },
	["FreePocket"] = { ["Main"] = "Ignore", ["Vein"] = "Ignore" },
}

local PathingSettings = {
	["PsDefault"] = { costNoiseFrequency = 1.0, costNoiseIntensity = 0.0, costZPenalty = 0.0 },
	["PsMain"] = { costNoiseFrequency = 1 / 5, costNoiseIntensity = 2.5, costZPenalty = 5.0, maxDistance = 30 },
	["PsDrift"] = { costNoiseFrequency = 1 / 2.0, costNoiseIntensity = 10.5, costZPenalty = 5.5, startHorizontal = true, endHorizontal = true },
	["PsDriftDirected"] = { costNoiseFrequency = 2.0, costNoiseIntensity = 10.5, costZPenalty = 5.5, endHorizontal = true },
	["PsFunnel"] = { costNoiseFrequency = 1.0, costNoiseIntensity = 0.0, costZPenalty = 0.0, endHorizontal = true },
	["PsVein"] = { costNoiseFrequency = 1 / 5.0, costNoiseIntensity = 2.0, costZPenalty = 2.0, maxDistance = 20 },
}

local TunnelSettings = {
	["Main"] = { ["Vein"] = { tunnelType = "MainVein", pathingSettings = "PsVein" }, },
	["Vein"] = { ["Main"] = { tunnelType = "MainVein", pathingSettings = "PsVein" }, ["Vein"] = { tunnelType = "CrossVein", pathingSettings = "PsVein" } },
}
local DefaultTunnelSetting = { tunnelType = "TtDefault", pathingSettings = "PsDefault" }

local RandomTunnelConnections = {
	{ fromNodeType = "Main", toNodeTypes = { "Vein" }, maxDistance = 20 * TUNNEL_GRID_SIZE, distancePenalty = sm.vec3.new( 1, 1, 2.5 ), tunnelSettings = { tunnelType = "MainVein", pathingSettings = "PsVein" } },
	{ fromNodeType = "Vein", toNodeTypes = { "Vein" }, maxDistance = 10 * TUNNEL_GRID_SIZE, distancePenalty = sm.vec3.new( 1, 1, 2.5 ), tunnelSettings = { tunnelType = "CrossVein", pathingSettings = "PsVein" } },
	--{ fromNodeType = "Gold", toNodeTypes = { "Gold" }, distancePenalty = sm.vec3.new( 1, 1, 2 ), preferredDistance = 3 * TUNNEL_GRID_SIZE, maxDistance = 10 * TUNNEL_GRID_SIZE },
}

local f_blockers = {}
local f_tunnelSystemNodes = {}

function TgInit()





end

function TgAddTunnelNode( system, srcKey, pos, direction, type, maxConnections, maxIncoming, toNode )
	if type == "Ignore" then
		return nil
	end
	if system ~= "Main" and system ~= "Vein" then
		sm.log.warning( "TgAddTunnelNode: Unknown tunnel system '"..system.."', node type: '"..type.."'" )
	end
	local roundedPos = ( ( pos / TUNNEL_GRID_SIZE ):floor() + 0.5 ) * TUNNEL_GRID_SIZE
	local tunnelNode = { srcKey = srcKey, pos = roundedPos, direction = direction, type = type, maxConnections = maxConnections, maxIncoming = maxIncoming, toNode = toNode }
	f_tunnelSystemNodes[system] = f_tunnelSystemNodes[system] or {}
	table.insert( f_tunnelSystemNodes[system], tunnelNode )
	--print( "Added tunnel node:", tunnelNode )
	return tunnelNode
end

function TgAddBlocker( min, max, type, padding )
	padding = padding or 0
	local blocker = {
		mi = min * TUNNEL_GRID_CELLS_PER_CHUNK - padding,
		mx = max * TUNNEL_GRID_CELLS_PER_CHUNK + padding,
		type = type
	}
	f_blockers[#f_blockers + 1] = blocker
end

function TgProcessCaveCell( uidTile, cell, zOffset, tileSize, tag, cellNodes, srcKey )
	local tunnelNodes = {}
	local padding = 0
	TgAddBlocker( sm.vec3.new( cell.x * CHUNKS_PER_CELL, cell.y * CHUNKS_PER_CELL, zOffset ),
				  sm.vec3.new( ( cell.x + 1 ) * CHUNKS_PER_CELL, ( cell.y + 1 ) * CHUNKS_PER_CELL, zOffset + tileSize.z ),
				  "Cave", padding )

	cellNodes = cellNodes or sm.terrainTile.getNodesForCell( uidTile, cell.offsetX, cell.offsetY )
	for _, node in ipairs( cellNodes ) do
		if valueExists( node.tags, "TUNNEL" ) then
			local rx, ry = RotateLocal2( cell.rotation, node.pos.x, node.pos.y, CELL_SIZE, CELL_SIZE )
			local pos = sm.vec3.new( cell.x * CELL_SIZE + rx, cell.y * CELL_SIZE + ry, node.pos.z + zOffset * CHUNK_SIZE )
			local direction = GetRotationQuat2( cell.rotation ) * node.rot * sm.vec3.new( 0, 1, 0 )

			local nodeType = node.params and node.params.tunnel.tunnel.type or "Generic"
			if NodeTypeRemap[tag] then
				nodeType = NodeTypeRemap[tag][nodeType] or nodeType
			end
			local systemName = SystemFromType[tag] and SystemFromType[tag][nodeType] or "Default"
			local maxConnections = node.params and node.params.tunnel.tunnel.maxConnections or nil
			local maxIncoming = node.params and node.params.tunnel.tunnel.maxIncoming or nil

			local tunnelNode = TgAddTunnelNode( systemName, srcKey, pos, direction, nodeType, maxConnections, maxIncoming )
			tunnelNodes[#tunnelNodes + 1] = tunnelNode
		end
	end
	return tunnelNodes
end

function TgProcessPocket( tileUid, pos, rotation, tileSize, rasterGrid, tag, cellNodes, srcKey )
	local tunnelNodes = {}
	--TODO: Move blocker cration here
	--print( "Processing pocket:", tileUid, pos, rotation, tileSize, tag )

	cellNodes = cellNodes or sm.terrainTile.getNodesForCell( tileUid, 0, 0 )
	for _, node in ipairs( cellNodes ) do
		if valueExists( node.tags, "TUNNEL" ) then
			local rx, ry = RotateLocal2( rotation, node.pos.x, node.pos.y, tileSize.x * CHUNK_SIZE, tileSize.y * CHUNK_SIZE )
			local pos = sm.vec3.new( pos.x * CHUNK_SIZE + rx, pos.y * CHUNK_SIZE + ry, pos.z * CHUNK_SIZE + node.pos.z )
			local direction = GetRotationQuat2( rotation ) * node.rot * sm.vec3.new( 0, 1, 0 )

			local nodeType = node.params and node.params.tunnel.tunnel.type or "Generic"
			if NodeTypeRemap[tag] then
				nodeType = NodeTypeRemap[tag][nodeType] or nodeType
			end
			local systemName = SystemFromType[tag] and SystemFromType[tag][nodeType] or "Default"
			local maxConnections = node.params and node.params.tunnel.tunnel.maxConnections or nil
			local maxIncoming = node.params and node.params.tunnel.tunnel.maxIncoming or nil

			local tunnelNode = TgAddTunnelNode( systemName, srcKey, pos, direction, nodeType, maxConnections, maxIncoming )
			tunnelNodes[#tunnelNodes + 1] = tunnelNode
		end
	end
	return tunnelNodes
end

function TgDebugDrawBlockers()
	if g_dbgShowBlockedVolumes then
		for i, blocker in ipairs( f_blockers ) do
			sm.debugDraw.addAabb( "VoxelProcDebug_BlockBox"..i, blocker.mi * TUNNEL_GRID_SIZE, blocker.mx * TUNNEL_GRID_SIZE, sm.color.new( 0, 0, 1, 1 ) )
		end
	end
end

-- Spatial grid cell size for node lookup optimization
local SPATIAL_GRID_CELL_SIZE = 20 * TUNNEL_GRID_SIZE -- Sized to cover max search distance

function TgCreateTunnels( xMin, xMax, yMin, yMax, zMin, zMax, seed, tunnelSystemName, blockerTypes )
	print( "Creating '"..tunnelSystemName.."' tunnels" )
	local startTime = os.clock()

	local function fromIsFull( fromNode )
		return ( fromNode.incomingCount or 0 ) + ( fromNode.outgoingCount or 0 ) >= ( fromNode.maxConnections or 1 )
	end
	local function toIsFull( other )
		return ( other.maxIncoming ~= nil and ( other.incomingCount or 0 ) >= other.maxIncoming )
			or ( ( other.incomingCount or 0 ) + ( other.outgoingCount or 0 ) >= ( other.maxConnections or 1 ) )
	end
	local function notSameSrc( fromNode, toNode )
		return fromNode.srcKey == nil or toNode.srcKey == nil or fromNode.srcKey ~= toNode.srcKey
	end
	local function notLinkedSrc( fromNode, toNode, mapLinkedKeys )
		if fromNode.srcKey == nil or toNode.srcKey == nil then
			return true
		end
		return not mapLinkedKeys[fromNode.srcKey.."-"..toNode.srcKey] and not mapLinkedKeys[toNode.srcKey.."-"..fromNode.srcKey]
	end

	-- Build spatial hash grid for faster node lookups
	local function buildSpatialGrid( nodes )
		local grid = {}
		for _, node in ipairs( nodes ) do
			local gx = math.floor( node.pos.x / SPATIAL_GRID_CELL_SIZE )
			local gy = math.floor( node.pos.y / SPATIAL_GRID_CELL_SIZE )
			local gz = math.floor( node.pos.z / SPATIAL_GRID_CELL_SIZE )
			local key = gx .. "," .. gy .. "," .. gz
			grid[key] = grid[key] or {}
			grid[key][#grid[key] + 1] = node
		end
		return grid
	end

	-- Get nearby nodes from spatial grid within search radius
	local function getNearbyNodes( grid, pos, searchRadius )
		local nearby = {}
		local cellRange = math.ceil( searchRadius / SPATIAL_GRID_CELL_SIZE )
		local cx = math.floor( pos.x / SPATIAL_GRID_CELL_SIZE )
		local cy = math.floor( pos.y / SPATIAL_GRID_CELL_SIZE )
		local cz = math.floor( pos.z / SPATIAL_GRID_CELL_SIZE )
		for gx = cx - cellRange, cx + cellRange do
			for gy = cy - cellRange, cy + cellRange do
				for gz = cz - cellRange, cz + cellRange do
					local key = gx..","..gy..","..gz
					local cell = grid[key]
					if cell then
						for _, node in ipairs( cell ) do
							nearby[#nearby + 1] = node
						end
					end
				end
			end
		end
		return nearby
	end

	local function getBestNode( fromNode, spatialGrid, tunnelConnection, mapLinkedKeys )
		local types = tunnelConnection.toNodeTypes
		local distancePenalty = tunnelConnection.distancePenalty or sm.vec3.new( 1, 1, 2 ) -- Prefer horizontal tunnels
		local preferredDistance = tunnelConnection.preferredDistance or 0
		local maxDistance = tunnelConnection.maxDistance or math.huge

		local bestNode = nil
		local bestDist = maxDistance

		-- Only search nearby nodes using spatial grid
		local nearbyNodes = getNearbyNodes( spatialGrid, fromNode.pos, maxDistance )
		for _, other in ipairs( nearbyNodes ) do
			if other ~= fromNode and isAnyOf( other.type, types ) and not toIsFull( other )
				and notSameSrc( fromNode, other ) and notLinkedSrc( fromNode, other, mapLinkedKeys ) then
				local dist = math.abs( ( ( fromNode.pos - other.pos ) * distancePenalty ):length() - preferredDistance )
				if ( bestNode == nil and dist <= maxDistance - preferredDistance ) or dist < bestDist - preferredDistance then
					bestNode = other
					bestDist = dist
				end
			end
		end
		return bestNode
	end

	local tunnelNodes = f_tunnelSystemNodes[tunnelSystemName]
	if tunnelNodes then
		shuffle( tunnelNodes )
	end

	local tunnelPathingRequests = {}
	local tunnelPathingRequestCounts = {}
	local tunnelNodes = f_tunnelSystemNodes[tunnelSystemName]
	if tunnelNodes then
		local mapLinkedKeys = {}
		-- Adds pre-linked keys
		local preLinkedCount = 0
		for _, fromNode in ipairs( tunnelNodes ) do
			local toNode = fromNode.toNode
			if toNode then
				if fromNode.srcKey ~= nil and toNode.srcKey ~= nil then
					mapLinkedKeys[fromNode.srcKey.."-"..toNode.srcKey] = true
					preLinkedCount = preLinkedCount + 1
				end
			end
		end
		print( "Added pre-linked tunnel connections:", preLinkedCount )

		for _, fromNode in ipairs( tunnelNodes ) do
			local toNode = fromNode.toNode
			assert( not toNode or toNode.toNode == fromNode, "Tunnel nodes should have symmetric toNode connections" )
			if toNode and not fromIsFull( fromNode ) and not toIsFull( toNode ) then
				fromNode.outgoingCount = fromNode.outgoingCount or 1
				toNode.incomingCount = toNode.incomingCount or 1
				local settings = ( TunnelSettings[fromNode.type] and TunnelSettings[fromNode.type][toNode.type] )
				if not settings then
					settings = DefaultTunnelSetting
				end
				tunnelPathingRequests[#tunnelPathingRequests + 1] = {
					dirA = fromNode.direction,
					dirB = toNode.direction,
					posA = fromNode.pos / TUNNEL_GRID_SIZE,
					posB = toNode.pos / TUNNEL_GRID_SIZE,
					pathingSettings = settings.pathingSettings,
					tunnelType = settings.tunnelType,
				}
				tunnelPathingRequestCounts[settings.tunnelType] = ( tunnelPathingRequestCounts[settings.tunnelType] or 0 ) + 1
				if fromNode.srcKey ~= nil and toNode.srcKey ~= nil then
					mapLinkedKeys[fromNode.srcKey.."-"..toNode.srcKey] = true
				end
			end
		end
		for _, tunnelConnection in ipairs( RandomTunnelConnections ) do
			-- Build spatial grid for this tunnel system (once per connection type)
			local spatialGrid = buildSpatialGrid( f_tunnelSystemNodes[tunnelSystemName] )
			for _, fromNode in ipairs( tunnelNodes ) do
				if fromNode.type == tunnelConnection.fromNodeType and not fromIsFull( fromNode ) then
					local toNode = getBestNode( fromNode, spatialGrid, tunnelConnection, mapLinkedKeys )
					if toNode then
						fromNode.outgoingCount = fromNode.outgoingCount or 1
						toNode.incomingCount = toNode.incomingCount or 1
						local settings = ( TunnelSettings[fromNode.type] and TunnelSettings[fromNode.type][toNode.type] )
						if not settings then
							settings = DefaultTunnelSetting
						end
						tunnelPathingRequests[#tunnelPathingRequests + 1] = {
							dirA = fromNode.direction,
							dirB = toNode.direction,
							posA = fromNode.pos / TUNNEL_GRID_SIZE,
							posB = toNode.pos / TUNNEL_GRID_SIZE,
							pathingSettings = tunnelConnection.tunnelSettings.pathingSettings or settings.pathingSettings,
							tunnelType = tunnelConnection.tunnelSettings.tunnelType or settings.tunnelType,
						}
						tunnelPathingRequestCounts[settings.tunnelType] = ( tunnelPathingRequestCounts[settings.tunnelType] or 0 ) + 1
						if fromNode.srcKey ~= nil and toNode.srcKey ~= nil then
							mapLinkedKeys[fromNode.srcKey.."-"..toNode.srcKey] = true
						end
					end
				end
			end
		end
		local unusedTunnelNodeCounts = {}
		for _, node in ipairs( tunnelNodes ) do
			if ( node.outgoingCount or 0 ) == 0 and ( node.incomingCount or 0 ) == 0 then
				unusedTunnelNodeCounts[node.type] = ( unusedTunnelNodeCounts[node.type] or 0 ) + 1
			end
		end
		print( "Unused tunnel nodes:" )
		for nodeType, count in pairs( unusedTunnelNodeCounts ) do
			print( "  "..nodeType..": "..count )
		end
	end



























	print( "Number of tunnel requests:", #tunnelPathingRequests )
	for tunnelType, count in pairs( tunnelPathingRequestCounts ) do
		print( "  "..tunnelType..": "..count )
	end
	for i, request in ipairs( tunnelPathingRequests ) do
		--sm.debugDraw.addArrow( "VoxelProcDebug_RequestArrow"..i.."-"..request.tunnelType, request.posA * TUNNEL_GRID_SIZE, request.posB * TUNNEL_GRID_SIZE, sm.color.new( 1, 1, 1 ) )
		--print( "  Request ", i, ": ", request )
	end

	--g_prevTunnels = sm.terrainGeneration.loadGameStorage( "DEBUG_TUNNELS" )
	--sm.terrainGeneration.setGameStorageNoSave( "DEBUG_TUNNELS", tunnels )
	--g_prevTunnels = g_prevTunnels or tunnels
	--assert( #tunnels == #g_prevTunnels )
	--for i = 1, #tunnels do
	--	assert( tunnels[i].dirA == g_prevTunnels[i].dirA )
	--	assert( tunnels[i].dirB == g_prevTunnels[i].dirB )
	--	assert( tunnels[i].posA == g_prevTunnels[i].posA )
	--	assert( tunnels[i].posB == g_prevTunnels[i].posB )
	--	assert( tunnels[i].pathingSettings == g_prevTunnels[i].pathingSettings )
	--end

	local blockers = {}
	for i, blocker in ipairs( f_blockers ) do
		if not blockerTypes or valueExists( blockerTypes, blocker.type ) then
			blockers[#blockers + 1] = blocker
		end
	end

	local tunnelGridMin = sm.vec3.new( xMin, yMin, zMin ) * TUNNEL_GRID_CELLS_PER_CHUNK
	local tunnelGridMax = sm.vec3.new( xMax + 1, yMax + 1, zMax + 1 ) * TUNNEL_GRID_CELLS_PER_CHUNK
	print( "Generating tunnels in grid:", tunnelGridMin, tunnelGridMax )
	local startTimeGen = os.clock()
	local tunnels = sm.tunnelGenerator.generate( seed, tunnelGridMin, tunnelGridMax, PathingSettings, tunnelPathingRequests, blockers, TUNNEL_GRID_SIZE )
	local endTimeGen = os.clock()
	print( string.format( "Tunnel generation: %.3f seconds", endTimeGen - startTimeGen ) )
	for i = 1, #tunnels do
		local tunnel = tunnels[i]
		local request = tunnelPathingRequests[i]
		tunnel.tunnelType = request.tunnelType
		if #tunnel.positions == 0 then
			if g_dbgShowTunnels then
				print( "  Tunnel", i, "had no positions!" )
				print( tunnel )
				sm.debugDraw.addArrow( "VoxelProcDebug_FailedTunnelRequest"..i.."-"..request.tunnelType, request.posA * TUNNEL_GRID_SIZE, request.posB * TUNNEL_GRID_SIZE, sm.color.new( 1, 0, 0 ) )
			end
		else
			for j = 1, #tunnel.positions do
				tunnel.positions[j] = ( tunnel.positions[j] + 0.5 ) * TUNNEL_GRID_SIZE -- Center in grid
			end
		end
	end
	local endTime = os.clock()
	print( string.format( "Create '%s' tunnels : %.3f seconds", tunnelSystemName, endTime - startTime ) )
	return tunnels
end

local function MergeTunnels( tunnels )
	local n = #tunnels;
	local j = 1
	for i = 2, n do
		if tunnels[j].positions[#(tunnels[j].positions)] == tunnels[i].positions[1] and tunnels[j].tunnelType == tunnels[i].tunnelType then
			for k = 2, #tunnels[i].positions do
				tunnels[j].positions[#tunnels[j].positions + 1] = tunnels[i].positions[k];
			end
			tunnels[i] = nil;
		else
			if i ~= j then
				tunnels[j] = tunnels[i];
				tunnels[i] = nil;
			end
			j = j + 1;
		end
	end
end

local function RasterTunnels( tunnels )
	for i = 1, #tunnels do
		local tunnel = tunnels[i]
		for i = 2, #tunnel.positions - 1 do
			local pos = tunnel.positions[i]:floor() -- From chunk center
			WriteChunkRaster( pos, sm.vec3.one(), 1 )
			TgAddBlocker( pos, pos + sm.vec3.one(), "Tunnel" )
			local prevPos = tunnel.positions[i - 1]:floor()
			local dx = pos.x - prevPos.x
			local dy = pos.y - prevPos.y
			local dz = pos.z - prevPos.z
			WriteChunkRaster( pos - sm.vec3.new( dx, 0, 0 ), sm.vec3.one(), 1 )
			WriteChunkRaster( pos - sm.vec3.new( 0, dy, 0 ), sm.vec3.one(), 1 )
			WriteChunkRaster( pos - sm.vec3.new( dx, 0, dz ), sm.vec3.one(), 1 )
			WriteChunkRaster( pos - sm.vec3.new( 0, dy, dz ), sm.vec3.one(), 1 )
		end
	end
end