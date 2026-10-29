dofile( "$SURVIVAL_DATA/Scripts/game/managers/QuestManager.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/quest_util.lua" )

TutorialQuest = class()
TutorialQuest.isSaveObject = true

local Stages = {
	go_crashsite = 1,
	find_bucket = 2,
	fill_bucket = 3,
	return_to_ship = 4,
	putout_fire = 5,
	find_ruin = 6,
	find_battery = 7,
	activate_ship = 8,
	build_connect_tool = 9,
	use_connect_tool = 10,
	use_note_terminal = 11,
	open_logbook = 12,
	read_log = 13,
	track_waypoint = 14,
	close_logbook = 15
}

local FireNames = { "quest_tutorial.fire01", "quest_tutorial.fire02", "quest_tutorial.fire03" }
local Version = 2

function TutorialQuest.server_onCreate( self )
	print("TutorialQuest.server_onCreate")
	self.sv = {}
	self.sv.saved = self.storage:load()
	if self.sv.saved == nil then
		self.sv.saved = {}
		self.sv.saved.version = Version
		self.sv.saved.stage = Stages.go_crashsite
		self.sv.saved.stageData = {}
		self.sv.saved.stageData.dousedFires = {}
		self.sv.saved.completedStages = {}
	end

	self.sv.tutorialPopupDelay = 0

	QuestManager.Sv_SubscribeEvent( QuestEvent.InventoryChanges, self.scriptableObject, "sv_e_onQuestEvent" )
	QuestManager.Sv_SubscribeEvent( QuestEvent.FireDoused, self.scriptableObject, "sv_e_onQuestEvent" )
	QuestManager.Sv_SubscribeEvent( "event.quest_tutorial.power_restored", self.scriptableObject, "sv_e_onQuestEvent" )
	QuestManager.Sv_SubscribeEvent( QuestEvent.AreaTriggerPlayerEnter, self.scriptableObject, "sv_e_onQuestEvent" )
	QuestManager.Sv_SubscribeEvent( QuestEvent.AreaTriggerPlayerExit, self.scriptableObject, "sv_e_onQuestEvent" )
	QuestManager.Sv_SubscribeEvent( QuestEvent.LogBookOpen, self.scriptableObject, "sv_e_onQuestEvent" )
	QuestManager.Sv_SubscribeEvent( QuestEvent.LogBookClose, self.scriptableObject, "sv_e_onQuestEvent" )
	QuestManager.Sv_SubscribeEvent( QuestEvent.LogBookReadLog, self.scriptableObject, "sv_e_onQuestEvent" )
	QuestManager.Sv_SubscribeEvent( QuestEvent.LogBookWaypointTracked, self.scriptableObject, "sv_e_onQuestEvent" )
	QuestManager.Sv_SubscribeEvent( "event.quest_tutorial.connect", self.scriptableObject, "sv_e_onQuestEvent" )
	QuestManager.Sv_SubscribeEvent( "event.quest_tutorial.note_terminal_used", self.scriptableObject, "sv_e_onQuestEvent" )
	





	QuestPinManager.Sv_AddWatchedUuid( ITEMS.obj_survivalobject_powercore, "PickUpPin", sm.vec3.new( 0, 0, 0.5 ) )

	sm.event.sendToScriptableObject( self.scriptableObject, "sv_e_onQuestEvent", {} )
	self:sv_saveAndSync()
end

function TutorialQuest.server_onFixedUpdate( self, dt )
	-- Delay tutorial popup to make sure it doesn't cover mission progress in HUD
	if self.sv.tutorialPopupDelay > 0 then
		self.sv.tutorialPopupDelay = self.sv.tutorialPopupDelay - 1
		if self.sv.tutorialPopupDelay == 0 then
			TutorialManager.Sv_TutorialEvent( TutorialEvent.ShipCraftbot )
		end
	end
end















function TutorialQuest.sv_e_onFinishQuest( self )
	QuestPinManager.Sv_RemoveWatchedUuid( ITEMS.obj_survivalobject_powercore )
	QuestManager.Sv_UnsubscribeAllEvents( self.scriptableObject )
	CompleteQuest( "quest_tutorial", "quest_mechanicstation" )
end

function TutorialQuest.sv_saveAndSync( self )
	self.storage:save( self.sv.saved )
	self.network:setClientData( { stage = self.sv.saved.stage, stageData = self.sv.saved.stageData } )
