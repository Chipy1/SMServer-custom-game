dofile "$SURVIVAL_DATA/Scripts/game/survival_constants.lua"
dofile "$SURVIVAL_DATA/Scripts/game/survival_units.lua"
dofile "$SURVIVAL_DATA/Scripts/game/util/Timer.lua"
dofile "$CHALLENGE_DATA/Scripts/challenge/world_util.lua"
dofile "$SURVIVAL_DATA/Scripts/game/survival_collections.lua"
dofile "$SURVIVAL_DATA/Scripts/util.lua"

-- Server side
UnitManager = class( nil )

local NoiseShapeSettings = {
	[tostring( obj_interactive_radio )] = { noiseRadius = 40 },
	["d5e36413-b3c1-4636-8447-3410c352ec7b"] = { noiseRadius = 20 }, -- creative gas engine
	[tostring( obj_scrap_gasengine )] = { noiseRadius = 20 },
	[tostring( obj_interactive_gasengine_01 )] = { noiseRadius = 20 },
	[tostring( obj_interactive_gasengine_02 )] = { noiseRadius = 20 },
	[tostring( obj_interactive_gasengine_03 )] = { noiseRadius = 20 },
	[tostring( obj_interactive_gasengine_04 )] = { noiseRadius = 20 },
	[tostring( obj_interactive_gasengine_05 )] = { noiseRadius = 20 },
	["6546c293-a5aa-4442-80d5-a2819f077746"] = { noiseRadius = 20 }, -- creative electric engine
	[tostring( obj_interactive_electricengine_01 )] = { noiseRadius = 20 },
	[tostring( obj_interactive_electricengine_02 )] = { noiseRadius = 20 },
	[tostring( obj_interactive_electricengine_03 )] = { noiseRadius = 20 },
	[tostring( obj_interactive_electricengine_04 )] = { noiseRadius = 20 },
	[tostring( obj_interactive_electricengine_05 )] = { noiseRadius = 20 },
	["5e96037a-a338-490a-a76f-6b4d820f8e46"] = { noiseRadius = 20 }, -- creative thruster
	[tostring( obj_interactive_thruster_01 )] = { noiseRadius = 20 },
	[tostring( obj_interactive_thruster_02 )] = { noiseRadius = 20 },
	[tostring( obj_interactive_thruster_03 )] = { noiseRadius = 20 },
	[tostring( obj_interactive_thruster_04 )] = { noiseRadius = 20 },
	[tostring( obj_interactive_thruster_05 )] = { noiseRadius = 20 },
	[tostring( obj_interactive_horn )] = { noiseRadius = 40 },
	[tostring( obj_interactive_robotbasshead )] = { noiseRadius = 40 },
	[tostring( obj_interactive_robotdrumhead )] = { noiseRadius = 40 },
	[tostring( obj_interactive_robotsynthhead )] = { noiseRadius = 40 },
	[tostring( obj_interactive_robotbliphead01 )] = { noiseRadius = 40 }
}

local BotCapsules = {
	sm.uuid.new( "34d22fc5-0a45-4d71-9aaf-64df1355c272" ), -- Totebot
	sm.uuid.new( "da993c70-ba90-4748-8a22-6246bad32930" ), -- Haybot
	sm.uuid.new( "4c5c3ffd-9aaf-4ded-a7c5-452d239cac32" ), -- Tapebot
	sm.uuid.new( "50f624e6-7e33-4118-8252-2219e73e9af1" ), -- Red Tapebot
	sm.uuid.new( "9c1f1f76-7391-4661-ae32-e96250030229" ), -- Farmbot
	sm.uuid.new( "cd76f081-0116-4eb3-a3f7-0440d844265a" ), -- Minerbot
	sm.uuid.new( "dd5c9a11-0f9c-4485-93b9-bac54b8ebe5f" ), -- Green Tapebot
	sm.uuid.new( "7eed9369-e813-4dbe-a283-fb160452a7fa" ), -- Yellow Tapebot
	sm.uuid.new( "cde543b1-65b6-4db6-9c5c-2b990154bf4f" ), -- Blue Totebot
	sm.uuid.new( "acadcfa4-53d4-428f-b509-b1f1cb14b455" ), -- Yellow Totebot
	sm.uuid.new( "3c98515e-78c0-4544-8b13-7a1b06673081" ), -- Red Totebot
	sm.uuid.new( "9492cea6-2417-416f-b801-2e85260c5906" ), -- Cablebot
	sm.uuid.new( "65fe80e6-5606-4747-a1c4-c2208167c815" )  -- Cablebot multi
}
local AnimalCapsules = {
	sm.uuid.new( "7735cab3-56d7-4d52-b615-090d021e8fdc" ), -- Glowgorp
	sm.uuid.new( "12cc6e9a-6d66-4a9a-bb59-b13a50373fd8" )  -- Woc
}

