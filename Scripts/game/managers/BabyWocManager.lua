dofile( "$SURVIVAL_DATA/Scripts/game/survival_constants.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/managers/DialogManager.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/managers/ProgressionManager.lua" )

BabyWocManager = class( nil )

local FollowerCheckTickInterval = 200
local UnitRequestCooldownTicks = 40 -- Max amount of ticks to wait for a babywoc to spawn after being called, before activating auto-spawning
local SpawnDistance = 12 -- Distance from the player to spawn the babywoc

local BabyWocFirstBondBuilder = "babywoc_summon1" -- Named bond builder played the first time the babywoc is summoned after visiting Drill1
local BabyWocSecondBondBuilder = "babywoc_summon2" -- Follow-up bond builder, played on a later summon
local BabyWocSecondBondBuilderDelayTicks = 40 * 60 * 120 -- Minimum game time after the first before the second can play

local function GetSpawnPosition( characterToSpawnAt )
	local playerPosition = characterToSpawnAt.worldPosition
	local playerWorld = characterToSpawnAt:getWorld()

	local worldUp = sm.vec3.new( 0, 0, 1 )
	local verticalCheckOffsetUp = 2
	local verticalCheckOffsetDown = 10
	local amountOfCasts = 5
	local castRadius = 0.25
	local offsetRadius = 0.75
	local offsetStartingDirection = sm.vec3.new( 0, 1, 0 )

	local allowedGroundTypes = { "terrainSurface",
								"terrainAsset",
								"body",
								"voxelTerrain",
								"lift" }

	-- Get player's facing direction and spawn behind them
	local behindDirection = sm.vec3.new( -characterToSpawnAt.direction.x, -characterToSpawnAt.direction.y, 0 ):safeNormalize( sm.vec3.new( 0, 1, 0 ) )

	-- Move behind the player and follow slopes/obstacles by projecting direction on hit normals
	local traversedDistance = 0
	local currentPosition = playerPosition
	local currentDirection = behindDirection
	for i = 1, amountOfCasts do
		local remainingDistance = SpawnDistance - traversedDistance
		if remainingDistance <= 0 then
			break
		end

		local castStart = currentPosition + worldUp * 0.5
		local castEnd = castStart + currentDirection * remainingDistance
		local hit, result = sm.physics.spherecast(
			castStart,
			castEnd,
			castRadius,
			characterToSpawnAt,
			nil,
			playerWorld
		)

		if not hit then
			currentPosition = currentPosition + currentDirection * remainingDistance
			traversedDistance = SpawnDistance
			break
		end

		-- Move to the hit position and project the direction on the hit normal to follow slopes/obstacles
		local hitPoint = result.pointWorld
		local hitNormal = ( result.normalWorld and result.normalWorld:length2() > 0 ) and result.normalWorld:safeNormalize( worldUp ) or worldUp
		local steppedDistance = ( hitPoint - currentPosition ):length()
		traversedDistance = traversedDistance + steppedDistance
		currentPosition = hitPoint + hitNormal * castRadius

		-- Project the direction on the hit normal to follow slopes/obstacles
		local projectedDirection = currentDirection - hitNormal * currentDirection:dot( hitNormal )
		if projectedDirection:length2() < 0.0001 then -- Too steep, can't project a direction
			break
		end
		currentDirection = projectedDirection:safeNormalize( currentDirection )
	end

	-- Validate the position against the ground
	local success, result = sm.physics.spherecast(
		currentPosition + worldUp * verticalCheckOffsetUp,
		currentPosition - worldUp * verticalCheckOffsetDown,
		castRadius,
		characterToSpawnAt,
		nil,
		playerWorld
	)
	if success and isAnyOf( result.type, allowedGroundTypes ) then
		if playerWorld:isVoxelTerrainPointClear( playerPosition, result.pointWorld ) then
			return result.pointWorld
		end
	end

	-- Fallback: Try random positions around the player
	verticalCheckOffsetDown = 100
	local casts = {}
	for i = 1, amountOfCasts do
		local degrees = ( 360 / amountOfCasts ) * ( i - 1 )
		local offsetDirection = offsetStartingDirection:rotate( math.rad( degrees ), worldUp )
		local offsetPosition = playerPosition + offsetDirection * offsetRadius
		casts[#casts+1] = { type = "sphere",
							startPoint = offsetPosition + worldUp * verticalCheckOffsetUp,
							endPoint = offsetPosition - worldUp * verticalCheckOffsetDown,
							radius = 0.125 }
	end
	local retTable = sm.physics.multicast( casts, playerWorld )
	local groundHits = {}
	for i = 1, amountOfCasts do
		local success = retTable[i][1]
		local result = retTable[i][2]
		if success then
			if isAnyOf( result.type, allowedGroundTypes ) then
				if playerWorld:isVoxelTerrainPointClear( playerPosition, result.pointWorld ) then
					groundHits[#groundHits+1] = result.pointWorld
				end
			end
		end
	end
	if #groundHits > 0 then
		return groundHits[math.random( 1, #groundHits )]
	end

	-- Final fallback to player position
	return playerPosition
end

--[[ Server ]]
function BabyWocManager.server_onCreate( self )
	assert( g_babyWocManager == nil )
	g_babyWocManager = self
	self.sv = {}
	self.sv.saved = sm.storage.load( STORAGE_CHANNEL_BABYWOC_MANAGER )
	if self.sv.saved == nil then
		self.sv.saved = {}
		self.sv.saved.followerData = nil -- table when spawned
		self.sv.saved.baguetteState = false
		self.sv.saved.glowstickState = false
		sm.storage.save( STORAGE_CHANNEL_BABYWOC_MANAGER, self.sv.saved )
	end

	self.sv.lastFollowerCheckTick = sm.game.getCurrentTick()

	self:sv_sync()
end

function BabyWocManager.server_onFixedUpdate( self, dt )
	if not LogEntryManager.Sv_HasLog( LOGS.log_babywoc ) then
		return
	end

	local currentTick = sm.game.getCurrentTick()
	if currentTick >= self.sv.lastFollowerCheckTick + FollowerCheckTickInterval then
		self.sv.lastFollowerCheckTick = currentTick
		if self.sv.saved.followerData then
			if self.sv.saved.followerData.pendingUnitRequestTick then
				if currentTick >= self.sv.saved.followerData.pendingUnitRequestTick + UnitRequestCooldownTicks then
					self.sv.saved.followerData.pendingUnitRequestTick = nil
				end
			end

			local playerToFollow = sm.exists( self.sv.saved.followerData.playerToFollow ) and self.sv.saved.followerData.playerToFollow or nil
			local shouldRespawn = not sm.exists( self.sv.saved.followerData.unit ) and self.sv.saved.followerData.pendingUnitRequestTick == nil
			if playerToFollow == nil then
				-- Owner is gone, remove the babywoc
				if self.sv.saved.followerData.unit then
					sm.unit.forceDestroy( self.sv.saved.followerData.unit )
				end
				self.sv.saved.followerData = nil
				self:sv_save()
			elseif shouldRespawn then
				-- Find a player character to respawn the babywoc at
				local characterToRespawnAt = nil

				-- Find player to follow
				local playerToFollow = self.sv.saved.followerData.playerToFollow or nil
				if sm.exists( playerToFollow ) then
					local characterToFollow = sm.exists( playerToFollow.character ) and playerToFollow.character or nil
					if characterToFollow then
						characterToRespawnAt = characterToFollow
					end
				end

				if characterToRespawnAt then
					-- Respawn the unit
					local spawnParams = {
						uuid = unit_baby_woc,
						position = GetSpawnPosition( characterToRespawnAt ),
						amount = 1,
						customParams = { playerToFollow = playerToFollow, spawnEffect = true }
					}
					sm.event.sendToWorld( characterToRespawnAt:getWorld(), "sv_e_spawnUnit", spawnParams )
					self.sv.saved.followerData.pendingUnitRequestTick = currentTick
					if self.sv.saved.followerData.unit then
						sm.unit.forceDestroy( self.sv.saved.followerData.unit )
					end
				else
					-- Couldn't find the owner to respawn at. Remove for now until a player calls for it
					if self.sv.saved.followerData.unit then
						sm.unit.forceDestroy( self.sv.saved.followerData.unit )
					end
					self.sv.saved.followerData = nil
				end
				self:sv_save()
			end
		end
	end

	if self.sv.needSync then
		self:sv_sync()
		self.sv.needSync = false
	end
end

function BabyWocManager.sv_sync( self )
	local syncData
	if self.sv.saved.followerData then
		syncData = { character = sm.exists( self.sv.saved.followerData.unit ) and self.sv.saved.followerData.unit.character or nil,
					playerToFollow = self.sv.saved.followerData.playerToFollow or nil,
					baguetteContainer = self.sv.saved.followerData.baguetteContainer,
					glowstickContainer = self.sv.saved.followerData.glowstickContainer }
	end

	self.network:setClientData( syncData )
end

function BabyWocManager.sv_save( self )
	sm.storage.save( STORAGE_CHANNEL_BABYWOC_MANAGER, self.sv.saved )
	self.sv.needSync = true
end

function BabyWocManager.Sv_CallFollower( player )
	if g_babyWocManager then
		g_babyWocManager:sv_callFollower( player )
	end
end

-- Plays the babywoc summon bond builders. Requires the player to have reached Drill1. The first
-- plays on summon; the second only on a later summon, once the cooldown after the first has passed.
function BabyWocManager.sv_tryPlayBondBuilder( self, player )
	if not ProgressionManager.Sv_HasReachedUndergroundDepth( 4 ) then
		return
	end
	if not DialogManager.Sv_HasNamedBondBuilderFired( BabyWocFirstBondBuilder ) then
		if DialogManager.Sv_PlayNamedBondBuilder( BabyWocFirstBondBuilder ) then
			-- Record when the first actually played, so the second can be delayed from it.
			self.sv.saved.firstBondBuilderTick = sm.game.getCurrentTick()
			self:sv_save()
		end
	elseif not DialogManager.Sv_HasNamedBondBuilderFired( BabyWocSecondBondBuilder ) then
		if self.sv.saved.firstBondBuilderTick and sm.game.getCurrentTick() - self.sv.saved.firstBondBuilderTick >= BabyWocSecondBondBuilderDelayTicks then
			DialogManager.Sv_PlayNamedBondBuilder( BabyWocSecondBondBuilder )
		end
	end
end

function BabyWocManager.sv_callFollower( self, player )
	if not LogEntryManager.Sv_HasLog( LOGS.log_babywoc ) then
		return
	end

	self:sv_tryPlayBondBuilder( player )

	if self.sv.saved.followerData then
		if self.sv.saved.followerData.playerToFollow == player then
			-- Despawn
			if sm.exists( self.sv.saved.followerData.unit ) then
				local babywocCharacter = self.sv.saved.followerData.unit.character
				if sm.exists( babywocCharacter ) then
					sm.effect.playEffect( "Babywoc - Despawn", babywocCharacter.worldPosition, nil, nil, nil, nil, nil, babywocCharacter:getWorld() )
				end
				self.sv.saved.followerData.unit:destroy()
			elseif self.sv.saved.followerData.unit then
				sm.unit.forceDestroy( self.sv.saved.followerData.unit )
			end
			self.sv.saved.followerData = nil
		else
			-- Change player to follow
			self.sv.saved.followerData.playerToFollow = player
		end
	else
		-- Setup baby woc follower
		local characterToSpawnAt = sm.exists( player.character ) and player.character or nil
		if characterToSpawnAt then
			sm.effect.playEffect( "Babywoc - Whistle", characterToSpawnAt.worldPosition, nil, nil, nil, nil, nil, characterToSpawnAt:getWorld() )
			self.sv.saved.followerData = {}
			self.sv.saved.followerData.playerToFollow = player

			local spawnParams = {
				uuid = unit_baby_woc,
				position = GetSpawnPosition( characterToSpawnAt ),
				amount = 1,
				customParams = { playerToFollow = player, baguetteState = self.sv.saved.baguetteState, glowstickState = self.sv.saved.glowstickState, spawnEffect = true }
			}
			sm.event.sendToWorld( characterToSpawnAt:getWorld(), "sv_e_spawnUnit", spawnParams )
			self.sv.saved.followerData.pendingUnitRequestTick = sm.game.getCurrentTick()
		else
			sm.log.warning( "Player: " .. player .. ", called for the babywoc without a character." )
		end
	end
	self:sv_save()
end

function BabyWocManager.Sv_DespawnFollower()
	if g_babyWocManager then
		g_babyWocManager:sv_despawnFollower()
	end
end

function BabyWocManager.sv_despawnFollower( self )
	if self.sv.saved.followerData then
		if self.sv.saved.followerData.unit then
			sm.unit.forceDestroy( self.sv.saved.followerData.unit )
		end
		self.sv.saved.followerData = nil
	end
	self:sv_save()
end

function BabyWocManager.Sv_RegisterFollower( unit, playerToFollow )
	if g_babyWocManager then
		g_babyWocManager:sv_registerFollower( unit, playerToFollow )
	end
end

function BabyWocManager.sv_registerFollower( self, unit, playerToFollow )
	self.sv.saved.followerData = self.sv.saved.followerData or {}
	if self.sv.saved.followerData.unit and unit ~= self.sv.saved.followerData.unit then
		-- Make sure there's no duplicate
		if self.sv.saved.followerData.unit then
			sm.unit.forceDestroy( self.sv.saved.followerData.unit )
		end
	end

	self.sv.saved.followerData.baguetteContainer = unit:getContainer( BABYWOC_BAGUETTE_CONTAINER_INDEX )
	if self.sv.saved.baguetteState then
		sm.container.beginTransaction()
		self.sv.saved.followerData.baguetteContainer:setItem( 0, ITEMS.obj_consumable_longsandwich, 1 )
		sm.container.endTransaction()
	end

	self.sv.saved.followerData.glowstickContainer = unit:getContainer( BABYWOC_GLOWSTICK_CONTAINER_INDEX )
	if self.sv.saved.glowstickState then
		sm.container.beginTransaction()
		self.sv.saved.followerData.glowstickContainer:setItem( 0, ITEMS.obj_consumable_glowstick, 1 )
		sm.container.endTransaction()
	end

	local character = sm.exists( unit ) and unit.character or nil
	if character then
		sm.event.sendToCharacter( character , "sv_e_updateState", { glowstickState = self.sv.saved.glowstickState, baguetteState = self.sv.saved.baguetteState }, sm.event.types.blind )
	end

	self.sv.saved.followerData.baguetteContainer:bindOnTransaction( "sv_baguetteContainer_onTransaction", g_babyWocManager )
	self.sv.saved.followerData.glowstickContainer:bindOnTransaction( "sv_glowstickContainer_onTransaction", g_babyWocManager )

	self.sv.saved.followerData.unit = unit
	self.sv.saved.followerData.playerToFollow = playerToFollow
	self:sv_save()
end

function BabyWocManager.Sv_GetFollowerData()
	if g_babyWocManager then
		return g_babyWocManager:sv_getFollowerData()
	end
	return nil
end

function BabyWocManager.sv_getFollowerData( self )
	if self.sv.saved.followerData then
		return self.sv.saved.followerData
	end
	return nil
end

function BabyWocManager.Sv_GetPlayerToFollow()
	if g_babyWocManager then
		return g_babyWocManager:sv_getPlayerToFollow()
	end
	return nil
end

function BabyWocManager.sv_getPlayerToFollow( self )
	if self.sv.saved.followerData then
		return self.sv.saved.followerData.playerToFollow
	end
	return nil
end

function BabyWocManager.sv_baguetteContainer_onTransaction( self, container )
	if sm.exists( self.sv.saved.followerData.baguetteContainer ) then
		self.sv.saved.baguetteState = not self.sv.saved.followerData.baguetteContainer:isEmpty()
		self:sv_save()

		local character = sm.exists( self.sv.saved.followerData.unit ) and self.sv.saved.followerData.unit.character or nil
		if character then
			sm.event.sendToCharacter( character , "sv_e_updateState", { glowstickState = self.sv.saved.glowstickState, baguetteState = self.sv.saved.baguetteState }, sm.event.types.blind )
		end
	end
end

function BabyWocManager.sv_glowstickContainer_onTransaction( self, container )
    if sm.exists( self.sv.saved.followerData.glowstickContainer ) then
		self.sv.saved.glowstickState = not self.sv.saved.followerData.glowstickContainer:isEmpty()
		self:sv_save()

		local character = sm.exists( self.sv.saved.followerData.unit ) and self.sv.saved.followerData.unit.character or nil
		if character then
			sm.event.sendToCharacter( character , "sv_e_updateState", { glowstickState = self.sv.saved.glowstickState, baguetteState = self.sv.saved.baguetteState }, sm.event.types.blind )
		end
	end
end

--[[ Client ]]
function BabyWocManager.client_onCreate( self )
	g_babyWocManagerClient = self
	self.cl = {}
	self.cl.followerData = nil -- table when summoned
	self.cl.isActive = false
end

function BabyWocManager.client_onClientDataUpdate( self, data, channel )
	self.cl.followerData = data
	self.cl.isActive = self.cl.followerData ~= nil -- Active when the server has data
end

--[[ Manager ]]
function BabyWocManager.Cl_UpdateActiveStatus()
	if g_babyWocManager then
		g_babyWocManager:cl_updateActiveStatus()
	end
end

function BabyWocManager.cl_updateActiveStatus( self )
	-- Preemptively set state for gui
	if self.cl.followerData then
		self.cl.isActive = false -- Server will dismiss the follower
	else
		self.cl.isActive = true -- Server will call the follower
	end
end

function BabyWocManager.Cl_IsActive()
	if g_babyWocManagerClient then
		return g_babyWocManagerClient:cl_isActive()
	end
	return false
end

function BabyWocManager.cl_isActive( self )
	return self.cl.isActive
end

function BabyWocManager.Cl_GetFollowerData()
	if g_babyWocManagerClient then
		return g_babyWocManagerClient:cl_getFollowerData()
	end
	return nil
end

function BabyWocManager.cl_getFollowerData( self )
	-- { character, playerToFollow, baguetteContainer, glowstickContainer }
	return self.cl.followerData
end
