dofile( "$SURVIVAL_DATA/Scripts/game/quest_util.lua" )

QuestManager = class( nil )
QuestManager.isSaveObject = true


QuestEvent = {
	QuestCompleted = "event.generic.quest_completed", -- data.params: { questName = ? }
	QuestAbandoned = "event.generic.quest_abandoned", -- data.params: { questName = ? }
	InventoryChanges = "event.generic.inventory_changes", -- data.params: { container = ?, changes = { { uuid = ?, difference = ? [, instance = ?] } }, ... }
	InteractableCreated = "event.generic.interactable_created", -- data.params: { interactable = ? }
	InteractableDestroyed = "event.generic.interactable_destroyed", -- data.params: { interactable = ? }
	WaypointLoaded = "event.generic.waypoint_loaded", -- { data.params: waypoint = ?, world = ? }
	WaypointTrackLoaded = "event.generic.waypointTrack_loaded", -- data.params: { waypointTrack = ?, world = ? }
	ActorTrackLoaded = "event.generic.actorTrack_loaded", -- data.params: { name = ? }
	AreaTriggerEnter = "event.generic.areaTrigger_enter", -- { data.params: name = ?, results = { ? } }
	AreaTriggerExit = "event.generic.areaTrigger_exit", -- { data.params: name = ?, results = { ? } }
	AreaTriggerPlayerEnter = "event.generic.areaTrigger_playerEnter", -- Sent only when a player is among the entering results. { data.params: name = ?, results = { ? } }
	AreaTriggerPlayerExit = "event.generic.areaTrigger_playerExit", -- Sent only when a player is among the exiting results. { data.params: name = ?, results = { ? } }
	PlayerJoined = "event.generic.player_joined", -- data.params: { questName = ? }
	PlayerLeft = "event.generic.player_left", -- data.params: { questName = ? }
	FireDoused = "event.generic.fire_doused", -- data.params: { fireName = ? }
	FarmerTalk = "event.generic.farmer_talk", -- data.params: {}
	LorenzoTalk = "event.generic.lorenzo_talk", -- data.params: {}
	LogBookOpen = "event.generic.open_logbook", -- data.params: {}
	LogBookClose = "event.generic.close_logbook", -- data.params: {}
	LogBookReadLog = "event.generic.read_log", -- data.params: { log = ? }
	LogBookWaypointTracked = "event.generic.track_waypoint", -- data.params: { log = ? }
	QuestConsoleDestroyed = "event.generic.quest_console_destroyed", -- data.params: { warehouseIndex = ? }
	WarehouseDestructionStarted = "event.generic.warehouse_destruction_started", -- data.params: { warehouseIndex = ? }
	WarehouseDestruction = "event.generic.warehouse_destruction", -- data.params: { warehouseIndex = ? }
	TraderProgressTrade = "event.generic.trade_crate", -- data.params: {}
	TraderCompleteTrade = "event.generic.trade_complete_trade", -- data.params: {}
	GrowlabUnlocked = "event.generic.unlock_growlab", -- data.params: { log = ? }
	GrowlabElevatorCalled = "event.generic.activate_growlab_elevator_called", -- data.params: { poiType = ? }
	GrowlabElevatorActivated = "event.generic.activate_growlab_elevator_activated", -- data.params: { poiType = ? }
	GrowlabRewardClaimed = "event.generic.activate_growlab_reward_claimed", -- data.params: { poiType = ? }
	GrowlabCompleted = "event.generic.activate_growlab_complete", -- data.params: { poiType = ? }
	QuestUnitCreated = "event.generic.quest_unit_created", -- data.params: { character = ?, questUnitEnum = ? }
	QuestUnitInteract = "event.generic.quest_unit_interact", -- data.params: { questUnitEnum = ? }
	LogCardReaderUnlock = "event.generic.log_card_reader_unlock", -- data.params: { keyTag = ? }
	LogUnlocked = "event.generic.log_unlocked", -- data.params: { uuid = ? }
	RecipeUnlocked = "event.generic.recipe_unlocked", -- data.params: { uuidString = ? }
	QuestConsoleHit = "event.generic.quest_console_hit", -- data.params: { hits = ? }
	DispenserSpawnShape = "event.generic.dispenser_spawn_shape", -- data.params: { shapeUuid = ? }
	DispenserCraftStarted = "event.generic.dispenser_craft_start", -- data.params: {}
	PackingStationCreateCrate = "event.generic.packingstation_create_crate", -- data.params: { shapeUuid = ? }
	PackingStationDeposit = "event.generic.packingstation_deposit", -- data.params: { depositUuid = ? }
	DeliverTraderCrate = "event.generic.deliver_trader_crate", -- data.params: { shapeUuid = ? }
	TraderLeaveArea = "event.generic.trader_leave_area", -- data.params: {},
	RecordingDone = "event.generic.recording_done", -- data.params: { dialogUuid = ?, entry = ? }
	RecordingStarted = "event.generic.recording_started", -- data.params: { dialogUuid = ?, entry = ? }
	BridgeRaised = "event.generic.bridge_raised", -- data.params: {}
	VaultTotalUpdated = "event.generic.vault_total_updated", -- data.params: { total = ? }
	VaultQuotaReached = "event.generic.vault_quota_reached", -- data.params: {}
	DialogCompleted = "event.generic.dialog_completed", -- data.params: { uuid = ?, entryName = ? }

	-- Per-trigger named event suffixes. Concatenate with the area trigger's name to subscribe to a specific trigger,
	-- e.g. QuestManager.Sv_SubscribeEvent( "my_trigger" .. QuestEvent.AreaTriggerPlayerEnterSuffix, ... ).
	AreaTriggerEnterSuffix = "_triggerEnter",
	AreaTriggerExitSuffix = "_triggerExit",
	AreaTriggerPlayerEnterSuffix = "_playerTriggerEnter",
	AreaTriggerPlayerExitSuffix = "_playerTriggerExit",
}

