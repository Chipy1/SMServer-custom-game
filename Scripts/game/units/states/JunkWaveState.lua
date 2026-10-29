dofile( "$SURVIVAL_DATA/Scripts/game/units/states/BaseState.lua" )

JunkWaveState = class( BaseState )

local ShockwaveUuid = sm.uuid.new( "fad7edde-4a10-4e35-851c-645a42f02a76" )
local StartupDelay = 40 * 0.0
local StompInterval = 40 * 0.5
local StompSpawnDelay = 40 * 1.0
local StompsPerAttack = 1

function JunkWaveState.sv_onCreate( self, unit, isRightSide )
	self.unit = unit
	self.lookDirection = sm.vec3.new( 0, 1, 0 )
	self.worldPosition = sm.vec3.zero()
	self.stageIndex = 1
	self.isRightSide = isRightSide
	self.waveAmount = 1
	self.type = 1
	self.playDialogWeight = 0.0

	self.waitState = self.unit:createState( "wait" )
	self.waitState.debugName = "waitState"
	self.waitState.time = 2.0
	self.waitState.interruptible = false

	self.stompTimer = Timer()
	self.stompSpawnTimer = Timer()
	self.stompSpawnTimer:start( StompSpawnDelay )
	self.stompCount = 0

	self.stompsToSpawn = 0
	self.color = "green"
end

function JunkWaveState.refresh( self ) end

function JunkWaveState.sv_setLookDirection( self, lookDirection )
	self.lookDirection = lookDirection
end

function JunkWaveState.sv_setPosition( self, worldPosition )
	self.worldPosition = worldPosition
end

function JunkWaveState.sv_setTarget( self, target )
	self.target = target
end

function JunkWaveState.sv_setStage( self, stageIndex )
	self.stageIndex = stageIndex
end

function JunkWaveState.sv_updateJunkWave( self )
	if self.stompCount < StompsPerAttack then
		self.stompTimer:tick()
		if self.stompTimer:done() then
			self.stompTimer:start( StompInterval )
			self.unit:sendCharacterEvent( "stomp" )
			self.stompCount = self.stompCount + 1
			self.stompsToSpawn = self.stompsToSpawn + 1
		end
	end
	if self.stompsToSpawn > 0 then
		self.stompSpawnTimer:tick()
		if self.stompSpawnTimer:done() then
			self.stompSpawnTimer:reset()
			self.stompsToSpawn = self.stompsToSpawn - 1

			-- Spawn junk shock wave
			local spawnPos = self.unit.character:getTpBonePos( "root_jnt" )
			if not spawnPos then
				local heightOffset = sm.vec3.new( 0, 0, -1.25 )
				spawnPos = self.unit.character.worldPosition + heightOffset
			else
				spawnPos = spawnPos + sm.vec3.new( 0, 0, 0.8 )
			end
			local params = { position = spawnPos, color = self.color, waveAmount = self.waveAmount or 1 }
			sm.scriptableObject.createScriptableObject( ShockwaveUuid, params, self.unit.character:getWorld() )
			self.waveAmount = 1
		end
	end
end

--[[API functions]]

function JunkWaveState.start( self )
	self.waitState:start()
	self.stompTimer:start( StartupDelay )
	self.stompCount = 0
	if self.type == 1 then
		-- Will play dialog at most every 11th attack (due to exclusive random), and at least every 20th attack.
		self.playDialogWeight = self.playDialogWeight + math.max(0.5, math.random())
		if self.playDialogWeight >= 10 then
			DialogManager.Sv_PlayShoutDialog( dialog_trashbot_fight, "Jump", nil, DialogSpeakerName.Lorenzo, nil, 60 )
			self.playDialogWeight = 0.0
		end
	end
end

function JunkWaveState.stop( self )
	self.waitState:stop()
end

function JunkWaveState.onFixedUpdate( self, dt )
	self.target = sm.exists( self.target ) and self.target or nil
	self.waitState:onFixedUpdate( dt )
	self:sv_updateJunkWave()
end

function JunkWaveState.onUnitUpdate( self, dt )
	self.waitState:onUnitUpdate( dt )
end

function JunkWaveState.isDone( self )
	return self.waitState:isDone()
end

function JunkWaveState.getMovementDirection( self )
	return self.waitState:getMovementDirection()
end

function JunkWaveState.getFacingDirection( self )
	return self.waitState:getFacingDirection()
end

function JunkWaveState.getMovementType( self )
	return self.waitState:getMovementType()
end

function JunkWaveState.getWantsJump( self )
	return false
end

function JunkWaveState.setColor( self, color )
	self.color = color
end

function JunkWaveState.setWaveAmount( self, waveAmount )
	self.waveAmount = waveAmount
end

function JunkWaveState.setFightType( self, type )
	self.type = type
end