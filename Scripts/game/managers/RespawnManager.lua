dofile("$SURVIVAL_DATA/Scripts/game/survival_constants.lua")
dofile "$SURVIVAL_DATA/Scripts/game/survival_shapes.lua"
dofile( "$SURVIVAL_DATA/Scripts/game/managers/WarehouseManager.lua" )
dofile( "$SURVIVAL_DATA/Scripts/util.lua" )

-- Server side
RespawnManager = class( nil )

local BagVersion = 2

function RespawnManager.sv_onCreate( self, overworld )
	self.sv = {}

	self.sv.playerBeds = sm.storage.load( STORAGE_CHANNEL_BEDS )
	if self.sv.playerBeds then
		print( "Loaded player beds:" )
		print( self.sv.playerBeds )
	else
		self.sv.playerBeds = {}
		self:sv_saveBeds()
	end

	self.sv.permanentPlayerBeds = sm.storage.load( STORAGE_CHANNEL_PERMANENT_BEDS )
	if self.sv.permanentPlayerBeds then
		print( "Loaded permanent player beds:" )
		print( self.sv.permanentPlayerBeds )
	else
		self.sv.permanentPlayerBeds = {}
		self:sv_savePermanentBeds()
	end

	self.sv.spawners = sm.storage.load( STORAGE_CHANNEL_SPAWNERS )
	if self.sv.spawners then
		print( "Loaded spawners:" )
		print( self.sv.spawners )
	else
		self.sv.spawners = {}
		self.sv.spawners.all = {}
		self.sv.spawners.latest = {}
		self:sv_saveSpawners()
	end

	self.sv.savedBags = sm.storage.load( STORAGE_CHANNEL_BAGS )
	if self.sv.savedBags then
		local savedBagVersion = self.sv.savedBags.version and self.sv.savedBags.version or 1
		print( "Loaded bags with version", savedBagVersion, ":" )
		print( self.sv.savedBags )

		if savedBagVersion == 1 then
			local updatedSavedBags = { version = BagVersion, players = {} }
			for playerIdKey, playerBag in pairs( self.sv.savedBags ) do
				updatedSavedBags.players[playerIdKey] = {}
				updatedSavedBags.players[playerIdKey][1] = playerBag
			end
			self.sv.savedBags = updatedSavedBags
		end
		if savedBagVersion ~= BagVersion then
			print( "Upgraded bags to version", BagVersion, ":" )
			print( self.sv.savedBags )
		end
	else
		self.sv.savedBags = { version = BagVersion, players = {} }
		self:sv_saveBags()
	end

	self.sv.activePlacementCells = {}
	self.sv.loadedNodes = {}

	self.sv.latestSpawnIndex = 1
	self.sv.overworld = overworld
end

function RespawnManager.sv_onFixedUpdate( self )
	for _,bags in pairs( self.sv.savedBags.players ) do
		for _,bag in reverse_ipairs( bags ) do
			if bag.creationTick and ( sm.game.getCurrentTick() - bag.creationTick ) >= LOST_BAG_SHOW_TICKS then
				self:sv_removeBag( bag.shape )
				break
			end
		end
	end
end

function RespawnManager.sv_saveBeds( self )
	sm.storage.save( STORAGE_CHANNEL_BEDS, self.sv.playerBeds )
end

function RespawnManager.sv_savePermanentBeds( self )
	sm.storage.save( STORAGE_CHANNEL_PERMANENT_BEDS, self.sv.permanentPlayerBeds )
end

function RespawnManager.sv_saveSpawners( self )
	sm.storage.save( STORAGE_CHANNEL_SPAWNERS, self.sv.spawners )
end

function RespawnManager.sv_saveBags( self )
	sm.storage.save( STORAGE_CHANNEL_BAGS, self.sv.savedBags )
end

-- Game environment
function RespawnManager.sv_onSpawnCharacter( self, player )
	local playerBags = self.sv.savedBags.players[tostring( player.id )]
	if playerBags then
		sm.event.sendToGame( "sv_e_markBag", { player = player, bags = playerBags } )
	end
end

