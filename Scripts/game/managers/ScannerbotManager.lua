dofile( "$SURVIVAL_DATA/Scripts/game/survival_units.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/survival_constants.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/managers/QuestManager.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/managers/QuestEntityManager.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/managers/ProgressionManager.lua" )
dofile( "$GAME_DATA/Scripts/game/managers/EffectManager.lua" )

ScannerbotManager = class()

local IntroTickTime = math.floor( 18.75 * 40.0 )

local SaveAndSyncInterval = 40 * 5 -- Interval between regular save and sync of the scannerbot's status. ( When scannerbot is a loaded unit or while it's doing fake movement and haven't arrived yet )

local ScannerbotGroundOffsetRoad = sm.vec3.new( 0, 0, SCANNERBOT_GROUND_HEIGHT_ROAD )
local ToleranceMovementXY = 8.0 -- Same as ScannerbotMoveState
local ForgetCharacterTickTime = 40 * 12.0 -- Time since last seen that the scannerbot will forget a character
local HuntRelocateMinTickDelay = 40 * 4 -- Min amount of ticks to pass before doing a potential relocate when hunt mode starts
local HuntRelocateMaxTickDelay = 40 * 8 -- Max amount of ticks to pass before doing a potential relocate when hunt mode starts
local HuntRelocateDistance = 20 * 64 -- The scannerbot will relocate closer to its target if further away than this distance (64 cellsize)
local HuntDesiredMaxDistance = 12 * 64 -- The scannerbot will relocate to its target within these distance intervals (64 cellsize)
local HuntDesiredMinDistance = 8 * 64
local RoamDesiredMaxDistance = 64 * 64 -- The scannerbot will relocate away from its current position within these distance intervals (64 cellsize)
local RoamDesiredMinDistance = 32 * 64
local AmountOfPlayersToTrack = 8
local AmountOfPlayerLocationsToTrack = 144 -- Amount of locations stored before rewriting old locations
local PlayerTrackingTickInterval = 40 * 10 -- Tick time between storing player locations
local ChanceToHuntTrackedLocation = 0.5
local AmountOfInitialAggressiveHunts = 3 -- The amount of hunts that will be aggressive and hunt players regardless of tracked locations and hunt cooldown
local HuntCooldownTickTime = DAYCYCLE_TIME_TICKS * 1.8 -- The amount of ticks that must have passed since last hunt before allowed to hunt again
local MaxRoadVisits = 2 -- Will force a relocate if stuck
local MaxRoadVisitRelocateTickTime = 40 * 30 -- The amount of ticks that must have passed since last relocate before allowed to relocate from a stuck position

local Forward = sm.vec3.new( 0, 1, 0 )

local AscendTimeout = 30.0 -- Act as if done with ascend if this amount of time has passed
local DescendTimeout = 60.0 -- Act as if done with descend if this amount of time has passed

local GuiFadeInDuration = 0.50
local GuiFadeOutDuration = 0.50
local SeekerbotIconGuiData = dofile( "$SURVIVAL_DATA/Gui/JsonGuis/SeekerbotIcon.gui" )
local SeekerbotIconParentPanel = FindWidget( SeekerbotIconGuiData, "SeekerbotIconPanel" )
SeekerbotIconParentPanel.Alpha = 0

local ShowTargetOnSelf = false
local ShowTargetOnOthers = true

local PassiveQuestNames = {
	"quest_warehouse_destruction",
	"quest_find_excavation"
}

function ScannerbotManager.server_onCreate( self )
	g_scannerbotManager = self
	local currentTick = sm.game.getCurrentTick()
	self.sv = {}
	self.sv.saved = sm.storage.load( STORAGE_CHANNEL_SCANNERBOT_MANAGER )
	local shouldSave = false
	if self.sv.saved == nil then
		self.sv.saved = {}
		self.sv.saved.firstContactTick = nil -- The tick when the scannerbot was seen for the first time
		self.sv.saved.lastSaveAndSyncTick = currentTick -- Periodically save and sync the scannerbot
		self.sv.saved.huntMode = false -- Hunting the players or roaming
		self.sv.saved.lastHuntTick = currentTick
		self.sv.saved.scannerbotData = nil -- Timestamped data
		self.sv.saved.visitedRoads = {} -- Scanned road cells (reset each night)
		self.sv.saved.lastRelocateTick = currentTick -- When the scannerbot last finished relocating
		self.sv.saved.playerLocationData = {} -- Stored player locations, used to determine points of interest
		self.sv.saved.lastPlayerTrackingTick = currentTick
		self.sv.saved.huntModeTarget = nil -- Road of interest that was selected at the start of the hunt
		shouldSave = true
	end
	if self.sv.saved.huntsPerformed == nil then
		self.sv.saved.huntsPerformed = 0
		shouldSave = true
	end
	if shouldSave then
		sm.storage.save( STORAGE_CHANNEL_SCANNERBOT_MANAGER, self.sv.saved )
	end
	self.network:setClientData( self.sv.saved.scannerbotData, 1 )
	self.sv.needScannerbotSave = false

	if self.sv.saved.scannerbotData then
		-- The orientation of the scannerbot whether it exists or is fake
		self.sv.scannerbotPosition = self.sv.saved.scannerbotData.currentPosition
		self.sv.scannerbotDirection = self.sv.saved.scannerbotData.currentDirection
	end
	self.sv.scannerbotUnit = nil
	self.sv.previousRoadCellKey = nil
	self.sv.heightAboveGroundLevel = nil

	self.sv.characterTargets = {} -- Character and last seen tick
	self.sv.characterTargetsSync = {} -- Character
	self.network:setClientData( { characterTargets = self.sv.characterTargetsSync }, 2 )
	self.sv.needTargetSynch = false

	-- Keep track of cells of interest to the scannerbot
	self.sv.scannerbotCells = {}
	self.sv.scannerbotCells.roadCells = {}
	self.sv.scannerbotCells.warehouseCells = {}

	self.sv.loadedCells = {}
	self.sv.scannerbotCellNodes = {}
	self.sv.namedScannerbotNodes = {}

	local time = sm.game.getTimeOfDay()
	self.sv.isNightTime = time < DAYCYCLE_DAWN or time > DAYCYCLE_NIGHT
end

function ScannerbotManager.sv_loadWarehouses( self )
	-- Reset previous data
	self.sv.scannerbotCells.warehouseCells = {}

	-- Load overworld cell data
	local world = self.scriptableObject:getWorld()
	local worldId = world and world.id or 1 -- Default to overworld
	local worldCellData = GetCellDataStorage( worldId )
	for y, yData in pairs( worldCellData ) do
		for x, xyData in pairs( yData ) do
			local isWarehouse = valueExists( xyData.tags, "WAREHOUSE2" ) or
							valueExists( xyData.tags, "WAREHOUSE3" ) or
							valueExists( xyData.tags, "WAREHOUSE4" ) or
							valueExists( xyData.tags, "WAREHOUSE4QUEST" )

			if isWarehouse then
				local cellKey = CellKey( x, y )
				local terrainPosition = sm.vec3.new( x * 64 + 32, y * 64 + 32, xyData.terrainHeight )
				self.sv.scannerbotCells.warehouseCells[cellKey] = { groundPosition = terrainPosition }
			end
		end
	end
	self.sv.loadedWarehouses = true
