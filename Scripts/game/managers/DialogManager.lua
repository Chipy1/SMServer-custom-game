dofile( "$SURVIVAL_DATA/Scripts/game/survival_dialogs.lua" )

DialogManager = class()

DialogType = {
	Person = "person",
	Recording = "recording",
	Call = "call"
}

DialogSpeakerName = {
	Lorenzo = "#{DIALOG_NAME_LORENZO}",
	Mysterious = "#{DIALOG_NAME_MYSTERIOUS}",
	Hubert = "#{DIALOG_NAME_HUBERT}",
	Phe = "#{DIALOG_NAME_PHAE}",
	Recording = "#{DIALOG_NAME_RECORDING}",
	Mainframe = "#{DIALOG_NAME_MAINFRAME}",
	Axobot = "#{DIALOG_NAME_AXOBOT}",
	Lorenzo_Clone = "#{DIALOG_NAME_LORENZO}",
	Hubert_Clone = "#{DIALOG_NAME_HUBERT}",
	Phe_Clone = "#{DIALOG_NAME_PHAE}"
}

DialogPriority = {
	MainQuest = 1,
	BondBuilder = 2,
	SideQuest = 3,
	Recording = 4,
	Shout = 5
}


-- Bond builders are dialogs that play for flavor and are not part of any quest. 
-- The idea is that they play while the player(s) are NOT in areas where quest activities normally happen.
-- Whole underground worlds excluded by depth (1 Mining Hub, 3 Station1, 5 Scrapyard, 7 Station2, 8 Final Boss Lobby).
-- Individual tiles (overworld builder quests + hideout, underground elevator tiles) are excluded via
-- STORAGE_CHANNEL_BONDBUILDER_EXCLUSION_TILES, populated during world generation.
local BondBuilderExclusionUndergroundDepths = {
	[1] = true, -- Mining Hub
	[3] = true, -- Station 1
	[5] = true, -- Scrapyard
	[7] = true, -- Station 2
	[8] = true, -- Final Boss Lobby (Drillboss)
}

-- Ordered lists of bond builder dialogs, played in queued order. These are standalone flavor
-- dialogs (not registered in dialog_beats_lookup); each entry is a self-contained spec:
--   { dialog = <uuid>, entry = <entryName>, type = <DialogType>, speaker = <DialogSpeakerName> }
-- A batch is queued in full the first time players reach the matching drill world
-- (signalled by UndergroundElevatorManager via Sv_QueueBondBuilderBatch).
local BondBuilderDialogsDrill1 = {
	{ dialog = dialog_hubert_bondbuilder1, entry = "hubert_bondbuilder1", speaker = "Hubert" },
	{ dialog = dialog_lorenzo_bondbuilder2, entry = "lorenzo_bondbuilder2", speaker = "Lorenzo" },
	{ dialog = dialog_phae_bondbuilder1, entry = "phae_bondbuilder1", speaker = "Phe" },
	{ dialog = dialog_hubert_bondbuilder3, entry = "hubert_bondbuilder3", speaker = "Hubert" },
	{ dialog = dialog_lorenzo_bondbuilder1, entry = "lorenzo_bondbuilder1", speaker = "Lorenzo" },

}
local BondBuilderDialogsDrill2 = {
	{ dialog = dialog_lorenzo_bondbuilder5, entry = "lorenzo_bondbuilder5", speaker = "Lorenzo" },
	{ dialog = dialog_lorenzo_bonus_3, entry = "lorenzo_bonus_3", speaker = "Lorenzo" },
	{ dialog = dialog_lorenzo_bonus_4, entry = "lorenzo_bonus_4", speaker = "Lorenzo" },
	{ dialog = dialog_phae_bondbuilder3, entry = "phae_bondbuilder3", speaker = "Phe" },
	{ dialog = dialog_lorenzo_bondbuilder6, entry = "lorenzo_bondbuilder6", speaker = "Lorenzo" },
	{ dialog = dialog_hubert_bonus_3, entry = "hubert_bonus_3", speaker = "Hubert" },
	{ dialog = dialog_lorenzo_bonus_1, entry = "lorenzo_bonus_1", speaker = "Lorenzo" },
	{ dialog = dialog_lorenzo_bonus_2, entry = "lorenzo_bonus_2", speaker = "Lorenzo" },
	{ dialog = dialog_phae_bondbuilder2, entry = "phae_bondbuilder2", speaker = "Phe" },
	{ dialog = dialog_lorenzo_bondbuilder3, entry = "lorenzo_bondbuilder3", speaker = "Lorenzo" },
}

-- Batch name -> ordered dialog list. Batch names double as the saved "already queued" keys.
local BondBuilderBatches = {
	drill1 = BondBuilderDialogsDrill1,
	drill2 = BondBuilderDialogsDrill2,
}

-- Named bond builders are standalone flavor dialogs played on demand (NOT queued). Each is played
-- immediately like any other dialog, may only fire once (tracked here by name), is blocked while the
-- triggering player is in an exclusion tile/world, and resets the timed bond builder interval.
-- Each entry is a self-contained spec: { dialog = <uuid>, entry = <entryName>, type, speaker }.
local NamedBondBuilders = {
	-- babywoc summon calls
	babywoc_summon1 = { dialog = dialog_hubert_babywoc, entry = "hubert_babywoc", speaker = "Hubert" },
	babywoc_summon2 = { dialog = dialog_lorenzo_babywoc, entry = "lorenzo_babywoc", speaker = "Lorenzo" },

	-- carried-item pickup calls
	carry_pickup1   = { dialog = dialog_hubert_artifacts, entry = "hubert_artifacts", speaker = "Hubert" },
	carry_pickup2   = { dialog = dialog_lorenzo_artifacts, entry = "lorenzo_artifacts", speaker = "Lorenzo" },

	-- general overworld
	carrot_raid  = { dialog = dialog_hubert_bonus_4, entry = "hubert_bonus_4", speaker = "Hubert" },
	hubert_cookbot  = { dialog = dialog_hubert_bonus_1, entry = "hubert_bonus_1", speaker = "Hubert" },
	banana_raid  = { dialog = dialog_hubert_bonus_2, entry = "hubert_bonus_2", speaker = "Hubert" },

	-- Underground (drill1): Hubert comments once players dig far enough from the elevator during VaultQuest2
	drill1_digging = { dialog = dialog_vault_quest_2_hubert, entry = "HubertSecondQuotaDigging", speaker = "Hubert" },
}

local BondBuilderCheckIntervalTicks = 40 * 5 -- Run the scheduler check every 5 seconds
local BondBuilderIntervalTicks = 40 * 60 * 30 -- Default gap between consecutive bond builders (30 minutes of qualifying time)
local BondBuilderBlockedClampTicks = 40 * 60 * 2 -- Keep at least 2 minutes of qualifying time remaining while/after any player is blocked
local BondBuilderAfkMoveThresholdSq = 1.0 * 1.0 -- Squared distance a player must move between checks to count as having moved
local BondBuilderAfkTimeoutTicks = 40 * 60 -- A player is considered inactive (afk) after not moving for this long (1 minute)

-- Plays a bond builder dialog at the lowest priority (into the normal dialog queue).
local function PlayBondBuilderDialog( dialogSpec )
	local speakerName = dialogSpec.speaker and DialogSpeakerName[dialogSpec.speaker] or nil
	DialogManager.Sv_PlayDialog( dialogSpec.dialog, dialogSpec.entry, nil, DialogType.Call, speakerName, DialogPriority.BondBuilder, nil )
end


local CallRange = 50
local CallRangeDeadzone = 2.0

