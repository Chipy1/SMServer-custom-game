dofile( "$SURVIVAL_DATA/Scripts/game/survival_constants.lua" )

WarehouseManager = class( nil )
WarehouseManager.isSaveObject = false

local WarehouseDestructionUuid = sm.uuid.new( "4a825c08-cd87-4a15-9bc5-ffec9fdb4b9d" )
local WarehouseDestructionPaintLight = sm.uuid.new( "2e689944-180d-4a1a-8e2d-35b162938792" )
local WarehouseDestructionFlag = "warehouse_destruction"
local WarehouseConsoleDestroyedFlag = "warehouse.consoledestroyed"

--[[ Server ]]
function WarehouseManager.server_onCreate( self )
	assert( g_warehouseManager == nil )
	g_warehouseManager = self
	self.sv = {}
	self.sv.warehouses = sm.storage.load( STORAGE_CHANNEL_WAREHOUSES )
	if self.sv.warehouses == nil then
		self.sv.warehouses = {}
		sm.storage.save( STORAGE_CHANNEL_WAREHOUSES, self.sv.warehouses )
	end

	self.network:setClientData( { warehouses = self.sv.warehouses }, 2 )
	self.sv.synchToClients = false

	if g_beaconManager then
		g_beaconManager:sv_clearStaleWarehouseBeacons()
	end
end

function WarehouseManager.server_onFixedUpdate( self, dt )
	-- Synch client data
	if self.sv.synchToClients then
		self.network:setClientData( { warehouses = self.sv.warehouses }, 2 )
		self.sv.synchToClients = false
	end
end

function WarehouseManager.Sv_ConsoleDestroyed( warehouseIndex )
	if g_warehouseManager then
		g_warehouseManager:sv_consoleDestroyed( warehouseIndex )
	end
end

function WarehouseManager.sv_consoleDestroyed( self, warehouseIndex )
	local warehouse = self.sv.warehouses[warehouseIndex]
	warehouse.consoleDestroyed = true
	self:sv_saveAndSynch()

	for _, world in ipairs( warehouse.worlds ) do
		self:sv_tryUpdateDestructionState( warehouseIndex, world )
	end
end

function WarehouseManager.Sv_BeginCountdown( warehouseIndex, countdownTicks )
	if g_warehouseManager then
		g_warehouseManager:sv_beginCountdown( warehouseIndex, countdownTicks )
	end
end

function WarehouseManager.sv_beginCountdown( self, warehouseIndex, countdownTicks )
	local warehouse = self.sv.warehouses[warehouseIndex]
	if warehouse then
		if sm.exists( warehouse.countdownEvent ) then
			warehouse.countdownEvent:destroy()
		end
		local params = { warehouseIndex = warehouseIndex }
		if countdownTicks then
			params.countdownTicks = countdownTicks
		end
		warehouse.countdownEvent = sm.scriptableObject.createScriptableObject( WarehouseDestructionUuid, params )
		self:sv_saveAndSynch()
		
		QuestManager.Sv_SendEvent( QuestEvent.WarehouseDestructionStarted, { warehouseIndex = warehouse.index } )
		
		for _, world in ipairs( warehouse.worlds ) do
			self:sv_tryUpdateDestructionState( warehouseIndex, world )
		end
	end
end

function WarehouseManager.Sv_TryUpdateDestructionState( warehouseIndex, world )
	if g_warehouseManager then
		g_warehouseManager:sv_tryUpdateDestructionState( warehouseIndex, world )
	end
end

