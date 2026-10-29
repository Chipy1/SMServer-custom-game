dofile( "$SURVIVAL_DATA/Scripts/util.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/managers/ElevatorManager.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/managers/WorldManager.lua" )

MinidungeonElevatorManager = class( ElevatorManager )

local ELEVATOR_TRAVEL_TICKS = 680
local ELEVATOR_MOVEWALLS_TICK = ELEVATOR_TRAVEL_TICKS - 60
local ELEVATOR_LOAD_WORLDS_TICK = ELEVATOR_MOVEWALLS_TICK - 60
local ELEVATOR_TRANSFER_TICK = 120
local ELEVATOR_START_FADE = ELEVATOR_TRANSFER_TICK + 40 -- Sometime before transfer
local ELEVATOR_END_FADE = 40 -- Before doors open

function MinidungeonElevatorManager.server_onCreate( self )
	g_minidungeonElevatorManager = self

	self.elevators = sm.storage.load( STORAGE_CHANNEL_MINIDUNGEON_ELEVATORS )
	self.connections = sm.storage.load( STORAGE_CHANNEL_MINIDUNGEON_CONNECTIONS )

	if self.connections == nil then
		self.connections = {}
		self.connections.exitPortals = {}
	end
	if self.elevators == nil then
		self.elevators = {}
		self:sv_saveElevators()
	end

	self.activeElevators = {}
	self.objectToElevator = {}

	self.loadedCells = {}
	self.loadHandles = {}
	self.exitLoadHandles = {}

	local overworld = WorldManager.Sv_GetWorld( "overworld" )
	for name, portalData in pairs( self.connections.exitPortals ) do
		sm.portal.addWorldPortalHook( overworld, name, portalData.portal )
	end
end

function MinidungeonElevatorManager.sv_saveElevators( self )
	sm.storage.save( STORAGE_CHANNEL_MINIDUNGEON_ELEVATORS, self.elevators )
end