-- swaps phone and in person effects. if the type and effect don't match.
local function GetAudioEffectForType( audioEffect, dialogType )
	if dialogType == DialogType.Call and audioEffect == "Dialog - Npc" then
		return "Dialog - NpcPhone"
	elseif dialogType == DialogType.Person and audioEffect == "Dialog - NpcPhone" then
		return "Dialog - Npc"
	end
	return audioEffect
end

local function ResolveSpeaker( speakerInfo, argsSpeakerObject )
	-- Registered speaker has priority over speakerObject from args.
	local obj = nil
	if speakerInfo and speakerInfo.speakerObject and sm.exists( speakerInfo.speakerObject ) then
		obj = speakerInfo.speakerObject
	elseif argsSpeakerObject and sm.exists( argsSpeakerObject ) then
		obj = argsSpeakerObject
	end
	if obj == nil then
		return nil, nil
	end
	return obj, type( obj )
end

-- Returns true if the speaker is out of range or cannot be located for in-person dialog.
local function IsSpeakerOutOfRange( speakerObj, range )
	range = range or CallRange
	if speakerObj == nil or not sm.exists( speakerObj ) then
		return true
	end
	local speakerType = type( speakerObj )
	local speakerWorld = nil
	local speakerWorldPosition = nil
	if speakerType == "Character" or speakerType == "Harvestable" then
		speakerWorld = speakerObj:getWorld()
		speakerWorldPosition = speakerObj.worldPosition
	elseif speakerType == "Interactable" then
		if speakerObj.body then
			speakerWorld = speakerObj.body:getWorld()
		end
		if speakerObj.shape then
			speakerWorldPosition = speakerObj.shape.worldPosition
		end
	end
	if not speakerWorldPosition then
		return true
	end
	local player = sm.localPlayer.getPlayer()
	local playerCharacter = player:getCharacter()
	if playerCharacter then
		if speakerWorld and speakerWorld ~= playerCharacter:getWorld() then
			return true
		end
		local distance = ( speakerWorldPosition - playerCharacter.worldPosition ):length2()
		if distance > ( range * range ) then
			return true
		end
	end
	return false
end

local OpenCallEffect = "Gui - CallPortrait_stranger_open"
local IdleCallEffect = "Gui - CallPortrait_stranger_idle"
local CloseCallEffect = "Gui - CallPortrait_stranger_close"

local IncomingCallDelaySeconds = 5.0
local QuickIncomingCallDelaySeconds = 0.2
local CallOpenDelaySeconds = 0.5
local CallCloseDelaySeconds = 0.5
local AudioOpenDelaySeconds = 0.5
local AudioCloseDelaySeconds = 0.5

local SmallDialogMaxLength = 64

local function LoadDialogSet( path, dialogTable, language )
	local dialogSet = sm.json.open( path )

	local function parseDialog( dialogContent )
		local uuidString = tostring( dialogContent.uuid )
		local title = dialogContent.title
		dialogTable[uuidString] = { speaker = dialogContent.speaker, title = title, hideInLogbook = dialogContent.hideInLogbook, entries = {} }
		for i, entry in ipairs( dialogContent.entries ) do
			local lines = {}
			local accumulatedTime = 0

			local timingMode = nil
			for j, line in ipairs( entry.lines ) do
				if line.sound then
					lines[j] = { key = line.sound, text = line.text, callback = line.callback, animation = line.animation }
					if timingMode == nil then
						timingMode = "sound"
					end

					assert( timingMode ~= "number", "DialogManager: Audio and duration lines in the same dialog entry is not supported" )
				else
					lines[j] = { startTime = accumulatedTime, endTime = accumulatedTime + line.duration, text = line.text, callback = line.callback, animation = line.animation }
					accumulatedTime = accumulatedTime + line.duration
					if timingMode == nil then
						timingMode = "number"
					end
					assert( timingMode ~= "sound", "DialogManager: Audio and duration lines in the same dialog entry is not supported" )
				end
			end
			dialogTable[uuidString].entries[entry.name] = { lines = lines, audio = entry.audio }
		end
	end

	local nilUuid = sm.uuid.getNil()
	for _, dialog in ipairs( dialogSet.dialogSet ) do
		local languagePath = dialog:gsub( "#{LANGUAGE}", language )
		if not sm.json.fileExists( languagePath ) then
			languagePath = dialog:gsub( "#{LANGUAGE}", "English" )
		end
		if sm.json.fileExists( languagePath ) then
			local dialogContent = sm.json.open( languagePath )
			if dialogContent.list then
				for _, entry in ipairs( dialogContent.list ) do
					parseDialog( entry )
				end
			end
		end
	end
end

local function LoadDialogSets( dialogTable, language )
	if sm.json.fileExists( "$SURVIVAL_DATA/Dialog/dialogset.json" ) then
		LoadDialogSet( "$SURVIVAL_DATA/Dialog/dialogset.json", dialogTable, language )
	end
	if sm.json.fileExists( "$SURVIVAL_DATA/Dialog/shout_dialogset.json" ) then
		LoadDialogSet( "$SURVIVAL_DATA/Dialog/shout_dialogset.json", dialogTable, language )
	end





end

local function LoadShoutEntryInfo( path, entryInfoTable )
	local dialogSet = sm.json.open( path )
	local nilUuid = sm.uuid.getNil()
	for _, dialog in ipairs( dialogSet.dialogSet ) do
		local languagePath = dialog:gsub( "#{LANGUAGE}", "English" )
		if sm.json.fileExists( languagePath ) then
			local dialogContent = sm.json.open( languagePath )
			if dialogContent.list then
				for _, item in ipairs( dialogContent.list ) do
					local uuidString = tostring( item.uuid )
					local entryOrder = {}
					for i, entry in ipairs( item.entries ) do
						entryOrder[i] = entry.name
					end
					entryInfoTable[uuidString] = { entryOrder = entryOrder }
				end
			end
		end
	end
end

local GuiData = dofile( "$SURVIVAL_DATA/Gui/JsonGuis/Dialog.gui" )

local CallerDialogHolder = FindWidget( GuiData, "CallerDialogHolder" )
local AudioDialogHolder = FindWidget( GuiData, "AudioDialogHolder" )
local SubtitleDialogHolder = FindWidget( GuiData, "SubtitleDialogHolder" )
local SubtitleSmallDialogHolder = FindWidget( GuiData, "SubtitleSmallDialogHolder" )
local CallerOpenEffects = FindWidget( GuiData, "CallerOpenEffects" )
local CallerEffectBox = FindWidget( GuiData, "CallerEffectBox" )
local CallerCloseEffectBox = FindWidget( GuiData, "CallerCloseEffectBox" )
local CallerOpenEffectBox = FindWidget( GuiData, "CallerOpenEffectBox" )
local CallerBarText = FindWidget( GuiData, "CallerBarText" )
local CallerDialogText = FindWidget( GuiData, "CallerDialogText" )
local AudioBarText = FindWidget( GuiData, "AudioBarText" )
local AudioDialogText = FindWidget( GuiData, "AudioDialogText" )
local AudioEffectBox = FindWidget( GuiData, "AudioEffectBox" )
local AudioIdleEffectBox = FindWidget( GuiData, "AudioIdleEffectBox" )
local IncomingCallHolder = FindWidget( GuiData, "IncomingCallHolder" )
local IncomingCallEffectBox = FindWidget( GuiData, "IncomingCallEffectBox" )
local CallerCloseEffects = FindWidget( GuiData, "CallerCloseEffects" )
local SubtitleDialogText = FindWidget( SubtitleDialogHolder, "SubtitleDialogText" )
local SubtitleNameBarText = FindWidget( SubtitleDialogHolder, "SubtitleNameBarText" )
local SubtitleSmallDialogText = FindWidget( SubtitleSmallDialogHolder, "SubtitleDialogText" )
local SubtitleSmallNameBarText = FindWidget( SubtitleSmallDialogHolder, "SubtitleNameBarText" )

