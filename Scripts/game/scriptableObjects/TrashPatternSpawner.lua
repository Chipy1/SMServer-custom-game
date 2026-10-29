TrashPatternSpawner = class()
TrashPatternSpawner.isSaveObject = false

local RotationAxis = sm.vec3.new( 0, 0, 1 )
local TerrainCollisionMask = bit.bor( sm.physics.filter.terrainSurface, sm.physics.filter.terrainAsset, sm.physics.filter.voxelTerrain )




local BubbleTypes = {

	bh_straight_ball_green = "bh_straight_ball_green",
	bh_straight_ball_purple = "bh_straight_ball_purple",
	bh_straight_twister_green = "bh_straight_twister_green",
	bh_straight_twister_purple = "bh_straight_twister_purple",
	bh_straight_star_green = "bh_straight_star_green",
	bh_straight_star_purple = "bh_straight_star_purple",

	bh_curved01_ball_green = "bh_curved01_ball_green",
	bh_curved01_ball_purple = "bh_curved01_ball_purple",
	bh_curved01_twister_green = "bh_curved01_twister_green",
	bh_curved01_twister_purple = "bh_curved01_twister_purple",
	bh_curved01_star_green = "bh_curved01_star_green",
	bh_curved01_star_purple = "bh_curved01_star_purple",

	bh_curved02_ball_green = "bh_curved02_ball_green",
	bh_curved02_ball_purple = "bh_curved02_ball_purple",
	bh_curved02_twister_green = "bh_curved02_twister_green",
	bh_curved02_twister_purple = "bh_curved02_twister_purple",
	bh_curved02_star_green = "bh_curved02_star_green",
	bh_curved02_star_purple = "bh_curved02_star_purple",

	bh_curved02_ball_green_c = "bh_curved02_ball_green_c",
	bh_curved02_ball_purple_c = "bh_curved02_ball_purple_c",
	bh_curved02_twister_green_c = "bh_curved02_twister_green_c",
	bh_curved02_twister_purple_c = "bh_curved02_twister_purple_c",

	bh_arched_ball_green = "bh_arched_ball_green",
	bh_arched_ball_purple = "bh_arched_ball_purple",
	bh_arched_twister_green = "bh_arched_twister_green",
	bh_arched_twister_purple = "bh_arched_twister_purple",

	bh_big_ball_green = "bh_big_ball_green",
	bh_big_ball_purple = "bh_big_ball_purple",

	bh_danger_ball_color01 = "bh_danger_ball_color01",
	bh_danger_ball_color02 = "bh_danger_ball_color02",



}

local SpawnShapePresets = {
	Single = "Single",
	Circle = "Circle",
	LineHorizontal = "LineHorizontal",
	LineVertical = "LineVertical"
}

local BubbleProjectiles = {
	[BubbleTypes.bh_straight_ball_green] = projectile_trashbot_bh_straight_ball_green,
	[BubbleTypes.bh_straight_ball_purple] = projectile_trashbot_bh_straight_ball_purple,
	[BubbleTypes.bh_straight_twister_green] = projectile_trashbot_bh_straight_twister_green,
	[BubbleTypes.bh_straight_twister_purple] = projectile_trashbot_bh_straight_twister_purple,
	[BubbleTypes.bh_straight_star_green] = projectile_trashbot_bh_straight_star_green,
	[BubbleTypes.bh_straight_star_purple] = projectile_trashbot_bh_straight_star_purple,
	[BubbleTypes.bh_danger_ball_color01] = projectile_trashbot_bh_danger_ball_color01,
	[BubbleTypes.bh_danger_ball_color02] = projectile_trashbot_bh_danger_ball_color02,
	[BubbleTypes.bh_curved01_ball_green] = projectile_trashbot_bh_curved01_ball_green,
	[BubbleTypes.bh_curved01_ball_purple] = projectile_trashbot_bh_curved01_ball_purple,
	[BubbleTypes.bh_curved01_twister_green] = projectile_trashbot_bh_curved01_twister_green,
	[BubbleTypes.bh_curved01_twister_purple] = projectile_trashbot_bh_curved01_twister_purple,
	[BubbleTypes.bh_curved01_star_green] = projectile_trashbot_bh_curved01_star_green,
	[BubbleTypes.bh_curved01_star_purple] = projectile_trashbot_bh_curved01_star_purple,
	[BubbleTypes.bh_curved02_ball_green] = projectile_trashbot_bh_curved02_ball_green,
	[BubbleTypes.bh_curved02_ball_purple] = projectile_trashbot_bh_curved02_ball_purple,
	[BubbleTypes.bh_curved02_twister_green] = projectile_trashbot_bh_curved02_twister_green,
	[BubbleTypes.bh_curved02_twister_purple] = projectile_trashbot_bh_curved02_twister_purple,
	[BubbleTypes.bh_curved02_star_green] = projectile_trashbot_bh_curved02_star_green,
	[BubbleTypes.bh_curved02_star_purple] = projectile_trashbot_bh_curved02_star_purple,
	[BubbleTypes.bh_curved02_ball_green_c] = projectile_trashbot_bh_curved02_ball_green_c,
	[BubbleTypes.bh_curved02_ball_purple_c] = projectile_trashbot_bh_curved02_ball_purple_c,
	[BubbleTypes.bh_curved02_twister_green_c] = projectile_trashbot_bh_curved02_twister_green_c,
	[BubbleTypes.bh_curved02_twister_purple_c] = projectile_trashbot_bh_curved02_twister_purple_c,
	[BubbleTypes.bh_arched_ball_green] = projectile_trashbot_bh_arched_ball_green,
	[BubbleTypes.bh_arched_ball_purple] = projectile_trashbot_bh_arched_ball_purple,
	[BubbleTypes.bh_arched_twister_green] = projectile_trashbot_bh_arched_twister_green,
	[BubbleTypes.bh_arched_twister_purple] = projectile_trashbot_bh_arched_twister_purple,
	[BubbleTypes.bh_big_ball_green] = projectile_trashbot_bh_big_ball_green,
	[BubbleTypes.bh_big_ball_purple] = projectile_trashbot_bh_big_ball_purple,




}

