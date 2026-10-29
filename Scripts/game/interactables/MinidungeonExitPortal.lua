dofile( "$SURVIVAL_DATA/Scripts/game/survival_shapes.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/survival_constants.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/managers/WorldManager.lua" )
dofile( "$SURVIVAL_DATA/Scripts/util.lua" )

MinidungeonExitPortal = class()
local transportTickFrequency = 40 * 0.2
local transportTickCounter = 0
local markerOffset = sm.vec3.new( 0.0, 0.0, 16.0 )

function MinidungeonExitPortal.server_onCreate( self )
	self.sv = {}
	self.sv.cellPosX = math.floor( self.shape.worldPosition.x / 64 )
	self.sv.cellPosY = math.floor( self.shape.worldPosition.y / 64 )

	local world = self.shape.body:getWorld()
	self.sv.inDungeon = world.publicData.type ~= "Overworld"
	self.sv.poiType = self.sv.inDungeon and world.publicData.poiType or GetPoiTypeAtPosition( world, self.shape.worldPosition )
	self.sv.name = self.sv.poiType and ( "MiniDungeon_"..self.sv.poiType.."_exit" ) or nil

	local area = sm.cell.getNodesByTag( self.sv.cellPosX, self.sv.cellPosY, "MINIDUNGEON_EXIT_AREA" )[1]
	if not area then
		sm.log.warning( "No area was found for minidungeon exit portal" )
		return
	end
	self.sv.areaPosition = area.position
	self.sv.areaSize = area.scale / 2
	self.sv.areaRotation = area.rotation

	if self.sv.inDungeon then
		self:sv_createDungeonAreaTriggers()
	else
		self:sv_createOverworldAreaTrigger()
	end

	self.sv.saved = self.storage:load() or {}
	if self.sv.saved.portal == nil and self.sv.name then
		if self.sv.inDungeon then
			local partnerWorld = WorldManager.Sv_GetWorld( "overworld" )
			local portal = sm.portal.popWorldPortalHook( self.sv.name, partnerWorld )
			if portal == nil then
				sm.log.warning( "minidungeon exit was created but not connected to any portal" )
				return
			end
			MinidungeonElevatorManager.Sv_UnregisterExitPortal( self.sv.name )
			portal:setOpeningB( self.sv.areaPosition, self.sv.areaRotation )
			portal:setBMarkerOffset( markerOffset )
			self.sv.saved.portal = portal
		else
			local portal = sm.portal.createPortal( self.sv.areaSize )
			portal:setAToBMarkerAllowed( false )
			portal:setOpeningA( self.sv.areaPosition, self.sv.areaRotation )
			sm.portal.addWorldPortalHook( world, self.sv.name, portal )
			MinidungeonElevatorManager.Sv_RegisterExitPortal( self.sv.name, portal )
			self.sv.saved.portal = portal
		end
		self.storage:save( self.sv.saved )
	end
end

function MinidungeonExitPortal.server_onDestroy( self )
	if self.sv.loadTrigger then
		sm.areaTrigger.destroy( self.sv.loadTrigger )
	end
	if self.sv.unloadTrigger then
		sm.areaTrigger.destroy( self.sv.unloadTrigger )
	end
	if self.sv.teleportTrigger then
		sm.areaTrigger.destroy( self.sv.teleportTrigger )
	end
	if self.sv.goopTrigger then
		sm.areaTrigger.destroy( self.sv.goopTrigger )
	end
	MinidungeonElevatorManager.Sv_ReleaseLoadHandle( self.sv.name )
end

function MinidungeonExitPortal.server_onRefresh( self )
end

