TUNNEL_MAX_WIDTH = 6 -- Applied when culling tunnels positions to cells

local function calcSplineDistances( tunnel )
	local distances = {}
		distances[1] = 0
		local a = tunnel.positions[1]
		for i = 2, #tunnel.positions do
			local b = tunnel.positions[i]
			local d = ( b - a ):length()
			distances[i] = distances[i - 1] + d
			a = b
		end
	return distances
end

local function prepareSpline( tunnel, distances, splineDetail )
	local splineTunnel = {}
	local prevPos, pos, nextPos, dir, up, right
	pos = spline( tunnel.positions, 1, distances )
	nextPos = spline( tunnel.positions, 1 + 1 / splineDetail, distances )
	dir = ( nextPos - pos ):normalize()
	up = sm.vec3.new( 0, 0, 1 )
	if ( dir - up ):length2() < 1e-4 or ( -dir - up ):length2() < 1e-4 then
		up = sm.vec3.new( 1, 0, 0 ) -- TODO: Find better up
	end
	right = dir:cross( up ):normalize()
	up = right:cross( dir ):normalize()
	splineTunnel[#splineTunnel + 1] = { pos = pos, right = right, up = up }
	prevPos = pos
	pos = nextPos
	for p = 1, ( #tunnel.positions - 1 ) * splineDetail - 1 do
		nextPos = spline( tunnel.positions, 1 + ( p + 1 ) / splineDetail, distances )
		if nextPos == prevPos then
			sm.debugDraw.addSphere( "VoxelProcDebug_ErrorSpline"..tostring( nextPos ), nextPos, 1, sm.color.new( 1, 0, 0 ) )
			sm.log.error( "Warning: tunnel spline produced identical consecutive points", nextPos )
		end
		dir = ( nextPos - prevPos ):normalize()
		up = sm.vec3.new( 0, 0, 1 )
		if ( dir - up ):length2() < 1e-4 or ( -dir - up ):length2() < 1e-4 then
			up = splineTunnel[#splineTunnel].up
		end
		if ( dir - up ):length2() < 1e-4 or ( -dir - up ):length2() < 1e-4 then
			up = sm.vec3.new( 1, 0, 0 )
		end
		right = dir:cross( up ):normalize()
		up = right:cross( dir ):normalize()

		splineTunnel[#splineTunnel + 1] = { pos = pos, right = right, up = up }
		prevPos = pos
		pos = nextPos
	end
	dir = ( pos - prevPos ):normalize()
	up = sm.vec3.new( 0, 0, 1 )
	if dir:abs() == up then
		up = sm.vec3.new( 1, 0, 0 )
	end
	right = dir:cross( up ):normalize()
	up = right:cross( dir ):normalize()
	splineTunnel[#splineTunnel + 1] = { pos = pos, right = right, up = up }
	prevPos = pos
	pos = nextPos
	return splineTunnel
end

local function ddHullSegment( name, idxTunnel, idxSegment, hull, startIndex, color )
    color = color or sm.color.new( 1, 1, 0 )
    local prev = hull[#hull]
    for j = startIndex, #hull do
        sm.debugDraw.addArrow( name..idxTunnel.."_"..idxSegment.."_"..j, prev, hull[j], color )
        prev = hull[j]
    end
end

local function selectCrossSection( idxTunnel, shape, i, count )
	local defaultCrossSection = { { -0.5, -1.0 }, { 0.5, -1.0 }, { 1.0, -0.5 }, { 1.0, 0.5 }, { 0.5, 1.0 }, { -0.5, 1.0 }, { -1.0, 0.5 }, { -1.0, -0.5 } }
	local flatFloorCrossSection = { { -1.0, 0.0 }, { 1.0, 0.0 }, { 1.0, 0.5 }, { 0.25, 1.0 }, { -0.25, 1.0 }, { -1.0, 0.5 } }
	local floorCrossSection = { { -0.5, -0.5 }, { 0.5, -0.5 }, { 0.5, 0 }, { -0.5, 0 } }
	local crossSections = {
		--["vein_rich"] = defaultCrossSection,
	}
	if crossSections[shape] then
		return crossSections[shape]
	end
	return defaultCrossSection
end

local function selectSize( idxTunnel, shape, i, count )
	local signedNoise = function( seedC, seedM, div ) return sm.noise.simplexNoise1d( seedC + idxTunnel * seedM + i / div ) end
	local absNoise = function( seedC, seedM, div ) return math.abs( sm.noise.simplexNoise1d( seedC + idxTunnel * seedM + i / div ) ) end

	local startSizes = {
		["vein_rich"] = { 1, 1 },
		["vein_t1_rock1"] = { 2, 2 },
		["vein_t1_clear"] = { 0, 0 },
	}
	local endSizes = {
		["vein_rich"] = { 1, 1 },
		["vein_t1_rock1"] = { 2, 2 },
		["vein_t1_clear"] = { 0, 0 },
	}
	local sizeFunctions = {
		["vein_rich"] = {
			function() return clamp( 5 * signedNoise( 2672, 2, 1.7 ) + 1, 2, 4 ) end,
			function() return clamp( 5 * signedNoise( 2672, 2, 1.7 ) + 1, 2, 4 ) end,
		},
		["vein_t1_t1"] = {
			function() return math.sqrt( clamp( math.sin( math.pi * ( i / 3 - 0.5 ) ), 0, 1 ) ) * 3 end,
			function() return math.sqrt( clamp( math.sin( math.pi * ( i / 3 - 0.5 ) ), 0, 1 ) ) * 3 end,
		},
		["vein_t1_rock1"] = {
			function() return math.max( clamp( 4 * absNoise( 2791, 131, 1.7 ) + 2, 2, 5 ),
				math.sqrt( clamp( ( math.sin( math.pi * ( i / 3 - 0.5 ) ) + 0.5 ) / 1.5, 0, 1 ) ) * 4.5 ) end,
			function() return math.max( clamp( 4 * absNoise( 2791, 131, 1.7 ) + 2, 2, 5 ),
				math.sqrt( clamp( ( math.sin( math.pi * ( i / 3 - 0.5 ) ) + 0.5 ) / 1.5, 0, 1 ) ) * 4.5 ) end,
		},
		["vein_t1_clear"] = {
			function() return clamp( 4 * absNoise( 2791, 131, 1.7 ) + 1, 1, 2 ) end,
			function() return clamp( 4 * absNoise( 2791, 131, 1.7 ) + 1, 1, 2 ) end,
		},
		["vein_t4_rock1"] = {
			function() return 2 end,
			function() return 2 end,
		},
		["vein_t4_t4"] = {
			function() return math.sqrt( clamp( math.sin( math.pi * ( i / 6 - 0.5 ) ), 0, 1 ) ) * 4.5 end,
			function() return math.sqrt( clamp( math.sin( math.pi * ( i / 6 - 0.5 ) ), 0, 1 ) ) * 4.5 end,
		},
		["vein_t4_clear"] = {
			function() return math.sqrt( clamp( ( math.sin( math.pi * ( i / 6 - 0.5 ) ) - 0.5 ) * 2, 0, 1 ) ) * 3 end,
			function() return math.sqrt( clamp( ( math.sin( math.pi * ( i / 6 - 0.5 ) ) - 0.5 ) * 2, 0, 1 ) ) * 3 end,
		},
	}
	local fnSize = sizeFunctions[shape] or {
		function() return 4 end,
		function() return 4 end,
	}
	local sizeX, sizeY
	local startSize = startSizes[shape] or { fnSize[1](), fnSize[2]() }
	local endSize = endSizes[shape] or { fnSize[1](), fnSize[2]() }
	if i == 1 then
		sizeX, sizeY = startSize[1], startSize[2]
	elseif i == count then
		sizeX, sizeY = endSize[1], endSize[2]
	elseif count == 3 and i == 2 then
		sizeX, sizeY = ( startSize[1] + endSize[1] ) * 0.25 + fnSize[1]() * 0.5,
			   ( startSize[2] + endSize[2] ) * 0.25 + fnSize[2]() * 0.5
	elseif i == 2 then
		sizeX, sizeY = ( startSize[1] + fnSize[1]() ) * 0.5,
			   ( startSize[2] + fnSize[2]() ) * 0.5
	elseif i == count - 1 then
		sizeX, sizeY = ( endSize[1] + fnSize[1]() ) * 0.5,
			   ( endSize[2] + fnSize[2]() ) * 0.5
	else
		sizeX, sizeY = fnSize[1](), fnSize[2]()
	end
	return sizeX, sizeY
end

local function selectOffset( idxTunnel, shape, i, count )
	local customEndOffsets = {
		--["vein_t1_rock1"] = { 0, -1 },
	}
	local customOffsets = {
		--["vein_t1_rock1"] = { 0, -1 },
	}
	local endOffset = customEndOffsets[shape] or { 0, 0 }
	local offset = customOffsets[shape] or { 0, 0 }
	if i == 1 or i == count then
		return endOffset[1], endOffset[2]
	elseif i == 2 or i == count - 1 then
		return ( offset[1] + endOffset[1] ) * 0.5, ( offset[2] + endOffset[2] ) * 0.5
	end
	return offset[1], offset[2]
end

local function selectTunnelShape( idxTunnel, shape, i, count )
	local crossSection = selectCrossSection( idxTunnel, shape, i, count )
	local size = { selectSize( idxTunnel, shape, i, count ) }
	local offset = { selectOffset( idxTunnel, shape, i, count ) }
	for _, crossSection in ipairs( crossSection ) do
		crossSection[1] = crossSection[1] * size[1] + offset[1]
		crossSection[2] = crossSection[2] * size[2] + offset[2]
	end
	return crossSection
end

local function addToHull( hull, shape, v )
	for j = 1, #shape do
		local s = shape[j]
		local offset = v.right * s[1] + v.up * s[2]






		local p = v.pos + offset
		hull[#hull + 1] = p
	end
end

local TunnelConfig = {
	["TtDefault"] = {
		{
			op = "set",
			density = 0,
			shape = "",
			filter = sm.voxelTerrainCell.voxelFilter.all - sm.voxelTerrainCell.voxelFilter.material7,
			noiseIntensity = 0.0,
			noiseFrequency = 0.0,
			detail = 1
		},
	},
	["TtVeinT1"] = {
		{
			op = "set",
			material = 5,
			density = 1,
			shape = "vein_t1_t1",
			filter = sm.voxelTerrainCell.voxelFilter.material2,
			noiseIntensity = 0.0,
			noiseFrequency = 0.0,
			detail = 3
		},
		{
			op = "set",
			material = 1,
			density = 1,
			shape = "vein_t1_rock1",
			filter = sm.voxelTerrainCell.voxelFilter.material2,
			noiseIntensity = 0.25,
			noiseFrequency = 0.2,
			detail = 3
		},
		{
			op = "set",
			density = 0,
			shape = "vein_t1_clear",
			filter = sm.voxelTerrainCell.voxelFilter.material1,
			noiseIntensity = 0.0,
			noiseFrequency = 0.0,
			detail = 3
		},
	},
	["TtVeinT4"] = {
		{
			op = "set",
			material = 5,
			density = 1,
			shape = "vein_t4_t4",
			filter = sm.voxelTerrainCell.voxelFilter.material2,
			noiseIntensity = 0.0,
			noiseFrequency = 0.0,
			detail = 3
		},
		{
			op = "set",
			material = 1,
			density = 1,
			shape = "vein_t4_rock1",
			filter = sm.voxelTerrainCell.voxelFilter.material2,
			noiseIntensity = 0.25,
			noiseFrequency = 0.2,
			detail = 1
		},
		{
			op = "set",
			density = 0,
			shape = "vein_t4_clear",
			filter = sm.voxelTerrainCell.voxelFilter.material5,
			noiseIntensity = 0.0,
			noiseFrequency = 0.0,
			detail = 3
		},
	},
	["TtVeinRich"] = {
		{
			op = "set",
			material = 4,
			density = 1,
			shape = "vein_rich",
			filter = sm.voxelTerrainCell.voxelFilter.material2,
			noiseIntensity = 0.25,
			noiseFrequency = 0.2,
			detail = 1
		},
	},
	["TtVeinSparkstone"] = {
	},
}

function CarveTunnel( idxTunnel, tunnel )
	local distances = calcSplineDistances( tunnel )
	local splineTunnels = {}
	splineTunnels[1] = prepareSpline( tunnel, distances, 1 )
	splineTunnels[3] = prepareSpline( tunnel, distances, 3 )

	local tunnelConfig = {}
	if tunnel.tunnelType then
		tunnelConfig = TunnelConfig[tunnel.tunnelType] or tunnelConfig
	end
	for idxCarve, carve in ipairs( tunnelConfig ) do
		local splineTunnel = splineTunnels[carve.detail or 1]
		local a = splineTunnel[1]
		local tunnelShapeA = selectTunnelShape( idxTunnel, carve.shape, 1, #splineTunnel )
		for i = 2, #splineTunnel do
			local b = splineTunnel[i]
			local tunnelShapeB = selectTunnelShape( idxTunnel, carve.shape, i, #splineTunnel )
			local aPos = a.pos + a.up * select( 2, selectOffset( idxTunnel, carve.shape, i - 1, #splineTunnel ) )
			local bPos = b.pos + b.up * select( 2, selectOffset( idxTunnel, carve.shape, i, #splineTunnel ) )
			local hull = {}
			addToHull( hull, tunnelShapeA, a )
			local idxDdOffset = #hull + 1
			addToHull( hull, tunnelShapeB, b )







			if i == 2 then
				hull[#hull + 1] = aPos - ( bPos - aPos ) / 2
			else
				local prevPos = splineTunnel[i - 2].pos + splineTunnel[i - 2].up * select( 2, selectOffset( idxTunnel, carve.shape, i - 2, #splineTunnel ) )
				hull[#hull + 1] = ( prevPos + aPos ) / 2
			end
			if i == #splineTunnel then
				hull[#hull + 1] = bPos + ( bPos - aPos ) / 2
			else
				local nextPos = splineTunnel[i + 1].pos + splineTunnel[i + 1].up * select( 2, selectOffset( idxTunnel, carve.shape, i + 1, #splineTunnel ) )
				hull[#hull + 1] = ( bPos + nextPos ) / 2
			end
			if carve.op == "set" then
				if carve.material and carve.density then
					sm.voxelTerrainCell.setMaterialAndDensityConvexHull( hull, 0.0, carve.material, carve.density, carve.filter, carve.noiseFrequency, carve.noiseIntensity )
				elseif carve.material then
					sm.voxelTerrainCell.setMaterialConvexHull( hull, 0.0, carve.material, carve.filter, carve.noiseFrequency, carve.noiseIntensity )
				elseif carve.density then
					sm.voxelTerrainCell.setDensityConvexHull( hull, 0.0, carve.density, carve.filter, carve.noiseFrequency, carve.noiseIntensity )
				else
					error( "Carve operation 'set' requires either material or density" )
				end
			elseif carve.op == "fill" then
				sm.voxelTerrainCell.fillEmptyConvexHull( hull, 0.0, 1, carve.material, 1, carve.noiseFrequency, carve.noiseIntensity )
			else
				error( "Unknown carve operation '"..tostring( carve.op ).."'" )
			end
			a = b
			tunnelShapeA = tunnelShapeB
		end
	end
end