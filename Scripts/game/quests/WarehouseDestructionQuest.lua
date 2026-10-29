dofile( "$SURVIVAL_DATA/Scripts/game/managers/QuestManager.lua" )
dofile( "$GAME_DATA/Scripts/game/managers/KinematicManager.lua" )
dofile( "$SURVIVAL_DATA/Scripts/util.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/survival_items.lua" )

WarehouseDestructionQuest = class()
WarehouseDestructionQuest.isSaveObject = true

local ShowQuestTickDelay = 27 * 40
local TakeKeyReminderTickDelay = 16 * 40
local ConsoleTroubleTickDelay = 8 * 40
local ConsoleTroubleAbortDistance = 2
local ConsoleTroubleAbortTickDelay = 3 * 40

local Stages = {
	follow_inside = 1,
	go_to_first_door = 2,
	take_warehouse_key = 3,
	unlock_first_door = 4,
	explore_top_department = 5,
	approach_chest = 6,
	chest_unopened_reaction = 7,
	open_chest = 8,
	chest_opened_reaction = 9,
	go_to_second_door = 10,
	second_door_trouble = 11,
	second_door_step_aside = 12,
	unlock_second_door = 13,
	enter_second_door = 14,
	go_to_console = 15,
	hit_console_1 = 16,
	hit_console_2 = 17,
	hit_console_3 = 18,
	hit_console_4 = 19,
	destroy_console = 20,
	mainframe_warning01 = 21,
	lorenzo_try_fix01 = 22,
	mainframe_warning02 = 23,
	lorenzo_try_fix02 = 24,
	mainframe_selfdestruct = 25,
	warehouse_countdown_goodbye = 26,
	warehouse_countdown_mainframe = 27,
	warehouse_countdown = 28,
	warehouse_escaped = 29
}

WaypointTracks = {
	"quest_warehouse_destruction.outside_track",
	"quest_warehouse_destruction.inside_track01",
	"quest_warehouse_destruction.inside_track02",
	"quest_warehouse_destruction.inside_track_approach_chest",
	"quest_warehouse_destruction.inside_track03",
	"quest_warehouse_destruction.inside_track04",
	"quest_warehouse_destruction.inside_track05",
	"quest_warehouse_destruction.inside_track_door_standby",
	"quest_warehouse_destruction.inside_track_door_enter",
	"quest_warehouse_destruction.inside_track06",
	"quest_warehouse_destruction.inside_track07",
	"quest_warehouse_destruction.inside_track08",
	"quest_warehouse_destruction.inside_track09"
}

ConsoleTroubleDialogs = {
	"LorenzoDoorTrouble01Dialog",
	"LorenzoDoorTrouble02Dialog",
	"LorenzoDoorTrouble03Dialog",
	"LorenzoDoorTrouble04Dialog",
	"LorenzoDoorTrouble05Dialog",
	"LorenzoDoorTrouble06Dialog",
	"LorenzoDoorTrouble07Dialog",
}

local function GetCurrentTrackName( QuestStage )
	if QuestStage == Stages.follow_inside then
		return WaypointTracks[1]
	elseif QuestStage == Stages.go_to_first_door then
		return WaypointTracks[2]
	elseif QuestStage == Stages.explore_top_department then
		return WaypointTracks[3]
	elseif QuestStage == Stages.approach_chest then
		return WaypointTracks[4]
	elseif QuestStage == Stages.chest_unopened_reaction then
		return WaypointTracks[5]
	elseif QuestStage == Stages.chest_opened_reaction then
		return WaypointTracks[6]
	elseif QuestStage == Stages.go_to_second_door then
		return WaypointTracks[7]
	elseif QuestStage == Stages.second_door_step_aside then
		return WaypointTracks[8]
	elseif QuestStage == Stages.enter_second_door then
		return WaypointTracks[9]
	elseif QuestStage == Stages.go_to_console then
		return WaypointTracks[10]
	elseif QuestStage == Stages.lorenzo_try_fix01 then
		return WaypointTracks[11]
	elseif QuestStage == Stages.lorenzo_try_fix02 then
		return WaypointTracks[12]
	elseif QuestStage >= Stages.warehouse_countdown_goodbye then
		return WaypointTracks[13]
	end
