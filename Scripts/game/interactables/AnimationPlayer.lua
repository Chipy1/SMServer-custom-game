
dofile "$SURVIVAL_DATA/Scripts/util.lua"

AnimationPlayer = class( nil )

function AnimationPlayer.cl_createAnimation( self, animationData, playTime )
	local animation =
	{
		name = animationData.name,
		playProgress = 0.0,
		playTime = playTime,
		isActive = false,
		looping = animationData.looping or false,
		playForward = true,
		nextAnimation = nil
	}
	return animation
end

function AnimationPlayer.cl_setAnimation( self, animation, playProgress )
	self:cl_unsetAnimation()
	animation.isActive = true
	animation.playProgress = playProgress
	self.interactable:setAnimEnabled(animation.name, true)

	local effects = self.cl.effects[animation.name]
	if effects ~= nil then
		for i, effect in ipairs( effects ) do
			if effect then
				if effect:isPlaying() then
					effect:stop()
				end
				effect:start()
			end
		end
	end
end

function AnimationPlayer.cl_unsetAnimation( self )
	for name, animation in pairs( self.cl.animations ) do
		animation.isActive = false
		animation.playProgress = 0.0
		self.interactable:setAnimEnabled( animation.name, false )
		self.interactable:setAnimProgress( animation.name, animation.playProgress )
	end
end

function AnimationPlayer.cl_updateAnimation( self, dt )
	for name, animation in pairs( self.cl.animations ) do
		if animation.isActive then
			self.interactable:setAnimEnabled(animation.name, true)
			if animation.playForward then
				animation.playProgress = animation.playProgress + dt / animation.playTime
				if animation.playProgress > 1.0 then
					if animation.looping then
						animation.playProgress = animation.playProgress - 1.0
					else
						if animation.nextAnimation then
							self:cl_setAnimation(animation.nextAnimation, 0.0)
							return
						else
							if self.cl.mode then
								animation.playProgress = 1.0
							else
								self:cl_nextAnimation()
							end
						end
					end
				end
				self.interactable:setAnimProgress(animation.name, animation.playProgress ) 
			else
				animation.playProgress = animation.playProgress - dt / animation.playTime
				if animation.playProgress < -1.0 then
					if animation.looping then
						animation.playProgress = animation.playProgress + 1.0
					else
						if animation.nextAnimation then
							self:cl_setAnimation(animation.nextAnimation, 0.0)
							return
						else
							if self.cl.mode then
								animation.playProgress = -1.0
							else
								self:cl_nextAnimation()
							end
						end
					end
				end
				self.interactable:setAnimProgress(animation.name, 1.0 + animation.playProgress )
			end
		end
	end
end

function AnimationPlayer.client_onCreate(self)
	self.cl = {}
	self:cl_init()
end

function AnimationPlayer.client_onDestroy(self)
	for name, effects in pairs( self.cl.effects ) do
		for i, effect in ipairs( effects ) do
			if effect then
				effect:destroy()
			end
		end
	end
end

function AnimationPlayer.cl_init(self)
	
	self.cl.idxAnimationNames = {}
	self.cl.effects = {}
	local animations = {}
	if self.data then
		if self.data.animationList then
			for i, animation in ipairs( self.data.animationList ) do
				local duration = self.interactable:getAnimDuration( animation.name )
				animations[animation.name] = self:cl_createAnimation( animation, duration )
				self.cl.idxAnimationNames[#self.cl.idxAnimationNames+1] = animation.name
				if animation.effect then
					if animation.effect.name then
						self.cl.effects[animation.name] = { sm.effect.createEffect( animation.effect.name, self.interactable, animation.effect.joint ) }
					else
						local allEffect = {}
						for i, effect in ipairs( animation.effect ) do
							allEffect[#allEffect+1] = sm.effect.createEffect( effect.name, self.interactable, effect.joint )
						end
						self.cl.effects[animation.name] = allEffect
					end
				end
			end
		end
	end
	self.cl.mode = false
	self.cl.animations = animations
	self.cl.currentAnimationIdx = 1
	local name = self.cl.idxAnimationNames[self.cl.currentAnimationIdx]
	self:cl_setAnimation( self.cl.animations[name], 0.0 )

end

function AnimationPlayer.client_onRefresh(self)
	self:cl_init()
end

function AnimationPlayer.client_onUpdate(self, dt)
	self:cl_updateAnimation( dt )
end

function AnimationPlayer.cl_nextAnimation( self )
	self.cl.currentAnimationIdx = ( self.cl.currentAnimationIdx % #self.cl.idxAnimationNames ) +1
	local name = self.cl.idxAnimationNames[self.cl.currentAnimationIdx]
	self:cl_setAnimation( self.cl.animations[name], 0.0 )
end
