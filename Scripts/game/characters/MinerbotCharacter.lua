dofile "$SURVIVAL_DATA/Scripts/game/characters/BaseEnemyCharacter.lua"
MinerbotCharacter = class( BaseEnemyCharacter )

local alertRenderableTp = "$SURVIVAL_DATA/Character/Char_Minerbot/char_minerbot_alert.rend"
local roamingRenderableTp = "$SURVIVAL_DATA/Character/Char_Minerbot/char_minerbot_roaming.rend"
sm.character.preloadRenderables( { alertRenderableTp, roamingRenderableTp } )

local alertMovementEffects = "$CHALLENGE_DATA/Character/Char_builderbot/builderbot_movement_effects.json"
local roamingMovementEffects = "$CHALLENGE_DATA/Character/Char_builderbot/builderbot_movement_effects.json"

local LookMaxRadiansPerSecond = math.rad( 75 )
local HeadTriggerSize = sm.vec3.new( 0.4, 0.35, 0.4 )
local HeadTriggerOffset = sm.vec3.new( 0, 0.0625, 0.22 )

local GroundCheckDistance = 1.5
local GroundCheckRadius = 0.25
local GroundEffectVelocityThreshold2 = 2.0 * 2.0

local BurstMinInterval = 0.8
local BurstMaxInterval = 1.2

function MinerbotCharacter.server_onCreate( self )
	self.character:setFlying( true )
end

function MinerbotCharacter.client_onCreate( self )
	self.cl = {}
	self.cl.animations = {}
	self.cl.animationSwitches = {}
	self.cl.currentAnimationSet = roamingRenderableTp
	self.cl.currentMovementEffects = roamingMovementEffects
	self.cl.effects = {}
	self.cl.target = nil
	self.cl.nearGround = false
	self.cl.lookDirection = self.character.direction:safeNormalize( sm.vec3.new( 0, 1, 0 ) )
	self.cl.lookingAtTarget = true -- TODO remove if always looking
	self.cl.headUpDownFraction = 0.5
	self.cl.headLeftRightFraction = 0.5
	self.cl.blendSpeed = 5.0
	self.cl.blendTime = 0.2
	self.cl.currentAnimation = ""
	self.cl.burstEffectCooldown = 0.0
end

function MinerbotCharacter.client_onGraphicsLoaded( self )
	self.character:addRenderable( self.cl.currentAnimationSet )
	self.character:setMovementEffects( self.cl.currentMovementEffects )
	self:cl_initGraphics()
	self:cl_initAnimationSwitch()
	self.character:setGlowMultiplier( 1 )

	self.cl.groundContactEffect = sm.effect.createEffect( "Minerbot - Groundcontact", self.character, "wheel_jnt" )
	self.cl.wheelSpinEffect = sm.effect.createEffect( "Minerbot - Wheelspin", self.character, "wheel_jnt" )
	self.cl.crashingFireballEffect = sm.effect.createEffect( "Minerbot - Deathcrash_fireballtrail", self.character, "center_jnt" )
	self.cl.leftThrusterEffect = sm.effect.createEffect( "Minerbot - Thruster_l", self.character, "pejnt_l_thruster" )
	self.cl.rightThrusterEffect = sm.effect.createEffect( "Minerbot - Thruster_r", self.character, "pejnt_r_thruster" )
	self.cl.engineEffect = sm.effect.createEffect( "Minerbot - Engine", self.character, "torso2_jnt" )
	self:cl_controlThrusterEffects()

	local headPosition = self.character:getTpBonePos( "head_jnt" )
	local headRotation = self.character:getTpBoneRot( "head_jnt" )
	self.cl.headAreaTrigger = sm.areaTrigger.createBox( HeadTriggerSize, headPosition + headRotation * HeadTriggerOffset, headRotation )
	self.cl.headAreaTrigger:bindOnProjectile( "trigger_onProjectile", self )

	self.cl.graphicsLoaded = true
end

