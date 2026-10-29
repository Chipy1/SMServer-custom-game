WocCharacter = class( nil )

function WocCharacter.server_onCreate( self )
	self:server_onRefresh()
end

function WocCharacter.server_onRefresh( self )

end

function WocCharacter.client_onCreate( self )
	self.animations = {}
	self:client_onRefresh()
	
end

function WocCharacter.client_onDestroy( self )
end

function WocCharacter.client_onRefresh( self )
end

function WocCharacter.client_onGraphicsLoaded( self )
	self.animations.tinker = {
		info = self.character:getAnimationInfo( "cow_eat_grass" ),
		time = 0,
		weight = 0
	}
	self.animations.idlespecial01 = {
		info = self.character:getAnimationInfo( "idlespecial01" ),
		time = 0,
		weight = 0
	}
	self.animations.idlespecial02 = {
		info = self.character:getAnimationInfo( "idlespecial02" ),
		time = 0,
		weight = 0
	}
	self.animationsLoaded = true

	self.blendSpeed = 5.0
	self.blendTime = 0.2
	
	self.currentAnimation = ""
	
	self.character:setMovementEffects( "$SURVIVAL_DATA/Character/Char_Cow/movement_effects.json" )
	self.eatEffect = sm.effect.createEffect( "Woc - Eating", self.character, "jnt_head" )
	self.graphicsLoaded = true
end

function WocCharacter.client_onGraphicsUnloaded( self )
	self.graphicsLoaded = false

	if self.eatEffect then
		self.eatEffect:destroy()
		self.eatEffect = nil
	end
end

function WocCharacter.client_onUpdate( self, deltaTime )
	if not self.graphicsLoaded then
		return
	end
















	for name, animation in pairs(self.animations) do
		animation.time = animation.time + deltaTime
	
		if name == self.currentAnimation then
			animation.weight = math.min(animation.weight+(self.blendSpeed * deltaTime), 1.0)
			if animation.time >= animation.info.duration then
				self.currentAnimation = ""
			end
		else
			animation.weight = math.max(animation.weight-(self.blendSpeed * deltaTime ), 0.0)
		end
	
		self.character:updateAnimation( animation.info.name, animation.time, animation.weight )
	end
end

function WocCharacter.client_onEvent( self, event )
	if not self.animationsLoaded then
		return
	end

	if event == "eat" then
		self.currentAnimation = "tinker"
		self.animations.tinker.time = 0
		if self.graphicsLoaded then
			self.eatEffect:start()
		end
	elseif event == "moo" then
		if self.graphicsLoaded then
			sm.effect.playHostedEffect( "Woc - Moo", self.character, "jnt_head" )
		end
	elseif event == "hit" then
		self.currentAnimation = ""
		if self.graphicsLoaded then
			self.eatEffect:stop()
		end
	elseif event == "idlespecial01" then
		self.currentAnimation = "idlespecial01"
		self.animations.idlespecial01.time = 0
	elseif event == "idlespecial02" then
		self.currentAnimation = "idlespecial02"
		self.animations.idlespecial02.time = 0
	end

end
