
AutoDoorDisplay = class( nil )

function AutoDoorDisplay.server_onCreate( self )
    self.sv = {}
    self.sv.saved = self.storage:load()
    if self.sv.saved == nil then
        self.sv.saved = {}
        self.sv.saved.keyTag = self.params.keyTag
        self.sv.saved.destroyedLocks = 0
        self.storage:save( self.sv.saved )
    end
    self.sv.tileStorageKey = TileStorageManager.Sv_GetTileStorageKeyFromObject( self.harvestable )
    self.network:setClientData( { visibleSubmesh = self.sv.saved.destroyedLocks } )
end

function AutoDoorDisplay.server_onFixedUpdate( self )
    if self.sv.saved.destroyedLocks ~= 3 then
        if self.sv.tileStorageKey == nil then
            self.sv.tileStorageKey = TileStorageManager.Sv_GetTileStorageKeyFromObject( self.harvestable )
            return
        end
        local brokenLockCount = TileStorageManager.Sv_GetValueInSubTable( self.sv.tileStorageKey, KEY_LOCK_COUNTER_TABLE, self.sv.saved.keyTag )
        if brokenLockCount then
            if brokenLockCount ~= self.sv.saved.destroyedLocks then
                self.sv.saved.destroyedLocks = brokenLockCount
                self.network:setClientData( { visibleSubmesh = self.sv.saved.destroyedLocks } )
                self.storage:save( self.sv.saved )
            end
        end
    end
end

function AutoDoorDisplay.client_onClientDataUpdate( self, data )
    local show0 = data.visibleSubmesh == 0
    local show1 = data.visibleSubmesh == 1
    local show2 = data.visibleSubmesh == 2
    local show3 = data.visibleSubmesh == 3

	self.harvestable:setSubMeshVisible( "m_screen0", show0 )
	self.harvestable:setSubMeshVisible( "m_screen1", show1 )
	self.harvestable:setSubMeshVisible( "m_screen2", show2 )
	self.harvestable:setSubMeshVisible( "m_screen3", show3 )
end