dofile( "$SURVIVAL_DATA/Scripts/game/units/unit_util.lua" )

TapebotRangedState = class( nil )

local MaxSidestepRadius = 2.0 -- Desired sidestep distance
local MinSidestepRadius = 0.5 -- Minimum distance available to not skip sidestep
local TickAttackDelayOnSpawn = 40 * 2 -- 2 seconds

function TapebotRangedState.sv_onCreate( self, unit, robotModel )
	self.unit = unit

	self.robotModel = robotModel or "standard"
	self.modelSettings = TAPEBOT_MODEL_SETTINGS[self.robotModel]
	self.shotsFired = 0

	-- BurstCooldown	
	self.burstCooldownState = self.unit:createState( "idle" )
	self.burstCooldownState.debugName = "burstCooldownState"
	self.burstCooldownTicks = 0
	self.burstSettings = self.modelSettings.burstSettings

	-- SidestepDelay	
	self.sidestepDelayState = self.unit:createState( "positioning" )
	self.sidestepDelayState.debugName = "sidestepDelayState"
	self.sidestepDelayState.movementType = "stand"
	self.sidestepDelayTicks = 0

	-- Sidestep
	self.sidestepState = self.unit:createState( "positioning" )
	self.sidestepState.debugName = "sidestepState"
	self.sidestepState.timeout = 0.5
	self.sidestepState.tolerance = 0.2
	self.sidestepState.avoidance = false
	self.sidestepState.movementType = "sprint"

	-- Ranged attack
	self.rangedAttack = self.unit:createState( "rangedAttack" )
	self.rangedAttack.spreadAngle = 3.0
	self.rangedAttack.projectile = self.modelSettings.projectile
	self.rangedAttack.cooldown = self.modelSettings.cooldown
	self.rangedAttack.aimTime = self.modelSettings.aimTime
	self.rangedAttack.damage = self.modelSettings.damage
	self.rangedAttack.event = "shoot"
	self.rangedAttack.fakeOffset = sm.vec3.new( 0.5, 0.5, -0.25 )
	self.rangedAttack.velocity = self.modelSettings.projectileVelocity

	self.nearProjectileSettings = self.modelSettings.nearProjectileSettings

	self.currentState = self.rangedAttack
end

function TapebotRangedState.sv_setAimPoint( self, aimPoint )
	self.rangedAttack.aimPoint = aimPoint
end

function TapebotRangedState.sv_setSpawnTick( self, spawnTick )
	self.spawnTick = spawnTick
end

--[[API functions]]
function TapebotRangedState.start( self )
	self.burstCooldownTicks = 0
	self.sidestepDelayTicks = 0
	self.currentState:stop()
	self.currentState = self.rangedAttack
	self.currentState:start()
end

function TapebotRangedState.stop( self )
	self.currentState:stop()
end

