dofile( "$SURVIVAL_DATA/Scripts/util.lua" )
dofile( "$SURVIVAL_DATA/Scripts/terrain/terrain_util2.lua" )
dofile( "$SURVIVAL_DATA/Scripts/kinematic_util.lua")
dofile "$SURVIVAL_DATA/Scripts/terrain/tile_database.lua"

dofile "$GAME_DATA/Scripts/terrain/terrain_prepare_cell_util.lua"

local CombatLegsSetup = {
	center = "c_run01",
	leftIn = "l_run_in",
	left = "l_run01",
	leftOut = "l_run_out",
	rightIn = "r_run_in",
	right = "r_run01",
	rightOut = "r_run_out"
}

local CombatBodySetup = {
	center = "c_run01",
	leftIn = "l_run_in",
	left = "l_run01",
	leftOut = "l_run_out",
	rightIn = "r_run_in",
	right = "r_run01",
	rightOut = "r_run_out"
}

local CombatTrackPrefabs = {
	{ prefabPath = "$SURVIVAL_DATA/LocalPrefabs/EffectPrefabs/Lavatrack/lavatrack_combat_a_01.prefab", legsAnimation = CombatLegsSetup, bodyAnimation = CombatBodySetup }		--[[6]]
}



local EnterTrackPrefabs = {
	{ prefabPath = "$SURVIVAL_DATA/LocalPrefabs/EffectPrefabs/Lavatrack/lavatrack_enter_a_01.prefab", legsAnimation = { center = "enter_wall_left" }, bodyAnimation = { center = "enter_wall_left" } },		--[[1]]
	{ prefabPath = "$SURVIVAL_DATA/LocalPrefabs/EffectPrefabs/Lavatrack/lavatrack_enter_a_02.prefab", legsAnimation = { center = "enter_wall_right" }, bodyAnimation = { center = "enter_wall_right" } },	--[[2]]
	{ prefabPath = "$SURVIVAL_DATA/LocalPrefabs/EffectPrefabs/Lavatrack/lavatrack_enter_a_03.prefab", legsAnimation = { center = "enter_floor" }, bodyAnimation = { center = "enter_floor" } },				--[[3]]
	{ prefabPath = "$SURVIVAL_DATA/LocalPrefabs/EffectPrefabs/Lavatrack/lavatrack_enter_a_04.prefab", legsAnimation = { center = "enter_ceiling" }, bodyAnimation = { center = "enter_ceiling" } },			--[[4]]
	{ prefabPath = "$SURVIVAL_DATA/LocalPrefabs/EffectPrefabs/Lavatrack/lavatrack_enter_a_06.prefab", legsAnimation = { center = "enter_destructcinematic"}, bodyAnimation = { center = "enter_destructcinematic" } },									--[5]
}

local IntroTrackPrefabs = {
	{ prefabPath = "$SURVIVAL_DATA/LocalPrefabs/EffectPrefabs/Lavatrack/lavatrack_enter_a_05.prefab", legsAnimation = { center = "enter_start" }, bodyAnimation = { center = "enter_start" } },		--[[1]]
	{ prefabPath = "$SURVIVAL_DATA/LocalPrefabs/EffectPrefabs/Lavatrack/lavatrack_enter_a_04.prefab", legsAnimation = { center = "c_run01" }, bodyAnimation = { center = "c_run01" } },				--[[2]]
}

