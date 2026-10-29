dofile( "$SURVIVAL_DATA/Scripts/game/managers/QuestManager.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/quest_util.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/survival_dialogs.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/managers/NodeSpawnManager.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/managers/DialogManager.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/managers/LogEntryManager.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/managers/BabyWocManager.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/survival_logs.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/survival_constants.lua" )

EndGameQuest = class()
EndGameQuest.isSaveObject = true

local QuestName = "quest_endgame"

local LockerPing = "quest_endgame.locker_ping"

local StartAreaTileStorageKey = "ts_1:(-38,-42)"
local StartAreaTileCell = { x = -38, y = -42 }
local TileSwapFlag = "ending"

local FireExtinguishRange = { min = { x = -38, y = -42 }, max = { x = -37, y = -40 } }


local EndCinematicName = "cinematic.survivalend01"

local ShipAreaTrigger = "quest_endgame.crashedship_area"

local PickupPhotoBeat = "lorenzo_calls_after_pickup_photo"
local ReturnSpeechBeat = "speak_to_lorenzo_before_end_cinematic"
local HubertGoodbyeEntry = "HubertBlastoff"
local PhaeGoodbyeEntry = "PhaeBlastoff"

local EndGameQuestMarkers = {
	"quest_endgame.marker_ship",	-- marker for Lorenzo's crashed ship (go get photo)
	"quest_endgame.marker_locker",			-- marker for the locker at the crashed ship
	"quest_endgame.marker_lorenzo",	-- static fallback marker for Lorenzo at the starter ship
	"quest_hosted_lorenzo.marker",	-- marker for returning to Lorenzo at the starter ship
	"quest_hosted_hubert.marker",	-- marker for saying goodbye to Hubert
	"quest_hosted_phe.marker",		-- marker for saying goodbye to Phae
}

local CelebrationSpawn = "quest_endgame.spawn_ship_npcs"
local ShipClearAreaTrigger = "quest_tutorial.area_ship"

local ShipRobotClearRadius = 64 * 5

local ShipRobotClearInterval = 40 * 3

local Stages = {
	go_to_crashedship = 1,	-- travel to Lorenzo's crashed ship
	pickup_photo = 2,		-- pick up the photo from the locker chest
	listen_lorenzo = 3,		-- Lorenzo calls after pickup; keep the "Retrieve" checkmark filled until he finishes
	return_to_lorenzo = 4,	-- return to Lorenzo with the photo
	listen_lorenzo_return = 5,	-- Lorenzo's farewell speech on return; keep the return checkmark filled until he finishes
	say_goodbye_hubert = 6,	-- say goodbye to Hubert first
	say_goodbye_phae = 7,	-- then say goodbye to Phae
	depart = 8,				-- talk to Lorenzo to depart (plays the end cinematic)
}
EndGameQuest.Stages = Stages

-- Stage reconciliation for the main quest actors that host the celebration.
local MainQuestActorRecovery = {
	{
		actorName = "Lorenzo",
		track = "corepickup_end_lorenzo",
		backupSpawn = "end_backup_spawn_lorenzo",
		notifies = {
			{ minStage = Stages.return_to_lorenzo, event = "notify.return_to_lorenzo" },
			{ minStage = Stages.depart, event = "notify.ready_to_depart" },
		},
	},
	{
		actorName = "Hubert",
		track = "corepickup_end_hubert",
		backupSpawn = "end_backup_spawn_hubert",
		notifies = {
			{ minStage = Stages.return_to_lorenzo, event = "notify.return_to_lorenzo" },
			{ minStage = Stages.say_goodbye_hubert, event = "notify.goodbye_hubert" },
		},
	},
	{
		actorName = "Phe",
		track = "corepickup_end_phe",
		backupSpawn = "end_backup_spawn_phae",
		notifies = {
			{ minStage = Stages.return_to_lorenzo, event = "notify.return_to_lorenzo" },
			{ minStage = Stages.say_goodbye_phae, event = "notify.goodbye_phae" },
		},
	},
}

-- Server

