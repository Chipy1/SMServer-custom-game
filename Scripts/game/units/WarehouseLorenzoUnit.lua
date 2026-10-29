dofile( "$SURVIVAL_DATA/Scripts/game/units/unit_util.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/units/states/QuestWaypointState.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/managers/QuestManager.lua" )

WarehouseLorenzoUnit = class( BaseUnit )

function WarehouseLorenzoUnit.server_onDestroy( self )
	if self.saved.markedForRemoval then
		WaypointQuestUnitManager.Sv_RemoveWaypointQuestUnit( self.unit )
		sm.unit.forceDestroy( self.unit )
	end
end

function WarehouseLorenzoUnit.server_onCreate( self )
	self.saved = self.storage:load()
	if self.saved == nil then
		self.saved = {}
	end

    self.unit:setWhiskerData( 4, math.rad( 70.0 ), 1.0, 4.75 )

	-- Idle
	self.idleState = self.unit:createState( "idle" )
	self.idleState.debugName = "idleState"

    self.questWaypointState = QuestWaypointState()
    self.questWaypointState:sv_onCreate( self.unit )
    self.questWaypointState.debugName = "questWaypointState"

	self.currentState = self.idleState
	self.currentState:start()

	QuestManager.Sv_RegisterQuestUnit( QuestUnits[self.data.questUnitName], self.unit )
	QuestManager.Sv_SendEvent( QuestEvent.QuestUnitCreated, { character = self.unit.character, questUnitEnum = QuestUnits[self.data.questUnitName] } )

	if self.params then
		if self.params.spawnTrigger then
			NodeSpawnManager.Sv_DeactivateSpawnTrigger( self.params.spawnTrigger )
		end
		if self.params.characterSpawnEvent then
			self.unit:sendCharacterEvent( self.params.characterSpawnEvent )
		end
		if self.params.respawnWaypointQuestUnitId then
			WaypointQuestUnitManager.Sv_OnRespawnWithWaypointQuestUnitId( self.unit, self.params.respawnWaypointQuestUnitId )
		end
		self.storage:save( self.saved )
	end

	print( "-- WarehouseLorenzoUnit created --" )
end

function WarehouseLorenzoUnit.server_onRefresh( self )
	print( "-- WarehouseLorenzoUnit refreshed --" )
end

function WarehouseLorenzoUnit.sv_saveData( self )
    --self.storage:save( self.saved )
end

function WarehouseLorenzoUnit.server_onFixedUpdate( self, dt )
	if self.currentState then
		self.currentState:onFixedUpdate( dt )
		self.unit:setMovementDirection( self.currentState:getMovementDirection() )
		self.unit:setMovementType( self.currentState:getMovementType())
		self.unit:setFacingDirection( self.currentState:getFacingDirection() )
	end
end

function WarehouseLorenzoUnit.server_onUnitUpdate( self, dt )
	if not sm.exists( self.unit ) then
		return
	end
	if self.currentState then
		self.currentState:onUnitUpdate( dt )
	end

	local questWaypointData = WaypointQuestUnitManager.Sv_GetWaypointQuestUnit( self.unit )
	local prevState = self.currentState
	local done, _ = self.currentState:isDone()
	if done then
		-- Select state
		if questWaypointData then
			self.currentState = self.questWaypointState

			-- Make Lorenzo immovable as soon as he's walked up to the console
			local character = self.unit.character
			if character and not character:getImmovable() then
				local waypointObject = self.currentState:sv_getWaypointObject( questWaypointData.quest )
				if waypointObject and ( waypointObject.characterEvent == "emote_countdown_in" or waypointObject.characterEvent == "emote_countdown_loop" ) then
					self.unit.character:setImmovable( true )
				end
			end
		else
			self.currentState = self.idleState
		end
	end

	if prevState ~= self.currentState then
		prevState:stop()
		self.currentState:start()
	end
end

function WarehouseLorenzoUnit.sv_e_onInteract( self, params )
    QuestManager.Sv_SendEvent( QuestEvent.QuestUnitInteract, { questUnitEnum = QuestUnits[self.data.questUnitName], player = params.player } )
end

function WarehouseLorenzoUnit.server_onMelee( self, hitPos, attacker, damage, power, hitDirection ) end

function WarehouseLorenzoUnit.server_onProjectile( self, hitPos, hitTime, hitVelocity, _, attacker, damage, userData, hitNormal, projectileUuid ) end
