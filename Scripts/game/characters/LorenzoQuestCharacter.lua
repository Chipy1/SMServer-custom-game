dofile( "$SURVIVAL_DATA/Scripts/game/characters/BaseQuestActorCharacter.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/characters/shared_animation.lua" )

LorenzoQuestCharacter = class( BaseQuestActorCharacter )


function LorenzoQuestCharacter.client_onCreate( self )
	BaseQuestActorCharacter.client_onCreate( self )
	print( "-- LorenzoQuestCharacter created --" )
end

function LorenzoQuestCharacter.server_onCreate( self )
	BaseQuestActorCharacter.server_onCreate( self )

	-- PATCH (recovery) ------------------------------------------------------------
	-- In the case of lorenzo's quest marker is in the wrong place at this stage force update it.
	local endGameQuest = QuestManager.Sv_GetQuest( "quest_endgame" )
	if endGameQuest and endGameQuest.publicData.stage and endGameQuest.publicData.stage == EndGameQuest.Stages.return_to_lorenzo then
		sm.event.sendToScriptableObject( endGameQuest, "sv_n_updateMarkers" )
	end
end

function LorenzoQuestCharacter.client_onGraphicsLoaded( self )
	self.cl.animations = self.cl.animations or {}
	local animTable = self.cl.animations
	local char = self.character
	INIT_ANIMATION_REND( animTable, char, "char_male_tp_npc_emote" )
	INIT_ANIMATION( animTable, char, "shipmechanic_drillbot_outside" )
	INIT_ANIMATION( animTable, char, "shipmechanic_drillbot_exit" )
	INIT_ANIMATION( animTable, char, "emote_slap" )
	INIT_ANIMATION( animTable, char, "explain_in", { nextAnimation = "explain_loop" } )
	INIT_ANIMATION( animTable, char, "explain_loop", { inAnimation = "explain_in", nextAnimation = "explain_out", variation = {
        ["explain_special01"] = 0.17,
        ["explain_special02"] = 0.17,
        ["dialogue_explain_out"] = 0.12,
        ["explain_loop"] = 0.54
     }, instantNext = true } )
	INIT_ANIMATION( animTable, char, "explain_out", { dialog = true } )

	INIT_ANIMATION( animTable, char, "l_hunkerdown_idle", { variation = {
        ["l_hunkerdown_shake"] = 0.25,
        ["l_hunkerdown_idle"] = 0.75
     }, instantNext = true } )

	INIT_ANIMATION( animTable, char, "l_hunkerdown_shake", { nextAnimation = "l_hunkerdown_idle", instantNext = true } )
	INIT_ANIMATION( animTable, char, "l_hunkerdown_point" )

	INIT_ANIMATION( animTable, char, "emote_rumble01" )
	INIT_ANIMATION( animTable, char, "emote_rumble02" )

	INIT_ANIMATION( animTable, char, "dialogue_explain_out", { nextAnimation = "talk_idle" } )
	INIT_ANIMATION( animTable, char, "explain_special01", { nextAnimation = "explain_loop" } )
    INIT_ANIMATION( animTable, char, "explain_special02", { nextAnimation = "explain_loop" } )
    INIT_ANIMATION( animTable, char, "talk_idle", { nextAnimation = "explain_loop", variation = {
        ["explain_in"] = 0.25,
        ["talk_idle"] = 0.75
    }, instantNext = true } )
	BaseQuestActorCharacter.client_onGraphicsLoaded( self )
end

function LorenzoQuestCharacter.sv_n_interact( self, _, player )
    BaseQuestActorCharacter.sv_n_interact( self, _, player )
    -- old quest specific events
	local interactionData = QuestManager.Sv_GetNpcInteractionData( QuestUnits.Lorenzo )
	if interactionData and interactionData.item and interactionData.item == sm.uuid.new( "03bdd942-c808-4795-aa0b-554fa98c3c74" ) then
		local inventory = player:getInventory()
		if inventory then
			sm.container.beginTransaction()
			inventory:collect( interactionData.item, 1, true )
			if sm.container.endTransaction() then
				QuestManager.Sv_SetNpcInteractionData( QuestUnits.Lorenzo, { canInteract = false } )
			end
		end
	end
    QuestManager.Sv_SendEvent( QuestEvent.LorenzoTalk )
end


--override
function LorenzoQuestCharacter.cl_getLoopingDialogAnimations( self )
	return "explain_loop", "explain_in", "explain_out", "explain_special01", "explain_special02", "dialogue_explain_out", "talk_idle"
end


-- old quest specific events
function LorenzoQuestCharacter.sv_n_giveBoombox( self, _, player )
	QuestManager.Sv_SendEvent( "give_boombox" )
end

function LorenzoQuestCharacter.cl_e_giveBoombox( self )
	if sm.isHost then
		self.network:sendToServer( "sv_n_giveBoombox" )
	end
end