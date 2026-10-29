dofile( "$SURVIVAL_DATA/Scripts/game/interactables/Chest.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/managers/QuestManager.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/quests/EndGameQuest.lua" )

---@class ShipCompartment : Chest
ShipCompartment = class( Chest )

function ShipCompartment.client_canInteract( self )
	-- The locker only opens once the player has reached the crashed ship.
	local stage = QuestManager.Cl_GetQuestStage( "quest_endgame" )
	return stage ~= nil and stage >= EndGameQuest.Stages.pickup_photo
end
