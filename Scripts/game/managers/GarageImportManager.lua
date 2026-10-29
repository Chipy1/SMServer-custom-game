dofile( "$SURVIVAL_DATA/Scripts/game/survival_constants.lua" )
GarageImportManager = class( nil )

-- Server
function GarageImportManager.server_onCreate( self )
    g_garageImportManagerServer = self
    self.sv = {}
    self.sv.saved = sm.storage.load( STORAGE_CHANNEL_GARAGE_IMPORT_MANAGER )
    if self.sv.saved == nil then
        self.sv.saved = {}
    end
    if self.sv.saved.containers ~= nil then
        self.network:setClientData( self.sv.saved.containers )
    end
end

function GarageImportManager.Sv_AssignContainers( garageId, containers )
    if not g_garageImportManagerServer then
        print( "GarageImportManager not initialized yet" )
        return
    end
    sm.event.sendToScriptableObject( g_garageImportManagerServer.scriptableObject, "sv_e_assignContainers", { garageId = garageId, garageContainers = containers } )
end

function GarageImportManager.sv_e_assignContainers( self, params )
    if not self.sv.saved.containers then
        self.sv.saved.containers = {}
    end
    self.sv.saved.containers[params.garageId] = params.garageContainers
    sm.storage.save( STORAGE_CHANNEL_GARAGE_IMPORT_MANAGER, self.sv.saved )
    self.network:setClientData( self.sv.saved.containers )
end

function GarageImportManager.Sv_GetContainers(garageId)
    return g_garageImportManagerServer:sv_getContainers(garageId)
end

function GarageImportManager.sv_getContainers( self,garageId )
    return self.sv.saved.containers[garageId]
end

-- Client
function GarageImportManager.client_onCreate( self )
    g_garageImportManagerClient = self
    self.cl = {}
    self.cl.containers = {}
end

function GarageImportManager.client_onClientDataUpdate( self, containers )
    self.cl.containers = containers
end

function GarageImportManager.Cl_GetContainers(garageId)
    return g_garageImportManagerClient:cl_getContainers(garageId)
end

function GarageImportManager.cl_getContainers( self,garageId )
    return self.cl.containers[garageId]
end


