dofile( "$SURVIVAL_DATA/Scripts/game/characters/BaseQuestActorCharacter.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/characters/shared_animation.lua" )

MechanicQuestCharacter = class( BaseQuestActorCharacter )


function MechanicQuestCharacter.client_onCreate( self )
	BaseQuestActorCharacter.client_onCreate( self )
	print( "-- MechanicQuestCharacter created --" )
end

function MechanicQuestCharacter.client_onGraphicsLoaded( self )
	self.cl.animations = self.cl.animations or {}
	local animTable = self.cl.animations
	local char = self.character	

	INIT_ANIMATION_REND( animTable, char, "char_male_tp_npc_emote" )
	INIT_ANIMATION_REND( animTable, char, "engine_blast_reactions" )
	INIT_ANIMATION(animTable, char, "scrapper_bye")
	INIT_ANIMATION(animTable, char, "axobot_bye")
	INIT_ANIMATION(animTable, char, "emote_shoot_loop")
	BaseQuestActorCharacter.client_onGraphicsLoaded( self )
end
