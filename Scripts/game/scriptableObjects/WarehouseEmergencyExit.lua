dofile( "$SURVIVAL_DATA/Scripts/game/survival_constants.lua" )

WarehouseEmergencyExit = class()
WarehouseEmergencyExit.isSaveObject = true

local PreloadTriggerExtents = sm.vec3.new( 5, 5, 5 )
local TravelTickCooldown = 20

function WarehouseEmergencyExit.server_onCreate( self )
    self.sv = {}
    self.sv.saved = self.storage:load()
    if self.sv.saved == nil then
        self.sv.saved = {}
        self.sv.saved.node = self.params.node
        self.sv.saved.overworldPortals = {}
        self.sv.saved.insidePortal = nil
        self.storage:save( self.sv.saved )
    end

    if self.scriptableObject.world.id == 1 then
        self.sv.outside = true
        self.sv.tileStorageKey = TileStorageManager.Sv_GetTileStorageKeyFromPosition( self.scriptableObject.world, self.sv.saved.node.position )
        local cellTags = sm.cell.getTags( math.floor( self.sv.saved.node.position. x / 64 ), math.floor( self.sv.saved.node.position.y / 64 ) )

        for _,tag in ipairs( cellTags ) do
            if CELL_TAG_TO_WAREHOUSE_FLOORS[tag] then
                self.sv.floorCount = CELL_TAG_TO_WAREHOUSE_FLOORS[tag]
                break
            end
        end
        if #self.sv.saved.overworldPortals == 0 then
            self:sv_createOverworldPortals()
        end
        self:sv_addPortalHooks()
    else
        self.sv.outside = false
        local warehouse = WarehouseManager.Sv_GetWarehouseFromWorld( self.scriptableObject.world )
        if warehouse then
            self.sv.isActive = warehouse.countdownEvent ~= nil
            self.sv.targetWorld = warehouse.world
            self.sv.tileStorageKey = warehouse.tileStorageKey
            if not self.sv.saved.insidePortal then
                self:sv_linkIndoorPortal()
            end
            if self.sv.saved.insidePortal then
                self.sv.saved.insidePortal:setBToAMarkerAllowed( self.sv.isActive )
            end
        end
        QuestManager.Sv_SubscribeEvent( QuestEvent.WarehouseDestructionStarted, self.scriptableObject, "sv_e_destructionStarted" )
        self.sv.worldPreloadTrigger = sm.areaTrigger.createBox( PreloadTriggerExtents, self.sv.saved.node.position, self.sv.saved.node.rotation, sm.areaTrigger.filter.character )
        self.sv.worldPreloadTrigger:bindOnEnter( "sv_onEnterPreloadTrigger", self )
        self.sv.worldPreloadTrigger:bindOnExit( "sv_onExitPreloadTrigger", self )
        self.sv.worldPreloadTrigger:setCharacterDetection( true )
    
        self.sv.travelTrigger = sm.areaTrigger.createBox( self.sv.saved.node.scale * 0.5 , self.sv.saved.node.position, self.sv.saved.node.rotation, sm.areaTrigger.filter.character )
        self.sv.travelTrigger:bindOnEnter( "sv_onEnterTravelTrigger", self )
        self.sv.travelTrigger:bindOnExit( "sv_onExitTravelTrigger", self )
        self.sv.travelTrigger:bindOnStay( "sv_onStayTravelTrigger", self )
    
        self.sv.loadHandle = nil
        self.sv.worldLoaded = false
        self.sv.travelTickCounter = 0
    end
end

-- overworld setup

function WarehouseEmergencyExit.sv_createOverworldPortals( self )
    for i = 1, self.sv.floorCount do
        local portal = sm.portal.createPortal( self.sv.saved.node.scale * 0.5 )
        portal:setOpeningA( self.sv.saved.node.position, self.sv.saved.node.rotation )
        self.sv.saved.overworldPortals[i] = portal
    end
    self.storage:save( self.sv.saved )