end

function WarehouseDestructionQuest.server_onCreate( self )

	self.sv = {}
	self.sv.questStage = Stages.follow_inside
	self.sv.waypointIndex = 1

	QuestManager.Sv_SubscribeEvent( QuestEvent.WaypointTrackLoaded, self.scriptableObject, "sv_e_onQuestEvent" )
	QuestManager.Sv_SubscribeEvent( QuestEvent.QuestUnitCreated, self.scriptableObject, "sv_e_onQuestEvent" )
	QuestManager.Sv_SubscribeEvent( QuestEvent.QuestUnitInteract, self.scriptableObject, "sv_e_onQuestEvent" )
	QuestManager.Sv_SubscribeEvent( QuestEvent.QuestConsoleDestroyed, self.scriptableObject, "sv_e_onQuestEvent" )
	QuestManager.Sv_SubscribeEvent( QuestEvent.LogCardReaderUnlock, self.scriptableObject, "sv_e_onQuestEvent" )
	QuestManager.Sv_SubscribeEvent( QuestEvent.RecipeUnlocked, self.scriptableObject, "sv_e_onQuestEvent" )
	QuestManager.Sv_SubscribeEvent( QuestEvent.QuestConsoleHit, self.scriptableObject, "sv_e_onQuestEvent" )
	QuestManager.Sv_SubscribeEvent( QuestEvent.DialogCompleted, self.scriptableObject, "sv_e_onDialogCompleted" )




	self.sv.saved = self.storage:load()
	if self.sv.saved == nil then
		self.sv.saved = {}
		self.sv.saved.hidden = true
		self.sv.saved.hiddenTickCounter = 0
	end
	if self.sv.saved.questStage then
		self.sv.questStage = self.sv.saved.questStage
	else
		self.sv.saved.questStage = self.sv.questStage
	end
	if self.sv.saved.waypointIndex then
		self.sv.waypointIndex = self.sv.saved.waypointIndex
	else
		self.sv.saved.waypointIndex = self.sv.waypointIndex
	end

	if self.sv.saved.waypointTracks == nil then
		self.sv.saved.waypointTracks = {}
	end
	for _, trackName in pairs( WaypointTracks ) do
		local waypointTrack = QuestEntityManager.Sv_GetNamedWaypointTrack( trackName )
		if waypointTrack then
			self.sv.saved.waypointTracks[trackName] = EvaluateWaypointTrack( waypointTrack.waypointTrack, waypointTrack.position, waypointTrack.rotation, waypointTrack.scale, waypointTrack.world  )
		end
	end

	-- Detect existing Lorenzo from cinematic
	local unit = QuestManager.Sv_GetQuestUnit( QuestUnits.Lorenzo )
	if unit then
		self.sv.saved.questWaypointUnitId = WaypointQuestUnitManager.Sv_AddWaypointQuestUnit( unit, self.scriptableObject )
	end

	self:sv_updateQuest()
end

































































