local RollercoasterTrackPrefabs = {
	{ prefabPath = "$SURVIVAL_DATA/LocalPrefabs/EffectPrefabs/Lavatrack/lavatrack_rollercoaster_a_start.prefab", legsAnimation = {}, bodyAnimation = {} },			--[[1]]
	{ prefabPath = "$SURVIVAL_DATA/LocalPrefabs/EffectPrefabs/Lavatrack/lavatrack_rollercoaster_a_01.prefab", legsAnimation = {}, bodyAnimation = {} },			--[[2]]
	{ prefabPath = "$SURVIVAL_DATA/LocalPrefabs/EffectPrefabs/Lavatrack/lavatrack_rollercoaster_a_02.prefab", legsAnimation = {}, bodyAnimation = {} },			--[[3]]
	{ prefabPath = "$SURVIVAL_DATA/LocalPrefabs/EffectPrefabs/Lavatrack/lavatrack_rollercoaster_a_03.prefab", legsAnimation = {}, bodyAnimation = {} },			--[[4]]
	{ prefabPath = "$SURVIVAL_DATA/LocalPrefabs/EffectPrefabs/Lavatrack/lavatrack_rollercoaster_a_04.prefab", legsAnimation = {}, bodyAnimation = {} },			--[[5]]
	{ prefabPath = "$SURVIVAL_DATA/LocalPrefabs/EffectPrefabs/Lavatrack/lavatrack_rollercoaster_a_05.prefab", legsAnimation = {}, bodyAnimation = {} },			--[[6]]
	{ prefabPath = "$SURVIVAL_DATA/LocalPrefabs/EffectPrefabs/Lavatrack/lavatrack_rollercoaster_a_06.prefab", legsAnimation = {}, bodyAnimation = {} },			--[[7]]
	{ prefabPath = "$SURVIVAL_DATA/LocalPrefabs/EffectPrefabs/Lavatrack/lavatrack_rollercoaster_a_07.prefab", legsAnimation = {}, bodyAnimation = {} },			--[[8]]
	{ prefabPath = "$SURVIVAL_DATA/LocalPrefabs/EffectPrefabs/Lavatrack/lavatrack_rollercoaster_a_08.prefab", legsAnimation = {}, bodyAnimation = {} },			--[[9]]
	{ prefabPath = "$SURVIVAL_DATA/LocalPrefabs/EffectPrefabs/Lavatrack/lavatrack_rollercoaster_a_end.prefab", legsAnimation = {}, bodyAnimation = {} },			--[[10]]
	{ prefabPath = "$SURVIVAL_DATA/LocalPrefabs/EffectPrefabs/Lavatrack/lavatrack_rollercoaster_b_01.prefab", legsAnimation = {}, bodyAnimation = {} },			--[[11]]
	{ prefabPath = "$SURVIVAL_DATA/LocalPrefabs/EffectPrefabs/Lavatrack/lavatrack_rollercoaster_b_02.prefab", legsAnimation = {}, bodyAnimation = {} },			--[[12]]
	{ prefabPath = "$SURVIVAL_DATA/LocalPrefabs/EffectPrefabs/Lavatrack/lavatrack_rollercoaster_b_03.prefab", legsAnimation = {}, bodyAnimation = {} },			--[[13]]
	{ prefabPath = "$SURVIVAL_DATA/LocalPrefabs/EffectPrefabs/Lavatrack/lavatrack_rollercoaster_b_04.prefab", legsAnimation = {}, bodyAnimation = {} },			--[[14]]
	{ prefabPath = "$SURVIVAL_DATA/LocalPrefabs/EffectPrefabs/Lavatrack/lavatrack_rollercoaster_c_01.prefab", legsAnimation = {}, bodyAnimation = {} },			--[[15]]
	{ prefabPath = "$SURVIVAL_DATA/LocalPrefabs/EffectPrefabs/Lavatrack/lavatrack_rollercoaster_c_02.prefab", legsAnimation = {}, bodyAnimation = {} },			--[[16]]
}

local DownTrackPrefabs = {
	{ prefabPath = "$SURVIVAL_DATA/LocalPrefabs/EffectPrefabs/Lavatrack/lavatrack_down_a_01.prefab", legsAnimation = { center = "stuck_loop" }, bodyAnimation = { center = "stuck_loop" } },
	{ prefabPath = "$SURVIVAL_DATA/LocalPrefabs/EffectPrefabs/Lavatrack/lavatrack_down_a_02.prefab", legsAnimation = { center = "stuck_loop" }, bodyAnimation = { center = "stuck_loop" } },
}

