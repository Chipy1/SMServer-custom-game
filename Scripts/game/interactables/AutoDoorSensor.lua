AutoDoorSensor = class( nil )
AutoDoorSensor.maxParentCount = 1
AutoDoorSensor.maxChildCount = 0
AutoDoorSensor.connectionInput = sm.interactable.connectionType.logic
AutoDoorSensor.connectionOutput = sm.interactable.connectionType.none

local SensorUvFrequency = 0.1

function AutoDoorSensor.server_onCreate( self )
    self.sv = {}
    self.sv.parentActive = false
end

function AutoDoorSensor.server_onFixedUpdate( self )
    local parent = self.interactable:getSingleParent()
    if parent and parent:isActive() ~= self.sv.parentActive then
        self.sv.parentActive = parent:isActive()
        self.network:setClientData( self.sv.parentActive )
    end
end

-- Client

function AutoDoorSensor.client_onCreate( self )
    self.cl = {}
    self.cl.counter = 0
    self.cl.uvMin = 0
    self.cl.uvMax = 9
    self.cl.isOpen = false
    self.cl.currentUvIndex = 0
end

function AutoDoorSensor.cl_swapUv( self )
    if not self.cl.isOpen then
        self.cl.uvMin = 0
        self.cl.uvMax = 9
        self.cl.currentUvIndex = 0
    else
        self.cl.uvMin = 10
        self.cl.uvMax = 19
        self.cl.currentUvIndex = 10
    end
end

function AutoDoorSensor.client_onUpdate( self, dt )
    self.cl.counter = self.cl.counter + dt
    if self.cl.counter >= SensorUvFrequency then
        self.cl.currentUvIndex = self.cl.currentUvIndex + 1
        if self.cl.currentUvIndex > self.cl.uvMax then
            self.cl.currentUvIndex = self.cl.uvMin
        end
        self.interactable:setUvFrameIndex( self.cl.currentUvIndex )
        self.cl.counter = 0
    end
end

function AutoDoorSensor.client_onClientDataUpdate( self, isOpen )
    if self.cl.isOpen ~= isOpen then
        self.cl.isOpen = isOpen
        self:cl_swapUv()
    end
end