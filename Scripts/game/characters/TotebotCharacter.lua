dofile "$SURVIVAL_DATA/Scripts/game/characters/BaseEnemyCharacter.lua"
TotebotCharacter = class( BaseEnemyCharacter )

local animationSets = {
	alert = "$SURVIVAL_DATA/Character/Char_Totebot/char_totebot_alert.rend",
	roaming = "$SURVIVAL_DATA/Character/Char_Totebot/char_totebot_roaming.rend"
}

sm.character.preloadRenderables( { animationSets.alert, animationSets.roaming } )

function TotebotCharacter.cl_changeAnimationSet( self, animationSet )
	self.character:removeRenderable( animationSets[self.cl.currentAnimationSet] )
	self.cl.currentAnimationSet = animationSet
	self.character:addRenderable( animationSets[self.cl.currentAnimationSet] )
end

function TotebotCharacter.client_onCreate( self )
	self.cl = {}
	self.cl.animations = {}
	self.cl.animationSwitches = {}
	self.cl.effects = {}
	self.cl.currentAnimationSet = "roaming"
	self.cl.target = nil
	self.cl.blendSpeed = 5.0
	self.cl.blendTime = 0.2
	self.cl.currentAnimation = ""

	self:client_onRefresh()
end

function TotebotCharacter.client_onRefresh( self )
end

function TotebotCharacter.client_onGraphicsLoaded( self )
	self.character:addRenderable( animationSets[self.cl.currentAnimationSet] )
	self:cl_initGraphics()
	self:cl_initAnimationSwitch()
	self.character:setGlowMultiplier( 1 )
	self.graphicsLoaded = true

	self.cl.effects = {}
	self.cl.effects.alerted = sm.effect.createEffect( "ToteBot - Alerted", self.character, "jnt_head" )
	self.cl.effects.hit = sm.effect.createEffect( "ToteBot - Hit", self.character, "jnt_head" )
	self.cl.effects.attack = sm.effect.createEffect( "ToteBot - Attack", self.character )
	self.cl.effects.launch = sm.effect.createEffect( "ToteBot - JumpAttack_start", self.character )
	self.cl.effects.inAir = sm.effect.createEffect( "ToteBot - JumpAttack_trail", self.character )
	self.cl.effects.sparks = sm.effect.createEffect( "ToteBot - Sparks", self.character, "cable6_jnt" )
	self.cl.effects.sparks:start()
end

function TotebotCharacter.client_onGraphicsUnloaded( self )
	self.graphicsLoaded = false

	if self.cl.effects.alerted then
		self.cl.effects.alerted:destroy()
		self.cl.effects.alerted = nil
	end
	if self.cl.effects.hit  then
		self.cl.effects.hit:destroy()
		self.cl.effects.hit = nil
	end
	if self.cl.effects.attack then
		self.cl.effects.attack:destroy()
		self.cl.effects.attack = nil
	end
	if self.cl.effects.launch then
		self.cl.effects.launch:destroy()
		self.cl.effects.launch = nil
	end
	if self.cl.effects.inAir then
		self.cl.effects.inAir:destroy()
		self.cl.effects.inAir = nil
	end
	if self.cl.effects.sparks then
		self.cl.effects.sparks:destroy()
		self.cl.effects.sparks = nil
	end
end

