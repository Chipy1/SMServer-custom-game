dofile( "$SURVIVAL_DATA/Scripts/game/survival_units.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/util/Timer.lua" )

CablebotPocket = class( nil )

local DigTimeoutTickTime = 2
local BotHeight = 0.6
local BotRadius = 0.3
local CapsuleHeight = math.max( BotHeight - BotRadius * 2, 0.0 )

local function sv_generateExactCountAssignments( numBots, distribution )
	local assignments = {}
	local trueCount = clamp( round( numBots * distribution ), 0, numBots )
	-- exact-count random distribution
	local trueLeft = trueCount
	for i = 1, numBots do
		local botsLeft = numBots - i + 1
		if trueLeft > 0 and math.random() < ( trueLeft / botsLeft ) then
			assignments[i] = true
			trueLeft = trueLeft - 1
		else
			assignments[i] = false
		end
	end

	return assignments
end

function CablebotPocket.server_onCreate( self )
	self.sv = {}
	self.sv.spawnedBots = 0
	self.sv.destroyed = false
	self.sv.triggerPosition = self.harvestable.worldPosition

	self.sv.numBots = 3
	self.sv.pocketRadius = 3.0
	self.sv.playerAttackerDistribution = CABLEBOT_PLAYER_ATTACKER_CHANCE
	self.sv.voxelDestroyerDistribution = 1.0
	if self.params then
		self.sv.numBots = math.max( round( self.params.ambushers or self.sv.numBots ), 0 )
		self.sv.pocketRadius = math.max( self.params.radius or self.sv.pocketRadius, 0.87 )
		self.sv.playerAttackerDistribution = clamp( self.params.playerAttackerDistribution or CABLEBOT_PLAYER_ATTACKER_CHANCE, 0.0, 1.0 )
		self.sv.voxelDestroyerDistribution = clamp( self.params.voxelDestroyerDistribution or self.sv.voxelDestroyerDistribution, 0.0, 1.0 )
	end

	self.sv.digTimeoutTimer = Timer()
	self.sv.digTimeoutTimer:start( DigTimeoutTickTime )
	self:sv_digHole()
end

function CablebotPocket.server_onFixedUpdate( self, dt )
	self.sv.digTimeoutTimer:tick()
	if self.sv.digTimeoutTimer:done() then
		self:sv_finalize()
	elseif not self:sv_isPocketClear() then
		self:sv_digHole()
	end
end

function CablebotPocket.sv_digHole( self )
	self.harvestable:getWorld():sphereVoxelDensitySubtraction( self.harvestable.worldPosition, self.sv.pocketRadius )
end

function CablebotPocket.sv_isPocketClear( self )
	local material, density = sm.world.getCurrentWorld():getVoxelMaterialFromWorldPosition( self.sv.triggerPosition )
	return density < 16
end

function CablebotPocket.sv_finalize( self )
	if not self.sv.destroyed then
		self:sv_spawnBots()
		self.harvestable:destroy()
		self.sv.destroyed = true
	end
end

function CablebotPocket.sv_spawnBots( self )

	local castAttempts = self.sv.numBots * 5
	local castRadius = 0.15
	local spawnMargin = 0.01
	local castMargin = 1.0
	local playerAttackerAssignments = sv_generateExactCountAssignments( self.sv.numBots, self.sv.playerAttackerDistribution )
	local voxelDestroyerAssignments = sv_generateExactCountAssignments( self.sv.numBots, self.sv.voxelDestroyerDistribution )
	local casts = {}
	for i = 1, castAttempts do
		local latitude = math.acos( 2 * math.random() - 1 ) - math.pi * 0.5
		local longitude = 2 * math.pi * math.random()
		local sphereX = math.cos( latitude ) * math.cos( longitude )
		local sphereY = math.cos( latitude ) * math.sin( longitude )
		local sphereZ = math.sin( latitude )
		local spherePoint = sm.vec3.new( sphereX, sphereY, sphereZ )
		local desiredSpawnPosition = self.harvestable.worldPosition + spherePoint * ( self.sv.pocketRadius - castRadius + spawnMargin + castMargin )
		casts[#casts+1] = { type = "sphere",
							startPoint = self.harvestable.worldPosition,
							endPoint = desiredSpawnPosition,
							radius = castRadius,
							ignoreObject = self.harvestable }
	end

	local retTable = sm.physics.multicast( casts )
	for i = 1, castAttempts do
		local success = retTable[i][1]
		local result = retTable[i][2]
		if success then
			local up = result.normalWorld
			local upOrtho = orthogonal( up )
			local forward = ( self.sv.triggerPosition - result.pointWorld ):safeNormalize( upOrtho )
			local projectedForward = ( forward - ( up * up:dot( forward ) ) ):safeNormalize( upOrtho )
			local yaw = math.atan2( projectedForward.y, projectedForward.x ) - math.pi / 2
			local pitch = math.asin( projectedForward.z )

			local upDot = sm.vec3.new( 0, 0, 1 ):dot( up )
			local capsuleRadiusFraction = 1.0 - upDot
			local capsuleHeightFraction = math.abs( clamp( upDot, -1.0, 0.0 ) )
			local capsuleOffset = math.max( CapsuleHeight * capsuleHeightFraction + BotRadius * capsuleRadiusFraction - spawnMargin, 0.0 )
			local spawnIndex = self.sv.spawnedBots + 1
			local unitParams = { playerAttacker = playerAttackerAssignments[spawnIndex], voxelDestroyer = voxelDestroyerAssignments[spawnIndex] }

			-- Spawn units on the walls of the hole
			sm.unit.createUnit( unit_cablebot, result.pointWorld + up * capsuleOffset, yaw, unitParams, pitch )
			self.sv.spawnedBots = self.sv.spawnedBots + 1
			if self.sv.spawnedBots >= self.sv.numBots then
				break
			end
		end
	end

	-- Failsafe, spawn units in the middle of the hole
	if self.sv.spawnedBots < self.sv.numBots then
		for i = self.sv.spawnedBots + 1, self.sv.numBots do
			local spawnDirection = ( self.sv.triggerPosition - self.harvestable.worldPosition ):safeNormalize( sm.vec3.new( 0, 1, 0 ) )
			local yaw = math.atan2( spawnDirection.y, spawnDirection.x ) - math.pi / 2
			local pitch = math.asin( spawnDirection.z )
			local unitParams = { playerAttacker = playerAttackerAssignments[i], voxelDestroyer = voxelDestroyerAssignments[i] }
			sm.unit.createUnit( unit_cablebot, self.harvestable.worldPosition, yaw, unitParams, pitch )
			self.sv.spawnedBots = self.sv.spawnedBots + 1
		end
	end

end