dofile( "$SURVIVAL_DATA/Scripts/game/managers/QuestManager.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/quest_util.lua" )

TraderTrackingQuest = class()
TraderTrackingQuest.isSaveObject = true

local EffectTickDelay = 120
local PingTickTime = 40

local ResourceToTierAndLog = {
	[tostring( ITEMS.obj_crates_carrot )] = { tier = 2, log = LOGS.log_growlab_01 },
	[tostring( ITEMS.obj_crates_redbeet )] = { tier = 3, log = LOGS.log_growlab_02 },
	[tostring( ITEMS.obj_crates_banana )] = {  tier = 4, log = LOGS.log_growlab_03 },
	[tostring( ITEMS.obj_crates_blueberry )] = { tier = 5, log = LOGS.log_growlab_04 },
	[tostring( ITEMS.obj_crates_orange )] = {  tier = 6, log = LOGS.log_growlab_05 },
	[tostring( ITEMS.obj_crates_broccoli )] = { tier = 7, log = LOGS.log_growlab_06 },
	[tostring( ITEMS.obj_crates_pineapple )] = { tier = 8, log = LOGS.log_growlab_07 },
}

function TraderTrackingQuest.server_onCreate( self )
	self.sv = {}
	self.sv.tradeData = sm.storage.load( STORAGE_CHANNEL_TRADER_INFORMATION ) or {}
	self.sv.saved = self.storage:load()
	if self.sv.saved == nil then
		self.sv.saved = {}
		self.storage:save( self.sv.saved )
	end
	QuestManager.Sv_SubscribeEvent( QuestEvent.TraderProgressTrade, self.scriptableObject, "sv_e_tradeEvent" )
	QuestManager.Sv_SubscribeEvent( QuestEvent.DeliverTraderCrate, self.scriptableObject, "sv_e_tradeEvent" )
	QuestManager.Sv_SubscribeEvent( QuestEvent.GrowlabCompleted, self.scriptableObject, "sv_e_growlabEvent" )
	QuestManager.Sv_SubscribeEvent( QuestEvent.LogUnlocked, self.scriptableObject, "sv_e_growlabEvent" )
	self.sv.waitForEffect = false
	self.sv.tickDelayCounter = 0
	self:sv_sync()
end

function TraderTrackingQuest.sv_sync( self )
	local currentTier = ProgressionManager.Sv_GetSeedTier()
	self.network:setClientData( { tradeData = self.sv.tradeData.tradeInfo, currentItems = self.sv.tradeData.currentItems, currentTier = currentTier } )
end

function TraderTrackingQuest.server_onFixedUpdate( self )
	if self.sv.waitForEffect then
		self.sv.tickDelayCounter = self.sv.tickDelayCounter + 1
		if self.sv.tickDelayCounter >= EffectTickDelay then
			self.sv.waitForEffect = false
			self.sv.tickDelayCounter = 0
			self.sv.tradeData = sm.storage.load( STORAGE_CHANNEL_TRADER_INFORMATION ) or {}
			self:sv_sync()
		end
	end
end

function TraderTrackingQuest.sv_e_tradeEvent( self, data )
	local tradeData = sm.storage.load( STORAGE_CHANNEL_TRADER_INFORMATION ) or {}
	self.sv.waitForPing = false
	if data.event == QuestEvent.TraderProgressTrade and ( tradeData.tradeInfo.currentStep % tradeData.tradeInfo.currentGroup.steps ) == 0 then
		self.sv.waitForEffect = true
		self.sv.tradeData.tradeInfo.currentStep = self.sv.tradeData.tradeInfo.currentGroup.steps
	else
		self.sv.tradeData = tradeData
	end
	self:sv_sync()
end

function TraderTrackingQuest.sv_e_growlabEvent( self, data )
	data.currentTier = ProgressionManager.Sv_GetSeedTier()
	self.network:sendToClients( "cl_n_progressGrowlabTracking", data )
end

function TraderTrackingQuest.client_onCreate( self )
	QuestManager.Cl_OnQuestCreated( "quest_trader_tracking" )
	self.cl = {}
	self.cl.waitForPing = false
	self.cl.currentTier = 1
	self.scriptableObject.clientPublicData = {}
	self.scriptableObject.clientPublicData.progressString = ""
	self.scriptableObject.clientPublicData.farmerQuest = true
	self.cl.effectTickCounter = 0
end

function TraderTrackingQuest.client_onFixedUpdate( self )
	if self.cl.waitForPing then
		self.cl.effectTickCounter = self.cl.effectTickCounter + 1
		if self.cl.effectTickCounter >= PingTickTime then
			self.cl.waitForPing = false
			self.cl.effectTickCounter = 0
			self:cl_updateProgress( self.cl.tradeData, self.cl.currentItems )
			QuestManager.Cl_UpdateQuestTracker()
		end
	end
end

