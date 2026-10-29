dofile( "$SURVIVAL_DATA/Scripts/terrain/overworld/celldata.lua" )
dofile( "$SURVIVAL_DATA/Scripts/terrain/overworld/roads_and_cliffs.lua" )
dofile( "$SURVIVAL_DATA/Scripts/terrain/overworld/type_meadow.lua" )
dofile( "$SURVIVAL_DATA/Scripts/terrain/overworld/type_forest.lua" )
dofile( "$SURVIVAL_DATA/Scripts/terrain/overworld/type_field.lua" )
dofile( "$SURVIVAL_DATA/Scripts/terrain/overworld/type_burntForest.lua" )
dofile( "$SURVIVAL_DATA/Scripts/terrain/overworld/type_autumnForest.lua" )
dofile( "$SURVIVAL_DATA/Scripts/terrain/overworld/type_lake.lua" )
dofile( "$SURVIVAL_DATA/Scripts/terrain/overworld/type_desert.lua" )
dofile( "$SURVIVAL_DATA/Scripts/terrain/overworld/poi.lua" )
dofile( "$SURVIVAL_DATA/Scripts/terrain/overworld/start_area.lua" )
dofile( "$SURVIVAL_DATA/Scripts/terrain/overworld/excavation_island.lua")
dofile( "$SURVIVAL_DATA/Scripts/terrain/terrain_util.lua" )
dofile( "$SURVIVAL_DATA/Scripts/terrain/terrain_util2.lua" )

----------------------------------------------------------------------------------------------------

-- POI_CAMP: 1
-- POI_RUIN: 11
-- POI_RANDOM: 5
-- POI_RUIN_MEDIUM: 4
-- POI_RANDOM_MEDIUM: 1

-- POI_FOREST_CAMP: 7
-- POI_FOREST_RUIN: 3
-- POI_FOREST_RANDOM: 7
-- POI_FOREST_RUIN_MEDIUM: 1
-- POI_FOREST_RANDOM_MEDIUM: 1

-- POI_DESERT_RANDOM: 2
-- POI_DESERT_OILPOOL: 2

-- POI_FIELD_RUIN: 3
-- POI_FIELD_RANDOM: 3
-- POI_FARMINGPATCH: 3

-- POI_BURNTFOREST_CAMP: 1
-- POI_BURNTFOREST_RUIN: 3

-- POI_AUTUMNFOREST_CAMP: 3
-- POI_AUTUMNFOREST_RUIN: 3

-- POI_LAKE_RANDOM: 3
-- POI_LAKE_RANDOM_MEDIUM: 2
-- POI_LAKE_RUIN_MEDIUM: 3

local PoiTypes = {
	[TYPE_MEADOW] = {
		[1] = { POI_CAMP, POI_RUIN, POI_RANDOM, POI_RUIN, POI_RANDOM, POI_RUIN }, -- Small
		[2] = { POI_CAMP, POI_RUIN, POI_RANDOM, POI_RUIN_MEDIUM, POI_RANDOM_MEDIUM, POI_RUIN_MEDIUM } -- Medium
	},
	[TYPE_FOREST] = {
		[1] = { POI_FOREST_CAMP, POI_FOREST_RUIN, POI_FOREST_RANDOM, POI_FOREST_CAMP, POI_FOREST_RANDOM }, -- Small
		[2] = { POI_FOREST_CAMP, POI_FOREST_RUIN, POI_FOREST_RANDOM, POI_FOREST_RUIN_MEDIUM, POI_FOREST_RANDOM_MEDIUM } -- Medium
	},
	[TYPE_DESERT] = {
		[1] = { POI_DESERT_RANDOM, POI_DESERT_OILPOOL }, -- Small
		[2] = { POI_DESERT_RANDOM, POI_DESERT_OILPOOL } -- Medium
	},
	[TYPE_FIELD] = {
		[1] = { POI_FARMINGPATCH, POI_FIELD_RUIN, POI_FIELD_RANDOM }, -- Small
		[2] = { POI_FARMINGPATCH, POI_FIELD_RUIN, POI_FIELD_RANDOM } -- Medium
	},
	[TYPE_BURNTFOREST] = {
		[1] = { POI_BURNTFOREST_CAMP, POI_BURNTFOREST_RUIN, POI_BURNTFOREST_RUIN }, -- Small
		[2] = { POI_BURNTFOREST_CAMP, POI_BURNTFOREST_RUIN, POI_BURNTFOREST_RUIN } -- Medium
	},
	[TYPE_AUTUMNFOREST] = {
		[1] = { POI_AUTUMNFOREST_CAMP, POI_AUTUMNFOREST_RUIN }, -- Small
		[2] = { POI_AUTUMNFOREST_CAMP, POI_AUTUMNFOREST_RUIN } -- Medium
	},
	[TYPE_LAKE] = {
		[1] = { POI_LAKE_RANDOM, }, -- Small
		[2] = { POI_LAKE_RANDOM, POI_LAKE_RUIN_MEDIUM, POI_LAKE_RANDOM_MEDIUM, POI_LAKE_RANDOM_MEDIUM } -- Medium
	},
}