function TotebotCharacter.cl_initGraphics( self )
	if not self.cl.animations.attack then
		self.cl.animations.attack = {
			info = self.character:getAnimationInfo( "attack_melee" ),
			time = 0,
			weight = 0
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
	if not self.cl.animations.launch then
		self.cl.animations.launch = {
			info = self.character:getAnimationInfo( "launch_windup" ),
			time = 0,
			weight = 0,
			disableMovementAnimations = true
		}
	end
	if not self.cl.animations.inAir then
		self.cl.animations.inAir = {
			info = self.character:getAnimationInfo( "launch_inair" ),
			time = 0,
			weight = 0,
			disableMovementAnimations = true
		}
	end
	if not self.cl.animations.landing then
		self.cl.animations.landing = {
			info = self.character:getAnimationInfo( "launch_land" ),
			time = 0,
			weight = 0,
			disableMovementAnimations = true
		}
	end
	self.character:setMovementEffects( "$SURVIVAL_DATA/Character/Char_Totebot/movement_effects.json" )
	self.animationsLoaded = true
end

function TotebotCharacter.cl_initAnimationSwitch( self )
	self.cl.animationSwitches.alerted = {
		info = self.character:getAnimationInfo( "alerted" ),
		time = 0,
		weight = 0,
		triggeredEvent = false
	}
	self.cl.animationSwitches.roaming = {
		info = self.character:getAnimationInfo( "roaming" ),
		time = 0,
		weight = 0,
		triggeredEvent = false
	}
	self.cl.currentSwitch = ""
end

function TotebotCharacter.client_onUpdate( self, deltaTime )
	if not self.graphicsLoaded then
		return
	end
	
	if sm.exists( self.character ) then















		
		-- Update animations
		for name, animation in pairs( self.cl.animations ) do
			if animation.info then
				animation.time = animation.time + deltaTime
			
				if name == self.cl.currentAnimation then
					if animation.disableMovementAnimations then
						animation.weight = 1.0
						self.character:setMovementWeights( 0, 0 )
					else
						animation.weight = math.min(animation.weight+(self.cl.blendSpeed * deltaTime), 1.0)
						self.character:setMovementWeights( 1, 1 )
					end
					if animation.time >= animation.info.duration then
						self.cl.currentAnimation = ""
						if animation.disableMovementAnimations then
							self.character:setMovementWeights( 1, 1 )
						end
					end
				elseif animation.active then
					local finished = false
					animation.weight = math.min(animation.weight+(self.cl.blendSpeed * deltaTime), 1.0)
					if animation.loopTime then
						animation.loopTimer = animation.loopTimer + deltaTime
						if animation.time >= animation.info.duration then
							animation.time = 0
						end
						if animation.loopTimer >= animation.loopTime then
							self.cl.animations[name].active = false
							finished = true
						end
					elseif animation.time >= animation.info.duration then
						self.cl.animations[name].active = false
						finished = true
					end
					if finished then
						if animation.nextAnimation then
							self.cl.animations[animation.nextAnimation].active = true
							self.cl.animations[animation.nextAnimation].time = 0
							self.cl.animations[animation.nextAnimation].weight = 1
							animation.weight = 0
						end
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
							if self.cl.currentAnimationSet ~= "alert" then
								self:cl_changeAnimationSet( "alert" )
								self:cl_initGraphics()
							end
						elseif name == "roaming" then
							if self.cl.currentAnimationSet ~= "roaming" then
								self:cl_changeAnimationSet( "roaming" )
								self:cl_initGraphics()
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

function TotebotCharacter.client_onEvent( self, event )
	self:cl_handleEvent( event )
end

function TotebotCharacter.cl_handleEvent( self, event )
	if not self.animationsLoaded then
		return
	end
	if sm.exists( self.character ) then
		if event == "melee" then
			self.cl.currentAnimation = "attack"
			self.cl.animations.attack.time = 0
			if self.graphicsLoaded then
				self.cl.effects.attack:start()
			end
		elseif event == "launch" then
			self.cl.currentAnimation = "launch"
			self.cl.animations.launch.time = 0
			if self.graphicsLoaded then
				self.cl.effects.launch:start()
			end
		elseif event == "inAir" then
			self.cl.currentAnimation = "inAir"
			self.cl.animations.inAir.time = 0
			if self.graphicsLoaded then
				self.cl.effects.inAir:start()
			end
		elseif event == "landing" then
			self.cl.currentAnimation = "landing"
			self.cl.animations.landing.time = 0
		elseif event == "alerted" then
			if self.cl.animationSwitches.alerted then
				self.cl.currentSwitch = "alerted"
				self.cl.animationSwitches.alerted.time = 0
				self.cl.animationSwitches.alerted.triggeredEvent = false
				if self.graphicsLoaded then
					self.cl.effects.alerted:start()
				end
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
			
			sm.effect.playEffect( "ToteBot - DestroyedParts", self.character.worldPosition, nil, nil, nil, { Color = self.character:getColor() } )
		elseif event == "idlespecial01" then
			self.cl.currentAnimation = "idlespecial01"
			self.cl.animations.idlespecial01.time = 0
		elseif event == "idlespecial02" then
			self.cl.currentAnimation = "idlespecial02"
			self.cl.animations.idlespecial02.time = 0
		else
			self.cl.currentAnimation = ""
			self.character:setMovementWeights( 1, 1 )
		end
	end
end

function TotebotCharacter.sv_n_updateTarget( self, params )
	self.network:sendToClients( "cl_n_updateTarget", params )
end

function TotebotCharacter.cl_n_updateTarget( self, params )
	self.cl.target = params.target
end
