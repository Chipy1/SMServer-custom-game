dofile( "$SURVIVAL_DATA/Scripts/game/survival_constants.lua" )

Missile = class()

local HitSphereRadius = 0.5
local HitCylinderLength = 1.0
local MaxAimSpeed = 2.0 -- radians/second
local MaxTravelSpeed = 40.0 -- m/s
local SelfdestructTickTime = 40 * 12.0
local TargetingDelayTickTime = 14
local SyncTickInterval = 5
local TimeStep = 0.025
local StopHomingDistance = 20
local StopHomingTickTime = 40 * 6.0
local CurveSpeed = 8.0 -- radians/second
local CurveTickTime = 34

-- Explosion
local ExplosionRadius = 2.0
local DestructionLevel = 9
local Damage = 50
local ExtraWoodBlockDestruction = 3

function Missile.server_onCreate( self )
	self.sv = {}

	self.sv.worldPosition = self.params.worldPosition
	self.sv.worldDirection = self.params.worldDirection
	local targetOffset = self.params.targetOffset or 0
	self.sv.targetOffset = sm.vec3.new( 0, targetOffset, 0 ):rotateZ( math.rad( math.random() * 359 + math.random() ) )
	self.sv.stoppedHoming = false -- Stop homing and fly straight when close to the target

	local curveChance = self.params.curveChance or 0.0
	if math.random() < curveChance then
		-- Add a random axis that the flight path will curve around
		local randomX = math.random() * 359 + math.random()
		local randomY = math.random() * 359 + math.random()
		self.sv.curveAxis = sm.vec3.new( 0, 0, 1 ):rotateX( math.rad( randomX ) ):rotateY( math.rad( randomY ) ):safeNormalize( orthogonal( self.sv.worldDirection ) )
	end

	self.sv.createTick = sm.game.getCurrentTick()
	self.sv.lastUpdateTick = self.sv.createTick
	self.sv.lastSyncTick = self.sv.createTick

	self.sv.targetCharacter = self.params.targetCharacter

	self.network:setClientData( { initialPosition = self.params.worldPosition, initialDirection = self.params.worldDirection, createTick = self.sv.createTick, targetCharacter = self.sv.targetCharacter, targetOffset = self.sv.targetOffset, curveAxis = self.sv.curveAxis }, 1 )
end

function Missile.server_onDestroy( self )
	if self.sv.trigger and sm.exists( self.sv.trigger ) then
		sm.areaTrigger.destroy( self.sv.trigger )
		self.sv.trigger = nil
	end
end

function Missile.server_onRefresh( self )
	self.scriptableObject:destroy()
end