function MinerbotCharacter.client_onGraphicsUnloaded( self )
	self.cl.graphicsLoaded = false

	if self.cl.wheelSpinEffect then
		self.cl.wheelSpinEffect:destroy()
		self.cl.wheelSpinEffect = nil
	end
	if self.cl.crashingFireballEffect then
		self.cl.crashingFireballEffect:destroy()
		self.cl.crashingFireballEffect = nil
	end
	if self.cl.leftThrusterEffect then
		self.cl.leftThrusterEffect:destroy()
		self.cl.leftThrusterEffect = nil
	end
	if self.cl.rightThrusterEffect then
		self.cl.rightThrusterEffect:destroy()
		self.cl.rightThrusterEffect = nil
	end
	if self.cl.engineEffect then
		self.cl.engineEffect:destroy()
		self.cl.engineEffect = nil
	end
	
	if sm.exists( self.cl.headAreaTrigger ) then
		sm.areaTrigger.destroy( self.cl.headAreaTrigger )
		self.cl.headAreaTrigger = nil
	end
end

function MinerbotCharacter.cl_initGraphics( self )
	if not self.cl.animations.shootIn then
		self.cl.animations.shootIn = {
			info = self.character:getAnimationInfo( "shoot_in" ),
			time = 0,
			weight = 0,
			onAnimationEnd = function( self )
				self.cl.animations.shootLoop.active = true
				self.cl.animations.shootLoop.time = 0
				self.cl.animations.shootWheelLoop.active = true
				self.cl.animations.shootWheelLoop.time = 0
			end
		}
	end
	if not self.cl.animations.shootLoop then
		self.cl.animations.shootLoop = {
			info = self.character:getAnimationInfo( "shoot_loop" ),
			time = 0,
			weight = 0,
			looping = true
		}
	end
	if not self.cl.animations.shootWheelLoop then
		self.cl.animations.shootWheelLoop = {
			info = self.character:getAnimationInfo( "shoot_wheel_loop" ),
			time = 0,
			weight = 0,
			looping = true,
			additive = true
		}
	end
	if not self.cl.animations.shootOut then
		self.cl.animations.shootOut = {
			info = self.character:getAnimationInfo( "shoot_out" ),
			time = 0,
			weight = 0
		}
	end

	if not self.cl.animations.destroyWindup then
		self.cl.animations.destroyWindup = {
			info = self.character:getAnimationInfo( "die" ),
			time = 0,
			weight = 0,
		}
	end
	if not self.cl.animations.destroy then
		self.cl.animations.destroy = {
			info = self.character:getAnimationInfo( "destruct" ),
			time = 0,
			weight = 0,
			looping = true
		}
	end
	if not self.cl.animations.idlespecial01 then
		self.cl.animations.idlespecial01 = {
			info = self.character:getAnimationInfo( "idlespecial01" ),
			time = 0,
			weight = 0
		}
	end
	if not self.cl.animations.idlespecial02 then
		self.cl.animations.idlespecial02 = {
			info = self.character:getAnimationInfo( "idlespecial02" ),
			time = 0,
			weight = 0
		}
	end
	if not self.cl.animations.idlespecial03 then
		self.cl.animations.idlespecial03 = {
			info = self.character:getAnimationInfo( "idlespecial03" ),
			time = 0,
			weight = 0
		}
	end
	if not self.cl.animations.idlealert then
		self.cl.animations.idlealert = {
			info = self.character:getAnimationInfo( "idlealert" ),
			time = 0,
			weight = 0
		}
	end
	if not self.cl.animations.hithead then
		self.cl.animations.hithead = {
			info = self.character:getAnimationInfo( "hit_head" ),
			time = 0,
			weight = 0
		}
	end
	if not self.cl.animations.hitleft then
		self.cl.animations.hitleft = {
			info = self.character:getAnimationInfo( "hit_left" ),
			time = 0,
			weight = 0
		}
	end
	if not self.cl.animations.hitright then
		self.cl.animations.hitright = {
			info = self.character:getAnimationInfo( "hit_right" ),
			time = 0,
			weight = 0
		}
	end
	if not self.cl.animations.spawn_bossfight then
		self.cl.animations.spawn_bossfight = {
			info = self.character:getAnimationInfo( "spawn_bossfight" ),
			time = 0,
			weight = 0
		}
	end

	self.animationsLoaded = true
end

function MinerbotCharacter.cl_initAnimationSwitch( self )
	self.cl.animationSwitches.alerted = {
		info = self.character:getAnimationInfo( "toalert" ),
		time = 0,
		weight = 0,
		triggeredEvent = false
	}
	self.cl.animationSwitches.roaming = {
		info = self.character:getAnimationInfo( "toroam" ),
		time = 0,
		weight = 0,
		triggeredEvent = false
	}
	self.cl.currentSwitch = ""
end