function WarehouseManager.sv_tryUpdateDestructionState( self, warehouseIndex, world )
	local needSave = false
	local warehouse = self.sv.warehouses[warehouseIndex]
	if warehouse and sm.exists( world ) then
		local tileStorageKey = TileStorageManager.Sv_GetTileStorageKeyFromCell( world, 0, 0 )
		if warehouse.consoleDestroyed then
			if not TileStorageManager.Sv_SyncedGetValueInSubTable( tileStorageKey, TILESTORAGE_FLAGS_TABLE, WarehouseConsoleDestroyedFlag ) then
				SetTileStorageFlag( tileStorageKey, WarehouseConsoleDestroyedFlag )
				EffectManager.Sv_UpdateTagFilteredEffectsForCell( world, 0, 0, { WarehouseConsoleDestroyedFlag } )
			end
		end

		if warehouse.countdownEvent then
			TileStorageManager.Sv_SetValueInSubTable( tileStorageKey, KEY_LOCK_TABLE, WarehouseDestructionFlag, true )
			if world:isCellLoadedServer( 0, 0 ) then
				warehouse.worldRestrictionsLifted = warehouse.worldRestrictionsLifted or {}
				if not warehouse.worldRestrictionsLifted[world.id] then
					local bodies = sm.body.getAllBodies( world )
					for _, body in ipairs( bodies ) do
						if body.destructable then -- Skip unrestricting bodies which are indestructable ie. elevator body and elevator doors
							body.buildable = true
							body.paintable = true
							body.connectable = true
							body.liftable = true
							body.erasable = true
							body.usable = true
						end
	
						local paintLights = body:getShapesByUuid( WarehouseDestructionPaintLight )
						for _, paintLight in ipairs( paintLights ) do
							paintLight:setColor( ALERT_COLOR_OVERRIDE )
						end
					end
					if not IsEmptyTable( bodies ) then
						warehouse.worldRestrictionsLifted[world.id] = true
						needSave = true
					end
				end
		
				warehouse.worldAlertLightingOn = warehouse.worldAlertLightingOn or {}
				if not warehouse.worldAlertLightingOn[world.id] then
					world:setLightColorOverride( ALERT_COLOR_OVERRIDE )
					warehouse.worldAlertLightingOn[world.id] = true
					needSave = true
				end
			end
		end
	end
	if needSave then
		self:sv_saveAndSynch()
	end
end

function WarehouseManager.Sv_DestroyWarehouse( warehouseIndex )
	if g_warehouseManager then
		g_warehouseManager:sv_destroyWarehouse( warehouseIndex )
	end
end

function WarehouseManager.sv_destroyWarehouse( self, warehouseIndex )
	local warehouse = self.sv.warehouses[warehouseIndex]
	if not warehouse or warehouse.destroyed then return end

	QuestManager.Sv_SendEvent( QuestEvent.WarehouseDestruction, { warehouseIndex = warehouseIndex } )

	warehouse.destroyed = true
	for _, player in ipairs( sm.player.getAllPlayers() ) do
		local playerCharacter = player and player.character or nil
		local playerWorld = sm.exists( playerCharacter ) and playerCharacter:getWorld() or nil
		if playerWorld then
			for _, warehouseWorld in ipairs( warehouse.worlds ) do
				if playerWorld == warehouseWorld then
					-- Teleport players outside
					sm.event.sendToPlayer( player, "sv_e_warehouseEject", { warehouseIndex = warehouseIndex } )
				end
			end
		end
	end

	self:sv_saveAndSynch()
end

function WarehouseManager.Sv_SaveAndSynch()
	if g_warehouseManager then
		g_warehouseManager:sv_saveAndSynch()
	end
end

function WarehouseManager.sv_saveAndSynch( self )
	sm.storage.save( STORAGE_CHANNEL_WAREHOUSES, self.sv.warehouses )
	self.sv.synchToClients = true
end

function WarehouseManager.Sv_GetWarehouseFromIndex( warehouseIndex )
	if g_warehouseManager then
		return g_warehouseManager:sv_getWarehouseFromIndex( warehouseIndex )
	end
	return nil
end

function WarehouseManager.sv_getWarehouseFromIndex( self, warehouseIndex )
	return self.sv.warehouses[warehouseIndex]
end

function WarehouseManager.Sv_GetWarehouseFromWorld( warehouseWorld )
	if g_warehouseManager then
		return g_warehouseManager:sv_getWarehouseFromWorld( warehouseWorld )
	end
	return nil
