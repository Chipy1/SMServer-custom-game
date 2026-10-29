ScannerbotCharacter = class( nil )

local InnerSphereRadius = 32 -- Detects projectiles
local VisionSphereRadius = 60 -- Vision
local CharacterKnockback = 4000 -- Impulse on characters that are knocked by the force field
local CharacterRotation = sm.quat.fromEuler( sm.vec3.new( -90, 0, 180 ) )
local ScanTriggerHeightOffset = -27.0
local DescendEffectHeight = SCANNERBOT_GROUND_HEIGHT_ROAD + 175 -- Descend effect starts playing when descending and at this height or lower
local PingTime = 10.0 -- Time between ping sounds

--[[ Server ]]
function ScannerbotCharacter.server_onCreate( self )
	self.character:setHovering( true )
	self.sv = {}
	self.sv.visionSphereTrigger = sm.areaTrigger.createSphere( VisionSphereRadius, self.character.worldPosition, sm.quat.identity(), sm.areaTrigger.filter.character )
	self.sv.visionSphereTrigger:setCharacterDetection( true )

	self.sv.scanTrigger = sm.areaTrigger.createHull( "$SURVIVAL_DATA/Effects/Meshes/scannerbot/lightbeam_scannerbot.fbx", self.character.worldPosition, sm.quat.identity(), sm.areaTrigger.filter.character )
	self.sv.scanTrigger:setCharacterDetection( true )
	self.sv.scanTrigger:setWorldRotation( sm.quat.fromEuler( sm.vec3.new( 90, 0, 0 ) ) )

	self.shieldSphereTrigger = sm.areaTrigger.createSphere( InnerSphereRadius, self.character.worldPosition, sm.quat.identity(), sm.areaTrigger.filter.dynamicBody + sm.areaTrigger.filter.character )
	self.shieldSphereTrigger:setShapeDetection( true )
	self.shieldSphereTrigger:bindOnEnter( "sv_trigger_onEnterShield" )
	self.shieldSphereTrigger:bindOnProjectile( "sv_trigger_onProjectileShield" )
	self:sv_updateTriggerTransforms()
end

function ScannerbotCharacter.server_onDestroy( self )
	if self.sv.scanTrigger then
		sm.areaTrigger.destroy( self.sv.scanTrigger )
	end
	if self.sv.visionSphereTrigger then
		sm.areaTrigger.destroy( self.sv.visionSphereTrigger )
	end
end

function ScannerbotCharacter.server_onFixedUpdate( self, dt )
	self:sv_updateTriggerTransforms()
	self:sv_scan()
end

function ScannerbotCharacter.sv_updateTriggerTransforms( self )
	local characterPosition = self.character.worldPosition
	local up = sm.vec3.new( 0, 0, 1 )
	if self.sv.scanTrigger then
		local scannerHeightOffset = up * ScanTriggerHeightOffset
		local scannerWorldPosition = characterPosition + scannerHeightOffset
		self.sv.scanTrigger:setWorldPosition( scannerWorldPosition )
	end
	if self.sv.visionSphereTrigger then
		local visionSphereHeightOffset = up * -4
		local visionSphereWorldPosition = characterPosition + visionSphereHeightOffset
		self.sv.visionSphereTrigger:setWorldPosition( visionSphereWorldPosition )
	end
end