function EndGameQuest.server_onCreate( self )
	self.sv = {}
	self.sv.saved = self.storage:load()
	if self.sv.saved == nil then
		self.sv.saved = {}
		self.sv.saved.stage = Stages.go_to_crashedship
	end

	-- Subscribe to events we'll need
	QuestManager.Sv_SubscribeEvent( QuestEvent.InventoryChanges, self.scriptableObject, "sv_e_onQuestEvent" )
	QuestManager.Sv_SubscribePlayerEnterAreaTrigger( ShipAreaTrigger, self.scriptableObject, "sv_e_onQuestEvent" )

	-- Custom events
	QuestManager.Sv_SubscribeEvent( QuestEvent.DialogCompleted, self.scriptableObject, "sv_e_onDialogCompleted" )
	QuestManager.Sv_SubscribeEvent( "event.quest_endgame.lorenzo_first_interact", self.scriptableObject, "sv_e_onQuestEvent" )
	QuestManager.Sv_SubscribeEvent( "event.quest_endgame.depart", self.scriptableObject, "sv_e_onQuestEvent" )
	QuestManager.Sv_SubscribeEvent( "event.quest_endgame.cinematic_done", self.scriptableObject, "sv_e_onQuestEvent" )
	QuestManager.Sv_SubscribeEvent( "event.quest_endgame.engine_blast", self.scriptableObject, "sv_e_onQuestEvent" )



	self.sv.endAreaNonBots = {}
	
	-- Delay one tick so QuestActorManager/NodeSpawnManager have loaded before reconciling actor state.
	sm.event.sendToScriptableObject( self.scriptableObject, "sv_e_reconcileCelebrationActors", true )

	self:sv_saveAndSync()
end

function EndGameQuest.sv_saveAndSync( self )
	if sm.exists( self.scriptableObject ) then
		self.storage:save( self.sv.saved )
		self.network:setClientData( { stage = self.sv.saved.stage } )
		self.scriptableObject.publicData =  { stage = self.sv.saved.stage } 
	end
end


-- PATCH (recovery) ------------------------------------------------------------
-- Reconcile the celebration actors with the current quest stage. 
function EndGameQuest.sv_e_reconcileCelebrationActors( self, first )
	local stage = self.sv.saved.stage
	if stage < Stages.listen_lorenzo then
		return -- the celebration crew hasn't been spawned yet
	end

	local done = true
	local world = WorldManager.Sv_GetWorld( "overworld" )
	for _, recovery in ipairs( MainQuestActorRecovery ) do
		local actorData = QuestActorManager.Sv_GetActor( recovery.actorName )
		local stateData = actorData and actorData.stateData
		local onTrack = stateData ~= nil and ( stateData.trackName == recovery.track or stateData.pendingTrackName == recovery.track )
		if not onTrack then
			done = false
			if first then
				sm.log.info( "EndGameQuest patch: actor '" .. recovery.actorName .. "' is missing its '" .. recovery.track .. "' track; re-triggering backup spawn." )
				NodeSpawnManager.Sv_ActivateSpawnTrigger( recovery.backupSpawn, world )
			end
		else
			for _, notify in ipairs( recovery.notifies ) do
				if stage >= notify.minStage then
					QuestActorManager.Sv_NotifyActor( recovery.actorName, notify.event )
				end
			end
		end
	end
	
	if not done then
		sm.event.sendToScriptableObject( self.scriptableObject, "sv_e_reconcileCelebrationActors", nil, nil, false )
	end
end