function Missile.server_onFixedUpdate( self, deltaTime )
	local currentTick = sm.game.getCurrentTick()

	if self.sv.trigger == nil and currentTick >= self.sv.createTick + TargetingDelayTickTime then
		-- Create character collision trigger after homing is activated
		local filter = sm.areaTrigger.filter.character
		local misileRotation = sm.vec3.getRotation( sm.vec3.new( 0, 0, 1 ), self.sv.worldDirection )
		self.sv.trigger = sm.areaTrigger.createCylinder( HitSphereRadius, HitCylinderLength, self.params.worldPosition, misileRotation, filter )
		self.sv.trigger:bindOnEnter( "sv_trigger_onEnter" )
		self.sv.trigger:bindOnProjectile( "sv_trigger_onProjectile")
	end

	-- Update time
	local elapsedTicks = 0
	if self.sv.lastUpdateTick then
		elapsedTicks = math.max( currentTick - self.sv.lastUpdateTick, 0 )
	end
	self.sv.lastUpdateTick = currentTick
	local elapsedTime = elapsedTicks * TimeStep

	-- Update direction
	local stoppedHomingSync = false
	if currentTick >= self.sv.createTick + TargetingDelayTickTime then
		if self.sv.curveAxis ~= nil and currentTick < self.sv.createTick + TargetingDelayTickTime + CurveTickTime then
			-- Curve
			-- Turn around the curve axis
			self.sv.worldDirection = self.sv.worldDirection:rotate( CurveSpeed * elapsedTime, self.sv.curveAxis ):safeNormalize( self.sv.worldDirection )
		else
			-- Homing
			if not self.sv.stoppedHoming then
				if sm.exists( self.sv.targetCharacter ) then
					local targetPosition = self.sv.targetCharacter.worldPosition + self.sv.targetOffset
					local fromTo = targetPosition - self.sv.worldPosition
					local wantedDirection = fromTo:safeNormalize( sm.vec3.new( 0, 0, -1 ) )
					local distance2 = fromTo:length2()
					if distance2 <= StopHomingDistance * StopHomingDistance or currentTick >= self.sv.createTick + StopHomingTickTime then
						self.sv.stoppedHoming = true
						stoppedHomingSync = true
					end
					-- Turn towards the wanted direction
					local cross = self.sv.worldDirection:cross( wantedDirection )
					local aimRotationVector = cross:safeNormalize( orthogonal( self.sv.worldDirection ) )
					local aimAngleDiff = clamp( math.acos( clamp( self.sv.worldDirection:dot( wantedDirection ), -1, 1 ) ), 0.0, MaxAimSpeed * elapsedTime )
					self.sv.worldDirection = self.sv.worldDirection:rotate( aimAngleDiff, aimRotationVector ):safeNormalize( self.sv.worldDirection )
				end
			end
		end
	end

	-- Update position
	local previousPosition = self.sv.worldPosition
	self.sv.worldPosition = self.sv.worldPosition + self.sv.worldDirection * MaxTravelSpeed * elapsedTime
	if self.sv.trigger then
		self.sv.trigger:setWorldPosition( self.sv.worldPosition )
		local misileRotation = sm.vec3.getRotation( sm.vec3.new( 0, 0, 1 ), self.sv.worldDirection )
		self.sv.trigger:setWorldRotation( misileRotation )
	end

	-- Check for collision
	local mask = sm.physics.filter.default + sm.physics.filter.waterArea - sm.physics.filter.character
	local hit, result = sm.physics.spherecast( previousPosition, self.sv.worldPosition, HitSphereRadius, nil, mask )
	if hit then
		-- Destroy shape
		if result.type == "body" then
			local hitShape = result:getShape()
			if sm.exists( hitShape ) then
				if hitShape.isBlock then
					-- Destroy hit block
					local hitPos = result.pointWorld
					local blockPosition = hitShape:getClosestBlockLocalPosition( hitPos )
					hitShape:destroyBlock( blockPosition, nil, DestructionLevel )

					-- Extra damage if wood or cardboard
					if isAnyOf( hitShape:getMaterialId(), { sm.shape.material.wood, sm.shape.material.cardboard } ) then
						-- Create list of extra destruction positions
						local hitPositions = {}
						-- Sides
						hitPositions[#hitPositions+1] = hitPos + sm.vec3.new( 1, 0, 0 ) * 0.25
						hitPositions[#hitPositions+1] = hitPos + sm.vec3.new( -1, 0, 0 ) * 0.25
						hitPositions[#hitPositions+1] = hitPos + sm.vec3.new( 0, 1, 0 ) * 0.25
						hitPositions[#hitPositions+1] = hitPos + sm.vec3.new( 0, -1, 0 ) * 0.25
						hitPositions[#hitPositions+1] = hitPos + sm.vec3.new( 0, 0, 1 ) * 0.25
						hitPositions[#hitPositions+1] = hitPos + sm.vec3.new( 0, 0, -1 ) * 0.25
						-- Corners
						hitPositions[#hitPositions+1] = hitPos + sm.vec3.new( 1, 1, 1 ) * 0.25
						hitPositions[#hitPositions+1] = hitPos + sm.vec3.new( -1, 1, 1 ) * 0.25
						hitPositions[#hitPositions+1] = hitPos + sm.vec3.new( 1, -1, 1 ) * 0.25
						hitPositions[#hitPositions+1] = hitPos + sm.vec3.new( 1, 1, -1 ) * 0.25
						hitPositions[#hitPositions+1] = hitPos + sm.vec3.new( -1, -1, 1 ) * 0.25
						hitPositions[#hitPositions+1] = hitPos + sm.vec3.new( -1, 1, -1 ) * 0.25
						hitPositions[#hitPositions+1] = hitPos + sm.vec3.new( 1, -1, -1 ) * 0.25
						hitPositions[#hitPositions+1] = hitPos + sm.vec3.new( -1, -1, -1 ) * 0.25

						-- Find all unique block positions
						local hashedBlockPositions = {}
						local indexedBlockPositions = {}
						for _, hitPosition in ipairs( hitPositions ) do
							local blockPosition = hitShape:getClosestBlockLocalPosition( hitPosition )
							local hashedBlockPosition = sm.util.hash( blockPosition )
							if not hashedBlockPositions[hashedBlockPosition] then
								hashedBlockPositions[hashedBlockPosition] = true
								indexedBlockPositions[#indexedBlockPositions+1] = blockPosition
							end
						end
						-- Destroy randomly selcted extra blocks
						if #indexedBlockPositions > 0 then
							for i = 1, math.min( #indexedBlockPositions, ExtraWoodBlockDestruction ) do
								-- Destroy random block
								local randomIndex = math.random( 1, #indexedBlockPositions )
								local randomBlockPosition = indexedBlockPositions[randomIndex]
								hitShape:destroyBlock( randomBlockPosition, nil, DestructionLevel )
								--Swap and pop
								indexedBlockPositions[randomIndex], indexedBlockPositions[#indexedBlockPositions] = indexedBlockPositions[#indexedBlockPositions], indexedBlockPositions[randomIndex]
								indexedBlockPositions[#indexedBlockPositions] = nil
							end
						end
					end
				elseif hitShape:getInteractable() == nil then
					-- Destroy non-interactable parts
					hitShape:destroyShape( DestructionLevel )
				end
			end
		end
		-- Ignite nearby shapes
		sm.fire.igniteSphere( result.pointWorld, ExplosionRadius )
	end

	-- Check if it's time to explode
	if hit or currentTick >= self.sv.createTick + SelfdestructTickTime then
		self:sv_destroy()
	end

	-- Sync to client
	if currentTick >= self.sv.lastSyncTick + SyncTickInterval or stoppedHomingSync then
		self.network:setClientData( { serverPosition = self.sv.worldPosition, serverDirection = self.sv.worldDirection, stoppedHoming = self.sv.stoppedHoming }, 2 )
		self.sv.lastSyncTick = currentTick
	end
end

function Missile.sv_destroy( self )
	if not self.destroyed and sm.exists( self.scriptableObject ) then
		sm.effect.playEffect( "Scannerbot - Missleexplosion", self.sv.worldPosition )

		-- Damage nearby characters
		local contacts = sm.physics.getSphereContacts( self.sv.worldPosition, ExplosionRadius )
		for _, character in ipairs( contacts.characters ) do
			if sm.exists( character ) then
				local validTargetCharacter = character:isPlayer() or isAnyOf( character:getCharacterType(), { unit_woc, unit_worm } )
				if validTargetCharacter then
					local fromToPlayer = character.worldPosition - self.sv.worldPosition
					self:sv_onHitCharacter( { character = character, knockbackDirection = sm.vec3.new( fromToPlayer.x, fromToPlayer.y, 0 ):safeNormalize( -character.direction ) } )
				end
			end
		end

		self.scriptableObject:destroy()
		self.destroyed = true
	end
end

function Missile.sv_onHitCharacter( self, params )
	if params.character:isPlayer() then
		local player = params.character:getPlayer()
		if sm.exists( player ) then
			sm.event.sendToPlayer( player, "sv_e_receiveDamage", { damage = Damage, source = "scannerbot" } )
		end
	else
		local unit = params.character:getUnit()
		if sm.exists( unit ) then
			sm.event.sendToUnit( unit, "sv_e_receiveDamage", { damage = Damage, impact = self.sv.worldDirection, hitPos = self.sv.worldPosition } )
		end
	end
	ApplyKnockback( params.character, params.knockbackDirection, 4000 )
end

function Missile.sv_trigger_onEnter( self, trigger, results )
	if not sm.exists( self.scriptableObject ) then return end
	self:sv_destroy()
end

function Missile.sv_trigger_onProjectile( self, trigger, hitPos, hitTime, hitVelocity, _, attacker, damage, userData, hitNormal, projectileUuid )
	-- Detect player attack
	if attacker and sm.exists( attacker ) then
		if type( attacker ) == "Player" then
			if isAnyOf( projectileUuid, g_potatoProjectiles ) then
				if not sm.exists( self.scriptableObject ) then return end
				self:sv_destroy()
				return true
			end
		end
	end

	return false
end

function Missile.client_onCreate( self )
	self.cl = {}
end

function Missile.client_onDestroy( self )
	if self.cl.effect then
		self.cl.effect:destroy()
		self.cl.effect = nil
	end
	if self.cl.trailEffect then
		self.cl.trailEffect:stop()
		self.cl.trailEffect = nil
	end
	if self.cl.targetCharacter then
		ScannerbotManager.Cl_RemoveMissileTarget( self.scriptableObject, self.cl.targetCharacter )
	end
end

function Missile.client_onClientDataUpdate( self, data, channel )
	if channel == 1 then
		self.cl.targetCharacter = data.targetCharacter
		if self.cl.targetCharacter then
			ScannerbotManager.Cl_AddMissileTarget( self.scriptableObject, self.cl.targetCharacter )
		end
		self.cl.worldPosition = data.initialPosition
		self.cl.previousWorldPosition = data.initialPosition
		self.cl.worldDirection = data.initialDirection
		self.cl.stoppedHoming = false
		self.cl.createTick = data.createTick
		self.cl.lastUpdateTick = data.createTick
		self.cl.targetOffset = data.targetOffset
		self.cl.curveAxis = data.curveAxis
	elseif channel == 2 then
		self.cl.previousWorldPosition = self.cl.worldPosition
		self.cl.worldPosition = data.serverPosition
		self.cl.worldDirection = data.serverDirection
		self.cl.stoppedHoming = data.stoppedHoming
	end

	if self.cl.effect == nil then
		self.cl.effect = sm.effect.createEffect( "ShapeRenderable" )
		local missileUuid = sm.uuid.new( "f993ed50-f6db-4f38-a559-d86dd1efda2a" )
		self.cl.effect:setParameter( "uuid", missileUuid )
		self.cl.effect:setScale( sm.vec3.new( 0.25, 0.25, 0.25 ) )
		self.cl.effect:setPosition( self.cl.worldPosition )
		local rotation = sm.vec3.getRotation( sm.vec3.new( 0, 1, 0 ), self.cl.worldDirection )
		self.cl.effect:setRotation( rotation )
		self.cl.effect:start()
	end
	if self.cl.trailEffect == nil then
		self.cl.trailEffect = sm.effect.createEffect( "Scannerbot - Misslesmoketrail" )
		self.cl.trailEffect:setPosition( self.cl.worldPosition )
		local rotation = sm.vec3.getRotation( sm.vec3.new( 0, 0, 1 ), self.cl.worldDirection )
		self.cl.trailEffect:setRotation( rotation )
		self.cl.trailEffect:start()
	end
end

function Missile.client_onUpdate( self, deltaTime )
	self.cl.interpolationTime = self.cl.interpolationTime + deltaTime
	local p = self.cl.interpolationTime / 0.025
	local interpolatedWorldPosition = sm.vec3.lerp( self.cl.previousWorldPosition, self.cl.worldPosition, p )
	self.cl.effect:setPosition( interpolatedWorldPosition )
	self.cl.trailEffect:setPosition( interpolatedWorldPosition )
	local forward = sm.vec3.new( 0, 1, 0 )
	local headingDirection = sm.vec3.new( self.cl.worldDirection.x, self.cl.worldDirection.y, 0.0 ):safeNormalize( forward )
	local heading = math.atan2( -headingDirection.x, headingDirection.y )
	local pitch = math.asin( self.cl.worldDirection.z )
	local rotation = sm.quat.fromEuler( sm.vec3.new( 0, 0, math.deg( heading ) ) ) * sm.quat.fromEuler( sm.vec3.new( math.deg( pitch ), 0, 0 ) )
	self.cl.effect:setRotation( rotation )
	self.cl.trailEffect:setRotation( rotation )
end

function Missile.client_onFixedUpdate( self, deltaTime )
	local serverTick = sm.game.getServerTick()

	-- Update time
	local elapsedTicks = 0
	if self.cl.lastUpdateTick then
		elapsedTicks = math.max( serverTick - self.cl.lastUpdateTick, 0 )
	end
	self.cl.lastUpdateTick = serverTick
	local elapsedTime = elapsedTicks * TimeStep

	-- Update direction
	if serverTick >= self.cl.createTick + TargetingDelayTickTime then
		if self.cl.curveAxis ~= nil and serverTick < self.cl.createTick + TargetingDelayTickTime + CurveTickTime then
			-- Curve
			-- Turn around the curve axis
			self.cl.worldDirection = self.cl.worldDirection:rotate( CurveSpeed * elapsedTime, self.cl.curveAxis ):safeNormalize( self.cl.worldDirection )
		else
			-- Homing
			if not self.cl.stoppedHoming then
				if sm.exists( self.cl.targetCharacter ) then
					local targetPosition = self.cl.targetCharacter.worldPosition + self.cl.targetOffset
					wantedDirection = ( targetPosition - self.cl.worldPosition ):safeNormalize( sm.vec3.new( 0, 0, -1 ) )
					-- Turn towards the wanted direction
					local cross = self.cl.worldDirection:cross( wantedDirection )
					local aimRotationVector = cross:safeNormalize( orthogonal( self.cl.worldDirection ) )
					local aimAngleDiff = clamp( math.acos( clamp( self.cl.worldDirection:dot( wantedDirection ), -1, 1 ) ), 0.0, MaxAimSpeed * elapsedTime )
					self.cl.worldDirection = self.cl.worldDirection:rotate( aimAngleDiff, aimRotationVector ):safeNormalize( self.cl.worldDirection )
				end
			end
		end
	end

	-- Update position
	self.cl.previousWorldPosition = self.cl.worldPosition
	self.cl.worldPosition = self.cl.worldPosition + self.cl.worldDirection * MaxTravelSpeed * elapsedTime
	self.cl.interpolationTime = 0.0
end