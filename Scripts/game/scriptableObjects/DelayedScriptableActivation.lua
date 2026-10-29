dofile( "$SURVIVAL_DATA/Scripts/game/quest_util.lua" )

DelayedScriptableActivation = class( nil )
DelayedScriptableActivation.isSaveObject = true

function DelayedScriptableActivation.server_onCreate( self )
    self.sv = {}
    self.sv.saved = self.storage:load()
    if self.sv.saved == nil then
        self.sv.saved = {}
        self.sv.saved.questName = self.params.questName
        self.sv.saved.questEvent = self.params.questEvent
        self.sv.saved.prerequisiteEvent = self.params.prerequisiteEvent
        self.sv.saved.tutorialEvent = self.params.tutorialEvent
        self.sv.saved.activationDelay = self.params.tickDelay
        self.sv.saved.hidden = self.params.hidden
        self.sv.saved.activationTick = math.floor( sm.game.getServerTick() + self.sv.saved.activationDelay )
        self.storage:save( self.sv.saved )
    end
    self.sv.waitingForEvent = false
    if self.sv.saved.prerequisiteEvent then
        self.sv.waitingForEvent = true
        QuestManager.Sv_SubscribeEvent( self.sv.saved.prerequisiteEvent, self.scriptableObject, "sv_onEvent" )
    end
    
    if self.sv.saved.questName then
        QuestManager.Sv_RegisterQuestActivator( self.sv.saved.questName, self.scriptableObject )
    end
end

function DelayedScriptableActivation.server_onDestroy( self )
    if self.sv.saved and self.sv.saved.questName then
        QuestManager.Sv_UnregisterQuestActivator( self.sv.saved.questName, self.scriptableObject )
    end
    QuestManager.Sv_UnsubscribeAllEvents( self.scriptableObject )
end

function DelayedScriptableActivation.sv_onEvent( self )
    if self.sv.waitingForEvent then
        self.sv.waitingForEvent = false
        self.sv.saved.activationTick = math.floor( sm.game.getServerTick() + self.sv.saved.activationDelay )
        self.storage:save( self.sv.saved )
    end
end

function DelayedScriptableActivation.server_onFixedUpdate( self )

    if self.sv.waitingForEvent then
        return
    end

    local currentTick = sm.game.getServerTick()
    if self.sv.saved.activationTick <= currentTick then
        if self.sv.saved.questEvent then
            QuestManager.Sv_SendEvent( self.sv.saved.questEvent )
        end
        if self.sv.saved.tutorialEvent then
            TutorialManager.Sv_TutorialEvent( self.sv.saved.tutorialEvent )
        end
        if self.sv.saved.questName then
            QuestManager.Sv_TryActivateQuest( self.sv.saved.questName, self.sv.saved.hidden )
        end
        QuestManager.Sv_UnsubscribeAllEvents( self.scriptableObject )
        self.scriptableObject:destroy()
    end
end