local DefaultHostSettings = {
	aggroCreations = false
}

local function refreshHostSettings( savedHostSettings )
	-- Remove deprecated host settings
	for key, val in pairs( savedHostSettings ) do
		if DefaultHostSettings[key] == nil then
			savedHostSettings[key] = nil
		end
	end

	-- Add new host settings
	for key, val in pairs( DefaultHostSettings ) do
		if savedHostSettings[key] == nil then
			savedHostSettings[key] = val
		end
	end

	return savedHostSettings
end

function UnitManager.sv_onCreate( self, overworld, DefaultHostSettingsOverride )
	-- Overwrite the DefaultHostSettings with game mode specific settings
	if DefaultHostSettingsOverride then
		for key, val in pairs( DefaultHostSettingsOverride ) do
			DefaultHostSettings[key] = val
		end
	end

	self.sv = {}
	self.saved = sm.storage.load( STORAGE_CHANNEL_UNIT_MANAGER )

	if self.saved then
		print( "Loaded UnitManager:" )
		print( self.saved )
		local savedVersion = self.saved.version and self.saved.version or 1
		if savedVersion == 1 then
			self.saved.unitGroups = nil
			self.saved.dailyUnitGroupId = nil
			self.saved.nextUnitGroupId = nil
			self.saved.version = 2
			print( "Upgraded UnitManager:" )
			print( self.saved )
		end

		-- Load host settings
		if self.saved.hostSettings == nil then
			self.saved.hostSettings = DefaultHostSettings
		else
			self.saved.hostSettings = refreshHostSettings( self.saved.hostSettings )
		end
	else
		self.saved = {}
		self.saved.version = 2

		self.saved.deathMarkers = {}
		self.saved.deathMarkerNextIndex = 1

		self.saved.hostSettings = DefaultHostSettings
		self:sv_save()
	end

	self.overworld = overworld

	self.deathMarkerMaxIndex = 100
	self.dangerousInteractables = {}

	self.noiseInteractables = {}
	self.activeNoiseInteractables = {}

	self.botCapsuleInteractables = {}
	self.animalCapsuleInteractables = {}

	self.elevatorFloorInteractables = {}
end

function UnitManager.sv_getHostSettings( self )
	return self.saved.hostSettings
end

function UnitManager.sv_setHostSettings( self, hostSettings )
	for key, val in pairs( hostSettings ) do
		if self.saved.hostSettings[key] ~= nil then
			self.saved.hostSettings[key] = val
		end
	end
	self:sv_save()
end

