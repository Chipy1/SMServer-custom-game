dofile( "$SURVIVAL_DATA/Scripts/game/characters/BaseQuestActorCharacter.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/characters/shared_animation.lua" )

HubertQuestCharacter = class( BaseQuestActorCharacter )


function HubertQuestCharacter.client_onCreate( self )
	BaseQuestActorCharacter.client_onCreate( self )
	print( "-- HubertQuestCharacter created --" )

    DialogManager.Cl_RegisterSpeaker( self.character, DialogSpeakerName.Mysterious )
end

function HubertQuestCharacter.client_onRefresh( self )
    self:client_onGraphicsLoaded()
end

function HubertQuestCharacter.client_onGraphicsLoaded( self )
    
    print( "-- HubertQuestCharacter.client_onGraphicsLoaded --" )
    self.cl.animations = self.cl.animations or {}
    local animTable = self.cl.animations
    local char = self.character
    INIT_ANIMATION_REND( animTable, char, "char_male_tp_npc_emote" )
    
    -- setup hubert dialog animations
    INIT_ANIMATION( animTable, char, "explain_in", { nextAnimation = "explain_loop", instantNext = true } )
    INIT_ANIMATION( animTable, char, "explain_loop", { inAnimation = "explain_in", nextAnimation = "explain_out", variation = {
        ["explain_special01"] = 0.2,
        ["explain_special02"] = 0.2,
        ["dialogue_explain_out"] = 0.25,
        ["explain_loop"] = 0.35
     }, instantNext = true } )
    INIT_ANIMATION( animTable, char, "explain_out" )
    INIT_ANIMATION( animTable, char, "dialogue_explain_out", { nextAnimation = "talk_idle" } )
    --emphasis dialogs
    INIT_ANIMATION( animTable, char, "explain_special01", { nextAnimation = "explain_loop", instantNext = true } )
    INIT_ANIMATION( animTable, char, "explain_special02", { nextAnimation = "explain_loop", instantNext = true } )
    INIT_ANIMATION( animTable, char, "talk_idle", { nextAnimation = "explain_loop", variation = {
        ["explain_in"] = 0.4,
        ["talk_idle"] = 0.45,
        ["emote_scratchbutt"] = 0.15
    }, instantNext = true } )
    INIT_ANIMATION( animTable, char, "emote_scratchbutt", { nextAnimation = "talk_idle" } )

    -- drillbot cinematic animations
    INIT_ANIMATION( animTable, char, "emote_crying" )
    INIT_ANIMATION( animTable, char, "emote_crying_standup" )
    -- chance to intersperse cower animations with looping cower
    INIT_ANIMATION( animTable, char, "emote_cower_loop", { variation = {
        ["emote_cower_special01"] = 0.15,
        ["emote_cower_special02"] = 0.35,
        ["emote_cower_loop"] = 0.5
    }, instantNext = true } )
    INIT_ANIMATION( animTable, char, "emote_cower_special01", { nextAnimation = "emote_cower_loop", instantNext = true } )
    INIT_ANIMATION( animTable, char, "emote_cower_special02", { nextAnimation = "emote_cower_loop", instantNext = true } )
    INIT_ANIMATION_REND( animTable, char, "engine_blast_reactions" )
    INIT_ANIMATION( animTable, char, "emote_cower_out", { instantNext = true } )
    
    INIT_ANIMATION( animTable, char, "emote_rumble01" )
    
    BaseQuestActorCharacter.client_onGraphicsLoaded( self )
end

-- override
function HubertQuestCharacter.sv_n_interact( self, _, player )
    BaseQuestActorCharacter.sv_n_interact( self, _, player )

    -- hubert quest specific event
    QuestManager.Sv_SendEvent( QuestEvent.FarmerTalk, { player = player } )
end

-- override
function HubertQuestCharacter.cl_getLoopingDialogAnimations( self )
    return "explain_loop", "explain_in", "explain_special01", "explain_special02", "dialogue_explain_out", "talk_idle", "emote_scratchbutt"
end