function ScannerbotCharacter.sv_scan( self )
	local charactersInArea = {}
	local visibleCharacters = {}
	if ScannerbotManager.Sv_GetBehaviour() == ScannerbotBehaviour.ROAD then
		-- Check scanner
		local scannerCharacterCollisions = self.sv.scanTrigger:getCharacters()
		for _, characterCollision in ipairs( scannerCharacterCollisions ) do
			if characterCollision.character ~= self.character then
				-- Filter on player and woc characters
				if sm.exists( characterCollision.character ) then
					local targetCharacter = characterCollision.character
					if ( targetCharacter:isPlayer() and not targetCharacter:isDowned() ) or targetCharacter:getCharacterType() == unit_woc then
						charactersInArea[targetCharacter.id] = targetCharacter
					end
				end
			end
		end
	end
	-- Check vision sphere
	local visionCharacterCollisions = self.sv.visionSphereTrigger:getCharacters()
	for _, characterCollision in ipairs( visionCharacterCollisions ) do
		if characterCollision.character ~= self.character then
			-- Filter on player and woc characters
			if sm.exists( characterCollision.character ) then
				local targetCharacter = characterCollision.character
				if ( targetCharacter:isPlayer() and not targetCharacter:isDowned() ) or targetCharacter:getCharacterType() == unit_woc then
					-- Can detect characters through objects
					visibleCharacters[targetCharacter.id] = targetCharacter
				end
			end
		end
	end
	-- Test if scanned characters are visible
	for _, character in pairs( charactersInArea ) do
		local from = self.character.worldPosition
		local to = character.worldPosition
		local fromTo = to - from
		local direction = fromTo:safeNormalize( sm.vec3.new( 0, 0, -1 ) )
		local numCasts = 5
		local casts = {}
		for i = 1, numCasts do
			local spreadDirection = sm.noise.gunSpread( direction, 0.5 )
			casts[#casts+1] = { type = "ray",
								startPoint = from,
								endPoint = from + spreadDirection * 256,
								mask = sm.physics.filter.default + sm.physics.filter.waterArea - sm.physics.filter.dynamicBody,
								ignoreObject = self.character }
		end

		local retTable = sm.physics.multicast( casts )
		for i = 1, numCasts do
			local success = retTable[i][1]
			local result = retTable[i][2]
			if success then
				if result.type == "character" then
					if result:getCharacter() == character then
						visibleCharacters[character.id] = character
						break
					end
				end
			end
		end
	end

	ScannerbotManager.Sv_AddTargets( visibleCharacters )
end

function ScannerbotCharacter.sv_trigger_onEnterShield( self, trigger, results )
	for _, result in ipairs( results ) do
		if sm.exists( result ) then
			if type( result ) == "Character" and result:isPlayer() and sm.game.getEnableAggro() then
				local character = result
				local enterPosition = character.worldPosition
				local sphereNormal = ( enterPosition - trigger:getWorldPosition() ):safeNormalize( sm.vec3.new( 0, 0, -1 ) )
				local knockbackDirection = sm.vec3.new( sphereNormal.x, sphereNormal.y, 0 ):safeNormalize( -character.direction )
				local shieldEffectRotation = sm.vec3.getRotation( sm.vec3.new( 0, 1, 0 ), sphereNormal )
				local forceEffectRotation = sm.vec3.getRotation( sm.vec3.new( 0, 0, 1 ), sphereNormal )
				local effectPos = enterPosition + sphereNormal
				sm.effect.playEffect( "Scannerbot - Shieldbarrierimpact", effectPos, nil, shieldEffectRotation )
				sm.effect.playEffect( "Scannerbot - Shieldbarrierplayerimpact", effectPos, nil, forceEffectRotation )
				character:setTumbling( true )
				local knockbackParams = { character = character, knockbackDirection = knockbackDirection }
				self.network:sendToClients( "cl_n_characterTumbleKnockback", knockbackParams )
			end
		end
	end
end

--[[ Client ]]
function ScannerbotCharacter.client_onCreate( self )
	self.cl = {}
	self.cl.animations = {}
	self.cl.behaviour = ScannerbotManager.Cl_GetBehaviour()

	if self.shieldSphereTrigger == nil then
		self.shieldSphereTrigger = sm.areaTrigger.createSphere( InnerSphereRadius, self.character.worldPosition, sm.quat.identity(), sm.areaTrigger.filter.dynamicBody + sm.areaTrigger.filter.character )
		self.shieldSphereTrigger:setShapeDetection( true )
	end
	self.shieldSphereTrigger:bindOnProjectile( "cl_trigger_onProjectileShield" )
	self:cl_updateTriggerTransforms()
	self.character.clientPublicData = {}

	self.cl.idleEffect = sm.effect.createEffect( "Scannerbot - Idle", self.character )
	self.cl.aggroEffect = sm.effect.createEffect( "Scannerbot - Aggro", self.character )
	self.cl.pingTimer = 0.0