function EndGameQuest.server_onFixedUpdate( self, dt )
	if self.sv.saved.clearShipShapes then
		local areaTriggerData = QuestEntityManager.Sv_GetNamedAreaTrigger( ShipClearAreaTrigger )
		if areaTriggerData then
			local trigger = areaTriggerData.areaTrigger
			local position = trigger:getWorldPosition()
			local rotation = trigger:getWorldRotation()
			local halfExtents = trigger:getSize()
			local shapeContacts = sm.physics.getShapeContactsInBox( position, rotation, halfExtents, trigger:getWorld() ) -- the quest areatrigger has a character filter.
			for _, contact in ipairs( shapeContacts ) do
				if contact.shape.body:isStatic() then
					sm.shape.destroyShape( contact.shape )
				end
			end
			print("EndGameQuest: Cleared shapes in ship volume")

			self.sv.saved.clearShipShapes = nil
			self:sv_saveAndSync()
		end
	end

	-- keep the area clear of bots in the end game, unless they are raiders.
	if self.sv.saved.stage > Stages.pickup_photo then
		if not self.sv.lastBotsClearedTick or sm.game.getCurrentTick() - self.sv.lastBotsClearedTick > ShipRobotClearInterval then
			self.sv.lastBotsClearedTick = sm.game.getCurrentTick()
			local world = WorldManager.Sv_GetWorld( "overworld" )
			if world then
				-- only checking while the start area is loaded
				if world:isCellLoadedServer( StartAreaTileCell.x, StartAreaTileCell.y ) then
					local units = sm.unit.getAllUnits( world )
					local cellPos = sm.vec3.new( StartAreaTileCell.x, StartAreaTileCell.y, 0 ) * 64
					for _, unit in pairs( units ) do
						if not self.sv.endAreaNonBots[unit.id] and sm.exists( unit ) then
							if not unit.publicData or not unit.publicData.raider then
								local character = unit:getCharacter() or nil
								if character and sm.exists( character ) and ( character:getWorldPosition() - cellPos ):length2() < ShipRobotClearRadius * ShipRobotClearRadius then
									-- if inside the killzone
									if isAnyOf( character:getCharacterType(), g_robots ) then
										unit:destroy()
										print( "Destroyed a robot at the start area" )
									else
										-- cache non-bots units in the area so we don't check them again
										self.sv.endAreaNonBots[unit.id] = true
									end
								end
							end
						end
					end
				end
			end
		end
	end
end



























function EndGameQuest.sv_e_onQuestEvent( self, data )
	if self.sv.saved.stage == Stages.go_to_crashedship then
		if data.event == ShipAreaTrigger .. QuestEvent.AreaTriggerPlayerEnterSuffix then
            self.sv.saved.stage = Stages.pickup_photo
		end
	elseif self.sv.saved.stage == Stages.pickup_photo then
		if data.event == QuestEvent.InventoryChanges then
			if FindInventoryChange( data.params.changes, ITEMS.obj_questitem_pictureframe ) > 0 then
                local world = WorldManager.Sv_GetWorld( "overworld" )
                SetTileStorageFlag( StartAreaTileStorageKey, TileSwapFlag )
				local position = sm.vec3.new( StartAreaTileCell.x, StartAreaTileCell.y, 0 ) * 64
                sm.event.sendToGame( "sv_reloadTile", { pos = position, world = world } )
				EffectManager.Sv_UpdateTagFilteredEffectsForTile( world, position, { TileSwapFlag } )

                NodeSpawnManager.Sv_ActivateSpawnTrigger( CelebrationSpawn )

                -- Delete all shapes within a box covering the ship (deferred to fixedUpdate until the cell is loaded)
				self.sv.saved.clearShipShapes = true

				if world then
					for x = FireExtinguishRange.min.x, FireExtinguishRange.max.x do
						for y = FireExtinguishRange.min.y, FireExtinguishRange.max.y do
							sm.event.sendToWorld( world, "sv_e_removeFiresInCell", { x = x, y = y } )
						end
					end
				end

				LogEntryManager.Sv_AddLog( LOGS.log_lorenzo_photo )
				DialogManager.Sv_PlayDialogBeat( PickupPhotoBeat, self.scriptableObject )
				-- Keep the "Retrieve" checkmark filled while Lorenzo calls; sv_e_onDialogCompleted advances once he finishes.
				self.sv.saved.stage = Stages.listen_lorenzo
			end
		end

	elseif self.sv.saved.stage == Stages.return_to_lorenzo then
		if data.event == "event.quest_endgame.lorenzo_first_interact" then
			-- Player interacted with Lorenzo; he gives his farewell speech. Keep the return checkmark filled until sv_e_onDialogCompleted advances to say_goodbye.
			self.sv.saved.stage = Stages.listen_lorenzo_return
		end
	elseif self.sv.saved.stage == Stages.depart then
		if data.event == "event.quest_endgame.depart" then
			BabyWocManager.Sv_DespawnFollower()

			-- Play End Game cinematic — the cinematic effect fires "event.quest_endgame.cinematic_done" via sv_e_sendQuestEvent callback when done
			sm.game.pauseSaving( "End Game", 40 * 60 * 3 )

			self.network:sendToClients( "cl_grantEndGameSuit" )

			EffectManager.Sv_PlayNamedCinematic( {
				name = EndCinematicName,
				callbackData = { world = WorldManager.Sv_GetWorld( "overworld" ), tileStorageKey = StartAreaTileStorageKey, useEffectWorld = true },
				interruptible = false
			} )

			print("End Game cinematic started")
			for _, name in pairs( CELEBRATION_ACTORS ) do
				QuestActorManager.Sv_NotifyActor( name, "notify.end_cinematic" )
			end
		end
		if data.event == "event.quest_endgame.engine_blast" then
			-- Cinematic: Send engine blast event to actors
			for _, name in pairs( CELEBRATION_ACTORS ) do
				QuestActorManager.Sv_NotifyActor( name, "notify.engine_blast" )
			end
		end
		if data.event == "event.quest_endgame.cinematic_done" then
			self.network:sendToClients( "cl_exitToMenu" )
		end
	end

	self:sv_saveAndSync()
