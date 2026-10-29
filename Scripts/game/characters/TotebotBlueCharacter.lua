dofile "$SURVIVAL_DATA/Scripts/game/util/Timer.lua"
dofile "$SURVIVAL_DATA/Scripts/game/characters/TotebotCharacter.lua"

TotebotBlueCharacter = class( TotebotCharacter )

local animationSets = {
	alert = "$SURVIVAL_DATA/Character/Char_Totebot_blue/char_totebot_blue_alert.rend",
	roaming = "$SURVIVAL_DATA/Character/Char_Totebot_blue/char_totebot_blue_roaming.rend"
}
local swimmingAnimationSets = {
	alert = { "$SURVIVAL_DATA/Character/Char_Totebot_blue/char_totebot_blue_swim_alert.rend", "$SURVIVAL_DATA/Character/Char_Totebot_blue/char_totebot_blue_head_swim_alert.rend" },
	roaming = { "$SURVIVAL_DATA/Character/Char_Totebot_blue/char_totebot_blue_swim_roaming.rend", "$SURVIVAL_DATA/Character/Char_Totebot_blue/char_totebot_blue_head_swim_roaming.rend" }
}
sm.character.preloadRenderables( { animationSets.alert, animationSets.roaming } )

--[[ Server ]]
function TotebotBlueCharacter.server_onCreate( self )
	self.sv = {}
end

function TotebotBlueCharacter.cl_changeAnimationSet( self, animationSet )
	self.character:removeRenderable( animationSets[self.cl.currentAnimationSet] )
	if swimmingAnimationSets[self.cl.currentAnimationSet] then
		for _, animationSet in pairs( swimmingAnimationSets[self.cl.currentAnimationSet] ) do
			self.character:removeRenderable( animationSet )
		end
	end
	self.cl.currentAnimationSet = animationSet
	self.character:addRenderable( animationSets[self.cl.currentAnimationSet] )
	if swimmingAnimationSets[self.cl.currentAnimationSet] then
		for _, animationSet in pairs( swimmingAnimationSets[self.cl.currentAnimationSet] ) do
			self.character:addRenderable( animationSet )
		end
	end
end

function TotebotBlueCharacter.client_onCreate( self )
	TotebotCharacter.client_onCreate( self )
	self.cl.currentAnimationSet = "roaming"
	self.cl.upDirection = sm.vec3.new( 0, 0, 1 )
	self.cl.torpedoActive = false
end

function TotebotBlueCharacter.client_onGraphicsLoaded( self )
	self.character:addRenderable( animationSets[self.cl.currentAnimationSet] )
	if swimmingAnimationSets[self.cl.currentAnimationSet] then
		for _, animationSet in pairs( swimmingAnimationSets[self.cl.currentAnimationSet] ) do
			self.character:addRenderable( animationSet )
		end
	end
	self:cl_initGraphics()
	self:cl_initAnimationSwitch()
	self.character:setGlowMultiplier( 1 )
	self.graphicsLoaded = true

	self.cl.attackEffect = sm.effect.createEffect( "ToteBotBlue - Attack", self.character )
	self.cl.idleBubbleEffect = sm.effect.createEffect( "Totebotblue - Idlebubble", self.character )
	self.cl.drillEffect = sm.effect.createEffect( "Totebotblue - Drillactive", self.character, "jnt_head" )
	self.cl.drillEffect:setOffsetRotation( sm.quat.fromEuler( sm.vec3.new( -90, 0, 0 ) ) )
	self.cl.drillEffect:setOffsetPosition( sm.vec3.new( 0, 1.25, 0 ) )
end

function TotebotBlueCharacter.client_onGraphicsUnloaded( self )
	self.graphicsLoaded = false

	if self.cl.attackEffect then
		self.cl.attackEffect:destroy()
		self.cl.attackEffect = nil
	end
	if self.cl.idleBubbleEffect then
		self.cl.idleBubbleEffect:destroy()
		self.cl.idleBubbleEffect = nil
	end
	if self.cl.drillEffect then
		self.cl.drillEffect:destroy()
		self.cl.drillEffect = nil
	end
end

