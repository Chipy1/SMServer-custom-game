dofile( "$GAME_DATA/Scripts/game/managers/TileStorageManager.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/managers/RaidManager.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/managers/PatrolManager.lua" )
dofile( "$SURVIVAL_DATA/Scripts/util.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/survival_projectiles.lua" )

local ShareTargetTime = 3.0
local DefaultAlertRange = 20

local RaidFleeStuckDistanceSqr = 16.0
local RaidFleeStuckTickDuration = 40 * 8 -- if enemies have not moved a certain distance in 8 seconds, they are considered stuck and will swap to idle state

local MaxWocAggroDistance = 20.0

function getClosestCharacter( position, characters )
	local closestDistance2
	local closestCharacter
	for _,character in ipairs( characters ) do
		local distance2 = ( position - character.worldPosition ):length2()
		if closestDistance2 == nil or distance2 < closestDistance2 then
			closestCharacter = character
		end
	end
	return closestCharacter, math.sqrt( closestDistance2 )
end

function ListenForPlayerNoise( listeningCharacter, noiseScale )
	if not sm.game.getEnableAggro() then
		return nil
	end
	local closestCharacter = nil
	local bestFraction = -1
	local allPlayers = sm.player.getAllPlayers()
	for _, player in ipairs( allPlayers ) do
		if player.character and player.character:getWorld() == listeningCharacter:getWorld() then
			local noiseRadius = player.character:getCurrentMovementNoiseRadius() * noiseScale
			if noiseRadius > 0 then
				local noiseFraction = 1.0 - ( player.character.worldPosition - listeningCharacter.worldPosition ):length() / noiseRadius
				if noiseFraction > 0 and ( noiseFraction > bestFraction or bestFraction == -1 ) then
					bestFraction = noiseFraction
					closestCharacter = player.character
				end
			end
		end
	end
	if closestCharacter then
		local success, result = sm.physics.raycast( listeningCharacter.worldPosition, closestCharacter.worldPosition, listeningCharacter )
		if success and result.type == "character" and result:getCharacter() == closestCharacter then
			return closestCharacter
		end
	end
	return nil
end

function initTumble( self )
	self.canTumble = true
	self.tumbleReset = Timer()
	self.tumbleReset:start( DEFAULT_TUMBLE_TICK_TIME )
	self.airTicks = 0
end

function startTumble( self, tumbleTickTime, tumbleState, tumbleVelocity )
	if not self.unit.character:isTumbling() then
		self.unit.character:setTumbling( true )
		if tumbleTickTime then
			self.tumbleReset:start( tumbleTickTime )
		else
			self.tumbleReset:start( DEFAULT_TUMBLE_TICK_TIME )
		end
		if tumbleState then
			self.currentState:stop()
			self.currentState = tumbleState
			self.currentState:start()
		end

		if tumbleVelocity then
			self.unit.character:applyTumblingImpulse( tumbleVelocity * self.unit.character.mass )
		end
		return true
	end
	return false
end

function updateTumble( self )
	if self.unit.character:isTumbling() then
		local tumbleVelocity = self.unit.character:getTumblingLinearVelocity()
		if tumbleVelocity:length() < 1.0 or self.unit.character:isSwimming() then
			self.tumbleReset:tick()

			if self.tumbleReset:done() then
				self.unit.character:setTumbling( false )
				self.tumbleReset:reset()
			end
		else
			self.tumbleReset:reset()
		end
	end
end