function TraderTrackingQuest.cl_n_progressGrowlabTracking( self, data )
	self.cl.currentTier = data.currentTier
	if self.scriptableObject.clientPublicData and self.scriptableObject.clientPublicData.trackerData then
		local targetResource = tostring( self.scriptableObject.clientPublicData.resource )
		local currentResourceData = ResourceToTierAndLog[targetResource]
		self.cl.waitForPing = true
		if self.scriptableObject.clientPublicData.trackerData then
			for i = 1, #self.scriptableObject.clientPublicData.trackerData do
				if data.event == QuestEvent.GrowlabCompleted and self.scriptableObject.clientPublicData.trackerData[i].name == "growlab" then
					self.scriptableObject.clientPublicData.trackerData[i].complete = true
				elseif data.event == QuestEvent.LogUnlocked and self.scriptableObject.clientPublicData.trackerData[i].name == "key" and tostring( currentResourceData.log ) == data.params.uuid then
					self.scriptableObject.clientPublicData.trackerData[i].complete = true
				end
			end
		end
		QuestManager.Cl_UpdateQuestTracker()
	end
end

function TraderTrackingQuest.client_onDestroy( self )
    self:cl_e_onUntracked()
end

local function GetCurrentReward( tradeData )
	local fromStep = tradeData.currentStep + 1
	local reward = nil
	for _, rewardInfo in ipairs( tradeData.currentGroup.rewards ) do
		if rewardInfo.step >= fromStep and ( reward == nil or rewardInfo.step < reward.step ) then
			reward = rewardInfo
		end
	end
	if reward and not ( reward.giveItem or reward.unlockCraftBot or reward.unlockCosmetic ) then
		sm.log.warning( "TraderTrackingQuest: reward selected for display does not grant an item, schematic or cosmetic. Reorder the tradegroup so a displayable reward is first for this step.  Step:", reward.step )
	end
	return reward
end

function TraderTrackingQuest.client_onClientDataUpdate( self, data )
	if data.tradeData == nil or IsEmptyTable( data.tradeData ) then
		return
	end
	self.cl.currentTier = data.currentTier
	self.cl.tradeData = data.tradeData
	self.cl.currentItems = data.currentItems
	self.cl.waitForPing = data.waitForPing
	self.cl.isQuest = data.tradeData.currentGroup.isQuest
	self.scriptableObject.clientPublicData.resource = data.tradeData.currentGroup.resource
	self.scriptableObject.clientPublicData.reward = GetCurrentReward( data.tradeData ) or self.scriptableObject.clientPublicData.reward
	self:cl_updateProgress( data.tradeData, data.currentItems )
	QuestManager.Cl_UpdateQuestTracker()
end

function TraderTrackingQuest.cl_updateProgress( self, tradeData, currentItems )
	local targetResource = tostring( tradeData.currentGroup.resource )
	local amount = 0
	if currentItems then
		for uid,quantity in pairs( currentItems ) do
			if uid == targetResource then
				amount = quantity
			end
		end
	end
	local deliveryAmount = math.min( tradeData.currentGroup.steps, amount + tradeData.currentStep )
	local currentResourceData = ResourceToTierAndLog[targetResource]

	self.scriptableObject.clientPublicData.trackerData = {}
	if self.cl.isQuest and currentResourceData then
		if targetResource == tostring( ITEMS.obj_crates_tomato ) then
			self.scriptableObject.clientPublicData.trackerData[#self.scriptableObject.clientPublicData.trackerData+1] = { name = "desc", text = self.data.trackingSteps.tomatoes }
		elseif targetResource == tostring( ITEMS.obj_crates_carrot ) then
			self.scriptableObject.clientPublicData.trackerData[#self.scriptableObject.clientPublicData.trackerData+1] = { name = "desc", text = self.data.trackingSteps.carrots }
		elseif currentResourceData and self.cl.currentTier < currentResourceData.tier then



		self.scriptableObject.clientPublicData.trackerData[#self.scriptableObject.clientPublicData.trackerData+1] = { name = "desc", text = self.data.trackingSteps.seeds_desc }
		if not LogEntryManager.Cl_HasLog( currentResourceData.log ) then
			self.scriptableObject.clientPublicData.trackerData[#self.scriptableObject.clientPublicData.trackerData+1] = { name = "key", text = self.data.trackingSteps.key, complete = false }
		else
			self.scriptableObject.clientPublicData.trackerData[#self.scriptableObject.clientPublicData.trackerData+1] = { name = "growlab", text = self.data.trackingSteps.growlab, complete = false }
		end
		return



		end
	end

	if IsEmptyTable( self.scriptableObject.clientPublicData.trackerData ) then
		self.scriptableObject.clientPublicData.trackerData[#self.scriptableObject.clientPublicData.trackerData+1] = { name = "desc", text = self.data.trackingSteps.finish_desc }
	end

	self.scriptableObject.clientPublicData.trackerData[#self.scriptableObject.clientPublicData.trackerData+1] = { name = "deliveries", text = FormatQuestDisplayNumbers( deliveryAmount, tradeData.currentGroup.steps )..self.data.trackingSteps.deliveries, complete = deliveryAmount >= tradeData.currentGroup.steps }
	self.scriptableObject.clientPublicData.trackerData[#self.scriptableObject.clientPublicData.trackerData+1] = { name = "deposits", text = FormatQuestDisplayNumbers( tradeData.currentStep, tradeData.currentGroup.steps )..self.data.trackingSteps.deposits, complete = tradeData.currentStep >= tradeData.currentGroup.steps }
end

function TraderTrackingQuest.cl_e_onTracked( self )
	self.cl.tracked = true
end

function TraderTrackingQuest.cl_e_onUntracked( self )
	self.cl.tracked = false
end