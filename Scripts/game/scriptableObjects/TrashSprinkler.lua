
TrashSprinkler = class()
TrashSprinkler.isSaveObject = false

local SpraySegments = 5
local DefaultSprayTimeout = math.floor( 40 * 40 )
local SprayDamage = 15
local RotationSpeed = 20
local NearDistance = 6
local FarDistance = 30
local SegmentLength = ( FarDistance - NearDistance ) / SpraySegments
local SegmentStartRotation = sm.vec3.new( -1, 0, 0 )
local UpVec = sm.vec3.new( 0, 0, 1 )
local TriggerHeight = 4.2
local HitCooldown = 0.4
local KnockbackStrength = 8000

local AbortDuration = math.floor( 0.6 * 40 )

local OpenDuration = math.floor( 5.0 * 40.0 )
local OpenInterval = math.floor( 2.0 * 40.0 )

local EffectMovementDelay = 0.5

function TrashSprinkler.server_onCreate( self )
	self.sv = {}
	self.sv.createTick = sm.game.getCurrentTick()
	self.sv.origo = self.params and self.params.position or nil
	self.sv.direction = self.params and self.params.direction or nil
	self.sv.firePosition = self.params and self.params.firePosition or nil
	self.sv.clockwise = self.params and self.params.clockwise or false
	self.sv.duration = self.params and self.params.duration or DefaultSprayTimeout
	self.sv.isRightSide = self.params and self.params.isRightSide or false
	
	self.network:setClientData( { origo = self.sv.origo, direction = self.sv.direction, firePosition = self.sv.firePosition, clockwise = self.sv.clockwise, isRightSide = self.sv.isRightSide }, 1 )

	self.sv.intervalCounter = 0
	self.sv.durationCounter = 0
	self.sv.hasOpening = false
	self.sv.markedForDestruction = false
end

function TrashSprinkler.server_onRefresh( self )

end

function TrashSprinkler.server_onFixedUpdate( self, deltaTime )
	local currentTick = sm.game.getCurrentTick()
	if currentTick >= self.sv.createTick + self.sv.duration and self.sv.markedForDestroy then
		if sm.exists( self.scriptableObject ) then
			self.scriptableObject:destroy()
		end
	end

	if currentTick >= self.sv.createTick + self.sv.duration - AbortDuration and not self.sv.markedForDestroy then
		self.sv.markedForDestroy = true
		self.network:sendToClients( "cl_n_stopEffects" )
	end

	if not self.sv.hasOpening then
		self.sv.intervalCounter = self.sv.intervalCounter + 1
		if self.sv.intervalCounter >= OpenInterval then
			self.sv.intervalCounter = 0
			self.sv.hasOpening = true
			local newOpening = math.random( SpraySegments )
			self.network:setClientData( newOpening, 2 )
		end
	else
		self.sv.durationCounter = self.sv.durationCounter + 1
		if self.sv.durationCounter >= OpenDuration then
			self.sv.durationCounter = 0
			self.sv.hasOpening = false
			self.network:setClientData( nil, 2 )
		end
	end
end

function TrashSprinkler.sv_n_hitCharacter( self, params )
	if params.character:isPlayer() then
		sm.event.sendToPlayer( params.character:getPlayer(), "sv_e_receiveDamage", { damage = SprayDamage, source = "impact" } )
	end
	ApplyKnockback( params.character, params.knockbackDirection, KnockbackStrength )
	sm.effect.playEffect( "Trashbot - Slimewave Impact Green", params.character.worldPosition + sm.vec3.new( 0, 0, -1.5 ), nil, nil, nil, { Velocity_max_50 = 9 } )
end

function TrashSprinkler.sv_n_shockwaveLift( self, lift )
	local bottomPos = lift.worldPosition
	sm.effect.playEffect( "ToteBot - DestroyedParts", bottomPos, nil, nil, nil, { Color = sm.color.new( 1, 1, 0 ) } )
	for i = 0, lift.level do
		local topOffset = ( 1 + i ) * 0.25 + 0.125
		local topPos = bottomPos + sm.vec3.new( 0, 0, topOffset )
		if i == lift.level then
			sm.effect.playEffect( "ToteBot - DestroyedParts", topPos, nil, nil, nil, { Color = sm.color.new( 1, 1, 0 ) } )
		else
			sm.effect.playEffect( "Farmbot - Hit", topPos )
		end
	end
	lift:destroy()
end

