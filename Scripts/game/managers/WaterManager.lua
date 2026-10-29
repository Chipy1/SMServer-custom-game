dofile( "$SURVIVAL_DATA/Scripts/game/survival_constants.lua" )
dofile( "$SURVIVAL_DATA/Scripts/util.lua" )

---@class WaterManager
WaterManager = class( nil )

function WaterManager.sv_onCreate( self )
	self.cells = {}
	self.triggeredCharactersServer = {}
end

function WaterManager.cl_onCreate( self )
	if not sm.isHost then
		self.cells = {}
	end
	self.triggeredCharactersClient = {}
	self.triggeredBodiesClient = {}
end

-- ################################ World cell callbacks ################################

-- Loaded/Reloaded

function WaterManager.onCellLoaded( self, x, y )
	--print("--- loading water objs on cell " .. x .. ":" .. y .. " ---")
	local cellKey = CellKey( x, y )
	local waterNodes = sm.cell.getNodesByTag( x, y, "WATER" )
	local chemicalNodes = sm.cell.getNodesByTag( x, y, "CHEMICALS" )
	local oilNodes = sm.cell.getNodesByTag( x, y, "OIL" )
	local lavaNodes = sm.cell.getNodesByTag( x, y, "LAVA" )

	if (#waterNodes > 0 or #chemicalNodes > 0 or #oilNodes > 0 or #lavaNodes > 0) and self.cells[cellKey] == nil then
		self.cells[cellKey] = {}
	end

	local idx = 1
	if #waterNodes > 0 then
		for _, node in ipairs( waterNodes ) do
			local areaTrigger = self.cells[cellKey][idx]
			if not areaTrigger then
				areaTrigger = sm.areaTrigger.createBoxWater( node.scale * 0.5, node.position, node.rotation, sm.areaTrigger.filter.character + sm.areaTrigger.filter.dynamicBody + sm.areaTrigger.filter.staticBody + sm.areaTrigger.filter.areaTrigger, { water = true } )
				areaTrigger:setWaterType( sm.areaTrigger.liquidType.water )
			end
			if sm.isServerMode() then
				areaTrigger:bindOnProjectile( "trigger_onProjectile", self )
				areaTrigger:bindOnEnter( "sv_t_onEnterWater", self )
				areaTrigger:bindOnExit( "sv_t_onExitWater", self )
				areaTrigger:bindOnStay( "sv_t_onStayWater", self )
			else
				areaTrigger:bindOnEnter( "trigger_onEnterWater", self )
				areaTrigger:bindOnExit( "trigger_onExitWater", self )
				areaTrigger:bindOnStay( "trigger_onStayWater", self )
			end
			self.cells[cellKey][idx] = areaTrigger
			idx = idx + 1
		end
	end

	if #chemicalNodes > 0 then
		for _, node in ipairs( chemicalNodes ) do
			local areaTrigger = self.cells[cellKey][idx]
			if not areaTrigger then
				areaTrigger = sm.areaTrigger.createBoxWater( node.scale * 0.5, node.position, node.rotation, sm.areaTrigger.filter.character + sm.areaTrigger.filter.dynamicBody + sm.areaTrigger.filter.staticBody + sm.areaTrigger.filter.areaTrigger, { chemical = true } )
				areaTrigger:setWaterType( sm.areaTrigger.liquidType.chemical )
			end
			if sm.isServerMode() then
				areaTrigger:bindOnProjectile( "trigger_onProjectile", self )
				areaTrigger:bindOnEnter( "sv_t_onEnterWater", self )
				areaTrigger:bindOnExit( "sv_t_onExitWater", self )
				areaTrigger:bindOnStay( "sv_t_onStayWater", self )
			else
				areaTrigger:bindOnEnter( "trigger_onEnterWater", self )
				areaTrigger:bindOnExit( "trigger_onExitWater", self )
				areaTrigger:bindOnStay( "trigger_onStayWater", self )
			end
			self.cells[cellKey][idx] = areaTrigger
			idx = idx + 1
		end
	end

	if #oilNodes > 0 then
		for _, node in ipairs( oilNodes ) do
			local areaTrigger = self.cells[cellKey][idx]
			if not areaTrigger then
				areaTrigger = sm.areaTrigger.createBoxWater( node.scale * 0.5, node.position, node.rotation, sm.areaTrigger.filter.character + sm.areaTrigger.filter.dynamicBody + sm.areaTrigger.filter.staticBody + sm.areaTrigger.filter.areaTrigger, { oil = true } )
				areaTrigger:setWaterType( sm.areaTrigger.liquidType.oil )
			end
			if sm.isServerMode() then
				areaTrigger:bindOnProjectile( "trigger_onProjectile", self )
				areaTrigger:bindOnEnter( "sv_t_onEnterWater", self )
				areaTrigger:bindOnExit( "sv_t_onExitWater", self )
				areaTrigger:bindOnStay( "sv_t_onStayWater", self )
			else
				areaTrigger:bindOnEnter( "trigger_onEnterWater", self )
				areaTrigger:bindOnExit( "trigger_onExitWater", self )
				areaTrigger:bindOnStay( "trigger_onStayWater", self )
			end
			self.cells[cellKey][idx] = areaTrigger
			idx = idx + 1
		end
	end

	if #lavaNodes > 0 then
		for _, node in ipairs( lavaNodes ) do
			local areaTrigger = self.cells[cellKey][idx]
			if not areaTrigger then
				areaTrigger = sm.areaTrigger.createBoxWater( node.scale * 0.5, node.position, node.rotation, sm.areaTrigger.filter.character + sm.areaTrigger.filter.dynamicBody + sm.areaTrigger.filter.staticBody + sm.areaTrigger.filter.areaTrigger, { lava = true } )
				areaTrigger:setIncludeShapesInContent( true )
				areaTrigger:setWaterType( sm.areaTrigger.liquidType.lava )
			end
			if sm.isServerMode() then
				areaTrigger:bindOnProjectile( "trigger_onProjectile", self )
				areaTrigger:bindOnEnter( "sv_t_onEnterWater", self )
				areaTrigger:bindOnExit( "sv_t_onExitWater", self )
				areaTrigger:bindOnStay( "sv_t_onStayWater", self )
			else
				areaTrigger:bindOnEnter( "trigger_onEnterWater", self )
				areaTrigger:bindOnExit( "trigger_onExitWater", self )
				areaTrigger:bindOnStay( "trigger_onStayWater", self )
			end
			self.cells[cellKey][idx] = areaTrigger
			idx = idx + 1
		end
	end
end

function WaterManager.sv_onCellLoaded( self, x, y )
	self:onCellLoaded( x, y )
end

function WaterManager.sv_onCellReloaded( self, x, y )
	self:onCellLoaded( x, y )
end

function WaterManager.cl_onCellLoaded( self, x, y )
	self:onCellLoaded( x, y )
end


-- Unloaded

function WaterManager.onCellUnloaded( self, x, y )
	--print("--- unloading water objs on cell " .. x .. ":" .. y .. " ---")
	local cellKey = CellKey( x, y )

	if self.cells[cellKey] then
		for _, trigger in ipairs( self.cells[cellKey] ) do
			sm.areaTrigger.destroy( trigger )
		end
		self.cells[cellKey] = nil
	end
end

function WaterManager.sv_onCellUnloaded( self, x, y )
	--self:onCellUnloaded( x, y )
end

function WaterManager.cl_onCellUnloaded( self, x, y )
	self:onCellUnloaded( x, y )
end


-- ################################ Update callbacks ################################

function WaterManager.onFixedUpdate( self )
	-- Reset tracking of triggered objects during previous tick
	if sm.isServerMode() then
		self.triggeredCharactersServer = {}
	else
		self.triggeredCharactersClient = {}
	end
end

function WaterManager.sv_onFixedUpdate( self )
	self:onFixedUpdate()
end

function WaterManager.cl_onFixedUpdate( self )
	self:onFixedUpdate()
end

-- ################################ AreaTrigger callbacks ################################

local function PlaySplashEffect( pos, velocity, mass, data )

	local energy = 0.5 * velocity:length() * velocity:length() * mass

	--print( "Velocity: ", velocity:length() )
	--print( "Mass: ", mass )
	--print( "Energy: ", energy)

	local params = {
		["Size"] = min( 1.0, mass / 76800.0 ),
		["Velocity_max_50"] = velocity:length(),
		["Phys_energy"] = energy / 1000.0
	}
	local prefix = "Water - "
	if data.chemical then
		prefix = "Chemical - "
	elseif data.oil then
		prefix = "Oil - "
	elseif data.lava then
		prefix = "Lava - "
	end
	if energy > 8000 then
		sm.effect.playEffect( prefix .. "HitWaterMassive", pos, sm.vec3.zero(), sm.quat.identity(), sm.vec3.one(), params )
	elseif energy > 4000 then
		sm.effect.playEffect( prefix .. "HitWaterBig", pos, sm.vec3.zero(), sm.quat.identity(), sm.vec3.one(), params )
	elseif energy > 750 then
		sm.effect.playEffect( prefix .. "HitWaterSmall", pos, sm.vec3.zero(), sm.quat.identity(), sm.vec3.one(), params )
	elseif energy > 1 then
		sm.effect.playEffect( prefix .. "HitWaterTiny", pos, sm.vec3.zero(), sm.quat.identity(), sm.vec3.one(), params )
	end
		
end

local function CalulateForce( waterHeightPos, worldPosition, worldRotation, velocity, halfExtent, mass )
	-- Setup all the corners of the shape's bounding box
	local volume = (halfExtent.x * 2.0 * halfExtent.y * 2.0 * halfExtent.z * 2.0)

	local corners = {}
	corners[1] = worldPosition + worldRotation * sm.vec3.new( halfExtent.x, halfExtent.y, halfExtent.z )
	corners[2] = worldPosition + worldRotation * sm.vec3.new( halfExtent.x, halfExtent.y, -halfExtent.z )
	corners[3] = worldPosition + worldRotation * sm.vec3.new( halfExtent.x, -halfExtent.y, halfExtent.z )
	corners[4] = worldPosition + worldRotation * sm.vec3.new( halfExtent.x, -halfExtent.y, -halfExtent.z )
	corners[5] = worldPosition + worldRotation * sm.vec3.new( -halfExtent.x, halfExtent.y, halfExtent.z )
	corners[6] = worldPosition + worldRotation * sm.vec3.new( -halfExtent.x, halfExtent.y, -halfExtent.z )
	corners[7] = worldPosition + worldRotation * sm.vec3.new( -halfExtent.x, -halfExtent.y, halfExtent.z )
	corners[8] = worldPosition + worldRotation * sm.vec3.new( -halfExtent.x, -halfExtent.y, -halfExtent.z )
	-- Sort so the lowest corners go first
	table.sort( corners, function( c1, c2 ) return c1.z < c2.z end )

	-- Check which of the lowest corners are under water and calculate their total depth
	local submergedPoints = {}
	local totalDepth = 0
	local avgDepth = 0
	for _, corner in pairs( { corners[1], corners[2], corners[3], corners[4] } ) do
		if corner.z < waterHeightPos then
			totalDepth = totalDepth + (waterHeightPos - corner.z)
			submergedPoints[#submergedPoints + 1] = corner
		end
	end
	avgDepth = totalDepth * 0.25

	-- Approximate how much of the shape is submerged to calculate the displaced volume
	local bottomArea = 0.5 * ((corners[1] - corners[2]):cross( corners[1] - corners[3] ):length() + (corners[4] - corners[2]):cross( corners[4] - corners[3] ):length())
	local displacedVolume = math.min( (bottomArea * avgDepth), volume )

	-- Buoyancy force formula
	local fluidDensity = 500 -- density level 4
	local buoyancyForce = fluidDensity * displacedVolume * GRAVITY

	-- Apply buoyancy force to the shape's body using the shape's CoM as an offset
	local force = sm.vec3.new( 0, 0, buoyancyForce )
	local result = force * 0.025;

	-- Diminishing force in water, acts as water resistance
	if velocity:length() >= FLT_EPSILON then
		local direction = velocity:normalize()
		local magnitude = velocity:length()

		local antiVelocity = -direction * (magnitude * 0.15)
		if velocity.z > 0 then
			antiVelocity = -direction * (magnitude * 0.15) --Ascending
		end
		local antiForceVector = (antiVelocity / 0.025) * mass

		local horizontalDiminishScale = 0.1
		antiForceVector.x = antiForceVector.x * horizontalDiminishScale
		antiForceVector.y = antiForceVector.y * horizontalDiminishScale
		result = result + (antiForceVector * 0.025)
	end

	return result
end

function WaterManager.cl_updateCharacterInWater( self, trigger, character )
	local waterHeightPos = trigger:getWorldMax().z
	local characterDiveOffset = 0.7 + ( character:isCrouching() and 0.4 or 0.0 )
	if character.clientPublicData then
		-- Scaled movement slowdown when walking through water
		if not character:isSwimming() then
			local depthScale = 1 - math.max( math.min( ( ( character.worldPosition.z + characterDiveOffset ) - waterHeightPos ) / ( characterDiveOffset * 2 ), 1.0 ), 0.0 )
			character.clientPublicData.waterMovementSpeedFraction = math.max( math.min( 1 - ( depthScale + 0.1 ), 1.0 ), 0.3 )
		else
			character.clientPublicData.waterMovementSpeedFraction = 1.0
		end
	end
	if character:isTumbling() then
		local worldPosition = character:getTumblingWorldPosition()
		local worldRotation = character:getTumblingWorldRotation()
		local velocity = character:getTumblingLinearVelocity()
		local halfExtent = character:getTumblingExtent() * 0.5
		local mass = character:getMass()
		local force = CalulateForce( waterHeightPos, worldPosition, worldRotation, velocity, halfExtent, mass )
		character:applyTumblingImpulse( force )
	end
end

----------------------------------------------------------------------------------------------------

function WaterManager.trigger_onEnterWater( self, trigger, results )
	local ud = trigger:getUserData()
	for _,object in ipairs( results ) do
		if sm.exists( object ) then
			if type( object ) == "Character" then
				if self.triggeredCharactersClient[object.id] == nil then
					self.triggeredCharactersClient[object.id] = true
					local triggerMax = trigger:getWorldMax()
					local characterPos = object:getWorldPosition()
					local splashPosition = sm.vec3.new( characterPos.x, characterPos.y, triggerMax.z )
					self:cl_updateCharacterInWater( trigger, object )
					if not object:isSwimming() then
						PlaySplashEffect( splashPosition, object:getVelocity(), object:getMass(), ud )
					end
				end
			elseif type( object ) == "Body" then
				if self.triggeredBodiesClient[object.id] == nil then
					self.triggeredBodiesClient[object.id] = true
					local triggerMax = trigger:getWorldMax()
					local centerPos = object:getCenterOfMassPosition()
					local splashPosition = sm.vec3.new( centerPos.x, centerPos.y, triggerMax.z )
					PlaySplashEffect( splashPosition, object:getVelocity(), object:getMass(), ud )
				end
			end
		end
	end
end

function WaterManager.sv_t_onEnterWater( self, trigger, results )
 	local ud = trigger:getUserData()
	for _,result in ipairs( results ) do
		if sm.exists( result ) then
			if type( result ) == "Character" then
				if self.triggeredCharactersServer[result.id] == nil then
					self.triggeredCharactersServer[result.id] = true
					if result:isPlayer() and ud.chemical then
						sm.event.sendToPlayer( result:getPlayer(), "sv_e_onEnterChemical" )
					elseif result:isPlayer() and ud.oil then
						sm.event.sendToPlayer( result:getPlayer(), "sv_e_onEnterOil" )
					elseif result:isPlayer() and ud.lava then
						sm.event.sendToPlayer( result:getPlayer(), "sv_e_onEnterFire" )
					end
				end
			end
		end
	end
end

function WaterManager.trigger_onExitWater( self, trigger, results )
	local ud = trigger:getUserData()
	assert( ud )
	for _, result in ipairs( results ) do
		if sm.exists( result ) then
			if type( result ) == "Character" then
				if result.clientPublicData then
					result.clientPublicData.waterMovementSpeedFraction = 1.0
				end
			end
		end
	end
end

function WaterManager.sv_t_onExitWater( self, trigger, results )
	local ud = trigger:getUserData()
	assert(ud)
	for _, result in ipairs( results ) do
		if sm.exists( result ) then
			if type( result ) == "Character" then
				if self.triggeredCharactersServer[result.id] == nil then
					self.triggeredCharactersServer[result.id] = true
					if result:isPlayer() and ud.chemical then
						sm.event.sendToPlayer( result:getPlayer(), "sv_e_onExitChemical" )
					elseif result:isPlayer() and ud.oil then
						sm.event.sendToPlayer( result:getPlayer(), "sv_e_onExitOil" )
					end
				end
			end
		end
	end
end

function WaterManager.trigger_onStayWater( self, trigger, results )
	local ud = trigger:getUserData()
	assert( ud )
	for _, result in ipairs( results ) do
		if sm.exists( result ) then
			if type( result ) == "Character" then
				-- Only trigger once per tick
				if self.triggeredCharactersClient[result.id] == nil then
					self.triggeredCharactersClient[result.id] = true
					self:cl_updateCharacterInWater( trigger, result )
				end
			end
		end
	end
end

function WaterManager.sv_t_onStayWater( self, trigger, results )
	local ud = trigger:getUserData()
	assert(ud)
	for _, result in ipairs( results ) do
		if sm.exists( result ) then
			if type( result ) == "Character" then
				if self.triggeredCharactersServer[result.id] == nil then
					self.triggeredCharactersServer[result.id] = true
					if result:isPlayer() and ud.chemical then
						sm.event.sendToPlayer( result:getPlayer(), "sv_e_onStayChemical" )
					elseif result:isPlayer() and ud.lava then
						sm.event.sendToPlayer( result:getPlayer(), "sv_e_onStayFire" )
					end
				end
			end
		end
	end
end

function WaterManager.trigger_onProjectile( self, trigger, hitPos, hitTime, hitVelocity, _, attacker, damage, userData, hitNormal, projectileUuid )
	if isAnyOf( projectileUuid, g_liquidProjectiles ) then
		return false
	end
	local max = trigger:getWorldMax()
	local distanceToTop = max.z - hitPos.z

	if distanceToTop <= 0.1 and hitTime > 0 then -- projectiles spawned inside water box will get incorrect hit possition from bullet. checking hitTime to avoid this
		local ud = trigger:getUserData()
		local hitEffect = "Projectile - HitWater"
		if ud then
			if ud.chemical then
				hitEffect = "Projectile - HitChemical"
			elseif ud.oil then
				hitEffect = "Projectile - HitOil"
			elseif ud.lava then
				hitEffect = "Projectile - HitLava"
			end
		end
		sm.effect.playEffect( hitEffect, hitPos )
		if (projectileUuid == projectile_cornade_explosive) then
			local at = hitVelocity:normalize()
			local toForward = sm.vec3.getRotation(sm.vec3.new(0,1,0),at)			

			local part = sm.shape.createPart( ITEMS.obj_interactive_cornade_explosive, hitPos + sm.vec3.new(0,0,1) * 0.25 , sm.quat.identity() * toForward , true )
			local interactable = part:getInteractable()
			interactable:setParams( { hitVelocity = hitVelocity,lifetime = hitTime } )

			return true
		end
	end
	return false
end
