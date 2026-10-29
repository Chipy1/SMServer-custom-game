CablebotCharacter = class( nil )

local FallingAlignTime = 0.25

function CablebotCharacter.server_onCreate( self )
	self.character:setClimbing( true )
end

function CablebotCharacter.client_onCreate( self )
	self.cl = {}
	self.cl.target = nil
	self.cl.fallingAlignCountdown = FallingAlignTime
end

function CablebotCharacter.client_onDestroy( self ) end

function CablebotCharacter.client_onGraphicsLoaded( self )
	self.character:setMovementEffects( "$SURVIVAL_DATA/Character/Char_Cablebot/movement_effects.json" )
	self.character:setGlowMultiplier( 1 )
	self.graphicsLoaded = true
end

function CablebotCharacter.client_onGraphicsUnloaded( self )
	self.graphicsLoaded = false
end

function CablebotCharacter.client_onUpdate( self, deltaTime )
	if not self.graphicsLoaded then
		return
	end

	if sm.exists( self.character ) then
		local upDirection = self.character:getSurfaceNormal():safeNormalize( sm.vec3.new( 0, 0, 1 ) )
		if self.character:getSurfaceNormal():length2() >= FLT_EPSILON * FLT_EPSILON then
			self.character:setUpDirection( upDirection )
			self.cl.fallingAlignCountdown = FallingAlignTime
		else
			if self.cl.fallingAlignCountdown > 0.0 then
				self.cl.fallingAlignCountdown = self.cl.fallingAlignCountdown - deltaTime
			else
				self.character:setUpDirection( upDirection )
				self.cl.fallingAlignCountdown = FallingAlignTime
			end
		end
















	end
end

function CablebotCharacter.client_onEvent( self, event ) end

function CablebotCharacter.sv_n_updateTarget( self, params )
	self.network:sendToClients( "cl_n_updateTarget", params )
end

function CablebotCharacter.cl_n_updateTarget( self, params )
	self.cl.target = params.target
end
