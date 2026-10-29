dofile( "$SURVIVAL_DATA/Scripts/game/survival_constants.lua" )

WorldManager = {}

function WorldManager.Sv_OnCreate()
	g_worldManager = g_worldManager or {}
	g_worldManager.sv_worldData = sm.storage.load( STORAGE_CHANNEL_WORLD_MANAGER ) or {}
end

function WorldManager.Cl_OnCreate()
	g_worldManager = g_worldManager or {}
	g_worldManager.cl_worlds = {}
end

function WorldManager.Sv_RegisterWorld( name, world )
	assert( g_worldManager and g_worldManager.sv_worldData, "WorldManager server not initialized" )

	g_worldManager.sv_worldData[name] = { world = world }
	sm.storage.save( STORAGE_CHANNEL_WORLD_MANAGER, g_worldManager.sv_worldData )
end

function WorldManager.Cl_RegisterWorld( name, world )
	assert( g_worldManager and g_worldManager.cl_worlds, "WorldManager client not initialized" )
	g_worldManager.cl_worlds[name] = world
end

function WorldManager.Sv_GetWorld( name )
	if g_worldManager and g_worldManager.sv_worldData then
		local data = g_worldManager.sv_worldData[name]
		if data then
			return data.world
		end
	end
	return nil
end

function WorldManager.Cl_GetWorld( name )
	if g_worldManager and g_worldManager.cl_worlds then
		return g_worldManager.cl_worlds[name]
	end
	return nil
end