local BubbleSizes = {
	[BubbleTypes.bh_straight_ball_green] = 0.25,
	[BubbleTypes.bh_straight_ball_purple] = 0.25,
	[BubbleTypes.bh_straight_twister_green] = 0.25,
	[BubbleTypes.bh_straight_twister_purple] = 0.25,
	[BubbleTypes.bh_straight_star_green] = 0.25,
	[BubbleTypes.bh_straight_star_purple] = 0.25,
	[BubbleTypes.bh_curved01_ball_green] = 0.25,
	[BubbleTypes.bh_curved01_ball_purple] = 0.25,
	[BubbleTypes.bh_curved01_twister_green] = 0.25,
	[BubbleTypes.bh_curved01_twister_purple] = 0.25,
	[BubbleTypes.bh_curved01_star_green] = 0.25,
	[BubbleTypes.bh_curved01_star_purple] = 0.25,

	[BubbleTypes.bh_curved02_ball_green] = 0.25,
	[BubbleTypes.bh_curved02_ball_purple] = 0.25,
	[BubbleTypes.bh_curved02_twister_green] = 0.25,
	[BubbleTypes.bh_curved02_twister_purple] = 0.25,
	[BubbleTypes.bh_curved02_star_green] = 0.25,
	[BubbleTypes.bh_curved02_star_purple] = 0.25,

	[BubbleTypes.bh_curved02_ball_green_c] = 0.25,
	[BubbleTypes.bh_curved02_ball_purple_c] = 0.25,
	[BubbleTypes.bh_curved02_twister_green_c] = 0.25,
	[BubbleTypes.bh_curved02_twister_purple_c] = 0.25,
	[BubbleTypes.bh_arched_ball_green] = 0.25,
	[BubbleTypes.bh_arched_ball_purple] = 0.25,
	[BubbleTypes.bh_arched_twister_green] = 0.25,
	[BubbleTypes.bh_arched_twister_purple] = 0.25,

	[BubbleTypes.bh_danger_ball_color01] = 0.25,
	[BubbleTypes.bh_danger_ball_color02] = 0.25,
	[BubbleTypes.bh_big_ball_green] = 0.25,
	[BubbleTypes.bh_big_ball_purple] = 0.25,




	
}

local ProjectileDamage = 20