function DialogManager.server_onCreate( self )
	self.sv = {}
	self.sv.saved = sm.storage.load( STORAGE_CHANNEL_DIALOGMANAGER )
	self.sv.shoutEntryInfo = {}
	self.sv.bondBuilderExclusionTiles = sm.storage.load( STORAGE_CHANNEL_BONDBUILDER_EXCLUSION_TILES ) or {}
	LoadShoutEntryInfo( "$SURVIVAL_DATA/Dialog/shout_dialogset.json", self.sv.shoutEntryInfo )

	local save = false

	if self.sv.saved == nil then
		self.sv.saved = { logbookFeed = {}, queuedDialogs = {}, nextDialogId = 1 }
		save = true
	end

	-- save migration.
	-- added dialog ids
	if self.sv.saved.nextDialogId == nil then
		self.sv.saved.nextDialogId = 1
		save = true
	end
	for _, dialog in ipairs( self.sv.saved.queuedDialogs ) do
		if dialog.id == nil then
			dialog.id = self.sv.saved.nextDialogId
			self.sv.saved.nextDialogId = self.sv.saved.nextDialogId + 1
			save = true
		end
	end
	-- changed to array of completed dialogs.
	if self.sv.saved.logbookFeed == nil then
		self.sv.saved.logbookFeed = {}
		save = true
	end
	-- bond builder (flavor dialog) scheduler state.
	if self.sv.saved.bondBuilder == nil then
		self.sv.saved.bondBuilder = { queue = {}, tick = 0, nextTick = 0, queuedBatches = {}, stopped = false, namedFired = {} }
		save = true
	end
	if save then
		self:sv_save()
	end

	self.sv.unresolvedSpeakers = {} -- set of dialog ids sent to clients with nil speakerObject

	self.sv.bondBuilderTickCounter = 0
	self.sv.bondBuilderLastPositions = {} -- player id -> last sampled worldPosition (transient, for afk detection)
	self.sv.bondBuilderLastMovedTicks = {} -- player id -> game tick the player last moved (transient, for afk detection)

	if not IsEmptyTable( self.sv.saved.queuedDialogs ) then
		self:sv_sendNextDialog()
	end
	self.network:setClientData( { logbookFeed = self.sv.saved.logbookFeed } )
end

-- Returns true if the player is in an area where bond builder (flavor) dialogs should be suppressed:
-- a whole excluded underground world, or on a tile flagged during world generation
-- (overworld builder quest tiles, hideout, underground elevator tiles).
function DialogManager.Sv_IsPlayerInBondBuilderExclusionArea( self, player )
	local character = player:getCharacter()
	if not ( character and sm.exists( character ) ) then
		return false
	end
	local world = character:getWorld()
	if not ( world and sm.exists( world ) ) then
		return false
	end

	-- Whole-world exclusion (mining hub, stations, scrapyard, final boss lobby)
	local publicData = world.publicData
	if publicData then
		if ( publicData.type == "UndergroundWorld" and BondBuilderExclusionUndergroundDepths[publicData.depth] )
			or publicData.type == "DungeonWorld"
			or publicData.type == "WarehouseWorld" then
			return true
		end
	end

	local key = TileStorageManager.Sv_GetTileStorageKeyFromPosition( world, character.worldPosition )
	if key and self.sv.bondBuilderExclusionTiles[key] then
		return true
	end

	return false
end

-- Reloads the cached bond builder exclusion tiles from storage. Called after world generation
-- ( server_onTerrainCreated ) so newly generated tiles are reflected without loading storage on every check.
function DialogManager.Sv_RefreshBondBuilderExclusionTiles()
	if g_dialogManagerSelf then
		g_dialogManagerSelf:sv_e_refreshBondBuilderExclusionTiles()
	end
end

function DialogManager.sv_e_refreshBondBuilderExclusionTiles( self )
	self.sv.bondBuilderExclusionTiles = sm.storage.load( STORAGE_CHANNEL_BONDBUILDER_EXCLUSION_TILES ) or {}
end

-- Queues a named bond builder batch once.
function DialogManager.Sv_QueueBondBuilderBatch( batch )
	if g_dialogManagerSelf then
		g_dialogManagerSelf:sv_e_queueBondBuilderBatch( batch )
	end
end

