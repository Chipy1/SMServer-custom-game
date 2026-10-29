InteractableDummy = class()

-- used on objects lacking scripts that need to be picked up by the QuestPinManager

function InteractableDummy.client_canInteract( self, character )
	if not sm.localPlayer.secondaryInteractBusy() then
		sm.gui.setInteractionText( "", sm.gui.getKeyBinding( "Attack", true ), "#{INTERACTION_PICK_UP_HOLD}" )
	end
	return true
end