end

function ScannerbotManager.sv_loadRoads( self )
	if not self.sv.loadedWarehouses then
		sm.log.error( "Loading roads before scanning the world for warehouses to avoid" )
	end

	-- Reset previous data
	self.sv.scannerbotCells.roadCells = {}

	-- Load overworld cell data
	local world = self.scriptableObject:getWorld()
	local worldId = world and world.id or 1 -- Default to overworld
	local worldCellData = GetCellDataStorage( worldId )
	for y, yData in pairs( worldCellData ) do
		for x, xyData in pairs( yData ) do
			local isRoad = valueExists( xyData.tags, "ROAD" )

			-- Detect roads
			if isRoad then
				local cellKey = CellKey( x, y )

				-- Prepare to check neighbour cells
				local cellNeighbourPositions = {
					{ cellX = x, cellY = y + 1 },
					{ cellX = x - 1, cellY = y },
					{ cellX = x + 1, cellY = y },
					{ cellX = x, cellY = y - 1 }
				}
				local hasWarehouseNeighbour = false
				for _, cellNeighbourPosition in ipairs( cellNeighbourPositions ) do
					-- Check if neighbour is a warehouse
					local neighbourCellKey = CellKey( cellNeighbourPosition.cellX, cellNeighbourPosition.cellY )
					if self.sv.scannerbotCells.warehouseCells[neighbourCellKey] then
						hasWarehouseNeighbour = true
						break
					end
				end
				if not hasWarehouseNeighbour then
					-- Remember road cell
					local terrainPosition = sm.vec3.new( x * 64 + 32, y * 64 + 32, xyData.terrainHeight )
					self.sv.scannerbotCells.roadCells[cellKey] = { groundPosition = terrainPosition }

					self.sv.loadedRoads = true -- Found at least one road
				end
			end
		end
	end
end

function ScannerbotManager.server_onDestroy( self )
	if sm.exists( self.sv.scannerbotUnit ) then
		self.sv.scannerbotUnit:destroy()
	end
	self.sv.scannerbotUnit = nil
end

function ScannerbotManager.server_onRefresh( self ) end

