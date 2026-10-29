dofile( "$SURVIVAL_DATA/Scripts/util.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/characters/shared_animation.lua" )

BaseCharacter = class( nil )

function BaseCharacter.server_onCreate( self )
	self.character.publicData = {}
	self.sv = {}
end

function BaseCharacter.client_onCreate( self )
	self.character.clientPublicData = {}
	self.cl = {}
end

function BaseCharacter.client_onClientDataUpdate( self, data, channel )
	-- Base implementation - override in derived classes as needed
end

function BaseCharacter.client_onGraphicsLoaded( self )
	self.cl.animator = self.cl.animator or CREATE_ANIMATOR( self.character,self.cl.animations )
	self.cl.graphicsLoaded = true
	if self.missedEventQueue then
		local queue = self.missedEventQueue
		self.missedEventQueue = nil
		for _, event in ipairs( queue ) do
			self:cl_handleEvent( event )
		end
	end
end

function BaseCharacter.client_onGraphicsUnloaded( self )
	self.cl.graphicsLoaded = false
end

function BaseCharacter.client_onUpdate( self, deltaTime )
	if not self.cl.graphicsLoaded then
		return
	end

	self.cl.animator:update( deltaTime )
end

function BaseCharacter.client_onEvent( self, event )
	self:cl_handleEvent( event )
end

function BaseCharacter.cl_handleEvent( self, event )
	if not self.cl.graphicsLoaded then
		self.missedEventQueue = self.missedEventQueue or {}
		self.missedEventQueue[#self.missedEventQueue + 1] = event
		return true
	end

	local handled = self.cl.animator:handleEvent( event )
	return handled
end

function BaseCharacter.cl_setCurrentAnimation( self, name )
	local result = self.cl.animator:setCurrentAnimation( name )
	return result
end

function BaseCharacter.cl_endAnimation( self, endedAnimationName )
	self.cl.animator:endAnimation( endedAnimationName )
end