end

function WarehouseManager.sv_getWarehouseFromWorld( self, warehouseWorld )
	for _, warehouse in ipairs( self.sv.warehouses ) do
		for _, world in ipairs( warehouse.worlds ) do
			if warehouseWorld == world then
				return warehouse
			end
		end
	end
	return nil
end

function WarehouseManager.Sv_GetWarehouseIndexFromWorld( warehouseWorld )
	if g_warehouseManager then
		return g_warehouseManager:sv_getWarehouseIndexFromWorld( warehouseWorld )
	end
	return nil
end

function WarehouseManager.sv_getWarehouseIndexFromWorld( self, warehouseWorld )
	for index, warehouse in ipairs( self.sv.warehouses ) do
		for _, world in ipairs( warehouse.worlds ) do
			if warehouseWorld == world then
				return index
			end
		end
	end
	return nil
end

function WarehouseManager.Sv_FindWarehouseAtPosition( world, position )
	if g_warehouseManager then
		return g_warehouseManager:sv_findWarehouseAtPosition( world, position )
	end
	return nil
end

function WarehouseManager.sv_findWarehouseAtPosition( self, world, position )
	local tileStorageKey = TileStorageManager.Sv_GetTileStorageKeyFromPosition( world, position )
	if tileStorageKey == nil then
		return nil
	end
	for _, warehouse in ipairs( self.sv.warehouses ) do
		if not warehouse.destroyed and warehouse.tileStorageKey == tileStorageKey then
			return warehouse
		end
	end
	return nil
end

function WarehouseManager.Sv_CreateWarehouse( params )
	if g_warehouseManager then
		return g_warehouseManager:sv_createWarehouse( params )
	end
	return nil
end

function WarehouseManager.sv_createWarehouse( self, params )
	-- Return existing warehouse if one already exists at this position
	local existing = self:sv_findWarehouseAtPosition( params.world, params.position )
	if existing then
		return existing
	end

	local warehouse = {}
	warehouse.tileStorageKey = TileStorageManager.Sv_GetTileStorageKeyFromPosition( params.world, params.position )
	warehouse.test = params.test
	warehouse.isQuestWarehouse = isAnyOf( "WAREHOUSE4QUEST", params.cellTags )
	warehouse.world = params.world
	warehouse.worlds = {}
	warehouse.worldRestrictionsLifted = {}
	warehouse.worldAlertLightingOn = {}
	warehouse.exits = params.exits
	warehouse.maxLevels = params.maxLevels
	warehouse.index = #self.sv.warehouses + 1
	local cellX = math.floor( params.position.x / 64 )
	local cellY = math.floor( params.position.y / 64 )
	local x0, y0 = GetTileZeroCell( cellX, cellY, params.world.id )
	if x0 then
		warehouse.zeroCell = { x = x0, y = y0 }
		local xMin, xMax, yMin, yMax = GetTileRangesFromCell( x0, y0, params.world.id )
		if xMin then
			warehouse.tileRange = { xMin = xMin, xMax = xMax, yMin = yMin, yMax = yMax }
		end
	end
	self.sv.warehouses[warehouse.index] = warehouse
	self:sv_saveAndSynch()
	return warehouse
end

--[[ Client ]]
function WarehouseManager.client_onCreate( self )
	assert( g_warehouseManagerClient == nil )
	g_warehouseManagerClient = self
	self.cl = {}
	self.cl.warehouses = {}
end

function WarehouseManager.client_onClientDataUpdate( self, data, channel )
	self.cl = self.cl or {}
	if channel == 2 then
		self.cl.warehouses = data.warehouses
	end
end

function WarehouseManager.Cl_GetWarehouseFromIndex( warehouseIndex )
	if g_warehouseManagerClient then
		return g_warehouseManagerClient:cl_getWarehouseFromIndex( warehouseIndex )
	end
	return nil