function DialogManager.sv_e_queueBondBuilderBatch( self, batch )
	local bb = self.sv.saved.bondBuilder
	if bb.stopped then
		return
	end
	if bb.queuedBatches[batch] then
		return
	end
	local list = BondBuilderBatches[batch]
	if list == nil then
		return
	end
	bb.queuedBatches[batch] = true
	local wasEmpty = #bb.queue == 0
	for _, dialogSpec in ipairs( list ) do
		bb.queue[#bb.queue + 1] = dialogSpec
	end
	if wasEmpty and #bb.queue > 0 then
		bb.nextTick = bb.tick + BondBuilderIntervalTicks
	end
	self:sv_save()
end

-- Permanently stops all bond builder playback and clears the queue.
-- Called when the gyrocore (bosstrain) quest begins.
function DialogManager.Sv_StopBondBuilders()
	if g_dialogManagerSelf then
		g_dialogManagerSelf:sv_e_stopBondBuilders()
	end
end

function DialogManager.sv_e_stopBondBuilders( self )
	local bb = self.sv.saved.bondBuilder
	if bb.stopped then
		return
	end
	bb.stopped = true
	bb.queue = {}
	self:sv_save()
end

-- Returns true if the named bond builder has already fired.
function DialogManager.Sv_HasNamedBondBuilderFired( name )
	if g_dialogManagerSelf then
		return g_dialogManagerSelf.sv.saved.bondBuilder.namedFired[name] ~= nil
	end
	return false
end

-- Plays a named (non-queued) bond builder once. Blocked while any player is in an exclusion
-- tile/world. Firing resets the timed bond builder interval so a queued one won't play immediately after.
-- queued one won't play immediately after. Returns true if the dialog was actually played, false otherwise.
function DialogManager.Sv_PlayNamedBondBuilder( name )
	if g_dialogManagerSelf then
		return g_dialogManagerSelf:sv_playNamedBondBuilder( name )
	end
	return false
end

function DialogManager.sv_playNamedBondBuilder( self, name )
	local bb = self.sv.saved.bondBuilder
	if bb.stopped then
		return false
	end
	if bb.namedFired[name] then
		return false
	end
	local spec = NamedBondBuilders[name]
	if spec == nil then
		return false
	end
	-- Blocked while any player is in an exclusion tile/world.
	for _, player in ipairs( sm.player.getAllPlayers() ) do
		if self:Sv_IsPlayerInBondBuilderExclusionArea( player ) then
			return false
		end
	end
	PlayBondBuilderDialog( spec )
	bb.namedFired[name] = true
	-- Push the target out so at least two minutes of qualifying time remain after firing a named bond builder.
	local minNextTick = bb.tick + BondBuilderBlockedClampTicks
	if bb.nextTick < minNextTick then
		bb.nextTick = minNextTick
	end
	self:sv_save()
	return true
end

-- Submits a named bond builder to the FRONT of the queue so it plays next, after the given delay
-- (in seconds). Fires once (tracked by name in bb.namedFired). Skipped while bond builders are
-- stopped. goes through the scheduler, so exclusion tiles/worlds and afk gating still apply.
function DialogManager.Sv_QueueNamedBondBuilderFront( name, delaySeconds )
	if g_dialogManagerSelf then
		g_dialogManagerSelf:sv_e_queueNamedBondBuilderFront( name, delaySeconds )
	end
end

function DialogManager.sv_e_queueNamedBondBuilderFront( self, name , delaySeconds )
	local bb = self.sv.saved.bondBuilder
	if bb.stopped then
		return
	end
	if bb.namedFired[name] then
		return
	end
	local spec = NamedBondBuilders[name]
	if spec == nil then
		return
	end
	table.insert( bb.queue, 1, spec )
	bb.namedFired[name] = true
	local delayTicks = math.max( math.floor( ( delaySeconds or 0 ) * 40 ), 0 )
	bb.nextTick = bb.tick + delayTicks
	self:sv_save()
end

-- Runs on a fixed interval. Advances the saved qualifying-time tick (paused while any player is
-- blocked or while all players are afk) and starts the next bond builder once the tick reaches the
-- saved target tick. Stops entirely once the gyrocore (bosstrain) quest begins.
function DialogManager.sv_updateBondBuilders( self )
	local bb = self.sv.saved.bondBuilder
	if bb.stopped then
		return
	end

	if IsEmptyTable( bb.queue ) then
		return
	end

	-- Determine whether any player blocks the timer and whether any player is active (not afk).
	local anyBlocked = false
	local anyActive = false
	local now = sm.game.getCurrentTick()
	for _, player in ipairs( sm.player.getAllPlayers() ) do
		if anyBlocked == false and self:Sv_IsPlayerInBondBuilderExclusionArea( player ) then
			anyBlocked = true
		end
		local character = player:getCharacter()
		if character and sm.exists( character ) then
			local pos = character.worldPosition
			local last = self.sv.bondBuilderLastPositions[player.id]
			if last == nil or ( pos - last ):length2() >= BondBuilderAfkMoveThresholdSq then
				self.sv.bondBuilderLastMovedTicks[player.id] = now
			end
			self.sv.bondBuilderLastPositions[player.id] = pos
			local lastMovedTick = self.sv.bondBuilderLastMovedTicks[player.id]
			if lastMovedTick and now - lastMovedTick < BondBuilderAfkTimeoutTicks then
				anyActive = true
			end
		end
	end

	if anyBlocked then
		-- Push the target out so at least two minutes of qualifying time remain after unblocking.
		local minNextTick = bb.tick + BondBuilderBlockedClampTicks
		if bb.nextTick < minNextTick then
			bb.nextTick = minNextTick
			self:sv_save()
		end
		return
	end

	if not anyActive then
		-- All players afk: qualifying time does not advance.
		return
	end

	bb.tick = bb.tick + BondBuilderCheckIntervalTicks
	if bb.tick >= bb.nextTick then
		local dialogSpec = table.remove( bb.queue, 1 )
		PlayBondBuilderDialog( dialogSpec )
		bb.nextTick = bb.tick + BondBuilderIntervalTicks
	end
	self:sv_save()
end

function DialogManager.server_onFixedUpdate( self, dt )
	self.sv.bondBuilderTickCounter = self.sv.bondBuilderTickCounter + 1
	if self.sv.bondBuilderTickCounter >= BondBuilderCheckIntervalTicks then
		self.sv.bondBuilderTickCounter = 0
		self:sv_updateBondBuilders()
	end

	for dialogId, _ in pairs( self.sv.unresolvedSpeakers ) do
		for _, dialog in ipairs( self.sv.saved.queuedDialogs ) do
			if dialog.id == dialogId and dialog.speakerObject and type( dialog.speakerObject ) == "Unit" then
				local character = sm.exists( dialog.speakerObject ) and dialog.speakerObject:getCharacter() or nil
				if character then
					self.sv.unresolvedSpeakers[dialogId] = nil
					self.network:sendToClients( "cl_n_updateDialogSpeaker", { id = dialogId, speakerObject = character } )
				end
				break
			end
		end
	end
end

function DialogManager.Sv_PlayDialogBeat( beatName, caller, speakerObject )
	local beatData = dialog_beats_lookup[beatName]
	if beatData then
		local speakerName = beatData.speaker and DialogSpeakerName[beatData.speaker] or nil
		DialogManager.Sv_PlayDialog( beatData.dialog, beatData.entry, caller, beatData.type, speakerName, DialogPriority.MainQuest, speakerObject )
	end
end

function DialogManager.Sv_PlayDialog( uuid, entryName, caller, dialogType, speakerName, priority, speakerObject )
	if g_dialogManagerSelf then
		if type( uuid ) == "Uuid" then
			uuid = tostring( uuid )
		end
		if speakerObject then
			local t = type( speakerObject )
			assert( t == "Unit" or t == "Harvestable" or t == "Interactable", "DialogManager: speakerObject must be a Unit, Harvestable, or Interactable, got " .. t )
			if t == "Harvestable" then
				assert( not speakerObject:isKinematic(), "DialogManager: Kinematic harvestables are not suitable as speakerObject" )
			end
		end
		sm.event.sendToScriptableObject( g_dialogManagerSelf.scriptableObject, "sv_e_playDialog", { uuid = uuid, entryName = entryName, caller = caller, type = dialogType or DialogType.Call, speakerName = speakerName, priority = priority or DialogPriority.MainQuest, speakerObject = speakerObject } )
	end
end

function DialogManager.Sv_PlayShoutDialog( uuid, entryName, caller, speakerName, speakerObject, audibleRange )
	if g_dialogManagerSelf then
		if type( uuid ) == "Uuid" then
			uuid = tostring( uuid )
		end
		if speakerObject then
			local t = type( speakerObject )
			assert( t == "Unit" or t == "Harvestable" or t == "Interactable", "DialogManager: speakerObject must be a Unit, Harvestable, or Interactable, got " .. t )
			if t == "Harvestable" then
				assert( not speakerObject:isKinematic(), "DialogManager: Kinematic harvestables are not suitable as speakerObject" )
			end
		end
		-- Shout dialogs are not queued or saved. They are sent as a one-off message for clients to play opportunistically.
		sm.event.sendToScriptableObject( g_dialogManagerSelf.scriptableObject, "sv_e_playShoutDialog", { uuid = uuid, entryName = entryName, caller = caller, speakerName = speakerName, speakerObject = speakerObject, audibleRange = audibleRange } )
	end
end

function DialogManager.sv_e_playShoutDialog( self, args )
	-- Shout dialogs are played immediately on clients without going through the dialog queue. They are not saved as completed when finished.
	local speakerObject = args.speakerObject
	if speakerObject and type( speakerObject ) == "Unit" then
		speakerObject = speakerObject:getCharacter()
	end
	self.network:sendToClients( "cl_n_playShoutDialog", { uuid = args.uuid, entryName = args.entryName, caller = args.caller, type = DialogType.Person, speakerName = args.speakerName, priority = DialogPriority.Shout, speakerObject = speakerObject, audibleRange = args.audibleRange } )
end

function DialogManager.Sv_GetShoutEntryCount( uuid )
	if g_dialogManagerSelf then
		if type( uuid ) == "Uuid" then
			uuid = tostring( uuid )
		end
		local info = g_dialogManagerSelf.sv.shoutEntryInfo[uuid]
		if info then
			return #info.entryOrder
		end
	end
	return 0
end

function DialogManager.Sv_GetShoutEntryName( uuid, index )
	if g_dialogManagerSelf then
		if type( uuid ) == "Uuid" then
			uuid = tostring( uuid )
		end
		local info = g_dialogManagerSelf.sv.shoutEntryInfo[uuid]
		if info then
			return info.entryOrder[index]
		end
	end
	return nil
end

function DialogManager.Sv_IsDialogQueued( uuid, entryName )
	if g_dialogManagerSelf then
		for _, dialog in ipairs( g_dialogManagerSelf.sv.saved.queuedDialogs ) do
			if dialog.uuid == uuid and dialog.entryName == entryName then
				return true
			end
		end
	end
	return false
end

function DialogManager.sv_save( self )
	sm.storage.save( STORAGE_CHANNEL_DIALOGMANAGER, self.sv.saved )
end

local function SortDialogQueue( dialogQueue )
	local function compare( a, b )
		if a.priority == b.priority then
			return false
		end
		return a.priority < b.priority
	end
	table.sort( dialogQueue, compare )
end

function DialogManager.sv_e_playDialog( self, args )
	args.id = self.sv.saved.nextDialogId
	for _, queuedDialog in ipairs( self.sv.saved.queuedDialogs ) do
		if queuedDialog.uuid == args.uuid and queuedDialog.entryName == args.entryName then
			return
		end
	end
	self.sv.saved.nextDialogId = self.sv.saved.nextDialogId + 1
	table.insert( self.sv.saved.queuedDialogs, args )
	SortDialogQueue( self.sv.saved.queuedDialogs )
	if self.sv.saved.queuedDialogs[1].id == args.id then
		self:sv_sendNextDialog()
	end
	self:sv_save()
end

function DialogManager.sv_sendNextDialog( self )
	local dialog = self.sv.saved.queuedDialogs[1]
	if not dialog then return end
	local copy = {}
	for k, v in pairs( dialog ) do
		copy[k] = v
	end
	if copy.speakerObject and type( copy.speakerObject ) == "Unit" then
		local character = sm.exists( copy.speakerObject ) and copy.speakerObject:getCharacter() or nil
		if character then
			copy.speakerObject = character
		else
			copy.speakerObject = nil
			self.sv.unresolvedSpeakers[dialog.id] = true
		end
	end
	self.network:sendToClients( "cl_n_playDialog", copy )
end

function DialogManager.sv_n_dialogFinished( self, args )
	if not args.hideInLogbook then
		local uuidValue = type( args.uuid ) == "string" and sm.uuid.new( args.uuid ) or args.uuid
		self.sv.saved.logbookFeed[#self.sv.saved.logbookFeed + 1] = {
			uuid = uuidValue,
			entryName = args.entryName
		}
	end
	local removedDialog = self.sv.saved.queuedDialogs[1]
	if removedDialog then
		self.sv.unresolvedSpeakers[removedDialog.id] = nil
	end
	table.remove( self.sv.saved.queuedDialogs, 1 )
	sm.storage.save( STORAGE_CHANNEL_DIALOGMANAGER, self.sv.saved )
	if not args.hideInLogbook then
		self.network:setClientData( { logbookFeed = self.sv.saved.logbookFeed } )
	end

	if not IsEmptyTable( self.sv.saved.queuedDialogs ) then
		self:sv_sendNextDialog()
	end

	QuestManager.Sv_SendEvent( QuestEvent.DialogCompleted, { uuid = args.uuid, entryName = args.entryName } )
end

function DialogManager.client_onClientDataUpdate( self, data )
	self.cl.dialogFeed = data.logbookFeed
	self.cl.completionRevision = self.cl.completionRevision + 1

	self.scriptableObject.clientPublicData.dialogFeed = self.cl.dialogFeed
	self.scriptableObject.clientPublicData.completionRevision = self.cl.completionRevision
end

function DialogManager.client_onCreate( self )
	g_dialogManagerSelf = self
	self.cl = {}
	self.cl.dialogSet = {}
	self.cl.dialogueWindowOpen = false
	self.cl.currentTime = 0
	self.cl.dialogQueue = {}
	self.cl.currentAudioEffect = nil
	self.cl.currentAudioEffectName = nil
	LoadDialogSets( self.cl.dialogSet, sm.gui.getCurrentLanguage() )

	self.cl.dialogFeed = {}
	self.cl.completionRevision = 0

	self.cl.nameBar = nil
	self.cl.dialogTextBox = nil

	self.scriptableObject.clientPublicData = { dialogFeed = self.cl.dialogFeed, completionRevision = self.cl.completionRevision }

	self.cl.registeredSpeakers = {}
end

function DialogManager.Cl_RegisterSpeaker( speakerObject, speakerName )
	if g_dialogManagerSelf then
		g_dialogManagerSelf:cl_registerSpeaker( speakerObject, speakerName )
	end
end

function DialogManager.cl_registerSpeaker( self, speakerObject, speakerName )
	self.cl.registeredSpeakers[speakerName] = { speakerObject = speakerObject, world = GetWorld( speakerObject ) }

	-- Update the playing dialog if it uses this speaker name
	if self.cl.playingDialog and self.cl.playingDialog.speakerName == speakerName then
		self.cl.playingDialog.speakerObj = speakerObject
		if self.cl.playingDialog.requestedType == DialogType.Person then
			local newType = IsSpeakerOutOfRange( speakerObject ) and DialogType.Call or DialogType.Person
			if newType ~= self.cl.playingDialog.type then
				self.cl.playingDialog.pendingType = newType
			end
		end
	end
end

function DialogManager.cl_getSpeakerInfo( self, speakerName )
	return self.cl.registeredSpeakers[speakerName]
end

function DialogManager.client_onRefresh( self )
	LoadDialogSets( self.cl.dialogSet, sm.gui.getCurrentLanguage() )
end

--This need to be called on language change
function DialogManager.cl_reloadDialogs( self, language )
	self.cl.dialogSet = {}
	LoadDialogSets( self.cl.dialogSet, language )

	local line = self:cl_getCurrentLine()
	if line and line.text then
		self:cl_setDialogText( line.text )
	end
end

function DialogManager.Cl_OnLanguageChange( language )
	g_dialogManagerSelf:cl_reloadDialogs( language )
end













































































function DialogManager.Cl_PlayRecording( uuid, entryName, speakerName, caller )
	if g_dialogManagerSelf then
		g_dialogManagerSelf:cl_playRecording( uuid, entryName, speakerName, caller )
	end
end

function DialogManager.cl_playRecording( self, uuid, entryName, speakerName, caller )
	local data = { uuid = uuid, entryName = entryName, type = DialogType.Recording, speakerName = speakerName, caller = caller, priority = DialogPriority.Recording }
	if QuestManager.Cl_IsQuestRecording( uuid, entryName ) then
		sm.event.sendToScriptableObject( self.scriptableObject, "cl_e_requestRecordingStart", data )
		return
	end
	if self.cl.dialogQueue == nil or IsEmptyTable( self.cl.dialogQueue ) then
		self:cl_n_playDialog( data )
	end
end

function DialogManager.cl_e_requestRecordingStart( self, args )
	self.network:sendToServer( "sv_e_playDialog", args )
end

function DialogManager.cl_n_playDialog( self, args )
	if self.cl.playingDialog then
		if self.cl.playingDialog.priority <= args.priority then
			-- Current dialog has same or higher priority, queue the incoming one
			self.cl.dialogQueue[#self.cl.dialogQueue + 1] = args
			SortDialogQueue( self.cl.dialogQueue )
		else
			-- New dialog has higher priority, abort current and discard local queue
			if self.cl.jsonGui then
				self.cl.jsonGui:close()
			end
			if self.cl.playingDialog.caller and sm.exists( self.cl.playingDialog.caller ) then
				SendEvent( self.cl.playingDialog.caller, "cl_e_onDialogAbort" )
			end
			if self.cl.playingDialog.speakerObj and sm.exists( self.cl.playingDialog.speakerObj ) then
				SendEvent( self.cl.playingDialog.speakerObj, "cl_e_onDialogAbort" )
			end
			self.cl.playingDialog = nil
			self.cl.dialogQueue = { args }
			self.cl.completionRevision = self.cl.completionRevision + 1 -- Unclear why this is needed, leaving just in case.
			self.scriptableObject.clientPublicData.completionRevision = self.cl.completionRevision
		end
	else
		self.cl.dialogQueue[#self.cl.dialogQueue + 1] = args
	end
	if not self.cl.playingDialog then
        self:cl_nextDialog()
    end
end

-- Sets up the dialog GUI layout for the given type.
-- instantCall: if true, skips the call open animation and shows the caller holder immediately.
function DialogManager.cl_setupDialogTypeGui( self, dialogType, speakerName, uuid, entryName, instantCall )
	CallerDialogHolder.Visible = false
	AudioDialogHolder.Visible = false
	SubtitleDialogHolder.Visible = false
	SubtitleSmallDialogHolder.Visible = false

	if CallerOpenEffects then
		CallerOpenEffects.Visible = false
	end

	if dialogType == DialogType.Person then
		local target = SubtitleDialogHolder
		local targetDialogText = SubtitleDialogText
		local targetNameBarText = SubtitleNameBarText
		local comingDialog = SafeNestedAccess(self.cl.dialogSet, uuid, "entries", entryName, "lines")
		if comingDialog then
			if #comingDialog == 1 and comingDialog[1].text and #comingDialog[1].text < SmallDialogMaxLength then
				target = SubtitleSmallDialogHolder
				targetDialogText = SubtitleSmallDialogText
				targetNameBarText = SubtitleSmallNameBarText
			end
		end
		target.Visible = true
		self.cl.dialogTextBox = targetDialogText
		if targetNameBarText and speakerName then
			targetNameBarText.Caption = speakerName
		end
	elseif dialogType == DialogType.Call then
		if CallerEffectBox then
			CallerEffectBox.Effects[1].EffectName = IdleCallEffect
		end
		if CallerCloseEffectBox then
			CallerCloseEffectBox.Effects[1].EffectName = CloseCallEffect
		end
		if instantCall then
			CallerDialogHolder.Visible = true
			for i = 1, 4 do
				CallerDialogHolder.Childs[i].Visible = true
			end
		else
			if CallerOpenEffects then
				CallerOpenEffects.Visible = true
			end
			if CallerOpenEffectBox then
				CallerOpenEffectBox.Effects[1].EffectName = OpenCallEffect
			end
			CallerDialogHolder.Visible = true
			for i = 1, 4 do
				CallerDialogHolder.Childs[i].Visible = false
			end
		end
		if speakerName then
			if CallerBarText then
				CallerBarText.Caption = speakerName
			end
		end
		self.cl.dialogTextBox = CallerDialogText
	elseif dialogType == DialogType.Recording then
		AudioDialogHolder.Visible = true
		if speakerName then
			if AudioBarText then
				AudioBarText.Caption = speakerName
			end
		end
		self.cl.dialogTextBox = AudioDialogText
	end
end

function DialogManager.cl_startDialog( self, args )
	-- find out who is talking
	-- if no speakerName was passed from the call site, use name from the dialog set speaker field.
	if args.speakerName == nil and self.cl.dialogSet[args.uuid].speaker then
		args.speakerName = self.cl.dialogSet[args.uuid].speaker
	end

	-- Resolve the speaker object. Registered speaker has priority over speakerObject from args.
	local speakerInfo = self:cl_getSpeakerInfo( args.speakerName )
	local speakerObj, speakerType = ResolveSpeaker( speakerInfo, args.speakerObject )

	local requestedType = args.type

	-- find out if the dialog was started too far away and should convert to look like a call.
	local forceCall = args.type == DialogType.Person and IsSpeakerOutOfRange( speakerObj, args.audibleRange )
	if forceCall then
		if args.isShout then
			-- Shout dialogs that are too far away should not play at all, instead of playing as a call.
			self:cl_nextDialog()
			return
		end
		args.type = DialogType.Call
		args.quickCallEffect = true
	end

	self:cl_setupDialogTypeGui( args.type, args.speakerName, args.uuid, args.entryName, false )

	-- Create and render the gui.
	self.cl.jsonGui = sm.jsonGui.createGui( { isInteractive = false, bNeedsCursor = false, isHud = true, handleKeySetup = "Dialog" } )
	self.cl.jsonGui:render( GuiData )

	self.cl.playingDialog = {
		id = args.id,
		uuid = args.uuid,
		entryName = args.entryName,
		segment = 1,
		type = args.type,
		requestedType = requestedType,
		speakerName = args.speakerName,
		openDone = false,
		openTimer = 0,
		closeTimer = 0,
		shouldClose = false,
		closeDone = false,
		incomingCallDone = false,
		incomingCallCounter = 0,
		caller = args.caller,
		speakerObj = speakerObj,
		priority = args.priority,
		isShout = args.isShout,
		audibleRange = args.audibleRange,
		quickIncomingCall = args.quickCallEffect
	}

	local line = self:cl_getCurrentLine()
	if line then
		if speakerObj and sm.exists( speakerObj ) then
			SendEvent( speakerObj, "cl_e_onDialogLine", { animation = line.animation } )
		end
		if line.text then
			self:cl_setDialogText( line.text )
		end
		-- Audio effect doesn't exist yet; client_onUpdate will create it and start playback.
	end
end

function DialogManager.cl_n_updateDialogSpeaker( self, args )
	-- Update speaker in the dialog queue
	for _, dialog in ipairs( self.cl.dialogQueue ) do
		if dialog.id == args.id then
			dialog.speakerObject = args.speakerObject
			break
		end
	end
	-- Update the currently playing dialog's resolved speaker if it matches
	if self.cl.playingDialog and self.cl.playingDialog.id == args.id then
		self.cl.playingDialog.speakerObj = args.speakerObject

		-- Re-evaluate whether the dialog should be a call or person now that we have a speaker
		if self.cl.playingDialog.requestedType == DialogType.Person then
			local newType = IsSpeakerOutOfRange( args.speakerObject ) and DialogType.Call or DialogType.Person
			if newType ~= self.cl.playingDialog.type then
				self.cl.playingDialog.pendingType = newType
			end
		end
	end
end

function DialogManager.cl_applyTypeChange( self, newType )
	self.cl.playingDialog.type = newType

	self:cl_setupDialogTypeGui( newType, self.cl.playingDialog.speakerName, self.cl.playingDialog.uuid, self.cl.playingDialog.entryName, true )

	if newType == DialogType.Person then
		self.cl.playingDialog.shouldClose = false
	elseif newType == DialogType.Call then
		self.cl.playingDialog.incomingCallDone = true
		self.cl.playingDialog.openDone = true
		self.cl.playingDialog.shouldClose = false
		self.cl.playingDialog.closeDone = false
	end

	-- Force audio effect recreation on the next line with the correct type
	if self.cl.currentAudioEffect and sm.exists( self.cl.currentAudioEffect ) then
		self.cl.currentAudioEffect:stop()
		self.cl.currentAudioEffect:destroy()
	end
	self.cl.currentAudioEffect = nil
	self.cl.currentAudioEffectName = nil
	self.cl.audioHost = nil

	self.cl.jsonGui:render( GuiData )
end

function DialogManager.cl_n_playShoutDialog( self, args )
	-- Shout dialogs are low priority one-offs. Only play if nothing else is active and the queue is empty.
	args.isShout = true
	if self.cl.playingDialog == nil and IsEmptyTable( self.cl.dialogQueue ) then
		self:cl_n_playDialog( args )
	end
end

function DialogManager.Cl_IsRunning()
	return g_dialogManagerSelf.cl.playingDialog ~= nil
end

function DialogManager.client_onUpdate( self, dt )
	if self.cl.playingDialog then
		if self.cl.playingDialog.type == DialogType.Call then
			if not self.cl.playingDialog.incomingCallDone then
				if self.cl.playingDialog.incomingCallCounter == 0 then
					if IncomingCallHolder then
						IncomingCallHolder.Visible = true
					end
					if IncomingCallEffectBox then
						if not self.cl.playingDialog.quickIncomingCall then
							IncomingCallEffectBox.Effects[1].PlayState = "Auto playing"
						else
							IncomingCallEffectBox.Effects[2].PlayState = "Auto playing"
						end
					end
				end
				self.cl.playingDialog.incomingCallCounter = self.cl.playingDialog.incomingCallCounter + dt
				if self.cl.playingDialog.incomingCallCounter >= ( self.cl.playingDialog.quickIncomingCall and QuickIncomingCallDelaySeconds or IncomingCallDelaySeconds )then
					self.cl.playingDialog.incomingCallDone = true
					if IncomingCallHolder then
						if IncomingCallEffectBox then
							if not self.cl.playingDialog.quickIncomingCall then
								IncomingCallEffectBox.Effects[1].PlayState = "Stopped"
							else
								IncomingCallEffectBox.Effects[2].PlayState = "Stopped"
							end
						end
						IncomingCallHolder.Visible = false
					end
				end
				self.cl.jsonGui:render( GuiData )
				return
			end

			local shouldReturn = false
			if not self.cl.playingDialog.openDone then
				if self.cl.playingDialog.openTimer == 0 then
					if CallerOpenEffectBox then
						CallerOpenEffectBox.Effects[1].PlayState = "Auto playing"
						CallerOpenEffectBox.Effects[2].PlayState = "Auto playing"
					end
				end
				self.cl.playingDialog.openTimer = self.cl.playingDialog.openTimer + dt
				if self.cl.playingDialog.openTimer >= CallOpenDelaySeconds then
					if CallerOpenEffectBox then
						CallerOpenEffectBox.Effects[1].PlayState = "Stopped"
						CallerOpenEffectBox.Effects[2].PlayState = "Stopped"
					end
					self.cl.playingDialog.openDone = true
					for i = 1, 4 do
						CallerDialogHolder.Childs[i].Visible = true
					end
					if CallerOpenEffects then
						CallerOpenEffects.Visible = false
					end
				end
				shouldReturn = true
			end
			if self.cl.playingDialog.shouldClose then
				if self.cl.playingDialog.closeTimer == 0 then
					CallerCloseEffectBox.Effects[1].PlayState = "Auto playing"
					CallerCloseEffectBox.Effects[2].PlayState = "Auto playing"
					CallerCloseEffects.Visible = true
				end
				if self.cl.playingDialog.closeTimer >= 0.1 then
					for i = 1, 4 do
						CallerDialogHolder.Childs[i].Visible = false
					end
				end

				self.cl.playingDialog.closeTimer = self.cl.playingDialog.closeTimer + dt
				if self.cl.playingDialog.closeTimer >= CallCloseDelaySeconds then
					self.cl.playingDialog.shouldClose = false
					self.cl.playingDialog.closeDone = true
					if CallerCloseEffects then
						CallerCloseEffectBox.Effects[1].PlayState = "Stopped"
						CallerCloseEffectBox.Effects[2].PlayState = "Stopped"
						CallerCloseEffects.Visible = false
					end
				end
				shouldReturn = true
			end
			self.cl.jsonGui:render( GuiData )
			if shouldReturn then
				return
			end
		end

		if self.cl.playingDialog.type == DialogType.Recording then
			if not self.cl.playingDialog.openDone then
				if self.cl.playingDialog.openTimer == 0 then
					if AudioEffectBox then
						AudioEffectBox.Effects[1].PlayState = "Auto playing"
						AudioEffectBox.Effects[2].PlayState = "Stopped"
						self.cl.jsonGui:render( GuiData )
					end
				end
				self.cl.playingDialog.openTimer = self.cl.playingDialog.openTimer + dt
				if self.cl.playingDialog.openTimer >= AudioOpenDelaySeconds then
					self.cl.playingDialog.openDone = true
					if AudioEffectBox then
						AudioEffectBox.Effects[1].PlayState = "Stopped"
					end
					if AudioIdleEffectBox then
						AudioIdleEffectBox.Effects[1].PlayState = "Auto playing"
						AudioIdleEffectBox.Visible = true
					end
					self.cl.jsonGui:render( GuiData )
				end
			end
			if self.cl.playingDialog.shouldClose then
				if self.cl.playingDialog.closeTimer == 0 then
					if AudioEffectBox then
						AudioEffectBox.Effects[2].PlayState = "Auto playing"
					end
					if AudioIdleEffectBox then
						AudioIdleEffectBox.Visible = false
					end
					self.cl.jsonGui:render( GuiData )
				end
				self.cl.playingDialog.closeTimer = self.cl.playingDialog.closeTimer + dt
				if self.cl.playingDialog.closeTimer >= AudioCloseDelaySeconds then
					self.cl.playingDialog.shouldClose = false
					self.cl.playingDialog.closeDone = true
				end
			end
		end

		self.cl.currentTime = self.cl.currentTime + dt

		-- Continuously monitor distance to speaker and switch between Call/Person
		if (self.cl.playingDialog.requestedType == DialogType.Person or self.cl.playingDialog.requestedType == DialogType.Call) and self.cl.playingDialog.speakerObj then
			local monitorRange = self.cl.playingDialog.audibleRange or CallRange
			if self.cl.playingDialog.type == DialogType.Person then
				if IsSpeakerOutOfRange( self.cl.playingDialog.speakerObj, monitorRange + CallRangeDeadzone ) then
					self.cl.playingDialog.pendingType = DialogType.Call
				end
			elseif self.cl.playingDialog.type == DialogType.Call then
				if not IsSpeakerOutOfRange( self.cl.playingDialog.speakerObj, monitorRange - CallRangeDeadzone ) then
					self.cl.playingDialog.pendingType = DialogType.Person
				end
			end
		end

		local currentLine, lineCount = self:cl_getCurrentLine()

		if currentLine == nil then
			return
		end

		local speakerObj = self.cl.playingDialog.speakerObj
		local speakerType = speakerObj and type( speakerObj ) or nil

		-- Handle speaker object destruction
		if speakerObj and not sm.exists( speakerObj ) then
			self.cl.playingDialog.speakerObj = nil
			local speakerInfo = self:cl_getSpeakerInfo( self.cl.playingDialog.speakerName )
			if speakerInfo and speakerInfo.speakerObject == speakerObj then
				-- Registered speaker: defer switch to call until next line transition
				if self.cl.playingDialog.type == DialogType.Person then
					self.cl.playingDialog.pendingType = DialogType.Call
				end
			else
				-- No registered speaker: cancel the dialog
				self:cl_dialogEnd( currentLine, nil, true )
				return
			end
		end

		if not currentLine.key then
			if currentLine.endTime then
				if self.cl.currentTime >= currentLine.endTime then --next
					if lineCount > self.cl.playingDialog.segment then --set next text
						self:cl_nextLine( currentLine, speakerObj )
					else
						self:cl_dialogEnd( currentLine, speakerObj )
					end
				end
			end
		elseif currentLine.key then
			local audioEffect = self.cl.dialogSet[self.cl.playingDialog.uuid].entries[self.cl.playingDialog.entryName].audio
			audioEffect = GetAudioEffectForType( audioEffect, self.cl.playingDialog.type )
			if audioEffect and self.cl.currentAudioEffect == nil or self.cl.currentAudioEffectName ~= audioEffect then
				self.cl.currentAudioEffectName = audioEffect
				if self.cl.currentAudioEffect then
					self.cl.currentAudioEffect:stop()
					self.cl.currentAudioEffect:destroy()
				end
				self.cl.currentAudioEffect = sm.effect.createEffect( audioEffect )
				local worldSet = false
				if speakerObj and self.cl.playingDialog.type == DialogType.Person then
					if speakerType == "Character" then
						worldSet = true
						self.cl.currentAudioEffect:setWorld( speakerObj:getWorld() )
						self.cl.currentAudioEffect:setPosition( speakerObj.worldPosition )
						self.cl.currentAudioEffect:setHost( speakerObj )
						self.cl.currentAudioEffect:setDetachOnHostDestroy( true )
						self.cl.audioHost = speakerObj
					elseif speakerType == "Harvestable" then
						worldSet = true
						self.cl.currentAudioEffect:setWorld( speakerObj:getWorld() )
						self.cl.currentAudioEffect:setPosition( speakerObj.worldPosition )
						self.cl.currentAudioEffect:setHost( speakerObj )
						self.cl.currentAudioEffect:setDetachOnHostDestroy( true )
						self.cl.audioHost = speakerObj
					elseif speakerType == "Interactable" then
						if speakerObj.body then
							worldSet = true
							self.cl.currentAudioEffect:setWorld( speakerObj.body:getWorld() )
						end
						if speakerObj.shape then
							self.cl.currentAudioEffect:setPosition( speakerObj.shape.worldPosition )
							self.cl.currentAudioEffect:setHost( speakerObj.shape )
							self.cl.currentAudioEffect:setDetachOnHostDestroy( true )
							self.cl.audioHost = speakerObj.shape
						end
					end
				end
				if not worldSet then
					self.cl.currentAudioEffect:setWorldAny()
				end
				self.cl.currentAudioEffect:setParameter( "audioKey", currentLine.key )
				self.cl.currentAudioEffect:start()
			end
			if self.cl.audioHost and not sm.exists( self.cl.audioHost ) then
				self.cl.audioHost = nil
			end

			if not sm.exists( self.cl.currentAudioEffect ) or self.cl.currentAudioEffect:isDone() then
				if lineCount > self.cl.playingDialog.segment then
					self:cl_nextLine( currentLine, speakerObj )
				else
					self:cl_dialogEnd( currentLine, speakerObj )
				end
			end
		end
	end
end

function DialogManager.cl_nextLine( self, line, speakerObj )
	-- finished line callback
	self:activateCallback( line, self.cl.playingDialog.caller )
	-- go to next line
	self.cl.playingDialog.segment = self.cl.playingDialog.segment + 1

	-- Apply pending type change from speaker update
	if self.cl.playingDialog.pendingType then
		self:cl_applyTypeChange( self.cl.playingDialog.pendingType )
		self.cl.playingDialog.pendingType = nil
		speakerObj = self.cl.playingDialog.speakerObj
	end

	-- do next line animation, sound and text
	local currentLine = self:cl_getCurrentLine()
	if currentLine then
		if speakerObj and sm.exists( speakerObj ) then
			SendEvent( speakerObj, "cl_e_onDialogLine", { animation = currentLine.animation } )
		end
		if currentLine.text then
			self:cl_setDialogText( currentLine.text )
		end
		if currentLine.key and self.cl.currentAudioEffect then
			self.cl.currentAudioEffect:setParameter( "audioKey", currentLine.key )
			self.cl.currentAudioEffect:start()
		end
	end
end

function DialogManager.cl_dialogEnd( self, finalLine, speakerObj, cancel )
	if ( self.cl.playingDialog.type == DialogType.Call or self.cl.playingDialog.type == DialogType.Recording ) and not self.cl.playingDialog.closeDone then
		self.cl.playingDialog.shouldClose = true
		return
	end
	if self.cl.dialogueWindowOpen then
		self.cl.jsonGui:close()
		self.cl.jsonGui = nil
		self:cl_dialogFinished( self.cl.playingDialog.uuid, self.cl.playingDialog.entryName, speakerObj )
		self.cl.dialogueWindowOpen = false
	end
	if not cancel then
		self:activateCallback( finalLine, self.cl.playingDialog.caller )
	end

	if self.cl.currentAudioEffect and sm.exists( self.cl.currentAudioEffect ) then
		self.cl.currentAudioEffect:destroy()
		self.cl.currentAudioEffect = nil
		self.cl.audioHost = nil
	end

	if self.cl.playingDialog.caller and sm.exists( self.cl.playingDialog.caller ) then
		SendEvent( self.cl.playingDialog.caller, "cl_e_onDialogEnd" )
	end
	if speakerObj and speakerObj ~= self.cl.playingDialog.caller and sm.exists( speakerObj ) then
		SendEvent( speakerObj, "cl_e_onDialogEnd" )
	end
	self:cl_nextDialog()
end

function DialogManager.cl_dialogFinished( self, uuid, entryName, speakerObj )
	if sm.isHost then
		if self.cl.playingDialog and not self.cl.playingDialog.isShout then
			local dialogInfo = self.cl.dialogSet[tostring( uuid )]
			local hideInLogbook = dialogInfo and dialogInfo.hideInLogbook or false
			self.network:sendToServer( "sv_n_dialogFinished", { uuid = uuid, entryName = entryName, hideInLogbook = hideInLogbook } )
		end
	end
end

function DialogManager.activateCallback( self, currentDialog, caller )
	if sm.isHost then
		if currentDialog.callback ~= nil then
			if caller ~= nil and sm.exists( caller ) then
				SendEvent( caller, currentDialog.callback )
			end
		end
	end
end

function DialogManager.cl_nextDialog( self )
	if self.cl.playingDialog then
		self.cl.playingDialog = nil
	end
	self.cl.currentTime = 0
	local next = table.remove( self.cl.dialogQueue, 1 )
	if next then
		self:cl_startDialog( next )
	end
end

function DialogManager.cl_getCurrentLine( self )
	if not self.cl.playingDialog then
		return nil, 0
	end
	local segment = self.cl.playingDialog.segment
	local entryName = self.cl.playingDialog.entryName
	local uuid = self.cl.playingDialog.uuid
	local line = SafeNestedAccess( self.cl.dialogSet, uuid, "entries", entryName, "lines", segment )
	if not line then
		sm.log.warning( "Missing dialog translation for language: '", sm.gui.getCurrentLanguage(), "' with entry name: '", entryName, "', uuid: '", uuid, "'" )
		return { startTime = 0, endTime = 4, text = "Error: Could not find "..entryName.." ".. uuid }, 1
	end
	return line, #self.cl.dialogSet[uuid].entries[entryName].lines
end

function DialogManager.cl_setDialogText( self, text )
	if self.cl.dialogTextBox then
		self.cl.dialogTextBox.Caption = text
		self.cl.jsonGui:render( GuiData )
		self.cl.dialogueWindowOpen = true
	end
end