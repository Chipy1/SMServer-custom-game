dofile( "$SURVIVAL_DATA/Scripts/game/SurvivalGame.lua")
dofile( "$SURVIVAL_DATA/Scripts/game/worlds/BaseWorld.lua")
dofile( "$SURVIVAL_DATA/Scripts/game/survival_units.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/survival_shapes.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/survival_items.lua" )
dofile( "$SURVIVAL_DATA/Scripts/util.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/survival_constants.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/survival_loot.lua" )

UndergroundWorld = class( BaseWorld )
UndergroundWorld.terrainScript = "$SURVIVAL_DATA/Scripts/terrain/terrain_underground.lua"
UndergroundWorld.groundMaterialSet = "$SURVIVAL_DATA/Terrain/Materials/gnd_cave_materialset.json"
UndergroundWorld.voxelMaterialSet = "$SURVIVAL_DATA/Terrain/Materials/voxel_materialset_drill1.voxelmaterialset"
UndergroundWorld.enableSurface = true
UndergroundWorld.enableAssets = true
UndergroundWorld.enableClutter = true
UndergroundWorld.enableNodes = true
UndergroundWorld.enableCreations = true
UndergroundWorld.enableHarvestables = true
UndergroundWorld.enableKinematics = true
UndergroundWorld.enableVoxelTerrain = true
UndergroundWorld.isIndoor = false
UndergroundWorld.renderMode = "underground"
UndergroundWorld.cellMinX = -32
UndergroundWorld.cellMaxX = 31
UndergroundWorld.cellMinY = -32
UndergroundWorld.cellMaxY = 31
UndergroundWorld.defaultVoxelMaterial = 7 -- Bedrock
UndergroundWorld.defaultVoxelDensity = 31 -- Max density

UndergroundWorld.voxelMaterialSetName = "UndergroundDrill1"

local LitMininghubSettings = "$GAME_DATA/Render/RenderSettings/World/world_mininghub_on.rendersettings"





















function UndergroundWorld.server_onCreate( self )
	print( "UndergroundWorld - server create" )
	BaseWorld.server_onCreate( self )
	local depth = self.data.depth or 1
	self.world.publicData.type = "UndergroundWorld"
	self.world.publicData.depth = depth
	self.world.publicData.voxelMaterialSetName = self.voxelMaterialSetName or "UndergroundDrill1"

	self.world:setTerrainScriptData( { depth = depth, worldPath = self.data.worldFilePath } )
	WorldManager.Sv_RegisterWorld( "undergroundworld" .. tostring( depth ), self.world )

	MiningManager.Sv_SetupWorldMiningConfig( self.world )
end

function UndergroundWorld.sv_e_lightUpMininghub( self, params )
	local mininghubLights = sm.storage.load( STORAGE_CHANNEL_MININGHUB_LIGHTS ) or {}
	mininghubLights.lit = true
	mininghubLights.zoneId = params.zoneId
	sm.storage.save( STORAGE_CHANNEL_MININGHUB_LIGHTS, mininghubLights )

	self.network:setClientData( { mininghubLitUp = true, zoneId = params.zoneId } )
	self.network:sendToClients( "cl_n_renderSettingsChanged", params )
end