function TotebotBlueCharacter.client_onUpdate( self, deltaTime )
	TotebotCharacter.client_onUpdate( self, deltaTime )
	if not self.graphicsLoaded then
		return
	end

	local desiredUpDirection = sm.vec3.new( 0, 0, 1 )
	if self.character:isSwimming() and not self.character:isTumbling() then
		if self.cl.currentAnimationSet == "alert" then
			local direction = self.character.direction
			local up = sm.vec3.new( 0, 0, 1 )
			local headingForward = sm.vec3.new( self.character.direction.x, self.character.direction.y, 0.0 ):safeNormalize( sm.vec3.new( 0, 1, 0 ) )
			local headingRight = headingForward:cross( up )
			local adjustedDirection = direction:rotate( math.rad( 5 ), headingRight )
			desiredUpDirection = adjustedDirection:safeNormalize( desiredUpDirection )
		end
	end
	self.cl.upDirection = magicDirectionInterpolation( self.cl.upDirection, desiredUpDirection, deltaTime, 1 / 4 )
	self.character:setUpDirection( self.cl.upDirection )
	if self.cl.torpedoActive then
		if not self.cl.drillEffect:isPlaying() then
			self.cl.drillEffect:start()
		end
	else
		if self.cl.drillEffect:isPlaying() then
			self.cl.drillEffect:stop()
		end
	end
	if self.character:isDiving() and not self.character:isTumbling() then
		if not self.cl.idleBubbleEffect:isPlaying() then
			self.cl.idleBubbleEffect:start()
		end
	else
		if self.cl.idleBubbleEffect:isPlaying() then
			self.cl.idleBubbleEffect:stop()
		end
	end
end

function TotebotBlueCharacter.sv_e_setTorpedoActive( self, torpedoActive )
	self.network:setClientData( torpedoActive, 2 )
end

function TotebotBlueCharacter.client_onClientDataUpdate( self, torpedoActive, channel )
	BaseEnemyCharacter.client_onClientDataUpdate( self, torpedoActive, channel )
	if channel == 2 then
		self.cl.torpedoActive = torpedoActive
	end
end

function TotebotBlueCharacter.cl_initGraphics( self )
	TotebotCharacter.cl_initGraphics( self )
	self.character:setMovementEffects( "$SURVIVAL_DATA/Character/Char_Totebot_blue/movement_effects.json" )
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

end

function TotebotBlueCharacter.cl_handleEvent( self, event )
	if not self.animationsLoaded then
		return
	end

	if sm.exists( self.character ) then
		if event == "melee" then
			self.cl.currentAnimation = "attack"
			self.cl.animations.attack.time = 0
			if self.graphicsLoaded then
				self.cl.attackEffect:start()
			end
		elseif event == "alerted" then
			if self.cl.animationSwitches.alerted then
				self.cl.currentSwitch = "alerted"
				self.cl.animationSwitches.alerted.time = 0
				self.cl.animationSwitches.alerted.triggeredEvent = false
			end
		elseif event == "roaming" then
			if self.cl.animationSwitches.roaming then
				self.cl.currentSwitch = "roaming"
				self.cl.animationSwitches.roaming.time = 0
				self.cl.animationSwitches.roaming.triggeredEvent = false
			end
		elseif event == "death" then
			SpawnDebris( self.character, "jnt_spine1", "Robotparts - TotebotBody" )
			SpawnDebris( self.character, "jnt_01_upperleg", "Robotparts - TotebotLeg" )
			SpawnDebris( self.character, "jnt_02_upperleg", "Robotparts - TotebotLeg" )
			SpawnDebris( self.character, "jnt_03_upperleg", "Robotparts - TotebotLeg" )
			SpawnDebris( self.character, "jnt_04_upperleg", "Robotparts - TotebotLeg" )
			SpawnDebris( self.character, "jnt_05_upperleg", "Robotparts - TotebotLeg" )
			SpawnDebris( self.character, "jnt_06_upperleg", "Robotparts - TotebotLeg" )

			sm.effect.playEffect( "Totebotblue - Destroy", self.character.worldPosition, nil, nil, nil, { Color = self.character:getColor() } )
		elseif event == "idlespecial01" then
			self.cl.currentAnimation = "idlespecial01"
			self.cl.animations.idlespecial01.time = 0
		elseif event == "idlespecial02" then
			self.cl.currentAnimation = "idlespecial02"
			self.cl.animations.idlespecial02.time = 0
		else
			self.cl.currentAnimation = ""
		end
	end
end