end

function WarehouseEmergencyExit.sv_addPortalHooks( self )
    for i,portal in ipairs( self.sv.saved.overworldPortals ) do
        if portal and not portal:hasOpeningB() then
            sm.portal.addWorldPortalHook( self.scriptableObject.world, self.sv.tileStorageKey..i, portal )
        elseif portal then
            portal:setAToBMarkerAllowed( false )
        end
    end
end

-- indoor setup

function WarehouseEmergencyExit.sv_e_destructionStarted( self, data )
    local warehouse = WarehouseManager.Sv_GetWarehouseFromWorld( self.scriptableObject.world )
    if warehouse.index == data.params.warehouseIndex then
        self.sv.isActive = true
        if self.sv.saved.insidePortal then
            self.sv.saved.insidePortal:setBToAMarkerAllowed( self.sv.isActive )
        end
    end
end

function WarehouseEmergencyExit.sv_linkIndoorPortal( self )
    local level = self.scriptableObject.world.publicData.level
    local portal = sm.portal.popWorldPortalHook( self.sv.tileStorageKey..level, self.sv.targetWorld )
    if portal then
        portal:setOpeningB( self.sv.saved.node.position, self.sv.saved.node.rotation )
        self.sv.saved.insidePortal = portal
        self.storage:save( self.sv.saved )
    end
end

function WarehouseEmergencyExit.sv_onEnterPreloadTrigger( self, trigger, results )
    if not self.sv.isActive or not TriggerResultContainsAnyPlayer( results ) then
        return
    end
    if self.sv.saved.insidePortal then
        local position = self.sv.saved.insidePortal:getPositionA()
        local x = math.floor( position.x / 64 )
        local y = math.floor( position.y / 64 )
        self.sv.loadHandle = self.sv.targetWorld:loadCellWithHandle( x, y, "sv_worldLoaded" )
    end
end

function WarehouseEmergencyExit.sv_onExitPreloadTrigger( self, trigger, results )
    if not self.sv.isActive or not TriggerResultContainsAnyPlayer( results ) then
        return
    end
    local playerStillInside = false
    for _,characterCollision in ipairs( trigger:getCharacters() ) do
        if sm.exists( characterCollision.character ) and characterCollision.character:isPlayer() then
            playerStillInside = true
        end
    end
    if not playerStillInside then
        if self.sv.loadHandle then
            self.sv.loadHandle = nil
            self.sv.worldLoaded = false
        end
    end
end

function WarehouseEmergencyExit.sv_onStayTravelTrigger( self, trigger, results )
    if not self.sv.isActive or not TriggerResultContainsAnyPlayer( results ) then
        return
    end
    self.sv.travelTickCounter = self.sv.travelTickCounter + 1
    if self.sv.travelTickCounter >= TravelTickCooldown and self.sv.worldLoaded then
        self.sv.saved.insidePortal:transferBToA()
        self.sv.travelTickCounter = 0
    end
end

function WarehouseEmergencyExit.sv_onEnterTravelTrigger( self, trigger, results )
    if not self.sv.isActive then
        return
    end
    for _,object in ipairs( results ) do
		if type( object ) == "Character" and sm.exists( object ) then
			local player = object:getPlayer()
			if player then
                sm.event.sendToPlayer( player, "sv_startFadeToBlackWaitForWorld", { duration = 0.5, timeout = 3 } )
            end
        end
    end
end

function WarehouseEmergencyExit.sv_onExitTravelTrigger( self, trigger, results )
    if not self.sv.isActive then
        return
    end
    for _,object in ipairs( results ) do
        if type( object ) == "Character" and sm.exists( object ) then
            local player = object:getPlayer()
            if player then
                sm.event.sendToPlayer( player, "sv_endFadeToBlackWaitForWorld", { duration = 0.5 } )
            end
        end
    end
end

function WarehouseEmergencyExit.sv_worldLoaded( self )
    self.sv.worldLoaded = true
end