function MinidungeonElevatorManager.server_onFixedUpdate( self )
	local save = false
	for _,elevator in pairs( self.activeElevators ) do
		-- Transfer
		if elevator.ticksToDestination == ELEVATOR_TRANSFER_TICK then
			print( "Transfering to", elevator.destination )

			if self:sv_isElevatorReadyForTransfer( elevator ) then
				if elevator.destination == "b" then
					elevator.portal:transferAToB()
				else--if elevator.destination == "a" then
					-- Capture the dungeon world and its riders before the transfer moves them out to the overworld.
					local dungeonWorld = elevator.portal:getWorldB()
					local leavingContents = elevator.portal:getContentsB()
					elevator.portal:transferBToA()
					-- Riding up to the overworld with the reward crate smashed counts as completing the growlab.
					if dungeonWorld and sm.exists( dungeonWorld ) and TriggerContentsContainsAnyPlayer( leavingContents ) then
						local poiType = dungeonWorld.publicData.poiType
						if poiType and ProgressionManager.Sv_IsGrowlabCrateSmashed( poiType ) then
							ProgressionManager.Sv_CompleteGrowlab( poiType )
						end
					end
				end
			else
				sm.log.info( "An elevator wants to transfer to '"..elevator.destination.."' but destination is not ready, added 1 second" )
				elevator.ticksToDestination = elevator.ticksToDestination + 40
				
				if self:sv_needToLoadWorlds( elevator.portal ) then
					self:sv_loadPortalWorlds( elevator.portal )
				end

				self:sv_prepareCells( elevator.portal )
			end
			save = true
		end

		-- Open doors
		if elevator.ticksToDestination == 0 then
			if elevator.a and sm.exists( elevator.a ) then
				elevator.a.active = elevator.destination == "a"
				elevator.a:setPower( 0 )
			end
			if elevator.b and sm.exists( elevator.b ) then
				elevator.b.active = elevator.destination == "b"
				elevator.b:setPower( 0 )
			end
		else -- Elevator is moving
			assert( elevator.ticksToDestination > 0 )

			-- Countdown
			elevator.ticksToDestination = elevator.ticksToDestination - 1
			if elevator.ticksToDestination == 0 then
				save = true
				self:sv_arrived( elevator )
			end

			-- Close doors
			if elevator.a and sm.exists( elevator.a ) then
				elevator.a.active = false
				if elevator.ticksToDestination == ELEVATOR_MOVEWALLS_TICK then
					elevator.a:setPower( elevator.destination == "a" and 1 or -1 )
				end
			end
			if elevator.b and sm.exists( elevator.b ) then
				elevator.b.active = false
				if elevator.ticksToDestination == ELEVATOR_MOVEWALLS_TICK then
					elevator.b:setPower( elevator.destination == "b" and -1 or 1 )
				end
			end

			-- Start Fade
			if elevator.ticksToDestination == ELEVATOR_START_FADE then
				if elevator.destination == "b" then
					if elevator.portal:getWorldB() then
						self:sv_sendFadeToBlackEvent( elevator.portal:getContentsA(), true )
					end
				end
				if elevator.destination == "a" then
					if elevator.portal:getWorldA() then
						self:sv_sendFadeToBlackEvent( elevator.portal:getContentsB(), true )
					end
				end
			end

			if elevator.ticksToDestination == ELEVATOR_LOAD_WORLDS_TICK then
				self:sv_loadPortalWorlds( elevator.portal )
			end

			-- Transfer
			if elevator.ticksToDestination < ELEVATOR_LOAD_WORLDS_TICK and
			   elevator.ticksToDestination > ELEVATOR_TRANSFER_TICK
			then
				-- Prepare for transfer
				self:sv_prepareCells( elevator.portal )
			end

			-- End Fade
			if elevator.ticksToDestination == ELEVATOR_END_FADE then
				if elevator.destination == "a" then
					if elevator.portal:getWorldB() then
						self:sv_sendFadeToBlackEvent( elevator.portal:getContentsA(), false )
					end
				end
				if elevator.destination == "b" then
					if elevator.portal:getWorldA() then
						self:sv_sendFadeToBlackEvent( elevator.portal:getContentsB(), false )
					end
				end
			end
		end
	end
	if save then
		self:sv_saveElevators()
	end
end

-- exit portal

local function CellKey( world, x, y )
	return world.id..":("..x..","..y..")"
end

function MinidungeonElevatorManager.sv_isCellLoaded( self, world, x, y )
	return self.loadedCells[CellKey( world, x, y )]
end

function MinidungeonElevatorManager.sv_registerExitPortal( self, name, portal )
	self.connections.exitPortals[name] = { portal = portal }
	sm.storage.save( STORAGE_CHANNEL_MINIDUNGEON_CONNECTIONS, self.connections )
end

function MinidungeonElevatorManager.sv_unregisterExitPortal( self, name )
	self.connections.exitPortals[name] = nil
	sm.storage.save( STORAGE_CHANNEL_MINIDUNGEON_CONNECTIONS, self.connections )
end

function MinidungeonElevatorManager.sv_loadBForPlayersInExitPortal( self, params )
	if not sm.exists( params.portal:getWorldA() ) then
		sm.log.warning( "MinidungeonElevatorManager: 244. No world cell loaded for: ", params.world, ". World did not exist" )
		return
	end

	local function loadCell ( world, position )
		local x = math.floor( position.x / 64 )
		local y = math.floor( position.y / 64 )
		return world:loadCellWithHandle( x, y, nil )
	end

	if self.exitLoadHandles[params.name] == nil then
		if sm.exists( params.portal:getWorldA() ) then
			self.exitLoadHandles[params.name] = loadCell( params.portal:getWorldA(), params.portal:getPositionA() )
		end
	end
end

function MinidungeonElevatorManager.sv_releaseLoadhandle( self, name )
	if self.exitLoadHandles[name] then
		self.exitLoadHandles[name]:release()
		self.exitLoadHandles[name] = nil
	end
end

