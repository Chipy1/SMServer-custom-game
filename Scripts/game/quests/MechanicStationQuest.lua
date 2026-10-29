dofile( "$SURVIVAL_DATA/Scripts/game/managers/QuestManager.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/quest_util.lua" )

MechanicStationQuest = class()
MechanicStationQuest.isSaveObject = true

local Stages = {
	to_station = 1,
	explore_station = 2,
	find_battery = 3,
	activate_station = 4,
	build_craftbot = 5,
	wait_for_crafter = 6
}

local StationAreaTrigger = "quest_mechanicstation.area_mechanicstation"
local StationInsideTrigger = "quest_mechanicstation.area_mechanicstationinside"

function MechanicStationQuest.server_onCreate( self )
	self.sv = {}
	self.sv.saved = self.storage:load()
	if self.sv.saved == nil then
		self.sv.saved = {}
		self.sv.saved.stage = Stages.to_station
		local tileStorageKey = TileStorageManager.Sv_GetTileStorageKeyFromCell( WorldManager.Sv_GetWorld( "overworld" ), -29, -26 )

		-- NOTE patch legacy usage of tile storage "power_restored".
		if TileStorageManager.Sv_GetValue( tileStorageKey, "power_restored" ) then
			TileStorageManager.Sv_SetValueInSubTable( tileStorageKey, POWER_CORE_SOCKET_TABLE, "power_restored", true )
			TileStorageManager.Sv_SetValue( tileStorageKey, "power_restored", nil )
		end
		local value = TileStorageManager.Sv_GetValueInSubTable( tileStorageKey, POWER_CORE_SOCKET_TABLE, "power_restored" )
		if value then
			self.sv.saved.stage = Stages.build_craftbot
		end
	end
	QuestManager.Sv_SubscribeEvent( QuestEvent.InventoryChanges, self.scriptableObject, "sv_e_onQuestEvent" )
	QuestManager.Sv_SubscribeEvent( "event.quest_mechanicstation.power_restored", self.scriptableObject, "sv_e_onQuestEvent" )
	QuestManager.Sv_SubscribeEvent( QuestEvent.InteractableCreated, self.scriptableObject, "sv_e_onQuestEvent" )
	QuestManager.Sv_SubscribePlayerEnterAreaTrigger( StationAreaTrigger, self.scriptableObject, "sv_e_onQuestEvent" )
	QuestManager.Sv_SubscribePlayerEnterAreaTrigger( StationInsideTrigger, self.scriptableObject, "sv_e_onQuestEvent" )
	QuestManager.Sv_SubscribeEvent( QuestEvent.DispenserSpawnShape, self.scriptableObject, "sv_e_onQuestEvent" )
	QuestManager.Sv_SubscribeEvent( QuestEvent.DispenserCraftStarted, self.scriptableObject, "sv_e_onQuestEvent" )






	QuestPinManager.Sv_AddWatchedUuid( obj_survivalobject_powercore, "PickUpPin", sm.vec3.new( 0, 0, 0.5 ) )

	sm.event.sendToScriptableObject( self.scriptableObject, "sv_e_onQuestEvent", {} )

	if self.sv.saved.stage == Stages.build_craftbot then
		self.scriptableObject.publicData = { activatePhone = true }
	end
	if self.sv.saved.stage < Stages.find_battery then
		self:sv_checkForBattery()
	end
	self:sv_saveAndSync()
end

function MechanicStationQuest.sv_checkForBattery( self )
    local players = sm.player.getAllPlayers()
    for _, player in ipairs( players ) do
        local coreCount = sm.container.totalQuantity( player:getInventory(), obj_survivalobject_powercore )
        if coreCount >= 1 then
			self.sv.saved.stage = Stages.activate_station
		end
    end
end



















function MechanicStationQuest.sv_saveAndSync( self )
	self.storage:save( self.sv.saved )
	self.network:setClientData( { stage = self.sv.saved.stage } )
end

function MechanicStationQuest.sv_e_onQuestEvent( self, data )
	if data.event == StationAreaTrigger .. QuestEvent.AreaTriggerPlayerEnterSuffix then
		if self.sv.saved.stage == Stages.to_station then
			self.sv.saved.stage = Stages.explore_station
			QuestEntityManager.Sv_BumpNamedAreaTrigger( StationInsideTrigger )
		end
	elseif data.event == StationInsideTrigger .. QuestEvent.AreaTriggerPlayerEnterSuffix then
		if self.sv.saved.stage == Stages.explore_station then
			self.sv.saved.stage = Stages.find_battery
		end
	elseif data.event == QuestEvent.InventoryChanges then
		if FindInventoryChange( data.params.changes, obj_survivalobject_powercore ) > 0 then
			self.sv.saved.stage = Stages.activate_station
		end
	elseif data.event == "event.quest_mechanicstation.power_restored" then
		self.scriptableObject.publicData = { activatePhone = true }
		self.sv.saved.stage = Stages.build_craftbot
		local world = WorldManager.Sv_GetWorld( "overworld" )
		local tileKey = TileStorageManager.Sv_GetTileStorageKeyFromCell( world, -29, -26 )
		SetTileStorageFlag( tileKey, "effect" )
		EffectManager.Sv_UpdateTagFilteredEffectsForTile( world, sm.vec3.new( -29, -26, 0 ) * 64, { "effect" } )
	elseif data.event == QuestEvent.DispenserSpawnShape then
		if data.params.shapeUuid == obj_craftbot_craftbot1 then
			self:sv_completeQuest()
		end
	elseif data.event == QuestEvent.DispenserCraftStarted then
		if self.sv.saved.stage == Stages.build_craftbot then
			self.sv.saved.stage = Stages.wait_for_crafter
		end
	end

	self:sv_saveAndSync()
