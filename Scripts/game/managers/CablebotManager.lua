CablebotManager = class()

local TimeScale = 1.0 -- For testing ( Default: 1.0 )
local InvTimeScale = TimeScale > 0 and 1 / TimeScale or 1
local ShapeCablebotExtent = 0.25 -- AreaTrigger extents around a compromised shape
local AttachRadius = 0.5

local DefaultColorString = "49642d"
local BlockEffects = { "Cablebot - Attached_blocks01", "Cablebot - Attached_blocks02", "Cablebot - Attached_blocks03" }
local SmallPartEffects = { "Cablebot - Attached_smallparts01", "Cablebot - Attached_smallparts02", "Cablebot - Attached_smallparts03" }
local PartEffects = { "Cablebot - Attached_parts01", "Cablebot - Attached_parts02", "Cablebot - Attached_parts03" }
local SmallPartSize = 3 -- Size threshold for small parts effects

local DirectionProbeShrink = 0.03
local DirectionProbeExtend = 0.25 + DirectionProbeShrink
local DirectionProbeMinHalfExtent = 0.05
local TriggerDirectionalExtend = 0.2

local SideDirections = {
	sm.vec3.new( 1, 0, 0 ),
	sm.vec3.new( -1, 0, 0 ),
	sm.vec3.new( 0, 1, 0 ),
	sm.vec3.new( 0, -1, 0 )
}

local function isDirectionBlockedByBoxProbe( shape, baseHalfExtents, direction )
	local probeCenter = shape.worldPosition
	local probeHalfExtents = sm.vec3.new( baseHalfExtents )
	local extendHalf = DirectionProbeExtend * 0.5
	local rotation = shape.worldRotation
	local localDirection = rotation:inverse() * direction

	local absX = math.abs( localDirection.x )
	local absY = math.abs( localDirection.y )
	local absZ = math.abs( localDirection.z )
	local localAxis

	if absX >= absY and absX >= absZ then
		-- X is the dominant axis, so extend probe in X direction
		localAxis = sm.vec3.new( localDirection.x >= 0 and 1 or -1, 0, 0 )
		probeHalfExtents.x = probeHalfExtents.x + extendHalf
	elseif absY >= absX and absY >= absZ then
		-- Y is the dominant axis, so extend probe in Y direction
		localAxis = sm.vec3.new( 0, localDirection.y >= 0 and 1 or -1, 0 )
		probeHalfExtents.y = probeHalfExtents.y + extendHalf
	else
		-- Z is the dominant axis, so extend probe in Z direction
		localAxis = sm.vec3.new( 0, 0, localDirection.z >= 0 and 1 or -1 )
		probeHalfExtents.z = probeHalfExtents.z + extendHalf
	end

	probeCenter = probeCenter + ( rotation * localAxis ) * extendHalf

	local shapeContacts = sm.physics.getShapeContactsInBox( probeCenter, rotation, probeHalfExtents )
	for _, shapeContact in ipairs( shapeContacts ) do
		if shapeContact.shape.id ~= shape.id then
			return true
		end
	end

	return false
end