QuestUnits = {
	Hubert = 1,
	Lorenzo = 2,
	Phe = 3,
	Hubert_Clone = 4,
	Lorenzo_Clone = 5,
	Phe_Clone = 6
}

function QuestManager.server_onCreate( self )
	assert( g_questManagerServer == nil )

	g_questManagerServer = self

	self.sv = {}
	self.sv.saved = self.storage:load()
	self.sv.saved = self.sv.saved or {}
    
	self.sv.saved.activeQuests = self.sv.saved.activeQuests or {}
	self.sv.saved.completedQuests = self.sv.saved.completedQuests or {}
	self.sv.saved.trackedQuests = self.sv.saved.trackedQuests or {}
	self.sv.saved.npcInteractionData = self.sv.saved.npcInteractionData or {}
	if not IsEmptyTable( self.sv.saved.completedQuests ) and not IsArray( self.sv.saved.completedQuests ) then -- Converts old kvp format to array format
		local array = {}
		for questName, _ in pairs( self.sv.saved.completedQuests) do
			array[#array+1] = questName
		end
		self.sv.saved.completedQuests = array
	end

	self.storage:save( self.sv.saved )
	self.network:setClientData( self.sv.saved )

	self.sv.eventSubs = {}
	self.sv.quests = {}
	self.sv.questUnits = {}
	self.sv.questData = {}
	self.sv.questActivators = {} -- questName -> set of activator scriptableObjects that intend to start it

	local path = "$SURVIVAL_DATA/ScriptableObjects/scriptableObjectSets/sob_quests.sobset"

	g_questNames = {}
	if sm.json.fileExists( path ) then
		local questSet = sm.json.open( path )
		if questSet and questSet.scriptableObjectList then
			for _, questEntry in pairs( questSet.scriptableObjectList ) do
				if questEntry.name and questEntry.uuid then
					self.sv.quests[questEntry.name] = sm.uuid.new( questEntry.uuid )
					self.sv.questData[questEntry.name] = questEntry.data



				end
			end
		end
	else
		sm.log.error("Failed to load quest set " .. path .. " file did not exist.")
	end



















	self:sv_e_setNpcInteractionData()

	--delay patch one tick, wait for activator objects to register
	sm.event.sendToScriptableObject( self.scriptableObject, "sv_e_patchMissingQuestActivators" )
end

function QuestManager.server_onDestroy( self )
	g_questManagerServer = nil
	if self.sv.saved.activeQuests then
		for _, quest in pairs( self.sv.saved.activeQuests ) do
			quest:destroy()
			quest = nil
		end
	end
end

-- Quest activator registry 
function QuestManager.Sv_RegisterQuestActivator( questName, activator )
	if g_questManagerServer and questName then
		g_questManagerServer:sv_registerQuestActivator( questName, activator )
	end
end

function QuestManager.sv_registerQuestActivator( self, questName, activator )
	local activators = self.sv.questActivators[questName]
	if activators == nil then
		activators = {}
		self.sv.questActivators[questName] = activators
	end
	activators[activator] = true
end

function QuestManager.Sv_UnregisterQuestActivator( questName, activator )
	if g_questManagerServer and questName then
		g_questManagerServer:sv_unregisterQuestActivator( questName, activator )
	end
end

function QuestManager.sv_unregisterQuestActivator( self, questName, activator )
	local activators = self.sv.questActivators[questName]
	if activators then
		activators[activator] = nil
		if next( activators ) == nil then
			self.sv.questActivators[questName] = nil
		end
	end
end

-- True if a still-existing activator object is registered to start the given quest.
function QuestManager.Sv_HasQuestActivator( questName )
	if g_questManagerServer then
		local activators = g_questManagerServer.sv.questActivators[questName]
		if activators then
			for activator in pairs( activators ) do
				if sm.exists( activator ) then
					return true
				end
			end
		end
	end
	return false
end

-- PATCH (recovery) ------------------------------------------------------------
-- An issue caused quest activator object to never be created. Perform a check on startup and recreate it if necessary.
function QuestManager.sv_e_patchMissingQuestActivators( self )
	if self:sv_isQuestComplete( "quest_vault_3" ) then
		if self:sv_isQuestComplete( "quest_scrapyard" ) then
			if not self:sv_isQuestComplete( "quest_station_2" ) then
				if not self:sv_isQuestActive( "quest_station_2" ) then
					if not QuestManager.Sv_HasQuestActivator( "quest_station_2" ) then
						sm.log.info( "QuestManager patch: quest_station_2 activator missing; recreating it to unblock progression." )
						ActivateQuestThroughDialogBeat( "quest_station_2", "finish_quota_3_start_station_2", 0 )
					end
				end
			end
		end
	end

	if self:sv_isQuestComplete( "quest_warehouse_destruction" ) then
		if not self:sv_isQuestComplete( "quest_save_watchtower" ) then
			if not self:sv_isQuestActive( "quest_save_watchtower" ) then
				if not QuestManager.Sv_HasQuestActivator( "quest_save_watchtower" ) then
					sm.log.info( "QuestManager patch: quest_save_watchtower activator missing; recreating it to unblock progression." )
					ActivateQuestThroughDialogBeat( "quest_save_watchtower", "hubert_save_watchtower_start", 0 )
				end
			end
		end
	end
end

function QuestManager.client_onCreate( self )
	g_questManagerClient = self
	self.cl = {}
	self.cl.completedQuests = {}
	self.cl.activeQuests = {}
	self.cl.trackedQuests = {}
	self.cl.trackerHud = sm.gui.createQuestTrackerGui()
	self.cl.questTrackerEnabled = sm.game.getSettingBoolean( "QuestTrackerHud" )
	self:cl_questTrackerHudEnable( self.cl.questTrackerEnabled )
	self.cl.questTrackerDirty = true
	self.cl.questCharacters = {}

	self.cl.npcInteractionData = {}

	self.cl.questTrackerRevision = 0

	self.cl.questData = {}
	if sm.isHost then
		for questName, questData in pairs( self.sv.questData ) do
			self.cl.questData[questName] = questData
		end
	else



		local path = "$SURVIVAL_DATA/ScriptableObjects/scriptableObjectSets/sob_quests.sobset"
		if sm.json.fileExists( path ) then
			local questSet = sm.json.open( path )
			if questSet and questSet.scriptableObjectList then
				for _, questEntry in pairs( questSet.scriptableObjectList ) do
					if questEntry.name and questEntry.data then
						self.cl.questData[questEntry.name] = questEntry.data



					end
				end
			end
		end
















	end
end

function QuestManager.client_onDestroy( self )
	g_questManagerClient = nil
	self.cl.trackerHud = nil
end

function QuestManager.Sv_GetQuestTitle( questName )
	return g_questManagerServer:sv_getQuestTitle( questName )
end

function QuestManager.sv_getQuestTitle( self, questName )
	return self.sv.questData[questName].title
end















function QuestManager.Sv_GetQuestRewards( questName )
	return g_questManagerServer:sv_getQuestRewards( questName )
end

function QuestManager.sv_getQuestRewards( self, questName )
	return self.sv.questData[questName].rewards
end

function QuestManager.Sv_GetBuilderguideNodeName( questName )
	return g_questManagerServer:sv_getBuilderguideNodeName( questName )
end

function QuestManager.sv_getBuilderguideNodeName( self, questName )
	return self.sv.questData[questName].nodeName
end

function QuestManager.Sv_ActivateQuest( questName, additionalParams, hide )
	if g_questManagerServer then
		print( "QuestManager - ActivateQuest:", questName )
		sm.event.sendToScriptableObject( g_questManagerServer.scriptableObject, "sv_e_activateQuest", { name = questName, additionalParams = additionalParams, hide = hide } )
	end
end

function QuestManager.Sv_TryActivateQuest( questName, hide )
	if not QuestManager.Sv_IsQuestActive( questName ) and not QuestManager.Sv_IsQuestComplete( questName ) then
		QuestManager.Sv_ActivateQuest( questName, nil, hide )
	end
end

function QuestManager.Sv_AbandonQuest( questName )
	if g_questManagerServer then
		print( "QuestManager - AbandonQuest:", questName )
		sm.event.sendToScriptableObject( g_questManagerServer.scriptableObject, "sv_e_abandonQuest", questName )
	end
end

function QuestManager.Sv_TryAbandonQuest( questName )
	if QuestManager.Sv_IsQuestActive( questName ) then
		QuestManager.Sv_AbandonQuest( questName )
	end
end

function QuestManager.Sv_CompleteQuest( questName, hideCompletion )
	if g_questManagerServer then
		g_questManagerServer:sv_completeQuest( questName, hideCompletion )
	end
end

function QuestManager.Sv_IsQuestActive( questName )
	if g_questManagerServer then
		return g_questManagerServer:sv_isQuestActive( questName )
	end
end

function QuestManager.Sv_IsQuestComplete( questName )
	if g_questManagerServer then
		return g_questManagerServer:sv_isQuestComplete( questName )
	end
end

function QuestManager.Sv_GetQuest( questName )
	if g_questManagerServer then
		return g_questManagerServer:sv_getQuest( questName )
	end
end

function QuestManager.Sv_GetActiveQuests()
	if g_questManagerServer then
		return g_questManagerServer.sv.saved.activeQuests
	end
end

function QuestManager.Sv_SubscribeEvent( event, subscriber, methodName )
	if g_questManagerServer then
		g_questManagerServer:sv_subscribeEvent( event, subscriber, methodName )
	end
end

function QuestManager.Sv_UnsubscribeEvent( event, subscriber )
	if g_questManagerServer then
		g_questManagerServer:sv_unsubscribeEvent( event, subscriber )
	end
end

function QuestManager.Sv_UnsubscribeAllEvents( subscriber )
	if g_questManagerServer then
		g_questManagerServer:sv_unsubscribeAllEvents( subscriber )
	end
end

function QuestManager.Sv_SendEvent( event, params )
	if g_questManagerServer then
		g_questManagerServer:sv_sendEvent( event, params )
	end
end

function QuestManager.Cl_OnQuestCreated( questName )
	if g_questManagerClient then
		return g_questManagerClient:cl_onQuestCreated( questName )
	end
end

function QuestManager.Cl_IsQuestActive( questName )
	if g_questManagerClient then
		return g_questManagerClient:cl_isQuestActive( questName )
	end
end

function QuestManager.Cl_IsQuestComplete( questName )
	if g_questManagerClient then
		return g_questManagerClient:cl_isQuestComplete( questName )
	end
end

function QuestManager.Cl_GetActiveQuest( questName )
	if g_questManagerClient then
		return g_questManagerClient:cl_getActiveQuest( questName )
	end
end

function QuestManager.Cl_TrackQuest( questName )
	if g_questManagerClient then
		return g_questManagerClient:cl_trackQuest( questName )
	end
end

function QuestManager.Cl_UntrackQuest( questName )
	if g_questManagerClient then
		return g_questManagerClient:cl_untrackQuest( questName )
	end
end

function QuestManager.Cl_GetActiveQuests()
	if g_questManagerClient then
		local returnPairs = {}
		for questName,quest in pairs( g_questManagerClient.cl.activeQuests ) do
			if sm.exists( quest ) then
				returnPairs[questName] = quest
			end
		end
		return returnPairs
	end
	return {}
end

function QuestManager.Cl_GetCompletedQuests()
	if g_questManagerClient then
		return g_questManagerClient.cl.completedQuests
	end
	return {}
end

function QuestManager.Cl_GetTrackedQuests()
	if g_questManagerClient then
		return g_questManagerClient.cl.trackedQuests
	end
	return {}
end

function QuestManager.Cl_UpdateQuestTracker()
	if g_questManagerClient then
		g_questManagerClient.cl.questTrackerDirty = true
		g_questManagerClient.cl.questTrackerRevision = g_questManagerClient.cl.questTrackerRevision + 1
	end
end

function QuestManager.Sv_QuestUnhidden( questName )
	if g_questManagerServer then
		sm.event.sendToScriptableObject( g_questManagerServer.scriptableObject, "sv_e_questUnhidden", questName )
	end
end

function QuestManager.sv_getQuestType( self, questName )
	if self.sv.questData[questName].mainQuest then
		return "main"
	elseif self.sv.questData[questName].farmerQuest then
		return "farmer"
	else
		return "side"
	end
end

function QuestManager.sv_e_questUnhidden( self, questName )
	local questType = self:sv_getQuestType( questName )
	NotificationManager.Sv_QuestAccepted( self:sv_getQuestTitle( questName ), questType )
	self.network:sendToClients( "cl_trackQuest", questName )
end

function QuestManager.sv_e_activateQuest( self, data )
	local questUuid = self.sv.quests[data.name]
	if questUuid ~= nil then
		if not data.hide then
			local questType = self:sv_getQuestType( data.name )
			NotificationManager.Sv_QuestAccepted( self:sv_getQuestTitle( data.name ), questType )
		end
		self.sv.saved.activeQuests[data.name] = sm.scriptableObject.createScriptableObject( questUuid, data )
		self.storage:save( self.sv.saved )
		self.network:setClientData( self.sv.saved )
	else
		sm.log.error( data.name .. " did not exist!" )
	end
end

function QuestManager.sv_e_abandonQuest( self, questName )
	local quest = self.sv.saved.activeQuests[questName]
	if quest then
		QuestManager.Sv_UnsubscribeAllEvents( quest )
		self.sv.saved.activeQuests[questName]:destroy()
		self.sv.saved.activeQuests[questName] = nil
		self.storage:save( self.sv.saved )
		self.network:setClientData( self.sv.saved )
		self:sv_sendEvent( QuestEvent.QuestAbandoned, { questName = questName } )
	end
end


































function QuestManager.sv_sendEvent( self, event, params )
	--print( "QuestManager - Event:", event, "params:", params )
	--print( "Subscribers:", self.sv.eventSubs[event] )
	if self.sv.eventSubs[event] ~= nil then
		for _, subCallback in ipairs( self.sv.eventSubs[event] ) do
			local sub = subCallback[1]
			local callbackName = subCallback[2]
			local data = { event = event, params = params }

			if sub == "Game" then
				sm.event.sendToGame( callbackName, data )
				goto continue
			end

			if not sm.exists( sub ) then
				sm.log.warning( "Tried to send callback to subscriber which does not exist: " .. tostring( sub ) )
			else
				SendEvent( sub, callbackName, data )
			end

			::continue::
		end
	end
end

function QuestManager.sv_subscribeEvent( self, event, subscriber, callbackName )
	if self.sv.eventSubs[event] == nil then
		self.sv.eventSubs[event] = { { subscriber, callbackName } }
	else
		for _, subscriberCallback in ipairs( self.sv.eventSubs[event] ) do
			local sub = subscriberCallback[1]
			if sub == subscriber then
				print( "QuestManager - Already subscribed to event:", event, subscriber )
				return
			end
		end
		local numSubs = #self.sv.eventSubs[event]
		self.sv.eventSubs[event][numSubs + 1] = { subscriber, callbackName }
	end
end

-- Combines the subscription and a bump to automatically handle the case where a quest subscribes to an area trigger after a player has already entered it.
function QuestManager.Sv_SubscribePlayerEnterAreaTrigger( triggerName, subscriber, methodName )
	QuestManager.Sv_SubscribeEvent( triggerName .. QuestEvent.AreaTriggerPlayerEnterSuffix, subscriber, methodName )
	QuestEntityManager.Sv_BumpNamedAreaTrigger( triggerName )
end

function QuestManager.sv_unsubscribeEvent( self, event, subscriber )
	if self.sv.eventSubs[event] ~= nil then
		removeFromArray( self.sv.eventSubs[event], function( subscriberCallback )
			local sub = subscriberCallback[1]
			--if sub == subscriber then
			--	print( "QuestManager - Unsubscribed from event:", event, subscriber )
			--end
			return sub == subscriber
		end )
	end
end

function QuestManager.sv_unsubscribeAllEvents( self, subscriber )
	for event, _ in pairs( self.sv.eventSubs ) do
		self:sv_unsubscribeEvent( event, subscriber )
	end
end

function QuestManager.sv_completeQuest( self, questName, hideCompletion )
	local completedQuest = self.sv.saved.activeQuests[questName]
	if completedQuest then
		if not hideCompletion then
			NotificationManager.Sv_QuestCompleted( self:sv_getQuestTitle( questName ), self:sv_getQuestType( questName ) )
		end
		print( "QuestManager - CompleteQuest:", questName )

		self.sv.saved.completedQuests[#self.sv.saved.completedQuests+1] = questName
		self.sv.saved.activeQuests[questName]:destroy()
		self.sv.saved.activeQuests[questName] = nil
		self.storage:save( self.sv.saved )
		if questName then
		-- Quest Achievements
		sm.achievement.seti( questName, 1, nil )
	end
		self:sv_sendEvent( QuestEvent.QuestCompleted, { questName = questName } )
	end

	sm.event.sendToScriptableObject( self.scriptableObject, "sv_e_completeQuestBroadcast", questName )
end

function QuestManager.sv_e_completeQuestBroadcast( self, questName )
	self.network:sendToClients( "cl_n_questCompleted", questName )
	self.network:setClientData( self.sv.saved )
end

function QuestManager.sv_isQuestActive( self, questName )
	return self.sv.saved.activeQuests[questName] ~= nil
end

function QuestManager.sv_isQuestComplete( self, questName )
	for _, quest in ipairs( self.sv.saved.completedQuests ) do
		if questName == quest then
			return true
		end
	end
	return false
end

function QuestManager.sv_getQuest( self, questName )
	return self.sv.saved.activeQuests[questName]
end

function QuestManager.cl_updateQuestTracker( self )
	if not self.cl.trackerHud then
		return
	end

	for questName, quest in pairs( self.cl.trackedQuests ) do
		if sm.exists( quest ) then
			local questData = quest:getData()
			local traderIcon = questData.trackerIcon
			local isMainQuest = questData.mainQuest
			local title = questData.title
			if quest.clientPublicData and quest.clientPublicData.trackerData then
				if quest.clientPublicData.flashTrackerData then
					-- One-shot: flash the completed checkmark, then let the GUI's flash queue defer the steady frame below.
					self.cl.trackerHud:trackQuest( questName, title, isMainQuest, quest.clientPublicData.flashTrackerData, traderIcon )
					quest.clientPublicData.flashTrackerData = nil
				end
				self.cl.trackerHud:trackQuest( questName, title, isMainQuest, quest.clientPublicData.trackerData, traderIcon )
			elseif quest.clientPublicData and quest.clientPublicData.progressString then
				self.cl.trackerHud:trackQuest( questName, title, isMainQuest, {
					{ name = "step1", text = quest.clientPublicData.progressString },
				}, traderIcon )
			end
		end
	end
	self.cl.questTrackerDirty = false
end

function QuestManager.client_onUpdate( self, dt )
	if self.cl.questTrackerDirty then
		self:cl_updateQuestTracker()
	end

	if self.cl.trackedQuestsDirty then
		self.network:sendToServer( "sv_n_updateTrackedQuests", self.cl.trackedQuests )
		self.cl.trackedQuestsDirty = false
	end

	local questTrackerEnabled = sm.game.getSettingBoolean( "QuestTrackerHud" )
	if self.cl.questTrackerEnabled ~= questTrackerEnabled then
		self.cl.questTrackerEnabled = questTrackerEnabled
		self:cl_questTrackerHudEnable( self.cl.questTrackerEnabled )
	end
end

function QuestManager.cl_questTrackerHudEnable( self, enable )
	if enable then
		self.cl.trackerHud:open()
	else
		self.cl.trackerHud:close()
	end
end

function QuestManager.cl_onQuestCreated( self, questName )
	local quest = self.cl.activeQuests[questName]
	if sm.exists( quest ) then
		local main = quest:getData().mainQuest
		local emptySlot = true

		for _, trackedQuest in pairs( self.cl.trackedQuests ) do
			if sm.exists( trackedQuest ) and trackedQuest:getData().mainQuest == main then
				emptySlot = false
			end
		end

		if emptySlot then
			self:cl_trackQuest( questName )
		end
		return true
	else
		-- got a creation call before client data about the quest
		if self.cl.missedQuestCreation == nil then
			self.cl.missedQuestCreation = {}
		end
		self.cl.missedQuestCreation[questName] = true
		return false
	end
end

function QuestManager.client_onFixedUpdate( self )
	if self.cl.missedQuestCreation ~= nil then
		for questName,_ in pairs( self.cl.missedQuestCreation )do
			if self:cl_onQuestCreated( questName ) then
				self.cl.missedQuestCreation[questName] = nil
			end
		end
		if IsEmptyTable( self.cl.missedQuestCreation ) then
			self.cl.missedQuestCreation = nil
		end
	end
end

function QuestManager.client_onRefresh( self )
end

function QuestManager.client_onClientDataUpdate( self, data, channel )
	if channel == 1 then
		self.cl.activeQuests = data.activeQuests
		self.cl.completedQuests = data.completedQuests
		self.cl.questTrackerDirty = true
		self.cl.questTrackerRevision = self.cl.questTrackerRevision + 1
	
		if not self.cl.loadedTrackedQuests then
			local player = sm.localPlayer.getPlayer()
			if( sm.exists( player) ) then
				local tracked = data.trackedQuests and data.trackedQuests[player:getId()] or {}
				for name, _ in pairs( tracked ) do
					self:cl_trackQuest( name )
				end
				self.cl.loadedTrackedQuests = true
			end
		end
	end
	if channel == 2 then
		self.cl.npcInteractionData = {}
		for questUnitEnum, interactionData in pairs( data ) do
			self.cl.npcInteractionData[questUnitEnum] = interactionData
		end
	end
end

function QuestManager.cl_isQuestActive( self, questName )
	return self.cl.activeQuests[questName] ~= nil
end

function QuestManager.cl_isQuestComplete( self, questName )
	for _,quest in ipairs( self.cl.completedQuests ) do
		if quest == questName then
			return true
		end
	end
	return false
end

function QuestManager.cl_getActiveQuest( self, questName )
	return self.cl.activeQuests[questName]
end

function QuestManager.cl_trackQuest( self, questName )
	local quest = self:cl_getActiveQuest( questName )

	if sm.exists( quest ) then
		local isMainQuest = quest:getData().mainQuest

		for name, previous in pairs( self.cl.trackedQuests ) do
			if sm.exists( previous ) and previous:getData().mainQuest == isMainQuest then
				self:cl_untrackQuest( name )
			end
		end

		self.cl.trackedQuests[questName] = quest
		sm.event.sendToScriptableObject( quest, "cl_e_onTracked" )

		local questData = quest:getData()
		local traderIcon = questData.trackerIcon
		if quest.clientPublicData and quest.clientPublicData.progressString then
			local title = quest:getData().title
			self.cl.trackerHud:trackQuest( questName, title, isMainQuest, {
				{ name = "step1", text = quest.clientPublicData.progressString },
			}, traderIcon )
		end

		if quest.clientPublicData and quest.clientPublicData.trackerData then
			local title = quest:getData().title
			quest.clientPublicData.flashTrackerData = nil
			self.cl.trackerHud:trackQuest( questName, title, isMainQuest, quest.clientPublicData.trackerData, traderIcon )
		end
	end

	self.cl.trackedQuestsDirty = true
end









function QuestManager.cl_untrackQuest( self, questName )
	if sm.exists( self.cl.trackedQuests[questName] ) then
		sm.event.sendToScriptableObject( self.cl.trackedQuests[questName], "cl_e_onUntracked" )
	end

	self.cl.trackedQuests[questName] = nil
	self.cl.trackerHud:untrackQuest( questName )
	self.cl.trackedQuestsDirty = true
end


function QuestManager.sv_n_updateTrackedQuests( self, params, player )
	self.sv.saved.trackedQuests[player:getId()] = params
	self.storage:save( self.sv.saved )
	self.network:setClientData( self.sv.saved )
end


function QuestManager.cl_n_questCompleted( self, questName )
	if self.cl.trackerHud then
		self:cl_untrackQuest( questName )
	end
end

function QuestManager.Sv_RegisterQuestUnit( questUnitEnum, unit )



	g_questManagerServer.sv.questUnits[questUnitEnum] = unit
end

function QuestManager.Sv_GetQuestUnit( questUnitEnum )



	if g_questManagerServer.sv.questUnits[questUnitEnum] ~= nil then
		if sm.exists( g_questManagerServer.sv.questUnits[questUnitEnum] ) then
			return g_questManagerServer.sv.questUnits[questUnitEnum]
		end
	end
	return nil
end

function QuestManager.Sv_SetNpcInteractionData( questUnitEnum, data )



	if g_questManagerServer then
		g_questManagerServer:sv_setNpcInteractionData( questUnitEnum, data )
	end
end

function QuestManager.sv_setNpcInteractionData( self, questUnitEnum, data )
	self.sv.saved.npcInteractionData[questUnitEnum] = data
	self.storage:save( self.sv.saved )
	sm.event.sendToScriptableObject( self.scriptableObject, "sv_e_setNpcInteractionData" )
end

function QuestManager.sv_e_setNpcInteractionData( self )
	self.network:setClientData( self.sv.saved.npcInteractionData, 2 )
end

function QuestManager.Sv_GetNpcInteractionData( questUnitEnum )



	if g_questManagerServer then
		return g_questManagerServer:sv_getNpcInteractionData( questUnitEnum )
	end
	return nil
end

function QuestManager.sv_getNpcInteractionData( self, questUnitEnum )
	return self.sv.saved.npcInteractionData[questUnitEnum]
end

function QuestManager.Sv_GetQuestStage( questName )
	if g_questManagerServer then
		local quest = g_questManagerServer.sv.saved.activeQuests[questName]
		if quest then
			local publicData = quest:getPublicData()
			if publicData then
				if publicData.stage then
					return publicData.stage
				else
					sm.log.warning( "Queried quest stage for quest that does not publish stage: " .. questName )
					return nil
				end
			end
		end
	end
	return nil
end

function QuestManager.Sv_QuestEntityTerrainLoaded( world )
	sm.message.send( MESSAGE_TYPES.QUEST.TerrainLoaded, world )
end

function QuestManager.Cl_GetQuestStage( questName )
	if g_questManagerClient then
		local quest = g_questManagerClient.cl.activeQuests[questName]
		if quest and sm.exists( quest ) and quest.clientPublicData then
			if quest.clientPublicData.stage then
				return quest.clientPublicData.stage
			else
				sm.log.warning( "Queried client quest stage for quest that does not publish stage: " .. questName )
				return nil
			end
		end
	end
	return nil
end

function QuestManager.Cl_getQuestTrackerRevision()
	if g_questManagerClient then
		return g_questManagerClient.cl.questTrackerRevision
	end
	return nil
end

function QuestManager.Cl_GetQuestData( questName )
	if g_questManagerClient then
		return g_questManagerClient:cl_getQuestData( questName )
	end
	return nil
end

function QuestManager.cl_getQuestData( self, questName )
	return self.cl.questData[questName]
end

function QuestManager.Cl_NpcCanInteract( questUnitEnum )
	if g_questManagerClient then
		return g_questManagerClient:cl_npcCanInteract( questUnitEnum )
	end
	return false
end

function QuestManager.cl_npcCanInteract( self, questUnitEnum )
	return self.cl.npcInteractionData[questUnitEnum] and self.cl.npcInteractionData[questUnitEnum].canInteract
end

function QuestManager.Cl_GetNpcInteractionData( questUnitEnum )
	if g_questManagerClient then
		return g_questManagerClient:cl_getNpcInteractionData( questUnitEnum )
	end
	return nil
end

function QuestManager.cl_getNpcInteractionData( self, questUnitEnum )
	return self.cl.npcInteractionData[questUnitEnum]
end

function QuestManager.Cl_SetQuestRecording( dialogUuid, entryName )
	if g_questManagerClient then
		g_questManagerClient:cl_setQuestRecording( dialogUuid, entryName )
	end
end

function QuestManager.cl_setQuestRecording( self, dialogUuid, entryName )
	if dialogUuid and entryName then
		self.cl.questRecording = { dialogUuid = dialogUuid, entryName = entryName }
	end
end

function QuestManager.Cl_IsQuestRecording( dialogUuid, entryName )
	if g_questManagerClient then
		return g_questManagerClient:cl_isQuestRecording( dialogUuid, entryName )
	end
	return false
end

function QuestManager.cl_isQuestRecording( self, dialogUuid, entryName )
	if self.cl.questRecording then
		return self.cl.questRecording.dialogUuid == dialogUuid and self.cl.questRecording.entryName == entryName
	end
end