end

function ScannerbotCharacter.client_onDestroy( self )
	if self.cl.renderSettingsVolume then
		RenderSettingsManager.Cl_RemoveAreaTriggerRenderSettings( self.cl.renderSettingsVolume )
		sm.areaTrigger.destroy( self.cl.renderSettingsVolume )
	end
	if self.shieldSphereTrigger then
		sm.areaTrigger.destroy( self.shieldSphereTrigger )
	end
end

function ScannerbotCharacter.client_onGraphicsLoaded( self )
	self:cl_initAnimations()
	self.character:setGlowMultiplier( 1 )
	self.character:setMovementEffects( "$CHALLENGE_DATA/Character/Char_builderbot/builderbot_movement_effects.json" )
	self.cl.scannerEffect = sm.effect.createEffect( "Scannerbot - Lightbeam", self.character )
	self.cl.scannerEffect:setOffsetPosition( sm.vec3.new( 0, -14.5, 0.25 ) ) -- under
	self.cl.scannerEffect:setHostAxisIgnore( sm.effect.axis.yaxis )
	self.cl.thrusterEffect = sm.effect.createEffect( "Scannerbot - Thruster", self.character )
	self.cl.thrusterEffect:setOffsetPosition( sm.vec3.new( 0, -14.5, 0.25 ) )

	self.cl.lightEffect = sm.effect.createEffect( "Scannerbot - Lights", self.character )
	self.cl.lightEffect:setOffsetPosition( sm.vec3.new( 0, 0, 0 ) )
	self.cl.lightEffect:setOffsetRotation( CharacterRotation )
	self.cl.lightEffect:setHostAxisIgnore( sm.effect.axis.yaxis )

	self.cl.scannerAscendingEffect = sm.effect.createEffect( "Scannerbot - Lightbeams_ascending", self.character )
	self.cl.scannerAscendingEffect:setHostAxisIgnore( sm.effect.axis.yaxis )

	self.cl.scannerDescendingEffect = sm.effect.createEffect( "Scannerbot - Lightbeams_descending", self.character )
	self.cl.scannerDescendingEffect:setHostAxisIgnore( sm.effect.axis.yaxis )

	self:cl_controlEffects()
	self.cl.graphicsLoaded = true
end

function ScannerbotCharacter.client_onGraphicsUnloaded( self )
	self.cl.graphicsLoaded = false

	if self.cl.scannerEffect then
		self.cl.scannerEffect:destroy()
		self.cl.scannerEffect = nil
	end
	if self.cl.thrusterEffect then
		self.cl.thrusterEffect:destroy()
		self.cl.thrusterEffect = nil
	end
	if self.cl.lightEffect then
		self.cl.lightEffect:destroy()
		self.cl.lightEffect = nil
	end
	if self.cl.scannerAscendingEffect then
		self.cl.scannerAscendingEffect:destroy()
		self.cl.scannerAscendingEffect = nil
	end
	if self.cl.scannerDescendingEffect then
		self.cl.scannerDescendingEffect:destroy()
		self.cl.scannerDescendingEffect = nil
	end
end

function ScannerbotCharacter.cl_initAnimations( self )
	if not self.cl.animations.idle then
		self.cl.animations.idle = {
			info = self.character:getAnimationInfo( "idle1" ),
			time = 0,
			weight = 0
		}
	end
	if not self.cl.animations.hatch then
		self.cl.animations.hatch = {
			info = self.character:getAnimationInfo( "add_open" ),
			time = 0,
			weight = 0,
			active = false,
			additive = true
		}
	end

	self.cl.animationsLoaded = true
	self.cl.blendSpeed = 5.0
	self.cl.blendTime = 0.2
