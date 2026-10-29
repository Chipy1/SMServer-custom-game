dofile "$SURVIVAL_DATA/Scripts/game/units/unit_util.lua"
dofile "$SURVIVAL_DATA/Scripts/util.lua"
dofile "$SURVIVAL_DATA/Scripts/game/util/Ticker.lua"
dofile "$SURVIVAL_DATA/Scripts/game/util/Timer.lua"
dofile "$SURVIVAL_DATA/Scripts/game/survival_shapes.lua"
dofile "$SURVIVAL_DATA/Scripts/game/survival_units.lua"
dofile "$SURVIVAL_DATA/Scripts/game/units/states/PathingState.lua"
dofile "$SURVIVAL_DATA/Scripts/game/units/states/BreachState.lua"
dofile "$SURVIVAL_DATA/Scripts/game/units/states/CombatAttackState.lua"
dofile "$SURVIVAL_DATA/Scripts/game/survival_constants.lua"
dofile "$SURVIVAL_DATA/Scripts/game/survival_items.lua"
dofile "$SURVIVAL_DATA/Scripts/game/managers/CablebotManager.lua"

CablebotUnit = class( BaseUnit )

local AllyRange = 20.0

local DetectPlayerRange = 45 -- Can detect players within this range
local StopSprintingRange = 7 -- Stop sprinting and switch to walking when within this range from the target. Always sprints towards players.
local StopSprintingClimbAngle = 45 -- Walk instead of sprinting when the target requires a steep climb or descent.
local BiteJumpTickDelay = 3 * 40 -- Delay before allowed to jump
local MaxJumpSpeed = 10 -- Max speed of the jump projectile
local PreferredJumpAngle = 70 -- Preferred jump angle in degrees
local PreferredTargetHeight = 4 -- Preferred height difference to the target for the jump attack
local PreferredHeightDifferenceThreshold = 0.2 -- Threshold for considering height difference as similar when selecting targets for the jump attack.
local JumpDistanceComparisonThreshold = 2.0 -- Threshold for considering distances as similar
local JumpSpeedVariationMin = 2 -- The jump projectile will randomly apply an additional speed between min and max variation.
local JumpSpeedVariationMax = 6
local BiteJumpRange = 5 -- Flat distance where the jump check will occur
local ForcedBiteJumpRange = 1 -- Flat distance where the jump will occur no matter what
local BiteJumpDamage = 1 -- Damage casued by the jump projectile if it hits a character
local DetectShapeRange = 16 -- Radius around the character for detecting shapes to attack
local DetectBodyRange = 24 -- Radius around the character for detecting bodies to move towards before shape targeting
local DetectShapesThreshold2 = 8 * 8 -- Switch from body to shape detection when this close to the body
local CloseEnoughRaycastTarget2 = 0.0625 -- 0.25 * 0.25, used for determining if a potential target shape is close enough to count as almost visible when it is not directly visible
local BiteBreachLevel = 9 -- The max level on the parts detected
local BiteRange = 1.0 -- Range of the melee attack against characters
local BiteTickInterval = 0.5 * 40 -- How often the melee attack can occur
local ChangeShapeTargetRange = 16.0 -- Look for closer shapes if current target is further than this distance
local SpawnKnockbackPower = 3000 -- The power of the knockback that hits them if they spawned from being hit by foam while attached to a shape
local BodySizePreferenceMinShapes = 3 -- Prefer attacking bodies with at least this many shapes (main creation vs small debris)
local BodyShapeCheckLimit = 5 -- Check validity of up to this many shapes when selecting a body target

local VoxelDigCooldownTicks = 4 -- How often the cablebot is allowed to dig
local VoxelDigRadius = 1.1 -- Radius of each dig sphere
local VoxelDigStrength = 0.5 -- How much each dig reduces the voxel density (higher is more digging)
local VoxelDigMaxDistance = 2.0 -- Cablebot only digs voxel walls within this distance from itself
local VoxelEdgeSmoothCastRadius = 0.3 -- Spherecast radius matching the cablebot body to catch edge snags the ray misses
local VoxelEdgeSmoothDigStrength = 0.05 -- Gentle dig strength for the edge-smoothing spherecast
local VoxelTargetFlatZMargin = 1.5 -- Treat target as "flat" if it is not lower than this margin below the cablebot

CablebotTargetTypes =
{
	None = 1,
	Body = 2,
	Shape = 3,
	Character = 4
}

CablebotShapesToAttackLast = {
	obj_scrap_smallwheel,
	obj_vehicle_smallwheel,
	obj_vehicle_bigwheel
}

