dofile( "$SURVIVAL_DATA/Scripts/game/SurvivalGame.lua")
dofile( "$SURVIVAL_DATA/Scripts/game/worlds/BaseWorld.lua")
dofile( "$SURVIVAL_DATA/Scripts/game/survival_units.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/survival_shapes.lua" )
dofile( "$SURVIVAL_DATA/Scripts/util.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/survival_constants.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/survival_loot.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/managers/WarehouseManager.lua" )

WarehouseWorld = class( BaseWorld )
WarehouseWorld.terrainScript = "$SURVIVAL_DATA/Scripts/terrain/terrain_warehouse.lua"
WarehouseWorld.enableSurface = false
WarehouseWorld.enableAssets = true
WarehouseWorld.enableClutter = false
WarehouseWorld.enableNodes = true
WarehouseWorld.enableCreations = true
WarehouseWorld.enableHarvestables = true
WarehouseWorld.enableKinematics = true
WarehouseWorld.enableBuildOnAssets = false
WarehouseWorld.renderMode = "warehouse"
WarehouseWorld.isIndoor = true
WarehouseWorld.worldBorder = false
WarehouseWorld.cellMinX = -4
WarehouseWorld.cellMaxX = 4
WarehouseWorld.cellMinY = -4
WarehouseWorld.cellMaxY = 4

local EntranceElevatorPosition = sm.vec3.new( 68, -3, 2.4 )

-- QUEST WAREHOUSE
local QuestWarehouseTileList = {
	[1] = { "$SURVIVAL_DATA/DungeonTiles/Warehouse_Interior_StorageFloor_Quest_01.tile"
	},
	[2] = { "$SURVIVAL_DATA/DungeonTiles/Warehouse_Interior_OfficeFloor_01.tile",
			"$SURVIVAL_DATA/DungeonTiles/Warehouse_Interior_OfficeFloor_02.tile",
			"$SURVIVAL_DATA/DungeonTiles/Warehouse_Interior_OfficeFloor_03.tile"
	},
	[3] = { "$SURVIVAL_DATA/DungeonTiles/Warehouse_Interior_ConstructionFloor_01.tile",
			"$SURVIVAL_DATA/DungeonTiles/Warehouse_Interior_ConstructionFloor_02.tile",
			"$SURVIVAL_DATA/DungeonTiles/Warehouse_Interior_ConstructionFloor_03.tile"
	},
	[4] = { "$SURVIVAL_DATA/DungeonTiles/Warehouse_Interior_TopFloor_Quest_01.tile"
	},
}

local WarehouseTileList = {
	[1] = { "$SURVIVAL_DATA/DungeonTiles/Warehouse_Interior_StorageFloor_01.tile",
			"$SURVIVAL_DATA/DungeonTiles/Warehouse_Interior_StorageFloor_02.tile",
			"$SURVIVAL_DATA/DungeonTiles/Warehouse_Interior_StorageFloor_03.tile",
			"$SURVIVAL_DATA/DungeonTiles/Warehouse_Interior_StorageFloor_04.tile",
			"$SURVIVAL_DATA/DungeonTiles/Warehouse_Interior_StorageFloor_05.tile"
	},
	[2] = { "$SURVIVAL_DATA/DungeonTiles/Warehouse_Interior_OfficeFloor_01.tile",
			"$SURVIVAL_DATA/DungeonTiles/Warehouse_Interior_OfficeFloor_02.tile",
			"$SURVIVAL_DATA/DungeonTiles/Warehouse_Interior_OfficeFloor_03.tile",
			"$SURVIVAL_DATA/DungeonTiles/Warehouse_Interior_DarkFloor_01.tile",
			"$SURVIVAL_DATA/DungeonTiles/Warehouse_Interior_DarkFloor_02.tile"
	},
	[3] = { "$SURVIVAL_DATA/DungeonTiles/Warehouse_Interior_ConstructionFloor_01.tile",
			"$SURVIVAL_DATA/DungeonTiles/Warehouse_Interior_ConstructionFloor_02.tile",
			"$SURVIVAL_DATA/DungeonTiles/Warehouse_Interior_ConstructionFloor_03.tile"
	},
	[4] = { "$SURVIVAL_DATA/DungeonTiles/Warehouse_Interior_TopFloor_01.tile",
			"$SURVIVAL_DATA/DungeonTiles/Warehouse_Interior_TopFloor_02.tile"
	},
}

local WarehouseLevelSelect = {
	[2] = { [1] = 1, [2] = 4 },
	[3] = { [1] = 1, [2] = 2, [3] = 4 },
	[4] = { [1] = 1, [2] = 2, [3] = 3, [4] = 4 },
}

local TapebotCount = 20
local TotebotCount = 20

