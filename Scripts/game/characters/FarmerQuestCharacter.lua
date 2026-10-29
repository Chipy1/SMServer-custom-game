dofile( "$SURVIVAL_DATA/Scripts/game/characters/BaseQuestActorCharacter.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/characters/shared_animation.lua" )

FarmerQuestCharacter = class( BaseQuestActorCharacter )


function FarmerQuestCharacter.client_onCreate( self )
	BaseQuestActorCharacter.client_onCreate( self )
	print( "-- FarmerQuestCharacter created --" )
end

function FarmerQuestCharacter.client_onGraphicsLoaded( self )
	self.cl.animations = self.cl.animations or {}
	local animTable = self.cl.animations
	local char = self.character

	INIT_ANIMATION_REND( animTable, char, "char_male_tp_npc_emote" )
	INIT_ANIMATION_REND( animTable, char, "engine_blast_reactions" )
	BaseQuestActorCharacter.client_onGraphicsLoaded( self )
end
