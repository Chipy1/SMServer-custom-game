LockedActivationButton = class( nil )

LockedActivationButton.States = {
	locked = 1,
	open = 2,
	lockdown = 3
}

function LockedActivationButton.server_onCreate( self )
	self.sv = {}
	self.sv.saved = self.storage:load()
	if self.sv.saved == nil then
		self.sv.saved = {}
		self.sv.saved.state = self.States.locked
		self.storage:save( self.sv.saved )
	end
end

function LockedActivationButton.sv_n_activate( self  )
	if not self.sv.saved.locked then
        self.sv.saved.state = self.States.lockdown
		self.sv.saved.press = true
		self.network:setClientData( self.sv.saved )
		self.sv.saved.press = nil
        self.storage:save( self.sv.saved )
    end
end

function LockedActivationButton.sv_saveAndSync( self )
    self.storage:save( self.sv.saved )
    self.network:setClientData( self.sv.saved )
end

-- Client

function LockedActivationButton.client_onCreate( self )
    self.cl = {}
	self.cl.locked = false
    self.cl.animations = {}
	self.cl.animations["Locked"] = self:cl_createAnimation( "locked" )
	self.cl.animations["Open"] = self:cl_createAnimation( "open" )
	self.cl.animations["Press"] = self:cl_createAnimation( "press", "Lockdown" )
	self.cl.animations["Lockdown"] = self:cl_createAnimation( "lockdown" )
    self:cl_setAnimation( self.cl.animations["Locked"], 0.0 )
end

function LockedActivationButton.client_onUpdate( self, dt )
    self:cl_updateAnimations( dt )
end

function LockedActivationButton.client_onClientDataUpdate( self, data, channel )
	self.cl.locked = data.state ~= self.States.open
	if data.press then
		self:cl_setAnimation( self.cl.animations["Press"], 0.0 )
    elseif data.state == self.States.locked then
        self:cl_setAnimation( self.cl.animations["Locked"], 0.0 )
	elseif data.state == self.States.open then
		self:cl_setAnimation( self.cl.animations["Open"], 0.0 )
	else
        self:cl_setAnimation( self.cl.animations["Lockdown"], 1.0 )
	end
end

function LockedActivationButton.cl_n_press( self )
end

function LockedActivationButton.client_canInteract( self )
	if not self.cl.locked then
		return true
	end
	return false
end

function LockedActivationButton.client_onInteract( self, _, state )
	if state then
		self.network:sendToServer( "sv_n_activate" )
	end
end

function LockedActivationButton.cl_createAnimation( self, name, nextAnimation )
	local animation =
	{
		name = name,
		playProgress = 0.0,
		playTime = self.interactable:getAnimDuration( name ),
		nextAnimation = nextAnimation
	}
	return animation
end

function LockedActivationButton.cl_setAnimation( self, animation, playProgress )
	self:cl_unsetAnimations()
	animation.isActive = true
	animation.playProgress = playProgress
	self.interactable:setAnimEnabled( animation.name, true )
end

function LockedActivationButton.cl_unsetAnimations( self )
	for name, animation in pairs( self.cl.animations ) do
		animation.isActive = false
		animation.playProgress = 0.0
		self.interactable:setAnimEnabled( animation.name, false )
		self.interactable:setAnimProgress( animation.name, animation.playProgress )
	end
end

function LockedActivationButton.cl_updateAnimations( self, dt )
    for _, animation in pairs( self.cl.animations ) do
		self:cl_updateAnimation( animation, dt )
	end
end

function LockedActivationButton.cl_updateAnimation( self, animation, dt )
	if animation.isActive then
		self.interactable:setAnimEnabled( animation.name, true )
        animation.playProgress = animation.playProgress + dt / animation.playTime            
        if animation.playProgress > 1.0 then
            if animation.nextAnimation then
                self:cl_setAnimation( self.cl.animations[animation.nextAnimation], 0.0 )
                return
            else
                animation.playProgress = 1.0
            end
        end
        self.interactable:setAnimProgress( animation.name, animation.playProgress )
	end
end