function MinidungeonExitPortal.sv_createDungeonAreaTriggers( self )
	if self.sv.areaSize and self.sv.areaPosition and self.sv.areaRotation then
		self.sv.teleportTrigger = sm.areaTrigger.createBox( self.sv.areaSize, self.sv.areaPosition, self.sv.areaRotation, sm.areaTrigger.filter.character )
		self.sv.fadeTrigger = sm.areaTrigger.createBox( self.sv.areaSize, self.sv.areaPosition + sm.vec3.new( 0, 0, 4 ), self.sv.areaRotation, sm.areaTrigger.filter.character )
		self.sv.loadTrigger = sm.areaTrigger.createBox( sm.vec3.new( 15, 15, 15 ), self.sv.areaPosition + sm.vec3.new( 0, 0, 15 ), self.sv.areaRotation, sm.areaTrigger.filter.character )
		self.sv.unloadTrigger = sm.areaTrigger.createBox( sm.vec3.new( 30, 30, 30 ), self.sv.areaPosition + sm.vec3.new( 0, 0, 15 ), self.sv.areaRotation, sm.areaTrigger.filter.character )
		
		self.sv.loadTrigger:bindOnEnter( "sv_loadPortalCell", self )
		self.sv.unloadTrigger:bindOnExit( "sv_unloadPortalCell", self )
		self.sv.teleportTrigger:bindOnEnter( "sv_tryInitateTeleport", self )
		self.sv.teleportTrigger:bindOnStay( "sv_tickTransportPlayers", self )
		self.sv.fadeTrigger:bindOnEnter( "sv_sendFadeToBlackEvent", self )
	end
end

function MinidungeonExitPortal.sv_createOverworldAreaTrigger( self )
	if self.sv.areaSize and self.sv.areaPosition and self.sv.areaRotation then
		self.sv.goopTrigger = sm.areaTrigger.createBox( self.sv.areaSize, self.sv.areaPosition, self.sv.areaRotation, sm.areaTrigger.filter.character )
		self.sv.goopTrigger:bindOnEnter( "sv_playerExitsTrashpipe", self )
	end
end

function MinidungeonExitPortal.sv_playerExitsTrashpipe( self, trigger, results )
	if not self:sv_resultsContainsPlayer( results ) then
		return
	end
	sm.effect.playEffect( "Growlab - Trashexit", self.sv.areaPosition )
end

function MinidungeonExitPortal.sv_loadPortalCell( self, trigger, results )
	if not self:sv_resultsContainsPlayer( results ) then
		return
	end
	MinidungeonElevatorManager.Sv_LoadBForPlayersInExitPortal( { portal = self.sv.saved.portal, name = self.sv.name } )
end

function MinidungeonExitPortal.sv_unloadPortalCell( self, trigger, results )
	if not self:sv_resultsContainsPlayer( results ) or self:sv_triggerAreaContainsPlayer( self.sv.loadTrigger ) then
		return
	end
	MinidungeonElevatorManager.Sv_ReleaseLoadHandle( self.sv.name )
end

function MinidungeonExitPortal.sv_tickTransportPlayers( self, trigger, results )
	if not self:sv_resultsContainsPlayer( results ) then
		return
	end
	transportTickCounter = transportTickCounter + 1
	if transportTickCounter >= transportTickFrequency then
		self:sv_tryInitateTeleport()
		transportTickCounter = 0
	end
end

function MinidungeonExitPortal.sv_tryInitateTeleport( self )
	if self:sv_isPortalTransferReady() then
		self.sv.saved.portal:transferBToA()
		ProgressionManager.Sv_CompleteGrowlab( self.sv.poiType )
	end
end

function MinidungeonExitPortal.sv_sendFadeToBlackEvent( self, trigger, results )
	if results == nil then
		return
	end
	for _,object in ipairs( results ) do
		if type( object ) == "Character" and sm.exists( object ) then
			local player = object:getPlayer()
			if player then
				sm.event.sendToPlayer( player, "sv_e_minidungeonEject" )
				sm.event.sendToPlayer( player, "sv_startFadeToBlackWaitForWorld", { duration = 0.125, timeout = 2.0 } )
			end
		end
	end
end

function MinidungeonExitPortal.sv_triggerAreaContainsPlayer( self, areaTrigger )
	local contents = areaTrigger:getContents()
	for _, content in ipairs( contents ) do
		if type( content ) == "Character" then
			if content:isPlayer() then
				return true
			end
		end
	end
	return false
end

function MinidungeonExitPortal.sv_isPortalTransferReady( self )
	local function worldReady ( world, position )
		local x = math.floor( position.x / 64 )
		local y = math.floor( position.y / 64 )
		return world and sm.exists( world ) and MinidungeonElevatorManager.Sv_IsCellLoaded( world, x, y )
	end
	
	return worldReady( self.sv.saved.portal:getWorldA(), self.sv.saved.portal:getPositionA() )
end

function MinidungeonExitPortal.sv_resultsContainsPlayer( self, results )
	for _,result in ipairs( results ) do
		if sm.exists( result ) then
			if result:isPlayer() then
				return true
			end
		end
	end
	return false
end	
