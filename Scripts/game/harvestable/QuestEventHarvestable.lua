dofile "$SURVIVAL_DATA/Scripts/game/harvestable/LogbookEntryHarvestable.lua"

QuestEventHarvestable = class( LogbookEntryHarvestable )

-- Server
function QuestEventHarvestable.server_onCreate( self )
    self.sv = {}
    self.sv.saved = self.storage:load()
    if self.sv.saved == nil then
        self.sv.saved = {}
        if self.params then
            self.sv.saved = self.params
        end
        self.storage:save( self.sv.saved )
    end
    self.sv.destroyed = false
    self.network:setClientData( { displayItemUuid = self.sv.saved.displayItemUuid } )
	self.harvestable.publicData = { vacuumable = false }
    if self.sv.saved.spawnEffect then
        sm.effect.playEffect( self.sv.saved.spawnEffect, self.harvestable.worldPosition )
    end
    self.sv.worldPos = self.harvestable.worldPosition
end

function QuestEventHarvestable.server_canErase( self )
    return true
end

function QuestEventHarvestable.sv_n_harvest( self, state )
    if self.sv.saved.delay then
        if self.sv.saved.questName ~= "" then
            sm.scriptableObject.createScriptableObject( sm.uuid.new( "d9458830-7899-4dd5-aae9-703cf9d46782" ), { questName = self.sv.saved.questName, delay = self.sv.saved.delay } )
        end
        if self.sv.saved.questEvent ~= "" then
            sm.scriptableObject.createScriptableObject( sm.uuid.new( "d9458830-7899-4dd5-aae9-703cf9d46782" ), { questEvent = self.sv.saved.questEvent, delay = self.sv.saved.delay } )
        end
    else
        if self.sv.saved.questName ~= "" then
            QuestManager.Sv_TryActivateQuest( self.sv.saved.questName )
        end
        if self.sv.questEvent ~= "" then
            QuestManager.Sv_SendEvent( self.sv.saved.questEvent )
        end
        if self.sv.saved.interactEffect then
            sm.effect.playEffect( self.sv.saved.interactEffect, self.sv.worldPos )
        end
    end
    if not self.sv.destroyed then
        if self.harvestable then
            self.sv.destroyed = true
            sm.harvestable.destroy( self.harvestable )
        end
    end
end

-- Client

function QuestEventHarvestable.client_canErase( self )
    return true
end

function QuestEventHarvestable.client_canInteract( self )
    local keyBindingText = GetInteractionKeybinding()
    sm.gui.setInteractionText( "", keyBindingText, "#{INTERACTION_PICK_UP}" )
    return true
end

function QuestEventHarvestable.client_onClientDataUpdate( self, data )
    self.cl.displayItemUuid = data.displayItemUuid
    self:cl_startEffect()
end