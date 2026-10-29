dofile( "$SURVIVAL_DATA/Scripts/game/units/states/BaseState.lua" )

TrashBallState = class( BaseState )

local StartupDelay = 40 * 0.0
local BallInterval = 40 * 0.7
local BallCircleRadius = 16.0
local MaxRadius = 50.0
local CircleGrowth = 0
local ClockwiseRotation = true

local Presets = {
	["LeftRot_Radius_01"] = {
		trashBallCircleRadius = 15.0,
		trashBallMaxRadius = 35.0,
		trashBallradiusGrowthPerSecond = 1.0,
		trashBallIsClockwise = true
	 },
	 ["LeftRot_Radius_02"] = {
		trashBallCircleRadius = 20.0,
		trashBallMaxRadius = 40.0,
		trashBallradiusGrowthPerSecond = 2.0,
		trashBallIsClockwise = true
	 },
	 ["LeftRot_Radius_03"] = {
		trashBallCircleRadius = 25.0,
		trashBallMaxRadius = 45.0,
		trashBallradiusGrowthPerSecond = 3.0,
		trashBallIsClockwise = true
	 },
	 ["LeftRot_Radius_04"] = {
		trashBallCircleRadius = 30.0,
		trashBallMaxRadius = 50.0,
		trashBallradiusGrowthPerSecond = 4.0,
		trashBallIsClockwise = true
	 },
	 ["LeftRot_Radius_05"] = {
		trashBallCircleRadius = 35.0,
		trashBallMaxRadius = 55.0,
		trashBallradiusGrowthPerSecond = 5.0,
		trashBallIsClockwise = true
	 },
	 ["RightRot_Radius_01"] = {
		trashBallCircleRadius = 15.0,
		trashBallMaxRadius = 35.0,
		trashBallradiusGrowthPerSecond = 1.0,
		trashBallIsClockwise = false
	 },
	 ["RightRot_Radius_02"] = {
		trashBallCircleRadius = 20.0,
		trashBallMaxRadius = 40.0,
		trashBallradiusGrowthPerSecond = 2.0,
		trashBallIsClockwise = false
	 },
	 ["RightRot_Radius_03"] = {
		trashBallCircleRadius = 25.0,
		trashBallMaxRadius = 45.0,
		trashBallradiusGrowthPerSecond = 3.0,
		trashBallIsClockwise = false
	 },
	 ["RightRot_Radius_04"] = {
		trashBallCircleRadius = 30.0,
		trashBallMaxRadius = 50.0,
		trashBallradiusGrowthPerSecond = 4.0,
		trashBallIsClockwise = false
	 },
	 ["RightRot_Radius_05"] = {
		trashBallCircleRadius = 35.0,
		trashBallMaxRadius = 55.0,
		trashBallradiusGrowthPerSecond = 5.0,
		trashBallIsClockwise = false
	 }
}

function TrashBallState.sv_onCreate( self, unit )
	self.unit = unit
	self.lookDirection = sm.vec3.new( 0, 1, 0 )
	self.stageIndex = 1
	self.circleRadius = BallCircleRadius
	self.clockwiseRotation = ClockwiseRotation
	self.circleGrowth = CircleGrowth
	self.maxRadius = MaxRadius

	self.waitState = self.unit:createState( "wait" )
	self.waitState.debugName = "waitState"
	self.waitState.time = 0.5
	self.waitState.name = "barf01"
	self.waitState.interruptible = false

	self.ballTimer = Timer()
	self.ballCount = 0
	self.spawned = false
end

function TrashBallState.refresh( self ) end

function TrashBallState.sv_setLookDirection( self, lookDirection )
	self.lookDirection = lookDirection
end

function TrashBallState.sv_setPosition( self, worldPosition ) end

function TrashBallState.sv_setTarget( self, target )
	self.target = target
end

function TrashBallState.sv_setStage( self, stageIndex )
	self.stageIndex = stageIndex
end

function TrashBallState.sv_updateTrashBall( self )
	if self.spawned == false then
		self.ballTimer:tick()
		if self.ballTimer:done() then
			self.ballTimer:start( BallInterval )
	
			-- Spawn trash ball
			local spawnPosition = self.unit.character:getTpBonePos( "head_jnt" )
			if not spawnPosition then
				local heightOffset = sm.vec3.new( 0, 0, 5.5 )
				local directionOffset = self.lookDirection * 3.5
				spawnPosition = self.unit.character.worldPosition + directionOffset + heightOffset
			else
				local vecToHead = spawnPosition - self.unit.character.worldPosition
				vecToHead.z = 0.0
				local dirToHead = vecToHead:safeNormalize( sm.vec3.new( 0.0, 0.0, 1.0 ) )
				spawnPosition = spawnPosition + dirToHead * 3
			end
			local yaw = math.atan2( self.lookDirection.y, self.lookDirection.x ) - math.pi / 2
	
			local params = { circleCenter = self.unit.character.worldPosition, circleRadius = self.circleRadius, clockwiseRotation = self.clockwiseRotation, circleGrowth = self.circleGrowth, maxRadius = self.maxRadius }
			if self.clockwiseRotation then
				sm.unit.createUnit( unit_trashball_green, spawnPosition, yaw, params )
			else
				sm.unit.createUnit( unit_trashball_purple, spawnPosition, yaw, params )
			end
			self.spawned = true
		end
	end
end

function TrashBallState.sv_setTrashBallPreset( self, presetName )
	if Presets[presetName] ~= nil then
		self.circleRadius = Presets[presetName].trashBallCircleRadius
		self.maxRadius = Presets[presetName].trashBallMaxRadius
		self.circleGrowth = Presets[presetName].trashBallradiusGrowthPerSecond
		self.clockwiseRotation = Presets[presetName].trashBallIsClockwise
	else
		print( "incorrect trash ball preset name: ", presetName )
	end
end

--[[API functions]]

function TrashBallState.start( self )
	self.waitState:start()
	self.ballTimer:start( StartupDelay )
	self.unit:sendCharacterEvent( "rotate" )
	self.spawned = false
end

function TrashBallState.stop( self )
	self.waitState:stop()
end

function TrashBallState.onFixedUpdate( self, dt )
	self.target = sm.exists( self.target ) and self.target or nil
	self.waitState:onFixedUpdate( dt )
	if self.target then
		self:sv_updateTrashBall()
	end
end

function TrashBallState.onUnitUpdate( self, dt )
	self.waitState:onUnitUpdate( dt )
end

function TrashBallState.isDone( self )
	if self.waitState:isDone() then
		self.unit:sendCharacterEvent( "stopRotate" )
	end
	return self.waitState:isDone()
end

function TrashBallState.getMovementDirection( self )
	return self.waitState:getMovementDirection()
end

function TrashBallState.getFacingDirection( self )
	return self.waitState:getFacingDirection()
end

function TrashBallState.getMovementType( self )
	return self.waitState:getMovementType()
end

function TrashBallState.getWantsJump( self )
	return false
end