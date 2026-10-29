DrillSpawnerEncounter = class( nil )
DrillSpawnerEncounter.isSaveObject = true

local SphereSamplingAmount = 200
local SphereSamplingRadius = 1.0
local SamplesPerFrame = 5
local GoldenRatio = ( math.sqrt( 5 ) + 1 ) / 2
local RaycastLength = 50
local RaycastFilter = sm.physics.filter.staticBody + sm.physics.filter.voxelTerrain + sm.physics.filter.harvestable + sm.physics.filter.terrainAsset
local VoxelDensityCheckDepth = 1.5
local MinDistanceBetweenSpawnsSqr = 8.0 * 8.0
local SpawnDelayTicks = 2.0 * 40

local PotentialSpawns = {
    { unit_totebot_green, unit_totebot_green, unit_totebot_green },
    { unit_totebot_green, unit_tapebot_green_1 },
	{ unit_totebot_green, unit_tapebot_green_2 },
	{ unit_totebot_green, unit_tapebot_green_3 },
}

function DrillSpawnerEncounter.server_onCreate( self )
    self.sv = {}
    self.sv.saved = self.storage:load() or {}
    self.sv.saved.position = self.sv.saved.position or self.params.position
    self.sv.saved.amount = self.sv.saved.amount or self.params.amount or 1
    self.sv.saved.spawnData = self.sv.saved.spawnData or {}
    self.storage:save( self.sv.saved )

    self.sv.acceptedPoints = {}
    self.sv.pointsTested = 0
    self.sv.combinedRayDistance = 0
    self.sv.spawningDone = false
    self.sv.successfulSpawns = 0
    self.sv.completedSpawns = 0
    self.sv.cellX = math.floor( self.sv.saved.position.x / 64 )
    self.sv.cellY = math.floor( self.sv.saved.position.y / 64 )
end

function DrillSpawnerEncounter.sv_getDirection( self, vObjectCenter, startingIndex )
    local fZ = 1 - ( 2 * startingIndex ) / ( SphereSamplingAmount - 1 );
    local fRadiusAtZ = math.sqrt( 1 - fZ * fZ );
    local fTheta = GoldenRatio * startingIndex;
    local fX = math.cos( fTheta ) * fRadiusAtZ;
    local fY = math.sin( fTheta ) * fRadiusAtZ;

    local vSamplePoint = vObjectCenter + sm.vec3.new( fX, fY, fZ ) * SphereSamplingRadius;
    return ( vSamplePoint - vObjectCenter ):safeNormalize( sm.vec3.new( 0, 0, 1 ) );
end

