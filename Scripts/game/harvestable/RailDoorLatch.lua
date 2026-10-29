
RailDoorLatch = class( nil )

local SpeedMultiplier = 5

function RailDoorLatch.server_onCreate( self )
    self.sv = {}
    self.sv.saved = self.storage:load()
    if self.sv.saved == nil then
        self.sv.saved = {}
        self.sv.saved.keyTag = self.params.keyTag
        self.storage:save( self.sv.saved )
    end
    self.sv.lastProgress = 0.0
    self.sv.lastDirection = 0
    self:sv_tryGetDoor()
end

function RailDoorLatch.sv_tryGetDoor( self )
    if g_tileStorageManager then
		self.sv.tileStorageKey = TileStorageManager.Sv_GetTileStorageKeyFromObject( self.harvestable )
        local group = TileStorageManager.Sv_GetValueInSubTable( self.sv.tileStorageKey, KINEMATIC_SPINNER_DOOR_TABLE, self.sv.saved.keyTag )
        if SafeGetExist( group, "door" ) then
            self.sv.door = group.door
            self.network:setClientData( self.sv.door )
        end
	end
end

function RailDoorLatch.server_onFixedUpdate( self )
    if not self.sv.door then
        self:sv_tryGetDoor()
    end
end

-- Client

function RailDoorLatch.client_onCreate( self )
    self.cl = {}
    self.cl.counter = 0
    self.cl.effect = sm.effect.createEffect( "Growlab - Kinematicspindoorchain", self.harvestable )
    self.cl.speed = 0.0
end

function RailDoorLatch.client_onDestroy( self )
    self.cl.effect:destroy()
end

function RailDoorLatch.client_onUpdate( self, dt )
    if self.cl.door and self.cl.door.clientPublicData then
        if self.cl.speed ~= self.cl.door.clientPublicData.speed then
            self.cl.speed = self.cl.door.clientPublicData.speed
            if self.cl.speed == 0.0 then
                self.cl.effect:stopBreakSustain()
            elseif not self.cl.effect:isPlaying() then
                self.cl.effect:start()
            end
            if self.cl.effect:isPlaying() then
                local soundVelocity = 0
                local currentSpeed = self.cl.speed
                soundVelocity = clamp( math.abs( currentSpeed ) / 50, 0.0, 1.0 )
                self.cl.effect:setParameter( "velocity", soundVelocity )
            end
        end
        self.cl.counter = self.cl.counter + dt * SpeedMultiplier * self.cl.door.clientPublicData.speed
        self.harvestable:setUvFrameIndex( math.floor( self.cl.counter ) )
    end
end

function RailDoorLatch.client_onClientDataUpdate( self, data )
    self.cl.door = data
end