function TapebotRangedState.onFixedUpdate( self, dt )
	if self.spawnTick and sm.game.getCurrentTick() - self.spawnTick < TickAttackDelayOnSpawn then
		self.currentState = self.sidestepDelayState
		self.currentState:start()
		self.spawnTick = nil
	end

	local stationary = self.saved and self.saved.stationary
	local desiredState = self.currentState
	if self.currentState == self.burstCooldownState then
		local finishedCooldown = self.modelSettings.burstSettings == nil
		if self.modelSettings.burstSettings then
			self.burstCooldownTicks = self.burstCooldownTicks + 1
			finishedCooldown = self.burstCooldownTicks >= self.modelSettings.burstSettings.cooldownTickTime
		end
		if finishedCooldown then
			self.burstCooldownTicks = 0
			if self.modelSettings.sidestep and not stationary then
				if math.random() < self.modelSettings.sidestep.chance then
					-- Prepare sidestep
					self.sidestepDelayTicks = 0
					self.sidestepDelayState.desiredDirection = ( self.rangedAttack.aimPoint - self.unit.character.worldPosition ):safeNormalize( self.unit:getCurrentFacingDirection() )
					self.sidestepDelayState.desiredPosition = self.unit.character.worldPosition
					desiredState = self.sidestepDelayState
				else
					desiredState = self.rangedAttack
				end
			else
				desiredState = self.rangedAttack
			end
		end
	elseif self.currentState == self.sidestepDelayState then
		self.sidestepDelayTicks = self.sidestepDelayTicks + 1
		local ticksBeforeSidestep = self.modelSettings.sidestep and self.modelSettings.sidestep.tickDelay or 0
		if self.sidestepDelayTicks >= ticksBeforeSidestep then
			local selectedSidestep = nil
			-- Setup sidestep vectors
			local startPosition = self.unit.character.worldPosition
			local facingDirection = ( self.rangedAttack.aimPoint - self.unit.character.worldPosition ):safeNormalize( self.unit:getCurrentFacingDirection() )
			local relRight = sm.vec3.new( facingDirection.y, -facingDirection.x, 0 )
			local relLeft = sm.vec3.new( -facingDirection.y, facingDirection.x, 0 )
			local sidestepRightPosition = startPosition + relRight * MaxSidestepRadius
			local sidestepLeftPosition = startPosition + relLeft * MaxSidestepRadius
			local abilities = { canWalk = true, canSwim = false }
			local currentWorld = GetWorld( self.unit )
			if currentWorld then
				local sidestepActions = {}

				-- Test how far the sidestep can move along the navmesh
				local traversableRight, distanceRight = sm.pathfinder.traversableRaycast( currentWorld, startPosition, sidestepRightPosition, abilities )
				if traversableRight then
					sidestepActions[#sidestepActions+1] = { sidestepDestination = sidestepRightPosition }
				else
					if distanceRight >= MinSidestepRadius then
						sidestepActions[#sidestepActions+1] = { distanceFraction = distanceRight / MaxSidestepRadius, sidestepDestination = sm.vec3.lerp( startPosition, sidestepRightPosition, distanceRight / MaxSidestepRadius ) }
					end
				end
				local traversableLeft, distanceLeft = sm.pathfinder.traversableRaycast( currentWorld, startPosition, sidestepLeftPosition, abilities )
				if traversableLeft then
					sidestepActions[#sidestepActions+1] = { sidestepDestination = sidestepLeftPosition }
				else
					if distanceLeft >= MinSidestepRadius then
						sidestepActions[#sidestepActions+1] = { distanceFraction = distanceLeft / MaxSidestepRadius, sidestepDestination = sm.vec3.lerp( startPosition, sidestepLeftPosition, distanceLeft / MaxSidestepRadius ) }
					end
				end
				-- Constrain result to navmesh and guesstimate if sidestep would walk behind an obstacle
				local goodSidesteps = {} -- Full traversability
				local mediocreSidesteps = {} -- Diminished traversability
				local badSidesteps = {} -- Blocked aim
				for _, sidestepAction in ipairs( sidestepActions ) do
					sidestepAction.navmeshDestination = sm.pathfinder.constrainPointToNavMesh( currentWorld, sidestepAction.sidestepDestination, abilities )
					local _, distanceFraction = sm.physics.distanceRaycast( sidestepAction.sidestepDestination, self.rangedAttack.aimPoint - startPosition )
					if distanceFraction < 0.8 then
						badSidesteps[#badSidesteps+1] = sidestepAction
					elseif sidestepAction.distanceFraction then
						mediocreSidesteps[#mediocreSidesteps+1] = sidestepAction
					else
						goodSidesteps[#goodSidesteps+1] = sidestepAction
					end
				end

				if #goodSidesteps > 0 then
					selectedSidestep = goodSidesteps[math.random( 1, #goodSidesteps )]
				elseif #mediocreSidesteps > 0 then
					table.sort( mediocreSidesteps, function( a, b ) return a.distanceFraction > b.distanceFraction end )
					selectedSidestep = mediocreSidesteps[1]
				end
			end

			self.sidestepDelayTicks = 0
			if selectedSidestep then
				self.sidestepState.desiredDirection = facingDirection
				self.sidestepState.desiredPosition = selectedSidestep.navmeshDestination
				desiredState = self.sidestepState
			else
				desiredState = self.rangedAttack
			end
		end
	elseif self.currentState == self.sidestepState then
		local done, result = self.sidestepState:isDone()
		if done then
			desiredState = self.rangedAttack
		else
			self.sidestepState.desiredDirection = ( self.rangedAttack.aimPoint - self.unit.character.worldPosition ):safeNormalize( self.unit:getCurrentFacingDirection() )
		end
	elseif self.currentState == self.rangedAttack then
		if self.modelSettings.nearProjectileSettings then
			local distance2 = ( self.rangedAttack.aimPoint - self.unit.character.worldPosition ):length2()
			if distance2 <= self.modelSettings.nearProjectileSettings.range * self.modelSettings.nearProjectileSettings.range then
				self.rangedAttack.velocity = self.modelSettings.nearProjectileSettings.projectileVelocity
			else
				self.rangedAttack.velocity = self.modelSettings.projectileVelocity
			end
		end
		if self.modelSettings.burstSettings then
			if self.rangedAttack.shotsFired >= self.modelSettings.burstSettings.shots then
				self.burstCooldownTicks = 0
				desiredState = self.burstCooldownState
			end
		elseif self.modelSettings.sidestep and not stationary then
			if self.shotsFired < self.rangedAttack.shotsFired then
				if math.random() < self.modelSettings.sidestep.chance then
					-- Prepare sidestep
					self.sidestepDelayTicks = 0
					self.sidestepDelayState.desiredDirection = ( self.rangedAttack.aimPoint - self.unit.character.worldPosition ):safeNormalize( self.unit:getCurrentFacingDirection() )
					self.sidestepDelayState.desiredPosition = self.unit.character.worldPosition
					desiredState = self.sidestepDelayState
				end
			end
		end
		self.shotsFired = self.rangedAttack.shotsFired
	end

	if desiredState ~= self.currentState then
		self.currentState:stop()
		self.currentState = desiredState
		self.currentState:start()
		self.shotsFired = 0
	end

	self.currentState:onFixedUpdate( dt )
end

function TapebotRangedState.onUnitUpdate( self, dt )
	self.currentState:onUnitUpdate( dt )
end

function TapebotRangedState.isDone( self )
	return true, ""
end

function TapebotRangedState.getMovementDirection( self )
	return self.currentState:getMovementDirection()
end

function TapebotRangedState.getFacingDirection( self )
	return self.currentState:getFacingDirection()
end

function TapebotRangedState.getMovementType( self )
	return self.currentState:getMovementType()
end

function TapebotRangedState.getWantsJump( self )
	return self.currentState:getWantsJump()
end

function TapebotRangedState.getWantsCrouch( self )
	return self.currentState:getWantsCrouch()
end