local PoiSizes = {
	[POI_CAMP] = 1,
	[POI_RUIN] = 1,
	[POI_RANDOM] = 1,
	[POI_RUIN_MEDIUM] = 2,
	[POI_RANDOM_MEDIUM] = 2,

	[POI_FOREST_CAMP] = 1,
	[POI_FOREST_RUIN] = 1,
	[POI_FOREST_RANDOM] = 1,
	[POI_FOREST_RUIN_MEDIUM] = 2,
	[POI_FOREST_RANDOM_MEDIUM] = 2,

	[POI_DESERT_RANDOM] = 1,
	[POI_DESERT_OILPOOL] = 1,

	[POI_FARMINGPATCH] = 1,
	[POI_FIELD_RUIN] = 1,
	[POI_FIELD_RANDOM] = 1,

	[POI_BURNTFOREST_CAMP] = 1,
	[POI_BURNTFOREST_RUIN] = 1,

	[POI_AUTUMNFOREST_CAMP] = 1,
	[POI_AUTUMNFOREST_RUIN] = 1,

	[POI_LAKE_RANDOM] = 1,
	[POI_LAKE_RUIN_MEDIUM] = 2,
	[POI_LAKE_RANDOM_MEDIUM] = 2,
}

local f_nextPoiIndex = {
	[TYPE_MEADOW] = { 1, 1 },
	[TYPE_FOREST] = { 1, 1 },
	[TYPE_DESERT] = { 1, 1 },
	[TYPE_FIELD] = { 1, 1 },
	[TYPE_BURNTFOREST] = { 1, 1 },
	[TYPE_AUTUMNFOREST] = { 1, 1 },
	[TYPE_LAKE] = { 1, 1 },
}


