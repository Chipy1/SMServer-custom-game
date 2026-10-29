dofile( "$SURVIVAL_DATA/Scripts/game/kinematics/ParentedKinematic.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/quests/ActivateMininghubQuest.lua" )

ParentedKinematicMininghubLever = class( ParentedKinematic )

local MininghubLightManagerUuid = sm.uuid.new( "53b762b3-f2f9-4faa-beca-750fa99c31c2" )

-- Server

function ParentedKinematicMininghubLever.server_onCreate( self )
	ParentedKinematic.server_onCreate( self )
	local progressData = self.sv.trackInstances["track"].progressData
	local onFirstNode = progressData.segmentIndex == 1 and progressData.segmentProgress == 0
	self.sv.used = not onFirstNode
	self.network:setClientData( { usable = onFirstNode }, 3 )
end

function ParentedKinematicMininghubLever.sv_n_activate( self )
	if self.sv.used then
		return
	end
	self.sv.used = true
	self:sv_activate()
	self.network:setClientData( { usable = false }, 3 )
	QuestManager.Sv_SendEvent( "mininghub_lever_pulled", { position = self.harvestable.worldPosition } )
	sm.scriptableObject.createScriptableObject( MininghubLightManagerUuid, { position = self.harvestable.worldPosition }, self.harvestable:getWorld() )
end

-- Client

function ParentedKinematicMininghubLever.client_onCreate( self )
	ParentedKinematic.client_onCreate( self )
	self.cl.usable = true
end

function ParentedKinematicMininghubLever.client_onClientDataUpdate( self, data, channel )
	if channel == 3 then
		self.cl.usable = data.usable
	else
		ParentedKinematic.client_onClientDataUpdate( self, data, channel )
	end
end

function ParentedKinematicMininghubLever.client_canInteract( self )
	if not self.cl.usable then
		return false
	end
	if DialogManager.Cl_IsRunning() then
		return false
	end
	local stage = QuestManager.Cl_GetQuestStage( "quest_activate_mininghub" )
	if stage == ActivateMininghubQuest.Stages.activate_pylon then
		sm.gui.setInteractionText( "", sm.gui.getKeyBinding( "Use", true ), "#{INTERACTION_USE}" )
		return true
	end
	return false
end

function ParentedKinematicMininghubLever.client_onInteract( self, character, state )
	if state == true then
		sm.effect.playEffect( "Elevator Button", self.harvestable.worldPosition )
		self.network:sendToServer( "sv_n_activate" )
	end
end