function MinerbotCharacter.cl_controlThrusterEffects( self )
	if self.character:isTumbling() or not self.character:isVisible() then
		if self.cl.leftThrusterEffect and self.cl.leftThrusterEffect:isPlaying() then
			self.cl.leftThrusterEffect:stop()
		end
		if self.cl.rightThrusterEffect and self.cl.rightThrusterEffect:isPlaying() then
			self.cl.rightThrusterEffect:stop()
		end
		if self.cl.engineEffect and self.cl.engineEffect:isPlaying() then
			self.cl.engineEffect:stop()
		end
	else
		if self.cl.leftThrusterEffect and not self.cl.leftThrusterEffect:isPlaying() then
			self.cl.leftThrusterEffect:start()
		end
		if self.cl.rightThrusterEffect and not self.cl.rightThrusterEffect:isPlaying() then
			self.cl.rightThrusterEffect:start()
		end
		if self.cl.engineEffect and not self.cl.engineEffect:isPlaying() then
			self.cl.engineEffect:start()
		end
	end
end

function MinerbotCharacter.cl_onAnimationEnd( self, name )
	local animation = self.cl.animations[name]
	if animation and animation.onAnimationEnd then
		animation.onAnimationEnd( self )
	end
end

function MinerbotCharacter.client_onFixedUpdate( self )
	if not self.cl.graphicsLoaded then
		self.cl.nearGround = false
		return
	end

	local from = self.character.worldPosition
	local to = from + sm.vec3.new( 0, 0, -GroundCheckDistance )
	local groundFilter = bit.bor( sm.physics.filter.terrainSurface, sm.physics.filter.terrainAsset, sm.physics.filter.voxelTerrain )
	local hit, result = sm.physics.spherecast( from, to, GroundCheckRadius, self.character, groundFilter )
	if hit then
		self.cl.nearGround = true
	else
		self.cl.nearGround = false
	end
end

