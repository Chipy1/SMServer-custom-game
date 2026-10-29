dofile( "$SURVIVAL_DATA/Scripts/game/survival_constants.lua" )

WaypointQuestUnitManager = class( nil )

local UnitCheckTickInterval = 200
local UnitRequestCooldownTicks = 40

--[[ Server ]]
function WaypointQuestUnitManager.server_onCreate( self )
	assert( g_waypointQuestUnitManager == nil )
	g_waypointQuestUnitManager = self
	self.sv = {}
	self.sv.saved = sm.storage.load( STORAGE_CHANNEL_WAYPOINTQUESTUNIT_MANAGER )
	if self.sv.saved == nil then
		self.sv.saved = {}
		self.sv.saved.waypointQuestUnits = {}
		self.sv.saved.waypointQuestUnitIdCounter = 1
		sm.storage.save( STORAGE_CHANNEL_WAYPOINTQUESTUNIT_MANAGER, self.sv.saved )
	end
	self.sv.unitIdToWaypointQuestUnitId = {}
	for waypointQuestUnitId, data in pairs( self.sv.saved.waypointQuestUnits ) do
		self.sv.unitIdToWaypointQuestUnitId[data.unit.id] = waypointQuestUnitId
	end
	self.sv.lastUnitCheckTick = sm.game.getCurrentTick()
	self.sv.missingWaypointQuestUnits = {}
	self.sv.unitLastPosition = {}
end

function WaypointQuestUnitManager.server_onRefresh( self, dt )
	if self.sv.unitLastPosition == nil then
		self.sv.unitLastPosition = {}
	end
end

function WaypointQuestUnitManager.server_onFixedUpdate( self, dt )
	local currentTick = sm.game.getCurrentTick()
	if currentTick >= self.sv.lastUnitCheckTick + UnitCheckTickInterval then
		self.sv.lastUnitCheckTick = currentTick
		for waypointQuestUnitId, data in pairs( self.sv.saved.waypointQuestUnits ) do
			local allowedToAutoSpawn = true
			if data.pendingUnitRequestTick then
				allowedToAutoSpawn = currentTick >= data.pendingUnitRequestTick + UnitRequestCooldownTicks
				if allowedToAutoSpawn then
					data.pendingUnitRequestTick = nil
				end
			end

			if sm.exists( data.unit ) then
				local waypointCharacter = data.unit.character
				if sm.exists( waypointCharacter ) then
					self.sv.unitLastPosition[waypointQuestUnitId] = { worldPosition = waypointCharacter.worldPosition, world = waypointCharacter:getWorld() }
				end
				self.sv.missingWaypointQuestUnits[waypointQuestUnitId] = nil
			elseif allowedToAutoSpawn then
				if self.sv.missingWaypointQuestUnits[waypointQuestUnitId] then
					local quest = data.quest
					local fnRespawn = function( position, world )
						if position and world then
							local cellX = math.floor( position.x / 64 )
							local cellY = math.floor( position.y / 64 )
							if world:isCellLoadedServer( cellX, cellY ) then
								local spawnParams = {
									uuid = data.uuid,
									position = position,
									amount = 1,
									customParams = { quest = quest, respawnWaypointQuestUnitId = waypointQuestUnitId }
								}
								sm.event.sendToWorld( world, "sv_e_spawnUnit", spawnParams )
								data.pendingUnitRequestTick = currentTick
								self:sv_destroyWaypointQuestUnit( data )
								return true
							end
						end
						return false
					end
					if quest and quest.publicData and quest.publicData.waypointObject and quest.publicData.waypointObject[waypointQuestUnitId] then
						local waypointObject = quest.publicData.waypointObject[waypointQuestUnitId]
						fnRespawn( waypointObject.position, waypointObject.world )
					else
						-- Fallback to the unit's last known position
						local last = self.sv.unitLastPosition[waypointQuestUnitId]
						if last then
							fnRespawn( last.worldPosition, last.world )
						end
					end
				else
					self.sv.missingWaypointQuestUnits[waypointQuestUnitId] = true
				end
			end
		end
	end
end

function WaypointQuestUnitManager.sv_save( self )
	sm.storage.save( STORAGE_CHANNEL_WAYPOINTQUESTUNIT_MANAGER, self.sv.saved )
end

function WaypointQuestUnitManager.Sv_AddWaypointQuestUnit( unit, quest )
	if g_waypointQuestUnitManager then
		return g_waypointQuestUnitManager:sv_addWaypointQuestUnit( unit, quest )
	end
	return nil
end

