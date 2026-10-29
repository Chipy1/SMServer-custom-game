dofile( "$SURVIVAL_DATA/Scripts/util.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/util/Timer.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/survival_constants.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/survival_projectiles.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/units/states/BaseState.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/units/states/FlyMoveState.lua" )

MinerbotSelfdestructState = class( BaseState )

local WaitTime = 0.8
local DestructionTickTime = 40 * 5
local Tolerance = 2.0
local ShakeTickTime = 5
local ShakeImpulse = 4000
local ShakeSpreadDeg = 80.0

local BoostTickTime = 5
local BoostImpulse = 22500
local BoostSpreadDeg = 50.0

local CollisionSphereDistance = 1.0
local CollisionSphereRadius = 0.5

local TrajectoryMaxAngle = 15 -- Angle up and away from the target position
local TrajectoryDistanceCap = 6 -- At this distance or further away, the trajectory is maximally angled away

-- State specific functions

function MinerbotSelfdestructState.sv_onCreate( self, unit )
	self.unit = unit

	self.destructionTicks = 0
	self.shakeTimer = Timer()
	self.shakeTimer:start( ShakeTickTime )
	self.shakePosition = self.unit.character.worldPosition

	-- Wait
	self.waitState = self.unit:createState( "wait" )
	self.waitState.debugName = "waitState"
	self.waitState.time = WaitTime
	self.waitState.interruptible = false

	self.boostTimer = Timer()
	self.boostTimer:start( BoostTickTime )

	-- Movement
	self.flyMoveState = FlyMoveState()
	self.flyMoveState:sv_onCreate( self.unit )
	self.flyMoveState:sv_setMovementType( "sprint" )
	self.flyMoveState.debugName = "flyMoveState"

	self.currentState = self.waitState
end

function MinerbotSelfdestructState.sv_setTarget( self, target )
	self.target = target
	if sm.exists( self.target ) then
		self.targetPosition = self.target.worldPosition
	else
		self.targetPosition = nil
	end
end

function MinerbotSelfdestructState.sv_setTargetPosition( self, targetPosition )
	self.targetPosition = targetPosition
	self.target = nil
end

--[[API functions]]

function MinerbotSelfdestructState.start( self )
	self.currentState:stop()
	self.currentState = self.waitState
	self.currentState:start()
	self.done = nil
	self.started = true
	self.destructionTicks = 0
	self.shakePosition = self.unit.character.worldPosition
	self.unit:sendCharacterEvent( "destroywindup" )
end

function MinerbotSelfdestructState.stop( self )
	self.started = false
	self.currentState:stop()
end

