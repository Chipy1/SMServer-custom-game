CombatRoomTrigger = class( nil )
CombatRoomTrigger.isSaveObject = true

function CombatRoomTrigger.server_onCreate( self )
    self.sv = {}
    self.sv.saved = self.storage:load()
    if self.sv.saved == nil then
        self.sv.saved = {}
        if self.params then
            self.sv.saved.roomName = self.params.roomName
            self.sv.saved.node = self.params.node
        end
        self.storage:save( self.sv.saved )
    end
    self.sv.tileStorageKey = TileStorageManager.Sv_GetTileStorageKeyFromPosition( self.sv.node.params.world, self.sv.saved.node.position )
    self.sv.node = nil
    self:sv_createAreaTrigger()
end

function CombatRoomTrigger.server_onDestroy( self )
    if self.sv.areaTrigger then
        sm.areaTrigger.destroy( self.sv.areaTrigger )
    end
end

function CombatRoomTrigger.sv_createAreaTrigger( self )
    self.sv.areaTrigger = sm.areaTrigger.createBox( self.sv.saved.node.scale / 2, self.sv.saved.node.position, self.sv.saved.node.rotation, sm.areaTrigger.filter.character )
    self.sv.areaTrigger:bindOnEnter( "sv_e_onEnter", self )
end

function CombatRoomTrigger.sv_e_onEnter( self, trigger, results )
    if not TriggerResultContainsAnyPlayer( results ) or CombatRoomManager.Sv_IsRoomActive( self.sv.saved.roomName..self.sv.tileStorageKey ) then
		return
	end

    if self.sv.node == nil then
        self:sv_tryGetNode()
    end

    if self.sv.node then
        local triggerParams = {}
        triggerParams.position = self.sv.node.position
        self.sv.node.params.world = self.scriptableObject.world
        self.sv.node.params.roomNameTag = self.sv.saved.roomName..self.sv.tileStorageKey
        if not CombatRoomManager.Sv_IsRoomActive( self.sv.node.params.roomNameTag ) then
            CombatRoomManager.Sv_ActivateCombatRoom( self.sv.node, triggerParams )
        end
    else
        sm.log.warning( "No combat room node was found in adjecent cells. Combat room encounter will not begin" )
    end
end

function CombatRoomTrigger.sv_tryGetNode( self )
    if self.sv.node == nil then
        local matchingNode = nil
        local xMin, xMax, yMin, yMax = GetTileRanges( self.sv.saved.node.position, self.scriptableObject.world.id )
        local breakAll = false
        for  x = xMin, xMax  do
			for y = yMin, yMax do
                local cellNodes = sm.cell.getNodesByTag( x, y, "GROWLAB_COMBAT_ROOM", self.scriptableObject.world )
                for _, node in ipairs( cellNodes ) do
                    if node.params.roomName == self.sv.saved.roomName then
                        matchingNode = node
                        breakAll = true
                    end
                    if breakAll then break end
                end
                if breakAll then break end
            end
            if breakAll then break end
        end
        if matchingNode then
            self.sv.node = matchingNode
        end
    end
end