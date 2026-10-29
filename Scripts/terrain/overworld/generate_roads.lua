
local function isNeighbor( pois, a, b )
	local x0 = pois[a].x
	local y0 = pois[a].y
	local x1 = pois[b].x
	local y1 = pois[b].y
	--In between point
	local cx = ( x0 + x1 ) / 2
	local cy = ( y0 + y1 ) / 2
	local dd = dist2( x0, y0, cx, cy )
	for i = 1, #pois do
		if i ~= a and i ~= b and dist2( pois[i].x, pois[i].y, cx, cy ) < dd then
			return false
		end
	end
	return true
end

----------------------------------------------------------------------------------------------------

function preparePoiRoadGraph( pois, roadPois )
	for _,poi in ipairs( pois ) do
		if poi.road then
			roadPois[#roadPois + 1] = poi
			poi.edges = {}
		end
	end

	local Multiplier = {
		[TYPE_MEADOW] = 1,
		[TYPE_FOREST] = 1,
		[TYPE_FIELD] = 1,
		[TYPE_BURNTFOREST] = 1,
		[TYPE_AUTUMNFOREST] = 1,
		[TYPE_LAKE] = 1,
		[TYPE_DESERT] = 1,
	}

	for i = 1, #roadPois - 1 do
		for j = i + 1, #roadPois do
			if isNeighbor( roadPois, i, j ) then
				local a = roadPois[i]
				local b = roadPois[j]

				local distance = math.abs( a.x - b.x ) + math.abs( a.y - b.y ) -- Manhattan distance
				local cliffDiff = math.abs( ( a.cliffLevel or 0 ) - ( b.cliffLevel or 0 ) )
				local multiplier = math.max( Multiplier[a.terrainType], Multiplier[b.terrainType] )

				local cost = distance * multiplier + cliffDiff^2 * 10

				a.edges[#a.edges + 1] = { n = b, cost = cost }
				b.edges[#b.edges + 1] = { n = a, cost = cost }



			end
		end
	end
end

----------------------------------------------------------------------------------------------------

function hasRoad( cellX, cellY, roadNodes )
	if not roadNodes[cellY] then
		return false
	end
	local node = roadNodes[cellY][cellX]
	if node then
		for _,e in ipairs( node.edges ) do
			if e.road then
				return true
			end
		end
	end
	return false
end

----------------------------------------------------------------------------------------------------

-- NOTE: All edge distances should be initialized to infinity (math.huge)
function writeDistancesInNodes( a, b )
    b.dist = 0

    local queue = {}
    queue[#queue + 1] = b

    local visited = {}

    local maxDist = math.huge
    local iterations = 0

    while #queue > 0 do
        local node = nil
        local index = nil

        -- Find the node with the shortest distance in the queue
        for i, n in ipairs( queue ) do
            if node == nil or n.dist < node.dist then
                node = n
                index = i
            end
        end

        -- Remove the node with the shortest distance from the queue
        queue[index] = queue[#queue]
        queue[#queue] = nil

        visited[node] = true

        for _, e in ipairs( node.edges ) do
            if not visited[e.n] then
                local dist = node.dist + e.cost
                if dist < e.n.dist then
                    e.n.dist = dist
                    if e.n == a and dist < maxDist then
                        maxDist = dist
                    end
                    if dist <= maxDist then
                        queue[#queue + 1] = e.n
                    end
                end
            end
        end

        iterations = iterations + 1
    end
    
    -- Return the shortest distance and number of iterations
    return maxDist, iterations
end

----------------------------------------------------------------------------------------------------

-- Find road path from start to destination
function findRoadPath( roadPois, roadEdges, start, destination )

	for _,poi in ipairs( roadPois ) do
		poi.dist = math.huge -- Init to huge costs
	end
	writeDistancesInNodes( start, destination )

	-- Traverse down the total costs
	local node = start
	while node ~= destination do
		local bestEdge

		for _,edge in ipairs( node.edges ) do
			if bestEdge == nil or edge.n.dist < bestEdge.n.dist then
				bestEdge = edge
			end
		end

		if bestEdge == nil then
			sm.log.error( "No path found!" )
			break
		end

		local a = node
		local b = bestEdge.n
		roadEdges[#roadEdges + 1] = { a = a, b = b }

		-- Reduce edge cost of beaten paths (remove muliplier for comming searches)
		local distance = math.abs( a.x - b.x ) + math.abs( a.y - b.y ) -- Manhattan distance
		local cliffDiff = math.abs( ( a.cliffLevel or 0 ) - ( b.cliffLevel or 0 ) )
		local cost = distance + cliffDiff^2 * 10

		bestEdge.cost = cost
		for _,edge in ipairs( b.edges ) do
			if edge.n == a then
				edge.cost = cost
			end
		end

		node = b
	end
end

----------------------------------------------------------------------------------------------------

local RoadPoiTypes = { POI_ROAD_CHEMPOOL, POI_ROAD_SCHEMATICSTATION, POI_ROAD_KIOSK, POI_ROAD_KIOSK }
local f_nextRoadPoiIndex = 1

-- Add the roads and convert placeholder pois
function drawRoads( roadEdges, pois )
	-- Prepare nodes for road search
	local roadNodes = {}

	local createNode = function( x, y )
		assert( roadNodes[y][x] == nil, "Node already exists "..x..", "..y )
		roadNodes[y][x] = { x = x, y = y, edges = {} }



	end

	for y = g_cellData.bounds.yMin + g_cellData.padding, g_cellData.bounds.yMax - g_cellData.padding do
		roadNodes[y] = {}
		for x = g_cellData.bounds.xMin + g_cellData.padding, g_cellData.bounds.xMax - g_cellData.padding do
			if not collides( x, y, 1, pois ) then
				local p = collides( x, y, 3, pois )
				if not p or ( p.type == POI_RANDOM_PLACEHOLDER and p.terrainType or math.floor( p.type / 100 ) ) == TYPE_MEADOW then
					createNode( x, y )
				end
			end
		end
	end

	local TerrainTypeCost = {
		[TYPE_MEADOW] = 3,
		[TYPE_FOREST] = 3,
		[TYPE_FIELD] = 3,
		[TYPE_BURNTFOREST] = 3,
		[TYPE_AUTUMNFOREST] = 3,
		[TYPE_LAKE] = 3,
		[TYPE_DESERT] = 3,
	}
	local maxNoiseCost = 50

	local roadNoise = function( x, y )
		local seed = g_cellData.seed % 32768
		local noise = math.abs( sm.noise.simplexNoise2d( ( x + 256 * ( seed + 53 ) ) / 3.7, ( y + 256 * ( seed + 96 ) ) / 3.7 ) )





		return noise * maxNoiseCost
	end

	local connectNodeEast = function( x, y, road )
		local a = roadNodes[y][x]
		local b = roadNodes[y][x + 1]
		if a and b then
			for _,e in ipairs( a.edges ) do
				assert( e.n ~= b )
			end
			for _,e in ipairs( b.edges ) do
				assert( e.n ~= a )
			end
			local cost = math.max( TerrainTypeCost[g_cornerTemp.terrainType[y][x + 1]], TerrainTypeCost[g_cornerTemp.terrainType[y + 1][x + 1]] )
			local c00 = g_cellData.cliffLevel[y][x]
			local c01 = g_cellData.cliffLevel[y + 1][x]
			local c10 = g_cellData.cliffLevel[y][x + 1]
			local c11 = g_cellData.cliffLevel[y + 1][x + 1]
			local c20 = g_cellData.cliffLevel[y][x + 2]
			local c21 = g_cellData.cliffLevel[y + 1][x + 2]

			local cliffDiff = math.max( c00, c01, c10, c11, c20, c21 ) - math.min( c00, c01, c10, c11, c20, c21 )
			cost = cost + cliffDiff^2 * 5 + roadNoise( x + 0.5, y )

			a.edges[#a.edges + 1] = { n = b, cost = cost, road = road }
			b.edges[#b.edges + 1] = { n = a, cost = cost, road = road }



		end
	end
	local connectNodeNorth = function( x, y, road )
		local a = roadNodes[y][x]
		local b = roadNodes[y + 1][x]
		if a and b then
			for _,e in ipairs( a.edges ) do
				assert( e.n ~= b )
			end
			for _,e in ipairs( b.edges ) do
				assert( e.n ~= a )
			end
			local cost = math.max( TerrainTypeCost[g_cornerTemp.terrainType[y + 1][x]], TerrainTypeCost[g_cornerTemp.terrainType[y + 1][x + 1]] )

			local c00 = g_cellData.cliffLevel[y][x]
			local c10 = g_cellData.cliffLevel[y][x + 1]
			local c01 = g_cellData.cliffLevel[y + 1][x]
			local c11 = g_cellData.cliffLevel[y + 1][x + 1]
			local c02 = g_cellData.cliffLevel[y + 2][x]
			local c12 = g_cellData.cliffLevel[y + 2][x + 1]

			local cliffDiff = math.max( c00, c10, c11, c01, c02, c12 ) - math.min( c00, c10, c11, c01, c02, c12 )
			cost = cost + cliffDiff^2 * 5 + roadNoise( x, y + 0.5 )

			a.edges[#a.edges + 1] = { n = b, cost = cost, road = road }
			b.edges[#b.edges + 1] = { n = a, cost = cost, road = road }



		end
	end

	-- Connect nodes W->E
	for y = g_cellData.bounds.yMin + g_cellData.padding, g_cellData.bounds.yMax - g_cellData.padding do
		for x = g_cellData.bounds.xMin + g_cellData.padding, g_cellData.bounds.xMax - g_cellData.padding - 1 do
			connectNodeEast( x, y )
		end
	end

	-- Connect nodes S->N
	for y = g_cellData.bounds.yMin + g_cellData.padding, g_cellData.bounds.yMax - g_cellData.padding - 1 do
		for x = g_cellData.bounds.xMin + g_cellData.padding, g_cellData.bounds.xMax - g_cellData.padding do
			connectNodeNorth( x, y )
		end
	end

	local randomRoadPoiCount = 0

	local prepareRoadPoiAndGetConnectionPoint = function( poi, other )
		local dx = poi.x - other.x
		local dy = poi.y - other.y

		-- Rotation based on road direction

		if poi.type == POI_RANDOM_PLACEHOLDER and poi.road then
			poi.type = RoadPoiTypes[f_nextRoadPoiIndex]
			f_nextRoadPoiIndex = f_nextRoadPoiIndex + 1
			if f_nextRoadPoiIndex > #RoadPoiTypes then
				f_nextRoadPoiIndex = 1
			end

			local rot = math.abs( dy ) > math.abs( dx ) and 1 or 0
			poi.rotation = rot + ( sm.noise.intNoise2d( poi.x, poi.y, g_cellData.seed + 211 ) % 2 ) * 2
			poi.size = 1
			poi.flat = false

			--local RoadPoiTypeColors = { [POI_ROAD_KIOSK] = "ffff00", [POI_ROAD_SCHEMATICSTATION] = "00ffff", [POI_ROAD_CHEMPOOL] = "ff00ff" }
			--ddBox( "roadpoi", poi.x, poi.y, 1, 1, RoadPoiTypeColors[poi.type] )

			createNode( poi.x - 1, poi.y )
			createNode( poi.x - 1, poi.y - 1 )
			createNode( poi.x, poi.y - 1 )

			connectNodeEast( poi.x - 2, poi.y - 1 )
			connectNodeEast( poi.x - 2, poi.y )
			connectNodeEast( poi.x - 1, poi.y - 1 )
			connectNodeEast( poi.x, poi.y - 1 )

			connectNodeNorth( poi.x - 1, poi.y - 2 )
			connectNodeNorth( poi.x, poi.y - 2 )
			connectNodeNorth( poi.x - 1, poi.y - 1 )
			connectNodeNorth( poi.x - 1, poi.y )

			if poi.terrainType ~= TYPE_MEADOW then
				createNode( poi.x - 2, poi.y - 2 )
				createNode( poi.x - 1, poi.y - 2 )
				createNode( poi.x, poi.y - 2 )
				createNode( poi.x + 1, poi.y - 2 )

				createNode( poi.x - 2, poi.y + 1 )
				createNode( poi.x - 1, poi.y + 1 )
				createNode( poi.x, poi.y + 1 )
				createNode( poi.x + 1, poi.y + 1 )

				createNode( poi.x - 2, poi.y - 1 )
				createNode( poi.x - 2, poi.y )

				createNode( poi.x + 1, poi.y - 1 )
				createNode( poi.x + 1, poi.y )


				connectNodeEast( poi.x - 3, poi.y - 2 )
				connectNodeEast( poi.x - 3, poi.y - 1 )
				connectNodeEast( poi.x - 3, poi.y )
				connectNodeEast( poi.x - 3, poi.y + 1 )

				connectNodeEast( poi.x - 2, poi.y - 2 )
				connectNodeEast( poi.x - 2, poi.y - 1 )
				connectNodeEast( poi.x - 2, poi.y )
				connectNodeEast( poi.x - 2, poi.y + 1 )

				connectNodeEast( poi.x - 1, poi.y - 2 )
				connectNodeEast( poi.x - 1, poi.y + 1 )

				connectNodeEast( poi.x, poi.y - 2 )
				connectNodeEast( poi.x, poi.y - 1 )
				connectNodeEast( poi.x, poi.y + 1 )

				connectNodeEast( poi.x + 1, poi.y - 2 )
				connectNodeEast( poi.x + 1, poi.y - 1 )
				connectNodeEast( poi.x + 1, poi.y )
				connectNodeEast( poi.x + 1, poi.y + 1 )


				connectNodeNorth( poi.x - 2, poi.y - 3 )
				connectNodeNorth( poi.x - 1, poi.y - 3 )
				connectNodeNorth( poi.x, poi.y - 3 )
				connectNodeNorth( poi.x + 1, poi.y - 3 )

				connectNodeNorth( poi.x - 2, poi.y - 2 )
				connectNodeNorth( poi.x - 1, poi.y - 2 )
				connectNodeNorth( poi.x, poi.y - 2 )
				connectNodeNorth( poi.x + 1, poi.y - 2 )

				connectNodeNorth( poi.x - 2, poi.y - 1 )
				connectNodeNorth( poi.x + 1, poi.y - 1 )

				connectNodeNorth( poi.x - 2, poi.y )
				connectNodeNorth( poi.x - 1, poi.y )
				connectNodeNorth( poi.x + 1, poi.y )

				connectNodeNorth( poi.x - 2, poi.y + 1 )
				connectNodeNorth( poi.x - 1, poi.y + 1 )
				connectNodeNorth( poi.x, poi.y + 1 )
				connectNodeNorth( poi.x + 1, poi.y + 1 )
			end
			randomRoadPoiCount = randomRoadPoiCount + 1
		end

		if poi.rotation == nil and poi.type == POI_BUILDERQUEST_RESOURCECAR then
			local rot = math.abs( dy ) > math.abs( dx ) and 1 or 0
			poi.rotation = rot + ( sm.noise.intNoise2d( poi.x, poi.y, g_cellData.seed + 211 ) % 2 ) * 2
		end

		if poi.rotation == nil and isAnyOf( poi.type, { POI_MECHANICSTATION_MEDIUM, POI_MECHANICSTATION_QUEST_MEDIUM, POI_PACKINGSTATIONVEG_MEDIUM, POI_PACKINGSTATIONFRUIT_MEDIUM } ) then
			if math.abs( dy ) > math.abs( dx ) then
				poi.rotation = dx > 0 and 3 or 1
			else
				poi.rotation = dy > 0 and 0 or 2
			end
		end

		if poi.rotation == nil and isAnyOf( poi.type, { POI_WAREHOUSE2_LARGE, POI_WAREHOUSE3_LARGE, POI_WAREHOUSE4_LARGE, POI_WAREHOUSE4_QUEST_LARGE } ) then
			local rot = math.abs( dy ) > math.abs( dx ) and 0 or 1
			poi.rotation = rot + ( sm.noise.intNoise2d( poi.x, poi.y, g_cellData.seed + 211 ) % 2 ) * 2
		end

		-- Road connections

		local addShortcut = function( x0, y0, x1, y1 )
			local a = roadNodes[y0][x0]
			local b = roadNodes[y1][x1]
			if a and b then
				a.edges[#a.edges + 1] = { n = b, cost = 1, shortcut = true }
				b.edges[#b.edges + 1] = { n = a, cost = 1, shortcut = true }



			end
		end

		if isAnyOf( poi.type, { POI_ROAD_KIOSK, POI_BUILDERQUEST_RESOURCECAR, POI_ROAD_SCHEMATICSTATION, POI_ROAD_CHEMPOOL, POI_ROAD_RANDOM } ) then
			if poi.rotation % 2 == 0 then -- W -> E
				if not poi.roaded then
					createNode( poi.x, poi.y )
					connectNodeEast( poi.x - 1, poi.y, true )
					connectNodeEast( poi.x, poi.y, true )
					poi.roaded = true
				end
				if dx > 0 then return -1, 0 else return 1, 0 end
			else -- S -> N
				if not poi.roaded then
					createNode( poi.x, poi.y )
					connectNodeNorth( poi.x, poi.y - 1, true )
					connectNodeNorth( poi.x, poi.y, true )
					poi.roaded = true
				end
				if dy > 0 then return 0, -1 else return 0, 1 end
			end
		end

		if isAnyOf( poi.type, { POI_MECHANICSTATION_MEDIUM, POI_MECHANICSTATION_QUEST_MEDIUM, POI_PACKINGSTATIONVEG_MEDIUM, POI_PACKINGSTATIONFRUIT_MEDIUM } ) then
			if poi.rotation == 0 then
				if not poi.roaded then
					createNode( poi.x - 1, poi.y - 1 )
					createNode( poi.x, poi.y - 1 )
					connectNodeEast( poi.x - 2, poi.y - 1, true )
					connectNodeEast( poi.x - 1, poi.y - 1, true )
					connectNodeEast( poi.x, poi.y - 1, true )
					poi.roaded = true
				end
				if dx > 0 then return -2, -1 else return 1, -1 end
			elseif poi.rotation == 1 then
				if not poi.roaded then
					createNode( poi.x, poi.y - 1 )
					createNode( poi.x, poi.y )
					connectNodeNorth( poi.x, poi.y - 2, true )
					connectNodeNorth( poi.x, poi.y - 1, true )
					connectNodeNorth( poi.x, poi.y, true )
					poi.roaded = true
				end
				if dy > 0 then return 0, -2 else return 0, 1 end
			elseif poi.rotation == 2 then
				if not poi.roaded then
					createNode( poi.x - 1, poi.y )
					createNode( poi.x, poi.y )
					connectNodeEast( poi.x - 2, poi.y, true )
					connectNodeEast( poi.x - 1, poi.y, true )
					connectNodeEast( poi.x, poi.y, true )
					poi.roaded = true
				end
				if dx > 0 then return -2, 0 else return 1, 0 end
			else
				if not poi.roaded then
					createNode( poi.x - 1, poi.y - 1 )
					createNode( poi.x - 1, poi.y )
					connectNodeNorth( poi.x - 1, poi.y - 2, true )
					connectNodeNorth( poi.x - 1, poi.y - 1, true )
					connectNodeNorth( poi.x - 1, poi.y, true )
					poi.roaded = true
				end
				if dy > 0 then return -1, -2 else return -1, 1 end
			end
		end

		if isAnyOf( poi.type, { POI_WAREHOUSE2_LARGE, POI_WAREHOUSE3_LARGE, POI_WAREHOUSE4_LARGE, POI_WAREHOUSE4_QUEST_LARGE } ) then
			if poi.rotation % 2 == 0 then
				if not poi.roaded then
					createNode( poi.x - 1, poi.y - 2 )
					createNode( poi.x, poi.y + 1 )
					connectNodeNorth( poi.x - 1, poi.y - 3, true )
					connectNodeNorth( poi.x, poi.y + 1, true )
					addShortcut( poi.x - 1, poi.y - 2, poi.x, poi.y + 1 )
					poi.roaded = true
				end
			else
				if not poi.roaded then
					createNode( poi.x - 2, poi.y )
					createNode( poi.x + 1, poi.y - 1 )
					connectNodeEast( poi.x - 3, poi.y, true )
					connectNodeEast( poi.x + 1, poi.y - 1, true )
					addShortcut( poi.x - 2, poi.y, poi.x + 1, poi.y - 1 )
					poi.roaded = true
				end
			end
			if poi.rotation % 2 == 0 then -- SSW -> NNE
				if dy > 0 then return -1, -3 else return 0, 2 end
			else -- WSW -> ENE
				if dx > 0 then return -3, 0 else return 2, -1 end
			end
		end

		if isAnyOf( poi.type, { POI_RUINCITY_XL, POI_MEADOW_GROWLAB_SILODISTRICT_XL } ) then
			if not poi.roaded then
				createNode( poi.x + 3, poi.y - 1 )
				createNode( poi.x, poi.y + 3 )
				createNode( poi.x - 4, poi.y )
				createNode( poi.x - 1, poi.y - 4 )
				connectNodeEast( poi.x + 3, poi.y - 1, true )
				connectNodeNorth( poi.x, poi.y + 3, true )
				connectNodeEast( poi.x - 5, poi.y, true )
				connectNodeNorth( poi.x - 1, poi.y - 5, true )
				addShortcut( poi.x + 3, poi.y - 1,  poi.x, poi.y + 3 )
				addShortcut( poi.x, poi.y + 3, poi.x - 4, poi.y )
				addShortcut( poi.x - 4, poi.y, poi.x - 1, poi.y - 4 )
				addShortcut( poi.x - 1, poi.y - 4, poi.x + 3, poi.y - 1 )
				poi.roaded = true
			end

			if dx > 0 and dx > math.abs( dy ) then 		-- From W
				return -5, 0
			elseif dx < 0 and dx < -math.abs( dy ) then	-- From E
				return 4, -1
			elseif dy > 0 then							-- From S
				return -1, -5
			else										-- From N
				return 0, 4
			end
		end

		if poi.type == POI_CAMP_LARGE then
			if not poi.roaded then
				createNode( poi.x + 1, poi.y - 2 )
				connectNodeEast( poi.x + 1, poi.y - 2, true )
				connectNodeNorth( poi.x + 1, poi.y - 3, true )
				poi.roaded = true
			end
			if dx > 0 or dy > 0 then	-- From W or S
				return 1, -3
			else
				return 2, -2
			end
		end

		if poi.type == POI_EXCAVATION_BRIDGE then
			if not poi.roaded then
				createNode( poi.x, poi.y )
				connectNodeEast( poi.x - 1, poi.y, true )
				poi.roaded = true
			end
			return -1, 0
		end

		if poi.type == POI_BUILDERQUEST_WOCHOUSE then
			if not poi.roaded then
				poi.roaded = true
			end
			return 0, 1
		end

		sm.log.error( "Error road connection", poi.type, poi.x, poi.y )
		return 0, 0
	end

	local drawRoad = function( x0, y0, x1, y1, aPoi, bPoi )
		local roadCells = {}

		local a = roadNodes[y0][x0]
		local b = roadNodes[y1][x1]
		if not a or not b then
			sm.log.error( "Error finding road from", x0, y0, "to", x1, y1 )
			if a == nil then sm.log.error( "	a is nil", aPoi.type, aPoi.terrainType ) end
			if b == nil then sm.log.error( "	b is nil", bPoi.type, bPoi.terrainType ) end



			return
		else



		end

		for _,row in pairs( roadNodes ) do
			for _,n in pairs( row ) do
				n.dist = math.huge -- Init to huge costs
			end
		end
		writeDistancesInNodes( a, b )

		local n = a
		roadCells[#roadCells + 1] = { x = n.x, y = n.y }
		local count = 0
		while n ~= b do
			local bestEdge
			for _,e in ipairs( n.edges ) do
				if bestEdge == nil or e.n.dist < bestEdge.n.dist then
					bestEdge = e
				end
			end
			if bestEdge == nil then
				sm.log.error( "No path found!" )
				break
			end



			-- Reduce cost for future searches (because of the existing road)
			local cost = 1
			bestEdge.cost = cost
			bestEdge.road = true
			for _,e in ipairs( bestEdge.n.edges ) do
				if e.n == n then
					e.cost = cost
					e.road = true
					break
				end
			end
			n = bestEdge.n
			roadCells[#roadCells + 1] = { x = n.x, y = n.y }
			count = count + 1
			if count > 1000 then
				sm.log.error( "Road search path too long", x0, y0, x1, y1 )



				break
			end
		end

		roadCells[#roadCells + 1] = { x = b.x, y = b.y }
	end

	for _, edge in ipairs( roadEdges ) do
		local aox, aoy = prepareRoadPoiAndGetConnectionPoint( edge.a, edge.b )
		local box, boy = prepareRoadPoiAndGetConnectionPoint( edge.b, edge.a )
		if edge.a.x + aox < edge.b.x + box then
			drawRoad( edge.a.x + aox, edge.a.y + aoy, edge.b.x + box, edge.b.y + boy, edge.a, edge.b )
		else
			drawRoad( edge.b.x + box, edge.b.y + boy, edge.a.x + aox, edge.a.y + aoy, edge.b, edge.a )
		end
	end

	print( "Random road pois:", randomRoadPoiCount )

	-- Clean out non road edges
	for _,row in pairs( roadNodes ) do
		for _,n in pairs( row ) do
			n.dist = nil
			removeFromArray( n.edges, function( e )
				return not e.road and not e.shortcut
			end )
			if #n.edges == 0 then
				roadNodes[n.y][n.x] = nil
			end
		end
	end

	return roadNodes
end