function TrashPatternSpawner.server_onCreate( self )
	self.sv = {}
	self.sv.origo = self.params and self.params.position or nil
	self.sv.world = self.scriptableObject:getWorld()
	if self.params then
		if self.params.unit then
			self.sv.unit = self.params.unit
		end
		if self.params.override then
			self.sv.override = self.params.override
		end
	end
	self.sv.initialDirection = self.params and self.params.direction or sm.vec3.new( 1, 0, 0 )
	self.sv.currentDirections = {}
	self.sv.accumulatedRotations = {}
	self.sv.rotationModifiers = {}
	self.sv.spawnTickCounters = {}
	self.sv.fireDurationCounters = {}
	self.sv.patternDurations = {}
	self.sv.skipFireCounters = {}
	self.sv.patternSkipIntervals = {}
	self.sv.patternSpawnDelay = {}
	self.sv.patternRadianRotationsPerTick = {}
	self.sv.stepRotations = {}
	self.sv.patternRadianRotationInvertThresholds = {}
	self.sv.bubbleSpawnTickInterval = {}
	self.sv.bubbleMaxLifetimes = {}
	self.sv.splits = {}
	self.sv.radiansBetweenSplits = {}
	self.sv.splitSpeedModifiers = {}
	self.sv.spawnShapeTypes = {}
	self.sv.spawnShapeData = {}
	self.sv.projectileSpeeds = {}
	self.sv.maxSpeeds = {}
	self.sv.minSpeeds = {}
	self.sv.accelerations = {}
	self.sv.bubbleTypes = {}
	self.sv.spawnChances = {}
	self.sv.easingDurations = {}
	self.sv.easingTickCounters = {}
	self.sv.easingTypes = {}
	self.sv.startingDirection = {}
	self.sv.fireAngles = {}
	self.sv.targetSpeeds = {}
	self.sv.targetRotationPoints = {}
	self.sv.targetSpawnIntervals = {}

	self.sv.systemAccumulatedRotation = 0
	self.sv.systemRotationModifier = 1
	self.sv.systemRotationRadiansPerTick = nil
	self.sv.systemRotationRadianInvertThreshold = nil
	self.sv.systemRepeatCounter = 0
	self.sv.systemSpeedData = nil

	self:sv_initValues()
end

function TrashPatternSpawner.server_onDestroy( self )
	self:sv_cleanUpBubbles()
end

function TrashPatternSpawner.sv_cleanUpBubbles( self )
end