-- Game environment
function UnitManager.sv_onFixedUpdate( self )

	-- Update table of interactables currently making noise
	self.activeNoiseInteractables = {}
	local validNoiseInteractables = {}
	for _, interactable in ipairs( self.noiseInteractables ) do
		if sm.exists( interactable ) then
			validNoiseInteractables[#validNoiseInteractables+1] = interactable

			-- Check if active
			local makingNoise = interactable.active
			if not makingNoise then
				-- Check if activated by a parent
				local logicParents = interactable:getParents( sm.interactable.connectionType.logic )
				for _, logicParent in ipairs( logicParents ) do
					makingNoise = makingNoise or logicParent.active
				end
			end
			if not makingNoise then
				-- Check if actuating bearings
				local bearings = GetBearingEnabledJoints( interactable )
				for _, bearing in ipairs( bearings ) do
					local lowSpeedNotZero = 0.2
					makingNoise = makingNoise or math.abs( bearing:getAngularVelocity() ) >= lowSpeedNotZero
				end
			end

			if makingNoise then
				self.activeNoiseInteractables[#self.activeNoiseInteractables+1] = interactable
			end
		end
	end
	self.noiseInteractables = validNoiseInteractables
end

function UnitManager.sv_save( self )
	sm.storage.save( STORAGE_CHANNEL_UNIT_MANAGER, self.saved )
end

local function openCapsules( capsuleInteractables )
	for _, capsuleInteractable in ipairs( capsuleInteractables ) do
		if sm.exists( capsuleInteractable ) then
			sm.event.sendToInteractable( capsuleInteractable, "sv_e_open" )
		end
	end
end

function UnitManager.sv_openCapsules( self, filter )
	if filter == nil then
		openCapsules( self.botCapsuleInteractables )
		openCapsules( self.animalCapsuleInteractables )
	elseif filter == "bot" then
		openCapsules( self.botCapsuleInteractables )
	elseif filter == "animal" then
		openCapsules( self.animalCapsuleInteractables )
	else
		sm.gui.chatMessage( "No such filter: '" .. filter .. "'" )
	end
end

function UnitManager.sv_getElevatorsByDistance( self, character )
	local elevatorsInWorld = {}
	for _, elevatorInteractable in ipairs( self.elevatorFloorInteractables ) do
		if sm.exists( elevatorInteractable ) and InSameWorld( elevatorInteractable, character ) then
			elevatorsInWorld[#elevatorsInWorld+1] = elevatorInteractable
		end
	end
	table.sort( elevatorsInWorld, function( a, b ) return ( a.shape.worldPosition - character.worldPosition ):length2() < ( b.shape.worldPosition - character.worldPosition ):length2() end )
	return elevatorsInWorld
end

function UnitManager.sv_addDeathMarker( self, position, reason )
	local deathMarker = { position = position, timeStamp = sm.game.getCurrentTick(), reason = reason  }
	self.saved.deathMarkers[self.saved.deathMarkerNextIndex] = deathMarker
	self.saved.deathMarkerNextIndex = ( self.saved.deathMarkerNextIndex % ( self.deathMarkerMaxIndex ) ) + 1
	self:sv_save()
end

function UnitManager.sv_getClosestDangers( self, position )

	local closestInteractable = nil
	local closestInteractableDistance = nil
	local validInteractables = {}
	for _, interactable in ipairs( self.dangerousInteractables ) do
		if sm.exists( interactable ) and interactable.shape then
			validInteractables[#validInteractables+1] = interactable
			if closestInteractableDistance then
				local distance = ( interactable.shape.worldPosition - position ):length2()
				if distance < closestInteractableDistance then
					closestInteractable = interactable
					closestInteractableDistance = distance
				end
			else
				closestInteractable = interactable
				closestInteractableDistance = ( interactable.shape.worldPosition - position ):length2()
			end
		end
	end
	self.dangerousInteractables = validInteractables

	local closestMarker = nil
	local closestMarkerDistance = nil
	for _, deathMarker in ipairs( self.saved.deathMarkers ) do
		if closestMarkerDistance then
			local distance = ( deathMarker.position - position ):length2()
			if distance < closestMarkerDistance then
				closestMarker = deathMarker
				closestMarkerDistance = distance
			end
		else
			closestMarker = deathMarker
			closestMarkerDistance = ( deathMarker.position - position ):length2()
		end
	end

	local closestShape = nil
	if closestInteractable then
		closestShape = closestInteractable.shape
	end
	return closestShape, closestMarker

end

function UnitManager.sv_getClosestNoiseShape( self, position, radius )
	local closestInteractable = nil
	local closestInteractableDistance = nil
	for _, interactable in ipairs( self.activeNoiseInteractables ) do
		if sm.exists( interactable ) and interactable.shape then
			local distance = ( interactable.shape.worldPosition - position ):length2()
			local noiseShapeSetting = NoiseShapeSettings[tostring(interactable.shape.shapeUuid)]
			if noiseShapeSetting then
				if closestInteractableDistance then
					if distance < closestInteractableDistance and distance <= noiseShapeSetting.noiseRadius * noiseShapeSetting.noiseRadius then
						closestInteractable = interactable
						closestInteractableDistance = distance
					end
				else
					if distance <= radius * radius and distance <= noiseShapeSetting.noiseRadius * noiseShapeSetting.noiseRadius then
						closestInteractable = interactable
						closestInteractableDistance = ( interactable.shape.worldPosition - position ):length2()
					end
				end
			end
		end
	end

	local closestShape = nil
	if closestInteractable then
		closestShape = closestInteractable.shape
	end
	return closestShape
end

-- World --

function UnitManager.sv_onInteractableCreated( self, interactable )
	if interactable.shape then
		if isDangerousCollisionShape( interactable.shape.shapeUuid ) then
			addToArrayIfNotExists( self.dangerousInteractables, interactable )
		end

		if isAnyOf( interactable.shape.shapeUuid, BotCapsules ) then
			addToArrayIfNotExists( self.botCapsuleInteractables, interactable )
		elseif isAnyOf( interactable.shape.shapeUuid, AnimalCapsules ) then
			addToArrayIfNotExists( self.animalCapsuleInteractables, interactable )
		end

		if NoiseShapeSettings[tostring(interactable.shape.shapeUuid)] ~= nil then
			addToArrayIfNotExists( self.noiseInteractables, interactable )
		end

		if interactable.shape.shapeUuid == obj_survivalobject_elevatorfloor then
			addToArrayIfNotExists( self.elevatorFloorInteractables, interactable )
		end
	end
end

function UnitManager.sv_onInteractableDestroyed( self, interactable )
	removeFromArray( self.dangerousInteractables, function( value ) return value == interactable end )
	removeFromArray( self.botCapsuleInteractables, function( value ) return value == interactable end )
	removeFromArray( self.animalCapsuleInteractables, function( value ) return value == interactable end )
	removeFromArray( self.noiseInteractables, function( value ) return value == interactable end )
	removeFromArray( self.elevatorFloorInteractables, function( value ) return value == interactable end )
end

function UnitManager.sv_onWorldCollision( self, worldSelf, objectA, objectB, collisionPosition, objectAPointVelocity, objectBPointVelocity, collisionNormal )
	local impactVelocity = math.abs( ( objectAPointVelocity - objectBPointVelocity ):dot( collisionNormal ) )
	if impactVelocity > 3 then
		local detectA = false
		local detectB = false
		if type( objectA ) == "Character" and sm.exists( objectA ) then
			detectA = objectA:isPlayer() and sm.game.getEnableAggro()
		elseif type( objectA ) == "Shape" and sm.exists( objectA ) and objectA.body:isDynamic() then
			detectA = true
		end
		if type( objectB ) == "Character" and sm.exists( objectB ) then
			detectB = objectB:isPlayer() and sm.game.getEnableAggro()
		elseif type( objectB ) == "Shape" and sm.exists( objectB ) and objectB.body:isDynamic() then
			detectB = true
		end

		local impactEnergy = 0
		if detectA and detectB then
			impactEnergy = ( objectA.mass * objectB.mass / ( objectA.mass + objectB.mass ) ) * ( objectAPointVelocity - objectBPointVelocity ):length2() / 2000.0
		else
			if detectA then
				impactEnergy = impactEnergy + objectAPointVelocity:length2() * objectA.mass / 2000.0
			end
			if detectB then
				impactEnergy = impactEnergy + objectBPointVelocity:length2() * objectB.mass / 2000.0
			end
		end
		if impactEnergy > 0.0 then
			sm.message.send( MESSAGE_TYPES.GENERAL.Collision, { world = worldSelf.world, position = collisionPosition, impactEnergy = impactEnergy } )
		end
	end
end