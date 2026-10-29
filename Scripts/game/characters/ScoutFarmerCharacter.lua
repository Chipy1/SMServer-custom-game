dofile "$SURVIVAL_DATA/Scripts/game/survival_dialogs.lua"

ScoutFarmerCharacter = class( nil )

function ScoutFarmerCharacter.server_onCreate( self )
	local unit = self.character:getUnit()
	if unit then
		sm.event.sendToUnit( unit, "sv_e_onSpawnCharacter" )
	end
end

function ScoutFarmerCharacter.client_onCreate( self )
	self.animations = {}

	print( "-- ScoutFarmerCharacter created --" )
	self:client_onRefresh()
end

function ScoutFarmerCharacter.client_onDestroy( self )
	print( "-- ScoutFarmerCharacter destroyed --" )
end

function ScoutFarmerCharacter.client_onRefresh( self )
	print( "-- ScoutFarmerCharacter refreshed --" )
end

function ScoutFarmerCharacter.client_canInteract( self )
	local keyBindingText =  sm.gui.getKeyBinding( "Use", true )
	sm.gui.setInteractionText( "", keyBindingText, "#{INTERACTION_TALK}" )
	return true
end

function ScoutFarmerCharacter.client_onInteract( self, character, state )
	if state == true then
		self.network:sendToServer( "sv_n_interact" )
	end
end

function ScoutFarmerCharacter.sv_n_interact( self, _, player )
	local unit = self.character:getUnit()
	if unit and sm.exists( unit ) then
		sm.event.sendToUnit( unit, "sv_e_interact", { player = player } )
	end
end

function ScoutFarmerCharacter.client_onGraphicsLoaded( self )

	-- Third person animations
	self.animations = {}

	self.animations.call = {
		info = self.character:getAnimationInfo( "impactdriver_use" ),
		time = 0,
		weight = 0
	}

	self.animations.tinker = {
		info = self.character:getAnimationInfo( "multiknife_use" ),
		time = 0,
		weight = 0
	}

	self.animations.investigate = {
		info = self.character:getAnimationInfo( "crowbar_idle" ),
		time = 0,
		weight = 0
	}

	self.blendSpeed = 5.0
	self.blendTime = 0.2

	self.currentAnimation = ""

	self.graphicsLoaded = true
end

function ScoutFarmerCharacter.client_onGraphicsUnloaded( self )
	self.graphicsLoaded = false
end

function ScoutFarmerCharacter.client_onUpdate( self, deltaTime )
	if not self.graphicsLoaded then
		return
	end

	-- Third person animations
	for name, animation in pairs(self.animations) do
		if animation.info then
			animation.time = animation.time + deltaTime

			if animation.info.looping == true then
				if animation.time >= animation.info.duration then
					animation.time = animation.time - animation.info.duration
				end
			end
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

end

function ScoutFarmerCharacter.client_onEvent( self, event )
	self:cl_handleEvent( event )
end

function ScoutFarmerCharacter.cl_handleEvent( self, event )
	if not self.graphicsLoaded then
		return
	end

	if event then
		if self.animations[event] then
			self.currentAnimation = event
			self.animations[event].time = 0
		else
			self.currentAnimation = ""
		end
	end

end