function MinerbotCharacter.client_onUpdate( self, deltaTime )
	if not self.cl.graphicsLoaded then
		return
	end

	if sm.exists( self.character ) then
		self:cl_controlThrusterEffects()
		if not self.character:isVisible() and self.cl.animations.spawn_bossfight.time >= 0.5 then
			self.character:setVisible( true )
		end

		self.cl.engineEffect:setParameter( "speed", clamp( self.character.velocity:length() / self.character:getSprintSpeed() * 10.0, 0.0, 10.0 ) )

		self.cl.burstEffectCooldown = math.max( self.cl.burstEffectCooldown - deltaTime, 0.0 )

		--Update head trigger
		if self.cl.headAreaTrigger then
			local headPosition = self.character:getTpBonePos( "head_jnt" )
			local headRotation = self.character:getTpBoneRot( "head_jnt" )
			self.cl.headAreaTrigger:setWorldPosition( headPosition + headRotation * HeadTriggerOffset )
			self.cl.headAreaTrigger:setWorldRotation( headRotation )
		end

		-- Toggle fireball crash effect
		if self.cl.animations.destroy.active then
			if not self.cl.crashingFireballEffect:isPlaying() then
				self.cl.crashingFireballEffect:start()
			end
		else
			if self.cl.crashingFireballEffect:isPlaying() then
				self.cl.crashingFireballEffect:stop()
			end
		end
		-- Toggle wheelspin effect
		if self.cl.animations.shootWheelLoop.active then
			if not self.cl.wheelSpinEffect:isPlaying() then
				self.cl.wheelSpinEffect:start()
			end
		else
			if self.cl.wheelSpinEffect:isPlaying() then
				self.cl.wheelSpinEffect:stop()
			end
		end
		-- Toggle groundeffect
		local playGroundEffect = false
		if self.cl.nearGround then
			local planeVelocity = sm.vec3.new( self.character.velocity.x, self.character.velocity.y, 0 )
			playGroundEffect = planeVelocity:length2() >= GroundEffectVelocityThreshold2
		end
		if playGroundEffect then
			if not self.cl.groundContactEffect:isPlaying() then
				self.cl.groundContactEffect:start()
			end
		else
			if self.cl.groundContactEffect:isPlaying() then
				self.cl.groundContactEffect:stop()
			end
		end

		-- Update look direction and spine bending animations
		local headPosition = self.character.worldPosition + sm.vec3.new( 0, 0, 2 )
		if self.cl.target and sm.exists( self.cl.target ) and self.cl.lookingAtTarget then
			local fromToTarget = self.cl.target.worldPosition - headPosition
			local flatFromToTarget = sm.vec3.new( fromToTarget.x, fromToTarget.y, 0 )
			local wantedFlatLookDirection = flatFromToTarget:safeNormalize( self.cl.lookDirection )

			-- Radians to rotate this step
			local radiansToRotate = math.acos( clamp( self.cl.lookDirection:dot( wantedFlatLookDirection ), -1, 1 ) )
			local rotationStep = math.min( LookMaxRadiansPerSecond * deltaTime, radiansToRotate )

			-- Find which direction to rotate
			local rotationZ = 0.0
			local determinant = wantedFlatLookDirection.x * self.cl.lookDirection.y - wantedFlatLookDirection.y * self.cl.lookDirection.x
			if determinant <= -FLT_EPSILON then
				rotationZ = rotationStep
			elseif determinant >= FLT_EPSILON then
				rotationZ = -rotationStep
			end
			-- Update look direction
			self.cl.lookDirection = ( self.cl.lookDirection:rotateZ( rotationZ ) ):safeNormalize( self.cl.lookDirection )

			-- Update spine bend up/down
			local targetLookDirection = ( fromToTarget ):safeNormalize( self.cl.lookDirection )
			local upDownAngleFraction = math.asin( targetLookDirection:dot( sm.vec3.new( 0, 0, 1 ) ) ) / ( math.pi / 2 )
			local desiredUpDownAnimationFraction = ( 0.5 + upDownAngleFraction * 0.5 )
			self.cl.headUpDownFraction = magicInterpolation( self.cl.headUpDownFraction, desiredUpDownAnimationFraction, deltaTime, 1.0 / 8.0 )

			-- Update spine bend right/left
			local rightLeftAngle = math.acos( clamp( self.cl.lookDirection:dot( wantedFlatLookDirection ), -1, 1 ) )
			local spineDeterminant = wantedFlatLookDirection.x * self.cl.lookDirection.y - wantedFlatLookDirection.y * self.cl.lookDirection.x
			if spineDeterminant >= FLT_EPSILON then
				rightLeftAngle = -rightLeftAngle
			end
			local rightLeftAngleFraction = clamp( rightLeftAngle / ( math.pi / 2 ), -1, 1 )
			local desiredRightLeftAnimationFraction = ( 0.5 + rightLeftAngleFraction * 0.5 )
			self.cl.headLeftRightFraction = magicInterpolation( self.cl.headLeftRightFraction, desiredRightLeftAnimationFraction, deltaTime, 1.0 / 15.0 )
		else
			self.cl.headUpDownFraction = magicInterpolation( self.cl.headUpDownFraction, 0.5, deltaTime, 1.0 / 8.0 )
			self.cl.headLeftRightFraction = magicInterpolation( self.cl.headLeftRightFraction, 0.5, deltaTime, 1.0 / 15.0 )
		end

		self.character:updateAnimation( "bend_updown", 1.0 - self.cl.headUpDownFraction, 1.0, true )
		self.character:updateAnimation( "bend_leftright", 1.0 - self.cl.headLeftRightFraction, 1.0, true )

		-- Update animations
		for name, animation in pairs( self.cl.animations ) do
			if animation.info then
				animation.time = animation.time + deltaTime
				if name == self.cl.currentAnimation then
					animation.weight = math.min(animation.weight+(self.cl.blendSpeed * deltaTime), 1.0)
					if animation.time >= animation.info.duration then
						self.cl.currentAnimation = ""
					end
				elseif animation.active then
					animation.weight = math.min(animation.weight+(self.cl.blendSpeed * deltaTime), 1.0)
					if animation.time >= animation.info.duration then
						if animation.looping then
							animation.time = animation.time % animation.info.duration
						else
							self.cl.animations[name].active = false
						end

						self:cl_onAnimationEnd( name )
					end
				else
					animation.weight = math.max(animation.weight-( self.cl.blendSpeed * deltaTime ), 0.0)
				end
				self.character:updateAnimation( animation.info.name, animation.time, animation.weight, animation.additive )
			end
		end

		-- Update state change
		for name, animationSwitch in pairs( self.cl.animationSwitches ) do
			if animationSwitch.info then
				animationSwitch.time = animationSwitch.time + deltaTime
				if name == self.cl.currentSwitch then
					animationSwitch.weight = math.max( 1 - 2 * math.abs( ( animationSwitch.time / animationSwitch.info.duration ) - 0.5 ), 0 )
					if animationSwitch.time >= animationSwitch.info.duration * 0.5 and not animationSwitch.triggeredEvent then
						animationSwitch.triggeredEvent = true
						if name == "alerted" then
							if self.cl.currentAnimationSet ~= alertRenderableTp then
								self.character:removeRenderable( self.cl.currentAnimationSet )
								self.cl.currentAnimationSet = alertRenderableTp
								self.character:addRenderable( self.cl.currentAnimationSet )
								self:cl_initGraphics()
								self.cl.currentMovementEffects = alertMovementEffects
								self.character:setMovementEffects( self.cl.currentMovementEffects )
							end
						elseif name == "roaming" then
							if self.cl.currentAnimationSet ~= roamingRenderableTp then
								self.character:removeRenderable( self.cl.currentAnimationSet )
								self.cl.currentAnimationSet = roamingRenderableTp
								self.character:addRenderable( self.cl.currentAnimationSet )
								self:cl_initGraphics()
								self.cl.currentMovementEffects = roamingMovementEffects
								self.character:setMovementEffects( self.cl.currentMovementEffects )
							end
						end
					end

					if animationSwitch.time >= animationSwitch.info.duration then
						self.cl.currentSwitch = ""
						animationSwitch.time = 0
						animationSwitch.weight = 0
						animationSwitch.triggeredEvent = false
					end
				else
					animationSwitch.time = 0
					animationSwitch.weight = 0
					animationSwitch.triggeredEvent = false
				end
				self.character:updateAnimation( animationSwitch.info.name, animationSwitch.time, animationSwitch.weight )
			end
		end

















	g_ambienceManager:triggerCombatMusicForTarget( self.cl.target )
	end