function updateAirTumble( self, tumbleState )
	if not self.unit.character:isOnGround() and not self.unit.character:isSwimming() and not self.unit.character:isTumbling() then
		self.airTicks = self.airTicks + 1
		if self.airTicks >= AIR_TICK_TIME_TO_TUMBLE then
			local defaultAllowedPenetrationDepth = 0.04
			local startPos = self.unit.character.worldPosition
			local endPos = startPos - ( sm.vec3.new( 0.0, 0.0, self.unit.character:getHeight() * 0.5 + defaultAllowedPenetrationDepth ) )
			local success, _ = sm.physics.raycast( startPos, endPos, self.unit.character, sm.physics.filter.static + sm.physics.filter.dynamicBody )
			if success then
				self.airTicks = 0
			else
				startTumble( self, DEFAULT_TUMBLE_TICK_TIME, tumbleState, self.unit.character.velocity )
			end
		end
	else
		self.airTicks = 0
	end
end

function initCrushing( self, crushTickTime )
	self.crushTicks = 0
	self.crushTickTime = crushTickTime and crushTickTime or DEFAULT_CRUSH_TICK_TIME
	self.crushUpdate = false
end

function onCrush( self  )
	self.crushUpdate = true
end

function updateCrushing( self )
	if self.crushUpdate then
		self.crushTicks = math.min( self.crushTicks + 1, self.crushTickTime )
		self.crushUpdate = false
	else
		self.crushTicks = math.max( self.crushTicks - 1, 0 )
	end

	if self.crushTicks >= self.crushTickTime then
		return true
	else
		return false
	end
end

function selectRaidTarget( self, targetCharacter, closestVisibleCrop )
	
	local prioritizeCharacterDistance = 5.0
	local deaggroDistance = 34.0
	local aggroDistance = 30.0

	-- Raiders prioritize targeting crops over distant players
	local closeToCharacter = false
	local inAggroDistance = false
	local overDeaggroDistance = true
	if targetCharacter then
		closeToCharacter = ( targetCharacter and ( targetCharacter.worldPosition - self.unit.character.worldPosition ):length() <= prioritizeCharacterDistance )
		inAggroDistance = ( targetCharacter and ( targetCharacter.worldPosition - self.homePosition ):length() <= aggroDistance )
		overDeaggroDistance = ( targetCharacter and ( targetCharacter.worldPosition - self.homePosition ):length() >= deaggroDistance )
	end
	local characterIsWithinAggroRange = inAggroDistance or ( self.target == targetCharacter and not overDeaggroDistance )

	if self.unit.character:getCharacterType() == unit_totebot_red then
		if ( not closeToCharacter ) or not targetCharacter then
			self.target = closestVisibleCrop
		else
			self.target = targetCharacter
		end
		return
	end

	if ( targetCharacter and ( self.raidTargetNonVisiblePlayer or self.isRanged ) ) or ( ( closestVisibleCrop == nil ) and characterIsWithinAggroRange ) or closeToCharacter then
		self.target = targetCharacter
	else
		self.target = closestVisibleCrop
	end
	
end

function FindNearbyEdible( character, edibleUuid, searchRadius, reach )
	local closestShape = nil
	local closestDistance = math.huge
	local nearbyShapes = sm.shape.shapesInSphere( character.worldPosition, searchRadius )
	for _, shape in ipairs( nearbyShapes )do
		if shape:getShapeUuid() == edibleUuid then
			local shapeTargetPosition = shape.worldPosition
			if shape.isBlock then
				local closestLocalPosition = shape:getClosestBlockLocalPosition( character.worldPosition )
				shapeTargetPosition = shape.body:transformPoint( ( closestLocalPosition + sm.vec3.new( 0.5, 0.5, 0.5 ) ) * 0.25 )
			end
			local distanceToShape = ( shapeTargetPosition - character.worldPosition ):length()
			if distanceToShape < closestDistance then
				closestDistance = distanceToShape
				closestShape = shape
			end
		end
	end

	if closestShape and sm.exists( closestShape ) then
		return closestShape, closestDistance <= reach
	end
	return nil, false
end