function MinerbotSelfdestructState.onFixedUpdate( self, timeStep )
	local character = self.unit.character
	if not sm.exists( character ) then return end

	if self.targetPosition == nil then
		-- Attempt to find a target position if none is set
		if sm.exists( self.target ) then
			self.targetPosition = self.target.worldPosition
		else
			local dir = character.direction
			dir.z = 0
			dir = dir:safeNormalize( sm.vec3.new( 0, 1, 0 ) )
			local angleDeg = -30 -- up or down angle away from character's forward direction
			local angleRad = math.rad( angleDeg )
			local horizontalScale = math.cos( angleRad )
			local vertical = math.sin( angleRad )
			local deathDirection = sm.vec3.new( dir.x * horizontalScale, dir.y * horizontalScale, vertical ):normalize()
			local castTargetPosition = character.worldPosition + deathDirection * 30
			local hit, result = sm.physics.spherecast( character.worldPosition, castTargetPosition, CollisionSphereRadius, character, sm.physics.filter.default, nil, { unit_minerbot, ITEMS.obj_robotparts_minerbot_thruster } )
			if hit then
				self.targetPosition = result.pointWorld
			else
				self.targetPosition = castTargetPosition
			end
		end
	end

	if self.currentState == self.waitState then
		self.shakeTimer:tick()
		if self.shakeTimer:done() then
			self.shakeTimer:reset()
			local shakeDirection = ( self.shakePosition - character.worldPosition ):safeNormalize( sm.vec3.new( 0, 0, 1 ) )
			shakeDirection = ( sm.noise.gunSpread( shakeDirection, ShakeSpreadDeg ) ):safeNormalize( sm.vec3.zero() )
			if shakeDirection:length2() > FLT_EPSILON then
				ApplyCharacterImpulse( character, shakeDirection, ShakeImpulse )
				local forward = self.unit:getCurrentFacingDirection():safeNormalize( sm.vec3.new( 0, 1, 0 ) )
				local directionDeterminant = ( forward.x * shakeDirection.y - forward.y * shakeDirection.x )
				if directionDeterminant > 0 then
					-- Moving right, burst left thruster
					self.unit:sendCharacterEvent( "burst01left" )
				else
					-- Moving left, burst right thruster
					self.unit:sendCharacterEvent( "burst01right" )
				end
			end
		end
	elseif self.currentState == self.flyMoveState then
		self.destructionTicks = self.destructionTicks + 1
		if self.targetPosition then
			-- Calculate an angled trajectory depending on distance
			local fromTo = self.targetPosition - character.worldPosition
			local distance = sm.vec3.new( fromTo.x, fromTo.y, 0 ):length()
			local direction = fromTo:safeNormalize( self.unit:getCurrentMovementDirection() )
			local up = sm.vec3.new( 0, 0, 1 )
			local flat = sm.vec3.new( direction.x, direction.y, 0 ):safeNormalize( sm.vec3.new( 0, 1, 0 ) )
			local right = flat:cross( up )
			local angleDeg = lerp( 0, TrajectoryMaxAngle, distance / TrajectoryDistanceCap )
			local angleRad = math.rad( angleDeg )
			local moveDirection = direction:rotate( angleRad, right )

			self.flyMoveState:sv_setDirection( moveDirection )
			self.boostTimer:tick()
			if self.boostTimer:done() then
				self.boostTimer:reset()
				moveDirection = ( sm.noise.gunSpread( moveDirection, BoostSpreadDeg ) ):safeNormalize( sm.vec3.zero() )
				if moveDirection:length2() > FLT_EPSILON then
					ApplyCharacterImpulse( character, moveDirection, BoostImpulse )
					local forward = self.unit:getCurrentFacingDirection():safeNormalize( sm.vec3.new( 0, 1, 0 ) )
					local directionDeterminant = ( forward.x * moveDirection.y - forward.y * moveDirection.x )
					if directionDeterminant > 0 then
						-- Moving right, burst left thruster
						self.unit:sendCharacterEvent( "burst02left" )
					else
						-- Moving left, burst right thruster
						self.unit:sendCharacterEvent( "burst02right" )
					end
				end
			end
		end
	end

	self.currentState:onFixedUpdate( timeStep )

	local selfdestructing = self.currentState == self.flyMoveState
	local finishedDestruction = self.destructionTicks >= DestructionTickTime
	local targetDistance = self.targetPosition and ( self.targetPosition - character.worldPosition ):length() or math.huge
	local arrivedAtTarget = targetDistance <= Tolerance

	if selfdestructing and not arrivedAtTarget then
		local from = character.worldPosition
		local to = from + character.direction * CollisionSphereDistance
		local hit, result = sm.physics.spherecast( from, to, CollisionSphereRadius, character, sm.physics.filter.default, nil, { unit_minerbot, ITEMS.obj_robotparts_minerbot_thruster } )
		if hit then
			-- Treat obstacle as target
			arrivedAtTarget = true
		end
	end

	if selfdestructing and arrivedAtTarget then
		self.done = "arrived"
	elseif selfdestructing and finishedDestruction then
		self.done = "finished"
	else
		self.done = nil
	end

	local done, result = self.currentState:isDone()
	if done then
		if self.currentState == self.waitState then
			self.currentState:stop()
			self.currentState = self.flyMoveState
			self.currentState:start()
			self.unit:sendCharacterEvent( "destroy" )
		end
	end
end

function MinerbotSelfdestructState.onUnitUpdate( self, dt ) end

function MinerbotSelfdestructState.isDone( self )
	if self.done then
		return true, self.done
	end
	return false, ""
end

function MinerbotSelfdestructState.getMovementDirection( self )
	return self.currentState:getMovementDirection()
end

function MinerbotSelfdestructState.getFacingDirection( self )
	return self.currentState:getFacingDirection()
end

function MinerbotSelfdestructState.getMovementType( self )
	return self.currentState:getMovementType()
end

function MinerbotSelfdestructState.getWantsJump( self )
	return self.currentState:getWantsJump()
end

function MinerbotSelfdestructState.getWantsCrouch( self )
	return self.currentState:getWantsCrouch()
end