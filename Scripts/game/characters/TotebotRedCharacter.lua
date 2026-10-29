dofile "$SURVIVAL_DATA/Scripts/game/characters/TotebotCharacter.lua"

TotebotRedCharacter = class( TotebotCharacter )

local RegularSpeed = 1.0
local ChaseSpeed = 1.1
local MovementSpeedIncreaseTicks = math.floor( 1.2 * 40 )

local animationSets = {
	alert = "$SURVIVAL_DATA/Character/Char_totebot_red/char_totebot_red_alert.rend",
	roaming = "$SURVIVAL_DATA/Character/Char_totebot_red/char_totebot_red_roaming.rend"
}
sm.character.preloadRenderables( { animationSets.alert, animationSets.roaming } )

function TotebotRedCharacter.sv_e_beginExplosionRun( self )
	self.network:setClientData( { serverTick = sm.game.getServerTick(), chase = true }, 2 )
end

function TotebotRedCharacter.sv_e_extinguish( self )
	self.network:setClientData( { chase = false }, 2 )
end

function TotebotRedCharacter.cl_changeAnimationSet( self, animationSet )
	self.character:removeRenderable( animationSets[self.cl.currentAnimationSet] )
	self.cl.currentAnimationSet = animationSet
	self.character:addRenderable( animationSets[self.cl.currentAnimationSet] )
end

function TotebotRedCharacter.client_onCreate( self )
	TotebotCharacter.client_onCreate( self )

	self.ignited = false
	self.currentSpeed = RegularSpeed
	self.speedIncreaseTickCounter = 0
	self.isChasing = false
end

function TotebotRedCharacter.client_onGraphicsLoaded( self )

	self.character:addRenderable( animationSets[self.cl.currentAnimationSet] )
	self:cl_initGraphics()
	self:cl_initAnimationSwitch()
	self.character:setGlowMultiplier( 1 )
	self.graphicsLoaded = true

	self.cl.alertedEffect = sm.effect.createEffect( "ToteBotRed - Alerted", self.character, "jnt_head" )

	self.cl.igniteEffect = sm.effect.createEffect( "Totebotred - Ignite", self.character, "root_jnt" )
	self.cl.igniteEffect:setOffsetRotation( sm.quat.fromEuler( sm.vec3.new( -90, 0, 0 ) ) )
	self.cl.igniteEffect:setOffsetPosition( sm.vec3.new( 0, 0.0, 0 ) )

	self.cl.gasLeakEffect = sm.effect.createEffect( "Totebotred - Gasleak", self.character, "barrel2_jnt" )
	self.cl.gasLeakEffect:setOffsetRotation( sm.quat.fromEuler( sm.vec3.new( -90, 0, 0 ) ) )
	self.cl.gasLeakEffect:setOffsetPosition( sm.vec3.new( 0, 0.0, 0 ) )

	if self.ignited then
		if not self.cl.gasLeakEffect:isPlaying() then
			self.cl.gasLeakEffect:start()
		end
	end

	self.cl.preExplodeEffect = sm.effect.createEffect( "Totebotred - Prexplode", self.character, "root_jnt" )
	self.cl.preExplodeEffect:setOffsetRotation( sm.quat.fromEuler( sm.vec3.new( -90, 0, 0 ) ) )
	self.cl.preExplodeEffect:setOffsetPosition( sm.vec3.new( 0, 0.0, 0 ) )
end

function TotebotRedCharacter.client_onGraphicsUnloaded( self )
	self.graphicsLoaded = false

	if self.cl.alertedEffect then
		self.cl.alertedEffect:destroy()
		self.cl.alertedEffect = nil
	end
	if self.cl.igniteEffect then
		self.cl.igniteEffect:destroy()
		self.cl.igniteEffect = nil
	end
	if self.cl.gasLeakEffect then
		self.cl.gasLeakEffect:destroy()
		self.cl.gasLeakEffect = nil
	end
	if self.cl.preExplodeEffect then
		self.cl.preExplodeEffect:destroy()
		self.cl.preExplodeEffect = nil
	end
end

function TotebotRedCharacter.cl_initGraphics( self )
	if not self.cl.animations.ignite then
		self.cl.animations.ignite = {
			info = self.character:getAnimationInfo( "ignite" ),
			time = 0,
			weight = 0,
			active = false
		}
	end
	if not self.cl.animations.preexplode_start then
		self.cl.animations.preexplode_start = {
			info = self.character:getAnimationInfo( "preexplode_start" ),
			time = 0,
			weight = 0,
			active = false,
			nextAnimation = "preexplode_loop"
		}
	end
	if not self.cl.animations.preexplode_loop then
		self.cl.animations.preexplode_loop = {
			info = self.character:getAnimationInfo( "preexplode_loop" ),
			time = 0,
			weight = 0,
			active = false,
			loopTime = 3,
			loopTimer = 0,
			nextAnimation = "preexplode_end"
		}
	end
	if not self.cl.animations.preexplode_end then
		self.cl.animations.preexplode_end = {
			info = self.character:getAnimationInfo( "preexplode_end" ),
			time = 0,
			weight = 0,
			active = false
		}
	end
	if not self.cl.animations.explode_wind_up then
		self.cl.animations.explode_wind_up = {
			info = self.character:getAnimationInfo( "preexplode_add" ),
			time = 0,
			weight = 0,
			active = false,
			additive = true,
			loopTime = 3,
			loopTimer = 0,
		}
	end
	self.character:setMovementEffects( "$SURVIVAL_DATA/Character/Char_Totebot/movement_effects.json" )
	self.animationsLoaded = true
