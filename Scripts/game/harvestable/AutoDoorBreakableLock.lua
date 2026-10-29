dofile( "$SURVIVAL_DATA/Scripts/terrain/overworld/poi_types.lua" )

AutoDoorBreakableLock = class( nil )
AutoDoorBreakableLock.poseWeightCount = 1
local BreakBlendDuration = 0.1

function AutoDoorBreakableLock.server_onCreate( self )
    self.sv = {}
    self.sv.saved = self.storage:load()
	self.sv.storageKey = TileStorageManager.Sv_GetTileStorageKeyFromObject( self.harvestable )
	self.sv.growlabEntrancePoiType = nil
	local worldPubData = self.harvestable:getWorld().publicData
	if worldPubData and worldPubData.poiType then
		self.sv.growlabEntrancePoiType = worldPubData.poiType
	end
	self.harvestable.publicData = { drillLevel = 1 }

    if self.sv.saved == nil then
        self.sv.saved = {}
        self.sv.saved.isBroken = false
		self.sv.saved.keyTag = self.params.keyTag
		self.sv.saved.eventTrigger = self.params.eventTrigger
		self.storage:save( self.sv.saved )
    end
	if self.sv.saved.eventTrigger == "enddoor" then -- Patch code for 1.0.6 that changes onboarding breakable lock to use keyTag instead of eventTrigger
		if worldPubData and worldPubData.type == "UndergroundWorld" and worldPubData.depth == 2 then
			self.sv.saved.keyTag = "enddoor"
		end
	end
	if self.sv.saved.isBroken then
		self.network:setClientData( { isBroken = self.sv.saved.isBroken, blendFinished = true } )

		if self.sv.saved.keyTag and self.sv.saved.keyTag ~= "" then
			TileStorageManager.Sv_SetValueInSubTable( self.sv.storageKey, KEY_LOCK_TABLE, self.sv.saved.keyTag, true )
		end
	else
		if g_questPinManagerServer and self.sv.growlabEntrancePoiType == POI_MEADOW_GROWLAB_QUEST_LARGE then
			QuestPinManager.Sv_AddPin( self.harvestable, self.harvestable:getWorld(), "SmashPin", sm.vec3.new( 0, 0, 1.2 ) )
		end
	end
end

function AutoDoorBreakableLock.server_onMelee( self, hitPos, attacker, damage, power, hitDirection )
    if type( attacker ) == "Player" and self.sv.saved.isBroken == false then
		self:sv_onHit()
    end
end

function AutoDoorBreakableLock.sv_onHit( self )
	if self.sv.saved.keyTag ~= "" then
		if g_tileStorageManager then
			TileStorageManager.Sv_SetValueInSubTable( self.sv.storageKey, KEY_LOCK_TABLE, self.sv.saved.keyTag, true )
			local brokenLockCount = TileStorageManager.Sv_GetValueInSubTable( self.sv.storageKey, KEY_LOCK_COUNTER_TABLE, self.sv.saved.keyTag )
			if brokenLockCount == nil then
				brokenLockCount = 1
			else
				brokenLockCount = brokenLockCount + 1
			end
			SetKeyLockCounterValue( self.sv.storageKey, self.sv.saved.keyTag, brokenLockCount )
		end
	end
	if g_questPinManagerServer and self.sv.growlabEntrancePoiType == POI_MEADOW_GROWLAB_QUEST_LARGE then
		QuestPinManager.Sv_RemovePin( self.harvestable.id, type( self.harvestable ) )
	end
	self.sv.saved.isBroken = true
	self.storage:save( self.sv.saved )
	if self.sv.saved.eventTrigger ~= "" then
		KinematicManager.Sv_Activate( self.sv.storageKey, self.sv.saved.eventTrigger )
	end
	self.network:setClientData( { isBroken = self.sv.saved.isBroken, blendFinished = false } )
end

function AutoDoorBreakableLock.sv_e_plasmaDrill( self, params )
	if self.sv.saved.isBroken == false then
		self:sv_onHit()
	end
end

function AutoDoorBreakableLock.client_onCreate( self )
	self.cl = {}
	self.cl.blendCounter = 0
	self.cl.blendFinished = false
	self.cl.isBroken = false
	self.cl.shimmerEffect = sm.effect.createEffect( "Growlab - Powerbreaker_idleglow", self.harvestable )
	self.cl.shimmerEffect:start()
end

function AutoDoorBreakableLock.client_onDestroy( self )
	self.cl.shimmerEffect:destroy()
end

function AutoDoorBreakableLock.client_onClientDataUpdate( self, data )
	self.cl.isBroken = data.isBroken
	self.cl.blendFinished = data.blendFinished
	if self.cl.blendFinished then
		self.cl.shimmerEffect:stopImmediate()
		self.harvestable:setPoseWeight( 0, 1 )
		self.harvestable:setSubMeshVisible( "glassbulb_broken", true )
		self.harvestable:setSubMeshVisible( "glassbulb", false )
	end
end

function AutoDoorBreakableLock.client_onUpdate( self, dt )
	if not self.cl.blendFinished and self.cl.isBroken then
		self.cl.blendCounter = clamp( self.cl.blendCounter + dt, 0.0, BreakBlendDuration )
		self.harvestable:setPoseWeight( 0, self.cl.blendCounter / BreakBlendDuration )
		if self.cl.blendCounter >= BreakBlendDuration then
			self.cl.blendFinished = true
			sm.effect.playEffect( "Growlab - Powerbreakerdestruct", self.harvestable.worldPosition, sm.vec3.zero(), self.harvestable.worldRotation )
			self.cl.shimmerEffect:stopImmediate()
			self.harvestable:setSubMeshVisible( "glassbulb_broken", true )
			self.harvestable:setSubMeshVisible( "glassbulb", false )
		end
	end
end