end

function EndGameQuest.sv_e_onDialogCompleted( self, data )
	if self.sv.saved.stage == Stages.listen_lorenzo then
		if IsDialogBeat( data.params.uuid, data.params.entryName, PickupPhotoBeat ) then
			-- Lorenzo finished his call: now send the player back to him with the photo.
			self.sv.saved.stage = Stages.return_to_lorenzo
			for _, name in pairs( CELEBRATION_ACTORS ) do
				QuestActorManager.Sv_NotifyActor( name, "notify.return_to_lorenzo" )
			end
			self:sv_saveAndSync()
		end
		return
	end

	if self.sv.saved.stage == Stages.listen_lorenzo_return then
		if IsDialogBeat( data.params.uuid, data.params.entryName, ReturnSpeechBeat ) then
			-- Lorenzo finished his farewell speech: now let Hubert say goodbye first.
			self.sv.saved.stage = Stages.say_goodbye_hubert
			for _, name in pairs( CELEBRATION_ACTORS ) do
				QuestActorManager.Sv_NotifyActor( name, "notify.goodbye" )
			end

			-- Only Hubert becomes ready to talk; Phae stays gated until Hubert's goodbye is done.
			QuestActorManager.Sv_NotifyActor( "Hubert", "notify.goodbye_hubert" )

			self:sv_saveAndSync()
		end
		return
	end

	local uuid = tostring( data.params.uuid )
	local changed = false
	if uuid == dialog_end_game_hubert and data.params.entryName == HubertGoodbyeEntry then
		if self.sv.saved.stage == Stages.say_goodbye_hubert then
			-- Hubert's goodbye is done: advance and let Phae become ready to talk.
			self.sv.saved.stage = Stages.say_goodbye_phae
			QuestActorManager.Sv_NotifyActor( "Phe", "notify.goodbye_phae" )
			changed = true
		end
	elseif uuid == dialog_end_game_phae and data.params.entryName == PhaeGoodbyeEntry then
		if self.sv.saved.stage == Stages.say_goodbye_phae then
			-- Both goodbyes said: let the player talk to Lorenzo to depart.
			self.sv.saved.stage = Stages.depart
			QuestActorManager.Sv_NotifyActor( "Lorenzo", "notify.ready_to_depart" )
			changed = true
		end
	end

	if changed then
		self:sv_saveAndSync()
	end
end

-- Client

function EndGameQuest.client_onCreate( self )
	self.cl = {}
	self.cl.stage = Stages.go_to_crashedship
	self.cl.tracked = false
	self.scriptableObject.clientPublicData = {}
	QuestManager.Cl_OnQuestCreated( QuestName )
end

function EndGameQuest.client_onDestroy( self )
	self:cl_e_onUntracked()
end

function EndGameQuest.client_onRefresh( self )
	self:cl_updateMarkers()
end

function EndGameQuest.client_onClientDataUpdate( self, data )
	local prevStage = self.cl.stage
	self.cl.stage = data.stage
	self.scriptableObject.clientPublicData = self.scriptableObject.clientPublicData or {}
	self.scriptableObject.clientPublicData.stage = data.stage
	self:cl_updateMarkers()
	self:cl_updateProgress( prevStage )