end

function ScannerbotCharacter.cl_controlEffects( self )
	local behaviour = ScannerbotManager.Cl_GetBehaviour()
	local isRelocating = isAnyOf( behaviour, { ScannerbotBehaviour.RELOCATE, ScannerbotBehaviour.RELOCATE_ASCEND, ScannerbotBehaviour.RELOCATE_DESCEND } )
	local earlyStartScanEffect = self.cl.descendEffectPlayed and ( not self.cl.scannerDescendingEffect:isPlaying() or self.cl.scannerDescendingEffect:isDone() ) or false
	if isRelocating and not earlyStartScanEffect then
		if self.cl.scannerEffect and self.cl.scannerEffect:isPlaying() then
			-- Hide scanner
			self.cl.scannerEffect:stop()

			if self.cl.renderSettingsVolume then
				RenderSettingsManager.Cl_RemoveAreaTriggerRenderSettings( self.cl.renderSettingsVolume )
				sm.areaTrigger.destroy( self.cl.renderSettingsVolume )
				self.cl.renderSettingsVolume = nil
			end
		end
		if self.cl.lightEffect and self.cl.lightEffect:isPlaying() then
			-- Hide lights
			self.cl.lightEffect:stop()
		end
	else
		if self.cl.scannerEffect and not self.cl.scannerEffect:isPlaying() then
			-- Show scanner
			self.cl.scannerEffect:start()

			if self.cl.renderSettingsVolume == nil then
				self.cl.renderSettingsVolume = sm.areaTrigger.createHull( "$SURVIVAL_DATA/Effects/Meshes/scannerbot/lightbeam_scannerbot.fbx", self.character.worldPosition, sm.quat.identity(), sm.areaTrigger.filter.character )
				self.cl.renderSettingsVolume:setCharacterDetection( true )
				self.cl.renderSettingsVolume:setWorldRotation( sm.quat.fromEuler( sm.vec3.new( 90, 0, 0 ) ) )
				RenderSettingsManager.Cl_AddAreaTriggerRenderSettings( self.cl.renderSettingsVolume, { settings = { settings = { renderSettings = "$GAME_DATA/Render/RenderSettings/Gameplay/gameplay_scannerbot.rendersettings" } } } )
				self.cl.renderSettingsVolume:bindOnEnter( "cl_aggroVolume_onEnter" )
				self.cl.renderSettingsVolume:bindOnExit( "cl_aggroVolume_onExit" )
			end

		end
		if self.cl.lightEffect and not self.cl.lightEffect:isPlaying() then
			-- Show lights
			self.cl.lightEffect:start()
		end
		if self.cl.scannerDescendingEffect and self.cl.scannerDescendingEffect:isPlaying() then
			-- Early abort descend if already started scanning roads
			self.cl.scannerDescendingEffect:stop()
		end
		if not isRelocating then
			self.cl.descendEffectPlayed = nil
		end
	end

	if behaviour ~= self.cl.behaviour then
		self.cl.wantsAscendEffect = behaviour == ScannerbotBehaviour.RELOCATE_ASCEND
		self.cl.wantsDescendEffect = behaviour == ScannerbotBehaviour.RELOCATE_DESCEND
	end
	self.cl.behaviour = behaviour

	local heightAboveGround = ScannerbotManager.Sv_GetHeightAboveGround()
	local readyToStartDescendEffect = heightAboveGround and heightAboveGround <= DescendEffectHeight
	if self.cl.wantsDescendEffect and readyToStartDescendEffect then
		self.cl.wantsDescendEffect = nil
		if self.cl.scannerDescendingEffect and not self.cl.scannerDescendingEffect:isPlaying() then
			self.cl.scannerDescendingEffect:start()
			self.cl.descendEffectPlayed = true
		end
	end

	if self.cl.wantsAscendEffect then
		self.cl.wantsAscendEffect = nil
		if self.cl.scannerAscendingEffect and not self.cl.scannerAscendingEffect:isPlaying() then
			self.cl.scannerAscendingEffect:start()
		end
	end

	if self.cl.thrusterEffect and not self.cl.thrusterEffect:isPlaying() then
		self.cl.thrusterEffect:start()
	end

	self.character.clientPublicData = {
		playingDescendingEffect = self.cl.scannerDescendingEffect and self.cl.scannerDescendingEffect:isPlaying(),
		playingAscendingEffect = self.cl.scannerAscendingEffect and self.cl.scannerAscendingEffect:isPlaying()
	}
