local ShockwaveUuid = sm.uuid.new( "fad7edde-4a10-4e35-851c-645a42f02a76" )

TrashShockwave = class()
TrashShockwave.isSaveObject = false

local ShockwaveSegments = 32
local EulerAngleZStep = 360 / ShockwaveSegments
local ShockwaveRadius = 80
local ShockwaveSpeed = 12
local ShockwaveTimeoutTick = 40 * 4.8
local ShockwaveDamage = 30
local ScaleFractionTweak = 0.5 -- Adjust scale with subwaves
local ShockwaveSegmentScale = ( 0.015625 * ShockwaveSegments * ShockwaveSegments - 1.375 * ShockwaveSegments + 32 ) * ScaleFractionTweak

local SecondSpawnTickDelay = math.floor( 1.0 * 40 ) -- Delay before spawning second shockwave when waveAmount is over 1

local HeightStartOffset = 6
local SlopeModifier = 0.0065
local SlopeEnd = 33.0

local ColorEffects = {
	["green"] = {
		impact = "Trashbot - Slimewave Impact Green",
		wave = "Trashbot - Slimewave Wave Green",
		subwave = "Trashbot - Slimewave Subwave Green",
		jump = "Trashbot - Jumpimpact Green"
	},
	["purple"] = {
		impact = "Trashbot - Slimewave Impact Purple",
		wave = "Trashbot - Slimewave Wave Purple",
		subwave = "Trashbot - Slimewave Subwave Purple",
		jump = "Trashbot - Jumpimpact Purple"
	}
}

function TrashShockwave.server_onCreate( self )
	self.sv = {}
	self.sv.createTick = sm.game.getCurrentTick()
	self.sv.origo = self.params and self.params.position or nil
	self.sv.color = self.params and self.params.color or "purple"
	self.sv.waveAmount = self.params and self.params.waveAmount - 1 or 0
	self.sv.secondSpawnCounter = 0

	sm.effect.playEffect( ColorEffects[self.sv.color].jump, self.sv.origo )

	self.network:setClientData( { origo = self.sv.origo, color = self.sv.color }, 1 )
end

function TrashShockwave.server_onRefresh( self )
end

function TrashShockwave.server_onFixedUpdate( self, deltaTime )
	if self.sv.waveAmount > 0 then
		self.sv.secondSpawnCounter = self.sv.secondSpawnCounter + 1
		if self.sv.secondSpawnCounter >= SecondSpawnTickDelay then
			self.sv.secondSpawnCounter = 0

			-- Spawn second shockwave
			local params = { position = self.sv.origo, color = self.sv.color, waveAmount = self.sv.waveAmount }
			sm.scriptableObject.createScriptableObject( ShockwaveUuid, params, self.scriptableObject:getWorld() )
			self.sv.waveAmount = 0
		end
	end

	local currentTick = sm.game.getCurrentTick()
	if currentTick >= self.sv.createTick + ShockwaveTimeoutTick then
		if sm.exists( self.scriptableObject ) then
			self.scriptableObject:destroy()
		end
	end
end

function TrashShockwave.sv_n_shockwaveCharacter( self, params )
	if params.character:isPlayer() then
		sm.event.sendToPlayer( params.character:getPlayer(), "sv_e_receiveDamage", { damage = ShockwaveDamage, source = "impact" } )
	end
	ApplyKnockback( params.character, params.knockbackDirection, 2000 )
	sm.effect.playEffect( ColorEffects[self.sv.color].impact, params.character.worldPosition + sm.vec3.new( 0, 0, -1.5 ), nil, nil, nil, { Velocity_max_50 = 9 } )
end

function TrashShockwave.sv_n_shockwaveLift( self, lift )
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

function TrashShockwave.client_onCreate( self )
	self.cl = {}

	self.cl.triggeredCharacter = false
	self.cl.triggeredLift = false
	self.cl.elapsedTime = 0
	self.cl.shockwaveSegments = {}
	self.cl.shockwaveAudio = sm.effect.createEffect( "audio:event:/char/npc/bots/enemies/trashbot/stomp_goo" )
	self.cl.color = "green"
end

function TrashShockwave.client_onClientDataUpdate( self, data, channel )
	if channel == 1 then
		self.cl.origo = data.origo
		if self.cl.origo then
			if data.color then
				self.cl.color = data.color
			end
			local baseEulerAngleZ = math.random() * 360
			for i = 1, ShockwaveSegments do
				local shockwaveSegment = {}

				local eulerAngleZCurrentStep = EulerAngleZStep * i
				local eulerAngleZ = ( baseEulerAngleZ + eulerAngleZCurrentStep ) % 360
				local segmentRotation = sm.quat.fromEuler( sm.vec3.new( 0, 0, eulerAngleZ ) )
				shockwaveSegment.direction = segmentRotation * sm.vec3.new( 0, 1, 0 )
				shockwaveSegment.rotation = sm.vec3.new( 0, 0, eulerAngleZ )

				-- Trigger
				local filter = sm.areaTrigger.filter.character + sm.areaTrigger.filter.lift
				shockwaveSegment.trigger = sm.areaTrigger.createBox( sm.vec3.new( 0.5, 0.5, 2.2 ), self.cl.origo, segmentRotation, filter )
				shockwaveSegment.trigger:bindOnEnter( "trigger_onEnter" )

				-- Shockwave Effect
				shockwaveSegment.shockwaveEffect = sm.effect.createEffect( ColorEffects[self.cl.color].wave )
				shockwaveSegment.shockwaveEffect:setPosition( self.cl.origo )
				shockwaveSegment.shockwaveEffect:setRotation( segmentRotation )
				shockwaveSegment.shockwaveEffect:setParameter( "Scale", sm.vec3.new( 1, 1, ShockwaveSegmentScale ) )
				shockwaveSegment.shockwaveEffect:start()

				-- Subwave Effect
				local subEulerAngleZ = ( eulerAngleZ - EulerAngleZStep * 0.5 ) % 360
				local subSegmentRotation = sm.quat.fromEuler( sm.vec3.new( 0, 0, subEulerAngleZ ) )
				shockwaveSegment.subRotation = sm.vec3.new( 0, 0, subEulerAngleZ )
				shockwaveSegment.subwaveEffect = sm.effect.createEffect( ColorEffects[self.cl.color].subwave )
				shockwaveSegment.subwaveEffect:setPosition( self.cl.origo )
				shockwaveSegment.subwaveEffect:setRotation( subSegmentRotation )
				shockwaveSegment.subwaveEffect:setParameter( "Scale", sm.vec3.new( 1, 1, ShockwaveSegmentScale ) )
				shockwaveSegment.subwaveEffect:start()

				self.cl.shockwaveSegments[tostring(shockwaveSegment.trigger.id)] = shockwaveSegment
			end
			self.cl.shockwaveAudio:setPosition( self.cl.origo )
			if not self.cl.shockwaveAudio:isPlaying() then
				self.cl.shockwaveAudio:start()
			end
		end

	end
