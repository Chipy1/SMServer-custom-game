-- GyroCoreCarryable.lua --
dofile("$SURVIVAL_DATA/Scripts/game/survival_shapes.lua")
dofile("$SURVIVAL_DATA/Scripts/game/survival_constants.lua")
dofile( "$SURVIVAL_DATA/Scripts/game/managers/TutorialManager.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/managers/QuestEntityManager.lua" )

local DroppedCoreMarkerName = "quest_bosstrain.marker_dropped_core"

GyroCoreCarryable = class( nil )

function GyroCoreCarryable.server_onCreate( self )
	self.sv = {}
	self.sv.saved = self.storage:load()
	if self.sv.saved == nil then
		self.sv.saved = {}
		-- Carry data is transferred from the player when dropping
		local carryData = self.interactable:getCarryData()
		if carryData then
			self.sv.saved.pickupTick = carryData.pickupTick
		end
		self.storage:save( self.sv.saved )
	end
	if self.sv.saved.pickupTick then
		self.interactable:setCarryData( { pickupTick = self.sv.saved.pickupTick } )
		QuestEntityManager.Sv_RegisterHostedQuestMarker( self.shape, sm.vec3.new( 0, 0, 0.5 ), true, DroppedCoreMarkerName )
	end

	self.sv.lastPosition = self.shape:getWorldPosition()
	self.sv.world = self.shape:getBody():getWorld()

	NodeSpawnManager.Sv_ResetSpawnTrigger( "respawn.gyrocore" )
end

function GyroCoreCarryable.server_onDestroy( self )
	QuestEntityManager.Sv_UnregisterHostedQuestMarker( DroppedCoreMarkerName )
end

function GyroCoreCarryable.client_onCreate( self )
	QuestEntityManager.Cl_BumpHostedQuestMarker( DroppedCoreMarkerName )
end

function GyroCoreCarryable.server_onFixedUpdate( self, dt )
	if self.sv.saved.pickupTick then
		local currentTick = sm.game.getCurrentTick()
		local elapsedTicks = currentTick - self.sv.saved.pickupTick

		if elapsedTicks > GYRO_CORE_TIMEOUT_TICKS then
			sm.log.info( "GyroCoreCarryable: Gyro core timeout reached (" .. elapsedTicks .. " > " .. GYRO_CORE_TIMEOUT_TICKS .. "), destroying core" )
			sm.shape.destroyShape( self.shape )
		end
	end
end