function GetClosestPlayerCharacter( position, world )
	local closestPlayer = nil
	local closestDd = math.huge
	local players = sm.player.getAllPlayers()
	for _, player in ipairs( players ) do
		local validTarget = player.character and
							world == player.character:getWorld() and
							not player.character:isDowned()
		if validTarget then
			local dd = ( player.character.worldPosition - position ):length2()
			if dd <= closestDd then
				closestPlayer = player
				closestDd = dd
			end
		end
	end
	if closestPlayer then
		return closestPlayer.character
	end
	return nil
end

function GetPlayerCharactersInSphere( position, radius, world )
	local playerCharacters = {}
	local players = sm.player.getAllPlayers()
	for _, player in ipairs( players ) do
		local validTarget = player.character and
							world == player.character:getWorld() and
							not player.character:isDowned()
		if validTarget then
			local dd = ( player.character.worldPosition - position ):length2()
			if dd <= radius * radius then
				playerCharacters[#playerCharacters+1] = player.character
			end
		end
	end
	return playerCharacters
end

local function getCharacter( userdataObject )
	local userdataType = enumType( userdataObject )
	if userdataObject and isAnyOf( userdataType, { LUA_TYPE.character, LUA_TYPE.player, LUA_TYPE.unit } ) then
		if sm.exists( userdataObject ) then
			if userdataType == LUA_TYPE.player or userdataType == LUA_TYPE.unit then
				return userdataObject.character
			elseif userdataType == LUA_TYPE.character then
				return userdataObject
			end
			return nil
		else
			return nil
		end
	end
	sm.log.warning( "Tried to get character for an unsupported type: "..type( userdataObject ) )
	return nil
end

function InSameTeam( userdataObjectA, userdataObjectB )
	local characterA = getCharacter( userdataObjectA )
	local characterB = getCharacter( userdataObjectB )
	if characterA == nil or characterB == nil then
		return false
	end

	if not characterA:isDefaultColor() and not characterB:isDefaultColor() then
		return characterA:getColor() == characterB:getColor()
	elseif not characterA:isPlayer() and not characterB:isPlayer() then
		return characterA:isDefaultColor() and characterB:isDefaultColor()
	end
	return false
end

function InSameGroup( unitA, unitB )
	local groupA = unitA.publicData and unitA.publicData.groupKey or nil
	local groupB = unitB.publicData and unitB.publicData.groupKey or nil
	return groupA and groupB and groupA == groupB
end

--[[
	Writes to:
	self.tileStorageKey
	self.saved.tetherPoint
	self.saved.lootType
	self.saved.deathEvent
	self.saved.raider
	self.saved.raidKey
	self.saved.patrolling
	self.saved.deathTickTimestamp
	self.saved.color
	self.saved.groupKey
	self.saved.patrolKey
	self.saved.raidPosition
	self.saved.stationary
	self.saved.ambusher
	self.saved.aggressive
	self.saved.destroyShapes
	self.saved.friendly
	self.saved.marked
	self.saved.combatRoomName
	self.homePosition
	self.ambushPosition
	self.allyUnits
	self.target
	self.lastTargetPosition
]]
function InitRobotParams( self )
	-- server_onCreate: Init after loading, before saving
	if g_tileStorageManager then
		self.tileStorageKey = TileStorageManager.Sv_GetTileStorageKeyFromObject( self.unit.character )
	end

	if self.params then
		if self.params.tetherPoint then
			self.saved.tetherPoint = self.params.tetherPoint
		end
		if self.params.lootType then
			self.saved.lootType = self.params.lootType
		end
		if self.params.deathEvent then
			self.saved.deathEvent = self.params.deathEvent
		end
		if self.params.targetPlayerOnly ~= nil then
			self.saved.targetPlayerOnly = self.params.targetPlayerOnly
		end
		if self.params.raider then
			self.saved.raider = true
		end
		if self.params.raidKey then
			self.saved.raidKey = self.params.raidKey
		end
		if self.params.isPatrolling ~= nil then
			self.saved.patrolling = self.params.isPatrolling
		end
		if self.params.deathTick then
			self.saved.deathTickTimestamp = self.params.deathTick
		end
		if self.params.color then
			self.saved.color = self.params.color
		end
		if self.params.groupTag then
			self.saved.groupKey = GetTileTagKey( self.tileStorageKey, self.params.groupTag )
		end
		if self.params.patrolTag then
			self.saved.patrolKey = GetTileTagKey( self.tileStorageKey, self.params.patrolTag )
		end
		if self.params.stationary and not self.saved.patrolling then
			self.saved.stationary = true
			self.saved.guardDirection = self.unit.character:getDirection()
		end
		if self.params.ambusher and not self.saved.patrolling then
			self.saved.ambusher = true
		end
		if self.params.aggressive then
			self.saved.aggressive = true
			local targetCharacter = GetClosestPlayerCharacter( self.unit.character.worldPosition, self.unit.character:getWorld() )
			if targetCharacter and ( targetCharacter.worldPosition - self.unit.character.worldPosition ):length() < AGGRESSIVE_TARGET_DISTANCE then
				self.target = targetCharacter
				self.lastTargetPosition = targetCharacter.worldPosition
			end
		end
		if self.params.destroyShapes then
			self.saved.destroyShapes = true
		end
		if self.params.friendly then
			self.saved.friendly = true
		end
		if self.params.combatRoomName then
			self.saved.combatRoomName = self.params.combatRoomName
		end
		if self.params.marked then
			self.saved.marked = true
		end
		if self.params.raidCenter then
			self.saved.raidCenter = self.params.raidCenter
		end
	end
	self.markerPlaced = false

	if self.saved.raidKey then
		RaidManager.Sv_AddRaider( self.saved.raidKey, self.unit )
	end
	if self.saved.patrolKey then
		PatrolManager.Sv_AddUnit( self.saved.patrolKey, self.unit )
	end

	if self.saved.color then
		self.unit.character:setColor( self.saved.color )
	end

	if self.saved.tetherPoint then
		self.homePosition = self.saved.tetherPoint + sm.vec3.new( 0, 0, self.unit.character:getHeight() * 0.5 )
		if self.saved.raider then
			self.saved.raidPosition = self.homePosition
		end
		if self.saved.aggressive then
			self.ambushPosition = self.homePosition
		end
	else
		self.homePosition = self.unit.character.worldPosition
	end

	self.unit.publicData = { groupKey = self.saved.groupKey, raider = self.saved.raider }
	self.allyUnits = {}
	self.shareTargetCounter = 0.0
	self.ignoreAnimalsInWater = true
end

function RobotOnDestroy( self )
	if SurvivalGame then
		if self.saved.raidKey then
			RaidManager.Sv_RemoveRaider( self.saved.raidKey, self.unit )
		end
	end
	if self.target ~= nil or self.eventTarget ~= nil then
		local allies = {}
		FindAllies( self, allies )
		ShareTarget( self, allies, self.target or self.eventTarget )
	end
end

--[[
	Consumes: 
	self.eventTarget

	Writes to:
	self.allyUnits
	self.target
	self.lastTargetPosition
	self.ambushPosition
	self.saved.stationary
	self.isDirty
	
	Listens to:
	self.ignoreWaterTarget
	self.ignoreTargetPerception
]]
function RobotSelectTarget( self, allyRange, dt )
	-- server_onUnitUpdate: Before selecting state
	if self.saved.friendly then
		return
	end
	local targetCharacter
	local closestVisiblePlayerCharacter
	local closestHeardPlayerCharacter
	local closestVisibleWocCharacter
	local closestVisibleWormCharacter
	local closestVisibleBabywocCharacter
	local closestVisibleCrop
	local closestVisibleTeamOpponent
	if not self.ignoreTargetPerception then
		if not SurvivalGame then
			closestVisibleTeamOpponent = sm.ai.getClosestVisibleTeamOpponent( self.unit, self.unit.character:getColor() )
			if self.ignoreWaterTarget then
				if closestVisibleTeamOpponent and sm.physics.isPointInLiquid( closestVisibleTeamOpponent.worldPosition, closestVisibleTeamOpponent:getWorld() ) then
					closestVisibleTeamOpponent = nil
				end
			end
		end
		closestVisiblePlayerCharacter = sm.ai.getClosestVisiblePlayerCharacter( self.unit )
		if self.ignoreWaterTarget then
			if closestVisiblePlayerCharacter and sm.physics.isPointInLiquid( closestVisiblePlayerCharacter.worldPosition, closestVisiblePlayerCharacter:getWorld() ) then
				closestVisiblePlayerCharacter = nil
			end
		end
		if not closestVisiblePlayerCharacter and self.saved.raidKey and self.raidTargetNonVisiblePlayer then
			closestVisiblePlayerCharacter = RaidManager.Sv_GetClosestPlayerInRaid( self.unit.character:getWorld().id, self.saved.raidKey, self.unit.character.worldPosition )
		end
		if not closestVisiblePlayerCharacter then
			closestHeardPlayerCharacter = ListenForPlayerNoise( self.unit.character, self.noiseScale )
			if self.ignoreWaterTarget then
				if closestHeardPlayerCharacter and sm.physics.isPointInLiquid( closestHeardPlayerCharacter.worldPosition, closestHeardPlayerCharacter:getWorld() ) then
					closestHeardPlayerCharacter = nil
				end
			end
		end
		if not self.saved.targetPlayerOnly and not self.saved.raider and not self.ignoreAnimals then
			if not closestVisiblePlayerCharacter and not closestHeardPlayerCharacter then
				if SurvivalGame then
					if not LogEntryManager.Sv_HasLog( LOGS.log_babywoc ) then
						closestVisibleBabywocCharacter = sm.ai.getClosestVisibleCharacterType( self.unit, unit_baby_woc )
					end
				end
				closestVisibleWocCharacter = sm.ai.getClosestVisibleCharacterType( self.unit, unit_woc )
				if closestVisibleWocCharacter and ( closestVisibleWocCharacter.worldPosition - self.unit.character.worldPosition ):length2() > MaxWocAggroDistance * MaxWocAggroDistance then
					closestVisibleWocCharacter = nil
				end
				if self.ignoreWaterTarget or self.ignoreAnimalsInWater then
					if closestVisibleWocCharacter and sm.physics.isPointInLiquid( closestVisibleWocCharacter.worldPosition, closestVisibleWocCharacter:getWorld() ) then
						closestVisibleWocCharacter = nil
					end
				end
			end
			if not closestVisibleWocCharacter and not closestVisiblePlayerCharacter and not closestHeardPlayerCharacter and not self.ignoreAnimals then
				closestVisibleWormCharacter = sm.ai.getClosestVisibleCharacterType( self.unit, unit_worm )
				if self.ignoreWaterTarget or self.ignoreAnimalsInWater then
					if closestVisibleWormCharacter and sm.physics.isPointInLiquid( closestVisibleWormCharacter.worldPosition, closestVisibleWormCharacter:getWorld() ) then
						closestVisibleWormCharacter = nil
					end
				end
			end
			if SurvivalGame then
				if not LogEntryManager.Sv_HasLog( LOGS.log_babywoc ) then
					if not closestVisibleWormCharacter and not closestVisiblePlayerCharacter and not closestHeardPlayerCharacter then
						closestVisibleBabywocCharacter = sm.ai.getClosestVisibleCharacterType( self.unit, unit_baby_woc )
						if closestVisibleBabywocCharacter and ( closestVisibleBabywocCharacter.worldPosition - self.unit.character.worldPosition ):length2() > MaxWocAggroDistance * MaxWocAggroDistance then
							closestVisibleBabywocCharacter = nil
						end
						if self.ignoreWaterTarget or self.ignoreAnimalsInWater then
							if closestVisibleBabywocCharacter and sm.physics.isPointInLiquid( closestVisibleBabywocCharacter.worldPosition, closestVisibleBabywocCharacter:getWorld() ) then
								closestVisibleBabywocCharacter = nil
							end
						end
					end
				end
			end
		end
		if self.saved.raider then
			closestVisibleCrop = sm.ai.getClosestCrop( self.unit )
		elseif not closestVisibleWormCharacter and not closestVisibleWocCharacter and not closestVisiblePlayerCharacter and not closestHeardPlayerCharacter then
			if not self.griefTimer or self.griefTimer:done() then
				closestVisibleCrop = sm.ai.getClosestVisibleCrop( self.unit )
			end
		end
	end

	-- Find target
	if closestVisibleTeamOpponent then
		targetCharacter = closestVisibleTeamOpponent
	elseif closestVisiblePlayerCharacter then
		targetCharacter = closestVisiblePlayerCharacter
	elseif closestHeardPlayerCharacter then
		targetCharacter = closestHeardPlayerCharacter
	elseif closestVisibleWocCharacter then
		targetCharacter = closestVisibleWocCharacter
	elseif closestVisibleWormCharacter then
		targetCharacter = closestVisibleWormCharacter
	elseif closestVisibleBabywocCharacter then
		targetCharacter = closestVisibleBabywocCharacter
	end
	-- Find allies
	
	-- Share found target
	if targetCharacter then
		self.allyUnits = {}
		FindAllies( self, self.allyUnits, allyRange )
		self.shareTargetCounter = self.shareTargetCounter + dt
		if self.target == nil or self.shareTargetCounter > ShareTargetTime then
			if self.saved.ambusher then
				self.saved.ambusher = false
				self.isDirty = true
			end
			ShareTarget( self, self.allyUnits, targetCharacter )
			self.shareTargetCounter = 0.0
		end
	end

	-- Check for targets acquired from callbacks
	if self.eventTarget and sm.exists( self.eventTarget ) and targetCharacter == nil then
		if type( self.eventTarget ) == "Character" then
			if not ( self.eventTarget:isPlayer() and not sm.game.getEnableAggro() ) then
				targetCharacter = self.eventTarget
			end
		end
	end
	self.eventTarget = nil

	if self.saved.raider then
		selectRaidTarget( self, targetCharacter, closestVisibleCrop )
	else
		if targetCharacter then
			self.target = targetCharacter
		else
			self.target = closestVisibleCrop
		end
	end
	if self.target and not sm.exists( self.target ) then
		self.target = nil
	end
	if self.target then
		self.lastTargetPosition = self.target.worldPosition
	end

	-- Ambushers will always have somewhere they want to go
	if self.ambushPosition then
		if not self.lastTargetPosition and not self.target then
			self.lastTargetPosition = self.ambushPosition
		end
		local flatFromToAmbush = sm.vec3.new(  self.ambushPosition.x,  self.ambushPosition.y, self.unit.character.worldPosition.z ) - self.unit.character.worldPosition
		if flatFromToAmbush:length() <= 2.0 then
			-- Finished this ambush
			self.ambushPosition = nil
		end
	end
end

function FindAllies( self, outUnits, allyRange )
	local unitsInRange = sm.unit.getUnitsInRange( self.unit.character:getWorld(), self.unit.character.worldPosition, allyRange or DefaultAlertRange, HEIGHT_DISTANCE_MULTIPLIER )
	for _,allyUnit in ipairs( unitsInRange ) do
		if sm.exists( allyUnit ) and self.unit ~= allyUnit and allyUnit.character and isAnyOf( allyUnit.character:getCharacterType(), g_robots ) then
			local sameTeam = true
			if not SurvivalGame then
				sameTeam = InSameTeam( allyUnit, self.unit )
			end
			if sameTeam then
				outUnits[#outUnits+1] = allyUnit
			end
		end
	end
end

function ShareTarget( self, allies, target )
	for _, allyUnit in ipairs( allies ) do
		local sameTeam = true
		if not SurvivalGame then
			sameTeam = InSameTeam( allyUnit, self.unit )
		end
		if sameTeam and InSameGroup( self.unit, allyUnit ) then
			sm.event.sendToUnit( allyUnit, "sv_e_receiveTarget", { targetCharacter = target, sendingUnit = self.unit } )
		end
	end
end

function CheckFleeFromRaid( self )
	if self.saved.raider and self.saved.deathTickTimestamp then
		
		if self.lastFleeCheckData then
			local currentPosition = self.unit.character.worldPosition
			if ( currentPosition - self.lastFleeCheckData.position ):length2() > RaidFleeStuckDistanceSqr then
				self.lastFleeCheckData = { tick = sm.game.getCurrentTick(), position = currentPosition }
			else
				if ( sm.game.getCurrentTick() - self.lastFleeCheckData.tick ) > RaidFleeStuckTickDuration then
					self.lastFleeCheckData = nil
					self.saved.deathTickTimestamp = nil
					self.saved.raider = false
					self.currentState:stop()
					self.currentState = self.idleState
					self.currentState:start()
					self.isDirty = true
					return false
				end
			end
		end

		if self.currentState == self.raidFlee then
			if not self.lastFleeCheckData then
				self.lastFleeCheckData = { tick = sm.game.getCurrentTick(), position = self.unit.character.worldPosition }
			end
			return true
		end
		if self.currentState ~= self.raidFlee and self.saved.deathTickTimestamp then
			local prevState = self.currentState
			prevState:stop()
			self.currentState = self.raidFlee
			self.currentState:start()
			self.unit:sendCharacterEvent( "raidFlee" )
		end
	end
	return false
end

-- Voxel Breach Detection
local DEBUG_DRAW_VOXEL_BREACH  = true

local DefaultVoxelBreachCheckDistance = 1.5
local BreachZOffset = 0.5

function GetVoxelBreachPosition( character, targetPosition )
	local rayStart = character.worldPosition + sm.vec3.new( 0, 0, BreachZOffset )
	local fromToTarget = targetPosition - rayStart
	local distanceToTarget = fromToTarget:length()
	if distanceToTarget <= 0 then
		return false, nil
	end
	local castRadius = character:getRadius()
	local fullHeight = character:getHeight() - BreachZOffset
	local castHeight = math.max( fullHeight - 2 * castRadius, 0.1 )

	local travelDir = fromToTarget / distanceToTarget
	local rayEnd = rayStart + travelDir * math.min( distanceToTarget, castRadius + DefaultVoxelBreachCheckDistance )

	local hit, result = sm.physics.capsulecast( rayStart, rayEnd, castRadius, castHeight, character, sm.physics.filter.voxelTerrain )
	if hit and result then
		local hitPos = rayStart + ( rayEnd - rayStart ) * result.fraction
		local material, density, position = character.world:getDominantMaterialInCapsule( hitPos, castRadius + 1.0, castHeight )
		if material == 0 and density > 15 then
			if DEBUG_DRAW_VOXEL_BREACH then
				sm.debugDraw.flashSphere( hitPos, castRadius, sm.color.new( 1, 1, 0, 0.3 ), 0.1 )
				sm.debugDraw.flashArrow( hitPos - sm.vec3.new( 0, 0, fullHeight * 0.5 ), hitPos + sm.vec3.new( 0, 0, fullHeight * 0.5 ), sm.color.new( 1, 1, 0, 0.3 ), 0.1 )
			end
			return true, position
		else
			if DEBUG_DRAW_VOXEL_BREACH then
				sm.debugDraw.flashSphere( hitPos, castRadius, sm.color.new( 0, 1, 1, 0.3 ), 0.1 )
				sm.debugDraw.flashArrow( hitPos - sm.vec3.new( 0, 0, fullHeight * 0.5 ), hitPos + sm.vec3.new( 0, 0, fullHeight * 0.5 ), sm.color.new( 0, 1, 1, 0.3 ), 0.1 )
			end
			return false, nil
		end
	end
	if DEBUG_DRAW_VOXEL_BREACH then
		sm.debugDraw.flashSphere( rayEnd, castRadius, sm.color.new( 0, 1, 0, 0.3 ), 0.1 )
		sm.debugDraw.flashArrow( rayEnd - sm.vec3.new( 0, 0, fullHeight * 0.5 ), rayEnd + sm.vec3.new( 0, 0, fullHeight * 0.5 ), sm.color.new( 0, 1, 0, 0.3 ), 0.1 )
	end
	return false, nil
end

function ComputePushbackDirection( character, direction )
	local normalizedDirection = sm.vec3.new( direction.x, direction.y, 0 ):safeNormalize( sm.vec3.new( 1, 0, 0 ) )
	local success,_ = sm.physics.raycast( character.worldPosition, character.worldPosition + sm.vec3.new( direction.x, direction.y, 0 ) * 10, nil, sm.physics.filter.dynamicBody + sm.physics.filter.staticBody )
	if success then
		local dir1 = sm.vec3.rotateZ( sm.vec3.new( direction.x, direction.y, 0 ), math.rad( 10 ) )
		local success1,_ = sm.physics.raycast( character.worldPosition, character.worldPosition + dir1 * 10, nil, sm.physics.filter.dynamicBody + sm.physics.filter.staticBody )
		if not success1 then
			normalizedDirection = dir1
		else
			local dir2 = sm.vec3.rotateZ( sm.vec3.new( direction.x, direction.y, 0 ), math.rad( -10 ) )
			local success2,_ = sm.physics.raycast( character.worldPosition, character.worldPosition + dir2 * 10, nil, sm.physics.filter.dynamicBody + sm.physics.filter.staticBody )
			if not success2 then
				normalizedDirection = dir2
			end
		end
	end
	return normalizedDirection:safeNormalize( sm.vec3.new( 1, 0, 0 ) )
end

-- Constant that requires survival_projectiles.lua
TAPEBOT_MODEL_SETTINGS = {
	["standard"] = {
		projectileBreachLevel = 8,
		projectile = projectile_tape,
		projectileVelocity = 40,
		cooldown = 1.5,
		aimTime = 0.1,
		damage = 35,
		armPartDamage = 20,
		stationaryWallHack = true,
		sidestep = { tickDelay = 20, chance = 0.75 },
		loot = "lootsource_tapebot_schematic"
	},
	["red"] = {
		projectileBreachLevel = 8,
		projectile = projectile_explosivetape,
		projectileVelocity = 40,
		cooldown = 3.0,
		aimTime = 0.25,
		damage = 5,
		armPartDamage = 5,
		sidestep = { tickDelay = 20, chance = 0.75 },
		loot = "lootsource_tapebot_schematic"
	},
	["green"] = {
		projectileBreachLevel = 8,
		projectile = projectile_bubblewrap,
		projectileVelocity = 40,
		cooldown = 3.0,
		aimTime = 0.25,
		damage = 20,
		armPartDamage = 10,
		stationaryWallHack = true,
		sidestep = { tickDelay = 20, chance = 0.75 },
		loot = "lootsource_tapebot"
	},
	["yellow"] = {
		projectileBreachLevel = 8,
		projectile = projectile_colorblob,
		nearProjectileSettings = { range = 8, projectileVelocity = 12 },
		projectileVelocity = 20,
		cooldown = 0.125,
		aimTime = 0.25,
		damage = 5,
		armPartDamage = 5,
		stationaryWallHack = true,
		burstSettings = { shots = 3, cooldownTickTime = 40 * 1.25 },
		sidestep = { tickDelay = 5, chance = 0.75 },
		loot = "lootsource_tapebot_yellow"
	}
}