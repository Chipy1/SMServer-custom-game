SurpriseSpawnerHarvestable = class( nil )
SurpriseSpawnerHarvestable.poseWeightCount = 1

local ProximitySpawnRange = 4.0

function SurpriseSpawnerHarvestable.server_onCreate( self )
    self.sv = {}
    self.sv.saved = self.storage:load()
    if self.sv.saved == nil then
        self.sv.saved = {}
        self.sv.saved.activated = false
        self.sv.saved.spawnTickCounter = 0
        self.sv.saved.effectTickCounter = 0
        if self.params then
            self.sv.saved.spawnEventName = self.params.spawnEventName
            self.sv.saved.spawnDelayTicks = math.floor( self.params.spawnDelaySeconds * 40 )
            self.sv.saved.effectDelayTicks = math.floor( self.params.effectDelaySeconds * 40 )
            self.sv.saved.keyTag = self.params.keyTag
            self.sv.saved.reactive = self.sv.saved.spawnEventName == nil or self.sv.saved.spawnEventName == ""
            if self.params.keyTag ~= nil and self.params.keyTag ~= "" then
                local tileStorageKey = TileStorageManager.Sv_GetTileStorageKeyFromObject( self.harvestable )
                local value = TileStorageManager.Sv_GetValueInSubTable( tileStorageKey, SURPRISE_SPAWNER_TABLE, self.params.keyTag ) or {}
                value[#value+1] = self.harvestable
                TileStorageManager.Sv_SetValueInSubTable( tileStorageKey, SURPRISE_SPAWNER_TABLE, self.params.keyTag, value )
            end
            self.storage:save( self.sv.saved )
        end
    end

    if self.sv.saved.spawnTickCounter >= self.sv.saved.spawnDelayTicks and self.sv.saved.effectTickCounter >= self.sv.saved.effectDelayTicks and self.sv.saved.activated then
        self.sv.done = true
        self.network:setClientData( self.sv.done )
    end
end

function SurpriseSpawnerHarvestable.server_onDestroy( self )
    if self.sv.proximityTrigger then
        self.sv.proximityTrigger:destroy()
        self.sv.proximityTrigger = nil
    end
end

function SurpriseSpawnerHarvestable.sv_e_activate( self )
    self.sv.saved.activated = true
    self.storage:save( self.sv.saved )
end

function SurpriseSpawnerHarvestable.server_onUnload( self )
    self.storage:save( self.sv.saved )
end

function SurpriseSpawnerHarvestable.server_onProjectile( self, hitPos, hitTime, hitVelocity, projectileName, attacker, damage )
    if not self.sv.saved.activated and self.data.destroy then
        self.sv.saved.spawnTickCounter = self.sv.saved.spawnDelayTicks
        self:sv_e_activate()
    end
end

function SurpriseSpawnerHarvestable.server_onMelee( self, hitPos, attacker, damage )
    if not self.sv.saved.activated and self.data.destroy then
        self.sv.saved.spawnTickCounter = self.sv.saved.spawnDelayTicks
        self:sv_e_activate()
    end
end

function SurpriseSpawnerHarvestable.server_onFixedUpdate( self )
    if self.sv.saved.activated and not self.sv.done then
        if self.sv.saved.spawnTickCounter == self.sv.saved.spawnDelayTicks then
            if self.sv.saved.reactive then
                local myPos = self.harvestable.worldPosition
                local closestNode = nil
                local cellX = math.floor( myPos.x / 64 )
                local cellY = math.floor( myPos.y / 64 )
                local closestDistance = ProximitySpawnRange * ProximitySpawnRange
                for x = cellX - 1, cellX + 1 do
                    for y = cellY - 1, cellY + 1 do
                        local nodes = sm.cell.getNodesByTag( x, y,  "SPAWNABLE_UNIT")
                        if nodes then
                            for _,node in ipairs( nodes ) do
                                local nodePos = node.position
                                local distance = ( nodePos - myPos ):length2()
                                if distance < closestDistance then
                                    closestDistance = distance
                                    closestNode = node
                                end
                            end
                        end
                    end
                end
                if closestNode then
                    sm.event.sendToWorld( self.harvestable:getWorld(), "sv_e_spawnNodeUnit", { node = closestNode } )
                end
            elseif self.sv.saved.spawnEventName ~= nil and self.sv.saved.spawnEventName ~= "" then
                NodeSpawnManager.Sv_ActivateSpawnTrigger( self.sv.saved.spawnEventName, self.harvestable:getWorld() )
            end
        end
        if self.sv.saved.effectTickCounter == self.sv.saved.effectDelayTicks then
            sm.effect.playEffect( self.data.effect, self.harvestable.worldPosition, sm.vec3.zero(), self.harvestable.worldRotation, nil, { Color = self.harvestable:getColor()} )
            self.network:setClientData( true )
        end

        if self.sv.saved.spawnTickCounter >= self.sv.saved.spawnDelayTicks and self.sv.saved.effectTickCounter >= self.sv.saved.effectDelayTicks then
            self.sv.done = true
        end
        self.sv.saved.spawnTickCounter = self.sv.saved.spawnTickCounter + 1
        self.sv.saved.effectTickCounter = self.sv.saved.effectTickCounter + 1
    elseif self.sv.done and self.data.destroy then
        local tileStorageKey = TileStorageManager.Sv_GetTileStorageKeyFromObject( self.harvestable )
        local value = TileStorageManager.Sv_GetValue( tileStorageKey, self.sv.saved.keyTag ) or {}
        for index,harvestable in ipairs( value ) do
            if harvestable == self.harvestable then
                table.remove( value, index )
                break
            end
        end
        TileStorageManager.Sv_SetValue( tileStorageKey, self.sv.saved.keyTag, value )
        self.harvestable:destroy()
    end
end

-- Client

function SurpriseSpawnerHarvestable.client_onClientDataUpdate( self, data )
    self.harvestable:setPoseWeight( 0, 1 )
end
