function UndergroundWorld.client_onCreate( self )
	BaseWorld.client_onCreate( self )
	print( "UndergroundWorld - client create" )

	local depth = self.data.depth or 1
	local worldPath = self.data.worldFilePath

	if not sm.isHost then
		self.world:setTerrainScriptData( { depth = depth, worldPath = worldPath } )
	end

	if worldPath and worldPath ~= "" then
		local worldData = sm.json.open( worldPath )
		self.cl.zoneSettingsPath = worldData.zoneSettings
		self.cl.ambienceAudio = worldData.ambienceAudio or "Underground - Ambiance"
		self.cl.musicParam = worldData.survivalMusicParameter
		self.cl.playerEffect = worldData.playerEffect
		self.cl.defaultRenderSetting = worldData.defaultRendersettings
	end





	if not self.cl.defaultRenderSetting or self.cl.defaultRenderSetting == "" then
		self.cl.defaultRenderSetting = "$GAME_DATA/Render/RenderSettings/World/world_underground_drill01.rendersettings"
	end
	if self.cl.zoneSettingsPath and self.cl.zoneSettingsPath ~= "" then
		self.cl.zoneSettings = sm.json.open( self.cl.zoneSettingsPath )
	end

	self.world.clientPublicData.type = "UndergroundWorld"
	self.world.clientPublicData.depth = depth
	self.world.clientPublicData.voxelMaterialSetName = self.voxelMaterialSetName or "UndergroundMininghub"
	self.world.clientPublicData.zoneSettingsPath = self.cl.zoneSettingsPath
	self.world.clientPublicData.zoneSettings = self.cl.zoneSettings
	self.world.clientPublicData.defaultRenderSetting = self.cl.defaultRenderSetting
	self.world.clientPublicData.ambience = self.cl.ambienceAudio or "Underground - Ambiance"
	self.world.clientPublicData.musicParameter = self.cl.musicParam or 8
	self.world.clientPublicData.playerEffect = self.cl.playerEffect

	WorldManager.Cl_RegisterWorld( "undergroundworld" .. tostring( depth ), self.world )
end

function UndergroundWorld.client_onClientDataUpdate( self, data )
	if data.mininghubLitUp then
		for _, zone in ipairs( self.cl.zoneSettings.zoneData ) do
			if zone.id == data.zoneId then
				zone.settingsPath = LitMininghubSettings
				self.world.clientPublicData.zoneSettings = self.cl.zoneSettings
				break
			end
		end
	end
end

function UndergroundWorld.cl_n_renderSettingsChanged( self, params )
	RenderSettingsManager.Cl_ModifyZoneRenderSettings( self.world, params.zoneId )
end

function UndergroundWorld.server_onFixedUpdate( self )
	BaseWorld.server_onFixedUpdate( self )
end

function UndergroundWorld.sv_e_spawnRaiders( self, params )
	local incomingUnits = {}
	for k, v in pairs( params.raiders ) do
		for i = 1, v do
			table.insert( incomingUnits, k )
		end
	end

	local randomOffset = sm.vec3.new( 0, math.random() * 6, 0 )
	randomOffset = randomOffset:rotateZ( math.rad( math.random() * 360 ) )
	local spawnPosition = params.attackPos + sm.vec3.new( 0, 0, -10 ) + randomOffset
	local spawnRotation = sm.quat.fromEuler( sm.vec3.new( 90, 0, 0 ) )
	local destination = params.attackPos + sm.vec3.new( 0, 0, 1.5 )
	local spawnParams = { world = self.world, uuid = kin_drillspawner, position = spawnPosition, quat = spawnRotation, harvestableParams = { destination = destination, raiders = incomingUnits } }
	self:sv_spawnHarvestable( spawnParams )
end

UndergroundWorldMiningHub = class( UndergroundWorld )
UndergroundWorldMiningHub.voxelMaterialSet = "$SURVIVAL_DATA/Terrain/Materials/voxel_materialset_mininghub.voxelmaterialset"
UndergroundWorldMiningHub.cellMinX = -16
UndergroundWorldMiningHub.cellMaxX = 15
UndergroundWorldMiningHub.cellMinY = -16
UndergroundWorldMiningHub.cellMaxY = 15
UndergroundWorldMiningHub.voxelMaterialSetName = "UndergroundMininghub"

function UndergroundWorldMiningHub.server_onCreate( self )
	print( "UndergroundWorldMiningHub - server create" )
	UndergroundWorld.server_onCreate( self )

	local mininghubLights = sm.storage.load( STORAGE_CHANNEL_MININGHUB_LIGHTS )
	if mininghubLights and mininghubLights.lit then
		self.network:setClientData( { mininghubLitUp = true, zoneId = mininghubLights.zoneId } )
	end
end