function ScannerbotManager.server_onFixedUpdate( self, timeStep )
	local currentTick = sm.game.getCurrentTick()
	local time = sm.game.getTimeOfDay()
	local wasNightTime = self.sv.isNightTime
	self.sv.isNightTime = time < DAYCYCLE_DAWN or time > DAYCYCLE_NIGHT
	if not wasNightTime and self.sv.isNightTime then -- night started
		self.sv.saved.visitedRoads = {} -- Reset number of visits to road cells
	end








































































































	-- Init terrain awareness
	if g_overworldTerrainLoaded then
		if not self.sv.loadedWarehouses then
			self:sv_loadWarehouses()
		end
		if self.sv.loadedWarehouses and not self.sv.loadedRoads then
			self:sv_loadRoads()
		end
	end
	if not self.sv.loadedRoads then
		-- Shouldn't spawn or update if no roads exists in the world
		if sm.exists( self.sv.scannerbotUnit ) then
			self.sv.scannerbotUnit:destroy()
		end
		self.sv.scannerbotUnit = nil
		return
	end

	-- Forget unit and targets when the unit is unloaded
	if self.sv.scannerbotUnit and not sm.exists( self.sv.scannerbotUnit ) then
		self.sv.scannerbotUnit = nil
		self.sv.characterTargets = {}
		self.sv.characterTargetsSync = {}
		self.sv.needTargetSynch = true
	end

	-- Update scannerbot
	if self.sv.saved.scannerbotData then -- Scannerbot is active in the overworld
		local scannerbotCharacter = ( self.sv.scannerbotUnit and sm.exists( self.sv.scannerbotUnit.character ) ) and self.sv.scannerbotUnit.character or nil
		if scannerbotCharacter then
			self.sv.scannerbotPosition = scannerbotCharacter.worldPosition
			self.sv.scannerbotDirection = sm.vec3.new( scannerbotCharacter.direction.x, scannerbotCharacter.direction.y, 0 ):safeNormalize( Forward )
		end
		if self.sv.saved.scannerbotData.scannerbotCharacter ~= scannerbotCharacter then
			-- Force sync when a character is loaded or unloaded
			self.sv.saved.scannerbotData.scannerbotCharacter = scannerbotCharacter
			self.sv.needScannerbotSave = true
		end

		-- Track player locations
		if currentTick >= self.sv.saved.lastPlayerTrackingTick + PlayerTrackingTickInterval then
			local players = sm.player.getAllPlayers()
			for _, player in ipairs( players ) do
				local playerCharacter = sm.exists( player.character ) and player.character or nil
				local overworld = WorldManager.Sv_GetWorld( "overworld" )
				if playerCharacter and overworld then
					local playerTrackingIndex = ModuloIndex( player.id, AmountOfPlayersToTrack )
					local playerTrackingData = self.sv.saved.playerLocationData[playerTrackingIndex] or {}
					local playerTrackingPosition = playerCharacter.worldPosition
					if not InSameWorld( player, overworld ) then
						-- Player is in another world, track portal position
						local portalPosition, _ = sm.portal.findBestPortalToWorld( overworld.id, playerCharacter:getWorld().id, self.sv.scannerbotPosition )
						playerTrackingPosition = portalPosition
					end
					if #playerTrackingData >= AmountOfPlayerLocationsToTrack then
						table.remove( playerTrackingData, 1 )
					end
					playerTrackingData[#playerTrackingData+1] = playerTrackingPosition
					self.sv.saved.playerLocationData[playerTrackingIndex] = playerTrackingData
				end
			end
			self.sv.saved.lastPlayerTrackingTick = currentTick
			self.sv.needScannerbotSave = true
		end

		-- Check height above ground
		if scannerbotCharacter then
			local sphereRadius = 6.0
			local testDistance = 1000.0
			local groundTestPosition = self.sv.scannerbotPosition - sm.vec3.new( 0, 0, testDistance )
			local hit, result = sm.physics.spherecast( self.sv.scannerbotPosition, groundTestPosition, sphereRadius, scannerbotCharacter, sm.physics.filter.terrainSurface + sm.physics.filter.terrainAsset )
			if hit then
				if result.type == "terrainAsset" then
					local materialName = result:getTerrainAssetMaterialName()
					if materialName ~= "Metal" then -- Only metal counts as ground, for the case of bridges
						-- Check for surface under the asset
						hit, result = sm.physics.spherecast( self.sv.scannerbotPosition, groundTestPosition, sphereRadius, scannerbotCharacter, sm.physics.filter.terrainSurface )
					end
				end
			end
			if hit then
				self.sv.heightAboveGroundLevel = testDistance * result.fraction - scannerbotCharacter:getHeight() * 0.5 + sphereRadius
			else
				local cellX = math.floor( self.sv.scannerbotPosition.x / 64 )
				local cellY = math.floor( self.sv.scannerbotPosition.y / 64 )
				local currentCellKey = CellKey( cellX, cellY )
				local currentRoadCell = self.sv.scannerbotCells.roadCells[currentCellKey]
				if currentRoadCell then
					self.sv.heightAboveGroundLevel = self.sv.scannerbotPosition.z - currentRoadCell.groundPosition.z
				else
					self.sv.heightAboveGroundLevel = nil
				end
			end
		else
			self.sv.heightAboveGroundLevel = nil
		end

		-- Toggle hunt
		local shouldHunt = self:sv_shouldHunt( currentTick )
		if shouldHunt ~= self.sv.saved.huntMode then
			self.sv.saved.huntMode = shouldHunt
			if self.sv.saved.huntMode then
				-- Switched to hunt mode
				local isInitialAggressionHunt = self.sv.saved.huntsPerformed < AmountOfInitialAggressiveHunts
				self.sv.saved.huntsPerformed = self.sv.saved.huntsPerformed + 1
				self.sv.saved.lastHuntTick = currentTick
				if math.random() < ChanceToHuntTrackedLocation and not isInitialAggressionHunt then
					self:sv_selectHuntTargetCell()
				end
				self.sv.saved.playerLocationData = {} -- Reset tracked players

				local targetPosition = self:sv_getHuntedPosition()
				if targetPosition and self.sv.scannerbotPosition then
					local flatDistance2 = ( sm.vec3.new( targetPosition.x, targetPosition.y, 0 ) - sm.vec3.new( self.sv.scannerbotPosition.x, self.sv.scannerbotPosition.y, 0 ) ):length2()
					if flatDistance2 > HuntRelocateDistance * HuntRelocateDistance then
						-- Delayed relocate if target is far away
						self.sv.requestRelocateTick = currentTick + math.random( HuntRelocateMinTickDelay, HuntRelocateMaxTickDelay )
					end
				end
			else
				-- Switched to roam mode
				self.sv.saved.huntModeTarget = nil
				local cellX = math.floor( self.sv.scannerbotPosition.x / 64 )
				local cellY = math.floor( self.sv.scannerbotPosition.y / 64 )
				local currentCellKey = CellKey( cellX, cellY )
				if self.sv.saved.visitedRoads[currentCellKey] then
					-- Relocate if the current road has already been scanned during the hunt mode
					self.sv.requestRelocateTick = currentTick
				end
			end
			self.sv.needScannerbotSave = true
		end

		-- Update behaviour
		local currentBehaviour = ScannerbotManager.Sv_GetBehaviour()
		if currentBehaviour == ScannerbotBehaviour.UNKNOWN then
			-- Attempt to fix broken state
			self:sv_initScannerbot()
		elseif currentBehaviour == ScannerbotBehaviour.ROAD then
			local toDestination = self.sv.saved.scannerbotData.desiredPosition - self.sv.scannerbotPosition
			toDestination.z = 0
			if toDestination:length2() <= ToleranceMovementXY * ToleranceMovementXY then
				-- Remember visiting this road cell +1
				local cellX = math.floor( self.sv.scannerbotPosition.x / 64 )
				local cellY = math.floor( self.sv.scannerbotPosition.y / 64 )
				local currentCellKey = CellKey( cellX, cellY )
				self.sv.saved.visitedRoads[currentCellKey] = self.sv.saved.visitedRoads[currentCellKey] and self.sv.saved.visitedRoads[currentCellKey] + 1 or 1

				local shouldRelocate = self.sv.requestRelocateTick and currentTick >= self.sv.requestRelocateTick
				if shouldRelocate then
					self.sv.requestRelocateTick = nil
					self:sv_changeLocation()
				else
					self:sv_updateRoadDestination()
				end
			end
		elseif currentBehaviour == ScannerbotBehaviour.RELOCATE then
			-- Arrived
			local toDestination = self.sv.saved.scannerbotData.desiredPosition - self.sv.scannerbotPosition
			toDestination.z = 0
			if toDestination:length2() <= ToleranceMovementXY * ToleranceMovementXY then
				self.sv.saved.scannerbotData = {
					scannerbotCharacter = scannerbotCharacter,
					currentPosition = self.sv.scannerbotPosition,
					currentDirection = self.sv.scannerbotDirection,
					desiredPosition = self.sv.saved.scannerbotData.desiredPosition,
					serverTick = currentTick,
					behaviour = ScannerbotBehaviour.RELOCATE_DESCEND
				}

				-- Reset movement ticks after arriving at a location
				self.sv.needScannerbotSave = true
			end
		elseif currentBehaviour == ScannerbotBehaviour.RELOCATE_ASCEND then
			if not self.playingAscendingEffect or currentTick >= self.sv.saved.scannerbotData.serverTick + AscendTimeout * 40 then
				-- Spent enough time ascending
				local farAboveGround = self.sv.heightAboveGroundLevel == nil or self.sv.heightAboveGroundLevel >= SCANNERBOT_GROUND_HEIGHT_RELOCATE
				if farAboveGround then
					-- Ascended
					self.sv.saved.scannerbotData = {
						scannerbotCharacter = scannerbotCharacter,
						currentPosition = self.sv.scannerbotPosition,
						currentDirection = self.sv.scannerbotDirection,
						desiredPosition = self.sv.saved.scannerbotData.desiredPosition,
						serverTick = currentTick,
						behaviour = ScannerbotBehaviour.RELOCATE
					}

					self.sv.needScannerbotSave = true
				end
			end
		elseif currentBehaviour == ScannerbotBehaviour.RELOCATE_DESCEND then
			if not self.playingDescendingEffect or currentTick >= self.sv.saved.scannerbotData.serverTick + DescendTimeout * 40 then
				-- Spent enough time descending
				local nearGround = self.sv.heightAboveGroundLevel == nil or self.sv.heightAboveGroundLevel <= SCANNERBOT_GROUND_HEIGHT_ROAD
				if nearGround then
					-- Descended
					self.sv.requestRelocateTick = nil

					-- Select cell behaviour
					local cellX = math.floor( self.sv.scannerbotPosition.x / 64 )
					local cellY = math.floor( self.sv.scannerbotPosition.y / 64 )
					local currentCellKey = CellKey( cellX, cellY )
					if not self.sv.scannerbotCells.roadCells[currentCellKey] then
						-- Arrived at a cell without a road
						sm.log.error( "Seekerbot arrived at a cell without a road. Cell:", cellX, cellY )
						self.sv.requestRelocateTick = currentTick
					end

					self.sv.saved.scannerbotData = {
						scannerbotCharacter = scannerbotCharacter,
						currentPosition = self.sv.scannerbotPosition,
						currentDirection = self.sv.scannerbotDirection,
						desiredPosition = self.sv.saved.scannerbotData.desiredPosition,
						serverTick = currentTick,
						behaviour = ScannerbotBehaviour.ROAD
					}

					self.sv.needScannerbotSave = true
					self.sv.saved.lastRelocateTick = currentTick
				end
			end
		end

		-- Update scannerbot data
		if self.sv.scannerbotUnit then
			-- Scannerbot is loaded
			-- Update scannerbot data with latest position and direction
			self.sv.saved.scannerbotData.currentPosition = self.sv.scannerbotPosition
			self.sv.saved.scannerbotData.currentDirection = self.sv.scannerbotDirection
			self.sv.saved.scannerbotData.scannerbotCharacter = scannerbotCharacter
			-- Rely on save and sync interval
		else
			-- Spawn unit
			local headingDirection = sm.vec3.new( self.sv.scannerbotDirection.x, self.sv.scannerbotDirection.y, 0.0 ):safeNormalize( Forward )
			local heading = math.atan2( -headingDirection.x, headingDirection.y )
			local spawnPosition = self.sv.scannerbotPosition
			self.sv.scannerbotUnit = sm.unit.createUnit( unit_scannerbot, spawnPosition, heading )

			self.sv.saved.scannerbotData = {
				scannerbotCharacter = scannerbotCharacter,
				currentPosition = self.sv.scannerbotPosition,
				currentDirection = self.sv.scannerbotDirection,
				desiredPosition = self.sv.saved.scannerbotData.desiredPosition,
				serverTick = currentTick,
				behaviour = self.sv.saved.scannerbotData.behaviour
			}
			self.sv.needScannerbotSave = true
		end
	else -- No scannerbot in the world
		if self:sv_shouldSpawn() then
			self:sv_initScannerbot()
		end
	end

	-- Trigger the intro Scannerbot
	if not self.sv.saved.firstContactTick then
		local playerInArea = QuestEntityManager.Sv_NamedAreaTriggerContainsPlayer( "scannerbot_first_contact_trigger" )
		if playerInArea then
			self.sv.hasHadPlayerInArea = true
		end
		if self.sv.hasHadPlayerInArea and not playerInArea then
			local scannerbotIntroNode = self.sv.namedScannerbotNodes["ScannerbotFirstSighting"]
			if scannerbotIntroNode then
				self.network:sendToClients( "cl_n_showIntroScannerbot", { startingTick = currentTick,
																		startingPosition = scannerbotIntroNode.position,
																		startingRotation = scannerbotIntroNode.rotation } )
				self.sv.saved.firstContactTick = currentTick
				sm.storage.save( STORAGE_CHANNEL_SCANNERBOT_MANAGER, self.sv.saved )
			end
		end
	end

	-- Forget unseen characters and downed players
	for characterId, characterTarget in pairs( self.sv.characterTargets ) do
		local disabledPlayerAggro = not sm.game.getEnableAggro() and sm.exists( characterTarget.character ) and characterTarget.character:isPlayer()
		if not sm.exists( characterTarget.character ) or currentTick >= characterTarget.lastSeenTick + ForgetCharacterTickTime or disabledPlayerAggro or characterTarget.character:isDowned() then
			self.sv.characterTargets[characterId] = nil
			self.sv.characterTargetsSync[characterId] = nil
			self.sv.needTargetSynch = true
			-- Achievement: Survive the Seekerbot
			if sm.exists( characterTarget.character ) and not characterTarget.character:isDowned() and characterTarget.character:isPlayer() then
				sm.achievement.seti( "38ea25df-e543-4d53-8524-2cd8531a3552", 1, { characterTarget.character:getPlayer():getId() } )
			end
		end
	end

	--Save and synch scannerbot
	self.sv.needScannerbotSave = self.sv.needScannerbotSave or currentTick >= self.sv.saved.lastSaveAndSyncTick + SaveAndSyncInterval
	self:sv_saveAndSync()
end

function ScannerbotManager.sv_saveAndSync( self )
	-- Save and synch if flag has been set
	local currentTick = sm.game.getCurrentTick()
	if self.sv.needScannerbotSave then
		self.sv.saved.lastSaveAndSyncTick = currentTick
		sm.storage.save( STORAGE_CHANNEL_SCANNERBOT_MANAGER, self.sv.saved )
		self.network:setClientData( self.sv.saved.scannerbotData, 1 )
		self.sv.needScannerbotSave = false
	end
	if self.sv.needTargetSynch then
		self.network:setClientData( { characterTargets = self.sv.characterTargetsSync }, 2 )
		self.sv.needTargetSynch = false
	end
end

function ScannerbotManager.sv_selectHuntTargetCell( self )
	self.sv.saved.huntModeTarget = nil

	local trackedMedianLocations = {}
	for trackingIndex, playerLocations in pairs( self.sv.saved.playerLocationData ) do
		trackedMedianLocations[#trackedMedianLocations+1] = sm.util.geometricMedian( playerLocations, playerLocations[#playerLocations], 12 )
	end
	if #trackedMedianLocations > 0 then
		local randomMedianLocation = trackedMedianLocations[math.random( 1, #trackedMedianLocations )]

		local closestCellKey = nil
		local closestDistance2 = math.huge
		for cellKey, roadCell in pairs( self.sv.scannerbotCells.roadCells ) do
			local toLocation = randomMedianLocation - roadCell.groundPosition
			toLocation.z = 0
			local distanceToLocation2 = toLocation:length2()
			if distanceToLocation2 <= closestDistance2 then
				closestCellKey = cellKey
				closestDistance2 = distanceToLocation2
			end
		end
		if closestCellKey then
		local targetCell = self.sv.scannerbotCells.roadCells[closestCellKey]
			if targetCell then
				self.sv.saved.huntModeTarget = { cellKey = closestCellKey, locationOfInterest = targetCell.groundPosition }
			end
		end
	end
end

function ScannerbotManager.sv_updateRoadDestination( self )
	local currentTick = sm.game.getCurrentTick()
	if self.sv.scannerbotPosition and ScannerbotManager.Sv_GetBehaviour() == ScannerbotBehaviour.ROAD then

		-- Prepare to check neighbour cells
		local cellX = math.floor( self.sv.scannerbotPosition.x / 64 )
		local cellY = math.floor( self.sv.scannerbotPosition.y / 64 )
		local currentCellKey = CellKey( cellX, cellY )
		local cellNeighbourPositions = {
			{ cellX = cellX, cellY = cellY + 1 },
			{ cellX = cellX - 1, cellY = cellY },
			{ cellX = cellX + 1, cellY = cellY },
			{ cellX = cellX, cellY = cellY - 1 }
		}

		if self.sv.saved.huntMode and self.sv.saved.huntModeTarget then
			if self.sv.saved.huntModeTarget.cellKey == currentCellKey then
				-- Arrived at hunted location, return to searching for players
				self.sv.saved.huntModeTarget = nil
			end
		end

		-- Determine the current target
		local targetLocation = nil
		if self.sv.saved.huntMode and self.sv.saved.huntModeTarget then
			targetLocation = self.sv.saved.huntModeTarget.locationOfInterest
		else
			-- Get the closest player
			local closestPlayerLocation = nil
			local closestPlayerLocationDistance2 = math.huge
			for _, player in ipairs( sm.player.getAllPlayers() ) do
				if InSameWorld( player, WorldManager.Sv_GetWorld( "overworld" ) ) then
					local playerCharacter = sm.exists( player.character ) and player.character or nil
					local playerPosition = ( playerCharacter and sm.exists( playerCharacter ) ) and playerCharacter.worldPosition or nil
					if playerPosition then
						local toPlayer = playerPosition - self.sv.scannerbotPosition
						toPlayer.z = 0
						local playerDistance2 = toPlayer:length2()
						if playerDistance2 <= closestPlayerLocationDistance2 then
							closestPlayerLocation = { player = player, playerPosition = playerPosition }
							closestPlayerLocationDistance2 = playerDistance2
						end
					end
				end
			end
			if closestPlayerLocation then
				targetLocation = closestPlayerLocation.playerPosition
			end
		end

		local roadNeighboursByRandom = {}
		local roadNeighboursByDistance = {}
		local previousRoad = nil
		for _, cellNeighbourPosition in ipairs( cellNeighbourPositions ) do
			-- Check if neighbour is a road
			local neighbourCellKey = CellKey( cellNeighbourPosition.cellX, cellNeighbourPosition.cellY )
			local roadCell = self.sv.scannerbotCells.roadCells[neighbourCellKey]
			if roadCell then
				-- Prioritize finding new paths, but select the previous road if arriving at a dead end
				if self.sv.previousRoadCellKey and neighbourCellKey == self.sv.previousRoadCellKey then
					previousRoad = { roadCell = roadCell, cellKey = neighbourCellKey }
				else
					if targetLocation then
						-- Check the road's distance to the scannerbot's target
						local targetToCell = roadCell.groundPosition - targetLocation
						targetToCell.z = 0
						local targetToCellDistance2 = targetToCell:length2()
						roadNeighboursByDistance[#roadNeighboursByDistance+1] = { roadCell = roadCell, targetToCellDistance2 = targetToCellDistance2, cellKey = neighbourCellKey }
					end
					roadNeighboursByRandom[#roadNeighboursByRandom+1] = { roadCell = roadCell }
				end
			end
		end

		local selectedCell
		if #roadNeighboursByDistance > 0 then
			-- Select closest road while hunting, and furthest road while roaming
			if self.sv.saved.huntMode then
				-- Sort closest first (distance to target)
				table.sort( roadNeighboursByDistance, function( a, b ) return a.targetToCellDistance2 < b.targetToCellDistance2 end )
			else
				-- Sort furthest first (distance to target)
				table.sort( roadNeighboursByDistance, function( a, b ) return a.targetToCellDistance2 > b.targetToCellDistance2 end )
			end

			-- Prioritize unvisited roads
			local lowestTimesVisited = MaxRoadVisits
			for _, roadNeighbour in ipairs( roadNeighboursByDistance ) do
				local timesVisited = self.sv.saved.visitedRoads[roadNeighbour.cellKey] and self.sv.saved.visitedRoads[roadNeighbour.cellKey] or 0
				if timesVisited == 0 then
					-- Not visited, select
					lowestTimesVisited = 0
					selectedCell = roadNeighbour
					break
				elseif timesVisited < lowestTimesVisited then
					-- Lowest visited so far, select for now
					lowestTimesVisited = timesVisited
					selectedCell = roadNeighbour
				end
			end
		end

		if selectedCell == nil then
			-- Neighbouring roads have been visited too often or don't exist, try turning back
			if previousRoad then
				local timesVisited = self.sv.saved.visitedRoads[previousRoad.cellKey] and self.sv.saved.visitedRoads[previousRoad.cellKey] or 1
				if timesVisited < MaxRoadVisits then
					selectedCell = previousRoad
				end
			end
		end

		if selectedCell == nil then
			-- No road fulfills the desired parameters, select a random road if relocate is on cooldown
			if currentTick < self.sv.saved.lastRelocateTick + MaxRoadVisitRelocateTickTime then
				selectedCell = roadNeighboursByRandom[math.random( 1, #roadNeighboursByRandom )]
			end
		end

		if selectedCell then
			-- Remember current cell
			self.sv.previousRoadCellKey = currentCellKey

			-- Set new road destination
			local desiredPosition = selectedCell.roadCell.groundPosition + ScannerbotGroundOffsetRoad
			self.sv.saved.scannerbotData = {
				scannerbotCharacter = self.sv.saved.scannerbotData.scannerbotCharacter,
				currentPosition = self.sv.scannerbotPosition,
				currentDirection = self.sv.scannerbotDirection,
				desiredPosition = desiredPosition,
				serverTick = currentTick,
				behaviour = ScannerbotBehaviour.ROAD
			}
			self.sv.needScannerbotSave = true
		else
			-- Failed to select next road piece, relocate
			self.sv.requestRelocateTick = currentTick
		end
	end
end

function ScannerbotManager.sv_shouldSpawn( self )
	local hasSeenIntro = self.sv.saved.firstContactTick ~= nil
	local hasProgressed = ProgressionManager.Sv_ConditionsFulfilled( { completedQuest = "quest_clear_minidungeon" } )
	local playerInOverworld = false
	for _, player in ipairs( sm.player.getAllPlayers() ) do
		if InSameWorld( player, WorldManager.Sv_GetWorld( "overworld" ) ) then
			playerInOverworld = true
			break
		end
	end

	return self.sv.isNightTime and hasSeenIntro and hasProgressed and playerInOverworld
end

function ScannerbotManager.sv_shouldHunt( self, currentTick )
	local isQuestPassive = false
	for _, questName in pairs( PassiveQuestNames ) do
		if QuestManager.Sv_IsQuestActive( questName ) then
			isQuestPassive = true
			break
		end
	end
	local isHuntCooldownOver = currentTick >= self.sv.saved.lastHuntTick + HuntCooldownTickTime
	local isInitialAggressionHunt = self.sv.saved.huntsPerformed < AmountOfInitialAggressiveHunts

	return self.sv.isNightTime and not isQuestPassive and ( self.sv.saved.huntMode or isHuntCooldownOver or isInitialAggressionHunt )
end

--[[ Manager ]]
function ScannerbotManager.Sv_InitScannerbot()
	if g_scannerbotManager then
		g_scannerbotManager:sv_initScannerbot()
	end
end

function ScannerbotManager.sv_initScannerbot( self )
	local currentTick = sm.game.getCurrentTick()

	-- Get valid player locations
	local players = sm.player.getAllPlayers()
	local playerLocations = {}
	for _, player in ipairs( players ) do
		local playerCharacter = sm.exists( player.character ) and player.character or nil
		local playerPosition = ( playerCharacter and sm.exists( playerCharacter ) ) and playerCharacter.worldPosition or nil
		if playerPosition then
			playerLocations[#playerLocations+1] = { player = player, playerPosition = playerPosition }
		end
	end

	-- Reject cells that could cause the scannerbot to spawn on top of the player
	local minAllowedDistance = 128 -- 2 cells

	local cellsByDistance = {}
	-- Find the closest distance to road cells
	for _, roadCell in pairs( self.sv.scannerbotCells.roadCells ) do
		local closestPlayerLocation = nil
		local closestPlayerLocationDistance2 = math.huge
		for _, playerLocation in ipairs( playerLocations ) do
			local toCell = playerLocation.playerPosition - roadCell.groundPosition
			toCell.z = 0
			local distance2 = toCell:length2()
			if distance2 < closestPlayerLocationDistance2 then
				closestPlayerLocation = playerLocation
				closestPlayerLocationDistance2 = distance2
			end
		end
		if closestPlayerLocation and closestPlayerLocationDistance2 >= minAllowedDistance * minAllowedDistance then
			cellsByDistance[#cellsByDistance+1] = { roadCell = roadCell, closestPlayerLocationDistance2 = closestPlayerLocationDistance2 }
		end
	end

	-- Sort closest first
	table.sort( cellsByDistance, function( a, b ) return a.closestPlayerLocationDistance2 < b.closestPlayerLocationDistance2 end )
	-- Select furthest
	local selectedCell = cellsByDistance[#cellsByDistance]
	if selectedCell then
		self.sv.scannerbotPosition = selectedCell.roadCell.groundPosition + ScannerbotGroundOffsetRoad
		self.sv.scannerbotDirection = sm.vec3.new( 0, 1, 0 ):rotateZ( math.rad( math.random() * 360 ) )
		self.sv.saved.firstContactTick = self.sv.saved.firstContactTick or currentTick
		self.sv.saved.scannerbotData = {
			scannerbotCharacter = nil,
			currentPosition = self.sv.scannerbotPosition,
			currentDirection = self.sv.scannerbotDirection,
			desiredPosition = self.sv.scannerbotPosition,
			serverTick = currentTick,
			behaviour = ScannerbotBehaviour.ROAD
		}
		self.sv.needScannerbotSave = true
	end
end

function ScannerbotManager.Sv_GetPosition()
	if g_scannerbotManager then
		return g_scannerbotManager:sv_getPosition()
	end
	return nil
end

function ScannerbotManager.sv_getPosition( self )
	local scannerbotCharacter = ( self.sv.scannerbotUnit and sm.exists( self.sv.scannerbotUnit.character ) ) and self.sv.scannerbotUnit.character or nil
	if scannerbotCharacter then
		return scannerbotCharacter.worldPosition
	elseif self.sv.scannerbotPosition then
		return self.sv.scannerbotPosition
	elseif self.sv.saved and self.sv.saved.scannerbotData then
		return self.sv.saved.scannerbotData.currentPosition
	end
	return nil
end

function ScannerbotManager.Sv_ChangeLocation()
	if g_scannerbotManager then
		g_scannerbotManager:sv_changeLocation()
	end
end

function ScannerbotManager.sv_changeLocation( self )
	local currentTick = sm.game.getCurrentTick()
	local selectedCell
	local targetPosition

	-- Look for a targeted position
	if self.sv.saved.huntMode then
		targetPosition = self:sv_getHuntedPosition()
	end

	if targetPosition then
		-- Hunt
		local desiredCells, farCells, nearCells, undesiredCells = self:sv_getDestinationCells( targetPosition, HuntDesiredMinDistance, HuntDesiredMaxDistance )
		if #desiredCells > 0 then
			-- Sort closest first (distance to target)
			table.sort( desiredCells, function( a, b ) return a.targetToCellDistance2 < b.targetToCellDistance2 end )
			-- Select one of the 10 closest cells to the target
			local maxIndex = math.min( 10, #desiredCells )
			local randomCellIndex = math.random( 1, maxIndex )
			selectedCell = desiredCells[randomCellIndex]
		elseif #farCells > 0 then
			-- Sort closest first (distance to target)
			table.sort( farCells, function( a, b ) return a.targetToCellDistance2 < b.targetToCellDistance2 end )
			-- Select closest
			selectedCell = farCells[1]
		elseif #nearCells > 0 then
			-- Sort closest first (distance to target)
			table.sort( nearCells, function( a, b ) return a.targetToCellDistance2 < b.targetToCellDistance2 end )
			-- Select furthest
			selectedCell = nearCells[#nearCells]
		elseif #undesiredCells > 0 then
			-- Sort closest first (distance to scannerbot)
			table.sort( undesiredCells, function( a, b ) return a.scannerbotToCellDistance2 < b.scannerbotToCellDistance2 end )
			-- Select closest
			selectedCell = undesiredCells[1]
		end
	else
		-- Roam
		-- No target to chase
		-- Relocate far away from current position to find new areas
		local fleeFromPosition = self.sv.scannerbotPosition or sm.vec3.zero()
		local desiredCells, farCells, nearCells, undesiredCells = self:sv_getDestinationCells( fleeFromPosition, RoamDesiredMinDistance, RoamDesiredMaxDistance )
		if #desiredCells > 0 then
			-- Sort closest first (distance to scannerbot)
			table.sort( desiredCells, function( a, b ) return a.scannerbotToCellDistance2 < b.scannerbotToCellDistance2 end )
			-- Select one of the 10 closest cells to the scannerbot
			local maxIndex = math.min( 10, #desiredCells )
			local randomCellIndex = math.random( 1, maxIndex )
			selectedCell = desiredCells[randomCellIndex]
		elseif #farCells > 0 then
			-- Sort closest first (distance to target)
			table.sort( farCells, function( a, b ) return a.targetToCellDistance2 < b.targetToCellDistance2 end )
			-- Select closest
			selectedCell = farCells[1]
		elseif #nearCells > 0 then
			-- Sort closest first (distance to target)
			table.sort( nearCells, function( a, b ) return a.targetToCellDistance2 < b.targetToCellDistance2 end )
			-- Select furthest
			selectedCell = nearCells[#nearCells]
		elseif #undesiredCells > 0 then
			-- Sort closest first (distance to scannerbot)
			table.sort( undesiredCells, function( a, b ) return a.scannerbotToCellDistance2 < b.scannerbotToCellDistance2 end )
			-- Select closest
			selectedCell = undesiredCells[1]
		end
	end

	if selectedCell == nil then
		-- No road cell data was found at all
		sm.log.warning( "Scannerbot tried to relocate, but no road tiles were found.")
		return
	end

	-- Forget any previously scanned road
	self.sv.previousRoadCellKey = nil

	-- Update scannerbot
	local desiredPosition = self.sv.scannerbotPosition
	if selectedCell then
		desiredPosition = selectedCell.roadCell.groundPosition + ScannerbotGroundOffsetRoad
	end

	self.sv.saved.scannerbotData = {
		scannerbotCharacter = nil,
		currentPosition = self.sv.scannerbotPosition,
		currentDirection = self.sv.scannerbotDirection,
		desiredPosition = desiredPosition,
		serverTick = currentTick,
		behaviour = ScannerbotBehaviour.RELOCATE_ASCEND
	}
	self.sv.needScannerbotSave = true
end

function ScannerbotManager.sv_getHuntedPosition( self )
	local targetPosition
	if self.sv.saved.huntModeTarget then
		-- Get hunted position
		targetPosition = self.sv.saved.huntModeTarget.locationOfInterest
	else
		-- Get the closest player
		local closestPlayerLocation = nil
		local closestPlayerLocationDistance2 = math.huge
		for _, player in ipairs( sm.player.getAllPlayers() ) do
			if InSameWorld( player, WorldManager.Sv_GetWorld( "overworld" ) ) then
				local playerCharacter = sm.exists( player.character ) and player.character or nil
				local playerPosition = ( playerCharacter and sm.exists( playerCharacter ) ) and playerCharacter.worldPosition or nil
				if playerPosition then
					local toPlayer = playerPosition - self.sv.scannerbotPosition
					toPlayer.z = 0
					local playerDistance2 = toPlayer:length2()
					if playerDistance2 <= closestPlayerLocationDistance2 then
						closestPlayerLocation = { player = player, playerPosition = playerPosition }
						closestPlayerLocationDistance2 = playerDistance2
					end
				end
			end
		end
		if closestPlayerLocation then
			targetPosition = closestPlayerLocation.playerPosition
		end
	end
	return targetPosition
end

function ScannerbotManager.sv_getDestinationCells( self, targetPosition, desiredMinDistance, desiredMaxDistance )
	local desiredMinDistance2 = desiredMinDistance and desiredMinDistance * desiredMinDistance or 0
	local desiredMaxDistance2 = desiredMaxDistance and desiredMaxDistance * desiredMaxDistance or 4096 * 4096
	local desiredCells = {}
	local farCells = {}
	local nearCells = {}
	local undesiredCells = {}

	if self.sv.scannerbotPosition then
		if targetPosition then
			-- Reject road cells that would cause the scannerbot to arrive with the scanner on top of the player
			local minAllowedRoadDistance = 128 -- 2 cells

			local currentCellX = math.floor( self.sv.scannerbotPosition.x / 64 )
			local currentCellY = math.floor( self.sv.scannerbotPosition.y / 64 )
			local currentCellKey = CellKey( currentCellX, currentCellY )
			-- Find the distances to road cells
			for cellKey, roadCell in pairs( self.sv.scannerbotCells.roadCells ) do
				-- Reject the current cell
				if cellKey ~= currentCellKey then
					local timesVisited = self.sv.saved.visitedRoads[cellKey] and self.sv.saved.visitedRoads[cellKey] or 0
					local targetToCell = roadCell.groundPosition - targetPosition
					targetToCell.z = 0
					local targetToCellDistance2 = targetToCell:length2()
					local scannerbotToCell = roadCell.groundPosition - self.sv.scannerbotPosition
					scannerbotToCell.z = 0
					local scannerbotToCellDistance2 = scannerbotToCell:length2()

					local cellByDistance = { roadCell = roadCell, targetToCellDistance2 = targetToCellDistance2, scannerbotToCellDistance2 = scannerbotToCellDistance2 }
					if targetToCellDistance2 >= minAllowedRoadDistance * minAllowedRoadDistance and timesVisited < MaxRoadVisits then
						if targetToCellDistance2 >= desiredMinDistance2 and targetToCellDistance2 <= desiredMaxDistance2 then
							-- Within desired range
							desiredCells[#desiredCells+1] = cellByDistance
						elseif targetToCellDistance2 > desiredMaxDistance2 then
							-- Far away cells
							farCells[#farCells+1] = cellByDistance
						else
							-- Too near cells
							nearCells[#nearCells+1] = cellByDistance
						end
					else
						undesiredCells[#undesiredCells+1] = cellByDistance
					end
				end
			end
		end
	end
	return desiredCells, farCells, nearCells, undesiredCells
end

function ScannerbotManager.Sv_GetDesiredPostion()
	if g_scannerbotManager then
		return g_scannerbotManager:sv_getDesiredPostion()
	end
	return nil
end

function ScannerbotManager.sv_getDesiredPostion( self )
	if self.sv.saved.scannerbotData then
		return self.sv.saved.scannerbotData.desiredPosition
	elseif self.sv.scannerbotUnit then
		return self.sv.scannerbotUnit.character.worldPosition
	end
	return nil
end

function ScannerbotManager.Sv_GetHeightAboveGround()
	if g_scannerbotManager then
		return g_scannerbotManager:sv_getHeightAboveGround()
	end
	return nil
end

function ScannerbotManager.sv_getHeightAboveGround( self )
	return self.sv.heightAboveGroundLevel
end

function ScannerbotManager.Sv_GetBehaviour()
	if g_scannerbotManager then
		return g_scannerbotManager:sv_getBehaviour()
	end
	return ScannerbotBehaviour.UNKNOWN
end

function ScannerbotManager.sv_getBehaviour( self )
	if self.sv.saved.scannerbotData then
		return self.sv.saved.scannerbotData.behaviour
	end
	return ScannerbotBehaviour.UNKNOWN
end

function ScannerbotManager.Sv_AddTargets( characterTargets )
	if g_scannerbotManager then
		g_scannerbotManager:sv_addTargets( characterTargets )
	end
end

function ScannerbotManager.sv_addTargets( self, characterTargets )
	local currentTick = sm.game.getCurrentTick()
	for characterId, character in pairs( characterTargets ) do
		if sm.game.getEnableAggro() or not character:isPlayer() then -- Ignore players when aggro is off
			if self.sv.characterTargets[characterId] == nil then
				-- Synch new targets
				self.sv.needTargetSynch = true
			end
			self.sv.characterTargetsSync[characterId] = { character = character }
			self.sv.characterTargets[characterId] = { character = character, lastSeenTick = currentTick }
		end
	end
end

function ScannerbotManager.Sv_GetTargets()
	if g_scannerbotManager then
		return g_scannerbotManager:sv_getTargets()
	end
	return {}
end

function ScannerbotManager.sv_getTargets( self )
	return self.sv.characterTargets
end






































function ScannerbotManager.Sv_OnWorldCellLoaded( x, y )
	if g_scannerbotManager then
		g_scannerbotManager:sv_onWorldCellLoaded( x, y )
	end
end

function ScannerbotManager.sv_onWorldCellLoaded( self, x, y )
	-- Only overworld
	local cellKey = CellKey( x, y )
	self.sv.loadedCells[cellKey] = true

	local scannerbotNodes = sm.cell.getNodesByTag( x, y, "SCANNERBOT" )
	self.sv.scannerbotCellNodes[cellKey] = scannerbotNodes
	for _, node in ipairs( scannerbotNodes ) do
		if node.params and node.params.name then
			self.sv.namedScannerbotNodes[node.params.name] = node
		end
	end
end

function ScannerbotManager.Sv_OnWorldCellUnloaded( x, y )
	if g_scannerbotManager then
		g_scannerbotManager:sv_onWorldCellUnloaded( x, y )
	end
end

function ScannerbotManager.sv_onWorldCellUnloaded( self, x, y )
	-- Only overworld
	local cellKey = CellKey( x, y )
	self.sv.loadedCells[cellKey] = nil

	local scannerbotNodes = self.sv.scannerbotCellNodes[cellKey]
	if scannerbotNodes then
		for _, node in ipairs( scannerbotNodes ) do
			if node.params and node.params.name then
				self.sv.namedScannerbotNodes[node.params.name] = nil
			end
		end
	end
	self.sv.scannerbotCellNodes[cellKey] = nil
end

--[[ Client ]]
function ScannerbotManager.client_onCreate( self )
	g_scannerbotManagerClient = self
	self.cl = {}
	self.cl.characterTargets = {}
	self.cl.characterTargetByMissile = {}
	self.cl.scannerbotData = nil

	self.cl.seekerbotIconGui = nil
	self.cl.seekerbotIconAlpha = 0.0

	self.cl.characterTargetEffects = {}
end

function ScannerbotManager.cl_updateTargets( self, deltaTime )
	local selfPlayer = sm.localPlayer.getPlayer()
	local selfCharacterId = sm.exists( selfPlayer.character ) and selfPlayer.character.id or -1
	local selfTargetted = false

	local updatedCharacterEffects = {}
	-- Update characters detected by sight
	for characterId, characterTarget in pairs( self.cl.characterTargets ) do
		local isSelfCharacter = selfCharacterId == characterId
		selfTargetted = selfTargetted or isSelfCharacter

		local previousCharacterTargetEffect = self.cl.characterTargetEffects[characterId]
		if previousCharacterTargetEffect then
			updatedCharacterEffects[characterId] = previousCharacterTargetEffect
			self.cl.characterTargetEffects[characterId] = nil
		elseif sm.exists( characterTarget.character ) then
			if ( not isSelfCharacter and ShowTargetOnOthers ) or ( isSelfCharacter and ShowTargetOnSelf ) then
				updatedCharacterEffects[characterId] = {}
				updatedCharacterEffects[characterId].character = characterTarget.character
				updatedCharacterEffects[characterId].effect = sm.effect.createEffect( "Scannerbot - Lockontarget", characterTarget.character )
				updatedCharacterEffects[characterId].effect:start()
			end
		end
	end
	-- Update characters detected by missiles
	for characterId, characterTarget in pairs( self.cl.characterTargetByMissile ) do
		local isSelfCharacter = selfCharacterId == characterId
		selfTargetted = selfTargetted or isSelfCharacter

		local previousCharacterTargetEffect = self.cl.characterTargetEffects[characterId]
		if previousCharacterTargetEffect then
			updatedCharacterEffects[characterId] = previousCharacterTargetEffect
			self.cl.characterTargetEffects[characterId] = nil
		elseif sm.exists( characterTarget.character ) then
			if ( not isSelfCharacter and ShowTargetOnOthers ) or ( isSelfCharacter and ShowTargetOnSelf ) then
				updatedCharacterEffects[characterId] = {}
				updatedCharacterEffects[characterId].character = characterTarget.character
				updatedCharacterEffects[characterId].effect = sm.effect.createEffect( "Scannerbot - Lockontarget", characterTarget.character )
				updatedCharacterEffects[characterId].effect:start()
			end
		end
	end

	-- Remove effects from non targetted characters
	for _, characterTarget in pairs( self.cl.characterTargetEffects ) do
		if sm.exists( characterTarget.effect ) then
			characterTarget.effect:destroy()
		end
	end
	self.cl.characterTargetEffects = updatedCharacterEffects

	-- Targetted icon
	if selfTargetted then
		self.cl.seekerbotIconAlpha = math.min( self.cl.seekerbotIconAlpha + ( deltaTime / GuiFadeInDuration ), 1.0 )
	else
		self.cl.seekerbotIconAlpha = math.max( self.cl.seekerbotIconAlpha - ( deltaTime / GuiFadeOutDuration ), 0.0 )
	end

	if self.cl.seekerbotIconGui then
		if self.cl.seekerbotIconAlpha <= 0.0 then
			self.cl.seekerbotIconGui:close()
			self.cl.seekerbotIconGui = nil
		else
			SeekerbotIconParentPanel.Alpha = self.cl.seekerbotIconAlpha
			self.cl.seekerbotIconGui:render( SeekerbotIconGuiData )
		end
	else
		if self.cl.seekerbotIconAlpha > 0.0 then
			self.cl.seekerbotIconGui = sm.jsonGui.createGui( { isHud = true, needsCursor = false, isInteractive = false } )
			SeekerbotIconParentPanel.Alpha = self.cl.seekerbotIconAlpha
			self.cl.seekerbotIconGui:render( SeekerbotIconGuiData )
		end
	end
end

function ScannerbotManager.client_onUpdate( self, dt )







































	-- Intro
	local introScannerbot = self.cl.introScannerbot
	if introScannerbot then
		if not introScannerbot.effect:isPlaying() then
			introScannerbot.effect:start()
		end

		if introScannerbot.startingTick + IntroTickTime <= sm.game.getServerTick() then
			if sm.exists( introScannerbot.effect ) then
				introScannerbot.effect:destroy()
			end
			self.cl.introScannerbot = nil
		end
	end

	self:cl_updateTargets( dt )

	-- Check ascend / descend effect state for host
	if sm.isHost then
		self.playingDescendingEffect = nil
		self.playingAscendingEffect = nil
		if self.cl.scannerbotData then
			local scannerbotCharacter = sm.exists( self.cl.scannerbotData.scannerbotCharacter ) and self.cl.scannerbotData.scannerbotCharacter or nil
			if scannerbotCharacter then
				self.playingDescendingEffect = scannerbotCharacter.clientPublicData and scannerbotCharacter.clientPublicData.playingDescendingEffect or nil
				self.playingAscendingEffect = scannerbotCharacter.clientPublicData and scannerbotCharacter.clientPublicData.playingAscendingEffect or nil
			end
		end
	end
end

function ScannerbotManager.Cl_spawnScannerbotEffect( params )
	g_scannerbotManagerClient:cl_n_showIntroScannerbot( params )
end

function ScannerbotManager.cl_n_showIntroScannerbot( self, params )
	local scannerbotIntroEffect = sm.effect.createEffect( "Scannerbot - Character_start" )
	scannerbotIntroEffect:setPosition( params.startingPosition )
	scannerbotIntroEffect:setRotation( params.startingRotation )
	scannerbotIntroEffect:setWorld( WorldManager.Cl_GetWorld( "overworld" ) )
	scannerbotIntroEffect:start()

	self.cl.introScannerbot = {
		effect = scannerbotIntroEffect,
		startingTick = params.startingTick
	}
end

function ScannerbotManager.client_onClientDataUpdate( self, data, channel )
	if channel == 1 then
		self.cl.scannerbotData = data
	elseif channel == 2 then
		self.cl.characterTargets = data.characterTargets
	end
end

--[[ Manager ]]
function ScannerbotManager.Cl_GetBehaviour()
	if g_scannerbotManagerClient then
		return g_scannerbotManagerClient:cl_getBehaviour()
	end
	return ScannerbotBehaviour.UNKNOWN
end

function ScannerbotManager.cl_getBehaviour( self )
	if self.cl.scannerbotData then -- Scannerbot exists in the overworld
		return self.cl.scannerbotData.behaviour
	end
	return ScannerbotBehaviour.UNKNOWN
end

function ScannerbotManager.Cl_AddMissileTarget( missile, targetCharacter )
	if g_scannerbotManagerClient then
		g_scannerbotManagerClient:cl_addMissileTarget( missile, targetCharacter )
	end
end

function ScannerbotManager.cl_addMissileTarget( self, missile, targetCharacter )
	self.cl.characterTargetByMissile[targetCharacter.id] = self.cl.characterTargetByMissile[targetCharacter.id] or {}
	self.cl.characterTargetByMissile[targetCharacter.id][missile.id] = missile
end

function ScannerbotManager.Cl_RemoveMissileTarget( missile, targetCharacter )
	if g_scannerbotManagerClient then
		g_scannerbotManagerClient:cl_removeMissileTarget( missile, targetCharacter )
	end
end

function ScannerbotManager.cl_removeMissileTarget( self, missile, targetCharacter )
	self.cl.characterTargetByMissile[targetCharacter.id] = self.cl.characterTargetByMissile[targetCharacter.id] or {}
	self.cl.characterTargetByMissile[targetCharacter.id][missile.id] = nil
	if IsEmptyTable( self.cl.characterTargetByMissile[targetCharacter.id] ) then
		self.cl.characterTargetByMissile[targetCharacter.id] = nil
	end
end

function ScannerbotManager.Cl_IsTargettedByMissiles( targetCharacter )
	if g_scannerbotManagerClient then
		return g_scannerbotManagerClient:cl_isTargettedByMissiles( targetCharacter )
	end
	return false
end

function ScannerbotManager.cl_isTargettedByMissiles( self, targetCharacter )
	if self.cl.characterTargetByMissile[targetCharacter.id] then
		return not IsEmptyTable( self.cl.characterTargetByMissile[targetCharacter.id] )
	end
	return false
end