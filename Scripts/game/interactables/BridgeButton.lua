dofile( "$SURVIVAL_DATA/Scripts/game/interactables/LockedActivationButton.lua" )

BridgeButton = class( LockedActivationButton )

local BridgeManagerUuid = sm.uuid.new( "5876231c-667d-4690-8e3f-3e99da05dc83" )

-- Server

function BridgeButton.server_onCreate( self )
    LockedActivationButton.server_onCreate( self )
    self.network:setClientData( self.sv.saved )
    QuestManager.Sv_SubscribeEvent( "bridgeQuestEvent", self.interactable, "sv_e_unlockButton" )
end

function BridgeButton.sv_e_unlockButton( self )
    self.sv.saved.state = LockedActivationButton.States.open
    self:sv_saveAndSync()
end

function BridgeButton.server_onDestroy( self )
    QuestManager.Sv_UnsubscribeEvent( "bridgeQuestEvent", self.interactable )
end

function BridgeButton.sv_n_activate( self  )
    if not self.sv.saved.state ~= LockedActivationButton.States.open then
        QuestManager.Sv_SendEvent( "bridge_button_pressed", { position = self.shape.worldPosition } )
        sm.scriptableObject.createScriptableObject( BridgeManagerUuid, { position = self.shape:getWorldPosition() }, self.shape.body:getWorld() )
        LockedActivationButton.sv_n_activate( self )
    end



end

-- Client

function BridgeButton.client_onClientDataUpdate( self, data, channel )
    LockedActivationButton.client_onClientDataUpdate( self, data, channel )
end

function BridgeButton.client_canInteract( self )
    local quest = QuestManager.Cl_GetActiveQuest( "quest_find_excavation" )
    quest = sm.exists( quest ) and quest or nil
    if quest and quest.clientPublicData then
        local onButtonStep = quest.clientPublicData.onButtonStep
        if onButtonStep then
            return true
        end
    end






    return false
end