local EndTrackPrefabs = {
	{ prefabPath = "$SURVIVAL_DATA/LocalPrefabs/EffectPrefabs/Lavatrack/lavatrack_down_a_end.prefab", legsAnimation = { center = "stuck_out" }, bodyAnimation = { center = "stuck_out" } },
	{ prefabPath = "$SURVIVAL_DATA/LocalPrefabs/EffectPrefabs/Lavatrack/lavatrack_down_a_end_02.prefab", legsAnimation = { center = "stuck_out_run" }, bodyAnimation = { center = "stuck_out_run" } },
}

local CinematicTrackPrefabs = {
	{ prefabPath = "$SURVIVAL_DATA/LocalPrefabs/EffectPrefabs/Lavatrack/lavatrack_cinematic_a_01.prefab", legsAnimation = { center = "c_run01" }, bodyAnimation = { center = "ani_destructcinematic" } },
}

local DownTransitionTrackPrefabs = {
	{ prefabPath = "$SURVIVAL_DATA/LocalPrefabs/EffectPrefabs/Lavatrack/lavatrack_down_a_start.prefab", legsAnimation = { center = "stuck_in" }, bodyAnimation = { center = "stuck_in" } },
	{ prefabPath = "$SURVIVAL_DATA/LocalPrefabs/EffectPrefabs/Lavatrack/lavatrack_transition_a_01.prefab", legsAnimation = { center = "stuck_in_prep" }, bodyAnimation = { center = "stuck_in_prep" } }
}

local EndTransitionTrackPrefabs = {
	{ prefabPath = "$SURVIVAL_DATA/LocalPrefabs/EffectPrefabs/Lavatrack/lavatrack_down_a_preflip.prefab", legsAnimation = { center = "stuck_out_loop" }, bodyAnimation = { center = "stuck_out_loop" } },
	
}

local KinematicTrainCarPrefabs = {
	"$SURVIVAL_DATA/LocalPrefabs/GameplayPrefabs/Drillbot/gameplay_drillbot_wagon01.prefab",
	"$SURVIVAL_DATA/LocalPrefabs/GameplayPrefabs/Drillbot/gameplay_drillbot_wagon02.prefab",
	"$SURVIVAL_DATA/LocalPrefabs/GameplayPrefabs/Drillbot/gameplay_drillbot_wagon03.prefab",
	"$SURVIVAL_DATA/LocalPrefabs/GameplayPrefabs/Drillbot/gameplay_drillbot_wagon04.prefab",
	"$SURVIVAL_DATA/LocalPrefabs/GameplayPrefabs/Drillbot/gameplay_drillbot_endwagon.prefab"
}

