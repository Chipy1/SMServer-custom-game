QuotaMeter = class( nil )

dofile( "$SURVIVAL_DATA/Scripts/game/managers/QuestManager.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/managers/ProgressionManager.lua" )

-- The progress bar submesh ("m_bar") uses the UVAnimDifAsg material with uv0.u = 1/30,
-- i.e. 30 horizontal frames. Frame 0 = empty bar, frame 29 = full bar.
local UV_FRAME_COUNT = 30

-- Vault quota quests in order; index doubles as the displayed quota "level"
local VAULT_QUESTS = {
	"quest_vault_1",
	"quest_vault_2",
	"quest_vault_3"
}

function QuotaMeter.client_onCreate( self )
	self.cl = {}
	self.cl.textEffect = sm.effect.createEffect( "Miningvault - QuotameterText", self.interactable )
	self.cl.textEffect:setOffsetRotation( sm.quat.rotNegX90() )
	self.cl.textEffect:start()

    self.cl.target = -1
    self.cl.total = -1
    self.cl.questIdx = -1
    self.cl.progress = -1
    self.cl.tick = 0
end

function QuotaMeter.client_onFixedUpdate( self, timestep )
    self.cl.tick = self.cl.tick + 1
    if self.cl.tick % 20 == 0 then
        local total = ProgressionManager.Cl_GetVaultTotal()
        if total ~= self.cl.total then
            self.cl.textEffect:setParameter( "total.TextContent", "a "..FormatVaultNumber( total, true ) )
            self.cl.total = total
        end

        local questIdx = 0
        for idx, questName in ipairs( VAULT_QUESTS ) do
            if QuestManager.Cl_IsQuestComplete( questName ) then
                questIdx = idx
            elseif QuestManager.Cl_IsQuestActive( questName ) then
                local waitingForLorenzoDialog = idx == 2 and QuestManager.Cl_GetQuestStage( VAULT_QUESTS[2] ) < 2
                if not waitingForLorenzoDialog then
                    questIdx = idx
                end
                break
            end
        end

        if questIdx ~= self.cl.questIdx then
            self.cl.textEffect:setParameter( "level.TextContent", questIdx == 0 and "" or tostring( questIdx ) )
            self.cl.questIdx = questIdx
        end

        local activeQuota = QuestManager.Cl_IsQuestActive( VAULT_QUESTS[questIdx] )
        if activeQuota then
            local target = QuestManager.Cl_GetQuestData( VAULT_QUESTS[questIdx] ).trackingSteps.quota.threshold
            if target ~= self.cl.target then
                self.cl.textEffect:setParameter( "target.TextContent", "a "..FormatVaultNumber( target, true ) )
                self.cl.target = target
            end

            local progress = math.max( 0, math.min( total / target, 1 ) )
            if self.cl.progress ~= progress then
                local frame = math.min( math.floor( progress * UV_FRAME_COUNT ), UV_FRAME_COUNT - 1 )
                self.interactable:setUvFrameIndex( frame )
                self.cl.progress = progress
            end
        else
            if self.cl.target ~= 0 then
                self.cl.textEffect:setParameter( "target.TextContent", "" )
                self.interactable:setUvFrameIndex( questIdx == 0 and 0 or UV_FRAME_COUNT )
                self.cl.target = 0
            end
        end
    end
end
