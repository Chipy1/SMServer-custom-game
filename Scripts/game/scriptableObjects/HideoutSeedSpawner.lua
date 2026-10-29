HideoutSeedSpawner = class()
HideoutSeedSpawner.isSaveObject = true

local SpawnFrequency = math.floor( DAYCYCLE_TIME_TICKS * 1.0 ) -- one seed bag every day
local UpdateFrequency = math.floor( DAYCYCLE_TIME_TICKS * 0.1 ) -- check to see if we can spawn it 10 times a day
local MinAmount = 1
local MaxAmount = 5

local SeedsList = {
    obj_seed_tomato,
    obj_seed_carrot,
    obj_seed_redbeet,
}

local seedBoundingBoxOffset = sm.vec3.new( -0.25, 0.25, 0 )

function HideoutSeedSpawner.server_onCreate( self )
    self.sv = {}
    self.sv.tickCounter = 0
    self.sv.saved = self.storage:load()
    if self.sv.saved == nil then
        self.sv.saved = {}
        self.sv.saved.lastSpawnTick = sm.game.getServerTick()
        if self.params then
            self.sv.saved.node = self.params.node
        end
        self.storage:save( self.sv.saved )
    end

    if self.sv.saved.node.scale.x > self.sv.saved.node.scale.y then
        self.sv.spawnOffsets = {
            self.sv.saved.node.position - self.sv.saved.node.rotation * sm.vec3.new( self.sv.saved.node.scale.x / 2 - 0.5, 0, 0 ),
            self.sv.saved.node.position - self.sv.saved.node.rotation * sm.vec3.new( self.sv.saved.node.scale.x / 2 - 1, 0, 0 ),
            self.sv.saved.node.position,
            self.sv.saved.node.position + self.sv.saved.node.rotation * sm.vec3.new( self.sv.saved.node.scale.x / 2 - 1, 0, 0 ),
            self.sv.saved.node.position + self.sv.saved.node.rotation * sm.vec3.new( self.sv.saved.node.scale.x / 2 - 0.5, 0, 0 )
        }
    else
        self.sv.spawnOffsets = {
            self.sv.saved.node.position - self.sv.saved.node.rotation * sm.vec3.new( 0, self.sv.saved.node.scale.y / 2 - 0.35, 0 ),
            self.sv.saved.node.position - self.sv.saved.node.rotation * sm.vec3.new( 0, self.sv.saved.node.scale.y / 2 - 0.85, 0 ),
            self.sv.saved.node.position,
            self.sv.saved.node.position + self.sv.saved.node.rotation * sm.vec3.new( 0, self.sv.saved.node.scale.y / 2 - 0.85, 0 ),
            self.sv.saved.node.position + self.sv.saved.node.rotation * sm.vec3.new( 0, self.sv.saved.node.scale.y / 2 - 0.35, 0 )
        }
    end
    self.sv.cellX, self.sv.cellY = getCell( self.sv.saved.node.position.x, self.sv.saved.node.position.y )
end

function HideoutSeedSpawner.server_onFixedUpdate( self )
    
    self.sv.tickCounter = self.sv.tickCounter + 1
    if self.sv.tickCounter >= UpdateFrequency then
        if self.scriptableObject.world:isCellLoadedServer( self.sv.cellX, self.sv.cellY ) then
            if self:sv_shouldSpawnSeeds() then
                self:sv_spawnSeeds()
            end
        end
        self.sv.tickCounter = 0
    end
end

function HideoutSeedSpawner.sv_shouldSpawnSeeds( self )
    return sm.game.getServerTick() - self.sv.saved.lastSpawnTick >= SpawnFrequency
end

function HideoutSeedSpawner.sv_spawnSeeds( self )
    local diff = sm.game.getServerTick() - self.sv.saved.lastSpawnTick
    local daysPassed = math.min( math.floor( diff / SpawnFrequency ), 5 )
    local spawned = false
    local acceptedSpawnPositions = {}
    for _,spawnPos in ipairs( self.sv.spawnOffsets ) do
        local shapesInSphere = sm.physics.getShapeContactsInSphere( spawnPos, 0.17 )
        if #shapesInSphere == 0 then
            acceptedSpawnPositions[#acceptedSpawnPositions+1] = spawnPos
        end
    end
    for _ = 1, daysPassed do
        if #acceptedSpawnPositions == 0 then
            break
        end
        local randomPositionIndex = math.random( 1, #acceptedSpawnPositions )
        local spawnPos = acceptedSpawnPositions[randomPositionIndex]
        table.remove( acceptedSpawnPositions, randomPositionIndex )
        local lootUid = SeedsList[math.random( 1, math.min( #SeedsList, ProgressionManager.Sv_GetSeedTier() ) )]

        local rot_x_90 = sm.quat.new( 0.707107, 0, 0, 0.707107 )
        local randomRotAngle = math.random( 0, 359 )
        local randomRot = sm.quat.fromEuler( sm.vec3.new( 0, randomRotAngle, 0 ) )
        local rotationOffsetFix = sm.quat.fromEuler( sm.vec3.new( 0, 0, randomRotAngle ) ) * seedBoundingBoxOffset
        local randomOffset = sm.vec3.new( ( math.random() * 2 - 1 ) * 0.05, ( math.random() * 2 - 1 ) * 0.05, 0 )
        local finalSpawnPos = spawnPos - sm.vec3.new( 0, 0, self.sv.saved.node.scale.z / 2 ) + rotationOffsetFix + randomOffset
        local part = sm.shape.createPart( lootUid, finalSpawnPos, rot_x_90 * randomRot, false )
        part.stackedAmount = math.random( MinAmount, MaxAmount )
        spawned = true
    end
    if spawned then
        self.sv.saved.lastSpawnTick = sm.game.getServerTick()
        self.storage:save( self.sv.saved )
    end
end