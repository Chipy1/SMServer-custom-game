dofile( "$SURVIVAL_DATA/Scripts/util.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/units/states/FollowPathState2.lua" )
dofile "$SURVIVAL_DATA/Scripts/game/survival_constants.lua"
dofile( "$SURVIVAL_DATA/Scripts/game/units/states/BaseState.lua" )

RangedRaidPathingState = class( BaseState )

-- State specific functions

function RangedRaidPathingState.sv_onCreate( self, unit )
	self.unit = unit
	self.tolerance = 1.5
	self.followPathState = FollowPathState2()
	self.followPathState:sv_onCreate( unit, "a:" )
	self.followPathState.debugName = "followPathState"
	
	self.followDirectionState = self.unit:createState( "followDirection" )
	self.followDirectionState.debugName = "followDirectionState"
	self.followDirectionState.customData = { onUnitUpdateOnly = true }
	
	self.idleState = self.unit:createState( "idle" )
	self.idleState.debugName = "idleState"
	
	self.progressTimeout = 5.0 -- seconds without progress
	self.ticksWithoutProgress = 0
	self.lastProgressPosition = self.unit.character.worldPosition
	self.targetDistance = 20
	self.raidPoint = nil

	self.randomOffsetVec = sm.vec3.new( math.random(), math.random(), 0 )

	self.currentState = self.idleState
end

function RangedRaidPathingState.sv_onDestroy( self )
	self:sv_debugDrawCleanup()
	self.followPathState:sv_onDestroy()
end

function RangedRaidPathingState.sv_setMovementType( self, movementType )
	self.followPathState:sv_setMovementType( movementType )
	self.followDirectionState.movementType = movementType
end

function RangedRaidPathingState.sv_setWaterAvoidance( self, waterAvoidance )
	self.followPathState:sv_setWaterAvoidance( waterAvoidance )
	self.followDirectionState.waterAvoidance = waterAvoidance
	self.waterAvoidance = waterAvoidance
end

function RangedRaidPathingState.sv_setCliffAvoidance( self, cliffAvoidance )
	self.followPathState:sv_setCliffAvoidance( cliffAvoidance )
	self.followDirectionState.cliffAvoidance = cliffAvoidance
end

function RangedRaidPathingState.sv_setWhiskerAvoidance( self, whiskerAvoidance )
	self.followPathState:sv_setWhiskerAvoidance( whiskerAvoidance )
	self.followDirectionState.avoidance = whiskerAvoidance
end

function RangedRaidPathingState.sv_setTimeout( self, progressTimeout )
	self.progressTimeout = progressTimeout
end

function RangedRaidPathingState.sv_setTargetDistance( self, distance )
	self.targetDistance = distance
end

function RangedRaidPathingState.sv_setRaidPoint( self, point )
	if point then
		self.raidPoint = point
		self.newDestination = true
		self.mainPath = { self.unit.character.worldPosition + sm.vec3.new( 0, 0, self.unit.character:getHeight() * 0.5 ), point + sm.vec3.new( 0, 0, self.unit.character:getHeight() * 0.5 ) }
		self.followPathState:sv_setPath( self.mainPath )
	end
end

-- AiState common interface

function RangedRaidPathingState.start( self )
	self.done = nil
	self.breachPosition = nil
	self.breachDirection = nil
	
	self.lastProgressPosition = self.unit.character.worldPosition
	self.ticksWithoutProgress = 0

	self.currentState = self.followDirectionState
	self.currentState:start()
	
	self.started = true
end

function RangedRaidPathingState.stop( self )
	self.started = false

	self.currentState:stop()
	self.currentState = self.idleState

	self:sv_debugDrawCleanup()
end