local KinematicSideCartPrefabs = {
--Enemysidecars	1-6
	{ left = "$SURVIVAL_DATA/LocalPrefabs/GameplayPrefabs/Traintrack/traintrack_sidecart_left01.prefab", right = "$SURVIVAL_DATA/LocalPrefabs/GameplayPrefabs/Traintrack/traintrack_sidecart_right01.prefab" },
	{ left = "$SURVIVAL_DATA/LocalPrefabs/GameplayPrefabs/Traintrack/traintrack_sidecart_left02.prefab", right = "$SURVIVAL_DATA/LocalPrefabs/GameplayPrefabs/Traintrack/traintrack_sidecart_right02.prefab" },
	{ left = "$SURVIVAL_DATA/LocalPrefabs/GameplayPrefabs/Traintrack/traintrack_sidecart_left03.prefab", right = "$SURVIVAL_DATA/LocalPrefabs/GameplayPrefabs/Traintrack/traintrack_sidecart_right03.prefab" },
	{ left = "$SURVIVAL_DATA/LocalPrefabs/GameplayPrefabs/Traintrack/traintrack_sidecart_left04.prefab", right = "$SURVIVAL_DATA/LocalPrefabs/GameplayPrefabs/Traintrack/traintrack_sidecart_right04.prefab" },
	{ left = "$SURVIVAL_DATA/LocalPrefabs/GameplayPrefabs/Traintrack/traintrack_sidecart_left05.prefab", right = "$SURVIVAL_DATA/LocalPrefabs/GameplayPrefabs/Traintrack/traintrack_sidecart_right05.prefab" },
	{ left = "$SURVIVAL_DATA/LocalPrefabs/GameplayPrefabs/Traintrack/traintrack_sidecart_left06.prefab", right = "$SURVIVAL_DATA/LocalPrefabs/GameplayPrefabs/Traintrack/traintrack_sidecart_right06.prefab" },
--Shootsidecars 7-9
	{ left = "$SURVIVAL_DATA/LocalPrefabs/GameplayPrefabs/Traintrack/traintrack_shootcar_left01.prefab", right = "$SURVIVAL_DATA/LocalPrefabs/GameplayPrefabs/Traintrack/traintrack_shootcar_right01.prefab" },
	{ left = "$SURVIVAL_DATA/LocalPrefabs/GameplayPrefabs/Traintrack/traintrack_shootcar_left02.prefab", right = "$SURVIVAL_DATA/LocalPrefabs/GameplayPrefabs/Traintrack/traintrack_shootcar_right02.prefab" },
	{ left = "$SURVIVAL_DATA/LocalPrefabs/GameplayPrefabs/Traintrack/traintrack_shootcar_left03.prefab", right = "$SURVIVAL_DATA/LocalPrefabs/GameplayPrefabs/Traintrack/traintrack_shootcar_right03.prefab" },
--Boaridngsidecars --- Test 10
	{ left = "$SURVIVAL_DATA/LocalPrefabs/GameplayPrefabs/Traintrack/traintrack_boarding_left04.prefab", right = "$SURVIVAL_DATA/LocalPrefabs/GameplayPrefabs/Traintrack/traintrack_boarding_right01.prefab" },
--Dropfromabove --- Test 11  /left = Front /Right = Back
	{ left = "$SURVIVAL_DATA/LocalPrefabs/GameplayPrefabs/Traintrack/traintrack_sidecart_above01.prefab", right = "$SURVIVAL_DATA/LocalPrefabs/GameplayPrefabs/Traintrack/traintrack_sidecart_above01.prefab" },
--Boxcars --- 12
	{ left = "$SURVIVAL_DATA/LocalPrefabs/GameplayPrefabs/Traintrack/traintrack_sidecart_left07.prefab", right = "$SURVIVAL_DATA/LocalPrefabs/GameplayPrefabs/Traintrack/traintrack_sidecart_right07.prefab" },
--Mechaniccar (exit cinematic mechanics) --- 13 (only right side)
	{ left = "$SURVIVAL_DATA/LocalPrefabs/GameplayPrefabs/Traintrack/traintrack_mechaniccar_left01.prefab", right = "$SURVIVAL_DATA/LocalPrefabs/GameplayPrefabs/Traintrack/traintrack_mechaniccar_right01.prefab" }
}

function Init( world, generatorIndex )
    g_world = world
	g_generatorIndex = generatorIndex
end

-------------------------------------------------------------------------------------------