local isValidTargetShape = function( shape, attackLevel )
	local hasNoAttacker = CablebotManager.Sv_GetCablebotAttacker( shape ) == nil
	local normalStatus = not shape:getBurning() and not shape:getCompromised()
	local shapeQualityLevel = sm.item.getQualityLevel( shape.shapeUuid )
	local isWeakOrCraftableShape = isAnyOf( shape.shapeUuid, CABLEBOT_WEAK_SHAPES ) or RecipeManager.IsCraftableShape( shape.shapeUuid )
	return hasNoAttacker and normalStatus and isWeakOrCraftableShape and shape.destructable and attackLevel >= shapeQualityLevel and shapeQualityLevel > 0
end

-- Will prioritize blocks and non-interactable parts
-- Will avoid parts with a container or connections
-- Prio 1 blocks
-- Prio 2 parts
-- Prio 3 shapesToAttackLast
local function findCablebotTargetShape( worldPosition, radius, attackLevel )
	local function filterVisibleCandidates( candidates )
		local maxShapeCasts = 50
		if #candidates == 0 then
			return candidates
		end

		local casts = {}
		for i = 1, math.min( #candidates, maxShapeCasts ) do
			casts[#casts+1] = {
				type = "ray",
				startPoint = worldPosition,
				endPoint = candidates[i].shape.worldPosition
			}
		end

		local castResults = sm.physics.multicast( casts )
		local visibleCandidates = {}
		for i = 1, math.min( #candidates, maxShapeCasts ) do
			local resultPair = castResults[i]
			local hit = resultPair and resultPair[1] or false
			local result = resultPair and resultPair[2] or nil

			if hit and result then
				if result.type == "body" then
					local hitShape = result:getShape()
					if hitShape == candidates[i].shape then
						visibleCandidates[#visibleCandidates+1] = candidates[i]
					elseif hitShape:getBody() == candidates[i].shape:getBody() then
						local validTarget = isValidTargetShape( hitShape, attackLevel )
						if validTarget then
							local aabbMin, aabbMax = hitShape:getLocalAabb()
							local distance2 = Distance2ToAabb( hitShape:transformPoint( result.pointWorld ) + hitShape.localPosition, aabbMin, aabbMax )
							if distance2 < CloseEnoughRaycastTarget2 then
								-- Can't see the desired shape, but vision was blocked by a nearby valid target in the same body
								visibleCandidates[#visibleCandidates+1] = candidates[i]
							end
						end
					end
				end
			else
				-- No hit means clear line of sight
				visibleCandidates[#visibleCandidates+1] = candidates[i]
			end
		end

		return visibleCandidates
	end

	local nearbyShapes = sm.shape.shapesInSphere( worldPosition, radius )
	local destructableWeakShapes = {}
	local destructableNearbyBlocks = {}
	local destructableNearbyParts = {}
	local destructableNearbyShapesToAttackLast = {}
	local bodyShapeCounts = {} -- Cache of body to number of shapes

	for _, shape in ipairs( nearbyShapes ) do
		local validTarget = isValidTargetShape( shape, attackLevel )
		if validTarget then
			local distance2 = ( shape.worldPosition - worldPosition ):length2()
			local heightDiff = shape.worldPosition.z - worldPosition.z
			local body = shape:getBody()
			local bodyShapeCount = bodyShapeCounts[body.id] or body:getShapeCount()
			bodyShapeCounts[body.id] = bodyShapeCount
			local candidate = { shape = shape, distance2 = distance2, heightDiff = heightDiff, bodyShapeCount = bodyShapeCount }
			if shape.isBlock then
				destructableNearbyBlocks[#destructableNearbyBlocks+1] = candidate
			elseif isAnyOf( shape.uuid, CABLEBOT_WEAK_SHAPES ) then
				destructableWeakShapes[#destructableWeakShapes+1] = candidate
			elseif isAnyOf( shape.uuid, CablebotShapesToAttackLast ) then
				destructableNearbyShapesToAttackLast[#destructableNearbyShapesToAttackLast+1] = candidate
			elseif shape.interactable == nil then
				destructableNearbyParts[#destructableNearbyParts+1] = candidate
			end -- else ignore
		end
	end
	-- Sort function that prefers attacking as high as possible, but not over PreferredTargetHeight
	-- Prioritizes close targets first, then uses height as a secondary factor
	local function sortByHeightPreference( a, b )
		-- Prefer larger bodies (main creation) over small debris above all else
		local aIsLargeBody = a.bodyShapeCount >= BodySizePreferenceMinShapes
		local bIsLargeBody = b.bodyShapeCount >= BodySizePreferenceMinShapes
		if aIsLargeBody ~= bIsLargeBody then
			return aIsLargeBody -- Prefer the candidate from the larger body
		end

		local aOverPreferred = a.heightDiff > PreferredTargetHeight
		local bOverPreferred = b.heightDiff > PreferredTargetHeight

		-- Deprioritize targets above preferred height
		if aOverPreferred and not bOverPreferred then
			return false -- b is better
		elseif not aOverPreferred and bOverPreferred then
			return true -- a is better
		end

		-- Both are at valid heights - prefer closer targets primarily
		if not aOverPreferred then
			-- Distance comparison
			local distanceDifference2 = math.abs( a.distance2 - b.distance2 )

			-- If distances are significantly different, prefer the closer one
			if distanceDifference2 > JumpDistanceComparisonThreshold * JumpDistanceComparisonThreshold then
				return a.distance2 < b.distance2 -- Closer is better
			end

			-- Distances are similar - prefer higher target
			local heightDifference = math.abs( a.heightDiff - b.heightDiff )
			if heightDifference > PreferredHeightDifferenceThreshold then
				return a.heightDiff > b.heightDiff -- Higher is better
			end
		end

		-- Same height tier or both over preferred - prefer closer
		return a.distance2 < b.distance2
	end

	local attackTable = nil
	local fallbackAttackTable = nil
	local function tryAttackTable( candidates )
		if attackTable ~= nil or IsEmptyTable( candidates ) then
			return
		end

		table.sort( candidates, sortByHeightPreference )
		if fallbackAttackTable == nil then
			fallbackAttackTable = candidates
		end

		local visibleCandidates = filterVisibleCandidates( candidates )
		if not IsEmptyTable( visibleCandidates ) then
			attackTable = visibleCandidates
		end
	end

	tryAttackTable( destructableWeakShapes )
	tryAttackTable( destructableNearbyBlocks )
	tryAttackTable( destructableNearbyParts )
	tryAttackTable( destructableNearbyShapesToAttackLast )
	if attackTable == nil then
		attackTable = fallbackAttackTable
	end

	if attackTable then
		local targetShape = attackTable[1].shape
		local targetPosition = targetShape.worldPosition
		if sm.item.isBlock( targetShape.shapeUuid ) then
			local targetLocalPosition = targetShape:getClosestBlockLocalPosition( worldPosition )
			targetPosition = targetShape.body:transformPoint( ( targetLocalPosition + sm.vec3.new( 0.5, 0.5, 0.5 ) ) * 0.25 )
		end
		return targetShape, targetPosition
	end

	return nil, nil
end

-- Returns the closest body within radius.
-- Returns: body, distance2
local function findClosestBody( worldPosition, radius, world )
	local contacts = sm.physics.getSphereContacts( worldPosition, radius, world, sm.physics.filter.dynamicBody + sm.physics.filter.staticBody )
	local nearbyBodies = contacts and contacts.bodies or {}
	local closestBody = nil
	local closestDistance2 = nil

	for _, body in ipairs( nearbyBodies ) do
		if sm.exists( body ) then
			local aabbMin, aabbMax = body:getWorldAabb()
			local closestPoint = sm.vec3.new(
				math.max( aabbMin.x, math.min( worldPosition.x, aabbMax.x ) ),
				math.max( aabbMin.y, math.min( worldPosition.y, aabbMax.y ) ),
				math.max( aabbMin.z, math.min( worldPosition.z, aabbMax.z ) )
			)
			local blockedByVoxel, _ = sm.physics.raycast( worldPosition, closestPoint, nil, sm.physics.filter.voxelTerrain )
			if not blockedByVoxel then
				local bodyDistance2 = Distance2ToAabb( worldPosition, aabbMin, aabbMax )
				if closestDistance2 == nil or bodyDistance2 < closestDistance2 then
					closestBody = body
					closestDistance2 = bodyDistance2
				end
			end
		end
	end

	return closestBody, closestDistance2
end

function CablebotUnit.server_onCreate( self )

	self.target = nil
	self.previousTarget = nil

	self.saved = self.storage:load()
	if self.saved == nil then
		self.saved = {}
	end
	if self.saved.stats == nil then
		self.saved.stats = { hp = 10, maxhp = 10 }
	end

	InitRobotParams( self )
	self.biteJumpTimestamp = sm.game.getCurrentTick()
	if self.params then
		if self.params.playerAttacker ~= nil then
			self.saved.playerAttacker = self.params.playerAttacker
		end
		if self.params.voxelDestroyer ~= nil then
			self.saved.voxelDestroyer = self.params.voxelDestroyer
		end
	end
	if self.saved.playerAttacker == nil then
		self.saved.playerAttacker = math.random() < CABLEBOT_PLAYER_ATTACKER_CHANCE
	end
	if self.saved.voxelDestroyer == nil then
		self.saved.voxelDestroyer = true
	end
	self.storage:save( self.saved )

	sm.message.subscribe( MESSAGE_TYPES.GENERAL.ProjectileHit, "sv_m_projectileHit" )
	sm.message.subscribe( MESSAGE_TYPES.GENERAL.ProjectileFire, "sv_m_projectileFire" )
	sm.message.subscribe( MESSAGE_TYPES.GENERAL.Collision, "sv_m_collision" )

	self.unit.eyeHeight = self.unit.character:getHeight() * 0.75
	self.unit.visionFrustum = {
		{ 3.0, math.rad( 80.0 ), math.rad( 80.0 ) },
		{ 20.0, math.rad( 40.0 ), math.rad( 35.0 ) },
		{ 40.0, math.rad( 20.0 ), math.rad( 20.0 ) }
	}
	self.unit:setWhiskerData( 3, math.rad( 60.0 ), 1.5, 5.0 )
	self.noiseScale = 1.0
	self.impactCooldownTicks = 0

	self.voxelDigCooldownTicks = 0

	-- Idle	
	self.idleState = self.unit:createState( "idle" )
	self.idleState.debugName = "idleState"

	-- Approach
	self.approachState = self.unit:createState( "positioning" )
	self.approachState.debugName = "approachState"
	self.approachState.tolerance = 1.0
	self.approachState.avoidance = false
	self.approachState.movementType = "sprint"
	self.approachState.debugName = "approachState"

	-- Tumble
	initTumble( self )

	-- Crushing
	initCrushing( self, DEFAULT_CRUSH_TICK_TIME )

	-- Bite
	self.biteTimer = Timer()
	self.biteTimer:start( BiteTickInterval )

	self.currentState = self.idleState
	self.currentState:start()

	if self.params and self.params.spawnKnockbackDirection then
		ApplyKnockback( self.unit.character, self.params.spawnKnockbackDirection, SpawnKnockbackPower )
	end
end

function CablebotUnit.server_onDestroy( self )
	BaseUnit.server_onDestroy( self )
	CablebotManager.Sv_OnCablebotDestroyed( self.unit )
end

function CablebotUnit.server_onRefresh( self )
end

function CablebotUnit.sv_tryDigTowards( self, targetPosition )
	if not self.saved.voxelDestroyer then
		return
	end
	if self.voxelDigCooldownTicks > 0 then
		return
	end
	local triedDigging = false

	local world = self.unit.character:getWorld()
	local botPosition = self.unit.character.worldPosition
	local fromToTarget = targetPosition - botPosition
	local distanceToTarget = fromToTarget:length()
	if fuzzyZero( distanceToTarget ) then
		return
	end
	local movingUpOrFlat = targetPosition.z >= ( botPosition.z - VoxelTargetFlatZMargin )

	local travelDir = fromToTarget / distanceToTarget
	local digRayEnd = botPosition + travelDir * math.min( distanceToTarget, VoxelDigMaxDistance )
	local hit, result = sm.physics.raycast( botPosition, digRayEnd, self.unit.character, sm.physics.filter.voxelTerrain )
	if hit and result then
		if movingUpOrFlat and result.pointWorld.z < botPosition.z then
			-- Avoid digging downward when we are trying to move up or stay level.
		else
			world:sphereVoxelDensitySubtraction( result.pointWorld, VoxelDigRadius, nil, VoxelDigStrength )
			self.voxelDigCooldownTicks = VoxelDigCooldownTicks
			triedDigging = true
		end
	end

	-- Secondary spherecast with the bot's physical radius to catch edges the ray passes through.
	local sphereHit, sphereResult = sm.physics.spherecast( botPosition, digRayEnd, VoxelEdgeSmoothCastRadius, self.unit.character, sm.physics.filter.voxelTerrain )
	local sphereCastDelta = digRayEnd - botPosition
	local sphereFraction = sphereHit and sphereResult.fraction or 1.0
	local sphereDigPosition = botPosition + sphereCastDelta * sphereFraction
	if sphereHit then
		if not ( movingUpOrFlat and sphereResult.pointWorld.z < botPosition.z ) then
			world:sphereVoxelDensitySubtraction( sphereDigPosition, VoxelDigRadius, nil, VoxelEdgeSmoothDigStrength )
			self.voxelDigCooldownTicks = VoxelDigCooldownTicks
			triedDigging = true
		end
	end

	if triedDigging then
		sm.effect.playEffect( "Cablebot - Digging", botPosition )
	end
end

function CablebotUnit.server_onFixedUpdate( self, dt )
	BaseUnit.server_onFixedUpdate( self )

	if updateCrushing( self ) then
		self:sv_onDeath( sm.vec3.new( 0, 0, 0 ) )
	end

	updateTumble( self )

	if self.currentState then
		if self.target and not sm.exists( self.target ) then
			self.target = nil
		end

		if not self.currentState.customData or not self.currentState.customData.onUnitUpdateOnly then
			self.currentState:onFixedUpdate( dt )
		end
		self.unit:setMovementDirection( self.currentState:getMovementDirection() )
		self.unit:setMovementType( self.currentState:getMovementType() )
		self.unit:setFacingDirection( self.currentState:getFacingDirection() )

		self.impactCooldownTicks = math.max( self.impactCooldownTicks - 1, 0 )
		self.voxelDigCooldownTicks = math.max( self.voxelDigCooldownTicks - 1, 0 )

		-- Bite while approaching
		if self.currentState == self.approachState then
			self.biteTimer:tick()
			if self.biteTimer:done() then
				self.biteTimer:reset()
				sm.melee.meleeAttack( melee_cablebotbite, 3, self.unit.character.worldPosition, self.unit.character.direction * BiteRange, self.unit, 0, 800 )
			end
		else
			self.biteTimer:reset()
		end
	end

	-- Update target for totebot character
	if self.target ~= self.previousTarget then
		self:sv_updateCharacterTarget()
		self.previousTarget = self.target
	end
end

function CablebotUnit.server_onCharacterChangedColor( self, color )
	if self.saved.color ~= color then
		self.saved.color = color
		self.storage:save( self.saved )
	end
end

function CablebotUnit.server_onUnitUpdate( self, dt )

	if not sm.exists( self.unit ) then
		return
	end
	local currentTick = sm.game.getCurrentTick()
	if self.currentState then
		self.currentState:onUnitUpdate( dt )
		if self.currentState.customData and self.currentState.customData.onUnitUpdateOnly then
			self.currentState:onFixedUpdate( dt )
		end
	end

	if self.unit.character:isTumbling() then
		return
	end

	RobotSelectTarget( self, AllyRange, dt )

	-- Can always find the player
	if self.target == nil and sm.game.getEnableAggro() then
		local closestPlayer = GetClosestPlayer( self.unit.character.worldPosition, nil, self.unit.character:getWorld() )
		local closestPlayerCharacter = closestPlayer and closestPlayer.character or nil
		if closestPlayerCharacter and sm.exists( closestPlayerCharacter ) and not closestPlayerCharacter:isDowned() then
			local closestPlayerDistance = ( closestPlayerCharacter.worldPosition - self.unit.character.worldPosition ):length()
			if closestPlayerDistance <= DetectPlayerRange then
				self.target = closestPlayerCharacter
			end
		end
	end

	-- Check for shape to bite
	local desiredBitePosition = nil
	local distanceToBitePosition = nil
	local desiredBodyPosition = nil

	if not self.saved.playerAttacker or self.target == nil then
		local currentTargetShape = CablebotManager.Sv_GetTargetShape( self.unit )
		if currentTargetShape then
			if sm.exists( currentTargetShape ) then
				local currentTargetPosition = currentTargetShape.worldPosition
				local currentDistance = ( currentTargetPosition - self.unit.character.worldPosition ):length()
				-- Prepare current bite position
				desiredBitePosition = currentTargetPosition
				distanceToBitePosition = currentDistance

				local normalStatus = not currentTargetShape:getBurning() and not currentTargetShape:getCompromised()
				if not normalStatus then
					-- Forget target if it has become an invalid target
					CablebotManager.Sv_UnsetTargetShape( currentTargetShape )
					desiredBitePosition = nil
					distanceToBitePosition = nil
				end
				-- Check if should look for closer shape
				if currentDistance > ChangeShapeTargetRange or not normalStatus then
					-- Look for a closer shape to target
					local attackableShape, attackPosition = findCablebotTargetShape( self.unit.character.worldPosition, DetectShapeRange, BiteBreachLevel )
					if attackableShape and attackPosition then
						local otherTargetDistance = ( attackPosition - self.unit.character.worldPosition ):length()
						if otherTargetDistance < currentDistance then
							-- Swap target
							CablebotManager.Sv_UnsetTargetShape( currentTargetShape )
							CablebotManager.Sv_SetTargetShape( self.unit, attackableShape )
							currentTargetShape = attackableShape
							-- Update current bite position
							desiredBitePosition = attackPosition
							distanceToBitePosition = otherTargetDistance
						end
					end
				end
			else
				CablebotManager.Sv_UnsetTargetShape( currentTargetShape ) -- cleanup
			end
		else
			-- Look for a body to attack
			local attackBody, bodyDistance2 = findClosestBody( self.unit.character.worldPosition, DetectBodyRange, self.unit.character:getWorld() )
			if attackBody and bodyDistance2 then
				-- For bodies with few shapes, check if any shape is attackable before targeting the body
				local shouldTargetBody = true
				local bodyShapeCount = attackBody:getShapeCount()
				if bodyShapeCount <= BodyShapeCheckLimit then
					shouldTargetBody = false
					local bodyShapes = attackBody:getShapes()
					for i = 1, bodyShapeCount do
						if isValidTargetShape( bodyShapes[i], BiteBreachLevel ) then
							shouldTargetBody = true
							break
						end
					end
				end

				if shouldTargetBody then
					local aabbMin, aabbMax = attackBody:getWorldAabb()
					local bodyPosition = aabbMin + ( aabbMax - aabbMin ) * 0.5
					local distanceToBodyAabb2 = Distance2ToAabb( self.unit.character.worldPosition, aabbMin, aabbMax )
					-- When close enough to the body, switch to shape targeting
					if distanceToBodyAabb2 <= DetectShapesThreshold2 then
						local attackableShape, attackPosition = findCablebotTargetShape( self.unit.character.worldPosition, DetectShapeRange, BiteBreachLevel )
						if attackableShape == nil then
							-- Failed to find a shape to target, try again with full radius
							attackableShape, attackPosition = findCablebotTargetShape( self.unit.character.worldPosition, DetectBodyRange, BiteBreachLevel )
						end
						if attackableShape and attackPosition then
							desiredBitePosition = attackPosition
							distanceToBitePosition = ( attackPosition - self.unit.character.worldPosition ):length()
							CablebotManager.Sv_SetTargetShape( self.unit, attackableShape )
							currentTargetShape = attackableShape
						else
							-- Ignore the body when close enough for shape targeting but no shape target exists.
							shouldTargetBody = false
						end
					end
					if shouldTargetBody then
						desiredBodyPosition = bodyPosition
					end
				end
			end
		end
	end

	local targetType = CablebotTargetTypes.None
	local approachPosition = nil
	local waitingToJump = false
	if desiredBitePosition then
		targetType = CablebotTargetTypes.Shape
		approachPosition = desiredBitePosition

		if distanceToBitePosition < BiteJumpRange then
			if self.unit.character:isOnGround() then
				-- Jump attack
				local currentTargetShape = CablebotManager.Sv_GetTargetShape( self.unit )
				local skipJumpDelay = currentTargetShape and isAnyOf( currentTargetShape.shapeUuid, CABLEBOT_WEAK_SHAPES )
				if currentTick >= self.biteJumpTimestamp + BiteJumpTickDelay or skipJumpDelay then
					local hit, result = sm.physics.spherecast( self.unit.character.worldPosition, desiredBitePosition, 0.1, self.unit.character )
					local clearJump = hit == false or result.type == "body"
					if clearJump or distanceToBitePosition < ForcedBiteJumpRange then
						self.biteJumpTimestamp = currentTick
						self:sv_jumpAttack( desiredBitePosition )
					end
				else
					waitingToJump = true
				end
			end
		end
	elseif desiredBodyPosition then
		targetType = CablebotTargetTypes.Body
		approachPosition = desiredBodyPosition
	elseif self.target and sm.exists( self.target ) then
		targetType = CablebotTargetTypes.Character
		approachPosition = self.target.worldPosition
		self.approachState.desiredPosition = self.target.worldPosition
		local fromToTarget = self.target.worldPosition - self.unit.character.worldPosition
		self.approachState.desiredDirection = fromToTarget:safeNormalize( sm.vec3.new( 0, 1, 0 ) )
	end

	if targetType ~= CablebotTargetTypes.None then
		self:sv_tryDigTowards( approachPosition )
		if targetType == CablebotTargetTypes.Character then
			self.approachState.movementType = "sprint"
		else
			local fromToTarget = approachPosition - self.unit.character.worldPosition
			local horizontalTargetDistance = HorizontalDistance( approachPosition, self.unit.character.worldPosition )
			local targetAngle = math.deg( math.atan( math.abs( fromToTarget.z ) / math.max( horizontalTargetDistance, 0.001 ) ) )
			local distanceToApproach = ( approachPosition - self.unit.character.worldPosition ):length()
			if distanceToApproach <= StopSprintingRange or targetAngle >= StopSprintingClimbAngle then
				self.approachState.movementType = "walk"
			else
				self.approachState.movementType = "sprint"
			end
		end
		if waitingToJump then
			self.approachState.desiredPosition = self.unit.character.worldPosition -- Stay in place and wait to jump
		else
			self.approachState.desiredPosition = approachPosition
		end
		local fromToTarget = approachPosition - self.unit.character.worldPosition
		self.approachState.desiredDirection = fromToTarget:safeNormalize( sm.vec3.new( 0, 1, 0 ) )
	end

	local prevState = self.currentState
	local done, result = self.currentState:isDone()
	if done then
		if self.currentState == self.approachState and result == "timeout" then
			-- Got stuck while trying to approach, try to find a new target
			local currentTargetShape = CablebotManager.Sv_GetTargetShape( self.unit )
			if currentTargetShape then
				CablebotManager.Sv_UnsetTargetShape( currentTargetShape )
			end
			approachPosition = nil
		end
		if approachPosition then
			self.currentState = self.approachState
		else
			self.currentState = self.idleState
		end
	end

	if prevState ~= self.currentState then
		prevState:stop()
		self.currentState:start()
		if DEBUG_AI_STATES then
			print( self.currentState.debugName )
		end
	end
end

function CablebotUnit.server_onProjectile( self, hitPos, hitTime, hitVelocity, _, attacker, damage, userData, hitNormal, projectileUuid )
	if not sm.exists( self.unit ) or not sm.exists( attacker ) then
		return
	end
	local teamOpponent = false
	if type( attacker ) == "Unit" then
		if not SurvivalGame then
			teamOpponent = not InSameTeam( attacker, self.unit )
		end
	end

	if type( attacker ) == "Player" or type( attacker ) == "Shape" or teamOpponent then
		if projectileUuid == projectile_foam then
			-- Temporarily unable to attach to shapes
			self.biteJumpTimestamp = sm.game.getCurrentTick()
		end
		if damage > 0 then
			if self.eventTarget == nil then
				if type( attacker ) == "Player" or type( attacker ) == "Unit" then
					self.eventTarget = attacker:getCharacter()
				elseif type( attacker ) == "Shape" then
					self.eventTarget = attacker
				end
			end
			self:sv_knockback( hitPos, hitVelocity )
		end
		local impact = hitVelocity:normalize() * 6
		self:sv_takeDamage( damage, impact, hitPos )
	end
end

function CablebotUnit.server_onMelee( self, hitPos, attacker, damage, power, hitDirection )
	if not sm.exists( self.unit ) or not sm.exists( attacker ) then
		return
	end
	local teamOpponent = false
	if type( attacker ) == "Unit" then
		if not SurvivalGame then
			teamOpponent = not InSameTeam( attacker, self.unit )
		end
	end

	if type( attacker ) == "Player" or teamOpponent then
		local attackingCharacter = attacker:getCharacter()
		if self.eventTarget == nil then
			self.eventTarget = attackingCharacter
		end

		local impact = hitDirection * 6
		self:sv_takeDamage( damage, impact, hitPos )
		self:sv_knockback( hitPos, hitDirection )
	end
end

function CablebotUnit.server_onExplosion( self, center, destructionLevel )
	if not sm.exists( self.unit ) then
		return
	end
	local impact = ( self.unit:getCharacter().worldPosition - center ):safeNormalize( sm.vec3.new( 0, 0, 1 ) ) * 6
	self:sv_takeDamage( self.saved.stats.maxhp, impact, self.unit:getCharacter().worldPosition )
end

function CablebotUnit.server_onCollision( self, other, collisionPosition, selfPointVelocity, otherPointVelocity, collisionNormal )
	if not sm.exists( self.unit ) then
		return
	end

	if type( other ) == "Character" then
		if not sm.exists( other ) then
			return
		end
		local teamOpponent = false
		if not SurvivalGame then
			teamOpponent = not InSameTeam( other, self.unit )
		end
		if other:isPlayer() or teamOpponent then
			if self.eventTarget == nil then
				self.eventTarget = other
			end
		end
	elseif type( other ) == "Shape" then
		if not sm.exists( other ) then
			return
		end
		if self.target == nil and self.eventTarget == nil then
			local creationBodies = other.body:getCreationBodies()
			for _, body in ipairs( creationBodies ) do
				local seatedCharacters = body:getAllSeatedCharacter()
				if #seatedCharacters > 0 then
					self.eventTarget = seatedCharacters[1]
					break
				end
			end
		end
	end

	if self.impactCooldownTicks > 0 then
		return
	end

	local collisionDamageMultiplier = 0.2
	local damage, tumbleTicks, tumbleVelocity, impactReaction = CharacterCollision( self.unit.character, other, collisionPosition, selfPointVelocity, otherPointVelocity, collisionNormal, self.saved.stats.maxhp / collisionDamageMultiplier, nil, self.velocityBuffer, self.velocityBufferIndex )
	damage = damage * collisionDamageMultiplier
	if damage > 0 or tumbleTicks > 0 then
		self.impactCooldownTicks = 6
	end
	if damage > 0 then
		self:sv_takeDamage(damage, collisionNormal, collisionPosition)

		if self.saved.stats.hp <= 0  then
			--Achievement check
			RoadRageAchievementCheck(other)
		end
	end
end

function CablebotUnit.server_onCollisionCrush( self )
	if not sm.exists( self.unit ) then
		return
	end
	onCrush( self )
end

function CablebotUnit.sv_updateCharacterTarget( self )
	if self.unit.character then
		sm.event.sendToCharacter( self.unit.character, "sv_n_updateTarget", { target = self.target } )
	end
end

function CablebotUnit.sv_takeDamage( self, damage, impact, hitPos, source )
	if self.saved.stats.hp > 0 and damage > 0 then
		if source == "plasma" then
			damage = self.saved.stats.maxhp
		end
		self.saved.stats.hp = self.saved.stats.hp - damage
		self.saved.stats.hp = math.max( self.saved.stats.hp, 0 )

		local effectRotation = sm.quat.identity()
		if hitPos and impact then
			local impactDirection = impact:safeNormalize( sm.vec3.new( 0, 0, 1 ) )
			effectRotation = sm.vec3.getRotation( sm.vec3.new( 0, 0, 1 ), -impactDirection )
		end

		if self.saved.stats.hp <= 0 then
			self:sv_onDeath( impact )
		else
			sm.effect.playEffect( "ToteBot - Hit", hitPos, nil, effectRotation )
			self.storage:save( self.saved )
		end
	end
end

function CablebotUnit.sv_jumpAttack( self, desiredPosition )
	local fromPosition = self.unit.character.worldPosition
	local fromTo = desiredPosition - fromPosition

	-- Calculate projectile velocity optimized for the configured launch angle
	local horizontalDistance = sm.vec3.new( fromTo.x, fromTo.y, 0 ):length()
	local verticalDistance = fromTo.z

	-- Base velocity for the desired angle: v = sqrt((range * gravity) / sin( 2 * angle ) )
	-- Using gravity magnitude of 10
	local angleRad = math.rad( PreferredJumpAngle )
	local baseVelocity = math.sqrt( ( horizontalDistance * 10 ) / math.sin( 2 * angleRad ) )

	-- Adjust for height difference - add energy when going upward
	if verticalDistance > 0 then
		baseVelocity = baseVelocity + math.sqrt( 2 * 10 * verticalDistance )
	end

	-- Add random variation for natural feel
	local jumpSpeedVariation = JumpSpeedVariationMin + math.random() * ( JumpSpeedVariationMax - JumpSpeedVariationMin )
	local projectileVelocity = math.min( MaxJumpSpeed, baseVelocity + jumpSpeedVariation )

	-- Jump in an arc
	local lowAngleVector, _ = sm.projectile.solveBallisticArc( self.unit.character.worldPosition, desiredPosition, projectileVelocity, GRAVITY )
	if lowAngleVector then
		sm.projectile.projectileAttack( projectile_cablebot, BiteJumpDamage, self.unit.character.worldPosition, lowAngleVector, self.unit )
		sm.effect.playEffect( "Cablebot - Jumpattack_start", self.unit.character.worldPosition )
		self.unit:destroy()
		self.destroyed = true
	end
end


function CablebotUnit.sv_knockback( self, hitPos, direction, power )
	local knockbackPosition = hitPos or self.unit.character.worldPosition
	local knockbackPower = power or 4000
	local knockbackDirection = direction:safeNormalize( -self.unit.character.direction )
	if not self.unit.character:isTumbling() then
		startTumble( self, 25, self.idleState )
	end
	local offset = knockbackPosition - self.unit.character.worldPosition
	ApplyCharacterImpulse( self.unit.character, knockbackDirection, knockbackPower, offset )
end

function CablebotUnit.sv_onDeath( self, impact )
	local character = self.unit:getCharacter()
	if not self.destroyed then
		sm.effect.playEffect( "CableBot - Death", character.worldPosition, nil, nil, nil, { Color = self.unit.character:getColor(), ExplosionIndex = math.random( 1, 3 ) } )
		g_unitManager:sv_addDeathMarker( character.worldPosition )
		self.saved.stats.hp = 0
		self.unit:destroy()
		--self:sv_spawnParts( impact )
		if SurvivalGame then
			local loot = SelectLoot( "lootsource_cablebot", nil, self.saved.lootType )
			SpawnLoot( self.unit, loot )
		end
		BaseUnit.sv_onDeath( self )
		self.destroyed = true
	end
end

function CablebotUnit.sv_spawnParts( self, impact )
	local character = self.unit:getCharacter()

	local lookDirection = character:getDirection()
	local bodyPos = character.worldPosition
	local bodyRot = sm.quat.identity()
	lookDirection = sm.vec3.new( lookDirection.x, lookDirection.y, 0 )
	if lookDirection:length() >= FLT_EPSILON then
		lookDirection = lookDirection:normalize()
		bodyRot = sm.vec3.getRotation( sm.vec3.new( 0, 1, 0 ), lookDirection  ) --Turn parts sideways
	end
	local bodyOffset = bodyRot * sm.vec3.new( -0.25, 0.25, 0.375 )
	bodyPos = bodyPos - bodyOffset

	local color = self.unit.character:getColor()

	if math.random( 1, 5 ) == 1 then
		local middleBody = sm.body.createBody( bodyPos, bodyRot, true )
		local middleShape = middleBody:createPart( obj_robotpart_cablebot, sm.vec3.new( 0, 0, 0 ), sm.vec3.new( 0, 1, 0 ), sm.vec3.new( -1, 0, 0 ), true )
		middleShape.color = color
		sm.physics.applyImpulse( middleShape, impact * middleShape.mass, true )
	end

end