end

function TrashShockwave.client_onDestroy( self )
	for _, shockwaveSegment in pairs( self.cl.shockwaveSegments ) do
		if shockwaveSegment.trigger and sm.exists( shockwaveSegment.trigger ) then
			sm.areaTrigger.destroy( shockwaveSegment.trigger )
		end
		if shockwaveSegment.shockwaveEffect and sm.exists( shockwaveSegment.shockwaveEffect ) then
			shockwaveSegment.shockwaveEffect:destroy()
		end
		if shockwaveSegment.subwaveEffect and sm.exists( shockwaveSegment.subwaveEffect ) then
			shockwaveSegment.subwaveEffect:destroy()
		end
	end
	if self.cl.shockwaveAudio then
		self.cl.shockwaveAudio:destroy()
	end
	self.cl.shockwaveSegments = {}
end

function TrashShockwave.client_onUpdate( self, deltaTime )

	self.cl.elapsedTime = self.cl.elapsedTime + deltaTime
	local vertexRadius = self.cl.elapsedTime * ShockwaveSpeed
	local inRadius = vertexRadius * math.cos( math.pi / ShockwaveSegments )
	local segmentLength = inRadius * 2 * math.tan( math.pi / ShockwaveSegments )

	if vertexRadius > ShockwaveRadius then
		-- Remove shockwave on client
		for _, shockwaveSegment in pairs( self.cl.shockwaveSegments ) do
			if shockwaveSegment.trigger and sm.exists( shockwaveSegment.trigger ) then
				sm.areaTrigger.destroy( shockwaveSegment.trigger )
			end
			if shockwaveSegment.shockwaveEffect and sm.exists( shockwaveSegment.shockwaveEffect ) then
				shockwaveSegment.shockwaveEffect:destroy()
			end
			if self.cl.shockwaveAudio then
				self.cl.shockwaveAudio:destroy()
			end
			if shockwaveSegment.subwaveEffect and sm.exists( shockwaveSegment.subwaveEffect ) then
				shockwaveSegment.subwaveEffect:destroy()
			end
		end
		self.cl.shockwaveSegments = {}
	end

	local distance = math.max( 0, inRadius - HeightStartOffset )
	local verticalIncrease = SlopeModifier * distance * distance
	
	if distance > SlopeEnd then
		verticalIncrease = verticalIncrease + ( ( distance - SlopeEnd )^2 * SlopeModifier )
	end

	-- Update shockwave segments
    for _, shockwaveSegment in pairs( self.cl.shockwaveSegments ) do
        local shockwaveOffset = shockwaveSegment.direction * inRadius
        shockwaveOffset.z = shockwaveOffset.z + verticalIncrease  -- Add the vertical component

        -- Update trigger position
        local size = shockwaveSegment.trigger:getSize()
        shockwaveSegment.trigger:setSize( sm.vec3.new( segmentLength * 0.5, size.y, size.z ) )
        shockwaveSegment.trigger:setWorldPosition( self.cl.origo + shockwaveOffset )

        -- Update shockwave effect position
        shockwaveSegment.shockwaveEffect:setPosition( self.cl.origo + shockwaveOffset )

        -- Update subwave effect position
        local subwaveOffset = shockwaveOffset:rotateZ( math.rad( -EulerAngleZStep * 0.5 ) )
        shockwaveSegment.subwaveEffect:setPosition( self.cl.origo + subwaveOffset )
    end

	if self.cl.shockwaveAudio then
		local myPlayer = sm.localPlayer.getPlayer()
		local myCharacter = myPlayer and myPlayer.character or nil
		if sm.exists( myCharacter ) then
			local direction = myCharacter.worldPosition - self.cl.origo
			direction.z = 0
			direction = direction:normalize()
			
			local shockwaveOffset = direction * inRadius
        	shockwaveOffset.z = shockwaveOffset.z + verticalIncrease
			self.cl.shockwaveAudio:setPosition( self.cl.origo + shockwaveOffset )
		end
	end
end

function TrashShockwave.trigger_onEnter( self, trigger, results )
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
				if character:isOnGround() and not self.cl.triggeredCharacter then
					-- Shockwave hit player
					self.cl.triggeredCharacter = true
					local fromToPlayer = character.worldPosition - self.cl.origo
					self.network:sendToServer( "sv_n_shockwaveCharacter", { character = character, knockbackDirection = sm.vec3.new( fromToPlayer.x, fromToPlayer.y, 0 ):safeNormalize( -character.direction ) } )
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
