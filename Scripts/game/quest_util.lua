
dofile( "$CUSTOMIZATION_DATA/Scripts/game/quest_reward_util.lua" )

function FindInventoryChange( changes, uidItem )
	for _, change in ipairs( changes ) do
		if change.uuid == uidItem then
			return change.difference
		end
	end
	return 0
end

function GrantSchematics( questName )
	local rewardList = QuestManager.Sv_GetQuestRewards( questName ) or {}
	Sv_GrantSchematics( rewardList )
end

function GrantLogs( questName )
	local rewardList = QuestManager.Sv_GetQuestRewards( questName ) or {}
	Sv_GrantLogs( rewardList )
end

function GetRewardDelay( questName )
	local rewardList = QuestManager.Sv_GetQuestRewards( questName ) or {}
	local delay = 5
	for _,reward in ipairs( rewardList ) do
		if reward.type == "log" then
			-- Skip delay padding for logs that were already granted earlier in the quest.
			if not LogEntryManager.Sv_HasLog( tostring( reward.uuid ) ) then
				delay = delay + 4
			end
		end
		if reward.type == "schematic" then
			-- Skip delay padding for schematics already unlocked.
			if not RecipeManager.Sv_IsUnlocked( tostring( ITEMS[reward.name] ) ) then
				delay = delay + 4
			end
		end
	end
	return delay
end

function CompleteQuest( questName, nextQuest, hidden, additionaldelay )
	QuestManager.Sv_CompleteQuest( questName )
	GrantSchematics( questName )
	GrantLogs( questName )

	local rewardList = QuestManager.Sv_GetQuestRewards( questName )
	sm.event.sendToGame( "sv_e_grantAdditionalRewards", rewardList )

	if nextQuest  then
		local delay = GetRewardDelay( questName ) + ( additionaldelay or 0 )
		sm.scriptableObject.createScriptableObject( sm.uuid.new( "d9458830-7899-4dd5-aae9-703cf9d46782" ), { questName = nextQuest, tickDelay = math.floor( delay * 40 ), hidden = hidden } )
	end
end

function CompleteAndActivateQuestThroughDialog( questName, nextQuest, dialogData, additionalWaitTime )
	QuestManager.Sv_CompleteQuest( questName )
	GrantSchematics( questName )
	GrantLogs( questName )
	local additionalTime = additionalWaitTime or 0





	local params = {
		dialogUuid = dialogData.dialogUuid,
		dialogEntry = dialogData.dialogEntry,
		dialogType = dialogData.dialogType,
		dialogSpeaker = dialogData.dialogSpeaker,
		questName = nextQuest,
		prerequisiteQuestEvent  = dialogData.prerequisiteQuestEvent,
		prerequisiteTimeoutTicks = dialogData.prerequisiteTimeoutTicks,
		tickDelay = math.floor( ( GetRewardDelay( questName ) + additionalTime ) * 40 ),
	}
	sm.scriptableObject.createScriptableObject( sm.uuid.new( "9dde94ad-6524-4e1d-9024-1210c0ab659d" ), params )
end

function CompleteAndActivateQuestThroughDialogBeat( questName, nextQuest, beatName, additionalWaitTime, options )
	local beatData = dialog_beats_lookup[beatName]
	assert( beatData, "CompleteAndActivateQuestThroughDialogBeat: unknown beat '" .. tostring( beatName ) .. "'" )
	local dialogData = {
		dialogUuid = beatData.dialog,
		dialogEntry = beatData.entry,
		dialogType = beatData.type,
		dialogSpeaker = DialogSpeakerName[beatData.speaker],
		prerequisiteQuestEvent = options and options.prerequisiteQuestEvent or nil,
		prerequisiteTimeoutTicks = options and options.prerequisiteTimeoutTicks or nil,
	}
	CompleteAndActivateQuestThroughDialog( questName, nextQuest, dialogData, additionalWaitTime )
end

-- Spawn a DialogQuestActivator that plays the given dialog beat after `tickDelay` ticks.
-- Use this when a follow-up character call should happen after a previous dialog and/or quest reward
-- popup has had time to display. The activator destroys itself once the beat completes.
function PlayDialogBeatDelayed( beatName, tickDelay )
	local beatData = dialog_beats_lookup[beatName]
	assert( beatData, "PlayDialogBeatDelayed: unknown beat '" .. tostring( beatName ) .. "'" )
	return sm.scriptableObject.createScriptableObject( sm.uuid.new( "9dde94ad-6524-4e1d-9024-1210c0ab659d" ), {
		dialogUuid = beatData.dialog,
		dialogEntry = beatData.entry,
		dialogType = beatData.type,
		dialogSpeaker = DialogSpeakerName[beatData.speaker],
		tickDelay = tickDelay or 0,
	} )
