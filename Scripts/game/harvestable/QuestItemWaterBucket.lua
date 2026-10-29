dofile( "$SURVIVAL_DATA/Scripts/game/managers/TutorialManager.lua" )

QuestItemWaterBucket = class( nil )
local TutorialActivationDistance = 8.5

function QuestItemWaterBucket.server_onCreate( self )
end

function QuestItemWaterBucket.client_onCreate( self )
end

function QuestItemWaterBucket.client_canInteract( self, character )
	if not sm.localPlayer.secondaryInteractBusy() then
		sm.gui.setInteractionText( "", sm.gui.getKeyBinding( "Attack", true ), "#{INTERACTION_PICK_UP_HOLD}" )
	end
	return true
end

function QuestItemWaterBucket.client_onFixedUpdate( self )
	local myCharacter = sm.localPlayer.getPlayer().character
	if sm.exists( myCharacter ) then
		local distance2 = ( myCharacter.worldPosition - self.harvestable.worldPosition ):length2()
		if distance2 <= TutorialActivationDistance^2 then
			TutorialManager.Cl_TutorialEvent( TutorialEvent.PickUpBucket )
		end
	end
end

function QuestItemWaterBucket.server_canErase( self )
	return true
end

function QuestItemWaterBucket.client_canErase( self )
	return true
end

function QuestItemWaterBucket.server_onRemoved( self, player )
	if not self.removed and sm.exists( self.harvestable ) then
		if sm.container.beginTransaction() then
			sm.container.collect( player:getInventory(), obj_tool_bucket_empty, 1, true )
			if sm.container.endTransaction() then
				self.harvestable:destroy()
				self.removed = true
				sm.effect.playEffect( "Part - Removed", self.harvestable.worldPosition )
			end
		end
	end
end