function TrashPatternSpawner.sv_initValues( self )
	self.sv.createTick = sm.game.getCurrentTick()
	local settings = self.sv.override or PresetValues
	for i,data in ipairs( settings.patternSettings ) do
		local rotationAngle =  math.floor( data.startingAngle ) * math.pi / 180
		self.sv.startingDirection[i] = self.sv.initialDirection:rotate( rotationAngle, RotationAxis )
		self.sv.currentDirections[i] = self.sv.startingDirection[i]
		self.sv.spawnTickCounters[i] = math.floor( data.spawnInterval * 40 )
		self.sv.accumulatedRotations[i] = 0
		self.sv.rotationModifiers[i] = 1
		self.sv.skipFireCounters[i] = 0
		self.sv.fireDurationCounters[i] = 0
		self.sv.spawnShapeTypes[i] = data.spawnShapeType
		self.sv.projectileSpeeds[i] = data.projectileSpeed
		self.sv.accelerations[i] = data.acceleration
		self.sv.bubbleTypes[i] = data.bubbleType
		self.sv.bubbleMaxLifetimes[i] = math.floor( data.maxLifetime * 40 )
		self.sv.patternDurations[i] = math.floor( data.duration * 40 )
		if data.fireAngle ~= nil then
			self.sv.fireAngles[i] = data.fireAngle * math.pi / 180
		else
			self.sv.fireAngles[i] = nil
		end
		if data.maxSpeed ~= nil then
			self.sv.maxSpeeds[i] = data.maxSpeed
		else
			self.sv.maxSpeeds[i] = nil
		end
		if data.minSpeed ~= nil then
			self.sv.minSpeeds[i] = data.minSpeed
		else
			self.sv.minSpeeds[i] = nil
		end
		if data.spawnChance ~= nil then
			self.sv.spawnChances[i] = data.spawnChance
		else
			self.sv.spawnChances[i] = 1.0
		end
		if data.activationDelay ~= nil then
			self.sv.patternSpawnDelay[i] = math.floor( data.activationDelay * 40 )
		else
			self.sv.patternSpawnDelay[i] = 0
		end
		if data.rotationPerSecond ~= nil then
			self.sv.patternRadianRotationsPerTick[i] = data.rotationPerSecond * 0.025 * math.pi / 180
		else
			self.sv.patternRadianRotationsPerTick[i] = 0.0
		end
		if data.targetRotationPoints ~= nil then
			self.sv.targetRotationPoints[i] = {}
			for j,rotationData in ipairs( data.targetRotationPoints ) do
				self.sv.targetRotationPoints[i][j] = {}
				self.sv.targetRotationPoints[i][j].targetRotationsPerTick = rotationData.targetRotationSpeed * 0.025 * math.pi / 180
				self.sv.targetRotationPoints[i][j].durationPoint = math.floor(  (  self.sv.patternDurations[i] ) * rotationData.durationPoint )
			end
		else
			self.sv.targetRotationPoints[i] = nil
		end

		if data.stepRotation ~= nil then
			self.sv.stepRotations[i] = {}
			self.sv.stepRotations[i].radianRotation = data.stepRotation.angle * math.pi / 180
			self.sv.stepRotations[i].stepTicks = math.floor( data.stepRotation.stepTime * 40 )
			self.sv.stepRotations[i].tickCounter = 0
		else
			self.sv.stepRotations[i] = nil
		end
		if data.invertRotationThreshold ~= nil then
			self.sv.patternRadianRotationInvertThresholds[i] = data.invertRotationThreshold * math.pi / 180
			if data.invertRotationEasing ~= nil and self.sv.patternRadianRotationsPerTick[i] ~= nil then
				if data.invertRotationEasing == true then
					self.sv.easingDurations[i] = math.floor( self.sv.patternRadianRotationInvertThresholds[i] / self.sv.patternRadianRotationsPerTick[i] ) -- amount of ticks to reach the target rotation value
					self.sv.easingTickCounters[i] = 0
				else
					self.sv.easingDurations[i] = nil
				end
				if data.easingType ~= nil then
					self.sv.easingTypes[i] = data.easingType
				else
					self.sv.easingTypes[i] = "easeInOutQuad"
				end
			else
				self.sv.easingDurations[i] = nil
				self.sv.easingTickCounters[i] = nil
			end
		else
			self.sv.patternRadianRotationInvertThresholds[i] = nil
			self.sv.easingDurations[i] = nil
			self.sv.easingTickCounters[i] = nil
			self.sv.easingTypes[i] = nil
		end
		self.sv.bubbleSpawnTickInterval[i] = math.floor( data.spawnInterval * 40 )
		self.sv.splits[i] = data.split or 1
		if data.splitAngle ~= nil then
			self.sv.radiansBetweenSplits[i] = math.floor( data.splitAngle ) * math.pi / 180
		else
			self.sv.radiansBetweenSplits[i] = 0.0
		end
		self.sv.splitSpeedModifiers[i] = data.splitSpeedModifier or 0.0
		if data.skipInterval ~= nil then
			self.sv.patternSkipIntervals[i] = { fireDuration = math.floor( data.skipInterval.fireDuration * 40 ), skipDuration = math.floor( data.skipInterval.skipDuration * 40 ) }
		else
			self.sv.patternSkipIntervals[i] = nil
		end
		if data.targetSpeedPoints ~= nil then
			self.sv.targetSpeeds[i] = {}
			for j,speedData in ipairs( data.targetSpeedPoints ) do
				self.sv.targetSpeeds[i][j] = {}
				self.sv.targetSpeeds[i][j].targetSpeed = speedData.targetSpeed
				self.sv.targetSpeeds[i][j].durationPoint = math.floor(  ( self.sv.patternDurations[i] ) * speedData.durationPoint )
			end
		else
			self.sv.targetSpeeds[i] = nil
		end
		if data.targetSpawnIntervals ~= nil then
			self.sv.targetSpawnIntervals[i] = {}
			for j, spawnData in ipairs( data.targetSpawnIntervals ) do
				self.sv.targetSpawnIntervals[i][j] = {}
				self.sv.targetSpawnIntervals[i][j].targetInterval = math.floor( spawnData.targetInterval * 40 )
				self.sv.targetSpawnIntervals[i][j].durationPoint = math.floor(  (  self.sv.patternDurations[i] ) * spawnData.durationPoint )
			end
		else
			self.sv.targetSpawnIntervals[i] = nil
		end
	end
	self.sv.systemAccumulatedRotation = 0
	self.sv.systemRotationModifier = 1
	self.sv.systemRepeatCounter = 0
	if settings.systemSettings ~= nil then
		if settings.systemSettings.rotationPerSecond ~= nil and settings.systemSettings.rotationPerSecond ~= 0 then
			self.sv.systemRotationRadiansPerTick = settings.systemSettings.rotationPerSecond * 0.025 * math.pi / 180
		else
			self.sv.systemRotationRadiansPerTick = nil
		end
		if settings.systemSettings.invertRotationThreshold ~= nil and settings.systemSettings.invertRotationThreshold ~= 0 then
			self.sv.systemRotationRadianInvertThreshold = settings.systemSettings.invertRotationThreshold * math.pi / 180
		else
			self.sv.systemRotationRadianInvertThreshold = nil
		end
		self.sv.systemRepeatCount = settings.systemSettings.repeatCount
		if settings.systemSettings.speedModifications ~= nil then
			self.sv.systemSpeedData = {}
			self.sv.systemSpeedData.modifications = DeepCopy( settings.systemSettings.speedModifications )
			for i,data in ipairs( self.sv.systemSpeedData.modifications ) do
				self.sv.systemSpeedData.modifications[i].increaseTime = math.floor( data.increaseTime * 40 )
				self.sv.systemSpeedData.modifications[i].duration = math.floor( data.duration * 40 )
			end
			self.sv.systemSpeedData.currentModifier = 1.0
			self.sv.systemSpeedData.fromModifier = 1.0
			self.sv.systemSpeedData.counter = 0
			self.sv.systemSpeedData.currentIndex = 1
		else
			self.sv.systemSpeedData = nil
		end
	else
		self.sv.systemRotationRadiansPerTick = nil
		self.sv.systemRotationRadianInvertThreshold = nil
		self.sv.systemSpeedData = nil
	end