end

function MechanicStationQuest.sv_completeQuest( self )
	QuestManager.Sv_UnsubscribeAllEvents( self.scriptableObject )
	QuestPinManager.Sv_RemoveWatchedUuid( obj_survivalobject_powercore )
	local world = WorldManager.Sv_GetWorld( "overworld" )
	local tileKey = TileStorageManager.Sv_GetTileStorageKeyFromCell( world, -29, -26 )
	SetTileStorageFlag( tileKey, "effect" )
	EffectManager.Sv_UpdateTagFilteredEffectsForTile( world, sm.vec3.new( -29, -26, 0 ) * 64, { "effect" } )
	CompleteQuest( "quest_mechanicstation" )
end

function MechanicStationQuest.client_onCreate( self )
	QuestManager.Cl_OnQuestCreated( "quest_mechanicstation" )
	self.cl = {}
	self.scriptableObject.clientPublicData = {}
	self.scriptableObject.clientPublicData.progressString = ""
	sm.item.addTrackedItem( obj_survivalobject_powercore, sm.item.trackingType.mainQuest )
end

function MechanicStationQuest.client_onDestroy( self )
	sm.item.removeTrackedItem( obj_survivalobject_powercore, sm.item.trackingType.mainQuest )
	QuestEntityManager.Cl_DeactivateEventPing( "ping_mechanicstation_socket" )
	QuestEntityManager.Cl_DeactivateEventPing( "ping_mechanicstation_battery" )

	self:cl_e_onUntracked()
end

function MechanicStationQuest.client_onRefresh( self )
end

function MechanicStationQuest.client_onClientDataUpdate( self, data )
	local prevStage = self.cl.stage
	if data.stage ~= self.cl.stage then
		self:cl_hideMarkers()
		self.cl.stage = data.stage
		self:cl_updateMarkers()
	end

	self:cl_updateProgress( prevStage )
end

function MechanicStationQuest.cl_updateProgress( self, prevStage )
	local trackingData = self.data.trackingSteps

	trackingData.find.complete = self.cl.stage > Stages.to_station
	trackingData.investigate.complete = self.cl.stage > Stages.explore_station
	trackingData.battery.complete = self.cl.stage > Stages.find_battery
	trackingData.power.complete = self.cl.stage > Stages.activate_station
	trackingData.craftbot.complete = self.cl.stage > Stages.build_craftbot

	ApplyTrackingProgress( self, trackingData, self.cl.stage, prevStage )

	QuestManager.Cl_UpdateQuestTracker()
end

function MechanicStationQuest.cl_updateMarkers( self )
	if not self.cl.tracked then
		return
	end
	if self.cl.stage == Stages.find_battery then
		QuestEntityManager.Cl_SetNamedQuestMarkerVisible( "quest_mechanicstation.marker_battery", true )
		QuestEntityManager.Cl_ActivateEventPing( "ping_mechanicstation_battery" )
	elseif self.cl.stage == Stages.activate_station or self.cl.stage == Stages.explore_station then
		QuestEntityManager.Cl_SetNamedQuestMarkerVisible( "quest_mechanicstation.marker_socket", true )
	end
	if self.cl.stage <= Stages.activate_station then
		QuestEntityManager.Cl_ActivateEventPing( "ping_mechanicstation_socket" )
	end
end

function MechanicStationQuest.cl_hideMarkers( self )
	QuestEntityManager.Cl_DeactivateEventPing( "ping_mechanicstation_socket" )
	QuestEntityManager.Cl_DeactivateEventPing( "ping_mechanicstation_battery" )
	QuestEntityManager.Cl_SetNamedQuestMarkerVisible( "quest_mechanicstation.marker_battery", false )
	QuestEntityManager.Cl_SetNamedQuestMarkerVisible( "quest_mechanicstation.marker_socket", false )
end

function MechanicStationQuest.cl_e_onTracked( self )
	self.cl.tracked = true
	self:cl_updateMarkers()
end

function MechanicStationQuest.cl_e_onUntracked( self )
	self:cl_hideMarkers()
	self.cl.tracked = false
end