function TrashSprinkler.client_onCreate( self )
	self.cl = {}

	self.cl.triggeredCharacter = false
	self.cl.triggeredLift = false
	self.cl.elapsedTime = 0
	self.cl.effectDelayTimer = 0
	self.cl.spraySegments = {}
	self.cl.shootEffect = nil
	self.cl.cooldownTimer = 0.0
	self.cl.directionModifier = -1
	self.cl.currentDiration = sm.vec3.new( 1, 0, 0 )
	self.cl.currentOpening = nil

	self.cl.loopStarted = false
end

function TrashSprinkler.client_onClientDataUpdate( self, data, channel )
	if channel == 1 then
		self.cl.origo = data.origo
		self.cl.direction = data.direction
		self.cl.firePosition = data.firePosition
		self.cl.isRightSide = data.isRightSide
		
		if data.clockwise == false then
			self.cl.directionModifier = 1
		end
		local filter = sm.areaTrigger.filter.character + sm.areaTrigger.filter.lift
		local raycastFilter = bit.bor( sm.physics.filter.terrainAsset, sm.physics.filter.terrainSurface )
		if self.cl.origo and self.cl.direction and self.cl.firePosition then
			local verticalStartRotation = sm.vec3.getRotation( SegmentStartRotation, self.cl.direction )
			for i = 1, SpraySegments do
				local spawnPos = self.cl.origo + self.cl.direction * ( NearDistance + SegmentLength * i + SegmentLength * ( i - 1 ) ) -- center point of the segment
				local hit, result = sm.physics.raycast( spawnPos + sm.vec3.new( 0, 0, 30 ), spawnPos - sm.vec3.new( 0, 0, 30 ), nil, raycastFilter )
				if hit then
					self.cl.spraySegments[i] = {}
					local positionNormal = result.normalWorld
					local dot = sm.vec3.dot( positionNormal, UpVec )
	
					local angle = math.acos( dot )
					self.cl.spraySegments[i].angle = angle
	
					local horizontalRotation = sm.quat.angleAxis( angle, sm.quat.getUp( verticalStartRotation ) )
					local hitHeight = result.pointWorld.z
					spawnPos.z = hitHeight
	
					self.cl.spraySegments[i].trigger = sm.areaTrigger.createBox( sm.vec3.new( SegmentLength * 1.1, 0.5, TriggerHeight ), spawnPos, horizontalRotation * verticalStartRotation, filter )
					self.cl.spraySegments[i].trigger:bindOnEnter( "trigger_onEnter" )

					local color = self.cl.isRightSide == true and "Green" or "Purple"

					self.cl.spraySegments[i].splashEffect = sm.effect.createEffect( "Trashbot - "..color.."sprinkler01_splash" )
					self.cl.spraySegments[i].splashEffect:setPosition( spawnPos + sm.vec3.new( 0, 0, 0.5 ) )
					self.cl.spraySegments[i].splashEffect:setRotation( horizontalRotation )

					self.cl.spraySegments[i].startEffect = sm.effect.createEffect( "Trashbot - "..color.."sprinkler0"..i.."_start" )
					self.cl.spraySegments[i].loopEffect = sm.effect.createEffect( "Trashbot - "..color.."sprinkler0"..i.."_loop" )
					self.cl.spraySegments[i].endEffect = sm.effect.createEffect( "Trashbot - "..color.."sprinkler0"..i.."_end" )

					self.cl.spraySegments[i].startEffect:setPosition( self.cl.origo )
					self.cl.spraySegments[i].loopEffect:setPosition( self.cl.origo )
					self.cl.spraySegments[i].endEffect:setPosition( self.cl.origo )

					self.cl.spraySegments[i].startEffect:setRotation( verticalStartRotation )
					self.cl.spraySegments[i].loopEffect:setRotation( verticalStartRotation )
					self.cl.spraySegments[i].endEffect:setRotation( verticalStartRotation )

					self.cl.spraySegments[i].startEffect:start()
				end
			end
		end
	elseif channel == 2 then
		self.cl.currentOpening = data
		if data ~= nil then
			self.cl.spraySegments[data].splashEffect:stop()
		end
	end
end

function TrashSprinkler.client_onDestroy( self )
	for _, spraySegment in pairs( self.cl.spraySegments ) do
		if spraySegment.trigger and sm.exists( spraySegment.trigger ) then
			sm.areaTrigger.destroy( spraySegment.trigger )
		end
		if spraySegment.splashEffect and sm.exists( spraySegment.splashEffect ) then
			spraySegment.splashEffect:destroy()
		end
		if spraySegment.startEffect and sm.exists( spraySegment.startEffect ) then
			spraySegment.startEffect:destroy()
		end
		if spraySegment.loopEffect and sm.exists( spraySegment.loopEffect ) then
			spraySegment.loopEffect:destroy()
		end
		if spraySegment.endEffect and sm.exists( spraySegment.endEffect ) then
			spraySegment.endEffect:destroy()
		end
	end
	self.cl.spraySegments = {}
