-- KinematicRailVehicle.lua --
dofile( "$SURVIVAL_DATA/Scripts/util.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/kinematics/KinematicRailObject.lua" )

KinematicRailVehicle = class( KinematicRailObject )

local Input = {
	LEFT = 1,
	RIGHT = 2,
	FORWARD = 4,
	BACKWARD = 8
}
local Acceleration = 10

function KinematicRailVehicle.sv_n_input( self, params )
	self.sv.updateData.acceleration = 0
	if bit.band( params.inputFlags, Input.FORWARD ) == Input.FORWARD then
		self.sv.updateData.acceleration = Acceleration
	end
	if bit.band( params.inputFlags, Input.BACKWARD ) == Input.BACKWARD then
		self.sv.updateData.acceleration = -Acceleration
	end
	self.sv.updateData.serverTick = sm.game.getServerTick()
	self.network:setClientData( self.sv.updateData, 2 )
end

function KinematicRailVehicle.client_onCreate( self )
	KinematicRailObject.client_onCreate( self )
	self.cl.inputFlags = 0
end

function KinematicRailVehicle.client_canInteract( self, character )
	if character:getCharacterType() == unit_mechanic and not character:isTumbling() then
		local keyBindingText =  sm.gui.getKeyBinding( "Use", true )
		sm.gui.setInteractionText( "", keyBindingText, "Use vehicle" )
		return true
	end
	return false
end

function KinematicRailVehicle.client_onInteract( self, character, state )
	if state == true then
		if not self.harvestable:getSeatCharacter() then
			self:cl_seat()
		end
	end
end

function KinematicRailVehicle.client_onAction( self, action, state )
	local previousInputFlags = self.cl.inputFlags
	local consumeAction = true
	if state == true then
		if action == sm.interactable.actions.use or action == sm.interactable.actions.jump then
			self:cl_seat()
		elseif action == sm.interactable.actions.left then
			self.cl.inputFlags = bit.bor( self.cl.inputFlags, Input.LEFT )
		elseif action == sm.interactable.actions.right then
			self.cl.inputFlags = bit.bor( self.cl.inputFlags, Input.RIGHT )
		elseif action == sm.interactable.actions.forward then
			self.cl.inputFlags = bit.bor( self.cl.inputFlags, Input.FORWARD )
		elseif action == sm.interactable.actions.backward then
			self.cl.inputFlags = bit.bor( self.cl.inputFlags, Input.BACKWARD )
		else
			consumeAction = false
		end
	else
		if action == sm.interactable.actions.left then
			self.cl.inputFlags = bit.band( self.cl.inputFlags, bit.bnot( Input.LEFT ) )
		elseif action == sm.interactable.actions.right then
			self.cl.inputFlags = bit.band( self.cl.inputFlags, bit.bnot( Input.RIGHT ) )
		elseif action == sm.interactable.actions.forward then
			self.cl.inputFlags = bit.band( self.cl.inputFlags, bit.bnot( Input.FORWARD ) )
		elseif action == sm.interactable.actions.backward then
			self.cl.inputFlags = bit.band( self.cl.inputFlags, bit.bnot( Input.BACKWARD ) )
		else
			consumeAction = false
		end
	end
	if bit.bxor( self.cl.inputFlags, previousInputFlags ) > 0 then
		self.network:sendToServer( "sv_n_input", { inputFlags = self.cl.inputFlags } )
	end
	return consumeAction
end

function KinematicRailVehicle.cl_seat( self )
	if sm.localPlayer.getPlayer() and sm.localPlayer.getPlayer():getCharacter() then
		self.harvestable:setSeatCharacter( sm.localPlayer.getPlayer():getCharacter() )
		self.cl.inputFlags = 0
	end
end