-- Interactable environment
function RespawnManager.sv_markBag( self, shape, player, creationTick )
	if player and shape and sm.exists( shape ) then
		local bag = {}
		bag.world = shape.body:getWorld()
		bag.position = shape.worldPosition
		bag.shape = shape
		bag.player = player
		bag.creationTick = creationTick

		local playerBags = self.sv.savedBags.players[tostring( player.id )]
		if playerBags == nil then
			playerBags = {}
		end
		local exists = false
		for _, playerBag in ipairs( playerBags ) do
			if playerBag.shape == shape then
				playerBag.position = bag.position
				playerBag.world = bag.world
				exists = true
			end
		end
		if not exists then
			playerBags[#playerBags+1] = bag
		end
		self.sv.savedBags.players[tostring( player.id )] = playerBags
		self:sv_saveBags()

		sm.event.sendToGame( "sv_e_markBag", { player = player, bags = playerBags } )
	end
end

-- Interactable environment
function RespawnManager.sv_unmarkBag( self, shape )
	for _, playerBags in pairs( self.sv.savedBags.players ) do
		for index, bag in ipairs( playerBags ) do
			if bag.shape == shape and index == #playerBags then
				sm.event.sendToGame( "sv_e_unmarkBag", bag.player )
				self:sv_removeBag( shape )
				break
			end
		end
	end
end

function RespawnManager.sv_removeBag( self, shape )
	local updatedSavedBags = {
		version = BagVersion,
		players = {},
		queuedBags = self.sv.savedBags.queuedBags,
		namedSpawnPoints = self.sv.savedBags.namedSpawnPoints,
		bagIdCounter = self.sv.savedBags.bagIdCounter,
	}
	for playerIdKey, playerBags in pairs( self.sv.savedBags.players ) do
		local updatedPlayerBags = {}
		local playerNeedsUpdate = false
		local player = nil
		for _, bag in ipairs( playerBags ) do
			if player == nil then
				player = bag.player
			end
			if bag.shape ~= shape then
				updatedPlayerBags[#updatedPlayerBags+1] = bag
			else
				playerNeedsUpdate = true
			end
		end
		if playerNeedsUpdate then
			sm.event.sendToGame( "sv_e_removeBag", { player = player, bags = updatedPlayerBags } )
		end
		updatedSavedBags.players[playerIdKey] = updatedPlayerBags
	end
	self.sv.savedBags = updatedSavedBags
	self:sv_saveBags()
end

function RespawnManager.sv_addSpawners( self, nodes )
	for i, node in ipairs( nodes ) do
		self.sv.spawners.all[#self.sv.spawners+1] = node
	end
	self:sv_saveSpawners()
end

function RespawnManager.sv_setLatestSpawners( self, nodes )
	self.sv.spawners.latest = nodes
	self.sv.latestSpawnIndex = 1
	self:sv_saveSpawners()
end

function RespawnManager.sv_bedNoLongerAvailable( self, player )
	local playerPermanentBed = self:sv_getPlayerBed( player )
	if playerPermanentBed then			
		if playerPermanentBed.location == "CrashedShip" then
			sm.event.sendToPlayer( player, "sv_e_onMsg", "#{INFO_HOME_CRASH_SITE}" )
		elseif playerPermanentBed.location == "MechanicStation" then
			sm.event.sendToPlayer( player, "sv_e_onMsg", "#{INFO_HOME_MECHANIC_STATION}" )
		elseif playerPermanentBed.location == "MiningHub" then
			sm.event.sendToPlayer( player, "sv_e_onMsg", "#{INFO_HOME_MINING_HUB}" )
		end
	else
		sm.event.sendToPlayer( player, "sv_e_onMsg", "#{INFO_HOME_CRASH_SITE}" )
	end	
end

function RespawnManager.sv_destroyBed( self, shape )

	local updatedPlayerBeds = {}
	local playersUsingBed = {}

	for playerBedKey, playerBed in pairs( self.sv.playerBeds ) do
		if playerBed.shape and playerBed.shape == shape then
			if sm.exists( playerBed.player ) then
				playersUsingBed[#playersUsingBed+1] = playerBed.player
			end
			updatedPlayerBeds[playerBedKey] = nil
		else
			updatedPlayerBeds[playerBedKey] = playerBed
		end
	end

	self.sv.playerBeds = updatedPlayerBeds
	self:sv_saveBeds()

	for _, player in ipairs( playersUsingBed ) do
		self:sv_bedNoLongerAvailable( player )
	end
end

local PermanentBedUuids = {
	sm.uuid.new( "d4a74caa-6ffc-4f20-960c-b719e4402081" ),
	sm.uuid.new( "863e8585-4548-4cd8-a221-c123aeaab060" )
}

function RespawnManager.sv_registerBed( self, shape, character )
	if character:isPlayer() then
		local playerBed = {}
		playerBed.world = shape.body:getWorld()
		playerBed.shape = shape
		playerBed.position = shape.worldPosition
		playerBed.rotation = shape.worldRotation
		playerBed.player = character:getPlayer()

		if isAnyOf( shape.uuid, PermanentBedUuids ) and shape.body:isStatic() and not shape.convertableToDynamic then
			
			local pubData = playerBed.world.publicData
			local worldType = pubData and pubData.type
			if worldType == "Overworld" then
				if ( playerBed.position - START_AREA_SPAWN_POINT ):length() <= CELL_SIZE then
					playerBed.location = "CrashedShip"
				else
					playerBed.location = "MechanicStation"
				end
			elseif worldType == "UndergroundWorld" then
				playerBed.location = "MiningHub"
			end

			self.sv.permanentPlayerBeds[tostring( character:getPlayer().id )] = playerBed
			self:sv_savePermanentBeds()

			self.sv.playerBeds[tostring( character:getPlayer().id )] = nil
			self:sv_saveBeds()

			assert( playerBed.location, "Couldn't determine location for permanent bed in world type " .. tostring( worldType ) .. " at position " .. tostring( playerBed.position ) )
		else
			self.sv.playerBeds[tostring( character:getPlayer().id )] = playerBed
			self:sv_saveBeds()
		end
	end
end

function RespawnManager.sv_clearBeds( self, player )
	if player then
		self.sv.permanentPlayerBeds[tostring( player.id )] = nil
		self:sv_savePermanentBeds()
		self.sv.playerBeds[tostring( player.id )] = nil
		self:sv_saveBeds()
	end
end

function RespawnManager.sv_updateBed( self, shape )
	local updatedPlayerBeds = {}
	for playerBedKey, playerBed in pairs( self.sv.playerBeds ) do
		if playerBed.shape and sm.exists( playerBed.shape ) and playerBed.shape == shape then
			playerBed.position = shape.worldPosition
			playerBed.rotation = shape.worldRotation
			playerBed.world = shape.body:getWorld()
		end
		updatedPlayerBeds[playerBedKey] = playerBed
	end
	self.sv.playerBeds = updatedPlayerBeds
	self:sv_saveBeds()
end

function RespawnManager.Sv_CheckBedsVoxelCovered( world, constructions )
	if g_respawnManager then
		g_respawnManager:sv_checkBedsVoxelCovered( world, constructions )
	end
end

function RespawnManager.sv_checkBedsVoxelCovered( self, world, constructions )

	local bedsToCheck = {}
	for playerIdKey, playerBed in pairs( self.sv.playerBeds ) do
		if playerBed.world == world then
			bedsToCheck[playerIdKey] = playerBed
		end
	end

	if IsEmptyTable( bedsToCheck ) then
		return
	end

	local affectedBedKeys = {}
	for _, construction in ipairs( constructions ) do
		for i = 1, 8 do
			if construction.densities[i] > 0 then
				local aabbMin = construction.aabbsMin[i] - 1
				local aabbMax = construction.aabbsMax[i] + 1
				for playerIdKey, playerBed in pairs( bedsToCheck ) do
					if playerBed.shape and sm.exists( playerBed.shape ) then
						local shape = playerBed.shape
						local halfExtent = shape:getBoundingBox() * 0.5
						local rot = shape.worldRotation
						local axisX = rot * sm.vec3.new( halfExtent.x, 0, 0 )
						local axisY = rot * sm.vec3.new( 0, halfExtent.y, 0 )
						local axisZ = rot * sm.vec3.new( 0, 0, halfExtent.z )
						local worldHalfExtent = sm.vec3.new(
							math.abs( axisX.x ) + math.abs( axisY.x ) + math.abs( axisZ.x ),
							math.abs( axisX.y ) + math.abs( axisY.y ) + math.abs( axisZ.y ),
							math.abs( axisX.z ) + math.abs( axisY.z ) + math.abs( axisZ.z )
						)

						local pos = shape.worldPosition
						local bedMin = pos - worldHalfExtent
						local bedMax = pos + worldHalfExtent
						if bedMax.x >= aabbMin.x and bedMax.y >= aabbMin.y and bedMax.z >= aabbMin.z and bedMin.x <= aabbMax.x and bedMin.y <= aabbMax.y and bedMin.z <= aabbMax.z then
							affectedBedKeys[playerIdKey] = { bed = playerBed, player = construction.player }
						end
					end
				end
			end
		end
	end

	for playerIdKey, data in pairs( affectedBedKeys ) do
		local bedPos = data.bed.shape.worldPosition
		local referencePos = bedPos
		if data.player and data.player.character and sm.exists( data.player.character ) then
			referencePos = data.player.character:getWorldPosition()
		end
		if not world:isVoxelTerrainPointClear( referencePos, bedPos ) then
			local player = data.bed.player
			self.sv.playerBeds[playerIdKey] = nil
			self:sv_bedNoLongerAvailable( player )
		end
	end

	if not IsEmptyTable( affectedBedKeys ) then
		self:sv_saveBeds()
	end
end

function RespawnManager.sv_getPlayerBed( self, player )
	-- Find placed bed
	local playerBed = self.sv.playerBeds[tostring( player.id )]

	if playerBed == nil then
		-- Find permanent bed
		playerBed = self.sv.permanentPlayerBeds[tostring( player.id )]
	end

	return playerBed
end

function RespawnManager.sv_getSpawner( self, character )
	local spawnPosition = g_survivalDev and SURVIVAL_DEV_SPAWN_POINT or START_AREA_SPAWN_POINT
	local spawnRotation = sm.quat.identity()

	if character:getWorld() == self.sv.overworld then
		-- Find the closest saved spawner
		local closestSpawnerDistance = nil
		local closestSpawner = nil
		for _, spawner in pairs( self.sv.spawners.all ) do
			local spawnerDistance = ( spawner.position - character.worldPosition ):length()
			if closestSpawnerDistance == nil then
				closestSpawnerDistance = spawnerDistance
				closestSpawner = spawner
			else
				if spawnerDistance < closestSpawnerDistance  then
					closestSpawnerDistance = spawnerDistance
					closestSpawner = spawner
				end
			end
		end

		if closestSpawner ~= nil then
			spawnPosition = closestSpawner.position
			spawnRotation = closestSpawner.rotation
		end
	elseif not IsEmptyTable( self.sv.spawners.latest ) then
		-- Use the latest nearby nodes
		local spawner = self.sv.spawners.latest[self.sv.latestSpawnIndex]
		self.sv.latestSpawnIndex = ( self.sv.latestSpawnIndex % #self.sv.spawners.latest ) + 1
		spawnPosition = spawner.position
		spawnRotation = spawner.rotation
	end

	return spawnPosition, spawnRotation
end

-- Game environment helper function
function RespawnManager.sv_requestRespawnCharacter( self, player )
	local spawnPosition = g_survivalDev and SURVIVAL_DEV_SPAWN_POINT or START_AREA_SPAWN_POINT
	local respawnWorld = self.sv.overworld

	-- Load respawn cell
	local playerBed = self:sv_getPlayerBed( player )
	if playerBed then
		-- Load the bed's position if it exists, otherwise use its last known position.
		if playerBed.shape and sm.exists( playerBed.shape ) then
			spawnPosition = playerBed.shape.worldPosition
			respawnWorld = playerBed.shape.body:getWorld()
		else
			spawnPosition = playerBed.position
			respawnWorld = playerBed.world
		end
	else
		spawnPosition, _ = self:sv_getSpawner( player.character )
	end

	if not sm.exists( respawnWorld ) then
		sm.world.loadWorld( respawnWorld )
	end
	respawnWorld:loadCell( math.floor( spawnPosition.x / 64 ), math.floor( spawnPosition.y / 64 ), player, "sv_loadedRespawnCell" ) -- Callback received by the Game script
end

-- Game environment helper function
function RespawnManager.sv_respawnCharacter( self, player, world )
	local spawnPosition = g_survivalDev and SURVIVAL_DEV_SPAWN_POINT or START_AREA_SPAWN_POINT
	local spawnRotation = sm.quat.identity()

	local playerBed = self:sv_getPlayerBed( player )
	if playerBed then
		-- Spawn at the bed's position if it exists, otherwise use its last known position.
		if playerBed.shape and sm.exists( playerBed.shape ) then
			spawnPosition = playerBed.shape.worldPosition
			spawnRotation = playerBed.shape.worldRotation
		else
			spawnPosition = playerBed.position
			spawnRotation = playerBed.rotation
		end
	else
		spawnPosition, spawnRotation = self:sv_getSpawner( player.character )
	end

	spawnPosition = spawnPosition + sm.vec3.new( 0, 0, player.character:getHeight() * 0.5 )
	local yaw = 0
	local pitch = 0
	local spawnDirection = spawnRotation * sm.vec3.new( 0, 0, 1 )
	yaw = math.atan2( spawnDirection.y, spawnDirection.x ) - math.pi/2
	local newCharacter = sm.character.createCharacter( player, world, spawnPosition, yaw, pitch )
	player:setCharacter( newCharacter )

end

-- Player environment helper function
function RespawnManager.sv_performItemLoss( self, player )
	local shape = nil
	if player then
		local inventory = player:getInventory()
		local size = inventory:getSize()
		local lostItems = {}
		for i = 0, size do
			local item = inventory:getItem( i )
				if not sm.item.isTool( item.uuid ) and item.uuid ~= sm.uuid.getNil() then
				item.slot = i
				lostItems[#lostItems+1] = item
			end
		end

		local spawnPos = self:sv_getSpawnPointFromPosition( player.character.worldPosition, player.character:getWorld() )
		if not IsEmptyTable( lostItems ) then
			shape = sm.shape.createPart( obj_survivalobject_kobag, spawnPos, sm.quat.identity(), true, true )
			shape.interactable:setParams( { owner = player } )
			local lostContainer = shape.interactable:addContainer( 0, #lostItems )
			if sm.container.beginTransaction() then
				for i, item in ipairs( lostItems ) do
					sm.container.spendFromSlot( inventory, item.slot, item.uuid, item.quantity, true )
					sm.container.collectToSlot( lostContainer, i-1, item.uuid, item.quantity, true )
				end
				sm.container.endTransaction()
			end
		end
	end
end

-- make a bag at any position in any world. if possible, spawns the bag now, otherwise queues is and marks the location
function RespawnManager.sv_makeBagAtNamedNode( self, nodeName, player )

	if not self.sv.savedBags.namedSpawnPoints or not self.sv.savedBags.namedSpawnPoints[nodeName] then
		return
	end
	
	local world = self.sv.savedBags.namedSpawnPoints[nodeName].world
	local spawnPointNode = self.sv.savedBags.namedSpawnPoints[nodeName]
	
	-- get a random position in the node volume.
	local randomPos = sm.vec3.new( math.random(), math.random(), math.random() )
	randomPos = ( randomPos - sm.vec3.new( 0.5, 0.5, 0.5 ) ) * spawnPointNode.scale
	randomPos = spawnPointNode.rotation * randomPos
	randomPos = randomPos + spawnPointNode.position

	local inventory = player:getInventory()
	local size = inventory:getSize()
	local lostItems = {}
	for i = 0, size do
		local item = inventory:getItem( i )
		if not sm.item.isTool( item.uuid ) and item.uuid ~= sm.uuid.getNil() then
			item.slot = i
			lostItems[#lostItems+1] = item
		end
	end

	if #lostItems == 0 then
		return
	end

	local cellX = math.floor( randomPos.x / 64 )
	local cellY = math.floor( randomPos.y / 64 )
	if sm.exists( world ) and world:isCellLoadedServer( cellX, cellY ) then
		local shape = sm.shape.createPart( ITEMS.obj_survivalobject_kobag, randomPos, spawnPointNode.rotation, true, true, world )
		shape.interactable:setParams( { owner = player } )
		local lostContainer = shape.interactable:addContainer( 0, #lostItems )
		if sm.container.beginTransaction() then
			for i, item in ipairs( lostItems ) do
				sm.container.spendFromSlot( inventory, item.slot, item.uuid, item.quantity, true )
				sm.container.collectToSlot( lostContainer, i-1, item.uuid, item.quantity, true )
			end
			sm.container.endTransaction()
		end
	else
		self.sv.savedBags.bagIdCounter = ( self.sv.savedBags.bagIdCounter or 0 ) + 1

		-- make a bag entry that can have it's location tracked.
		local bag = {}
		bag.world = world
		bag.position = randomPos

		-- has a queued bag creation id instead of a shape
		bag.queued = {
			contents = {},
			id = self.sv.savedBags.bagIdCounter,
		}
		bag.shape = nil

		bag.player = player
		bag.creationTick = sm.game.getCurrentTick()


		if sm.container.beginTransaction() then
			for i, item in ipairs( lostItems ) do
				sm.container.spendFromSlot( inventory, item.slot, item.uuid, item.quantity, true )
				bag.queued.contents[i] = { uuid = item.uuid, quantity = item.quantity }
			end
			sm.container.endTransaction()
		end

		-- put in the queued bags list to check when loading cells
		self.sv.savedBags.queuedBags = self.sv.savedBags.queuedBags or {}
		self.sv.savedBags.queuedBags[world.id] = self.sv.savedBags.queuedBags[world.id] or {}
		local cellKey = CellKey( cellX, cellY )
		self.sv.savedBags.queuedBags[world.id][cellKey] = self.sv.savedBags.queuedBags[world.id][cellKey] or {}
		table.insert( self.sv.savedBags.queuedBags[world.id][cellKey], bag.queued.id )

		local playerBags = self.sv.savedBags.players[tostring( player.id )]
		if playerBags == nil then
			playerBags = {}
		end
		playerBags[#playerBags+1] = bag
		self.sv.savedBags.players[tostring( player.id )] = playerBags
		self:sv_saveBags()

		sm.event.sendToGame( "sv_e_markBag", { player = player, bags = playerBags } )
	end
end

-- Lost bag placement

function RespawnManager.Sv_OnCellLoaded( x, y, world )
    g_respawnManager:sv_onCellLoaded( x, y, world )
end

function RespawnManager.sv_onCellLoaded( self, x, y, world )
	local cellKey = CellKey( x, y )
	local save = false
	-- Check for queued bags to spawn in this cell
	if self.sv.savedBags.queuedBags and self.sv.savedBags.queuedBags[world.id] and self.sv.savedBags.queuedBags[world.id][cellKey] then
		for _, bagId in pairs( self.sv.savedBags.queuedBags[world.id][cellKey] ) do
			for _, playerBags in pairs( self.sv.savedBags.players ) do
				for _, bag in ipairs( playerBags ) do
					if bag.queued and bag.queued.id == bagId then
						local shape = sm.shape.createPart( ITEMS.obj_survivalobject_kobag, bag.position, bag.queued.rotation, true, true )
						shape.interactable:setParams( { owner = bag.player } )
						local lostContainer = shape.interactable:addContainer( 0, #bag.queued.contents )
						if sm.container.beginTransaction() then
							for i, item in ipairs( bag.queued.contents ) do
								sm.container.collectToSlot( lostContainer, i-1, item.uuid, item.quantity, true )
							end
							sm.container.endTransaction()
						end
						bag.shape = shape
						bag.queued = nil
						save = true
						self:sv_unmarkBag( shape )
					end
				end
			end
		end

		self.sv.savedBags.queuedBags[world.id][cellKey] = nil
	end

    local nodes = sm.cell.getNodesByTag( x, y, "LOSTLOOT_SPAWNPOINT", world )
    if not IsEmptyTable( nodes ) then
        for _, node in ipairs( nodes ) do
			if node.params and node.params.name then
				self.sv.savedBags.namedSpawnPoints = self.sv.savedBags.namedSpawnPoints or {}
				self.sv.savedBags.namedSpawnPoints[node.params.name] = node
				self.sv.savedBags.namedSpawnPoints[node.params.name].world = world
				save = true
			else
				InitializeNestedTables( self.sv, "loadedNodes", world.id, x, y )
				table.insert( self.sv.loadedNodes[world.id][x][y], node )
			end
        end
    end

	if save then
		self:sv_saveBags()
	end
end

function RespawnManager.Sv_OnCellUnloaded( x, y, world )
    g_respawnManager:sv_onCellUnloaded( x, y, world )
end

function RespawnManager.sv_onCellUnloaded( self, x, y, world )
    if self.sv.loadedNodes[world.id] == nil or self.sv.loadedNodes[world.id][x] == nil or self.sv.loadedNodes[world.id][x][y] == nil then
        return
    end
    self.sv.loadedNodes[world.id][x][y] = {}
end

function RespawnManager.sv_getSpawnPointFromPosition( self, position, world )
    local cellX = math.floor( position.x / 64 )
    local cellY = math.floor( position.y / 64 )
    if self.sv.loadedNodes[world.id] == nil or self.sv.activePlacementCells[world.id] == nil or self.sv.activePlacementCells[world.id][CellKey( cellX, cellY )] == nil then
        return position
    end

    local closestPoint = nil
    local bestDistance = math.huge

	local xMin, xMax, yMin, yMax = GetTileRanges( position, world.id )

    for x = xMin, xMax do
        for y = yMin, yMax do
            if self.sv.loadedNodes[world.id][x] and self.sv.loadedNodes[world.id][x][y] then
                for _,node in ipairs( self.sv.loadedNodes[world.id][x][y] ) do
                    if closestPoint == nil then
                        closestPoint = node.position
                    else
                        local distanceSqr = ( position - node.position ):length2()
                        if distanceSqr < bestDistance then
                            bestDistance = distanceSqr
                            closestPoint = node.position
                        end
                    end
                end
            end
        end
    end

    if closestPoint ~= nil then
        return closestPoint
    end
    return position
end

function RespawnManager.Sv_ActivateCellRange( pos, world )
    g_respawnManager:sv_activateCellRange( pos, world )
end

function RespawnManager.sv_activateCellRange( self, pos, world )
    if  self.sv.activePlacementCells[world.id] == nil then
        self.sv.activePlacementCells[world.id] = {}
    end

    local xMin, xMax, yMin, yMax = GetTileRanges( pos, world.id )

    for x = xMin, xMax do
        for y = yMin, yMax do
            self.sv.activePlacementCells[world.id][CellKey( x, y )] = true
        end
    end
end

function RespawnManager.Sv_DisableCellRange( pos, world )
    g_respawnManager:sv_disableCellRange( pos, world )
end

function RespawnManager.sv_disableCellRange( self, pos, world )
    if  self.sv.activePlacementCells[world.id] == nil then
        return
    end

    local xMin, xMax, yMin, yMax = GetTileRanges( pos, world.id )

    for x = xMin, xMax do
        for y = yMin, yMax do
            self.sv.activePlacementCells[world.id][CellKey( x, y )] = nil
        end
    end
end

-- Client
function RespawnManager.cl_onCreate( self )
	self.cl = {}
	self.cl.bags = {}
	self.cl.bagMarkerCreated = false
	self.cl.compassEnabled = sm.game.getSettingBoolean( "CompassHud" )
	self.cl.color = nil
end

-- World environment
function RespawnManager.cl_markBag( self, bags )
	local bag = bags[#bags]
	if bag then
		if not sm.exists( bag.shape ) then
			if not self.cl.bagMarkerCreated then
				WorldMarkerManager.Cl_CreateOrUpdateMarker( "RespawnManager_targetBag", {
					effect = "LostItem",
					position = bag.position,
					world = bag.world,
					compassImage = "icon_compass_lostitem.png",
					activate = true,
				})
				self.cl.bagMarkerCreated = true
			else
				WorldMarkerManager.Cl_SetWorldPosition( "RespawnManager_targetBag", bag.position, bag.world )
				WorldMarkerManager.Cl_ActivateMarker( "RespawnManager_targetBag" )
			end
		end
		self.cl.bags = bags
	end
end

-- World environment
function RespawnManager.cl_unmarkBag( self )
	WorldMarkerManager.Cl_HideMarker( "RespawnManager_targetBag" )
end

function RespawnManager.cl_removeBag( self, bags )
	self.cl.bags = bags
	if IsEmptyTable( bags ) then
		WorldMarkerManager.Cl_HideMarker( "RespawnManager_targetBag" )
	else
		self:cl_markBag( bags )
	end
end