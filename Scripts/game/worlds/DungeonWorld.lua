dofile( "$SURVIVAL_DATA/Scripts/game/SurvivalGame.lua")
dofile( "$SURVIVAL_DATA/Scripts/game/worlds/BaseWorld.lua")
dofile( "$SURVIVAL_DATA/Scripts/game/survival_units.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/survival_shapes.lua" )
dofile( "$SURVIVAL_DATA/Scripts/util.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/survival_constants.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/survival_loot.lua" )

DungeonWorld = class( BaseWorld )
DungeonWorld.terrainScript = "$SURVIVAL_DATA/Scripts/terrain/terrain_dungeon.lua"
DungeonWorld.enableSurface = false
DungeonWorld.enableAssets = true
DungeonWorld.enableClutter = false
DungeonWorld.enableNodes = true
DungeonWorld.enableCreations = true
DungeonWorld.enableHarvestables = true
DungeonWorld.enableKinematics = true
DungeonWorld.enableBuildOnAssets = true
DungeonWorld.enableBuildOnLift = true
DungeonWorld.enableBuildOnBodies = true
DungeonWorld.renderMode = "mini_dungeon"
DungeonWorld.isIndoor = false
DungeonWorld.worldBorder = true
DungeonWorld.cellMinX = -16
DungeonWorld.cellMaxX = 15
DungeonWorld.cellMinY = -16
DungeonWorld.cellMaxY = 15

function DungeonWorld.server_onTerrainCreated( self )
	BaseWorld.server_onTerrainCreated( self )
	local storage = sm.storage.load( STORAGE_CHANNEL_ELEVATOR_LOCATIONS ) or {}
	if not storage[self.world.id] then
		storage[self.world.id] = {}
	end
	















	for index, node in ipairs( storage[self.world.id] ) do
		if node.tags and isAnyOf( "GROWLAB_ELEVATOR", node.tags ) then
			MinidungeonElevatorManager.Sv_WorldReady( {
				portalId = self.data.portalId,
				world = self.world,
				x = math.floor( node.pos.x / 64 ),
				y = math.floor( node.pos.y / 64 )
			} )
			break
		end
	end
end

function DungeonWorld.server_onCreate( self )
	print( "DungeonWorld - server create" )
    BaseWorld.server_onCreate( self )
	self.world.publicData.type = "DungeonWorld"
	self.world.publicData.poiType = self.data.poiType

    self:sv_createKillBox()
	self.world:setTerrainScriptData( { path = self.data.path, filterVoxelTrianglesFromNavMesh = true } )
end

function DungeonWorld.client_onCreate( self )
    BaseWorld.client_onCreate( self )
	local worldData = sm.json.open( self.data.path )

	self.cl.zoneSettings = nil
	if worldData.zoneSettings ~= "" then
		self.cl.zoneSettings = sm.json.open( worldData.zoneSettings )
	end

	self.world.clientPublicData.isLiftPlacable = true
	self.world.clientPublicData.defaultRenderSetting = worldData.defaultRendersettings
	self.world.clientPublicData.zoneSettingsPath = worldData.zoneSettings
	self.world.clientPublicData.zoneSettings = self.cl.zoneSettings
	self.world.clientPublicData.ambience = worldData.ambienceAudio or "Underground - Ambiance"
	self.world.clientPublicData.musicParameter = worldData.survivalMusicParameter or 5
	self.world.clientPublicData.playerEffect = worldData.playerEffect
	self.world.clientPublicData.blockBed = true
	self.world.clientPublicData.type = "DungeonWorld"
	
	if not sm.isHost then
		self.world:setTerrainScriptData( { path = self.data.path } )
	end
end

function DungeonWorld.sv_createKillBox( self )

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


function DungeonWorld.trigger_onEnterKillBox( self, trigger, results )
    -- New objects in the kill box
	for _,result in ipairs( results ) do
		if sm.exists( result ) then
			-- Respawn character
			if type( result ) == "Character" then
				if result:isPlayer() then
					local storage = sm.storage.load( STORAGE_CHANNEL_ELEVATOR_LOCATIONS ) or {}
					for index, node in ipairs( storage[self.world.id] ) do
						if node.tags and isAnyOf( "GROWLAB_ELEVATOR", node.tags ) then
							result:setWorldPosition( node.pos + sm.vec3.new( 0, 0, 5 ) )
							break
						end
					end
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

function DungeonWorld.client_onUpdate( self, deltaTime )
	BaseWorld.client_onUpdate( self, deltaTime )
end

function DungeonWorld.server_onCellCreated( self, x, y )
    BaseWorld.server_onCellCreated( self, x, y )
end

function DungeonWorld.server_onCellLoaded( self, x, y )
    BaseWorld.server_onCellLoaded( self, x, y )
end