end

function EndGameQuest.cl_updateProgress( self, prevStage )
	local trackingData = self.data.trackingSteps

	trackingData.goto_ship.complete = self.cl.stage > Stages.pickup_photo
	trackingData.pickup.complete = self.cl.stage > Stages.return_to_lorenzo
	trackingData.goodbye_hubert.complete = self.cl.stage > Stages.say_goodbye_hubert
	trackingData.goodbye_phae.complete = self.cl.stage > Stages.say_goodbye_phae
	trackingData.final_depart.complete = self.cl.stage > Stages.depart

	ApplyTrackingProgress( self, trackingData, self.cl.stage, prevStage )
	QuestManager.Cl_UpdateQuestTracker()
end

function EndGameQuest.sv_n_updateMarkers( self )
	self.network:sendToClients( "cl_n_updateMarkers" )
end

function EndGameQuest.cl_n_updateMarkers( self )
	self:cl_updateMarkers()
end

function EndGameQuest.cl_updateMarkers( self )
	if not self.cl.tracked then
		return
	end
	self:cl_hideMarkers()

	if self.cl.stage == Stages.go_to_crashedship then
		QuestEntityManager.Cl_SetNamedQuestMarkerVisible( "quest_endgame.marker_locker", true )
	elseif self.cl.stage == Stages.pickup_photo then
		QuestEntityManager.Cl_SetNamedQuestMarkerVisible( "quest_endgame.marker_locker", true )
		QuestEntityManager.Cl_ActivateEventPing( LockerPing )
	elseif self.cl.stage == Stages.return_to_lorenzo then
		local hostedMarker = QuestEntityManager.Cl_GetNamedQuestMarker( "quest_hosted_lorenzo.marker" )
		QuestEntityManager.Cl_SetNamedQuestMarkerVisible( hostedMarker and hostedMarker.world:getId() == 1 and "quest_hosted_lorenzo.marker" or "quest_endgame.marker_lorenzo", true )
	elseif self.cl.stage == Stages.say_goodbye_hubert then
		QuestEntityManager.Cl_SetNamedQuestMarkerVisible( "quest_hosted_hubert.marker", true )
	elseif self.cl.stage == Stages.say_goodbye_phae then
		QuestEntityManager.Cl_SetNamedQuestMarkerVisible( "quest_hosted_phe.marker", true )
	elseif self.cl.stage == Stages.depart then
		QuestEntityManager.Cl_SetNamedQuestMarkerVisible( "quest_hosted_lorenzo.marker", true )
	end
end

function EndGameQuest.cl_hideMarkers( self )
	for _, markerName in ipairs( EndGameQuestMarkers ) do
		QuestEntityManager.Cl_SetNamedQuestMarkerVisible( markerName, false )
	end
	QuestEntityManager.Cl_DeactivateEventPing( LockerPing )
end

function EndGameQuest.cl_e_onTracked( self )
	self.cl.tracked = true
	self:cl_updateMarkers()
end

function EndGameQuest.cl_e_onUntracked( self )
	self.cl.tracked = false
	self:cl_hideMarkers()
end

function EndGameQuest.cl_exitToMenu( self )
	sm.game.exitToMenuWithEndCredits()
end

function EndGameQuest.cl_grantEndGameSuit( self )
	local GoldenMechanicSuit = {
		"afe61fa5-7083-411c-b2c0-5d24d9866f4b", -- outfit_torso_goldenmechanic_jacket
		"1c62877a-2fd6-411e-a0a2-a8a3ab123a41", -- outfit_gloves_goldenmechanic_gloves
		"aece23b0-d692-4a15-ba4f-ac19386645df", -- outfit_shoes_goldenmechanic_shoes
		"5f6e028a-ed28-4624-8e85-f6fa66e592f6", -- outfit_legs_goldenmechanic_pants
		"6f63b847-9736-471a-a9cd-e66e6be91f53", -- outfit_backpack_goldenmechanic_backpack
	}
	for _, sUuid in ipairs( GoldenMechanicSuit ) do
		local uuid = sm.uuid.new( sUuid )
		if not sm.localPlayer.isGarmentUnlocked( uuid ) then
			sm.localPlayer.grantQuestItem( uuid )
		end
	end
end
