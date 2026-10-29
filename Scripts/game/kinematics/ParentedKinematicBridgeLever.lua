dofile( "$SURVIVAL_DATA/Scripts/game/kinematics/ParentedKinematic.lua" )

ParentedKinematicBridgeLever = class( ParentedKinematic )

local BridgeManagerUuid = sm.uuid.new( "5876231c-667d-4690-8e3f-3e99da05dc83" )

-- Server

function ParentedKinematicBridgeLever.server_onCreate( self )
	ParentedKinematic.server_onCreate( self )
	local progressData = self.sv.trackInstances["track"].progressData
	local onFirstNode = progressData.segmentIndex == 1 and progressData.segmentProgress == 0
	self.sv.used = not onFirstNode
	self.network:setClientData( { usable = onFirstNode }, 3 )
end

function ParentedKinematicBridgeLever.sv_n_activate( self )
	if self.sv.used then
		return
	end
	self.sv.used = true
	self:sv_activate()
	self.network:setClientData( { usable = false }, 3 )
	QuestManager.Sv_SendEvent( "bridge_button_pressed", { position = self.harvestable.worldPosition } )
	sm.scriptableObject.createScriptableObject( BridgeManagerUuid, { position = self.harvestable.worldPosition }, self.harvestable:getWorld() )
end

-- Client
function ParentedKinematicBridgeLever.client_onCreate( self )
	ParentedKinematic.client_onCreate( self )
	self.cl.usable = true
end

function ParentedKinematicBridgeLever.client_onClientDataUpdate( self, data, channel )
	if channel == 3 then
		if data.usable ~= nil then
			self.cl.usable = data.usable
		end
	else
		ParentedKinematic.client_onClientDataUpdate( self, data, channel )
	end
end

function ParentedKinematicBridgeLever.client_canInteract( self )
	if not self.cl.usable then
		return false
	end
	local quest = QuestManager.Cl_GetActiveQuest( "quest_find_excavation" )
    quest = sm.exists( quest ) and quest or nil
    if quest and quest.clientPublicData then
        local onButtonStep = quest.clientPublicData.onButtonStep
        if onButtonStep then
			sm.gui.setInteractionText( "", sm.gui.getKeyBinding( "Use", true ), "#{INTERACTION_USE}" )
            return true
        end
    end
	return false
end

function ParentedKinematicBridgeLever.client_onInteract( self, character, state )
	if state == true then
		sm.effect.playEffect( "Elevator Button", self.harvestable.worldPosition )
		self.network:sendToServer( "sv_n_activate" )
	end
end