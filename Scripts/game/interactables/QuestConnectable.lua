dofile( "$SURVIVAL_DATA/Scripts/game/survival_items.lua" )

QuestConnectable = class( nil )

QuestConnectable.maxParentCount = 1
QuestConnectable.maxChildCount = 1
QuestConnectable.colorNormal = sm.color.new( 0.8, 0.0, 0.8, 1.0 )
QuestConnectable.colorHighlight = sm.color.new( 0.8, 0.0, 0.8, 1.0 )
QuestConnectable.connectionInput = sm.interactable.connectionType.logic
QuestConnectable.connectionOutput = sm.interactable.connectionType.logic

local EventTickDelay = 4 -- Used to ensure that the associated quest has had time to subscribe to events before sending them

function QuestConnectable.server_onCreate( self )
    self.sv = {}
    self.sv.delayTick = 0
end

function QuestConnectable.server_onFixedUpdate( self )
    local activate = self:getInputs()
    if activate then
        if QuestManager.Sv_IsQuestActive( self.data.questName ) then
            self.sv.delayTick = self.sv.delayTick + 1
            if self.sv.delayTick >= EventTickDelay then
                if self.data.questEvent ~= nil then
                    QuestManager.Sv_SendEvent( self.data.questEvent )
                    self.shape:destroyShape()
                end
            end
        end
    end
end

function QuestConnectable.getInputs( self )
	local parents = self.interactable:getParents()
    local children = self.interactable:getChildren()
	local activate = false
	if parents[1] then
		if parents[1]:hasOutputType( sm.interactable.connectionType.logic ) then
			activate = true
		end
	end
    if children[1] and not activate then
        if children[1]:hasOutputType( sm.interactable.connectionType.logic ) then
            activate = true
        end
    end

	return activate
end

function QuestConnectable.client_onDestroy( self )
    if self.cl.effect then
        self.cl.effect:destroy()
    end
end

function QuestConnectable.client_onCreate( self )
    self.cl = {}
    self.cl.shouldShowLines = false
    self.cl.connectionShape = nil
    self.cl.effect = nil
    for _, shape in ipairs( self.shape:getBody():getCreationShapes() ) do
        if shape.uuid == self.shape.uuid then
            if shape.id == self.shape.id then
                break
            else
                self.cl.connectionShape = shape
                self.cl.shouldShowLines = true
                self.cl.effect = sm.effect.createEffect( "ConnectorPin", self.interactable )
                self.cl.effect:setOffsetPosition( sm.vec3.new( 0, 0, 0.5 ) )
                break
            end
        end
    end
end

function QuestConnectable.client_onUpdate( self )
    if QuestManager.Cl_IsQuestActive( self.data.questName ) then
        local quest = QuestManager.Cl_GetActiveQuest( self.data.questName )
        if quest and sm.exists( quest ) and quest.clientPublicData and quest.clientPublicData.showConnectTutorial then
            if self.cl.shouldShowLines and self.cl.connectionShape and sm.exists( self.cl.connectionShape ) then
                if self.cl.effect and not self.cl.effect:isPlaying() then
                    self.cl.effect:start()
                end
                local itemUuid = sm.localPlayer.getActiveItem()
                if itemUuid == ITEMS.tool_connect then
                    sm.visualization.drawLine( self.shape.worldPosition, self.cl.connectionShape.worldPosition )
                end
            end
        end
    end
end