local function selectRandomPoiType( poi, maxSize, terrainType )
	assert( #PoiTypes[terrainType][maxSize] > 0, "No POI types defined for terrain type: " .. terrainType .. ", size: " .. maxSize )
	poi.type = PoiTypes[terrainType][maxSize][f_nextPoiIndex[terrainType][maxSize]]
	poi.size = PoiSizes[poi.type]
	assert( poi.size, "POI type does not have a size defined: " .. poi.type )
	poi.flat = terrainType == TYPE_LAKE
	f_nextPoiIndex[terrainType][maxSize] = f_nextPoiIndex[terrainType][maxSize] + 1
	if f_nextPoiIndex[terrainType][maxSize] > #PoiTypes[terrainType][maxSize] then
		f_nextPoiIndex[terrainType][maxSize] = 1
	end
	return poi.type ~= nil
end

local function unselectRandomPoiType( maxSize, terrainType )
	f_nextPoiIndex[terrainType][maxSize] = f_nextPoiIndex[terrainType][maxSize] - 1
	if f_nextPoiIndex[terrainType][maxSize] < 1 then
		f_nextPoiIndex[terrainType][maxSize] = #PoiTypes[terrainType][maxSize]
	end
end

----------------------------------------------------------------------------------------------------

function convertPlaceholderPois( pois )
	local smallAndMediumPoiCount = 0
	for _,poi in ipairs( pois ) do
		if poi.type == POI_RANDOM_PLACEHOLDER then
			assert( poi.size == 2 )
			if selectRandomPoiType( poi, 2, poi.terrainType ) then
				if poi.size == 1 then
					poi.x = poi.x - ( sm.noise.intNoise2d( poi.x, poi.y, g_cellData.seed + 852 ) % 2 )
					poi.y = poi.y - ( sm.noise.intNoise2d( poi.x, poi.y, g_cellData.seed + 299 ) % 2 )
					--ddBox( "mediumpoi", poi.x, poi.y, 1, 1, "ffffff" )
				else
					--ddBox( "mediumpoi", poi.x - 1, poi.y - 1, 2, 2, "ffffff" )
				end
				smallAndMediumPoiCount = smallAndMediumPoiCount + 1
			else
				print( "Failed to select random poi type for placeholder at", poi.x, poi.y )
				print( "Terrain type:", poi.terrainType )
				ddBox( "mediumpoi", poi.x - 1, poi.y - 1, 2, 2, "ff0000" )
			end
		end
	end
	print( "Small/Medium random pois:", smallAndMediumPoiCount )
	removeFromArray( pois, function( poi )
		return poi.type == nil
	end )
end

----------------------------------------------------------------------------------------------------

function flattenPoiCliff( poi )
	local type = math.floor( poi.type / 100 )
	if type == 0 then type = TYPE_MEADOW end
	local pad = type ~= TYPE_MEADOW and 1 or 0
	-- Cliff level flatten
	for y0 = -pad, poi.size + pad do
		for x0 = -pad, poi.size + pad do
			local x = poi.x + x0 - math.floor( poi.size / 2 )
			local y = poi.y + y0 - math.floor( poi.size / 2 )
			if insideCornerBounds( x, y ) then
				g_cornerTemp.terrainType[y][x] = type
				g_cellData.cliffLevel[y][x] = poi.cliffLevel or 0
				g_cornerTemp.forceFlat[y][x] = true
			end
		end
	end
end

----------------------------------------------------------------------------------------------------

function addBorderingMeadows()
	forEveryCell( function( cellX, cellY )
		if g_cornerTemp.terrainType[cellY][cellX] ~= TYPE_MEADOW and g_cornerTemp.terrainType[cellY][cellX + 1] ~= TYPE_MEADOW then
			if g_cornerTemp.terrainType[cellY][cellX] ~= g_cornerTemp.terrainType[cellY][cellX + 1] then
				g_cornerTemp.terrainType[cellY][cellX + 1] = TYPE_MEADOW
				--ddArrow( "meadow", cellX - 0.5, cellY - 0.5, cellX + 1 - 0.5, cellY - 0.5, TERRAIN_TYPE_DEBUG_COLOR[g_cornerTemp.terrainType[cellY][cellX]] )
			end
		end
		if g_cornerTemp.terrainType[cellY][cellX] ~= TYPE_MEADOW and g_cornerTemp.terrainType[cellY + 1][cellX] ~= TYPE_MEADOW then
			if g_cornerTemp.terrainType[cellY][cellX] ~= g_cornerTemp.terrainType[cellY + 1][cellX] then
				g_cornerTemp.terrainType[cellY + 1][cellX] = TYPE_MEADOW
				--ddArrow( "meadow", cellX - 0.5, cellY - 0.5, cellX - 0.5, cellY + 1 - 0.5, TERRAIN_TYPE_DEBUG_COLOR[g_cornerTemp.terrainType[cellY][cellX]] )
			end
		end
		if g_cornerTemp.terrainType[cellY][cellX] ~= TYPE_MEADOW and g_cornerTemp.terrainType[cellY + 1][cellX + 1] ~= TYPE_MEADOW then
			if g_cornerTemp.terrainType[cellY][cellX] ~= g_cornerTemp.terrainType[cellY + 1][cellX + 1] then
				g_cornerTemp.terrainType[cellY + 1][cellX + 1] = TYPE_MEADOW
				--ddArrow( "meadow", cellX - 0.5, cellY - 0.5, cellX + 1 - 0.5, cellY + 1 - 0.5, TERRAIN_TYPE_DEBUG_COLOR[g_cornerTemp.terrainType[cellY][cellX]] )
			end
		end
		if g_cornerTemp.terrainType[cellY + 1][cellX] ~= TYPE_MEADOW and g_cornerTemp.terrainType[cellY][cellX + 1] ~= TYPE_MEADOW then
			if g_cornerTemp.terrainType[cellY + 1][cellX] ~= g_cornerTemp.terrainType[cellY][cellX + 1] then
				if g_cornerTemp.terrainType[cellY + 1][cellX] == TYPE_LAKE then
					g_cornerTemp.terrainType[cellY + 1][cellX] = TYPE_MEADOW
					--ddArrow( "meadow", cellX + 1 - 0.5, cellY - 0.5, cellX - 0.5, cellY + 1 - 0.5, TERRAIN_TYPE_DEBUG_COLOR[g_cornerTemp.terrainType[cellY][cellX + 1]] )
				else
					g_cornerTemp.terrainType[cellY][cellX + 1] = TYPE_MEADOW
					--ddArrow( "meadow", cellX - 0.5, cellY + 1 - 0.5, cellX + 1 - 0.5, cellY - 0.5, TERRAIN_TYPE_DEBUG_COLOR[g_cornerTemp.terrainType[cellY + 1][cellX]] )
				end
			end
		end
	end )
end

----------------------------------------------------------------------------------------------------

function enforceCliffRoadLimitations( roadNodes )
	function maxCliffClamp( x, y, lower )
		local corrections = 0
		local violations = 0
		local offsets = {
			{ x = -1, y = -1 },
			{ x =  0, y = -1 },
			{ x =  1, y = -1 },
			{ x =  1, y =  0 },
			{ x =  1, y =  1 },
			{ x =  0, y =  1 },
			{ x = -1, y =  1 },
			{ x = -1, y =  0 }
		}
	
		if lower then
			local m = math.huge
			
			for _,o in ipairs( offsets ) do
				m = math.min( m, getCornerCliffLevel( x + o.x, y + o.y ) )
			end
			
			if m < g_cellData.cliffLevel[y][x] - 3 then
				if not g_cornerTemp.forceFlat[y][x] then
					g_cellData.cliffLevel[y][x] = m + 3
					corrections = corrections + 1
				else
					violations = violations + 1
				end
			end
		else
			local m = -math.huge
			
			for _,o in ipairs( offsets ) do
				m = math.max( m, getCornerCliffLevel( x + o.x, y + o.y ) )
			end
			
			if m > g_cellData.cliffLevel[y][x] + 3 then
				if not g_cornerTemp.forceFlat[y][x] then
					g_cellData.cliffLevel[y][x] = m - 3
					corrections = corrections + 1
				else
					violations = violations + 1
				end
			end
		end
		return corrections, violations
	end
	
	function roadCliffClamp( x, y, lower )
		local corrections = 0
		local violations = 0


		local roadCount = 0
		local node = roadNodes[y][x]
		if node then
			for _,e in ipairs( node.edges ) do
				if e.road then
					roadCount = roadCount + 1
				end
			end
		end
					
		if roadCount > 0 then
			local c00 = g_cellData.cliffLevel[y][x]
			local c10 = g_cellData.cliffLevel[y][x + 1]
			local c11 = g_cellData.cliffLevel[y + 1][x + 1]
			local c01 = g_cellData.cliffLevel[y + 1][x]

			local diff = math.max( c00, c10, c11, c01 ) - math.min( c00, c10, c11, c01 )
			local maxDiff = roadCount == 2 and 1 or 0
			
			if diff > maxDiff then
				if lower then
					local m = math.min( c00, c10, c11, c01 ) + maxDiff
					
					if c00 > m then
						if not g_cornerTemp.forceFlat[y][x] then
							g_cellData.cliffLevel[y][x] = m
							corrections = corrections + 1
						else
							violations = violations + 1
						end
					end
					if c10 > m then
						if not g_cornerTemp.forceFlat[y][x + 1] then
							g_cellData.cliffLevel[y][x + 1] = m
							corrections = corrections + 1
						else
							violations = violations + 1
						end
					end
					if c11 > m then
						if not g_cornerTemp.forceFlat[y + 1][x + 1] then
							g_cellData.cliffLevel[y + 1][x + 1] = m
							corrections = corrections + 1
						else
							violations = violations + 1
						end
					end
					if c01 > m then
						if not g_cornerTemp.forceFlat[y + 1][x] then
							g_cellData.cliffLevel[y + 1][x] = m
							corrections = corrections + 1
						else
							violations = violations + 1
						end
					end
				else
					local m = math.max( c00, c10, c11, c01 ) - maxDiff
					
					if c00 < m then
						if not g_cornerTemp.forceFlat[y][x] then
							g_cellData.cliffLevel[y][x] = m
							corrections = corrections + 1
						else
							violations = violations + 1
						end
					end
					if c10 < m then
						if not g_cornerTemp.forceFlat[y][x + 1] then
							g_cellData.cliffLevel[y][x + 1] = m
							corrections = corrections + 1
						else
							violations = violations + 1
						end
					end
					if c11 < m then
						if not g_cornerTemp.forceFlat[y + 1][x + 1] then
							g_cellData.cliffLevel[y + 1][x + 1] = m
							corrections = corrections + 1
						else
							violations = violations + 1
						end
					end
					if c01 < m then
						if not g_cornerTemp.forceFlat[y + 1][x] then
							g_cellData.cliffLevel[y + 1][x] = m
							corrections = corrections + 1
						else
							violations = violations + 1
						end
					end
				end
			end
		end












		return corrections, violations
	end

	--sm.debugDraw.clear("corrections")

	local pass = 1
	local hasViolations = true
	while pass <= 5 and hasViolations do



		hasViolations = false
		local corrections, violations
		local lower = pass % 2 == 1

		-- Max cliff sweep from SW to NE
		corrections = 0
		violations = 0
		for y = g_cellData.bounds.yMin + g_cellData.padding, g_cellData.bounds.yMax - g_cellData.padding do
			for x = g_cellData.bounds.xMin + g_cellData.padding, g_cellData.bounds.xMax - g_cellData.padding do
				local c, v = maxCliffClamp( x, y, lower )
				corrections = corrections + c
				violations = violations + v
				hasViolations = hasViolations or v > 0
			end
		end
		
		-- Max cliff sweep from NE to SW
		corrections = 0
		violations = 0
		for y = g_cellData.bounds.yMax - g_cellData.padding, g_cellData.bounds.yMin + g_cellData.padding, -1 do
			for x = g_cellData.bounds.xMax - g_cellData.padding, g_cellData.bounds.xMin + g_cellData.padding, -1 do
				local c, v = maxCliffClamp( x, y, lower )
				corrections = corrections + c
				violations = violations + v
				hasViolations = hasViolations or v > 0
			end
		end
		
		-- Road cliff sweep from SW to NE
		corrections = 0
		violations = 0
		for y = g_cellData.bounds.yMin + g_cellData.padding, g_cellData.bounds.yMax - g_cellData.padding do
			for x = g_cellData.bounds.xMin + g_cellData.padding, g_cellData.bounds.xMax - g_cellData.padding do
				local c, v = roadCliffClamp( x, y, lower )
				corrections = corrections + c
				violations = violations + v
				hasViolations = hasViolations or v > 0
			end
		end
		print( "Road SW to NE:", corrections, "corrections,", violations, "violations" )
		
		-- Road cliff sweep from NE to SW
		corrections = 0
		violations = 0
		for y = g_cellData.bounds.yMax - g_cellData.padding, g_cellData.bounds.yMin + g_cellData.padding, -1 do
			for x = g_cellData.bounds.xMax - g_cellData.padding, g_cellData.bounds.xMin + g_cellData.padding, -1 do
				local c, v = roadCliffClamp( x, y, lower )
				corrections = corrections + c
				violations = violations + v
				hasViolations = hasViolations or v > 0
			end
		end
		print( "Road NE to SW:", corrections, "corrections,", violations, "violations" )
		pass = pass + 1
	end
end

----------------------------------------------------------------------------------------------------

function evaluateRoadsAndCliffs( roadNodes )
	-- Calculate flags
	for cellY = g_cellData.bounds.yMin + g_cellData.padding, g_cellData.bounds.yMax - g_cellData.padding do
		for cellX = g_cellData.bounds.xMin + g_cellData.padding, g_cellData.bounds.xMax - g_cellData.padding do
			local cliffLevelSE = getCornerCliffLevel( cellX + 1, cellY )
			local cliffLevelSW = getCornerCliffLevel( cellX, cellY )
			local cliffLevelNW = getCornerCliffLevel( cellX, cellY + 1 )
			local cliffLevelNE = getCornerCliffLevel( cellX + 1, cellY + 1 )
			local cliffBits = calculateCliffBits( cliffLevelSE, cliffLevelSW, cliffLevelNW, cliffLevelNE )

			local roadE = false
			local roadN = false
			local roadW = false
			local roadS = false
			local node = roadNodes[cellY][cellX]
			if node then
				for _,e in ipairs( node.edges ) do
					if e.road then
						if e.n.y == node.y then
							if e.n.x > node.x then
								roadE = true
							elseif e.n.x < node.x then
								roadW = true
							end
						elseif e.n.x == node.x then
							if e.n.y > node.y then
								roadN = true
							end
							if e.n.y < node.y then
								roadS = true
							end
						end
					end
				end
			end
			local roadBits = calculateRoadBits( roadS, roadW, roadN, roadE )
			g_cellData.flags[cellY][cellX] = bit.bor( g_cellData.flags[cellY][cellX], bit.bor( roadBits, cliffBits ) )
		end
	end

	-- Statistics init
	local totalCliffTilesUsed = 0
	local cliffUsage = {}
	for i = 0, 255 do
		cliffUsage[i] = -1
	end
	for i = 0, 255 do
		local tileId1, rotation1 = getCliffRoadTileIdAndRotation( i, 0 )
		if not tileId1:isNil() then
			local bits = bit.bor( i, bit.lshift( i, 8 ) )
			bits = bit.rshift( bits, 2 * rotation1 )
			bits = bit.band( bits, 0xff )
			cliffUsage[bits] = 0
		end
	end
	
	for cellY = g_cellData.bounds.yMin + g_cellData.padding, g_cellData.bounds.yMax - g_cellData.padding do
		for cellX = g_cellData.bounds.xMin + g_cellData.padding, g_cellData.bounds.xMax - g_cellData.padding do
			-- Evaluate flags
			local flags = getRoadCliffFlags( cellX, cellY )
			local tileId, rotation = getCliffRoadTileIdAndRotation( flags, sm.noise.intNoise2d( cellX, cellY, g_cellData.seed + 2854 ) )
			if not tileId:isNil() and g_cellData.uid[cellY][cellX]:isNil() then
				g_cellData.uid[cellY][cellX] = tileId
				g_cellData.xOffset[cellY][cellX] = 0
				g_cellData.yOffset[cellY][cellX] = 0
				g_cellData.rotation[cellY][cellX] = rotation
				g_cellData.groupId[cellY][cellX] = 0
			end
			
			-- Cliff usage statistics calculation
			local cliffIndex = bit.band( flags, 0xff )
			local tileId1, rotation1 = getCliffRoadTileIdAndRotation( cliffIndex, 0 )
			if not tileId1:isNil() then
				local bits = bit.bor( cliffIndex, bit.lshift( cliffIndex, 8 ) )
				bits = bit.rshift( bits, 2 * rotation1 )
				bits = bit.band( bits, 0xff )
				
				cliffIndex = bits;
				
				cliffUsage[cliffIndex] = cliffUsage[cliffIndex] + 1
				totalCliffTilesUsed = totalCliffTilesUsed + 1
			end
		end
	end

	for i = 0, 255 do
		if cliffUsage[i] > 0 then
			local percentage = math.floor( 100000 * cliffUsage[i] / totalCliffTilesUsed ) / 1000
			local spaces = ""
			local n = 10000
			while n > cliffUsage[i] do
				spaces = spaces.." "
				n = n / 10
			end
		end
	end
end

----------------------------------------------------------------------------------------------------

function setForcedAndLakeAdjacentPoiHillynessToZero( poi )
	if not poi.flat then
		return
	end
	local halfSize = math.floor( poi.size / 2 )

	local lake = false

	if not poi.forceFlat then
		for y0 = -1, poi.size + 1 do
			local corner = y0 == -1 or y0 == poi.size + 1
			for x0 = corner and 0 or -1, poi.size + ( corner and 0 or 1 ) do
				local x = poi.x + x0 - halfSize
				local y = poi.y + y0 - halfSize
				if insideCornerBounds( x, y ) then
					if g_cornerTemp.lakeAdjacent[y][x] then
						lake = true
					end
				end
			end
		end
	end

	if lake or poi.forceFlat then
		for y0 = -1, poi.size + 1 do
			local corner = y0 == -1 or y0 == poi.size + 1
			for x0 = corner and 0 or -1, poi.size + ( corner and 0 or 1 ) do
				local x = poi.x + x0 - halfSize
				local y = poi.y + y0 - halfSize
				if insideCornerBounds( x, y ) then
					g_cornerTemp.hillyness[y][x] = 0
				end
			end
		end
	end
end

----------------------------------------------------------------------------------------------------

function smoothPoiElevation( poi )
	if not poi.elevationSmoothing then
		return
	end

	local halfSize = math.floor( poi.size / 2 )
	local avg = 0
	local count = 0

	for y0 = 0, poi.size do
		for x0 = 0, poi.size do
			local x = poi.x + x0 - halfSize
			local y = poi.y + y0 - halfSize
			if insideCornerBounds( x, y ) then
				avg = avg + g_cellData.elevation[y][x]
				count = count + 1
			end
		end
	end

	if count == 0 then
		return
	end

	avg = avg / count
	local ringCount = poi.elevationSmoothing

	for y0 = -ringCount, poi.size + ringCount do
		for x0 = -ringCount, poi.size + ringCount do
			local dx = 0
			local dy = 0

			if x0 < 0 then
				dx = -x0
			elseif x0 > poi.size then
				dx = x0 - poi.size
			end

			if y0 < 0 then
				dy = -y0
			elseif y0 > poi.size then
				dy = y0 - poi.size
			end

			local ring = math.max( dx, dy )
			if ring > 0 and ring <= ringCount then
				local x = poi.x + x0 - halfSize
				local y = poi.y + y0 - halfSize
				if insideCornerBounds( x, y ) then
					local blend = ( ringCount - ring + 1 ) / ( ringCount + 1 )
					local elevation = g_cellData.elevation[y][x]
					g_cellData.elevation[y][x] = elevation + ( avg - elevation ) * blend
				end
			end
		end
	end
end

----------------------------------------------------------------------------------------------------

function flattenPoiElevation( poi )
	if not poi.flat then
		return
	end
	local halfSize = math.floor( poi.size / 2 )

	-- Elevation flatten
	local avg = 0
	local count = 0
	local lake = false

	for y0 = -1, poi.size + 1 do
		local corner = y0 == -1 or y0 == poi.size + 1
		for x0 = corner and 0 or -1, poi.size + ( corner and 0 or 1 ) do
			local x = poi.x + x0 - halfSize
			local y = poi.y + y0 - halfSize
			if insideCornerBounds( x, y ) then
				avg = avg + g_cellData.elevation[y][x]
				count = count + 1
				lake = lake or g_cornerTemp.lakeAdjacent[y][x] or poi.type == POI_TEST
			end
		end
	end

	if lake then
		avg = 0
	else
		avg = round( 4 * avg / count ) / 4 -- Round to block grid
	end

	for y0 = -1, poi.size + 1 do
		local corner = y0 == -1 or y0 == poi.size + 1
		for x0 = corner and 0 or -1, poi.size + ( corner and 0 or 1 ) do
			local x = poi.x + x0 - halfSize
			local y = poi.y + y0 - halfSize
			if insideCornerBounds( x, y ) then
				g_cellData.elevation[y][x] = avg
			end
		end
	end

	for y0 = 0, poi.size  do
		for x0 = 0, poi.size do
			local x = poi.x + x0 - math.floor( poi.size / 2 )
			local y = poi.y + y0 - math.floor( poi.size / 2 )
			if insideCellBounds( x, y ) then
				g_cellData.flags[y][x] = bit.bor( g_cellData.flags[y][x], MASK_FLAT )
			end
		end
	end
end

----------------------------------------------------------------------------------------------------

function addExtraPois( pois, padding )
	local mediumExtraPoiCount = 0
	local smallExtraPoiCount = 0
	local mediumExtraSpots = {}
	local smallExtraSpots = {}
	for i = 0,30 do
		for j = 0,40 do
			local y = i * 3 - 46
			local x = j * 3 - 62 + ( i % 3 )
			local terrainType = g_cornerTemp.terrainType[y][x]
			local fits = 	g_cornerTemp.terrainType[y][x + 1] == terrainType
						and g_cornerTemp.terrainType[y][x + 2] == terrainType
						and g_cornerTemp.terrainType[y + 1][x] == terrainType
						and g_cornerTemp.terrainType[y + 1][x + 1] == terrainType
						and g_cornerTemp.terrainType[y + 1][x + 2] == terrainType
						and g_cornerTemp.terrainType[y + 2][x] == terrainType
						and g_cornerTemp.terrainType[y + 2][x + 1] == terrainType
						and g_cornerTemp.terrainType[y + 2][x + 2] == terrainType
						and g_cellData.flags[y][x] == 0
						and g_cellData.flags[y][x + 1] == 0
						and g_cellData.flags[y + 1][x] == 0
						and g_cellData.flags[y + 1][x + 1] == 0
			if fits and not collides( x + 1, y + 1, 4, pois ) then
				mediumExtraSpots[#mediumExtraSpots + 1] = {
					x = x + 1,
					y = y + 1,
					terrainType = terrainType
				}
				--ddBox( "extrapoi", x, y, 2, 2, "00ff00" )
			else
				local offsets = { { x = 0, y = 0 }, { x = 1, y = 0 }, { x = 0, y = 1 }, { x = 1, y = 1 } }
				shuffle( offsets )
				for k = 1 , #offsets do
					y = i * 3 - 46 + offsets[k].y
					x = j * 3 - 62 + ( i % 3 ) + offsets[k].x
					terrainType = g_cornerTemp.terrainType[y][x]
					fits = 	g_cornerTemp.terrainType[y][x + 1] == terrainType
						and g_cornerTemp.terrainType[y + 1][x] == terrainType
						and g_cornerTemp.terrainType[y + 1][x + 1] == terrainType
						and g_cellData.flags[y][x] == 0
					if fits and not collides( x, y, 3, pois ) then
						smallExtraSpots[#smallExtraSpots + 1] = {
							x = x,
							y = y,
							terrainType = terrainType
						}
						--ddBox( "extrapoi", x, y, 1, 1, "00ff00" )
						break
					end
				end
			end
		end
	end
	print( "Medium extra poi spots:", #mediumExtraSpots )
	print( "Small extra poi spots:", #smallExtraSpots )

	local writeTerrainType = function( poi )
		local x0 = poi.x - math.floor( poi.size / 2 )
		local y0 = poi.y - math.floor( poi.size / 2 )
		local terrainType = math.floor( poi.type / 100 )
		for _y = y0, y0 + poi.size do
			for _x = x0, x0 + poi.size do
				if g_cornerTemp.terrainType[_y][_x] ~= terrainType then
					goto roadchecks
				end
			end
		end
		do
			return true
		end
		::roadchecks::
		for _y = y0 - 1, y0 + poi.size do
			for _x = x0 - 1, x0 + poi.size do
				local roadBits = bit.band( g_cellData.flags[_y][_x], MASK_ROADS )
				if roadBits ~= 0 then
					if 	g_cornerTemp.terrainType[_y][_x] ~= terrainType
					or 	g_cornerTemp.terrainType[_y][_x + 1] ~= terrainType
					or	g_cornerTemp.terrainType[_y + 1][_x] ~= terrainType
					or	g_cornerTemp.terrainType[_y + 1][_x + 1] ~= terrainType then
						return false
					end
				end
			end
		end
		for _y = y0, y0 + poi.size do
			for _x = x0, x0 + poi.size do
				g_cornerTemp.terrainType[_y][_x] = terrainType
			end
		end
		return true
	end

	shuffle( mediumExtraSpots )
	for i = 1, #mediumExtraSpots do
		local spot = mediumExtraSpots[i]
		local poi = {
			x = spot.x,
			y = spot.y,
			type = nil,
			size = nil,
			road = false,
			flat = false,
			terrainType = spot.terrainType,
			edges = {}
		}
		if selectRandomPoiType( poi, 2, spot.terrainType ) then
			if writeTerrainType( poi ) then
				writePoi( poi, padding )
				if poi.size == 2 then
					mediumExtraPoiCount = mediumExtraPoiCount + 1
				else
					smallExtraPoiCount = smallExtraPoiCount + 1
				end
				--pois[#pois + 1] = poi -- Not needed, just slows down collides check
			else
				unselectRandomPoiType( 2, spot.terrainType )
			end
		end
	end
	shuffle( smallExtraSpots )
	for i = 1, #smallExtraSpots do
		local spot = smallExtraSpots[i]
		local poi = {
			x = spot.x,
			y = spot.y,
			type = nil,
			size = nil,
			road = false,
			flat = false,
			terrainType = spot.terrainType,
			edges = {}
		}
		if selectRandomPoiType( poi, 1, spot.terrainType ) then
			if writeTerrainType( poi ) then
				writePoi( poi, padding )
				smallExtraPoiCount = smallExtraPoiCount + 1
				--pois[#pois + 1] = poi -- Not needed, just slows down collides check
			else
				unselectRandomPoiType( 1, spot.terrainType )
			end
		end
	end
	print( "Medium extra pois:", mediumExtraPoiCount )
	print( "Small extra pois:", smallExtraPoiCount )
end

----------------------------------------------------------------------------------------------------

function evaluateType( type, fn )
	forEveryCell( function( x, y )
		if not g_cellData.uid[y][x]:isNil() then
			return
		end
		local typeSE = bit.tobit( g_cornerTemp.terrainType[y][x + 1] == type and 8 or 0 )
		local typeSW = bit.tobit( g_cornerTemp.terrainType[y][x] == type and 4 or 0 )
		local typeNW = bit.tobit( g_cornerTemp.terrainType[y + 1][x] == type and 2 or 0 )
		local typeNE = bit.tobit( g_cornerTemp.terrainType[y + 1][x + 1] == type and 1 or 0 )
		local typeBits = bit.bor( typeSE, typeSW, typeNW, typeNE )
		local tileId, rotation = fn( typeBits, sm.noise.intNoise2d( x, y, g_cellData.seed + 2854 ), sm.noise.intNoise2d( x, y, g_cellData.seed + 9439 ) )
		if not tileId:isNil() then
			g_cellData.uid[y][x] = tileId
			g_cellData.rotation[y][x] = rotation
			g_cellData.xOffset[y][x] = 0
			g_cellData.yOffset[y][x] = 0
			g_cellData.flags[y][x] = bit.bor( g_cellData.flags[y][x], bit.band( bit.lshift( type, SHIFT_TERRAINTYPE ), MASK_TERRAINTYPE ) )
		end
	end )
end

----------------------------------------------------------------------------------------------------