end

function ScannerbotCharacter.cl_aggroVolume_onEnter( self, trigger, results )
	if TriggerResultContainsAnyPlayer( results ) then
		if self.cl.aggroEffect and not self.cl.aggroEffect:isPlaying() then
			self.cl.aggroEffect:start()
		end
		sm.effect.playEffect( "Scannerbot - Detected", self.character.worldPosition )
	end
end

function ScannerbotCharacter.cl_aggroVolume_onExit( self, trigger, results )
	if TriggerResultContainsAnyPlayer( results ) then
		if self.cl.aggroEffect and self.cl.aggroEffect:isPlaying() then
			self.cl.aggroEffect:stop()
		end
		sm.effect.playEffect( "Scannerbot - Leaving", self.character.worldPosition )
	end
end

function ScannerbotCharacter.client_onUpdate( self, deltaTime )
	if not self.cl.graphicsLoaded then
		return
	end

	if sm.exists( self.character ) then
		self:cl_controlEffects()
	end
	self.character:setMovementWeights( 0, 0 )
	if self.cl.animations.idle then
		local animation = self.cl.animations.idle
		animation.time = animation.time + deltaTime
		animation.time = animation.time % animation.info.duration
		animation.weight = 1
		self.character:updateAnimation( animation.info.name, animation.time, animation.weight, animation.additive )

		if self.cl.aggroEffect:isPlaying() then
			if self.cl.idleEffect:isPlaying() then
				self.cl.idleEffect:stop()
			end
			self.cl.aggroEffect:setParameter( "velocity", self.character.velocity:length() / self.character:getSprintSpeed() )
		else 
			if not self.cl.idleEffect:isPlaying() then
				self.cl.idleEffect:start()
			end
			self.cl.idleEffect:setParameter( "velocity", self.character.velocity:length() / self.character:getSprintSpeed() )
		end
	else
		if self.cl.idleEffect:isPlaying() then
			self.cl.idleEffect:stop()
		end
	
	end

	self.cl.pingTimer = self.cl.pingTimer + deltaTime
	if self.cl.pingTimer >= PingTime then
		self.cl.pingTimer = 0
		sm.effect.playEffect( "Scannerbot - Ping", self.character.worldPosition )
	end

	if self.cl.animations.hatch then
		local animation = self.cl.animations.hatch
		if animation.active then
			animation.weight = 1.0
			animation.time = math.min( animation.time + deltaTime, animation.info.duration )
		else
			if animation.weight >= 1.0 then
				sm.effect.playEffect( "Scannerbot - HatchClose", self.character.worldPosition )
			end
			animation.weight = math.max( animation.weight - ( self.cl.blendSpeed * deltaTime ), 0.0)
		end
		self.character:updateAnimation( animation.info.name, animation.time, animation.weight, animation.additive )
	end
end

function ScannerbotCharacter.client_onFixedUpdate( self, dt )
	self:cl_updateTriggerTransforms()
	self:cl_shieldPush()
end

