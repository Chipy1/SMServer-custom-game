
MineralCluster = class( nil )

local Effects = {
    ["blue1"] = "Babywoc - Despawn",
    ["blue2"] = "Babywoc - Despawn",
    ["blue3"] = "Babywoc - Despawn",
    ["purple1"] = "Babywoc - Despawn",
    ["purple2"] = "Babywoc - Despawn",
    ["purple3"] = "Babywoc - Despawn",
    ["red1"] = "Babywoc - Despawn",
    ["red2"] = "Babywoc - Despawn",
    ["red3"] = "Babywoc - Despawn"
}

function MineralCluster.server_onCreate( self )
    self.sv = {}
    self.sv.destructionTime = 2.0
    self.sv.destructionCounter = 0.0
    if self.data then
        self.sv.clusterColor = self.data.clusterColor
    else
        self.sv.clusterColor = "blue"
    end
    self.harvestable.publicData = { drillLevel = 1 }
end

function MineralCluster.sv_e_plasmaDrill( self, params )
    self.sv.destructionCounter = self.sv.destructionCounter + params.progress
    if self.sv.destructionCounter >= self.sv.destructionTime then
        self.sv.destructionCounter = 0
        sm.effect.playEffect( Effects[self.sv.clusterColor], self.harvestable:getPosition(), nil, self.harvestable:getRotation(), nil, {} )
        self.harvestable:destroy()
    end
end