local function getFreeSurfaceDirection( shape )
	local halfSize = shape:getBoundingBox() * 0.5
	local baseHalfExtents = sm.vec3.new(
		math.max( halfSize.x - DirectionProbeShrink, DirectionProbeMinHalfExtent ),
		math.max( halfSize.y - DirectionProbeShrink, DirectionProbeMinHalfExtent ),
		math.max( halfSize.z - DirectionProbeShrink, DirectionProbeMinHalfExtent )
	)

	local upDirection = sm.vec3.new( 0, 0, 1 )
	-- Check up
	local upBlocked = isDirectionBlockedByBoxProbe( shape, baseHalfExtents, upDirection )
	if upBlocked then
		-- Check sides in a deterministic rotated order so server/client choose the same direction.
		local startIdx = ( shape.id % #SideDirections ) + 1
		for i = 1, 4 do
			local sideDirection = SideDirections[(( startIdx + i - 2 ) % #SideDirections ) + 1]
			if not isDirectionBlockedByBoxProbe( shape, baseHalfExtents, sideDirection ) then
				local localDirection = shape.worldRotation:inverse() * sideDirection
				return localDirection:safeNormalize( sideDirection )
			end
		end
		-- Check down
		if not isDirectionBlockedByBoxProbe( shape, baseHalfExtents, -upDirection ) then
			local localDirection = shape.worldRotation:inverse() * -upDirection
			return localDirection:safeNormalize( -upDirection )
		end
	end

	-- Default to up
	local localDirection = shape.worldRotation:inverse() * upDirection
	return localDirection:safeNormalize( upDirection )
end

local function computeDirectionalTriggerBox( shape, localDirection )
	local triggerExtents = sm.vec3.new( ShapeCablebotExtent, ShapeCablebotExtent, ShapeCablebotExtent )
	local triggerHalfSize = shape:getBoundingBox() * 0.5 + triggerExtents
	local triggerOffset = sm.vec3.new( 0, 0, 0 )

	local absX = math.abs( localDirection.x )
	local absY = math.abs( localDirection.y )
	local absZ = math.abs( localDirection.z )
	local extendHalf = TriggerDirectionalExtend * 0.5

	if absX >= absY and absX >= absZ then
		local sign = localDirection.x >= 0 and 1 or -1
		triggerHalfSize.x = triggerHalfSize.x + extendHalf
		triggerOffset.x = sign * extendHalf
	elseif absY >= absX and absY >= absZ then
		local sign = localDirection.y >= 0 and 1 or -1
		triggerHalfSize.y = triggerHalfSize.y + extendHalf
		triggerOffset.y = sign * extendHalf
	else
		local sign = localDirection.z >= 0 and 1 or -1
		triggerHalfSize.z = triggerHalfSize.z + extendHalf
		triggerOffset.z = sign * extendHalf
	end

	return triggerHalfSize, triggerOffset
end

local function createCablebotEffectWithTransform( shape )
	local freeSurfaceDirection = getFreeSurfaceDirection( shape )
	local offsetRotation = sm.vec3.getRotation( sm.vec3.new( 0, 0, 1 ), freeSurfaceDirection )

	if shape.isBlock then
		local effectName = BlockEffects[math.random( 1, #BlockEffects )]
		local cablebotEffect = sm.effect.createEffect( effectName, shape )
		cablebotEffect:setOffsetRotation( offsetRotation )
		return cablebotEffect
	else
		local bounds = shape:getBoundingBox()
		local size = math.max( round( bounds.x * 4 ), round( bounds.y * 4 ), round( bounds.z * 4 ) )
		local effectName
		if size < SmallPartSize then
			effectName = SmallPartEffects[math.random( 1, #SmallPartEffects )]
			local cablebotEffect = sm.effect.createEffect( effectName, shape )
			cablebotEffect:setOffsetRotation( offsetRotation )
			return cablebotEffect
		else
			effectName = PartEffects[math.random( 1, #PartEffects )]
			local cablebotEffect = sm.effect.createEffect( effectName, shape )
			cablebotEffect:setOffsetRotation( offsetRotation )

			local halfSize = shape:getBoundingBox() * 0.5
			local edgeOffset = sm.vec3.new(
				freeSurfaceDirection.x * halfSize.x,
				freeSurfaceDirection.y * halfSize.y,
				freeSurfaceDirection.z * halfSize.z
			)
			cablebotEffect:setOffsetPosition( edgeOffset )
			return cablebotEffect
		end
	end
end

local function computeDestroyTickTime( shape )
	local DestroyTimeMin = 110
	local DestroyTimeMax = 130
	if isAnyOf( shape.uuid, CABLEBOT_WEAK_SHAPES ) then
		DestroyTimeMin = 0.5
		DestroyTimeMax = 1.5
	elseif not RecipeManager.IsCraftableShape( shape.shapeUuid ) then
		-- Will be unable to destroy, so immediately give up and revert to cablebot form
		return 0
	end

	-- Feature multipliers (how much each factor matters)
	local wDurability = 1.0
	local wDensity = 1.0
	local wVolume = 1.0

	-- Curve shaping (>=1 makes the effect kick in later, <1 makes it kick in earlier)
	local gDurability = 1.0
	local gDensity = 1.0
	local gVolume = 1.0

	-- Volume half-saturation point: when volume == vHalf, volume feature == 0.5
	local vHalf = 27.0
	-------------------

	local durability = sm.item.getDurabilityRating( shape.uuid )
	local density = sm.item.getDensityRating( shape.uuid )
	local bounds = sm.item.getShapeSize( shape.uuid )
	local volume = bounds.x * bounds.y * bounds.z

	-- Saturating transform for unbounded volume:
	-- v = 1 - exp(-ln(2) * volume / vHalf)  -> 0..1, hits 0.5 at volume=vHalf
	local ln2 = 0.6931471805599453
	local v = 1 - math.exp( -ln2 * ( math.max( volume, 0 ) ) / vHalf )
	v = clamp( v, 0, 1 )

	-- Curve shaping
	local sDurability = normalize( durability, 1, 10 ) ^ gDurability
	local sDensity = normalize( density, 1, 10 ) ^ gDensity
	local sVolume = v ^ gVolume

	-- Weighted blend -> score in 0..1
	local sumW = wDurability + wDensity + wVolume
	local score = ( wDurability * sDurability + wDensity * sDensity + wVolume * sVolume ) / sumW
	score = clamp( score, 0, 1 )

	-- Map to time range
	local destroyTime = DestroyTimeMin + ( DestroyTimeMax - DestroyTimeMin ) * score
	return destroyTime * 40 * InvTimeScale
end

function CablebotManager.server_onCreate( self )
    g_cablebotManagerServer = self
    self.sv = {}
	self.sv.shapesWithCablebot = {}
	self.sv.targetShapeByUnitId = {}
	self.sv.unitByTargetShapeId = {}
end

function CablebotManager.server_onRefresh( self ) end

--[[ Manager ]]
function CablebotManager.Sv_OnWorldFixedUpdate( world )
	if g_cablebotManagerServer then
		g_cablebotManagerServer:sv_onWorldFixedUpdate( world )
	end
end

function CablebotManager.sv_onWorldFixedUpdate( self, world )
	local currentTick = sm.game.getCurrentTick()

	-- Update cablebots compromising shapes
    local shapesWithCablebot = self.sv.shapesWithCablebot[world.id] == nil and {} or self.sv.shapesWithCablebot[world.id]
	local compromisedShapes = sm.compromised.getCompromisedShapes()
	local updatedShapesWithCablebot = {}
	for _, shape in ipairs( compromisedShapes ) do
		if sm.exists( shape ) and shape:getCompromised() then
			local shapeWithCablebot = shapesWithCablebot[shape.id]
			if shapeWithCablebot then
				-- Shape still exists and is still compromised
				local shouldDestroy = shapeWithCablebot.destroyTick and currentTick >= shapeWithCablebot.destroyTick
				if shouldDestroy then
					-- Destroy compromised shape
					if sm.exists( shapeWithCablebot.shape ) then
						local isWeakOrCraftableShape = isAnyOf( shapeWithCablebot.shape.shapeUuid, CABLEBOT_WEAK_SHAPES ) or RecipeManager.IsCraftableShape( shapeWithCablebot.shape.shapeUuid )
						if sm.item.isHarvestablePart( shapeWithCablebot.shape.uuid ) then
							if shapeWithCablebot.shape.interactable then
								local params = { damage = 100, type = "cablebot" }
								sm.event.sendToInteractable( shapeWithCablebot.shape.interactable, "sv_e_receiveDamage", params )
							end
						elseif isAnyOf( shapeWithCablebot.shape.uuid, g_capsules ) then
							-- A capsule is gnawed through, so open it
							sm.event.sendToInteractable( shapeWithCablebot.shape.interactable, "sv_e_open" )
							shapeWithCablebot.destroyTick = nil
						elseif isAnyOf( shapeWithCablebot.shape.uuid, g_explosives ) then
							-- Ignited an explosive
							sm.event.sendToInteractable( shapeWithCablebot.shape.interactable, "server_startCountdown" )
							shapeWithCablebot.destroyTick = nil
						elseif shapeWithCablebot.shape.destructable and isWeakOrCraftableShape then
							-- A destructable shape is gnawed through, so destroy it
							sm.effect.playEffect( "CableBot - DestroyedParts", shapeWithCablebot.shape.worldPosition )
							shapeWithCablebot.shape:destroyShape( 0, sm.shape.destructionType.melee, shapeWithCablebot.shape.worldPosition )
						else
							-- Failed to destroy shape, revert into cablebot
							shapeWithCablebot.shape:setCompromised( false )
						end
						-- Respawn cablebot
						local yaw = math.random() * math.pi * 2
						sm.unit.createUnit( unit_cablebot, shapeWithCablebot.shape.worldPosition, yaw )
					end
				else
					updatedShapesWithCablebot[shape.id] = shapeWithCablebot
					shapesWithCablebot[shape.id] = nil
				end
			else
				-- Setup new cablebot attachment
				local destroyTick = currentTick + computeDestroyTickTime( shape )
				local localDirection = getFreeSurfaceDirection( shape )
				local halfSize, offset = computeDirectionalTriggerBox( shape, localDirection )
				local filter = sm.areaTrigger.filter.character
				local areaTrigger = sm.areaTrigger.createAttachedBox( shape, halfSize, offset, nil, filter, { shapeId = shape.id }, sm.areaTrigger.areaTriggerProxyType.melee )
				areaTrigger:bindOnProjectile( "trigger_onProjectile", self )
				areaTrigger:bindOnMelee( "trigger_onMelee", self )
				updatedShapesWithCablebot[shape.id] = {
					shape = shape,
					areaTrigger = areaTrigger,
					destroyTick = destroyTick
				}
			end
		else
			-- There's no compromised shape. Cleanup areaTrigger.
			local shapeWithCablebot = shapesWithCablebot[shape.id]
			if shapeWithCablebot then
				if sm.exists( shapeWithCablebot.areaTrigger ) then
					sm.areaTrigger.destroy( shapeWithCablebot.areaTrigger )
				end
			end
		end
	end

	-- Cleanup removed shapeWithCablebot
	for _, shapeWithCablebot in pairs( shapesWithCablebot ) do
		if sm.exists( shapeWithCablebot.areaTrigger ) then
			sm.areaTrigger.destroy( shapeWithCablebot.areaTrigger )
		end
	end
	self.sv.shapesWithCablebot[world.id] = updatedShapesWithCablebot
end

function CablebotManager.Sv_AttachCablebot( hitPos, attachDirection )
	if g_cablebotManagerServer then
		g_cablebotManagerServer:sv_attachCablebot( hitPos, attachDirection )
	end
end

function CablebotManager.sv_attachCablebot( self, hitPos, attachDirection )
	local attached = sm.compromised.compromiseShapeInSphere( hitPos, AttachRadius )
	if not attached then
		-- Create cablebot unit
		local yaw = math.atan2( attachDirection.y, attachDirection.x ) - math.pi / 2
		sm.unit.createUnit( unit_cablebot, hitPos, yaw )
	end
end

function CablebotManager.Sv_SetTargetShape( cablebotUnit, shape )
	if g_cablebotManagerServer then
		g_cablebotManagerServer:sv_setTargetShape( cablebotUnit, shape )
	end
end

function CablebotManager.sv_setTargetShape( self, cablebotUnit, shape )
	self.sv.targetShapeByUnitId[cablebotUnit.id] = shape
	self.sv.unitByTargetShapeId[shape.id] = cablebotUnit
end

function CablebotManager.Sv_GetTargetShape( cablebotUnit )
	if g_cablebotManagerServer then
		return g_cablebotManagerServer:sv_getTargetShape( cablebotUnit )
	end
	return nil
end

function CablebotManager.sv_getTargetShape( self, cablebotUnit )
	return self.sv.targetShapeByUnitId[cablebotUnit.id]
end

function CablebotManager.Sv_GetCablebotAttacker( shape )
	if g_cablebotManagerServer then
		return g_cablebotManagerServer:sv_getCablebotAttacker( shape )
	end
	return nil
end

function CablebotManager.sv_getCablebotAttacker( self, shape )
	return self.sv.unitByTargetShapeId[shape.id]
end

function CablebotManager.Sv_UnsetTargetShape( shape )
	if g_cablebotManagerServer then
		g_cablebotManagerServer:sv_unsetTargetShape( shape )
	end
end

function CablebotManager.sv_unsetTargetShape( self, shape )
	local cablebotUnit = self.sv.unitByTargetShapeId[shape.id]
	if cablebotUnit then
		self.sv.targetShapeByUnitId[cablebotUnit.id] = nil
	end
	self.sv.unitByTargetShapeId[shape.id] = nil
end

function CablebotManager.Sv_OnCablebotDestroyed( cablebotUnit )
	if g_cablebotManagerServer then
		g_cablebotManagerServer:sv_onCablebotDestroyed( cablebotUnit )
	end
end

function CablebotManager.sv_onCablebotDestroyed( self, cablebotUnit )
	local shape = self.sv.targetShapeByUnitId[cablebotUnit.id]
	if shape then
		self.sv.unitByTargetShapeId[shape.id] = nil
	end
	self.sv.targetShapeByUnitId[cablebotUnit.id] = nil
end



















function CablebotManager.Sv_Explosion( position, radius )
	if g_cablebotManagerServer then
		g_cablebotManagerServer:sv_explosion( position, radius )
	end
end

function CablebotManager.sv_explosion( self, position, radius )
	local world = sm.world.getCurrentWorld()
	if sm.compromised.hasCompromisedShapes( world ) then
		local shapeCollisions = sm.physics.getShapeContactsInSphere( position, radius, world )
		for _, shapeCollision in ipairs( shapeCollisions ) do
			local shapeWithCablebot = shapeCollision.shape
			if sm.exists( shapeWithCablebot ) and shapeWithCablebot:getCompromised() then
				sm.effect.playEffect( "CableBot - DestroyedParts", shapeWithCablebot.worldPosition, nil, nil, nil, { ExplosionIndex = math.random( 1, 3 ), Color = sm.color.new( DefaultColorString ) } )
				if SurvivalGame then
					local loot = SelectLoot( "lootsource_cablebot" )
					SpawnLoot( shapeWithCablebot, loot )
				end
				shapeWithCablebot:setCompromised( false )
			end
		end
	end
end
function CablebotManager.trigger_onMelee( self, trigger, hitPos, attacker, damage, power, hitDirection )
	local currentWorld = sm.world.getCurrentWorld()
	local shapesWithCablebot = self.sv.shapesWithCablebot[currentWorld.id]
	if sm.exists( trigger ) and type( attacker ) == "Player" or type( attacker ) == "Shape" then
		if damage > 0 then
			local ud = trigger:getUserData()
			local shapeWithCablebot = shapesWithCablebot and shapesWithCablebot[ud.shapeId] or nil
			if shapeWithCablebot and sm.exists( shapeWithCablebot.shape ) and shapeWithCablebot.shape:getCompromised() then
				sm.effect.playEffect( "CableBot - Death", hitPos, nil, nil, nil, { ExplosionIndex = math.random( 1, 3 ), Color = sm.color.new( DefaultColorString ) } )
				if SurvivalGame then
					local loot = SelectLoot( "lootsource_cablebot" )
					SpawnLoot( shapeWithCablebot.shape, loot )
				end
				shapeWithCablebot.shape:setCompromised( false )
			end
		end
	end
end

function CablebotManager.trigger_onProjectile( self, trigger, hitPos, hitTime, hitVelocity, _, attacker, damage, userData, hitNormal, projectileUuid )
	local currentWorld = sm.world.getCurrentWorld()
	local shapesWithCablebot = self.sv.shapesWithCablebot[currentWorld.id]
	if sm.exists( trigger ) and type( attacker ) == "Player" or type( attacker ) == "Shape" then
		if projectileUuid == projectile_foam then
			local ud = trigger:getUserData()
			local shapeWithCablebot = shapesWithCablebot and shapesWithCablebot[ud.shapeId] or nil
			if shapeWithCablebot and sm.exists( shapeWithCablebot.shape ) and shapeWithCablebot.shape:getCompromised() then
				local yaw = math.random() * math.pi * 2
				local spawnParams = { spawnKnockbackDirection = hitVelocity:safeNormalize( sm.vec3.new( 0, 0, 1 ) ) }
				sm.unit.createUnit( unit_cablebot, shapeWithCablebot.shape.worldPosition, yaw, spawnParams )
				shapeWithCablebot.shape:setCompromised( false )
				return true
			end
		elseif damage > 0 then
			if projectileUuid == projectile_flame then
				PotatoLauncherSplash( self.world, hitPos )
				return true
			end
			local ud = trigger:getUserData()
			local shapeWithCablebot = shapesWithCablebot and shapesWithCablebot[ud.shapeId] or nil
			if shapeWithCablebot and sm.exists( shapeWithCablebot.shape ) and shapeWithCablebot.shape:getCompromised() then
				sm.effect.playEffect( "CableBot - Death", hitPos, nil, nil, nil, { ExplosionIndex = math.random( 1, 3 ), Color = sm.color.new( DefaultColorString ) } )
				if SurvivalGame then
					local loot = SelectLoot( "lootsource_cablebot" )
					SpawnLoot( shapeWithCablebot.shape, loot )
				end
				shapeWithCablebot.shape:setCompromised( false )
				return true
			end
		end
	end
	return false
end

--[[ Client ]]
function CablebotManager.client_onCreate( self )
	g_cablebotManagerClient = self
	self.cl = {}
	self.cl.shapesWithCablebot = {}
end

--[[ Manager ]]
function CablebotManager.Cl_OnWorldFixedUpdate( world )
	if g_cablebotManagerClient then
		g_cablebotManagerClient:cl_onWorldFixedUpdate( world )
	end
end

function CablebotManager.cl_onWorldFixedUpdate( self, world )
	local shapesWithCablebot = self.cl.shapesWithCablebot[world.id] == nil and {} or self.cl.shapesWithCablebot[world.id]

	-- Update cablebots compromising shapes
	local compromisedShapes = sm.compromised.getCompromisedShapes()
	local updatedShapesWithCablebot = {}
	for _, shape in ipairs( compromisedShapes ) do
		if sm.exists( shape ) and shape:getCompromised() then
			local shapeWithCablebot = shapesWithCablebot[shape.id]
			if shapeWithCablebot then
				updatedShapesWithCablebot[shape.id] = shapeWithCablebot
				shapesWithCablebot[shape.id] = nil
			else
				-- Setup new cablebot
				shapeWithCablebot = { shape = shape, effect = createCablebotEffectWithTransform( shape ) }
				sm.effect.playEffect( "Cablebot - Attached_start", shape.worldPosition, nil, nil, nil, { material = shape:getMaterialId() } )

				updatedShapesWithCablebot[shape.id] = shapeWithCablebot
				if shapeWithCablebot.effect then
					shapeWithCablebot.effect:setParameter( "material", shape:getMaterialId() )
					shapeWithCablebot.effect:start()
				end
			end
		end
	end

	-- Cleanup removed cablebots
	for _, shapeWithCablebot in pairs( shapesWithCablebot ) do
		if shapeWithCablebot.effect then
			if sm.exists( shapeWithCablebot.effect ) then
				shapeWithCablebot.effect:stop()
				shapeWithCablebot.effect:destroy()
			end
		end
	end
	self.cl.shapesWithCablebot[world.id] = updatedShapesWithCablebot
end