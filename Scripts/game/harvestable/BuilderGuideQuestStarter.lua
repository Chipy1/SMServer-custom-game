dofile("$SURVIVAL_DATA/Scripts/util.lua")
dofile( "$SURVIVAL_DATA/Scripts/game/interactables/BlendPoseButtonBase.lua" )

BuilderGuideQuestStarter = class( BlendPoseButtonBase )


function BuilderGuideQuestStarter.server_onCreate( self )
	self.sv = {}
	self.sv.storageFetched = false
end

function BuilderGuideQuestStarter.server_onFixedUpdate( self )
	if self.sv.storageFetched == false then
		local storageKey = TileStorageManager.Sv_GetTileStorageKeyFromObject( self.harvestable )
		local value = TileStorageManager.Sv_GetValueInSubTable( storageKey, BUILDERGUIDE_PLATFORM_TABLE, "platformQuest" )
		if value then
			self.sv.path = value.path
			self.sv.questName = value.questName
			self.network:setClientData( value )
			self.sv.storageFetched = true
		end
	end
end

function BuilderGuideQuestStarter.client_onCreate( self )
	BlendPoseButtonBase.client_onCreate( self )
end

function BuilderGuideQuestStarter.client_onUpdate( self, dt )
	BlendPoseButtonBase.client_onUpdate( self, dt )
end

function BuilderGuideQuestStarter.client_onInteract( self, _, state )
	BlendPoseButtonBase.client_onInteract( self, _, state )
	if state and self.cl.questName and not QuestManager.Cl_IsQuestComplete( self.cl.questName ) then
		if not QuestManager.Cl_IsQuestActive( self.cl.questName ) then
			self.network:sendToServer( "sv_n_startQuest" )
			return
		end
	end
end

function BuilderGuideQuestStarter.sv_n_startQuest( self )
	if self.sv.questName then
		QuestManager.Sv_ActivateQuest( self.sv.questName, { world = self.harvestable:getWorld(), pos = self.harvestable:getPosition(), path = self.sv.path } )
	end
end

function BuilderGuideQuestStarter.client_canInteract( self )
	if self.cl.questName == "quest_build_first_car" then
		TutorialManager.Cl_TutorialEvent( TutorialEvent.HowToBuildACar )
	end

	local keyBindingText = sm.gui.getKeyBinding( "Use", true )
	sm.gui.setInteractionText( "", keyBindingText, "#{INTERACTION_USE}" )
	
    return true
end


function BuilderGuideQuestStarter.client_onClientDataUpdate( self, data )
	self.cl.questName = data.questName
end