dofile( "$SURVIVAL_DATA/Scripts/game/survival_collections.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/survival_constants.lua" )
dofile( "$GAME_DATA/Scripts/game/managers/WeatherManager.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/survival_sob.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/survival_sob.lua" )

AttachedFireManager = class()

local TimeScale = 1.0 -- For testing ( Default: 1.0 )
local InvTimeScale = TimeScale > 0 and 1 / TimeScale or 1
local BurnDestroyTickTimeMin = 12.5 * 40 * InvTimeScale
local BurnDestroyTickTimeMax = 18.175 * 40 * InvTimeScale
local WeatherExtinguishTicks = 1.5 * 40 * InvTimeScale
local ExtinguishDeviation = 0.4
local RainExtinguishBudget = 20
local NoDestruction = false
local RainDistance = 20.0
if NoDestruction then
	BurnDestroyTickTimeMin = math.huge
	BurnDestroyTickTimeMax = math.huge
end

local CreateBudget = 100 -- How many new area triggers are allowed to be setup per tick
local DestructionBudget = 30 -- How many shapes are allowed to be destroyed per tick
local DestructionTickDelay = 2 -- Interval for when destructions are allowed to occur

local DisableEffects = false
local InitialSmokeChance = 0.1875
local SmallFireSize = 1
local MediumFireSize = 4
local ShapeFireExtent = 0.125 -- AreaTrigger extents around a burning shape

local ExplosionFlameRadius = 4.0
local BaseQuenchRadius = 1.5

function AttachedFireManager.server_onCreate( self )
	g_attachedFireManager = self
	self.sv = {}
	self.sv.shapeFires = {}
	self.sv.nextDestructionTick = {}
end

function AttachedFireManager.server_onRefresh( self ) end

--[[ Manager ]]
function AttachedFireManager.Sv_OnWorldFixedUpdate( world )
	if g_attachedFireManager then
		g_attachedFireManager:sv_onWorldFixedUpdate( world )
	end
end