end

function TrashPatternSpawner.server_onRefresh( self )
	self:sv_cleanUpBubbles()
	self:sv_initValues()
end

function TrashPatternSpawner.sv_e_removeSystem( self )
	self.sv.markedForDestroy = true
end

function TrashPatternSpawner.sv_e_stopSystem( self )
	if sm.exists( self.scriptableObject ) then
		self.scriptableObject:destroy()
	end
end

function TrashPatternSpawner.server_onFixedUpdate( self, delta )
	if self.sv.unit and not sm.exists( self.sv.unit ) then
		self.sv.markedForDestroy = true
	end
	if self.sv.markedForDestroy then
		self:sv_cleanUpBubbles()
		if sm.exists( self.scriptableObject ) then
			self.scriptableObject:destroy()
		end
		return
	end

	local currentTick = sm.game.getCurrentTick()
	local settings = self.sv.override or PresetValues

	-- system rotation, affects all patterns
	if self.sv.systemRotationRadiansPerTick ~= nil and self.sv.systemRotationRadiansPerTick ~= 0 then
		for i,direction in ipairs( self.sv.currentDirections ) do
			self.sv.currentDirections[i] = direction:rotate( self.sv.systemRotationRadiansPerTick * self.sv.systemRotationModifier, RotationAxis )
		end
		self.sv.systemAccumulatedRotation = self.sv.systemAccumulatedRotation + self.sv.systemRotationRadiansPerTick
		if self.sv.systemRotationRadianInvertThreshold ~= nil and self.sv.systemRotationRadianInvertThreshold ~= 0 and math.abs( self.sv.systemAccumulatedRotation ) >= self.sv.systemRotationRadianInvertThreshold then
			self.sv.systemAccumulatedRotation = 0
			self.sv.systemRotationModifier = self.sv.systemRotationModifier * -1
		end
	end

	-- system speed modifications. affects all bubbles starting speed
	if self.sv.systemSpeedData ~= nil then
		if self.sv.systemSpeedData.currentIndex <= #self.sv.systemSpeedData.modifications then
			if self.sv.systemSpeedData.modifications[self.sv.systemSpeedData.currentIndex].incremental then
				if self.sv.systemSpeedData.counter <= self.sv.systemSpeedData.modifications[self.sv.systemSpeedData.currentIndex].increaseTime then
					self.sv.systemSpeedData.currentModifier = lerp( self.sv.systemSpeedData.fromModifier, self.sv.systemSpeedData.modifications[self.sv.systemSpeedData.currentIndex].bubbleSpeedMultiplier, self.sv.systemSpeedData.counter / self.sv.systemSpeedData.modifications[self.sv.systemSpeedData.currentIndex].increaseTime )
				end
			else
				if self.sv.systemSpeedData.counter >= self.sv.systemSpeedData.modifications[self.sv.systemSpeedData.currentIndex].increaseTime then
					if self.sv.systemSpeedData.currentModifier ~= self.sv.systemSpeedData.modifications[self.sv.systemSpeedData.currentIndex].bubbleSpeedMultiplier then
						self.sv.systemSpeedData.currentModifier = self.sv.systemSpeedData.modifications[self.sv.systemSpeedData.currentIndex].bubbleSpeedMultiplier
					end
				end
			end

			if self.sv.systemSpeedData.counter >= self.sv.systemSpeedData.modifications[self.sv.systemSpeedData.currentIndex].duration then
				self.sv.systemSpeedData.counter = 0
				self.sv.systemSpeedData.fromModifier = self.sv.systemSpeedData.modifications[self.sv.systemSpeedData.currentIndex].bubbleSpeedMultiplier
				self.sv.systemSpeedData.currentIndex = self.sv.systemSpeedData.currentIndex + 1
			end
			self.sv.systemSpeedData.counter = self.sv.systemSpeedData.counter + 1
		end
	end

	local totalTickLifetime = currentTick - self.sv.createTick
	local allPatternsDone = true
	for i = 1, #settings.patternSettings do
		local skipSpawn = false
		if totalTickLifetime >= self.sv.patternSpawnDelay[i] + self.sv.patternDurations[i] or self.sv.stopSystem then
			skipSpawn = true
		end
		local checkBoxSpawn = true



		if not skipSpawn and not self.sv.stopSystem and checkBoxSpawn then
			allPatternsDone = false
			if totalTickLifetime >= self.sv.patternSpawnDelay[i] then
				-- pattern rotation
				local radianRotationsPerSecond = self.sv.patternRadianRotationsPerTick[i]
				if self.sv.patternRadianRotationInvertThresholds[i] ~= nil and self.sv.easingDurations[i] ~= nil then
					-- modified rotation with easing
					self.sv.easingTickCounters[i] = self.sv.easingTickCounters[i] + 1
					local fraction = math.min( self.sv.easingTickCounters[i] / self.sv.easingDurations[i], 1.0 )
					fraction = sm.util.easing( self.sv.easingTypes[i], fraction )
					if self.sv.rotationModifiers[i] > 0 then
						self.sv.currentDirections[i] = self.sv.startingDirection[i]:rotate( self.sv.patternRadianRotationInvertThresholds[i] * fraction * self.sv.rotationModifiers[i], RotationAxis )
					else
						local startingDirection = self.sv.startingDirection[i]:rotate( self.sv.patternRadianRotationInvertThresholds[i], RotationAxis )
						self.sv.currentDirections[i] = startingDirection:rotate( self.sv.patternRadianRotationInvertThresholds[i] * fraction * self.sv.rotationModifiers[i], RotationAxis )
					end
				elseif self.sv.stepRotations[i] ~= nil then
					-- stepping rotation
					if self.sv.stepRotations[i].tickCounter >= self.sv.stepRotations[i].stepTicks then
						self.sv.stepRotations[i].tickCounter = 0
						self.sv.currentDirections[i] = self.sv.currentDirections[i]:rotate( self.sv.stepRotations[i].radianRotation * self.sv.rotationModifiers[i], RotationAxis )
						self.sv.accumulatedRotations[i] = self.sv.accumulatedRotations[i] + self.sv.stepRotations[i].radianRotation
					end
					self.sv.stepRotations[i].tickCounter = self.sv.stepRotations[i].tickCounter + 1
				elseif ( radianRotationsPerSecond ~= nil and radianRotationsPerSecond ~= 0.0 ) or self.sv.targetRotationPoints[i] ~= nil then
					-- regular rotation
					if self.sv.targetRotationPoints[i] ~= nil then
						local newRotationSpeed = self.sv.targetRotationPoints[i][#self.sv.targetRotationPoints[i]].targetRotationsPerTick
						for j,data in ipairs( self.sv.targetRotationPoints[i] ) do
							if ( totalTickLifetime - self.sv.patternSpawnDelay[i] ) < data.durationPoint then
								local fraction = ( totalTickLifetime - self.sv.patternSpawnDelay[i] ) / data.durationPoint
								if j > 1 then
									fraction = ( ( totalTickLifetime - self.sv.patternSpawnDelay[i] ) - self.sv.targetRotationPoints[i][j-1].durationPoint ) / ( data.durationPoint - self.sv.targetRotationPoints[i][j-1].durationPoint )
								end
								local fromRotation = j > 1 and self.sv.targetRotationPoints[i][j-1].targetRotationsPerTick or radianRotationsPerSecond
								newRotationSpeed = lerp( fromRotation, data.targetRotationsPerTick, fraction )
								break
							end
						end
						radianRotationsPerSecond = newRotationSpeed
					end
					self.sv.currentDirections[i] = self.sv.currentDirections[i]:rotate( radianRotationsPerSecond * self.sv.rotationModifiers[i], RotationAxis )
				end
				if radianRotationsPerSecond ~= nil and radianRotationsPerSecond ~= 0.0 then
					self.sv.accumulatedRotations[i] = self.sv.accumulatedRotations[i] + math.abs( radianRotationsPerSecond )
				end

				if  self.sv.patternRadianRotationInvertThresholds[i] ~= nil and self.sv.accumulatedRotations[i] >= self.sv.patternRadianRotationInvertThresholds[i] then
					-- reverse rotation direction
					self.sv.accumulatedRotations[i] = 0
					self.sv.rotationModifiers[i] = self.sv.rotationModifiers[i] * -1
					if self.sv.easingTickCounters[i] ~= nil then
						self.sv.easingTickCounters[i] = 0
					end
				end

				self.sv.spawnTickCounters[i] = self.sv.spawnTickCounters[i] + 1
				self.sv.skipFireCounters[i] = self.sv.skipFireCounters[i] - 1

				if self.sv.patternSkipIntervals[i] ~= nil and self.sv.fireDurationCounters[i] >= self.sv.patternSkipIntervals[i].fireDuration then
					self.sv.fireDurationCounters[i] = 0
					self.sv.skipFireCounters[i] = self.sv.patternSkipIntervals[i].skipDuration
				end
				if self.sv.skipFireCounters[i] <= 0 then
					self.sv.fireDurationCounters[i] = self.sv.fireDurationCounters[i] + 1
				end
				local spawnInterval = self.sv.bubbleSpawnTickInterval[i]
				if self.sv.targetSpawnIntervals[i] ~= nil then
					local targetSpawnInterval = self.sv.targetSpawnIntervals[i][#self.sv.targetSpawnIntervals[i]].targetInterval
					for j,data in ipairs( self.sv.targetSpawnIntervals[i] ) do
						if ( totalTickLifetime - self.sv.patternSpawnDelay[i] ) < data.durationPoint then
							local fraction = ( totalTickLifetime - self.sv.patternSpawnDelay[i] ) / data.durationPoint
							if j > 1 then
								fraction = ( ( totalTickLifetime - self.sv.patternSpawnDelay[i] ) - self.sv.targetSpawnIntervals[i][j-1].durationPoint ) / ( data.durationPoint - self.sv.targetSpawnIntervals[i][j-1].durationPoint )
							end
							local fromSpeed = j > 1 and self.sv.targetSpawnIntervals[i][j-1].targetInterval or self.sv.bubbleSpawnTickInterval[i]
							targetSpawnInterval = lerp( fromSpeed, data.targetInterval, fraction )
							break
						end
					end
					spawnInterval = targetSpawnInterval
				end
				if self.sv.spawnTickCounters[i] >= spawnInterval and self.sv.skipFireCounters[i] <= 0 then
					self.sv.spawnTickCounters[i] = 0
					local speedMultiplier = 1.0
					if self.sv.systemSpeedData ~= nil then
						speedMultiplier = self.sv.systemSpeedData.currentModifier
					end
					
					local speedOrigin = self.sv.projectileSpeeds[i]
					for b = 1, self.sv.splits[i] do
						local randomSpawnChance = math.random()
						if randomSpawnChance < self.sv.spawnChances[i] then
							local splitDirection = self.sv.currentDirections[i]
							if self.sv.fireAngles[i] ~= nil then
								local perpendicular = sm.vec3.cross( splitDirection, RotationAxis )
								splitDirection = splitDirection:rotate( self.sv.fireAngles[i], perpendicular )
							end
							if b > 1 then
								splitDirection = splitDirection:rotate( self.sv.radiansBetweenSplits[i] * ( b - 1 ), RotationAxis )
							end
							local spawnPosition = self.sv.origo + sm.vec3.new( 0, 0, BubbleSizes[self.sv.bubbleTypes[i]] )

							local source = self.sv.unit or self.sv.world
							
							local projectileSpawnSpeed = speedMultiplier * speedOrigin + self.sv.splitSpeedModifiers[i] * b
							local bubbleMaxLifetime = self.sv.bubbleMaxLifetimes[i]
							
							if self.sv.targetSpeeds[i] ~= nil then
								projectileSpawnSpeed = self.sv.targetSpeeds[i][#self.sv.targetSpeeds[i]].targetSpeed * speedMultiplier
								for j,data in ipairs( self.sv.targetSpeeds[i] ) do
									if ( totalTickLifetime - self.sv.patternSpawnDelay[i] ) < data.durationPoint then
										local fraction = ( totalTickLifetime - self.sv.patternSpawnDelay[i] ) / data.durationPoint
										if j > 1 then
											fraction = ( ( totalTickLifetime - self.sv.patternSpawnDelay[i] ) - self.sv.targetSpeeds[i][j-1].durationPoint ) / ( data.durationPoint - self.sv.targetSpeeds[i][j-1].durationPoint )
										end
										local fromSpeed = j > 1 and self.sv.targetSpeeds[i][j-1].targetSpeed or speedOrigin * speedMultiplier + self.sv.splitSpeedModifiers[i] * b
										projectileSpawnSpeed = lerp( fromSpeed, data.targetSpeed * speedMultiplier, fraction )
										break
									end
								end
							end
							
							bubbleMaxLifetime = math.floor( self.sv.bubbleMaxLifetimes[i] * ( speedOrigin / projectileSpawnSpeed ) )

							if self.sv.spawnShapeTypes[i].type == SpawnShapePresets.Single then
								sm.projectile.customProjectileAttack( { damagePlayer = true }, BubbleProjectiles[self.sv.bubbleTypes[i]], ProjectileDamage, spawnPosition, splitDirection * projectileSpawnSpeed, source, nil, nil, nil, self.sv.accelerations[i], bubbleMaxLifetime )
							else
								self:sv_spawnShapeType( spawnPosition, splitDirection, splitDirection * projectileSpawnSpeed, source, i, bubbleMaxLifetime )
							end
						end
					end
				end
			end
		end
	end

	if allPatternsDone and not self.sv.stopSystem then
		if settings.systemSettings ~= nil and settings.systemSettings.repeatCount ~= nil and self.sv.systemRepeatCounter < settings.systemSettings.repeatCount then
			allPatternsDone = false
			self.sv.systemRepeatCounter = self.sv.systemRepeatCounter + 1
			self.sv.createTick = currentTick
			if self.sv.systemSpeedData ~= nil then
				self.sv.systemSpeedData.counter = 0
				self.sv.systemSpeedData.fromModifier = 1.0
				self.sv.systemSpeedData.currentIndex = 1
				self.sv.systemSpeedData.currentModifier = 1.0
			end
			for i,_ in ipairs( self.sv.spawnTickCounters ) do
				self.sv.spawnTickCounters[i] = self.sv.bubbleSpawnTickInterval[i]
				self.sv.skipFireCounters[i] = 0
				self.sv.fireDurationCounters[i] = 0
			end
		end
	end
	
	if self.sv.stopSystem or ( allPatternsDone and self.sv.override == nil ) then
		if sm.exists( self.scriptableObject ) then
			self.scriptableObject:destroy()
		end
	end
end

function TrashPatternSpawner.sv_spawnShapeType( self, spawnPosition, direction, velocity, source, index, bubbleMaxLifetime )
	local amount = self.sv.spawnShapeTypes[index].values.amount
	if self.sv.spawnShapeTypes[index].type == SpawnShapePresets.Circle then
		for j = 1, amount do
			local newSpawnPos = spawnPosition + sm.vec3.new( self.sv.spawnShapeTypes[index].values.range, 0, 0 ):rotate( ( 360 / amount ) * j * math.pi / 180, RotationAxis )
			sm.projectile.customProjectileAttack( { damagePlayer = true }, BubbleProjectiles[self.sv.bubbleTypes[index]], 5, newSpawnPos, velocity, source, nil, nil, nil, self.sv.accelerations[i], bubbleMaxLifetime )
		end
	elseif self.sv.spawnShapeTypes[index].type == SpawnShapePresets.LineHorizontal then
		local perpendicularDirection = direction:cross( RotationAxis )
		local length = self.sv.spawnShapeTypes[index].values.range
		for j = 1, amount do
			local newSpawnPos = spawnPosition + perpendicularDirection * ( ( length / amount ) * j ) - perpendicularDirection * 0.5 * length
			sm.projectile.customProjectileAttack( { damagePlayer = true }, BubbleProjectiles[self.sv.bubbleTypes[index]], 5, newSpawnPos, velocity, source, nil, nil, nil, self.sv.accelerations[i], bubbleMaxLifetime )
		end
	elseif self.sv.spawnShapeTypes[index].type == SpawnShapePresets.LineVertical then
		local length = self.sv.spawnShapeTypes[index].values.range
		for j = 1, amount do
			local newSpawnPos = spawnPosition + direction * ( ( length / amount ) * j ) - direction * 0.5
			sm.projectile.customProjectileAttack( { damagePlayer = true }, BubbleProjectiles[self.sv.bubbleTypes[index]], 5, newSpawnPos, velocity, source, nil, nil, nil, self.sv.accelerations[i], bubbleMaxLifetime )
		end
	end
end