end

function TrashSprinkler.client_onUpdate( self, deltaTime )
	self.cl.effectDelayTimer = self.cl.effectDelayTimer + deltaTime
	-- Effects
	if self.cl.origo then
		for i = 1, SpraySegments do
			if self.cl.loopStarted == false and self.cl.effectDelayTimer >= EffectMovementDelay - 0.05 then
				if i == SpraySegments then
					self.cl.loopStarted = true
				end
				self.cl.spraySegments[i].loopEffect:start()
				self.cl.spraySegments[i].splashEffect:start()
			end
		end
	end
	if self.cl.effectDelayTimer >= EffectMovementDelay then
		self.cl.elapsedTime = self.cl.elapsedTime + deltaTime
	
		local modifiedDirection = self.cl.directionModifier * self.cl.elapsedTime * RotationSpeed * math.pi / 180
		local newDirection = sm.vec3.rotate( self.cl.direction, modifiedDirection,  UpVec )
		local verticalRotation = sm.vec3.getRotation( SegmentStartRotation, newDirection )
	
		-- Update shockwave segments
		for i, spraySegment in pairs( self.cl.spraySegments ) do
			if self.cl.currentOpening == nil and not spraySegment.splashEffect:isPlaying() then
				spraySegment.splashEffect:start()
			end

			if spraySegment.endEffect:isPlaying() and spraySegment.loopEffect:isPlaying() then
				spraySegment.loopEffect:stopImmediate()
			end

			spraySegment.loopEffect:setRotation( verticalRotation )
			spraySegment.endEffect:setRotation( verticalRotation )
	
			local currentPosition = spraySegment.trigger:getWorldPosition()
			local newPosition = self.cl.origo + newDirection * ( NearDistance + SegmentLength * i + SegmentLength * ( i - 1 ) )
			newPosition.z = currentPosition.z
			if i == 1 then
				self.cl.currentDiration = ( newPosition - currentPosition ):safeNormalize( sm.vec3.new( 1, 0, 0 ) )
			end
			local horizontalRotation = sm.quat.angleAxis( spraySegment.angle, sm.quat.getUp( verticalRotation ) )
			spraySegment.trigger:setWorldPosition( newPosition )
			spraySegment.trigger:setWorldRotation( horizontalRotation * verticalRotation )
	
			spraySegment.splashEffect:setPosition( newPosition + sm.vec3.new( 0, 0, 0.5 ) )
			spraySegment.splashEffect:setRotation( horizontalRotation )
		end
	
		if self.cl.triggeredCharacter ~= nil then
			self.cl.cooldownTimer = self.cl.cooldownTimer + deltaTime
			if self.cl.cooldownTimer >= HitCooldown then
				self.cl.triggeredCharacter = nil
				self.cl.cooldownTimer = 0.0
			end
		end
	end
end

function TrashSprinkler.cl_n_stopEffects( self )
	for i, spraySegment in pairs( self.cl.spraySegments ) do
		spraySegment.endEffect:start()
	end
end

function TrashSprinkler.trigger_onEnter( self, trigger, results )
	if self.cl.currentOpening ~= nil then
		if self.cl.spraySegments[self.cl.currentOpening].trigger == trigger then
			return
		end
	end
	local clientCharacter = sm.localPlayer.getPlayer().character
	local clientLift = sm.localPlayer.getOwnedLift()
	for _, result in ipairs( results ) do
		if sm.exists( result ) then
			local character
			local lift
			if type( result ) == "Character" and result:isPlayer() then
				character = result
			elseif type( result ) == "Lift" then
				lift = result
			end
			
			if clientCharacter and clientCharacter == character then
				if not self.cl.triggeredCharacter then
					-- Shockwave hit player
					self.cl.triggeredCharacter = true
					self.network:sendToServer( "sv_n_hitCharacter", { character = character, knockbackDirection = self.cl.currentDiration } )
				end
			elseif clientLift and clientLift == lift then
				if not self.cl.triggeredLift then
					-- Shockwave hit lift
					self.cl.triggeredLift = true
					self.network:sendToServer( "sv_n_shockwaveLift", lift )
				end
			end
		end
	end
end

function TrashSprinkler.sv_e_abort( self )
	self.sv.duration = self.sv.durationCounter + AbortDuration
end