end

function MinerbotCharacter.client_onEvent( self, event )
	self:cl_handleEvent( event )
end

function MinerbotCharacter.cl_handleEvent( self, event )
	if not self.animationsLoaded then
		return
	end

	if event == "startbarrage" then
		self.cl.animations.shootIn.active = true
		self.cl.animations.shootIn.time = 0

		self.cl.animations.shootLoop.active = false
		self.cl.animations.shootLoop.time = 0
		self.cl.animations.shootWheelLoop.active = false
		self.cl.animations.shootWheelLoop.time = 0
		self.cl.animations.shootOut.active = false
		self.cl.animations.shootOut.time = 0
	elseif event == "stopbarrage" then
		self.cl.animations.shootOut.active = true
		self.cl.animations.shootOut.time = 0

		self.cl.animations.shootIn.active = false
		self.cl.animations.shootIn.time = 0
		self.cl.animations.shootLoop.active = false
		self.cl.animations.shootLoop.time = 0
		self.cl.animations.shootWheelLoop.active = false
		self.cl.animations.shootWheelLoop.time = 0
	elseif event == "idlespecial01" then
		self.cl.animations.idlespecial01.active = true
		self.cl.animations.idlespecial01.time = 0
	elseif event == "idlespecial02" then
		self.cl.animations.idlespecial02.active = true
		self.cl.animations.idlespecial02.time = 0
	elseif event == "idlespecial03" then
		self.cl.animations.idlespecial03.active = true
		self.cl.animations.idlespecial03.time = 0
	elseif event == "idlealert" then
		self.cl.animations.idlealert.active = true
		self.cl.animations.idlealert.time = 0
	elseif event == "burst" then
		if self.cl.burstEffectCooldown < FLT_EPSILON then
			self.cl.burstEffectCooldown = BurstMinInterval + math.random() * ( BurstMaxInterval - BurstMinInterval )
			if self.cl.graphicsLoaded then
				sm.effect.playHostedEffect( "Minerbot - Burst02", self.character, "root_jnt" )
			end
		end
	elseif event == "burst01left" then
		if self.cl.burstEffectCooldown < FLT_EPSILON then
			self.cl.burstEffectCooldown = BurstMinInterval + math.random() * ( BurstMaxInterval - BurstMinInterval )
			if self.cl.graphicsLoaded then
				sm.effect.playHostedEffect( "Minerbot - Burst01", self.character, "l_thruster_jnt" )
			end
		end
	elseif event == "burst01right" then
		if self.cl.burstEffectCooldown < FLT_EPSILON then
			self.cl.burstEffectCooldown = BurstMinInterval + math.random() * ( BurstMaxInterval - BurstMinInterval )
			if self.cl.graphicsLoaded then
				sm.effect.playHostedEffect( "Minerbot - Burst01", self.character, "r_thruster_jnt" )
			end
		end
	elseif event == "burst02left" then
		if self.cl.burstEffectCooldown < FLT_EPSILON then
			self.cl.burstEffectCooldown = BurstMinInterval + math.random() * ( BurstMaxInterval - BurstMinInterval )
			if self.cl.graphicsLoaded then
				sm.effect.playHostedEffect( "Minerbot - Burst02", self.character, "l_thruster_jnt" )
			end
		end
	elseif event == "burst02right" then
		if self.cl.burstEffectCooldown < FLT_EPSILON then
			self.cl.burstEffectCooldown = BurstMinInterval + math.random() * ( BurstMaxInterval - BurstMinInterval )
			if self.cl.graphicsLoaded then
				sm.effect.playHostedEffect( "Minerbot - Burst02", self.character, "r_thruster_jnt" )
			end
		end
	elseif event == "hithead" then
		self.cl.animations.hithead.active = true
		self.cl.animations.hithead.time = 0
	elseif event == "hitleft" then
		self.cl.animations.hitleft.active = true
		self.cl.animations.hitleft.time = 0
	elseif event == "hitright" then
		self.cl.animations.hitright.active = true
		self.cl.animations.hitright.time = 0
	elseif event == "destroywindup" then
		self.cl.animations.destroyWindup.active = true
		self.cl.animations.destroyWindup.time = 0
		self.cl.animations.destroy.active = false
		self.cl.animations.destroy.time = 0
		if self.cl.graphicsLoaded then
			sm.effect.playHostedEffect( "Minerbot - Death01", self.character, "root_jnt" )
		end
	elseif event == "destroy" then
		self.cl.animations.destroy.active = true
		self.cl.animations.destroy.time = 0
		self.cl.animations.destroyWindup.active = false
		self.character:setMovementWeights( 0, 0 )
	elseif event == "spawnAnimation" then
		self.cl.animations.spawn_bossfight.active = true
		self.cl.animations.spawn_bossfight.time = 0
		self.cl.animations.spawn_bossfight.weight = 1.0
	elseif event == "alert" then
		if self.cl.animationSwitches.alerted then
			self.cl.currentSwitch = "alerted"
			self.cl.animationSwitches.alerted.time = 0
			self.cl.animationSwitches.alerted.triggeredEvent = false
			self.cl.currentAnimation = ""
		end
	elseif event == "calm" then
		if self.cl.animationSwitches.roaming then
			self.cl.currentSwitch = "roaming"
			self.cl.animationSwitches.roaming.time = 0
			self.cl.animationSwitches.roaming.triggeredEvent = false
			self.cl.currentAnimation = ""
		end
	end
