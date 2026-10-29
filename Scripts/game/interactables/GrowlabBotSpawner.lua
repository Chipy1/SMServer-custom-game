dofile( "$SURVIVAL_DATA/Scripts/game/survival_items.lua" )

GrowlabBotSpawner = class( nil )

local TetherOffsetDistance = 15

function GrowlabBotSpawner.server_onCreate( self )
    self.sv = {}
    self.sv.saved = self.storage:load()
    self.sv.tileStorageKey = TileStorageManager.Sv_GetTileStorageKeyFromObject( self.interactable )
    if self.sv.saved == nil then
        self.sv.saved = {}
        self.sv.saved.spawnInfo = {}
        if self.params then
            if self.params.spawnerIndex ~= nil and self.params.roomName and self.params.roomName ~= "" then
                local value = TileStorageManager.Sv_GetValue( self.sv.tileStorageKey, "combatroom"..self.params.roomName..self.sv.tileStorageKey ) or { spawners = {} }
                value.spawners[self.params.spawnerIndex] = self.interactable
                TileStorageManager.Sv_SetValue( self.sv.tileStorageKey, "combatroom"..self.params.roomName..self.sv.tileStorageKey, value )
            end
        end
        self.sv.saved.roomName = self.params.roomName..self.sv.tileStorageKey
        self.sv.saved.spawnerIndex = self.params.spawnerIndex
        self.storage:save( self.sv.saved )
    end
    self.sv.tickCounter = 0
    local shapeOffset = sm.item.getShapeOffset( self.shape.uuid ).y
    local directionOffset = self.shape.up * ( shapeOffset * 2 ) + sm.vec3.new( 0, 0, -1. )
    if self.shape.uuid == obj_survivalobject_platformspawner then
        directionOffset = self.shape.up
    end
    self.sv.spawnPosition = self.shape.worldPosition + directionOffset
    self.sv.spawnDirection = self.shape.worldRotation * sm.vec3.new( 0, 0, 1 )
    self.sv.yaw = math.atan2( self.sv.spawnDirection.y, self.sv.spawnDirection.x ) - math.pi / 2

    if not IsEmptyTable( self.sv.saved.spawnInfo ) then
        self:sv_spawnFromStart()
    end
end

function GrowlabBotSpawner.server_onMelee( self, hitPos, attacker, _, _, hitDirection )
    if type( attacker ) == "Player" then
        self.network:sendToClients( "cl_n_onHit" )
    end
end

function GrowlabBotSpawner.sv_e_setEncounterActive( self, state )
    self.network:setClientData( state )
    self.storage:save( self.sv.saved )
end

