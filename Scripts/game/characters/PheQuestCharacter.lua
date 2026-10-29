dofile( "$SURVIVAL_DATA/Scripts/game/characters/BaseQuestActorCharacter.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/characters/shared_animation.lua" )

PheQuestCharacter = class( BaseQuestActorCharacter )


function PheQuestCharacter.client_onCreate( self )
	BaseQuestActorCharacter.client_onCreate( self )
	print( "-- PheQuestCharacter created --" )
end

function PheQuestCharacter.client_onGraphicsLoaded( self )
	self.cl.animations = self.cl.animations or {}
	local animTable = self.cl.animations
	local char = self.character
	INIT_ANIMATION_REND( animTable, char, "char_male_tp_npc_emote" )

	INIT_ANIMATION( animTable, char, "explain_in", { nextAnimation = "explain_loop", instantNext = true } )
	INIT_ANIMATION( animTable, char, "explain_loop", { inAnimation = "explain_in", nextAnimation = "explain_out", variation = {
        ["explain_special01"] = 0.2,
        ["explain_special02"] = 0.2,
        ["dialogue_explain_out"] = 0.2,
        ["explain_loop"] = 0.4
     }, instantNext = true } )
	INIT_ANIMATION( animTable, char, "explain_out" )
    INIT_ANIMATION( animTable, char, "dialogue_explain_out", { nextAnimation = "talk_idle" } )
    --emphasis dialogs
    INIT_ANIMATION( animTable, char, "explain_special01", { nextAnimation = "explain_loop", instantNext = true } )
    INIT_ANIMATION( animTable, char, "explain_special02", { nextAnimation = "explain_loop", instantNext = true } )
    INIT_ANIMATION( animTable, char, "talk_idle", { nextAnimation = "explain_loop", variation = {
        ["explain_in"] = 0.25,
        ["talk_idle"] = 0.75
    }, instantNext = true } )

	INIT_ANIMATION( animTable, char, "emote_casual_explain", { dialog = "loop", nextAnimation = "emote_casual_explain_out" } )
	INIT_ANIMATION( animTable, char, "emote_casual_explain_out", { dialog = true } )
	INIT_ANIMATION( animTable, char, "emote_casual_explain_out" )

	INIT_ANIMATION(animTable, char, "emote_shoot_loop")

	BaseQuestActorCharacter.client_onGraphicsLoaded( self )
end

function PheQuestCharacter.sv_n_interact( self, _, player )
	BaseQuestActorCharacter.sv_n_interact( self, _, player )
	QuestManager.Sv_SendEvent( QuestEvent.PheTalk )
end

--override
function PheQuestCharacter.cl_getLoopingDialogAnimations( self )
	return "explain_loop", "explain_in", "explain_special01", "explain_special02", "dialogue_explain_out", "talk_idle"
end
