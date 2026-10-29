dofile("$SURVIVAL_DATA/Scripts/game/survival_shapes.lua")

HideoutVacuum = class()

function HideoutVacuum.client_onCreate( self )
	self.vacuumTime = self.interactable:getAnimDuration( "dropoff_in" )
	self.vacuumElapsed = 0.0
	
	self.currentAnimation = "dropoff_in"
	self.interactable:setAnimEnabled( self.currentAnimation, true )

	self.wasActive = false
	self.vacuumLoopEffect = sm.effect.createEffect( "Hideout - PumpSuction_loop", self.shape.interactable, "suction3_jnt" )
	self.vacuumEndEffect = sm.effect.createEffect( "Hideout - PumpSuction_loop_end", self.shape.interactable, "suction3_jnt" )
end

function HideoutVacuum.client_onUpdate( self, dt )

	if self.shape.interactable.active then
		if not self.wasActive then
			self.vacuumLoopEffect:start()
		end
		self.vacuumElapsed = math.min( self.vacuumElapsed + dt, self.vacuumTime )
		if self.vacuumElapsed >= self.vacuumTime then
			if self.currentAnimation == "dropoff_in" then
				self:cl_changeAnimation()
			elseif self.currentAnimation == "dropoff_loop" then
				self.vacuumElapsed = 0.0
			end
		end
	elseif self.wasActive then
		self.vacuumElapsed = math.min( self.vacuumElapsed + dt, self.vacuumTime )
		if self.vacuumElapsed >= self.vacuumTime then
			self:cl_changeAnimation()
		end
	elseif self.currentAnimation == "dropoff_out" then
		self.vacuumElapsed = math.min( self.vacuumElapsed + dt, self.vacuumTime )
		if self.vacuumElapsed >= self.vacuumTime then
			self:cl_changeAnimation()
		end
	else
		self.vacuumElapsed = 0.0
	end

	self.interactable:setAnimProgress( self.currentAnimation, self.vacuumElapsed / self.vacuumTime )
	self.wasActive = self.shape.interactable.active or self.vacuumElapsed > 0.0
end

function HideoutVacuum.cl_changeAnimation( self )
	self.interactable:setAnimEnabled( self.currentAnimation, false )
	self.vacuumElapsed = 0.0
	if self.currentAnimation == "dropoff_in" then
		self.currentAnimation = "dropoff_loop"
	elseif self.currentAnimation == "dropoff_loop" then
		self.currentAnimation = "dropoff_out"
		self.vacuumEndEffect:start()
		self.vacuumLoopEffect:stop()
	elseif self.currentAnimation == "dropoff_out" then
		self.currentAnimation = "dropoff_in"
	end
	self.interactable:setAnimEnabled( self.currentAnimation, true )
	self.interactable:setAnimProgress( self.currentAnimation, 0.0 )
	self.vacuumTime = self.interactable:getAnimDuration( self.currentAnimation )
end