end

function WarehouseManager.cl_getWarehouseFromIndex( self, warehouseIndex )
	return self.cl.warehouses[warehouseIndex]
end

function WarehouseManager.Cl_GetWarehouseFromWorld( warehouseWorld )
	if g_warehouseManagerClient then
		return g_warehouseManagerClient:cl_getWarehouseFromWorld( warehouseWorld )
	end
	return nil
end

function WarehouseManager.cl_getWarehouseFromWorld( self, warehouseWorld )
	for _, warehouse in ipairs( self.cl.warehouses ) do
		for _, world in ipairs( warehouse.worlds ) do
			if warehouseWorld == world then
				return warehouse
			end
		end
	end
	return nil
end

function WarehouseManager.Cl_EnterElevatorFromWarehouse( world )
	if g_warehouseManagerClient then
		return g_warehouseManagerClient:cl_enterElevatorFromWarehouse( world )
	end
end

function WarehouseManager.cl_enterElevatorFromWarehouse( self, world )
	for _, warehouse in ipairs( self.cl.warehouses ) do
		for _, warehouseWorld in ipairs( warehouse.worlds ) do
			if warehouseWorld == world then
				if self.cl.lockBorder then
					self.cl.lockBorder:destroy()
					self.cl.lockBorder = nil
				end
				return
			end
		end
	end
end

function WarehouseManager.Cl_EnterWarehouseFromElevator( world )
	if g_warehouseManagerClient then
		return g_warehouseManagerClient:cl_enterWarehouseFromElevator( world )
	end
end

function WarehouseManager.cl_enterWarehouseFromElevator( self, world )
	for _, warehouse in ipairs( self.cl.warehouses ) do
		for _, warehouseWorld in ipairs( warehouse.worlds ) do
			if warehouseWorld == world then
				if not self.cl.lockBorder and warehouse.countdownEvent == nil then
					self.cl.lockBorder = HudManager.Cl_CreateBorder( HudManager.Priority.WarehouseBarrier, HudManager.BorderType.WarehouseLock )
				end
				return
			end
		end
	end
end

function WarehouseManager.client_onUpdate( self )
	local player = sm.localPlayer.getPlayer()
	if player then
		local character = player:getCharacter()
		if character then
			local world = character:getWorld()
			if world then
				for _, warehouse in ipairs( self.cl.warehouses ) do
					for _, warehouseWorld in ipairs( warehouse.worlds ) do
						if warehouseWorld == world then
							if self.cl.lockBorder then
								self.cl.lockBorder:update( warehouse.consoleDestroyed == nil )
							end
							return
						end
					end
				end
			end
		end
	end
end

function WarehouseManager.client_onLocalPlayerChangedWorld( self, world )
	for warehouseIndex, warehouse in ipairs( self.cl.warehouses ) do
		for _, warehouseWorld in ipairs( warehouse.worlds ) do
			if warehouseWorld.id == world.id then
				if warehouse.destroyed then
					self.network:sendToServer( "sv_n_requestEject", { warehouseIndex = warehouseIndex }  )
				end

				if self.cl.lastWorld == nil then
					--loaded into warehouse without visiting another world first, activate the hud border now.
					--otherwise rely on exiting an elevator to activate the hud.
					if not self.cl.lockBorder and warehouse.countdownEvent == nil then
						self.cl.lockBorder = HudManager.Cl_CreateBorder( HudManager.Priority.WarehouseBarrier, HudManager.BorderType.WarehouseLock )
					end
				end
				self.cl.lastWorld = world
				return
			end
		end
	end

	-- not warehouse world
	if self.cl.lockBorder then
		self.cl.lockBorder:destroy()
		self.cl.lockBorder = nil
	end
	self.cl.lastWorld = world
end

function WarehouseManager.sv_n_requestEject( self, params, player )
	sm.event.sendToPlayer( player, "sv_e_warehouseEject", { warehouseIndex = params.warehouseIndex } )
end