end

function TutorialQuest.sv_getDousedFires( self )
	local dousedFires = {}
	for _, name in ipairs( FireNames ) do
		if g_dousedNamedFires[name] then
			dousedFires[#dousedFires + 1] = name
		end
	end
	return dousedFires
end

function TutorialQuest.sv_e_onQuestEvent( self, data )
	--[[ Event ]]
	if data.event == QuestEvent.InventoryChanges then
		-- Find bucket
		if FindInventoryChange( data.params.changes, ITEMS.obj_tool_bucket_empty ) > 0 then
			self.sv.saved.completedStages[Stages.find_bucket] = true
		end
		-- Fill bucket
		if FindInventoryChange( data.params.changes, ITEMS.obj_tool_bucket_water ) > 0 then
			self.sv.saved.completedStages[Stages.find_bucket] = true
			self.sv.saved.completedStages[Stages.fill_bucket] = true
		end
		-- Find master battery
		if FindInventoryChange( data.params.changes, ITEMS.obj_survivalobject_powercore ) > 0 then
			self.sv.saved.completedStages[Stages.find_battery] = true
		end
	elseif data.event == QuestEvent.AreaTriggerPlayerEnter or data.event == QuestEvent.AreaTriggerPlayerExit then
		-- Go to ship or ruin
 		self.sv.saved.completedStages[Stages.return_to_ship] = QuestEntityManager.Sv_NamedAreaTriggerContainsPlayer( "quest_tutorial.area_ship" )
		self.sv.saved.completedStages[Stages.find_ruin] = QuestEntityManager.Sv_NamedAreaTriggerContainsPlayer( "quest_tutorial.area_ruin" )
	elseif data.event == QuestEvent.FireDoused then
		-- Put out fire
		self.sv.saved.stageData.dousedFires = self:sv_getDousedFires()
		self.sv.saved.completedStages[Stages.putout_fire] = #self.sv.saved.stageData.dousedFires == #FireNames
	elseif data.event == "event.quest_tutorial.power_restored" then
		-- Activate ship
		self.sv.saved.completedStages[Stages.activate_ship] = true
		self.sv.tutorialPopupDelay = 40 * 3 -- Delay tutorial popup to make sure it doesn't cover mission progress in HUD

		if self.sv.saved.version == nil or self.sv.saved.version < Version then
			LogEntryManager.Sv_AddLog( LOGS.log_mechanicstation )
			self:sv_e_onFinishQuest()
			return
		end
	elseif data.event == "event.quest_tutorial.connect" then
		for _,index in pairs( Stages ) do
			if index < Stages.use_connect_tool and index ~= Stages.activate_ship then
				self.sv.saved.completedStages[index] = true
			end
		end
		self.sv.saved.completedStages[Stages.use_connect_tool] = true
	elseif data.event == "event.quest_tutorial.note_terminal_used" then
		LogEntryManager.Sv_AddLog( LOGS.log_mechanicstation )
		self.sv.saved.completedStages[Stages.use_note_terminal] = true
	end

	if self.sv.saved.stage == Stages.build_connect_tool then
		if data.event == QuestEvent.InventoryChanges then
			if FindInventoryChange( data.params.changes, ITEMS.tool_connect ) > 0 then
				self.sv.saved.completedStages[Stages.build_connect_tool] = true
			end
		end
	elseif self.sv.saved.stage == Stages.open_logbook then
		if data.event == QuestEvent.LogBookOpen then
			LogEntryManager.Sv_SetLogHighlight( LOGS.log_mechanicstation, true )
			self.sv.saved.completedStages[Stages.open_logbook] = true
		end
	elseif self.sv.saved.stage == Stages.read_log then
		if data.event == QuestEvent.LogBookReadLog and data.params and data.params.log == LOGS.log_mechanicstation then
			self.sv.saved.completedStages[Stages.read_log] = true
		end
	elseif self.sv.saved.stage == Stages.track_waypoint then
		if data.event == QuestEvent.LogBookWaypointTracked and data.params and data.params.log == LOGS.log_mechanicstation then
			LogEntryManager.Sv_SetLogHighlight( LOGS.log_mechanicstation, false )
			self.sv.saved.completedStages[Stages.track_waypoint] = true
		end
	elseif self.sv.saved.stage == Stages.close_logbook then
		if data.event == QuestEvent.LogBookClose then
			self.sv.saved.completedStages[Stages.close_logbook] = true
		end
	end

	-- Detect player at the crashsite for the first time
	if not self.sv.saved.completedStages[Stages.go_crashsite] then
		self.sv.saved.completedStages[Stages.go_crashsite] = QuestEntityManager.Sv_NamedAreaTriggerContainsPlayer( "quest_tutorial.area_ship" )
	end

	-- Detect already doused fires
	if not self.sv.saved.completedStages[Stages.putout_fire] then
		self.sv.saved.stageData.dousedFires = self:sv_getDousedFires()
		self.sv.saved.completedStages[Stages.putout_fire] = #self.sv.saved.stageData.dousedFires == #FireNames
	end

	-- Detect already active ship
	if not self.sv.saved.completedStages[Stages.activate_ship] then
		local powercoreSockets = QuestEntityManager.Sv_GetInteractablesWithUuid( ITEMS.obj_survivalobject_powercoresocket )
		for _, powercoreSocket in pairs( powercoreSockets ) do
			if sm.exists( powercoreSocket ) and powercoreSocket.active and powercoreSocket.publicData and powercoreSocket.publicData.area == "ship" then
				self.sv.saved.completedStages[Stages.activate_ship] = true
			end
		end
	end

	--[[ Quest progress ]]
	-- Determine quest stage
	if not self.sv.saved.completedStages[Stages.go_crashsite] then
		self.sv.saved.stage = Stages.go_crashsite
	elseif not self.sv.saved.completedStages[Stages.activate_ship] then
		if not self.sv.saved.completedStages[Stages.putout_fire] then
			if not self.sv.saved.completedStages[Stages.find_bucket] then
				self.sv.saved.stage = Stages.find_bucket
			elseif not self.sv.saved.completedStages[Stages.fill_bucket] then
				self.sv.saved.stage = Stages.fill_bucket
			elseif not self.sv.saved.completedStages[Stages.return_to_ship] then
				self.sv.saved.stage = Stages.return_to_ship
			else
				self.sv.saved.stage = Stages.putout_fire
			end
		elseif not self.sv.saved.completedStages[Stages.find_battery] then
			if not self.sv.saved.completedStages[Stages.find_ruin] then
				self.sv.saved.stage = Stages.find_ruin
			else
				self.sv.saved.stage = Stages.find_battery
			end
		else
			self.sv.saved.stage = Stages.activate_ship
		end
	elseif not self.sv.saved.completedStages[Stages.close_logbook] then
		if not self.sv.saved.completedStages[Stages.build_connect_tool] then
			self.sv.saved.stage = Stages.build_connect_tool
			local players = sm.player.getAllPlayers()
			local toolFound = false
			for _, player in pairs( players ) do
				if sm.exists( player ) then
					local inventory = player:getInventory()
					if inventory then
						local inventoryList = sm.container.itemUuid( inventory )
						for _, uuid in pairs( inventoryList ) do
							if uuid == ITEMS.tool_connect then
								toolFound = true
								break
							end
						end
					end
				end
				if toolFound then
					break
				end
			end
			if toolFound then
				self.sv.saved.completedStages[Stages.build_connect_tool] = true
			end
		elseif not self.sv.saved.completedStages[Stages.use_connect_tool] then
			self.sv.saved.stage = Stages.use_connect_tool
		elseif not self.sv.saved.completedStages[Stages.use_note_terminal] then
			self.sv.saved.stage = Stages.use_note_terminal
		elseif not self.sv.saved.completedStages[Stages.open_logbook] then
			self.sv.saved.stage = Stages.open_logbook
		elseif not self.sv.saved.completedStages[Stages.read_log] then
			self.sv.saved.stage = Stages.read_log
		elseif not self.sv.saved.completedStages[Stages.track_waypoint] then
			self.sv.saved.stage = Stages.track_waypoint
		else
			self.sv.saved.stage = Stages.close_logbook
		end
	end

	-- Complete quest
	if self.sv.saved.completedStages[Stages.close_logbook] then
		if self.sv.saved.stage ~= nil then
			self.sv.saved.stage = nil
			self:sv_e_onFinishQuest()
			return
		end
	end
	self.scriptableObject.publicData = { canActivate = self.sv.saved.stage >= Stages.activate_ship }
	self:sv_saveAndSync()
end


function TutorialQuest.client_onCreate( self )
	QuestManager.Cl_OnQuestCreated( "quest_tutorial" )
	sm.item.addTrackedItem( ITEMS.obj_survivalobject_powercore, sm.item.trackingType.mainQuest )
	self.cl = {}
	self.scriptableObject.clientPublicData = {}
	self.scriptableObject.clientPublicData.progressString = ""
end

function TutorialQuest.client_onDestroy( self )
	sm.item.removeTrackedItem( ITEMS.obj_survivalobject_powercore, sm.item.trackingType.mainQuest )
	QuestEntityManager.Cl_DeactivateEventPing("ping_battery")
	
	self:cl_e_onUntracked()
end

function TutorialQuest.client_onRefresh( self )
end

function TutorialQuest.client_onClientDataUpdate( self, data )
	local prevStage = self.cl.stage
	if data.stage ~= self.cl.stage then
		self:cl_hideMarkers()
		self.cl.stage = data.stage
	end
	self.cl.stageData = data.stageData
	self:cl_updateMarkers()
	self:cl_updateProgress( prevStage )
end

function TutorialQuest.cl_updateProgress( self, prevStage )
	if self.cl.stage == nil then
		return
	end

	local trackingData = self.data.trackingSteps

	trackingData.bucket.complete = self.cl.stage > Stages.fill_bucket
	trackingData.extinguish.complete = #self.cl.stageData.dousedFires >= #FireNames

	trackingData.battery.complete = self.cl.stage > Stages.find_battery
	trackingData.restorePower.complete = self.cl.stage > Stages.activate_ship

	trackingData.craft.complete = self.cl.stage > Stages.build_connect_tool
	trackingData.reconnect.complete = self.cl.stage > Stages.use_connect_tool

	trackingData.use.complete = self.cl.stage > Stages.use_note_terminal

	trackingData.open.complete = self.cl.stage > Stages.open_logbook
	trackingData.open.text = string.format( sm.gui.translateLocalizationTags( trackingData.open.text ), sm.gui.getKeyBinding( "Logbook", false ) )

	trackingData.track.complete = self.cl.stage > Stages.track_waypoint

	ApplyTrackingProgress( self, trackingData, self.cl.stage, prevStage )

	if self.cl.stage >= Stages.activate_ship then
		self.scriptableObject.clientPublicData.canActivate = true
	end
	if self.cl.stage == Stages.use_connect_tool then
		self.scriptableObject.clientPublicData.showConnectTutorial = true
	end
	if self.cl.stage > Stages.use_connect_tool then
		self.scriptableObject.clientPublicData.openNoteTerminal = true
	end
	if self.cl.stage == Stages.use_note_terminal then
		self.scriptableObject.clientPublicData.canUseNoteTerminal = true
	end
	QuestManager.Cl_UpdateQuestTracker()
end

function TutorialQuest.cl_updateMarkers( self )
	if not self.cl.tracked then
		return
	end

	if self.cl.stage == Stages.find_bucket then
		QuestEntityManager.Cl_SetNamedQuestMarkerVisible( "quest_tutorial.marker_bucket", true )
		QuestEntityManager.Cl_ActivateEventPing( "ping_bucket" )
	elseif self.cl.stage == Stages.fill_bucket then
		QuestEntityManager.Cl_SetNamedQuestMarkerVisible( "quest_tutorial.marker_water", true )
	elseif self.cl.stage == Stages.return_to_ship then
		QuestEntityManager.Cl_SetNamedQuestMarkerVisible( "quest_tutorial.marker_spaceship", true )
	elseif self.cl.stage == Stages.putout_fire then
		if isAnyOf( "quest_tutorial.fire01", self.cl.stageData.dousedFires ) then
			QuestEntityManager.Cl_SetNamedQuestMarkerVisible( "quest_tutorial.marker_fire01", false )
		else
			QuestEntityManager.Cl_SetNamedQuestMarkerVisible( "quest_tutorial.marker_fire01", true )
		end
		if isAnyOf( "quest_tutorial.fire02", self.cl.stageData.dousedFires ) then
			QuestEntityManager.Cl_SetNamedQuestMarkerVisible( "quest_tutorial.marker_fire02", false )
		else
			QuestEntityManager.Cl_SetNamedQuestMarkerVisible( "quest_tutorial.marker_fire02", true )
		end
		if isAnyOf( "quest_tutorial.fire03", self.cl.stageData.dousedFires ) then
			QuestEntityManager.Cl_SetNamedQuestMarkerVisible( "quest_tutorial.marker_fire03", false )
		else
			QuestEntityManager.Cl_SetNamedQuestMarkerVisible( "quest_tutorial.marker_fire03", true )
		end
	elseif self.cl.stage == Stages.find_ruin then
		QuestEntityManager.Cl_ActivateEventPing( "ping_battery" )
		QuestEntityManager.Cl_ActivateEventPing( "ping_masterbattery1" )
		QuestEntityManager.Cl_SetNamedQuestMarkerVisible( "quest_tutorial.marker_ruin", true )
	elseif self.cl.stage == Stages.find_battery then
		QuestEntityManager.Cl_ActivateEventPing( "ping_battery" )
		QuestEntityManager.Cl_ActivateEventPing( "ping_masterbattery1" )
		QuestEntityManager.Cl_SetNamedQuestMarkerVisible( "quest_tutorial.marker_battery", true )
	elseif self.cl.stage == Stages.activate_ship then
		QuestEntityManager.Cl_ActivateEventPing( "ping_battery" )
		QuestEntityManager.Cl_SetNamedQuestMarkerVisible( "quest_tutorial.marker_socket", true )
	elseif self.cl.stage == Stages.build_connect_tool then
		QuestEntityManager.Cl_ActivateEventPing( "ping_crafter" )
		QuestEntityManager.Cl_SetNamedQuestMarkerVisible( "quest_connector.marker_workbench", true )
	elseif self.cl.stage == Stages.use_connect_tool then
		QuestEntityManager.Cl_SetNamedQuestMarkerVisible( "quest_connector.marker_connect", true )
	elseif self.cl.stage == Stages.use_note_terminal then
		QuestEntityManager.Cl_SetNamedQuestMarkerVisible( "quest_connector.marker_connect", true )
		QuestEntityManager.Cl_ActivateEventPing( "ping_intel" )
	end
end

function TutorialQuest.cl_hideMarkers( self )
	QuestEntityManager.Cl_SetNamedQuestMarkerVisible( "quest_tutorial.marker_water", false )
	QuestEntityManager.Cl_SetNamedQuestMarkerVisible( "quest_tutorial.marker_bucket", false )
	QuestEntityManager.Cl_SetNamedQuestMarkerVisible( "quest_tutorial.marker_spaceship", false )
	QuestEntityManager.Cl_SetNamedQuestMarkerVisible( "quest_tutorial.marker_fire01", false )
	QuestEntityManager.Cl_SetNamedQuestMarkerVisible( "quest_tutorial.marker_fire02", false )
	QuestEntityManager.Cl_SetNamedQuestMarkerVisible( "quest_tutorial.marker_fire03", false )
	QuestEntityManager.Cl_SetNamedQuestMarkerVisible( "quest_tutorial.marker_fire04", false )
	QuestEntityManager.Cl_SetNamedQuestMarkerVisible( "quest_tutorial.marker_ruin", false )
	QuestEntityManager.Cl_SetNamedQuestMarkerVisible( "quest_tutorial.marker_battery", false )
	QuestEntityManager.Cl_SetNamedQuestMarkerVisible( "quest_tutorial.marker_socket", false )
	QuestEntityManager.Cl_SetNamedQuestMarkerVisible( "quest_connector.marker_workbench", false )
	QuestEntityManager.Cl_SetNamedQuestMarkerVisible( "quest_connector.marker_connect", false )
	QuestEntityManager.Cl_DeactivateEventPing( "ping_battery" )
	QuestEntityManager.Cl_DeactivateEventPing( "ping_bucket" )
	QuestEntityManager.Cl_DeactivateEventPing( "ping_crafter" )
	QuestEntityManager.Cl_DeactivateEventPing( "ping_intel" )
	QuestEntityManager.Cl_DeactivateEventPing( "ping_masterbattery1" )
end


function TutorialQuest.cl_e_onTracked( self )
	self.cl.tracked = true
	self:cl_updateMarkers()
end

function TutorialQuest.cl_e_onUntracked( self )
	self.cl.tracked = false
	self:cl_hideMarkers()
end