function SaveTunnelPrefabContent()

	if g_generatorIndex == 0 then
		local storagePrefabs = {
			CombatTrackPrefabs = {},
			EnterTrackPrefabs = {},
			RollercoasterTrackPrefabs = {},
			DownTrackPrefabs = {},
			EndTrackPrefabs = {},
			CinematicTrackPrefabs = {},
			DownTransitionTrackPrefabs = {},
			EndTransitionTrackPrefabs = {},
			IntroTrackPrefabs = {},
			BosstrainPrefab = {}
		}

		local loadPrefabs = function( destination, source )
			for i, value in ipairs( source ) do
				local creations, prefabs, nodes, assets, decals, harvestables, kinematics = sm.terrainTile.getContentFromPrefab( value.prefabPath, sm.terrainTile.loadFlags.nodes )
				destination[i] = { nodes = nodes, legsAnimation = value.legsAnimation, bodyAnimation = value.bodyAnimation }
			end
		end

		loadPrefabs( storagePrefabs.CombatTrackPrefabs, CombatTrackPrefabs )
		loadPrefabs( storagePrefabs.EnterTrackPrefabs, EnterTrackPrefabs )
		loadPrefabs( storagePrefabs.RollercoasterTrackPrefabs, RollercoasterTrackPrefabs )
		loadPrefabs( storagePrefabs.DownTrackPrefabs, DownTrackPrefabs )
		loadPrefabs( storagePrefabs.EndTrackPrefabs, EndTrackPrefabs )
		loadPrefabs( storagePrefabs.CinematicTrackPrefabs, CinematicTrackPrefabs )
		loadPrefabs( storagePrefabs.DownTransitionTrackPrefabs, DownTransitionTrackPrefabs )
		loadPrefabs( storagePrefabs.EndTransitionTrackPrefabs, EndTransitionTrackPrefabs )
		loadPrefabs( storagePrefabs.IntroTrackPrefabs, IntroTrackPrefabs )

		local loadFlags = bit.bor( sm.terrainTile.loadFlags.nodes, sm.terrainTile.loadFlags.kinematics, sm.terrainTile.loadFlags.creations )

		-- dirty appropriation of the default prepare cell procedure
		local function loadPrefabProcedure( prefabName )
			g_prefabNodes = {}
			g_connectionNodeCount = 65536
			g_prefabCreations = {}
			g_prefabHarvestables = {}
			g_prefabDecals = {}
			g_prefabAssets = {}
			g_prefabKinematics = {}
	
			-- this function writes to the above global variables
			

			local prefab = { name = prefabName, pos = sm.vec3.new(0,0,0), rot = sm.quat.identity(), scale = sm.vec3.new(1,1,1), flags = 0, tags = {} }
			DefaultLoadPrefabProcedure( prefab, loadFlags, nil, prefab.name, nil, nil, nil )
		end

		storagePrefabs.BosstrainPrefabs = {}
		for index, wagons in ipairs( KinematicTrainCarPrefabs ) do
			--creations, prefabs, nodes, assets, decals, harvestables, kinematics = sm.terrainTile.getContentFromPrefab( wagons, loadFlags )
			loadPrefabProcedure( wagons )
			storagePrefabs.BosstrainPrefabs[index] = { kinematics = g_prefabKinematics, nodes = g_prefabNodes, creations = g_prefabCreations }
		end

		storagePrefabs.SideCartPrefabs = {}
		for index, sideCarts in ipairs( KinematicSideCartPrefabs ) do
			loadPrefabProcedure( sideCarts.left )
			local left = { kinematics = g_prefabKinematics, nodes = g_prefabNodes, creations = g_prefabCreations }

			loadPrefabProcedure( sideCarts.right )
			local right = { kinematics = g_prefabKinematics, nodes = g_prefabNodes, creations = g_prefabCreations }

			storagePrefabs.SideCartPrefabs[index] = { left = left, right = right }
		end

		sm.terrainGeneration.setGameStorageNoSave( STORAGE_CHANNEL_DRILLBOT_PREFABS, storagePrefabs )
	end
end

function Create( xMin, xMax, yMin, yMax, seed, data )

	g_cellData = {}
	g_cellData.bounds = { xMin = xMin, xMax = xMax, yMin = yMin, yMax = yMax }

	sm.terrainData.save( g_cellData )
	SaveTunnelPrefabContent()
end

function Load()
    if sm.terrainData.exists() then
		g_cellData = sm.terrainData.load()
		SaveTunnelPrefabContent()
		return true
	end
	return false
end

----------------------------------------------------------------------------------------------------
-- Generator API Getters
----------------------------------------------------------------------------------------------------

function GetHeightAt( x, y, lod )
	return 0
end

function GetColorAt( x, y, lod )
	return 0, 0, 0
