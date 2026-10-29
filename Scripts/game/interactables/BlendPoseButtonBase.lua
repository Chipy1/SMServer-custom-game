BlendPoseButtonBase = class()
BlendPoseButtonBase.poseWeightCount = 2

function BlendPoseButtonBase.client_onCreate( self )
	local buttonBase = InitializeNestedTables( self, "cl", "buttonBase" )
	buttonBase.pressProgress = 0.0
	buttonBase.effectName = "BlendPoseButton"
	self.cl.buttonBase.pressTime = 0.2
	self.cl.buttonBase.pressSpeed = 1.0 / self.cl.buttonBase.pressTime
end

function BlendPoseButtonBase.client_onInteract( self, character, state )
	if state == true and self.cl.buttonBase.pressProgress == 1 then
		self.network:sendToServer( "sv_n_push" )
	end
end

function BlendPoseButtonBase.server_onProjectile( self, hitPos, hitTime, hitVelocity, _, attacker, damage, userData, hitNormal, projectileUuid )
	if type( attacker ) == "Player" and damage > 0 then
		self:sv_n_push( nil, attacker )
	end
end

function BlendPoseButtonBase.sv_n_push( self, _, player )
	self.network:sendToClients( "cl_push" )
end

function BlendPoseButtonBase.cl_worldPos( self )
	if self.shape then
		return self.shape.worldPosition
	elseif self.harvestable then
		return self.harvestable.worldPosition
	end
	assert( false, "BlendPoseButtonBase: Not shape or harvestable" )
end

function BlendPoseButtonBase.cl_push( self )
	if self.cl.buttonBase.pressProgress == 1 then
		self.cl.buttonBase.pressProgress = 0.0
		sm.effect.playEffect( "Button - On", self:cl_worldPos() )
	end
end

function BlendPoseButtonBase.client_onUpdate( self, dt )
	if self.cl.buttonBase.pressProgress < 1.0 then
		local current = self.cl.buttonBase.pressProgress
		self.cl.buttonBase.pressProgress = math.min( self.cl.buttonBase.pressProgress + dt * (1.0 / self.cl.buttonBase.pressTime), 1.0 )

		if current < 0.5 and self.cl.buttonBase.pressProgress >= 0.5 then
			sm.effect.playEffect( "Button - Off", self:cl_worldPos() )
		end

		local blendValue = 1 - math.abs(1.0 - 2.0 * self.cl.buttonBase.pressProgress)

		if self.interactable then
			self.interactable:setPoseWeight(0, blendValue)
		else
			self.harvestable:setPoseWeight(0, blendValue)
		end
	end
end
