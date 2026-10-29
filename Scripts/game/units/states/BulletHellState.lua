dofile( "$SURVIVAL_DATA/Scripts/game/units/states/BaseState.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/survival_constants.lua" )

BulletHellState = class( BaseState )

local BulletSystem = sm.uuid.new( "fe702672-27f3-4068-82c9-ffb729f2c6ee" )

function BulletHellState.sv_onCreate( self, unit )
	self.unit = unit
	self.fightType = unit.publicData.fightType or 1
	self.activeSystems = {}
	self.lookDirection = sm.vec3.new( 1, 0, 0 )
	self.unitLookDirection = sm.vec3.new( 1, 0, 0 )
	self.worldPosition = self.unit.character:getWorldPosition()
	self.world = self.unit.character:getWorld()
	self.stageIndex = 1
	self.origin = self.unit.character.worldPosition
	self.nextSystem = nil
	self.currentSystems = nil
	self.delayCounter = 0
	self.currentLoop = nil
	self.deactivated = false
end

function BulletHellState.sv_setLookDirection( self, newDirection )
	self.unitLookDirection = newDirection:safeNormalize( sm.vec3.new( 1, 0, 0 ) )
end

function BulletHellState.refresh( self ) end

function BulletHellState.sv_setPosition( self, worldPosition )
	self.worldPosition = worldPosition
end

function BulletHellState.sv_setTarget( self, target )
	if self.target == nil then
		self.target = target
	end
end

function BulletHellState.sv_setStage( self, stageIndex )
	self.stageIndex = stageIndex
end

function BulletHellState.sv_selectNextState( self )
	if self.currentLoop == nil then
		return
	end
	local patterns = TRASHBOT_BULLET_HELL_SETTINGS[self.fightType][self.stageIndex]
	if patterns[self.currentLoop] then
		if self.currentSystems == nil then
			self.nextSystem = patterns[self.currentLoop][1]
			self.delayCounter = 0
		else
			self.nextSystem = patterns[self.currentLoop][self.currentSystems.nextPatternIndex]
			self.delayCounter = 0
		end
	end
end

function BulletHellState.sv_updateBulletHellState( self, dt )
	local hasTimedOut = false
	for _,systemData in ipairs( self.activeSystems ) do
		if systemData.durationCounter >= systemData.duration or self.currentSystems == nil then
			hasTimedOut = true
			for _,system in ipairs( systemData.systems ) do
				if sm.exists( system ) then
					sm.event.sendToScriptableObject( system, "sv_e_stopSystem" )
				end
			end
		end
		systemData.delayCounter = systemData.delayCounter + 1
		systemData.durationCounter = systemData.durationCounter + 1
	end
	
	if ( self.currentSystems == nil or hasTimedOut ) and self.nextSystem == nil then
		self.activeSystems = {}
		self:sv_selectNextState()
	end
	
	if self.nextSystem ~= nil then
		self.delayCounter = self.delayCounter + 1
		
		if self.delayCounter >= math.floor( self.nextSystem.activationDelay * 40 ) then
			local newSystem = { durationCounter = 0, delayCounter = 0, systems = {} }
			print( "starting pattern: ", self.nextSystem.sequenceName )
			for _,systemName in ipairs( self.nextSystem.systemList ) do
				local params = {}
				params.position = self.worldPosition - sm.vec3.new( 0, 0, 1.5 )
				params.direction = self.nextSystem.useUnitRotation and self.unitLookDirection or self.lookDirection
				params.override = sm.json.open( "$SURVIVAL_DATA/Scripts/game/trashbot/TrashbotPatterns/"..systemName..".trashbotpattern" )
				params.unit = self.unit
				if self.nextSystem.duration ~= nil then
					newSystem.duration = math.floor( self.nextSystem.duration * 40 )
				else
					local bestTime = 0.0
					for _,settings in ipairs( params.override.patternSettings ) do
						local delay = settings.activationDelay or 0.0
						if bestTime < settings.duration + delay then
							bestTime = settings.duration + delay
						end
					end
					newSystem.duration = math.floor( bestTime * 40 )
				end
				newSystem.systems[#newSystem.systems+1] = sm.scriptableObject.createScriptableObject( BulletSystem, params, self.world )
			end
			table.insert( self.activeSystems, newSystem )
			self.currentSystems = shallowcopy( self.nextSystem )
			self.nextSystem = nil
		end
	end
	
end

--[[API functions]]

function BulletHellState.start( self )
	if not self.deactivated then
		self.active = true
	end
end

function BulletHellState.stun( self )
	self.active = false
	for _,systemData in ipairs( self.activeSystems ) do
		for _,system in ipairs( systemData.systems ) do
			if sm.exists( system ) then
				sm.event.sendToScriptableObject( system, "sv_e_removeSystem" )
			end
		end
	end
	self.activeSystems = {}
	self.currentLoop = nil
	self.currentSystems = nil
end

function BulletHellState.deactivate( self )
	self.active = false
	for _,systemData in ipairs( self.activeSystems ) do
		for _,system in ipairs( systemData.systems ) do
			if sm.exists( system ) then
				sm.event.sendToScriptableObject( system, "sv_e_removeSystem" )
			end
		end
	end
	self.activeSystems = {}
	self.currentLoop = nil
	self.currentSystems = nil
	self.deactivated = true
end

function BulletHellState.setPatternName( self, name )
	if self.currentLoop ~= name then
		self.currentLoop = name
		self.currentSystems = nil
	end
end

function BulletHellState.onFixedUpdate( self, dt )






	self.target = sm.exists( self.target ) and self.target or nil
	if self.target and self.active then
		self:sv_updateBulletHellState( dt )
	end
end

function BulletHellState.isActive( self )
	return self.active
end