function WaypointQuestUnitManager.sv_addWaypointQuestUnit( self, unit, quest )
	local newWaypointQuestUnit = {
		uuid = unit.character:getCharacterType(),
		unit = unit,
		quest = quest,
		pendingUnitRequestTick = nil
	}
	local existingWaypointQuestUnitId = self.sv.unitIdToWaypointQuestUnitId[unit.id]
	if existingWaypointQuestUnitId then
		-- Update
		self.sv.saved.waypointQuestUnits[existingWaypointQuestUnitId] = newWaypointQuestUnit
		self:sv_save()
		return existingWaypointQuestUnitId
	else
		-- New
		self.sv.saved.waypointQuestUnits[self.sv.saved.waypointQuestUnitIdCounter] = newWaypointQuestUnit
		local waypointQuestUnitId = self.sv.saved.waypointQuestUnitIdCounter
		self.sv.unitIdToWaypointQuestUnitId[unit.id] = waypointQuestUnitId
		self.sv.saved.waypointQuestUnitIdCounter = self.sv.saved.waypointQuestUnitIdCounter + 1
		self:sv_save()
		return waypointQuestUnitId
	end
end

function WaypointQuestUnitManager.Sv_RemoveWaypointQuestUnit( waypointQuestUnitIdOrUnit )
	if g_waypointQuestUnitManager then
		if type( waypointQuestUnitIdOrUnit ) == "Unit" then
			return g_waypointQuestUnitManager:sv_removeWaypointQuestUnitByUnit( waypointQuestUnitIdOrUnit )
		elseif type( waypointQuestUnitIdOrUnit ) == "number" then
			return g_waypointQuestUnitManager:sv_removeWaypointQuestUnitById( waypointQuestUnitIdOrUnit )
		end
	end
end

function WaypointQuestUnitManager.sv_removeWaypointQuestUnitById( self, waypointQuestUnitId )
	local data = self.sv.saved.waypointQuestUnits[waypointQuestUnitId]
	if data then
		self.sv.unitIdToWaypointQuestUnitId[data.unit.id] = nil
	end
	self.sv.saved.waypointQuestUnits[waypointQuestUnitId] = nil
	self.sv.missingWaypointQuestUnits[waypointQuestUnitId] = nil
	self.sv.unitLastPosition[waypointQuestUnitId] = nil
	self:sv_save()
end

function WaypointQuestUnitManager.sv_removeWaypointQuestUnitByUnit( self, unit )
	local waypointQuestUnitId = self.sv.unitIdToWaypointQuestUnitId[unit.id]
	if waypointQuestUnitId then
		self.sv.saved.waypointQuestUnits[waypointQuestUnitId] = nil
	end
	self.sv.unitIdToWaypointQuestUnitId[unit.id] = nil
	if waypointQuestUnitId then
		self.sv.missingWaypointQuestUnits[waypointQuestUnitId] = nil
		self.sv.unitLastPosition[waypointQuestUnitId] = nil
	end
	self:sv_save()
end

function WaypointQuestUnitManager.Sv_GetWaypointQuestUnit( waypointQuestUnitIdOrUnit )
	if g_waypointQuestUnitManager then
		if type( waypointQuestUnitIdOrUnit ) == "Unit" then
			return g_waypointQuestUnitManager:sv_getByUnit( waypointQuestUnitIdOrUnit )
		elseif type( waypointQuestUnitIdOrUnit ) == "number" then
			return g_waypointQuestUnitManager:sv_getById( waypointQuestUnitIdOrUnit )
		end
	end
	return nil
end

function WaypointQuestUnitManager.sv_getById( self, waypointQuestUnitId )
	return self.sv.saved.waypointQuestUnits[waypointQuestUnitId]
end

function WaypointQuestUnitManager.sv_getByUnit( self, unit )
	local waypointQuestUnitId = self.sv.unitIdToWaypointQuestUnitId[unit.id]
	return self.sv.saved.waypointQuestUnits[waypointQuestUnitId]
end

function WaypointQuestUnitManager.Sv_GetWaypointQuestUnitIdByUnit( unit )
	if g_waypointQuestUnitManager then
		return g_waypointQuestUnitManager.sv.unitIdToWaypointQuestUnitId[unit.id]
	end
	return nil
end

function WaypointQuestUnitManager.Sv_OnRespawnWithWaypointQuestUnitId( unit, waypointQuestUnitId )
	if g_waypointQuestUnitManager then
		g_waypointQuestUnitManager:sv_onRespawnWithWaypointQuestUnitId( unit, waypointQuestUnitId )
	end
end

function WaypointQuestUnitManager.sv_onRespawnWithWaypointQuestUnitId( self, unit, waypointQuestUnitId )
	local data = self.sv.saved.waypointQuestUnits[waypointQuestUnitId]
	if data then
		data.unit = unit
		self.sv.unitIdToWaypointQuestUnitId[unit.id] = waypointQuestUnitId
		self.sv.missingWaypointQuestUnits[waypointQuestUnitId] = nil
		self:sv_save()
	end
end

function WaypointQuestUnitManager.sv_destroyWaypointQuestUnit( self, data )
	self.sv.unitIdToWaypointQuestUnitId[data.unit.id] = nil
	sm.unit.forceDestroy( data.unit )
	data.unit = nil
end