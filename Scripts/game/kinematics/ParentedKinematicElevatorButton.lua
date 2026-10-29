dofile( "$SURVIVAL_DATA/Scripts/game/kinematics/ParentedKinematic.lua" )

ParentedKinematicElevatorButton = class( ParentedKinematic )

-- Server

function ParentedKinematicElevatorButton.server_onCreate( self )
	ParentedKinematic.server_onCreate( self )
	self.sv.elevatorMoving = false
end

function ParentedKinematicElevatorButton.server_onFixedUpdate( self )
	ParentedKinematic.server_onFixedUpdate( self )
	local isDirty = false
	if self.params and self.params.eventTrigger and self.params.eventTrigger ~= "" then
		if g_kinematicManager then
			local registered = KinematicManager.Sv_GetRegistered( self.sv.tileStorageKey, self.params.eventTrigger )
			if registered  then
				local anyIsMoving = false
				for _, elevator in ipairs( registered ) do
					if sm.exists( elevator ) then
						if elevator.publicData then
							if elevator.publicData.moving then
								anyIsMoving = true
								break
							end
						end
					end
				end
				if anyIsMoving ~= self.sv.elevatorMoving then
					isDirty = true
					self.sv.elevatorMoving = anyIsMoving
				end
			end
		end
	end
	if isDirty then
		self.network:setClientData( self.sv.elevatorMoving, 3 )
	end
end

function ParentedKinematicElevatorButton.sv_n_activate( self )
	-- Activation
	if self.params and self.params.eventTrigger and self.params.eventTrigger ~= "" then
		if g_kinematicManager then
			KinematicManager.Sv_Activate( self.sv.tileStorageKey, self.params.eventTrigger )
		end
	end
end

function ParentedKinematicElevatorButton.server_onProjectile( self, hitPos, hitTime, hitVelocity, _, attacker, damage, userData, hitNormal, projectileUuid )
	if damage > 0 and type( attacker ) == "Player" and not self.sv.elevatorMoving then
		self:sv_n_activate()
	end
end

-- Client
local UvUpdateFrequency = 0.1
local ActivateDuration = 0.5

function ParentedKinematicElevatorButton.client_onCreate( self )
	ParentedKinematic.client_onCreate( self )
	self.cl.elevatorMoving = false
	self.cl.currentUvStep = 1
	self.cl.uvMin = 12
	self.cl.uvMax = 15
	self.cl.uvUpdateCounter = 0
	self.cl.isActivating = false
	self.cl.activationCounter = 0.0
	self.harvestable:setUvFrameIndex( 1 )
end

function ParentedKinematicElevatorButton.client_onClientDataUpdate( self, clientData, channel )
	if channel == 3 then
		self.cl.elevatorMoving = clientData
		if not self.cl.elevatorMoving then
			self.harvestable:setUvFrameIndex( 1 )
		end
	else
		ParentedKinematic.client_onClientDataUpdate( self, clientData, channel )
	end
end

function ParentedKinematicElevatorButton.cl_setMovementUv( self )
	self.cl.uvMin = 4
	self.cl.uvMax = 7
	self.cl.currentUvStep = 4
end

function ParentedKinematicElevatorButton.cl_setActivationUv( self )
	self.cl.uvMin = 12
	self.cl.uvMax = 15
	self.cl.currentUvStep = 12
	self.cl.isActivating = true
end

function ParentedKinematicElevatorButton.client_onUpdate( self, dt )
	if self.cl.elevatorMoving then
		if self.cl.isActivating then
			self.cl.activationCounter = self.cl.activationCounter + dt
			if self.cl.activationCounter >= ActivateDuration then
				self.cl.activationCounter = 0.0
				self.cl.isActivating = false
				self:cl_setMovementUv()
			end
		end
		self.cl.uvUpdateCounter = self.cl.uvUpdateCounter + dt
		if self.cl.uvUpdateCounter >= UvUpdateFrequency then
			self.cl.currentUvStep = self.cl.currentUvStep + 1
			if self.cl.currentUvStep > self.cl.uvMax then
				self.cl.currentUvStep = self.cl.uvMin
			end
			self.harvestable:setUvFrameIndex( self.cl.currentUvStep )
			self.cl.uvUpdateCounter = 0
		end
	end
end

function ParentedKinematicElevatorButton.client_canInteract( self )
	if self.cl.elevatorMoving then
		return false
	end
	sm.gui.setInteractionText( "", sm.gui.getKeyBinding( "Use", true ), "#{INTERACTION_USE}" )
	return true
end

function ParentedKinematicElevatorButton.client_onInteract( self, character, state )
	if state == true and not self.cl.elevatorMoving then
		sm.effect.playEffect( "Elevator Button", self.harvestable.worldPosition )
		self:cl_setActivationUv()
		self.network:sendToServer( "sv_n_activate" )
	end
end

function ParentedKinematicElevatorButton.client_onProjectile( self, hitPos, hitTime, hitVelocity, _, attacker, damage, userData, hitNormal, projectileUuid )
	if damage > 0 and type( attacker ) == "Player" and not self.cl.elevatorMoving then
		sm.effect.playEffect( "Elevator Button", self.harvestable.worldPosition )
		self:cl_setActivationUv()
	end
end