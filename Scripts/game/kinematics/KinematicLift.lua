dofile( "$SURVIVAL_DATA/Scripts/util.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/kinematics/Kinematic.lua" )

KinematicLift = class( Kinematic )


function KinematicLift.sv_n_activate( self )
	self:sv_activate()
end

function KinematicLift.client_canInteract( self, character )
	if character:getCharacterType() == unit_mechanic and not character:isTumbling() and not self.cl.updateData.moving then
		local keyBindingText =  sm.gui.getKeyBinding( "Use", true )
		sm.gui.setInteractionText( "", keyBindingText, "Use lift" )
		return true
	end
	return false
end

function KinematicLift.client_onInteract( self, character, state )
	if state == true then
		if not self:sv_isMoving() and not self.harvestable:getSeatCharacter() then
			self:cl_seat()
			self.network:sendToServer( "sv_n_activate" )
		end
	end
end

function KinematicLift.client_onAction( self, action, state )
	local consumeAction = true
	if state == true then
		if action == sm.interactable.actions.use or action == sm.interactable.actions.jump then
			self:cl_seat()
		else
			consumeAction = false
		end
	else
		consumeAction = false
	end
	return consumeAction
end

function KinematicLift.cl_seat( self )
	if sm.localPlayer.getPlayer() and sm.localPlayer.getPlayer():getCharacter() then
		self.harvestable:setSeatCharacter( sm.localPlayer.getPlayer():getCharacter() )
	end
end