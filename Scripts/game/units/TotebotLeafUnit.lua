dofile "$SURVIVAL_DATA/Scripts/game/units/unit_util.lua"
dofile "$SURVIVAL_DATA/Scripts/util.lua"
dofile "$SURVIVAL_DATA/Scripts/game/survival_units.lua"
dofile "$SURVIVAL_DATA/Scripts/game/survival_constants.lua"
dofile "$SURVIVAL_DATA/Scripts/game/units/BaseUnit.lua"
dofile "$SURVIVAL_DATA/Scripts/game/units/TotebotGreenUnit.lua"


TotebotLeafUnit = class( TotebotGreenUnit )

local StandardVisionFrustum = {
	{ 3.0, math.rad( 80.0 ), math.rad( 80.0 ) },
	{ 20.0, math.rad( 40.0 ), math.rad( 35.0 ) },
	{ 40.0, math.rad( 20.0 ), math.rad( 20.0 ) }
}

local DormantVisionFrustum = {
	{ 1.0, math.rad( 40.0 ), math.rad( 40.0 ) },
	{ 5.0, math.rad( 20.0 ), math.rad( 20.0 ) },
	{ 40.0, math.rad( 7.0 ), math.rad( 7.0 ) }
}

function TotebotLeafUnit.server_onCreate( self )
	TotebotGreenUnit.server_onCreate( self )
	self.jumpChancePerSecond = 40.0
	if self.saved.leafActive == nil then
		self.saved.leafActive = true
	end
	self.dormant = self.saved.leafActive
	if self.dormant then
		self.unit.visionFrustum = DormantVisionFrustum
		self.noiseScale = 0.0
	end

	sm.event.sendToCharacter( self.unit.character, "sv_e_setLeafState", self.saved.leafActive, sm.event.types.blind )
	self.storage:save( self.saved )
end

function TotebotLeafUnit.server_onCharacterChangedColor( self, color )
	if self.saved.color ~= color then
		self.saved.color = color
		self.storage:save( self.saved )
	end
end

function TotebotLeafUnit.server_onUnitUpdate( self, dt )
	if self.dormant then
		-- The leaf totebot is in it's dormant state until detecting a target
		self.eventTarget = nil
		self.eventNoisePosition = nil
		RobotSelectTarget( self, 0, dt )
		if self.target then
			self.dormant = false
			self.noiseScale = 1.0
			self.unit.visionFrustum = StandardVisionFrustum
		end

		-- Dormant totebot is always in idle
		local prevState = self.currentState
		self.currentState = self.idleState
		if prevState ~= self.currentState then
			prevState:stop()
			self.currentState:start()
		end
	else
		TotebotGreenUnit.server_onUnitUpdate( self, dt )
	end
end

function TotebotLeafUnit.sv_takeDamage( self, damage, impact, hitPos, source )
	TotebotGreenUnit.sv_takeDamage( self, damage, impact, hitPos, source )

	self.dormant = false
	self.noiseScale = 1.0
	self.unit.visionFrustum = StandardVisionFrustum
	if self.saved.stats.hp > 0 then
		-- If still alive, trigger leaf removal
		if self.saved.leafActive then
			self.saved.leafActive = false
			self.storage:save( self.saved )
			sm.event.sendToCharacter( self.unit.character, "sv_e_setLeafState", self.saved.leafActive )
		end
	end
end