end

function GetMaterialAt( x, y, lod )
	return 0, 0, 0, 0, 0, 0, 0, 0
end

function GetClutterIdxAt( x, y )
	return -1
end

function GetEffectMaterialAt( x, y )
	return "Dirt"
end

----------------------------------------------------------------------------------------------------

function PrepareCell( cellX, cellY, loadFlags, lodLevel )
	g_prefabNodes = {}
	g_prefabCreations = {}
	g_prefabHarvestables = {}
	g_prefabDecals = {}
	g_prefabAssets = {}
	g_prefabKinematics = {}

	-- Note: no prefab loading desired in this world, tile is treated as empty, but gameplay related prefabs may be placed there for convenience.
end

----------------------------------------------------------------------------------------------------

function GetAssetsForCell( cellX, cellY, lod )
	return {}
end

function GetDecalsForCell( cellX, cellY )
	return {}
end

function GetHarvestablesForCell( cellX, cellY, lod )
	return {}
end

function GetKinematicsForCell( cellX, cellY, lod, terrainTaskTick )
	local kinematics = g_prefabKinematics
	g_prefabKinematics = {}

	if not ( cellX == 0 and cellY == 0 ) then
		return kinematics
	end

	local tileStorageKey
	tileStorageKey = CalculateIndoorTileStorageKey( g_world.id )
	if lod == 0 then
		local storageData = sm.terrainGeneration.loadGameStorage( tileStorageKey )
		if storageData then
			local drillbotManagerKinematics = storageData[DRILLBOT_KINEMATICS_TABLE]
			local getDrillbotKinematic = function( storedKinematic )
				if SafeNestedAccess( storageData, KINEMATIC_STORAGE_TABLE, storedKinematic.params.storageTag ) then
					table.insert( kinematics, {
						uuid = storedKinematic.uuid,
						pos = storedKinematic.createdPos,
						rot = storedKinematic.createdRot,
						scale = sm.vec3.new( 0.25, 0.25, 0.25 ),
						params = storedKinematic.params
					} )
				end
			end
	
			if drillbotManagerKinematics.leftSideCart then
				for storageTag, sideCartKinematic in pairs( drillbotManagerKinematics.leftSideCart ) do
					getDrillbotKinematic( sideCartKinematic )
				end
			end
			if drillbotManagerKinematics.rightSideCart then
				for storageTag, sideCartKinematic in pairs( drillbotManagerKinematics.rightSideCart ) do
					getDrillbotKinematic( sideCartKinematic )
				end
			end
	
			for _, cart in pairs( drillbotManagerKinematics.carts ) do
				for storageTag, cartKinematic in pairs( cart ) do
					getDrillbotKinematic( cartKinematic )
				end
			end
		end
	end

	local storageData = sm.terrainGeneration.loadGameStorage( tileStorageKey )
	for _, kinematic in pairs( kinematics ) do
		LoadKinematicFromStorage( kinematic, storageData, kinematic.pos, terrainTaskTick, g_world, cellX, cellY )
	end
	return kinematics
end

----------------------------------------------------------------------------------------------------

function GetCreationsForCell( cellX, cellY )
	return {}
end

function GetNodesForCell( cellX, cellY )
	return {}
end

----------------------------------------------------------------------------------------------------

function GetCellGroups()
	if g_cellData.bounds then
		g_cellData.groupId = {}
		for cellY = g_cellData.bounds.yMin, g_cellData.bounds.yMax do
			g_cellData.groupId[cellY] = {}
			for cellX = g_cellData.bounds.xMin, g_cellData.bounds.xMax do
				g_cellData.groupId[cellY][cellX] = 1 -- All cells in group 1
			end
		end
	end
	if g_cellData.groupId then
		return g_cellData.groupId
	end
	return {}
end

----------------------------------------------------------------------------------------------------
-- Tile Reader Path Getter
----------------------------------------------------------------------------------------------------

function GetTilePath( uid )
	return ""
end