function RangedRaidPathingState.sv_updatePath( self )
	local path = {}
	path = sm.pathfinder.getPath( self.unit.character, self.raidPoint, nil, { canSwim = not self.waterAvoidance } )
	if #path == 0 then
		self.newDestination = true
		self.mainPath = {}
		return
	end

	self.mainPath = {}
	for _, link in ipairs( path ) do
		local pathPosition = link.toNode:getPosition() + sm.vec3.new( 0, 0, self.unit.character:getHeight() * 0.5 )
		self.mainPath[#self.mainPath+1] = pathPosition
	end

	-- Tweak path by forcing it a set distance from path end
	if #self.mainPath >= 2 and self.raidPoint then
		local shavedPath = false
		for i = #self.mainPath - 1, 1, -1 do
			local distanceToPoint = ( self.mainPath[i] - self.raidPoint ):length()
			if distanceToPoint >= self.targetDistance or i == 1 then
				local direction = ( self.mainPath[i+1] - self.mainPath[i] ):safeNormalize( sm.vec3.new( 1, 0, 0 ) )
				local remainingBackingDistance = math.max( distanceToPoint - self.targetDistance, 0 )
				local newPoint = self.mainPath[i] + direction * remainingBackingDistance
				local success, result = sm.physics.raycast( newPoint + sm.vec3.new( 0, 0, 128 ), newPoint + sm.vec3.new( 0, 0, -128 ), nil, sm.physics.filter.terrainAsset + sm.physics.filter.terrainSurface )
				if success then
					newPoint = result.pointWorld + sm.vec3.new( 0, 0, self.unit.character:getHeight() * 0.5 )
				end
				shavedPath = true
				self.mainPath[i+1] = newPoint
				if #self.mainPath > ( i + 1 ) then
					for j = #self.mainPath, i + 2, -1 do
						table.remove( self.mainPath, j )
					end
				end
				break
			end
		end
		if not shavedPath then
			self.done = "arrived"
			return
		end
	end

	-- add random positioning around end point
	if #self.mainPath >= 2 then
		local distanceToEnd = ( self.unit.character.worldPosition - self.mainPath[#self.mainPath] ):length()
		local castPoint = self.mainPath[#self.mainPath] + ( self.randomOffsetVec * math.min( distanceToEnd * 0.8, 6 ) )
		local success, result = sm.physics.raycast( castPoint + sm.vec3.new( 0, 0, 128 ), castPoint + sm.vec3.new( 0, 0, -128 ), nil, sm.physics.filter.terrainAsset + sm.physics.filter.terrainSurface )
		if success and ( math.abs( result.pointWorld.z - self.mainPath[#self.mainPath].z ) < 3 ) then
			castPoint = result.pointWorld
			local randomOffsetPath = sm.pathfinder.getWorldPath( self.unit.character:getWorld(), self.mainPath[#self.mainPath-1], castPoint + sm.vec3.new( 0, 0, self.unit.character:getHeight() * 0.5 ), { canSwim = not self.waterAvoidance } )
			local pathPoints = {}
			for _, link in ipairs( randomOffsetPath ) do
				local pathPosition = link.toNode:getPosition() + sm.vec3.new( 0, 0, self.unit.character:getHeight() * 0.5 )
				pathPoints[#pathPoints+1] = pathPosition
			end
			if #pathPoints >= 1 then
				table.remove( pathPoints, 1 )
				table.remove( self.mainPath, #self.mainPath )
				for _,point in ipairs( pathPoints ) do
					if ( point - self.mainPath[#self.mainPath] ):length() > 0 then
						self.mainPath[#self.mainPath+1] = point
					end
				end
			end
		end
	end
	self.followPathState:sv_setPath( self.mainPath )
end

function RangedRaidPathingState.onFixedUpdate( self, timeStep )
	if not self.started then return end
	if self.currentState then
		if not self.currentState.customData or not self.currentState.customData.onUnitUpdateOnly then
			self.currentState:onFixedUpdate( timeStep )
		end
	end
	
	local prevState = self.currentState
	if self.newDestination then
		self.newDestination = nil
		self:sv_updatePath()
		self.done = nil
	end
	
	local movementSpeed = self.unit.character:getCurrentMovementSpeed()
	local updateInterval = 0.3 -- tweakable, % of timeout
	local progressUpdateDistance = movementSpeed * ( self.progressTimeout * updateInterval )
	local distanceTraveled = ( self.lastProgressPosition - self.unit.character.worldPosition ):length()
	if distanceTraveled >= progressUpdateDistance then
		self.lastProgressPosition = self.unit.character.worldPosition
		self.ticksWithoutProgress = 0
	else
		self.ticksWithoutProgress = self.ticksWithoutProgress + 1
	end
	if ( self.ticksWithoutProgress / 40 ) >= self.progressTimeout then
		self.currentState = self.idleState
		self.done = "failed"
	end

	local fromTo = self.raidPoint - self.unit.character.worldPosition
	local distanceLeft = fromTo:length()
	if distanceLeft <= self.tolerance then
		self.currentState = self.idleState
		self.done = "arrived"
	end
	
	if self.currentState == self.idleState then
		if not self.done then
			self.currentState = self.followDirectionState
		end
	end
	
	if self.currentState == self.followDirectionState then
		local flatFromTo = sm.vec3.new( fromTo.x, fromTo.y, 0.0 )
		if flatFromTo:length() >= FLT_EPSILON then
			self.followDirectionState.desiredDirection = flatFromTo:normalize()
		else
			self.followDirectionState.desiredDirection = self.unit.character.direction
		end
		
		if #self.mainPath >= 2 then
			self.currentState = self.followPathState
		end
		
	elseif self.currentState == self.followPathState then
		local done, result = self.followPathState:isDone()
		if done then
			self.done = result
		end
		
	end
	
	if prevState ~= self.currentState then
		prevState:stop()
		self.currentState:start()
	end
end

function RangedRaidPathingState.onUnitUpdate( self, dt )
	if not self.started then return end
	if self.currentState then
		self.currentState:onUnitUpdate( dt )
		if self.currentState.customData and self.currentState.customData.onUnitUpdateOnly then
			self.currentState:onFixedUpdate( dt )
		end
		if self.done == nil and self.currentState == self.followPathState then
			self.newDestination = true
		end
	end
end

function RangedRaidPathingState.isDone( self )
	if self.done then
		return true, self.done
	end
	return false, ""
end

function RangedRaidPathingState.getMovementDirection( self )
	return self.currentState:getMovementDirection()
end

function RangedRaidPathingState.getFacingDirection( self )
	return self.currentState:getFacingDirection()
end

function RangedRaidPathingState.getMovementType( self )
	return self.currentState:getMovementType()
end

-- Private

function RangedRaidPathingState.sv_debugDrawCleanup( self )



	self:sv_clearBacktrackDebugDraw()
end

function RangedRaidPathingState.sv_clearBacktrackDebugDraw( self )







end