function ScannerbotCharacter.cl_updateTriggerTransforms( self )
	local characterPosition = self.character.worldPosition
	local up = sm.vec3.new( 0, 0, 1 )
	if self.cl.renderSettingsVolume then
		local scannerHeightOffset = up * ScanTriggerHeightOffset
		local scannerWorldPosition = characterPosition + scannerHeightOffset
		self.cl.renderSettingsVolume:setWorldPosition( scannerWorldPosition )
	end
	if self.shieldSphereTrigger then
		local innerSphereHeightOffset = up * -3
		local innerSphereWorldPosition = characterPosition + innerSphereHeightOffset
		self.shieldSphereTrigger:setWorldPosition( innerSphereWorldPosition )
	end
end

function ScannerbotCharacter.cl_shieldPush( self )
	local pushedBodies = {}
	local shieldShapeCollisions = self.shieldSphereTrigger:getShapes()
	for _, shapeCollision in ipairs( shieldShapeCollisions ) do
		local hitShape = shapeCollision.shape
		if sm.exists( hitShape ) then
			if not pushedBodies[hitShape.body.id] then
				pushedBodies[hitShape.body.id] = true
				local sphereNormal = ( shapeCollision.shapeWorldPosition - self.shieldSphereTrigger:getWorldPosition() ):safeNormalize( sm.vec3.new( 0, 0, -1 ) )
				local impulse = sphereNormal * hitShape.body.mass
				sm.physics.applyImpulse( hitShape, impulse, true )
			end
		end
	end
end

function ScannerbotCharacter.cl_n_characterTumbleKnockback( self, params )
	local massImpulse = CharacterKnockback / ( 5000.0 / 10.0 )
	local massImpulseSqrt = CharacterKnockback / ( 5000.0 / 12.0 )
	local impulse = math.min( params.character.mass * massImpulse + math.sqrt( params.character.mass ) * massImpulseSqrt, CharacterKnockback )
	impulse = math.min( impulse, MAX_CHARACTER_KNOCKBACK_VELOCITY * params.character.mass )
	params.character:applyTumblingImpulse( params.knockbackDirection * impulse )
end

function ScannerbotCharacter.cl_trigger_onProjectileShield( self, trigger, hitPos, hitTime, hitVelocity, _, attacker, damage, userData, hitNormal, projectileUuid )
	-- Shield effect
	local sphereNormal = ( hitPos - trigger:getWorldPosition() ):safeNormalize( sm.vec3.new( 0, 0, -1 ) )
	local shieldMargin = 0.1
	local effectForward = sm.vec3.new( 0, 1, 0 )
	local effectRotation = sm.vec3.getRotation( effectForward, sphereNormal )
	local effectPos = hitPos + sphereNormal * shieldMargin
	sm.effect.playEffect( "Scannerbot - Shieldbarrierimpact", effectPos, nil, effectRotation )

	return true
end

function ScannerbotCharacter.sv_trigger_onProjectileShield( self, trigger, hitPos, hitTime, hitVelocity, _, attacker, damage, userData, hitNormal, projectileUuid )
	-- Detect player attack
	if attacker and sm.exists( attacker ) then
		if type( attacker ) == "Player" then
			local playerCharacter = attacker.character
			if sm.exists( playerCharacter ) then
				ScannerbotManager.Sv_AddTargets( { [playerCharacter.id] = playerCharacter } )
			end
		end
	end

	return false
end

function ScannerbotCharacter.client_onEvent( self, event )
	self:cl_handleEvent( event )
end

function ScannerbotCharacter.cl_handleEvent( self, event )
	if not self.cl.animationsLoaded then return end

	if event == "openHatch" then
		self.cl.animations.hatch.active = true
		self.cl.animations.hatch.time = 0
	elseif event == "closeHatch" then
		self.cl.animations.hatch.active = false
		self.cl.animations.hatch.time = self.cl.animations.hatch.info.duration
	end

end