end

function MinerbotCharacter.sv_e_updateTarget( self, params )
	self.network:sendToClients( "cl_n_updateTarget", params )
end

function MinerbotCharacter.cl_n_updateTarget( self, params )
	self.cl.target = params.target
end

function MinerbotCharacter.sv_n_hitHead( self, params )
	local unit = self.character:getUnit()
	if sm.exists( unit ) then
		sm.event.sendToUnit( unit, "sv_e_hitHead", params )
	end
end

function MinerbotCharacter.trigger_onProjectile( self, trigger, hitPos, hitTime, hitVelocity, _, attacker, damage, userData, hitNormal, projectileUuid )

	if type( attacker ) == "Player" or type( attacker ) == "Shape" then
		if damage > 0 then
			local up = sm.vec3.new( 0, 0, 1 )
			local normal = ( -hitVelocity ):safeNormalize( self.cl.lookDirection )
			sm.effect.playEffect( "Minerbot - Spudgunimpact Headshot", hitPos, nil, sm.vec3.getRotation( up, normal ) )
			if sm.isHost then
				-- Switch to server sandbox
				self.network:sendToServer( "sv_n_hitHead", { hitPos = hitPos, damage = damage, hitVelocity = hitVelocity } )
			end
		end
	end

	-- Destroy projectile
	return true
end

function MinerbotCharacter.sv_e_updateDamage( self, params )
	self.network:sendToClients( "cl_n_updateDamage", params )
end

function MinerbotCharacter.cl_n_updateDamage( self, params )
	self.cl.engineEffect:setParameter( "damage", params.damage )
end