function MinidungeonElevatorManager.sv_e_worldReady( self, params )
	if self.elevators then
		local entrancePortal = self.elevators[params.portalId].portal
		if not ( entrancePortal:hasOpeningA() and entrancePortal:hasOpeningB() ) then
			self:sv_loadBForPlayersInElevator( params.portalId, params.world, params.x, params.y )
		end
	end
end

function MinidungeonElevatorManager.sv_e_createMinidungeonDestination( self, params )
	local createdWorld = sm.world.createWorld( "$SURVIVAL_DATA/Scripts/game/worlds/DungeonWorld.lua", "DungeonWorld", { path = params.path, poiType = params.poiType, portalId = params.portal.id }, math.random( 1073741823 ) )
	sm.portal.addWorldPortalHook( createdWorld, params.name, params.portal )
end

function MinidungeonElevatorManager.Sv_OnCellLoaded( world, x, y )
	if g_minidungeonElevatorManager then
		g_minidungeonElevatorManager:sv_onCellLoaded( world, x, y )
	end
end

function MinidungeonElevatorManager.Sv_Go( object )
	if g_minidungeonElevatorManager then
		g_minidungeonElevatorManager:sv_go( object )
	end
end

function MinidungeonElevatorManager.Sv_Call( object )
	if g_minidungeonElevatorManager then
		g_minidungeonElevatorManager:sv_call( object )
	end
end

function MinidungeonElevatorManager.Sv_RegisterElevator( object, portal )
	if g_minidungeonElevatorManager then
		g_minidungeonElevatorManager:sv_registerElevator( object, portal )
	end
end

function MinidungeonElevatorManager.Sv_RemoveElevator( object )
	if g_minidungeonElevatorManager then
		g_minidungeonElevatorManager:sv_removeElevator( object )
	end
end

function MinidungeonElevatorManager.Sv_RegisterExitPortal( name, portal )
	if g_minidungeonElevatorManager then
		g_minidungeonElevatorManager:sv_registerExitPortal( name, portal )
	end
end

function MinidungeonElevatorManager.Sv_UnregisterExitPortal( name )
	if g_minidungeonElevatorManager then
		g_minidungeonElevatorManager:sv_unregisterExitPortal( name )
	end
end

function MinidungeonElevatorManager.Sv_GetElevatorHome( object )
	if g_minidungeonElevatorManager then
		return g_minidungeonElevatorManager:sv_getElevatorHome( object )
	end
end

function MinidungeonElevatorManager.Sv_GetElevatorDestination( object )
	if g_minidungeonElevatorManager then
		return g_minidungeonElevatorManager:sv_getElevatorDestination( object )
	end
end

function MinidungeonElevatorManager.Sv_IsCellLoaded( world, x, y )
	if g_minidungeonElevatorManager then
		return g_minidungeonElevatorManager:sv_isCellLoaded( world, x, y )
	end
end

function MinidungeonElevatorManager.Sv_CreateMinidungeonDestination( params )
	if g_minidungeonElevatorManager then
		sm.event.sendToScriptableObject( g_minidungeonElevatorManager.scriptableObject, "sv_e_createMinidungeonDestination", params )
	end
end

function MinidungeonElevatorManager.Sv_ReleaseLoadHandle( params )
	if g_minidungeonElevatorManager then
		sm.event.sendToScriptableObject( g_minidungeonElevatorManager.scriptableObject, "sv_releaseLoadhandle", params )
	end
end

function MinidungeonElevatorManager.Sv_LoadBForPlayersInExitPortal( params )
	if g_minidungeonElevatorManager then
		sm.event.sendToScriptableObject( g_minidungeonElevatorManager.scriptableObject, "sv_loadBForPlayersInExitPortal", params )	
	end
end

function MinidungeonElevatorManager.Sv_WorldReady( params )
	if g_minidungeonElevatorManager then
		sm.event.sendToScriptableObject( g_minidungeonElevatorManager.scriptableObject, "sv_e_worldReady", params )
	end
end