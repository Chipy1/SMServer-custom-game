dofile( "$SURVIVAL_DATA/Scripts/game/quest_util.lua" )

DialogQuestActivator = class( nil )
DialogQuestActivator.isSaveObject = true

local State = {
    WaitingForPrerequisite = 1, -- Blocked by prerequisiteQuest or questEvent
    WaitingForDelay = 2,        -- Prerequisite met, counting down tickDelay
    PlayingDialog = 3,          -- Dialog sent to DialogManager, waiting for server-side completion
    TryActivateQuest = 4,       -- Attempting to activate the quest after dialog completion
}

function DialogQuestActivator.server_onCreate( self )
    self.sv = {}
    self.sv.saved = self.storage:load()

    if self.sv.saved == nil then
        self.sv.saved = {
            dialogUuid = self.params.dialogUuid,
            dialogEntry = self.params.dialogEntry,
            dialogType = self.params.dialogType,
            dialogSpeaker = self.params.dialogSpeaker,
            questName = self.params.questName,
            tickDelay = self.params.tickDelay or 0,
            prerequisiteQuest = self.params.prerequisiteQuest,
            log = self.params.log,
            state = State.WaitingForPrerequisite,
            prerequisiteQuestEvent = self.params.prerequisiteQuestEvent,
            prerequisiteTimeoutTicks = self.params.prerequisiteTimeoutTicks,
            prerequisiteStartTick = sm.game.getCurrentTick(),
        }
        self.storage:save( self.sv.saved )
    elseif self.sv.saved.state == State.PlayingDialog then
        if not DialogManager.Sv_IsDialogQueued( self.sv.saved.dialogUuid, self.sv.saved.dialogEntry ) then
            -- Dialog is no longer in the queue?
            -- Fall back to WaitingForDelay to re-submit.
            self.sv.saved.state = State.WaitingForDelay
            self.sv.saved.delayStartTick = sm.game.getCurrentTick()
            self.storage:save( self.sv.saved )
        end
    end

    if self.sv.saved.state == State.WaitingForPrerequisite and self.sv.saved.prerequisiteQuestEvent then
        QuestManager.Sv_SubscribeEvent( self.sv.saved.prerequisiteQuestEvent, self.scriptableObject, "sv_onPrerequisiteEvent" )
    end

    QuestManager.Sv_SubscribeEvent( QuestEvent.DialogCompleted, self.scriptableObject, "sv_onDialogCompleted" )

    if self.sv.saved.questName then
        QuestManager.Sv_RegisterQuestActivator( self.sv.saved.questName, self.scriptableObject )
    end

    if self.sv.saved.state == State.TryActivateQuest then
        sm.log.warning( "Finished DialogQuestActivator persited over sessions! Trying to activate quest: " .. tostring( self.sv.saved.questName ) )
    end
end

function DialogQuestActivator.server_onDestroy( self )
    if self.sv.saved and self.sv.saved.questName then
        QuestManager.Sv_UnregisterQuestActivator( self.sv.saved.questName, self.scriptableObject )
    end
    QuestManager.Sv_UnsubscribeAllEvents( self.scriptableObject )
end

-- Called when a subscribed prerequisite quest event fires
function DialogQuestActivator.sv_onPrerequisiteEvent( self )
    if self.sv.saved.prerequisiteQuestEvent then
        self.sv.saved.prerequisiteQuestEvent = nil
        self.storage:save( self.sv.saved )
    end
end

function DialogQuestActivator.sv_onDialogCompleted( self, data )
    local params = data.params
    if params.uuid == self.sv.saved.dialogUuid and params.entryName == self.sv.saved.dialogEntry then
        self.sv.saved.state = State.TryActivateQuest
        self.storage:save( self.sv.saved )
    end
end

function DialogQuestActivator.server_onFixedUpdate( self )
    local saved = self.sv.saved
    local currentTick = sm.game.getCurrentTick()

    if saved.state == State.WaitingForPrerequisite then
        if saved.prerequisiteQuest then
            if not QuestManager.Sv_IsQuestComplete( saved.prerequisiteQuest ) then
                return
            elseif currentTick < GetRewardDelay( saved.prerequisiteQuest ) then
                return
            end
        end

        if self.sv.saved.prerequisiteQuestEvent then
            -- Check timeout override
            if self.sv.saved.prerequisiteTimeoutTicks and currentTick >= self.sv.saved.prerequisiteStartTick + self.sv.saved.prerequisiteTimeoutTicks then
                self.sv.saved.prerequisiteQuestEvent = nil
            else
                return
            end
        end

        self.sv.saved.delayStartTick = sm.game.getCurrentTick()
        saved.state = State.WaitingForDelay
        self.storage:save( self.sv.saved )
        
    elseif saved.state == State.WaitingForDelay then
        if currentTick >= saved.delayStartTick + saved.tickDelay then
            DialogManager.Sv_PlayDialog( saved.dialogUuid, saved.dialogEntry, self.scriptableObject, saved.dialogType, saved.dialogSpeaker, DialogPriority.MainQuest )
            saved.state = State.PlayingDialog
            self.storage:save( self.sv.saved )
        end
    elseif saved.state == State.TryActivateQuest then
        local allDone = true
        if saved.questName and not QuestManager.Sv_IsQuestActive( saved.questName ) and not QuestManager.Sv_IsQuestComplete( saved.questName ) then
            QuestManager.Sv_TryActivateQuest( saved.questName )
            allDone = false
        end

        if saved.log and not LogEntryManager.Sv_HasLog( saved.log ) then
            LogEntryManager.Sv_AddLog( saved.log )
            allDone = false
        end

        if allDone then
            self.scriptableObject:destroy()
        end
    end
end