end

function TotebotRedCharacter.cl_handleEvent( self, event )
	if not self.animationsLoaded then
		return
	end
	if sm.exists( self.character ) then
		if event == "alerted" then
			if self.cl.animationSwitches.alerted then
				self.cl.currentSwitch = "alerted"
				self.cl.animationSwitches.alerted.time = 0
				self.cl.animationSwitches.alerted.triggeredEvent = false
				if self.graphicsLoaded then
					self.cl.alertedEffect:start()
				end
			end
		elseif event == "roaming" then
			if self.cl.animationSwitches.roaming then
				self.cl.currentSwitch = "roaming"
				self.cl.animationSwitches.roaming.time = 0
				self.cl.animationSwitches.roaming.triggeredEvent = false
			end
		elseif event == "ignite" then
			self.cl.animations.ignite.time = 0
			self.cl.animations.ignite.active = true
			self.cl.animations.preexplode_start.active = false
			self.cl.animations.preexplode_loop.active = false
			self.cl.animations.preexplode_end.active = false
			self.cl.animations.explode_wind_up.active = false
		elseif event == "erupt" then
			self.ignited = true
			if self.graphicsLoaded then
				
				if not self.cl.gasLeakEffect:isPlaying() then
					self.cl.gasLeakEffect:start()
				end
			end
		elseif event == "preexplode_start" then
			if not self.cl.igniteEffect:isPlaying() then
				self.cl.igniteEffect:start()
			end
			self.cl.animations.preexplode_start.time = 0
			self.cl.animations.preexplode_start.active = true
			self.cl.animations.preexplode_loop.time = 0
			self.cl.animations.preexplode_loop.active = false
			self.cl.animations.preexplode_loop.loopTimer = 0
			self.cl.animations.preexplode_end.time = 0
			self.cl.animations.preexplode_end.active = false
			if self.graphicsLoaded then
				if self.cl.preExplodeEffect and not self.cl.preExplodeEffect:isPlaying() then
					self.cl.preExplodeEffect:start()
				end
			end
		elseif event == "explode_wind_up" then
			self.cl.animations.explode_wind_up.time = 0
			self.cl.animations.explode_wind_up.active = true
			self.cl.animations.explode_wind_up.loopTimer = 0
			if self.graphicsLoaded then
				if self.cl.preExplodeEffect and not self.cl.preExplodeEffect:isPlaying() then
					self.cl.preExplodeEffect:start()
				end
			end
		elseif event == "reset" then
			self.cl.igniteEffect:stop()
			self.cl.gasLeakEffect:stop()
			self.cl.preExplodeEffect:stop()
			self.cl.animations.preexplode_start.active = false
			self.cl.animations.preexplode_loop.active = false
			self.cl.animations.preexplode_end.active = false
			self.cl.animations.explode_wind_up.active = false
			self.cl.animations.explode_wind_up.loopTimer = 0
		elseif event == "death" then
			SpawnDebris( self.character, "jnt_spine1", "Robotparts - TotebotBody" )
			SpawnDebris( self.character, "jnt_01_upperleg", "Robotparts - TotebotLeg" )
			SpawnDebris( self.character, "jnt_02_upperleg", "Robotparts - TotebotLeg" )
			SpawnDebris( self.character, "jnt_03_upperleg", "Robotparts - TotebotLeg" )
			SpawnDebris( self.character, "jnt_04_upperleg", "Robotparts - TotebotLeg" )
			SpawnDebris( self.character, "jnt_05_upperleg", "Robotparts - TotebotLeg" )
			SpawnDebris( self.character, "jnt_06_upperleg", "Robotparts - TotebotLeg" )

			sm.effect.playEffect( "Totebotred - Destroy", self.character.worldPosition, nil, nil, nil, { Color = self.character:getColor() } )
		else
			self.cl.currentAnimation = ""
		end
	end
end

function TotebotRedCharacter.client_onClientDataUpdate( self, data, channel )
	if channel == 1 then
		TotebotCharacter.client_onClientDataUpdate( self, data, channel )
	elseif channel == 2 then
		if data.chase then
			local serverEstimate = sm.game.getServerTick()
			local missedTicks = serverEstimate - data.serverTick
			self.speedIncreaseTickCounter = missedTicks
			self.isChasing = true
			if self.character then
				self.currentSpeed = lerp( RegularSpeed, ChaseSpeed, self.speedIncreaseTickCounter / MovementSpeedIncreaseTicks )
				self.character.movementSpeedFraction = self.currentSpeed
			end
		else
			self.isChasing = false
			self.speedIncreaseTickCounter = 0
			self.character.movementSpeedFraction = RegularSpeed
		end
	end
end

function TotebotRedCharacter.client_onFixedUpdate( self )
	if self.isChasing then
		if self.character then
			self.speedIncreaseTickCounter = self.speedIncreaseTickCounter + 1
			self.currentSpeed = lerp( RegularSpeed, ChaseSpeed, self.speedIncreaseTickCounter / MovementSpeedIncreaseTicks )
			self.character.movementSpeedFraction = self.currentSpeed
		end
	end
end