function DrillSpawnerEncounter.server_onFixedUpdate( self )
    if not self.scriptableObject:getWorld():isCellLoadedServer( self.sv.cellX, self.sv.cellY ) then -- reset spawning if cell unloads
        self.sv.spawningDone = false
        return
    end

    if IsEmptyTable( self.sv.saved.spawnData ) and self.sv.pointsTested < SphereSamplingAmount then -- gather sample points
        for _ = 1, SamplesPerFrame do
            if self.sv.pointsTested < SphereSamplingAmount then
                local direction = self:sv_getDirection( self.sv.saved.position, self.sv.pointsTested )
                self.sv.pointsTested = self.sv.pointsTested + 1
                local hit,result = sm.physics.raycast( self.sv.saved.position, self.sv.saved.position + direction * RaycastLength, nil, RaycastFilter )
                local acceptedHit = hit and result.type == "voxelTerrain"
                if acceptedHit then
                    local densityBehindPoint = self.scriptableObject:getWorld():getWeightedVoxelDensityInWorldPoint( result.pointWorld + direction * VoxelDensityCheckDepth )
                    if densityBehindPoint > 0.5 then
                        local distance = result.fraction * RaycastLength
                        self.sv.combinedRayDistance = self.sv.combinedRayDistance + distance
                        self.sv.acceptedPoints[#self.sv.acceptedPoints+1] = { point = result.pointWorld, distance = distance }
                    else





                        acceptedHit = false
                    end
                end





            end
        end
    elseif IsEmptyTable( self.sv.saved.spawnData ) then -- prune and select points

        local averageDistance = 0
        local pointCount = #self.sv.acceptedPoints
        if pointCount > 0 then
            averageDistance = self.sv.combinedRayDistance / pointCount
        else
            self.scriptableObject:destroy()
            return
        end

        -- prune points that have too big of a difference from average distance
        for i, data in reverse_ipairs( self.sv.acceptedPoints ) do
            if math.abs( data.distance - averageDistance ) >= averageDistance * 0.3 then





                table.remove( self.sv.acceptedPoints, i )
            end
        end
        pointCount = #self.sv.acceptedPoints
        if pointCount == 0 then
            self.scriptableObject:destroy()
            return
        end
        
        local stepping = math.max( math.floor( pointCount / self.sv.saved.amount ), 1 )
        local randomStart = math.random( 1, pointCount )
        local usedIndexes = {}

        local function IsTooClose( point )
            for _,data in ipairs( self.sv.saved.spawnData ) do
                if ( point - data.hitPoint ):length2() < MinDistanceBetweenSpawnsSqr then
                    return true
                end
            end
            return false
        end

        local currentTick = sm.game.getServerTick()

        for i = 0, self.sv.saved.amount - 1 do
            local index = ModuloIndex( randomStart + i * stepping, pointCount )

            local acceptedPoint = true
            if usedIndexes[index] or IsTooClose( self.sv.acceptedPoints[index].point ) then
                acceptedPoint = false
                for offset = 1, pointCount do
                    local testIndex = ModuloIndex( index + offset, pointCount )
                    if not usedIndexes[testIndex] and not IsTooClose( self.sv.acceptedPoints[testIndex].point ) then
                        acceptedPoint = true
                        index = testIndex
                        break
                    end
                end
            end
            if not acceptedPoint then
                break
            end

            local spawnPosition = self.sv.acceptedPoints[index].point
            local direction = ( self.sv.saved.position - spawnPosition ):safeNormalize( sm.vec3.new( 0, 0, 1 ) )
            local destination = spawnPosition
            local units = PotentialSpawns[math.random( 1, #PotentialSpawns )]
            local spawnRotation = sm.vec3.getRotation( sm.vec3.new( 0, 1, 0 ), direction )
            local tickAddition = i * SpawnDelayTicks
            local spawnParams = {
                done = false,
                spawnTick = currentTick + tickAddition,
                hitPoint = spawnPosition,
                position = spawnPosition - direction * 10,
                quat = spawnRotation,
                harvestableParams = { destination = destination, units = units, handler = self.scriptableObject },
            }
            self.sv.saved.spawnData[#self.sv.saved.spawnData+1] = spawnParams
            self.storage:save( self.sv.saved )
            usedIndexes[index] = true
        end
    elseif not self.sv.spawningDone then -- spawn harvestables
        if not self.scriptableObject:getWorld():isCellLoadedServer( self.sv.cellX, self.sv.cellY ) then
            return
        end
        for _,spawnParams in ipairs( self.sv.saved.spawnData ) do
            if not spawnParams.done and sm.game.getServerTick() >= spawnParams.spawnTick then
                spawnParams.done = true
                spawnParams.world = self.scriptableObject:getWorld()
                spawnParams.uuid = kin_drillspawner
                sm.event.sendToWorld( self.scriptableObject:getWorld(), "sv_spawnHarvestable", spawnParams )
                self.sv.successfulSpawns = self.sv.successfulSpawns + 1
            end
        end
        if self.sv.successfulSpawns == #self.sv.saved.spawnData then
            self.sv.spawningDone = true
        end
    end
end

function DrillSpawnerEncounter.sv_e_onDrillSpawnerCompleted( self )
    self.sv.completedSpawns = self.sv.completedSpawns + 1
    if self.sv.completedSpawns >= self.sv.successfulSpawns then
        self.scriptableObject:destroy()
    end
end