function GrowlabBotSpawner.sv_e_spawn( self, spawnInfo )
    if self.sv.saved.spawnInfo == nil then
        self.sv.saved.spawnInfo = {}
    end
    self.sv.saved.spawnInfo[#self.sv.saved.spawnInfo+1] = spawnInfo
    self.network:sendToClients( "cl_n_startSpawn", { spawnInfo = self.sv.saved.spawnInfo, tick = sm.game.getServerTick() } )
    self.storage:save( self.sv.saved )
end

function GrowlabBotSpawner.sv_spawnFromStart( self )
    self.network:sendToClients( "cl_n_startSpawn", { spawnInfo = self.sv.saved.spawnInfo, tick = sm.game.getServerTick() } )
end

function GrowlabBotSpawner.sv_n_spawnEnemy( self )
    local spawnParams = {}
    local tetherPositionOffset = self.sv.spawnDirection * TetherOffsetDistance
    tetherPositionOffset.z = 0
    spawnParams.tetherPoint = self.sv.spawnPosition + tetherPositionOffset
    spawnParams.aggressive = true
    spawnParams.combatRoomName = self.sv.saved.roomName

	local pubData = sm.world.getCurrentWorld().publicData
	local worldType = pubData and pubData.type
	if worldType == "DungeonWorld" then
		spawnParams.lootType = "growlab"
	elseif worldType == "WarehouseWorld" then
		spawnParams.lootType = "warehouse"
	elseif worldType == "UndergroundWorld" then
		spawnParams.lootType = "underground"
	end

	if self.sv.saved.spawnInfo[1] then
    	local unit = sm.unit.createUnit( sm.uuid.new( self.sv.saved.spawnInfo[1].uuid ), self.sv.spawnPosition, self.sv.yaw, spawnParams )
		CombatRoomManager.Sv_RegisterEnemy( self.sv.saved.roomName, unit.id, self.sv.saved.spawnInfo[1].uuid, self.sv.saved.spawnerIndex )
		self.sv.saved.spawnInfo[1].counter = self.sv.saved.spawnInfo[1].counter + 1
		if self.sv.saved.spawnInfo[1].counter == self.sv.saved.spawnInfo[1].amount then
			table.remove( self.sv.saved.spawnInfo, 1 )
		end
		self.storage:save( self.sv.saved )
	end
end

-- Client

function GrowlabBotSpawner.client_onCreate( self )
    self.cl = {}
    self.cl.animations = {}
	self.cl.animations["Idle"] = self:cl_createAnimation( "idle", true, nil )
	self.cl.animations["Telegraph"] = self:cl_createAnimation( "telegraph", false, "Spawn" )
	self.cl.animations["Spawn"] = self:cl_createAnimation( "spawn", false, "Idle" )

	self.cl.hitAnimation = self:cl_createAnimation( "on_hit", false, nil )
    self.cl.spawnData = {}
    self.cl.current = {}
    self.cl.active = false
    self.cl.spawnEffectName = self.shape.uuid == obj_survivalobject_platformspawner and "Minidungeon - Botspawner02" or "Minidungeon - Botspawner01"
end

function GrowlabBotSpawner.client_onClientDataUpdate( self, startEncounter )
    self.cl.active = startEncounter
    if startEncounter then
        if IsEmptyTable( self.cl.spawnData ) then
            self:cl_setAnimation( self.cl.animations["Idle"], 0.0 )
        else
            self:cl_setAnimation( self.cl.animations["Telegraph"], 0.0 )
        end
    else
        self:cl_unsetAnimations()
    end
end

function GrowlabBotSpawner.cl_n_onHit( self )
    if self.cl.active then
        self.cl.hitAnimation.isActive = true
        self.cl.hitAnimation.playProgress = 0.0
        sm.effect.playEffect( "Minidungeon - BotspawnerHit", self.shape.worldPosition, nil, self.shape.worldRotation )
    end
end

function GrowlabBotSpawner.cl_n_startSpawn( self, data )
    if IsEmptyTable( self.cl.spawnData ) then
        local missedTicks = sm.game.getCurrentTick() - data.tick
        local missedSeconds =  missedTicks / 40
        if missedSeconds > self.cl.animations["Telegraph"].playTime then
            missedSeconds =  missedSeconds - self.cl.animations["Telegraph"].playTime
            local spawnAmount = 0
            for _, spawnData in ipairs( data.spawnInfo ) do
                spawnAmount = spawnAmount + spawnData.amount
            end
            local missedAnimations = missedSeconds / self.cl.animations["Spawn"].playTime

            if missedAnimations > spawnAmount then
                self:cl_setAnimation( self.cl.animations["Idle"],  0.0 )
            else
                self:cl_setAnimation( self.cl.animations["Spawn"], missedAnimations - math.floor( missedAnimations ) )
                local missedSpawnCount = round( missedAnimations )

                while missedSpawnCount > 0 and #data.spawnInfo > 0 do
                    if data.spawnInfo[1].amount > missedSpawnCount then
                        data.spawnInfo[1].amount = data.spawnInfo[1].amount - missedSpawnCount
                        missedSpawnCount = 0
                    else
                        missedSpawnCount = missedSpawnCount - data.spawnInfo[1].amount
                        table.remove( data.spawnInfo, 1 )
                    end
                end
            end
        else
            self:cl_setAnimation( self.cl.animations["Telegraph"], missedSeconds / self.cl.animations["Telegraph"].playTime )
        end
        self.cl.spawnDone = false
        self.cl.effectActivated = false
        self.cl.current = data.spawnInfo[1]
    end
    self.cl.spawnData = data.spawnInfo
end

function GrowlabBotSpawner.client_onUpdate( self, dt )
    if self.cl.active then
        self:cl_updateAnimations( dt )
    end
end

function GrowlabBotSpawner.cl_createAnimation( self, name, looping, nextAnimation )
	local animation =
	{
		name = name,
		playProgress = 0.0,
		playTime = self.interactable:getAnimDuration( name ),
        looping = looping,
		nextAnimation = nextAnimation
	}
	return animation
end

function GrowlabBotSpawner.cl_setAnimation( self, animation, playProgress )
	self:cl_unsetAnimations()
	animation.isActive = true
	animation.playProgress = playProgress
	self.interactable:setAnimEnabled( animation.name, true )
end

function GrowlabBotSpawner.cl_unsetAnimations( self )
	for name, animation in pairs( self.cl.animations ) do
		animation.isActive = false
		animation.playProgress = 0.0
		self.interactable:setAnimEnabled( animation.name, false )
		self.interactable:setAnimProgress( animation.name, animation.playProgress )
	end
end

function GrowlabBotSpawner.cl_updateAnimations( self, dt )
    for _, animation in pairs( self.cl.animations ) do
		self:cl_updateAnimation( animation, dt )
	end
    self:cl_updateAnimation( self.cl.hitAnimation, dt )
end

function GrowlabBotSpawner.cl_updateAnimation( self, animation, dt )
	if animation.isActive then
		self.interactable:setAnimEnabled( animation.name, true )
        animation.playProgress = animation.playProgress + dt / animation.playTime

        if animation.name == "spawn" then
            if animation.playProgress > 0.3 and not  self.cl.effectActivated then
                self.cl.effectActivated = true
                sm.effect.playEffect( self.cl.spawnEffectName, self.interactable.shape.worldPosition, sm.vec3.zero(), self.interactable.shape.worldRotation )
            end
            if animation.playProgress > 0.5 and not self.cl.spawnDone then
                if sm.isHost then
                    self.network:sendToServer( "sv_n_spawnEnemy" )
                end
                self.cl.spawnDone = true
                if self.cl.current and self.cl.current.counter then
                    self.cl.current.counter = self.cl.current.counter + 1
                    if self.cl.current.counter >= self.cl.current.amount then
                        table.remove( self.cl.spawnData, 1 )
                    end
                end
            end
        end
            
        if animation.playProgress > 1.0 then
            if animation.looping then
                animation.playProgress = animation.playProgress - 1.0
            else
                if animation.nextAnimation and self.cl.active then
                    self:cl_setAnimation( self.cl.animations[animation.nextAnimation], 0.0 )
                    if animation.name == "spawn" then
                        self.cl.spawnDone = false
                        self.cl.effectActivated = false
                        if self.cl.current.amount > self.cl.current.counter then
                            self:cl_setAnimation( self.cl.animations["Spawn"], 0.0 )
                        elseif #self.cl.spawnData > 0 then
                            self.cl.current = self.cl.spawnData[1]
                            self:cl_setAnimation( self.cl.animations["Spawn"], 0.0 )
                        end
                    end
                    return
                else
                    animation.playProgress = 1.0
                end
            end
        end
        self.interactable:setAnimProgress( animation.name, animation.playProgress )
	end
end