UndergroundWorldTutorial = class( UndergroundWorld )
UndergroundWorldTutorial.voxelMaterialSet = "$SURVIVAL_DATA/Terrain/Materials/voxel_materialset_onboarding.voxelmaterialset"
UndergroundWorldTutorial.cellMinX = -2
UndergroundWorldTutorial.cellMaxX = 2
UndergroundWorldTutorial.cellMinY = -12
UndergroundWorldTutorial.cellMaxY = 0
UndergroundWorldTutorial.voxelMaterialSetName = "UndergroundOnboarding"

UndergroundWorldDrill1 = class( UndergroundWorld )
UndergroundWorldDrill1.voxelMaterialSet = "$SURVIVAL_DATA/Terrain/Materials/voxel_materialset_drill1.voxelmaterialset"
UndergroundWorldDrill1.cellMinX = -5
UndergroundWorldDrill1.cellMaxX = 5
UndergroundWorldDrill1.cellMinY = -7
UndergroundWorldDrill1.cellMaxY = 0
UndergroundWorldDrill1.voxelMaterialSetName = "UndergroundDrill1"

UndergroundWorldStation1 = class( UndergroundWorld )
UndergroundWorldStation1.voxelMaterialSet = "$SURVIVAL_DATA/Terrain/Materials/voxel_materialset_controlstation.voxelmaterialset"
UndergroundWorldStation1.cellMinX = -8
UndergroundWorldStation1.cellMaxX = 7
UndergroundWorldStation1.cellMinY = -8
UndergroundWorldStation1.cellMaxY = 7
UndergroundWorldStation1.voxelMaterialSetName = "Controlstation"

UndergroundWorldScrapyard = class( UndergroundWorld )
UndergroundWorldScrapyard.voxelMaterialSet = "$SURVIVAL_DATA/Terrain/Materials/voxel_materialset_scrapyard.voxelmaterialset"
UndergroundWorldScrapyard.cellMinX = -8
UndergroundWorldScrapyard.cellMaxX = 7
UndergroundWorldScrapyard.cellMinY = -8
UndergroundWorldScrapyard.cellMaxY = 7
UndergroundWorldScrapyard.voxelMaterialSetName = "UndergroundScrapyard"

UndergroundWorldDrill2 = class( UndergroundWorld )
UndergroundWorldDrill2.voxelMaterialSet = "$SURVIVAL_DATA/Terrain/Materials/voxel_materialset_drill2.voxelmaterialset"
UndergroundWorldDrill2.cellMinX = -5
UndergroundWorldDrill2.cellMaxX = 5
UndergroundWorldDrill2.cellMinY = -7
UndergroundWorldDrill2.cellMaxY = 0
UndergroundWorldDrill2.voxelMaterialSetName = "UndergroundDrill2"

UndergroundWorldStation2 = class( UndergroundWorld )
UndergroundWorldStation2.voxelMaterialSet = "$SURVIVAL_DATA/Terrain/Materials/voxel_materialset_controlstation.voxelmaterialset"
UndergroundWorldStation2.cellMinX = -8
UndergroundWorldStation2.cellMaxX = 7
UndergroundWorldStation2.cellMinY = -8
UndergroundWorldStation2.cellMaxY = 7
UndergroundWorldStation2.voxelMaterialSetName = "Controlstation"

UndergroundWorldFinalBossLobby = class( UndergroundWorld )
UndergroundWorldFinalBossLobby.voxelMaterialSet = "$SURVIVAL_DATA/Terrain/Materials/voxel_materialset_drill1.voxelmaterialset"
UndergroundWorldFinalBossLobby.cellMinX = -16
UndergroundWorldFinalBossLobby.cellMaxX = 15
UndergroundWorldFinalBossLobby.cellMinY = -16
UndergroundWorldFinalBossLobby.cellMaxY = 15
UndergroundWorldFinalBossLobby.defaultVoxelMaterial = 0 -- Clay
UndergroundWorldFinalBossLobby.defaultVoxelDensity = 0 -- Min density

















