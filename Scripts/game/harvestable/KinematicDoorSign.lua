KinematicDoorSign = class( nil )

function KinematicDoorSign.server_onCreate( self )
    self.sv = {}
    self.sv.saved = self.storage:load()
    if self.sv.saved == nil then
        self.sv.saved =  {}
        self.sv.saved.keyTag = self.params.keyTag
        self.sv.saved.keyCount = self.params.keyCount
        self.sv.saved.kinematicEventTrigger = self.params.kinematicEventTrigger
        self.sv.saved.open = false
        self.storage:save( self.sv.saved )
    end

    
    self.network:setClientData( { open = self.sv.saved.open }, 2 )
    

    self.sv.tileStorageKey = TileStorageManager.Sv_GetTileStorageKeyFromObject( self.harvestable )
    if self.sv.saved.keyCount == 0 then
        local group = TileStorageManager.Sv_GetValueInSubTable( self.sv.tileStorageKey, KINEMATIC_SPINNER_DOOR_TABLE, self.sv.saved.keyTag )
        group = SafeSet( group, "sign", self.harvestable )
        if SafeGetExist( group, "door" ) then
            self.network:setClientData( { door = group.door }, 1 )
        end
        TileStorageManager.Sv_SetValueInSubTable( self.sv.tileStorageKey, KINEMATIC_SPINNER_DOOR_TABLE, self.sv.saved.keyTag, group )
    end
end

function KinematicDoorSign.sv_e_receiveDoor( self, door )
    if self.sv.saved.keyCount == 0 then
        self.network:setClientData( { door = door }, 1 )
    end
end

function KinematicDoorSign.server_onFixedUpdate( self )
    if self.sv.saved.keyCount and self.sv.saved.keyCount > 0 and not self.sv.saved.open then
        local keyCount = TileStorageManager.Sv_GetValueInSubTable( self.sv.tileStorageKey, KEY_LOCK_COUNTER_TABLE, self.sv.saved.keyTag )
        if keyCount and keyCount >= self.sv.saved.keyCount then
            self.sv.saved.open = true
            if self.sv.saved.kinematicEventTrigger and self.sv.saved.kinematicEventTrigger ~= "" then
                KinematicManager.Sv_Activate( self.sv.tileStorageKey, self.sv.saved.kinematicEventTrigger )
            end
            self.network:setClientData( { open = self.sv.saved.open }, 2 )
            self.storage:save( self.sv.saved )
        end
    end
end

function KinematicDoorSign.client_onCreate( self )
    self.cl = {}
    self.cl.connectedDoor = nil
    self.cl.isOpen = false
    self.cl.doorEffect = sm.effect.createEffect( "Growlab - DoorActive", self.harvestable )
end

function KinematicDoorSign.client_onFixedUpdate( self )
    if self.cl.connectedDoor and sm.exists( self.cl.connectedDoor ) then
        if self.cl.connectedDoor.clientPublicData then
            if self.cl.connectedDoor.clientPublicData.open ~= nil and self.cl.connectedDoor.clientPublicData.open ~= self.cl.isOpen then
                self.cl.isOpen = self.cl.connectedDoor.clientPublicData.open
                self:cl_swapUv( self.cl.isOpen )
            elseif self.cl.connectedDoor.clientPublicData.unlocked ~= nil and self.cl.connectedDoor.clientPublicData.unlocked ~= self.cl.isOpen then
                self.cl.isOpen = self.cl.connectedDoor.clientPublicData.unlocked
                self:cl_swapUv( self.cl.isOpen )
            end
        end
    end
end

function KinematicDoorSign.cl_swapUv( self, state )
    self.harvestable:setSubMeshVisible( "m_screen0", state )
	self.harvestable:setSubMeshVisible( "m_screen1", not state )

    if state and not self.cl.doorEffect:isPlaying() then
        self.cl.doorEffect:start()
    elseif not state and self.cl.doorEffect:isPlaying() then
        self.cl.doorEffect:stop()
    end
end

function KinematicDoorSign.client_onClientDataUpdate( self, data, channel )
    if channel == 1 then
        if sm.exists( data.door ) then
            self.cl.connectedDoor = data.door
        end
    elseif channel == 2 then
        self.cl.isOpen = data.open
        self:cl_swapUv( self.cl.isOpen )
    end
end

function KinematicDoorSign.client_onDestroy( self )
	self.cl.doorEffect:destroy()
end
