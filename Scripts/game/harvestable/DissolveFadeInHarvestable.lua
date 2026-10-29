DissolveFadeInHarvestable = class()

DissolveFadeInHarvestable.poseWeightCount = 3

local FadeInDuration = 1.5

function DissolveFadeInHarvestable.server_onCreate( self )
    self.sv = {}

    if self.params then
        self.network:setClientData( FadeInDuration )
    else
        self.network:setClientData( 0 )
    end
end

function DissolveFadeInHarvestable.client_onCreate( self )
    self.cl = {}

    self.cl.remainingTime = nil
    self.harvestable:setPoseWeight( 2, 0 )
end

function DissolveFadeInHarvestable.server_onRefresh( self )
    self:server_onCreate()
end

function DissolveFadeInHarvestable.client_onClientDataUpdate( self, remainingTime )
    self.cl.remainingTime = remainingTime
end

function DissolveFadeInHarvestable.client_onUpdate( self, dt )
    if self.cl.remainingTime then
        self.cl.remainingTime = self.cl.remainingTime - dt
        
        self.cl.remainingTime = max( 0, self.cl.remainingTime )
        
        local weight = ( 1 - ( self.cl.remainingTime / FadeInDuration ) ) / 2
        self.harvestable:setPoseWeight( 2, weight )
        
        if self.cl.remainingTime == 0 then
            self.cl.remainingTime = nil
        end
    end
end