function WarehouseDestructionQuest.server_onFixedUpdate( self )
	if self.sv.saved.hidden then
		self.sv.saved.hiddenTickCounter = self.sv.saved.hiddenTickCounter + 1
		if self.sv.saved.hiddenTickCounter >= ShowQuestTickDelay then
			self.sv.saved.hidden = false
			self.sv.saved.hiddenTickCounter = 0
			QuestManager.Sv_QuestUnhidden( "quest_warehouse_destruction" )
			self:sv_updateQuest()
		end
	end

	if self.sv.questStage == Stages.take_warehouse_key then
		self.sv.takeKeyTickCounter = self.sv.takeKeyTickCounter and self.sv.takeKeyTickCounter + 1 or 1
		if self.sv.takeKeyTickCounter >= TakeKeyReminderTickDelay then
			self.sv.takeKeyTickCounter = 0
			DialogManager.Sv_PlayShoutDialog( dialog_scout_farmer, "LorenzoKeyWaitDialog", self.scriptableObject, DialogSpeakerName.Lorenzo )
		end
	else
		self.sv.takeKeyTickCounter = nil
	end

	if self.sv.questStage == Stages.second_door_trouble then
		-- Play random dialog while struggling with console, first fail is instant
		self.sv.consoleTroubleTickCounter = self.sv.consoleTroubleTickCounter and self.sv.consoleTroubleTickCounter + 1 or ConsoleTroubleTickDelay
		if self.sv.consoleTroubleTickCounter >= ConsoleTroubleTickDelay then
			self.sv.consoleTroubleTickCounter = 0
			local randomDialog = ConsoleTroubleDialogs[math.random( 1, #ConsoleTroubleDialogs )]
			DialogManager.Sv_PlayDialog( dialog_scout_farmer, randomDialog, self.scriptableObject, DialogType.Person, DialogSpeakerName.Lorenzo )
		end

		self.sv.secondDoorDelayTickCounter = self.sv.secondDoorDelayTickCounter and math.min( self.sv.secondDoorDelayTickCounter + 1, ConsoleTroubleAbortTickDelay ) or 1
		if self.sv.secondDoorDelayTickCounter >= ConsoleTroubleAbortTickDelay then
			if self.sv.saved.questWaypointUnitId then
				local waypointUnitData = WaypointQuestUnitManager.Sv_GetWaypointQuestUnit( self.sv.saved.questWaypointUnitId )
				if waypointUnitData then
					local waypointCharacter = waypointUnitData.unit:getCharacter()
					local closestPlayer = GetClosestPlayer( waypointCharacter.worldPosition, ConsoleTroubleAbortDistance, waypointCharacter:getWorld() )
					if closestPlayer then
						-- Go to next quest stage
						self.sv.questStage = Stages.second_door_step_aside
						self:sv_updateQuest()
					end
				end
			end
		end
	else
		-- First fail is instant
		self.sv.consoleTroubleTickCounter = nil
	end

	if self.sv.questStage == Stages.unlock_second_door then
		local unit = QuestManager.Sv_GetQuestUnit( QuestUnits.Lorenzo )
		if unit then
			local tileStorageKey = TileStorageManager.Sv_GetTileStorageKeyFromObject( unit.character )
			local doorOpen = TileStorageManager.Sv_GetValueInSubTable( tileStorageKey, KEY_LOCK_TABLE, "FinalDoor" ) == true
			if doorOpen then
				-- Go to next quest stage
				self.sv.questStage = Stages.enter_second_door
				self:sv_updateQuest()
			end
		end
	end

	if self.sv.questStage >= Stages.mainframe_selfdestruct and not self.sv.finishedQuest then
		-- Complete quest after leaving the warehouse when the countdown has started
		local shouldFinishQuest = true
		local warehouse = self.sv.saved.questWarehouseIndex and WarehouseManager.Sv_GetWarehouseFromIndex( self.sv.saved.questWarehouseIndex ) or nil
		local currentTick = sm.game.getCurrentTick()
		local destructionTick = currentTick -- 0 time left if leaving the warehouse because it's destroyed
		if warehouse then
			for _, player in ipairs( sm.player.getAllPlayers() ) do
				local playerCharacter = player.character
				if playerCharacter then
					for _, warehouseWorld in ipairs( warehouse.worlds ) do
						if InSameWorld( playerCharacter, warehouseWorld ) then
							shouldFinishQuest = false
							goto break_nested_for
						end
					end
				else
					shouldFinishQuest = false
					break
				end
			end

			::break_nested_for::

			if warehouse.countdownEvent and warehouse.countdownEvent.publicData then
				destructionTick = warehouse.countdownEvent.publicData.destructionTick
			end
		else
			sm.log.error( "Failed to find the index of the warehouse that should be evacuated. Force finishing quest!" )
		end

		if shouldFinishQuest then
			self.sv.questStage = Stages.warehouse_escaped
			self:sv_updateQuest()
			local destructionTicksLeft = math.max( destructionTick - currentTick, 0 )
			self:sv_finishQuest( destructionTicksLeft )
			self.sv.finishedQuest = true
		end
	end
end

function WarehouseDestructionQuest.server_onRefresh( self )
	for _, trackName in pairs( WaypointTracks ) do
		local waypointTrack = QuestEntityManager.Sv_GetNamedWaypointTrack( trackName )
		if waypointTrack then
			self.sv.saved.waypointTracks[trackName] = EvaluateWaypointTrack( waypointTrack.waypointTrack, waypointTrack.position, waypointTrack.rotation, waypointTrack.scale, waypointTrack.world )
		end
	end
	self:sv_updateQuest()
end

function WarehouseDestructionQuest.sv_e_onQuestEvent( self, data )

	if data.event == QuestEvent.WaypointTrackLoaded then
		if isAnyOf( data.params.name, WaypointTracks ) then
			local waypointTrack = QuestEntityManager.Sv_GetNamedWaypointTrack( data.params.name )
			if waypointTrack then
				self.sv.saved.waypointTracks[data.params.name] = EvaluateWaypointTrack( waypointTrack.waypointTrack, waypointTrack.position, waypointTrack.rotation, waypointTrack.scale, waypointTrack.world )
				self:sv_updateQuest()
			end
		end
	elseif data.event == QuestEvent.QuestUnitCreated then
		if data.params.character:getCharacterType() == unit_shipMechanic then
			if self.sv.questStage < Stages.warehouse_countdown then
				self.sv.saved.questWaypointUnitId = WaypointQuestUnitManager.Sv_AddWaypointQuestUnit( data.params.character:getUnit(), self.scriptableObject )
			end
			self:sv_updateQuest()
		end
	elseif data.event == QuestEvent.QuestUnitInteract then
		if data.params.questUnitEnum == QuestUnits.Lorenzo then
			if self.sv.questStage == Stages.take_warehouse_key then
				-- Grant the master key
				if not LogEntryManager.Sv_HasLog( LOGS.log_warehousemasterkey ) then
					LogEntryManager.Sv_AddLog( LOGS.log_warehousemasterkey )
				end

				-- Check if door is already open
				local doorOpen = false
				local unit = QuestManager.Sv_GetQuestUnit( QuestUnits.Lorenzo )
				if unit then
					local tileStorageKey = TileStorageManager.Sv_GetTileStorageKeyFromObject( unit.character )
					doorOpen = TileStorageManager.Sv_GetValueInSubTable( tileStorageKey, KEY_LOCK_TABLE, "TopDepartment01" ) == true
				end
				if doorOpen then
					self.sv.questStage = Stages.explore_top_department
				else
					self.sv.questStage = Stages.unlock_first_door
				end
				self:sv_updateQuest()
			end
		end
	elseif data.event == QuestEvent.QuestConsoleDestroyed then
		DialogManager.Sv_PlayDialogBeat( "mainframe_warning_01", self.scriptableObject )

		-- Remember quest warehouse
		self.sv.saved.questWarehouseIndex = data.params.warehouseIndex
		self.sv.questStage = Stages.mainframe_warning01
		self:sv_updateQuest()
	elseif data.event == QuestEvent.LogCardReaderUnlock then
		if data.params.keyTag == "TopDepartment01" then
			if self.sv.questStage <= Stages.unlock_first_door then
				self.sv.questStage = Stages.explore_top_department
			end
			self:sv_updateQuest()
		end
	elseif data.event == QuestEvent.RecipeUnlocked then
		if data.params.uuidString == tostring( obj_interactive_plasmadrill_lvl1 ) then
			if isAnyOf( self.sv.questStage, { Stages.chest_unopened_reaction, Stages.open_chest } ) then
				self.sv.questStage = Stages.chest_opened_reaction
				self.sv.waypointIndex = 1
			elseif self.sv.questStage == Stages.approach_chest then
				self.sv.questStage = Stages.go_to_second_door
				self.sv.waypointIndex = 1
			end
			self:sv_updateQuest()
		end
	elseif data.event == QuestEvent.QuestConsoleHit then
		if data.params.hits == 1 and self.sv.questStage == Stages.hit_console_1 then
			DialogManager.Sv_PlayDialogBeat( "lorenzo_hit_console_one", self.scriptableObject )
			local questUnit = QuestManager.Sv_GetQuestUnit( QuestUnits.Lorenzo )
			if questUnit then
				questUnit:sendCharacterEvent( "emote_surprised" )
			end
			self.sv.questStage = Stages.hit_console_2
			self:sv_updateQuest()
		elseif data.params.hits == 2 and self.sv.questStage == Stages.hit_console_2 then
			DialogManager.Sv_PlayDialogBeat( "lorenzo_hit_console_two", self.scriptableObject )
			self.sv.questStage = Stages.hit_console_3
			self:sv_updateQuest()
		elseif data.params.hits == 3 and self.sv.questStage == Stages.hit_console_3 then
			DialogManager.Sv_PlayDialogBeat( "lorenzo_hit_console_three", self.scriptableObject )
			local questUnit = QuestManager.Sv_GetQuestUnit( QuestUnits.Lorenzo )
			if questUnit then
				questUnit:sendCharacterEvent( "emote_cheer" )
			end
			self.sv.questStage = Stages.hit_console_4
			self:sv_updateQuest()
		elseif data.params.hits == 4 and self.sv.questStage == Stages.hit_console_4 then
			self.sv.questStage = Stages.destroy_console
			self:sv_updateQuest()
		end
	end
end

function WarehouseDestructionQuest.sv_e_waypointCompleted( self, params )
	local currentWaypointTrackName = GetCurrentTrackName( self.sv.questStage )
	local currentWaypointTrack = self.sv.saved.waypointTracks[currentWaypointTrackName]
	if currentWaypointTrack then
		local waypointObject = currentWaypointTrack[self.sv.waypointIndex]
		if waypointObject then
			self.sv.waypointIndex = self.sv.waypointIndex + 1
			if currentWaypointTrack[self.sv.waypointIndex] == nil then
				-- Completed the whole track
				if self.sv.questStage == Stages.follow_inside then
					self.sv.questStage = Stages.go_to_first_door
				elseif self.sv.questStage == Stages.go_to_first_door then
					self.sv.questStage = Stages.take_warehouse_key
				elseif self.sv.questStage == Stages.explore_top_department then
					local hasSchematic = RecipeManager.Sv_IsUnlocked( tostring( obj_interactive_plasmadrill_lvl1 ) )
					self.sv.questStage = hasSchematic and Stages.go_to_second_door or Stages.approach_chest
				elseif self.sv.questStage == Stages.approach_chest then
					local hasSchematic = RecipeManager.Sv_IsUnlocked( tostring( obj_interactive_plasmadrill_lvl1 ) )
					if hasSchematic then
						self.sv.questStage = Stages.go_to_second_door
					else
						self.sv.questStage = Stages.chest_unopened_reaction
					end
				elseif self.sv.questStage == Stages.chest_unopened_reaction then
					self.sv.questStage = Stages.open_chest
				elseif self.sv.questStage == Stages.chest_opened_reaction then
					self.sv.questStage = Stages.go_to_second_door
				elseif self.sv.questStage == Stages.go_to_second_door then
					self.sv.questStage = Stages.second_door_trouble
				elseif self.sv.questStage == Stages.second_door_step_aside then
					self.sv.questStage = Stages.unlock_second_door
					ProgressionManager.Sv_UnlockWarehouseConsole()
				elseif self.sv.questStage == Stages.enter_second_door then
					self.sv.questStage = Stages.go_to_console
				elseif self.sv.questStage == Stages.go_to_console then
					self.sv.questStage = Stages.hit_console_1
				elseif self.sv.questStage == Stages.lorenzo_try_fix01 then
					DialogManager.Sv_PlayDialogBeat( "mainframe_warning_02", self.scriptableObject )
					self.sv.questStage = Stages.mainframe_warning02
				elseif self.sv.questStage == Stages.lorenzo_try_fix02 then
					DialogManager.Sv_PlayDialogBeat( "mainframe_selfdestruct", self.scriptableObject )

					if self.sv.saved.questWarehouseIndex then
						WarehouseManager.Sv_BeginCountdown( self.sv.saved.questWarehouseIndex )
					else
						sm.log.error( "Failed to find the index of the warehouse that should be destroyed." )
					end

					-- Mark Lorenzo for removal when countdown starts, player might run away without listening to dialog
					if self.sv.saved.questWaypointUnitId then
						local waypointUnitData = WaypointQuestUnitManager.Sv_GetWaypointQuestUnit( self.sv.saved.questWaypointUnitId )
						if waypointUnitData and waypointUnitData.unit then
							sm.event.sendToUnit( waypointUnitData.unit, "sv_e_markForRemoval" )
						end
					end

					self.sv.questStage = Stages.mainframe_selfdestruct
				elseif self.sv.questStage == Stages.warehouse_countdown_goodbye then
					DialogManager.Sv_PlayDialogBeat( "mainframe_goodbye", self.scriptableObject )
					self.sv.questStage = Stages.warehouse_countdown_mainframe
				else
					-- Fallback, but all cases should be handled above
					self.sv.questStage = self.sv.questStage + 1
				end
				self.sv.waypointIndex = 1
			end
		end
	end
	self:sv_updateQuest()
end

function WarehouseDestructionQuest.sv_e_onDialogCompleted( self, data )
	if data.params.uuid == dialog_warehouse_mainframe then
		if self.sv.questStage == Stages.mainframe_warning01 then
			self.sv.questStage = Stages.lorenzo_try_fix01
		elseif self.sv.questStage == Stages.mainframe_warning02 then
			self.sv.questStage = Stages.lorenzo_try_fix02
		elseif self.sv.questStage == Stages.mainframe_selfdestruct then
			self.sv.questStage = Stages.warehouse_countdown_goodbye
		elseif self.sv.questStage == Stages.warehouse_countdown_mainframe then
			self.sv.questStage = Stages.warehouse_countdown
		else
			return
		end
	
		self:sv_updateQuest()
	end
end

function WarehouseDestructionQuest.sv_finishQuest( self, destructionTicksLeft )
	QuestManager.Sv_UnsubscribeAllEvents( self.scriptableObject )

	CompleteAndActivateQuestThroughDialogBeat( "quest_warehouse_destruction", "quest_save_watchtower", "hubert_save_watchtower_start", ( destructionTicksLeft / 40 ) + 30 )

	-- Make sure all the quest progress rewards have been unlocked when the warehouse explodes
	if not LogEntryManager.Sv_HasLog( LOGS.log_warehousemasterkey ) then
		LogEntryManager.Sv_AddLog( LOGS.log_warehousemasterkey )
	end
	local drillDrop = tostring( obj_interactive_plasmadrill_lvl1 )
	if not RecipeManager.Sv_IsUnlocked( drillDrop ) then
		RecipeManager.Sv_UnlockRecipe( drillDrop )
	end

	if self.sv.saved.questWaypointUnitId then
		local waypointUnitData = WaypointQuestUnitManager.Sv_GetWaypointQuestUnit( self.sv.saved.questWaypointUnitId )
		if waypointUnitData and waypointUnitData.unit then
			sm.event.sendToUnit( waypointUnitData.unit, "sv_e_markForRemoval" )
		end
		WaypointQuestUnitManager.Sv_RemoveWaypointQuestUnit( self.sv.saved.questWaypointUnitId )
	end
end

function WarehouseDestructionQuest.sv_updateQuest( self )
	-- Update quest state
	self.scriptableObject.publicData = {}
	self.scriptableObject.publicData.progressString = ""
	self.scriptableObject.publicData.questStage = self.sv.questStage

	local waypointObject = nil
	local upcomingWaypointObject = nil
	local currentWaypointTrackName = GetCurrentTrackName( self.sv.questStage )
	local currentWaypointTrack = self.sv.saved.waypointTracks[currentWaypointTrackName]
	if currentWaypointTrack then
		waypointObject = currentWaypointTrack[self.sv.waypointIndex]
		upcomingWaypointObject = currentWaypointTrack[self.sv.waypointIndex+1]
	end
	
	QuestWaypointState.SetWaypointObject( self.scriptableObject, self.sv.saved.questWaypointUnitId, waypointObject )
	QuestWaypointState.SetUpcomingWaypointObject( self.scriptableObject, self.sv.saved.questWaypointUnitId, upcomingWaypointObject )
	QuestWaypointState.SetDialogOptions( self.scriptableObject, self.sv.saved.questWaypointUnitId, { dialogUuid = dialog_scout_farmer, dialogType = DialogType.Person, dialogSpeakerName = DialogSpeakerName.Lorenzo } )

	if self.sv.questStage ~= self.sv.saved.questStage then
		-- Make sure the waypoint progress resets if the quest stage has been changed from somewhere else
		self.sv.waypointIndex = 1
	end
	self.sv.saved.waypointIndex = self.sv.waypointIndex
	self.sv.saved.questStage = self.sv.questStage
	self.storage:save( self.sv.saved )
	self.network:setClientData( self.sv.saved )

	self:sv_progressReaction()
end

function WarehouseDestructionQuest.sv_progressReaction( self )
	if self.sv.questStage == Stages.take_warehouse_key then
		-- Makes Lorenzo hold out the key
		QuestWaypointState.SetWaitInteraction( self.scriptableObject, self.sv.saved.questWaypointUnitId, { animate = true, text = "#{INTERACTION_PICK_UP}" } )
	else
		QuestWaypointState.SetWaitInteraction( self.scriptableObject, self.sv.saved.questWaypointUnitId, nil )
	end

	self.scriptableObject.publicData.canDestroyConsole = self.sv.saved.questStage >= Stages.hit_console_1
end

function WarehouseDestructionQuest.client_onCreate( self )
	self.cl = {}
	self.cl.hidden = true
end

function WarehouseDestructionQuest.client_onClientDataUpdate( self, data )
	local prevStage = self.cl.questStage
	self.cl.questStage = data.questStage
	self.cl.hidden = data.hidden
	self:cl_updateProgress( prevStage )
end

function WarehouseDestructionQuest.cl_updateProgress( self, prevStage )
	local trackingData = self.data.trackingSteps
    trackingData.follow.complete = self.cl.questStage > Stages.take_warehouse_key
	trackingData.chest.complete = self.cl.questStage > Stages.open_chest
	trackingData.approach.complete = self.cl.questStage > Stages.second_door_trouble
	trackingData.open.complete = self.cl.questStage > Stages.unlock_second_door
	trackingData.destroy.complete = self.cl.questStage > Stages.destroy_console
	trackingData.escape.complete = self.cl.questStage > Stages.warehouse_countdown

	ApplyTrackingProgress( self, trackingData, self.cl.questStage, prevStage )
	self.scriptableObject.clientPublicData.hidden = self.cl.hidden

	if self.cl.questStage == Stages.follow_inside then
        QuestEntityManager.Cl_ActivateEventPing( "quest_destroy_warehouse.elevator" )
	else
		QuestEntityManager.Cl_DeactivateEventPing( "quest_destroy_warehouse.elevator" )
	end
	if not self.cl.hidden then
		QuestManager.Cl_OnQuestCreated( "quest_warehouse_destruction" )
		QuestManager.Cl_UpdateQuestTracker()
	end
end