end

function ActivateQuestThroughDialogBeat( questName, beatName, tickDelay )
	local beatData = dialog_beats_lookup[beatName]
	sm.scriptableObject.createScriptableObject( sm.uuid.new( "9dde94ad-6524-4e1d-9024-1210c0ab659d" ), {
		dialogUuid = beatData.dialog,
		dialogEntry = beatData.entry,
		dialogType = beatData.type,
		dialogSpeaker = DialogSpeakerName[beatData.speaker],
		tickDelay = tickDelay or 0,
		questName = questName,
	} )
end

function Cl_GetProgressText( stage, progressSteps )
	local text = ""
	for _,stepData in ipairs( progressSteps ) do
		if stepData.steps then
			if isAnyOf( stage, stepData.steps ) then
				text = stepData.text
				break
			end
		end
	end
	return text
end

function Sv_GetBuilderguideNodeName( questName )
	return QuestManager.Sv_GetBuilderguideNodeName( questName )
end

function Sv_SetPublicDataStage( self, stage )
	local publicData = self.scriptableObject.publicData
	if not publicData then
		publicData = {}
	end
	publicData.stage = stage
	self.scriptableObject:setPublicData( publicData )
end

function FormatQuestDisplayNumbers( number1, number2 )
	return "#FFFFC0"..FormatThousandSeparator( number1 ).."/"..FormatThousandSeparator( number2 ).."#FFFFFF "
end

-- Wait-for-effect helpers
-- Shared boilerplate for the 1-second delay used by quests when transitioning stages
-- (lets a UI/audio effect play before updating the quest tracker or finishing the quest).

local DefaultWaitTickTime = 40

-- Spawn a DelayedScriptableActivation that fires `finishEvent` after `tickDelay` ticks (default 40 = 1s).
-- Use at a quest's final stage to delay completion so the last checkmark's flash effect can play
function FinishQuestAfterDelay( finishEvent, tickDelay )
	return sm.scriptableObject.createScriptableObject( sm.uuid.new( "d9458830-7899-4dd5-aae9-703cf9d46782" ), {
		questEvent = finishEvent,
		tickDelay = tickDelay or DefaultWaitTickTime,
	} )
end

function FormatTrackingData( trackingData, stage, waitForEffect )
	local returnData = { trackerData = {}, completedData = {} }
	local completedData = {}
	local stepReduction = waitForEffect and 1 or 0
	for name, data in pairs( trackingData ) do
		local highestStep = 0
		for _,step in ipairs( data.steps ) do
			if step > highestStep then
				highestStep = step
			end
			if ( stage - stepReduction ) == step then
				returnData.trackerData[#returnData.trackerData+1] = { name = name, index = data.index }
				local text = data.text
				if data.count1 and data.count2 then
					text = FormatQuestDisplayNumbers( data.count1, data.count2 )..text
					returnData.trackerData[#returnData.trackerData].complete = data.count1 >= data.count2
				elseif data.complete ~= nil then
					returnData.trackerData[#returnData.trackerData].complete = data.complete
				end
				returnData.trackerData[#returnData.trackerData].text = text
			end
		end
		if highestStep < stage then
			completedData[#completedData+1] = { text = data.textEffect, index = data.index }
		end
	end

	local function ascendingSort( a, b )
		return a.index < b.index
	end
	table.sort( completedData, ascendingSort )
	for _, data in ipairs( completedData ) do
		returnData.completedData[#returnData.completedData+1] = data.text
	end
	table.sort( returnData.trackerData, ascendingSort )
	return returnData
end

-- True if two trackerData arrays have the same steps and completion state.
local function TrackerDataEquivalent( a, b )
	if #a ~= #b then
		return false
	end
	for i = 1, #a do
		if a[i].name ~= b[i].name or ( a[i].complete or false ) ~= ( b[i].complete or false ) then
			return false
		end
	end
	return true
end

-- Sets clientPublicData from trackingData. Pass prevStage to flash the most recently completed
-- objective on a forward advance before showing the next step (omit it to skip the flash).
function ApplyTrackingProgress( self, trackingData, stage, prevStage )
	local steady = FormatTrackingData( trackingData, stage, false )
	steady.stage = stage

	if prevStage and stage > prevStage then
		local flash = FormatTrackingData( trackingData, stage, true )
		if #flash.trackerData > 0 and not TrackerDataEquivalent( flash.trackerData, steady.trackerData ) then
			steady.flashTrackerData = flash.trackerData
		end
	end

	self.scriptableObject.clientPublicData = steady
end