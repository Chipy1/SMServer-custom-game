dofile "$SURVIVAL_DATA/Scripts/game/characters/TotebotCharacter.lua"

TotebotYellowCharacter = class( TotebotCharacter )

local animationSets = {
	alert = "$SURVIVAL_DATA/Character/Char_Totebot_yellow/char_totebot_yellow_alert.rend",
	roaming = "$SURVIVAL_DATA/Character/Char_Totebot_yellow/char_totebot_yellow_roaming.rend"
}
sm.character.preloadRenderables( { animationSets.alert, animationSets.roaming } )

function TotebotYellowCharacter.cl_changeAnimationSet( self, animationSet )
	self.character:removeRenderable( animationSets[self.cl.currentAnimationSet] )
	self.cl.currentAnimationSet = animationSet
	self.character:addRenderable( animationSets[self.cl.currentAnimationSet] )
end

function TotebotYellowCharacter.client_onCreate( self )
	TotebotCharacter.client_onCreate( self )
	self.cl.currentAnimationSet = "roaming"
	self.cl.wantsJump = false
end
function TotebotYellowCharacter.client_onGraphicsLoaded( self )
	self.character:addRenderable( animationSets[self.cl.currentAnimationSet] )
	self:cl_initGraphics()
	self:cl_initAnimationSwitch()
	self.character:setGlowMultiplier( 1 )
	self.graphicsLoaded = true

	self.cl.trailEffect = sm.effect.createEffect( "Yellowtotebot - Jumptrail", self.character )
end

function TotebotYellowCharacter.client_onGraphicsUnloaded( self )
	self.graphicsLoaded = false

	if self.cl.trailEffect then
		self.cl.trailEffect:destroy()
		self.cl.trailEffect = nil
	end
end

function TotebotYellowCharacter.client_onUpdate( self, deltaTime )
	TotebotCharacter.client_onUpdate( self, deltaTime )
	if not self.graphicsLoaded then
		return
	end

	if self.cl.trailEffect then
		if self.cl.wantsJump and not self.character:isOnGround() then
			-- Jumping
			self.cl.wantsJump = false
			self.cl.trailEffect:start()
		end
		if self.cl.trailEffect:isPlaying() then
			if self.character:isOnGround() then
				-- Landed
				self.cl.trailEffect:stop()
			end
		end
	end

end

function TotebotYellowCharacter.cl_initGraphics( self )
	if not self.cl.animations.recover then
		self.cl.animations.recover = {
			info = self.character:getAnimationInfo( "recover" ),
			time = 0,
			weight = 0,
			active = false
		}
	end
	self.character:setMovementEffects( "$SURVIVAL_DATA/Character/Char_Totebot/movement_effects.json" )
	self.animationsLoaded = true
end

function TotebotYellowCharacter.cl_handleEvent( self, event )
	if not self.animationsLoaded then
		return
	end

	if sm.exists( self.character ) then
		if event == "alerted" then
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
		elseif event == "jump" then
			local surfaceIndex = sm.physics.getMaterialId( sm.physics.getGroundMaterial( self.character.worldPosition ) )
			sm.effect.playEffect( "Yellowtotebot - Jumpinitation", self.character.worldPosition, nil, nil, nil, { surface = surfaceIndex } )
			self.cl.wantsJump = true
		elseif event == "disoriented" then
			self.cl.animations.recover.time = 0
			self.cl.animations.recover.active = true
		elseif event == "stomp" then
			sm.effect.playHostedEffect( "Yellowtotebot - Jumptrailimpactincoming", self.character )
		elseif event == "death" then
			SpawnDebris( self.character, "jnt_spine1", "Robotparts - TotebotBody" )
			SpawnDebris( self.character, "jnt_01_upperleg", "Robotparts - TotebotLeg" )
			SpawnDebris( self.character, "jnt_02_upperleg", "Robotparts - TotebotLeg" )
			SpawnDebris( self.character, "jnt_03_upperleg", "Robotparts - TotebotLeg" )
			SpawnDebris( self.character, "jnt_04_upperleg", "Robotparts - TotebotLeg" )
			SpawnDebris( self.character, "jnt_05_upperleg", "Robotparts - TotebotLeg" )
			SpawnDebris( self.character, "jnt_06_upperleg", "Robotparts - TotebotLeg" )

			sm.effect.playEffect( "Yellowtotebot - Destroy", self.character.worldPosition, nil, nil, nil, { Color = self.character:getColor() } )
		else
			self.cl.currentAnimation = ""
		end
	end
end