function WarehouseWorld.server_onCreate( self )
	print( "WarehouseWorld - server create" )
	BaseWorld.server_onCreate( self )
	self.world.publicData.type = "WarehouseWorld"
	self.world.publicData.level = self.data.level














		assert(self.data.level ~= nil, "Created a warehouse world without a level!")
		assert(self.data.level > 0 and self.data.level <= #WarehouseTileList, "Created with warehouse world with invalid level parameter")
		assert(self.data.maxLevels > 1 and self.data.maxLevels <= #WarehouseTileList, "Created with warehouse world with invalid maxLevels parameter")

		local index = WarehouseLevelSelect[self.data.maxLevels][self.data.level]
		assert(index)
		local tileList = WarehouseTileList[index]
		if self.data.isQuestWarehouse then
			tileList = QuestWarehouseTileList[index]
		end
		assert(tileList and #tileList > 0)
		local tile = tileList[math.random( #tileList )]

		local renderSettings = "$GAME_DATA/Render/RenderSettings/World/world_warehouse_default.rendersettings"
		if string.find( tile, "DarkFloor" ) then
			renderSettings = "$GAME_DATA/Render/RenderSettings/World/world_warehouse_darkfloor.rendersettings"
		end

		self.data.tiles = {}
		table.insert( self.data.tiles, tile )
		self.data.creations = {}
		self.data.lightReductionChance = 30
		self.data.filterVoxelTrianglesFromNavMesh = true
		self.world:setTerrainScriptData( self.data )

		self:sv_createKillBox()
		self.network:setClientData( { maxLevels = self.data.maxLevels, level = self.data.level, renderSettings = renderSettings } )



end

function WarehouseWorld.client_onCreate( self )
	self.cl = {}
	BaseWorld.client_onCreate( self )
	print( "WarehouseWorld - client create" )
	print( self.data )

	if self.world.clientPublicData == nil then
		self.world.clientPublicData = {}
	end
	self.world.clientPublicData.ambience = "WarehouseAmbiance"
	self.world.clientPublicData.blockBed = true
	self.world.clientPublicData.musicParameter = self.data.level == self.data.maxLevels and 6 or 5 -- top floor = 6
end

function WarehouseWorld.sv_createKillBox( self )

	-- Filter
	local filter = sm.areaTrigger.filter.character + sm.areaTrigger.filter.dynamicBody

	-- Kill effect box
	local rotation = sm.quat.identity()

	-- Kill box -Z
	local halfSize = sm.vec3.new( 8192, 8192, 512.0 )
	local position = sm.vec3.new( 0.0, 0.0, -1024.0 )
	self.killAreaTriggerNZ = sm.areaTrigger.createBox( halfSize, position, rotation, filter )
	self.killAreaTriggerNZ:bindOnEnter( "trigger_onEnterKillBox" )

	-- Kill box +Z
	local halfSize = sm.vec3.new( 8192, 8192, 512.0 )
	local position = sm.vec3.new( 0.0, 0.0, 1024.0 )
	self.killAreaTriggerPZ = sm.areaTrigger.createBox( halfSize, position, rotation, filter )
	self.killAreaTriggerPZ:bindOnEnter( "trigger_onEnterKillBox" )

	-- Kill box +Y
	local halfSize = sm.vec3.new( 8192, 512.0, 8192 )
	local position = sm.vec3.new( 0.0, 1024.0, 0.0 )
	self.killAreaTriggerPY = sm.areaTrigger.createBox( halfSize, position, rotation, filter )
	self.killAreaTriggerPY:bindOnEnter( "trigger_onEnterKillBox" )

	-- Kill box -Y
	local halfSize = sm.vec3.new( 8192, 512.0, 8192 )
	local position = sm.vec3.new( 0.0, -1024.0, 0.0 )
	self.killAreaTriggerNY = sm.areaTrigger.createBox( halfSize, position, rotation, filter )
	self.killAreaTriggerNY:bindOnEnter( "trigger_onEnterKillBox" )

	-- Kill box +X
	local halfSize = sm.vec3.new( 512.0, 8192, 8192 )
	local position = sm.vec3.new( 1024.0, 0.0, 0.0 )
	self.killAreaTriggerPX = sm.areaTrigger.createBox( halfSize, position, rotation, filter )
	self.killAreaTriggerPX:bindOnEnter( "trigger_onEnterKillBox" )

	-- Kill box -X
	local halfSize = sm.vec3.new( 512.0, 8192, 8192 )
	local position = sm.vec3.new( -1024.0, 0.0, 0.0 )
	self.killAreaTriggerNX = sm.areaTrigger.createBox( halfSize, position, rotation, filter )
	self.killAreaTriggerNX:bindOnEnter( "trigger_onEnterKillBox" )
end

function WarehouseWorld.trigger_onEnterKillBox( self, trigger, results )
	-- New objects in the kill box
	for _,result in ipairs( results ) do
		if sm.exists( result ) then
			-- Respawn character
			if type( result ) == "Character" then
				if result:isPlayer() then
					result:setWorldPosition( EntranceElevatorPosition )
				else
					result:getUnit():destroy()
				end
			end
			--Destroy shapes
			if type( result ) == "Body" then
				for _, shape in ipairs( result:getShapes() ) do
					sm.shape.destroyShape( shape )
				end
			end
		end
	end

end

function WarehouseWorld.server_onCellCreated( self, x, y )
	BaseWorld.server_onCellCreated( self, x, y )

	ElevatorManager.Sv_LoadElevatorsOnWarehouseCell( x, y, self.data.warehouseIndex, self.data.level )

	-- Warehouse reward chest
	local chests = sm.cell.getInteractablesByUuid( x, y, obj_container_smallchest )
	for _,chest in ipairs( chests ) do
		local container = chest:getContainer()
		local lootList = SelectLoot( "lootsource_rewardchest_warehouse", 20 )
		sm.container.beginTransaction()
		for i,loot in ipairs( lootList ) do
			sm.container.setItem( container, i - 1, loot.uuid, loot.quantity )
		end
		sm.container.endTransaction()
	end

	-- Warehouse file cabinet
	local filecabinets = sm.cell.getInteractablesByUuid( x, y, obj_interactive_filecabinet )
	for _, filecabinet in ipairs( filecabinets ) do
		local container = filecabinet:getContainer()
		local lootList = SelectLoot( "lootsource_filecabinet_warehouse", 3 )
		sm.container.beginTransaction()
		for i, loot in ipairs( lootList ) do
			sm.container.setItem( container, i - 1, loot.uuid, loot.quantity )
		end
		sm.container.endTransaction()
	end

	-- Warehouse locker
	local lockers = sm.cell.getInteractablesByUuid( x, y, obj_interactive_locker )
	for _, locker in ipairs( lockers ) do
		local container = locker:getContainer()
		local lootList = SelectLoot( "lootsource_locker_warehouse", 4 )
		sm.container.beginTransaction()
		for i, loot in ipairs( lootList ) do
			sm.container.setItem( container, i - 1, loot.uuid, loot.quantity )
		end
		sm.container.endTransaction()
	end

	-- Create units from tapebot nodes
	local tapebots = sm.cell.getNodesByTag( x, y, "TAPEBOT" )

	local redTapebotCount = self.data.level == self.data.maxLevels and 5 or 0
	assert( redTapebotCount <= TapebotCount )
	tapebots = shuffle( tapebots )
	for idx, tapebot in ipairs( tapebots ) do
		if idx <= TapebotCount then
			local spawnDirection = tapebot.rotation * sm.vec3.new( 0, 0, 1 )
			local yaw = math.atan2( spawnDirection.y, spawnDirection.x ) - math.pi/2
			local params = { tetherPoint = tapebot.position, lootType = "warehouse" }
			if tapebot.params then
				append( params, tapebot.params )
			end

			if idx <= redTapebotCount then
				sm.unit.createUnit( unit_tapebot_red, tapebot.position, yaw, params )
			else
				sm.unit.createUnit( g_tapebots[math.random( 1, #g_tapebots )], tapebot.position, yaw, params )
			end
		end
	end

	-- Create totebots
	local totebots = sm.cell.getNodesByTag( x, y, "TOTEBOT_GREEN" )
	totebots = shuffle( totebots )
	for idx, totebot in ipairs( totebots ) do
		if idx <= TotebotCount then
			local spawnDirection = totebot.rotation * sm.vec3.new( 0, 0, 1 )
			local yaw = math.atan2( spawnDirection.y, spawnDirection.x ) - math.pi/2
			local params = { tetherPoint = totebot.position, lootType = "warehouse" }
			if totebot.params then
				append( params, totebot.params )
			end
			sm.unit.createUnit( unit_totebot_green, totebot.position, yaw, params )
		end
	end

	-- Tell the level encryptors which warehouse they're part of
	local setParamsOnEncryptors = function( uuid )
		local encryptors = sm.cell.getInteractablesByUuid( x, y, uuid )
		for _, e in ipairs( encryptors ) do
			print( "WarehouseWorld: " .. tostring( uuid ) .. " found!" )
			local params = {
				warehouseIndex = self.data.warehouseIndex,
			}
			e:setParams( params )
		end
	end
	setParamsOnEncryptors( obj_interactive_encryptor_destruction )
	setParamsOnEncryptors( obj_interactive_encryptor_connection )
end

function WarehouseWorld.server_onCellLoaded( self, x, y )
	BaseWorld.server_onCellLoaded( self, x, y )

	if x == 0 and y == 0 then
		WarehouseManager.Sv_TryUpdateDestructionState( self.data.warehouseIndex, self.world )
	end
end

function WarehouseWorld.client_onClientDataUpdate( self, params )
	if self.world.clientPublicData == nil then
		self.world.clientPublicData = {}
	end
	if self.world.clientPublicData.defaultRenderSetting == nil then
		self.world.clientPublicData.defaultRenderSetting = params.renderSettings
		RenderSettingsManager.Cl_RefreshCurrentWorldSettings( self.world )
	end
end