function AttachedFireManager.sv_onWorldFixedUpdate( self, world )
	local currentTick = sm.game.getCurrentTick()
	if self.sv.nextDestructionTick[world.id] == nil then
		self.sv.nextDestructionTick[world.id] = currentTick
	end
	local allowDestruction = currentTick >= self.sv.nextDestructionTick[world.id]
	if allowDestruction then
		self.sv.nextDestructionTick[world.id] = currentTick + DestructionTickDelay
	end
	local createBudget = CreateBudget
	local destructionBudget = DestructionBudget
	local shapeFires = self.sv.shapeFires[world.id] == nil and {} or self.sv.shapeFires[world.id]
	local currentCheckCount = 0
	local currentTick = sm.game.getCurrentTick()
	local weatherExtinguishFires = false
	local rainDirection = sm.vec3.new( 0, 0, -1 )
	local rainSide = sm.vec3.new( 0, 1, 0 )
	if world.id == 1 then --overworld
		weatherExtinguishFires = WeatherManager.Sv_GetExtinguishFires()
		rainDirection = WeatherManager.Sv_GetRainDirection()
		rainSide = sm.vec3.new( -rainDirection.x, -rainDirection.y, 0 ):safeNormalize( rainSide )
	end

	local casts = {}
	local shapes = {}
	-- Update fires
	local burningShapes = sm.fire.getBurningShapes()
	local updatedShapeFires = {}
	for _, shape in ipairs( burningShapes ) do
		if sm.exists( shape ) and shape:getBurning() then
			local shapeFire = shapeFires[shape.id]
			if shapeFire then
				-- Shape still exists and is still burning
				local shouldDestroy = shapeFire.destroyTick and currentTick >= shapeFire.destroyTick
				if weatherExtinguishFires and not shouldDestroy and currentCheckCount < RainExtinguishBudget and shapeFire.extinguishCheckTick <= currentTick and not shapeFire.shouldExtinguish then
					local halfExtents = shapeFire.shape.worldRotation * ( shapeFire.shape:getBoundingBox() / 2 )
					local raycastEndTop = sm.vec3.new( shapeFire.shape.worldPosition.x, shapeFire.shape.worldPosition.y, shapeFire.shape.worldPosition.z + halfExtents.z )
					local modifiedExtents = sm.vec3.new( halfExtents.x, halfExtents.y, 0 )
					modifiedExtents = rainSide:dot( modifiedExtents ) > 0 and modifiedExtents or modifiedExtents * -1
					local raycastEndSide = shapeFire.shape.worldPosition + modifiedExtents
					local raycastStart = shapeFire.shape.worldPosition + -rainDirection * RainDistance
					casts[#casts+1] = {
						type = "sphere",
						startPoint = raycastStart,
						endPoint = raycastEndTop,
						radius = 0.03,
						ignoreObject = shapeFire.shape
					}
					casts[#casts+1] = {
						type = "sphere",
						startPoint = raycastStart,
						endPoint = raycastEndSide,
						radius = 0.03,
						ignoreObject = shapeFire.shape
					}
					shapes[#shapes+1] = shapeFire
					currentCheckCount = currentCheckCount + 1
				end
				if shouldDestroy and destructionBudget > 0 and allowDestruction then
					-- Destroy burning shape
					destructionBudget = destructionBudget - 1
					if sm.exists( shapeFire.shape ) then
						if isAnyOf( shapeFire.shape.uuid, { obj_harvest_wood, obj_harvest_wood2 } ) then
							if SurvivalGame then
								local lootList = {}
								lootList[1] = { uuid = obj_resource_ember, quantity = 1 }
								SpawnLoot( shapeFire.shape, lootList, shapeFire.shape.worldPosition )
							end
							shapeFire.shape:destroyShape( 0 )
							sm.effect.playEffect( "Attached Fire - Destruction", shapeFire.shape.worldPosition, shapeFire.shape.velocity, shapeFire.shape.worldRotation, nil, { Material = shapeFire.shape.materialId } )
						elseif sm.item.isHarvestablePart( shapeFire.shape.uuid ) then
							if shapeFire.shape.interactable then
								local params = { damage = 100, type = "fire" }
								sm.event.sendToInteractable( shapeFire.shape.interactable, "sv_e_receiveDamage", params )
							end
						elseif shapeFire.shape.uuid == obj_resource_corn then
							shapeFire.shape:destroyShape( 0 )
							sm.effect.playEffect( "Attached Fire - Popcorn", shapeFire.shape.worldPosition )
						elseif isAnyOf( shapeFire.shape.uuid, g_capsules ) then
							-- A capsule burned out, so open it
							sm.event.sendToInteractable( shapeFire.shape.interactable, "sv_e_open" )
							shapeFire.spreadTick = nil
							shapeFire.destroyTick = nil
						elseif isAnyOf( shapeFire.shape.uuid, g_explosives ) then
							-- Ignited an explosive
							sm.event.sendToInteractable( shapeFire.shape.interactable, "server_startCountdown" )
							shapeFire.spreadTick = nil
							shapeFire.destroyTick = nil
						elseif shapeFire.shape.destructable and sm.item.isFlammable( shapeFire.shape.uuid ) then
							-- A destructable shape burned out, so destroy it
							shapeFire.shape:destroyShape( 0 )
							sm.effect.playEffect( "Attached Fire - Destruction", shapeFire.shape.worldPosition, shapeFire.shape.velocity, shapeFire.shape.worldRotation, nil, { Material = shapeFire.shape.materialId } )
						else
							-- No reaction, put out the fire
							shapeFire.shape:setBurning( false )
							local bounds = shapeFire.shape:getBoundingBox()
							local size = math.max( round( bounds.x * 4 ), round( bounds.y * 4 ), round( bounds.z * 4 ) )
							if size > MediumFireSize then
								sm.effect.playEffect( "Attached Fire - putout 6x6x6", shapeFire.shape.worldPosition )
							elseif size > SmallFireSize then
								sm.effect.playEffect( "Attached Fire - putout 3x3x3", shapeFire.shape.worldPosition )
							else
								sm.effect.playEffect( "Attached Fire - putout 1x1x1", shapeFire.shape.worldPosition )
							end
						end
					end
				elseif shapeFire.shouldExtinguish then
					shapeFire.shape:setBurning( false )
					local bounds = shapeFire.shape:getBoundingBox()
					local size = math.max( round( bounds.x * 4 ), round( bounds.y * 4 ), round( bounds.z * 4 ) )
					if size > MediumFireSize then
						sm.effect.playEffect( "Attached Fire - putout 6x6x6", shapeFire.shape.worldPosition )
					elseif size > SmallFireSize then
						sm.effect.playEffect( "Attached Fire - putout 3x3x3", shapeFire.shape.worldPosition )
					else
						sm.effect.playEffect( "Attached Fire - putout 1x1x1", shapeFire.shape.worldPosition )
					end
				else
					-- Continue burning
					updatedShapeFires[shape.id] = shapeFire
					shapeFires[shape.id] = nil
				end
			else
				-- Setup new fire
				if createBudget > 0 then
					createBudget = createBudget - 1
					local destroyTick = currentTick + math.random( BurnDestroyTickTimeMin, BurnDestroyTickTimeMax )
					local fireExtents = sm.vec3.new( ShapeFireExtent, ShapeFireExtent, ShapeFireExtent )
					local halfSize = shape:getBoundingBox() * 0.5 + fireExtents
					local filter = sm.areaTrigger.filter.character
					local areaTrigger = sm.areaTrigger.createAttachedBox( shape, halfSize, nil, nil, filter, { shapeId = shape.id } )
					areaTrigger:bindOnEnter( "trigger_onEnterFire", self )
					areaTrigger:bindOnStay( "trigger_onStayFire", self )
					areaTrigger:bindOnProjectile( "trigger_onProjectile", self )
					updatedShapeFires[shape.id] = {
						shape = shape,
						areaTrigger = areaTrigger,
						destroyTick = destroyTick,
						extinguishCheckTick = currentTick + math.floor( math.random( ( 1.0 - ExtinguishDeviation ) * WeatherExtinguishTicks, ( 1.0 + ExtinguishDeviation ) * WeatherExtinguishTicks ) ),
						isTopInRain = false,
						isSideInRain = false,
						shouldExtinguish = false
					}
				end
			end
		else
			-- There's no burning shape. Cleanup areaTrigger.
			local shapeFire = shapeFires[shape.id]
			if shapeFire then
				if sm.exists( shapeFire.areaTrigger ) then
					sm.areaTrigger.destroy( shapeFire.areaTrigger )
				end
			end
		end
	end

	if #casts > 0 then
		local retTable = sm.physics.multicast( casts )
		local hitIndexes = {}
		for i = 1, #casts do
			local isSide = i % 2 == 0








			local success = retTable[i][1]
			local shapeIndex = math.ceil( i / 2 )
			local shapeIsInRain = isAnyOf( shapeIndex, hitIndexes )
			if not success and not shapeIsInRain then
				hitIndexes[#hitIndexes+1] = shapeIndex
				if shapes[shapeIndex].isSideInRain or shapes[shapeIndex].isTopInRain then
					shapes[shapeIndex].shouldExtinguish = true
				else
					if isSide then
						shapes[shapeIndex].isSideInRain = true
					else
						shapes[shapeIndex].isTopInRain = true
					end
					shapes[shapeIndex].extinguishCheckTick = currentTick + math.floor( math.random( ( 1.0 - ExtinguishDeviation ) * WeatherExtinguishTicks, ( 1.0 + ExtinguishDeviation ) * WeatherExtinguishTicks ) )
				end
			else
				shapes[shapeIndex].extinguishCheckTick = currentTick + math.floor( math.random( ( 1.0 - ExtinguishDeviation ) * WeatherExtinguishTicks, ( 1.0 + ExtinguishDeviation ) * WeatherExtinguishTicks ) )
				if not shapeIsInRain then
					if isSide then
						shapes[shapeIndex].isSideInRain = false
					else
						shapes[shapeIndex].isTopInRain = false
					end
				end
			end
		end
	end

	-- Cleanup removed shapeFires
	for _, shapeFire in pairs( shapeFires ) do
		if sm.exists( shapeFire.areaTrigger ) then
			sm.areaTrigger.destroy( shapeFire.areaTrigger )
		end
	end
	shapeFires = updatedShapeFires
	self.sv.shapeFires[world.id] = updatedShapeFires
end

function AttachedFireManager.trigger_onEnterFire( self, trigger, results )
	if sm.exists( trigger ) then
		for _, result in ipairs( results ) do
			if sm.exists( result ) then
				if type( result ) == "Character" then
					if result:isPlayer() then
						sm.event.sendToPlayer( result:getPlayer(), "sv_e_onEnterFire" )
					end
				end
			end
		end
	end
end

function AttachedFireManager.trigger_onStayFire( self, trigger, results )
	if sm.exists( trigger ) then
		for _, result in ipairs( results ) do
			if sm.exists( result ) then
				if type( result ) == "Character" then
					if result:isPlayer() then
						sm.event.sendToPlayer( result:getPlayer(), "sv_e_onStayFire" )
					end
				end
			end
		end
	end
end

function AttachedFireManager.trigger_onProjectile( self, trigger, hitPos, hitTime, hitVelocity, _, attacker, damage, userData, hitNormal, projectileUuid )
	local currentWorld = sm.world.getCurrentWorld()
	local shapeFires = self.sv.shapeFires[currentWorld.id]
	if sm.exists( trigger ) and ( projectileUuid == projectile_water or projectileUuid == projectile_foam ) then
		local ud = trigger:getUserData()
		local shapeFire = shapeFires and shapeFires[ud.shapeId] or nil
		if shapeFire and sm.exists( shapeFire.shape ) and shapeFire.shape:getBurning() then
			local bounds = shapeFire.shape:getBoundingBox()
			local size = math.max( round( bounds.x * 4 ), round( bounds.y * 4 ), round( bounds.z * 4 ) )
			if size > MediumFireSize then
				sm.effect.playEffect( "Attached Fire - putout 6x6x6", shapeFire.shape.worldPosition )
			elseif size > SmallFireSize then
				sm.effect.playEffect( "Attached Fire - putout 3x3x3", shapeFire.shape.worldPosition )
			else
				sm.effect.playEffect( "Attached Fire - putout 1x1x1", shapeFire.shape.worldPosition )
			end
			shapeFire.shape:setBurning( false )
		end
	elseif ( projectileUuid == projectile_oil ) and sm.exists( trigger ) then
		sm.physics.explode( hitPos, 4, 1.0, 3.0, 12.5, "PropaneTank - ExplosionSmall", nil, nil, nil, 10 )
		return true
	elseif ( projectileUuid == projectile_chemical ) and sm.exists( trigger ) then
		sm.scriptableObject.createScriptableObject( sob_pesticide_cloud, { position = hitPos + sm.vec3.new( 0, 0, PESTICIDE_SIZE.z * 0.25 ), rotation = sm.quat.identity(), sizeModifier = 0.25, pesticideLifeDuration = 6.0 }, trigger.world )
		return true
	end
	return false
end

function AttachedFireManager.Sv_OnExplosion( center, destructionLevel, world )
	if g_attachedFireManager then
		g_attachedFireManager:sv_onExplosion( center, destructionLevel, world )
	end
end

function AttachedFireManager.sv_onExplosion( self, center, destructionLevel, world )
	sm.fire.igniteSphere( center, ExplosionFlameRadius, false, world )
end

function AttachedFireManager.Sv_Quench( quenchPosition, quenchRadius )
	if g_attachedFireManager then
		g_attachedFireManager:sv_quench( quenchPosition, quenchRadius )
	end
end

function AttachedFireManager.sv_quench( self, quenchPosition, quenchRadius )
	local radius = quenchRadius == nil and BaseQuenchRadius or quenchRadius
	local shapeCollisions = sm.physics.getShapeContactsInSphere( quenchPosition, radius )
	for _, shapeCollision in ipairs( shapeCollisions ) do
		if sm.exists( shapeCollision.shape ) and shapeCollision.shape:getBurning() then
			local bounds = shapeCollision.shape:getBoundingBox()
			local size = math.max( round( bounds.x * 4 ), round( bounds.y * 4 ), round( bounds.z * 4 ) )
			if size > MediumFireSize then
				sm.effect.playEffect( "Attached Fire - putout 6x6x6", shapeCollision.shape.worldPosition )
			elseif size > SmallFireSize then
				sm.effect.playEffect( "Attached Fire - putout 3x3x3", shapeCollision.shape.worldPosition )
			else
				sm.effect.playEffect( "Attached Fire - putout 1x1x1", shapeCollision.shape.worldPosition )
			end
			shapeCollision.shape:setBurning( false )
		end
	end
end

--[[ Client ]]
function AttachedFireManager.client_onCreate( self )
	g_attachedFireManagerClient = self
	self.cl = {}
	self.cl.shapeFires = {}
	self.cl.numEffects = 0
	self.cl.smokingFires = 0
	self.cl.detachedFireEffects = {}
end

--[[ Manager ]]
function AttachedFireManager.Cl_OnWorldFixedUpdate( world )
	if g_attachedFireManagerClient then
		g_attachedFireManagerClient:cl_onWorldFixedUpdate( world )
	end
end

function AttachedFireManager.cl_onWorldFixedUpdate( self, world )
	local shapeFires = self.cl.shapeFires[world.id] == nil and {} or self.cl.shapeFires[world.id]
	local detachedFireEffects = self.cl.detachedFireEffects[world.id] or {}

	if DisableEffects then
		if next( shapeFires ) then
			for shapeId, shapeFire in pairs( shapeFires ) do
				if shapeFire.effect then
					self.cl.numEffects = self.cl.numEffects - 1
					if sm.exists( shapeFire.effect ) then
						shapeFire.effect:destroy()
					end
				end
				self.cl.smokingFires = shapeFire.isSmoking and math.max( self.cl.smokingFires - 1, 0 ) or self.cl.smokingFires
				shapeFires[shapeId] = nil
			end
		end
		self.cl.shapeFires[world.id] = shapeFires
		return
	end

	-- Update fires
	local burningShapes = sm.fire.getBurningShapes()
	local updatedShapeFires = {}
	for _, shape in ipairs( burningShapes ) do
		if sm.exists( shape ) and shape:getBurning() then
			local shapeFire = shapeFires[shape.id]
			if shapeFire then
				-- Continue burning
				updatedShapeFires[shape.id] = shapeFire
				shapeFires[shape.id] = nil
			else
				-- Setup new fire
				if self.cl.numEffects < FIRE_EFFECT_BUDGET then
					local currentSmokeChance = InitialSmokeChance - InitialSmokeChance * ( self.cl.smokingFires / FIRE_EFFECT_BUDGET )
					local isSmoking = math.random() < currentSmokeChance
					local bounds = shape:getBoundingBox()
					local size = math.max( round( bounds.x * 4 ), round( bounds.y * 4 ), round( bounds.z * 4 ) )
					shapeFire = { shape = shape, isSmoking = math.random() < currentSmokeChance }
					if size > MediumFireSize then
						if isSmoking then
							shapeFire.effect = sm.effect.createEffect( "Attached Fire - 6x6x6 Extra", shapeFire.shape )
						else
							shapeFire.effect = sm.effect.createEffect( "Attached Fire - 6x6x6", shapeFire.shape )
						end
					elseif size > SmallFireSize then
						if isSmoking then
							shapeFire.effect = sm.effect.createEffect( "Attached Fire - 3x3x3 Extra", shapeFire.shape )
						else
							shapeFire.effect = sm.effect.createEffect( "Attached Fire - 3x3x3", shapeFire.shape )
						end
					else
						if isSmoking then
							shapeFire.effect = sm.effect.createEffect( "Attached Fire - 1x1x1 Extra", shapeFire.shape )
						else
							shapeFire.effect = sm.effect.createEffect( "Attached Fire - 1x1x1", shapeFire.shape )
						end
					end
					updatedShapeFires[shape.id] = shapeFire

					if shapeFire.effect then
						self.cl.numEffects = self.cl.numEffects + 1
						self.cl.smokingFires = shapeFire.isSmoking and math.min( self.cl.smokingFires + 1, FIRE_EFFECT_BUDGET ) or self.cl.smokingFires
						shapeFire.effect:start()
					end
				end
			end
		end
	end

	-- Cleanup removed shapeFires
	for _, shapeFire in pairs( shapeFires ) do
		if shapeFire.effect then
			self.cl.numEffects = self.cl.numEffects - 1
			self.cl.smokingFires = shapeFire.isSmoking and math.max( self.cl.smokingFires - 1, 0 ) or self.cl.smokingFires
			if sm.exists( shapeFire.effect ) then
				shapeFire.effect:detach()
				shapeFire.effect:stopBreakSustain()
				detachedFireEffects[shapeFire.effect.id] = shapeFire.effect
			end
		end
	end
	self.cl.shapeFires[world.id] = updatedShapeFires

	-- Cleanup detached fire effects
	local updatedDetachedFireEffects = {}
	for _, detachedFireEffect in pairs( detachedFireEffects ) do
		local isActive = sm.exists( detachedFireEffect ) and not detachedFireEffect:isDone()
		if isActive then
			updatedDetachedFireEffects[detachedFireEffect.id] = detachedFireEffect
		elseif sm.exists( detachedFireEffect ) then
			detachedFireEffect:destroy()
		end
	end
	self.cl.detachedFireEffects[world.id] = updatedDetachedFireEffects
end