dofile( "$SURVIVAL_DATA/Scripts/game/managers/UndergroundElevatorManager.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/managers/QuestManager.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/managers/DialogManager.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/managers/LogEntryManager.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/survival_dialogs.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/quests/BosstrainQuest.lua" )

UndergroundMainElevator = class()
UndergroundMainElevator.poseWeightCount = 3

local Drill1FloorIndex = 5
local Drill1WarningCooldownTicks = 10 * 40
local ScrapyardFloorIndex = 6
local ScrapyardWarningCooldownTicks = 5 * 40

local buttons = {
	UP = {
		poseIndex = 0,
		effectName = "Survivalobject - ElevatorSmallButton_use",
		effectOffset = sm.vec3.new( -0.42, 0.0, 0.0 )
	},
	DOWN = {
		poseIndex = 1,
		effectName = "Survivalobject - ElevatorSmallButton_use",
		effectOffset = sm.vec3.new( -0.42, 0.0, 0.0 )
	},
	USE = {
		poseIndex = 2,
		effectName = "Survivalobject - Elevatorkeyreaderunlock_use",
		effectOffset = sm.vec3.new( 0.42, 0.0, 0.0 )
	}
}
local ButtonPressDuration = 0.1
local ButtonPoseSpeed = 15.0
local LightOffDelay = 0.1

function UndergroundMainElevator.server_onCreate( self )
    self.sv = {}
    self.sv.saved = self.storage:load()

    if not self.sv.saved then
        self.sv.saved = {}
        self.sv.saved.connectionTag = UndergroundElevatorManager.Sv_FindUndergroundConnectionTag( self.tags )
        self.storage:save( self.sv.saved )

    	local storageKey = TileStorageManager.Sv_GetTileStorageKeyFromObject( self.interactable )
		local tileData = TileStorageManager.Sv_GetValueInSubTable( storageKey, UNDERGROUND_ELEVATOR_TABLE, self.sv.saved.connectionTag ) or {}
		tileData.elevator = self.interactable
		tileData.locked = true
		tileData.lockUuid = UNDERGROUND_CONNECTION_TO_KEY_UUID[self.sv.saved.connectionTag]
		TileStorageManager.Sv_SetValueInSubTable( storageKey, UNDERGROUND_ELEVATOR_TABLE, self.sv.saved.connectionTag, tileData )
    end

	self.sv.elevatorName = CONNECTION_TO_ELEVATOR_NAME[self.sv.saved.connectionTag]

	self.sv.elevatorFloorIndex = UndergroundElevatorManager.Sv_FindElevatorFloor( sm.world.getCurrentWorld(), self.sv.saved.connectionTag )
	assert( self.sv.elevatorFloorIndex, "Elevator floor not found" )
	self.sv.targetFloor = self.sv.elevatorFloorIndex

	local transportArea = FindFirstNearbyNode( self.shape.worldPosition, { "UNDERGROUND_ELEVATOR_AREA", self.sv.saved.connectionTag } )
	if transportArea then
		UndergroundElevatorManager.Sv_RegisterElevatorFloor( self.sv.elevatorName, self.sv.elevatorFloorIndex, sm.world.getCurrentWorld(), self.shape.worldPosition, self.sv.saved.connectionTag, transportArea )
	end
	self:sv_updateClientData()

	self.sv.logRevision = LogEntryManager.Sv_GetLogRevision()
	self.sv.displayInitialized = self:sv_notifyDepthBots()
end

function UndergroundMainElevator.client_onCreate( self )
	self.cl = {}
	self.cl.pressedButton = nil
	self.cl.buttonPressTimer = 0
	self.cl.buttonPoseWeight = 0
	self:cl_updateButtonPoseWeights()
end

function UndergroundMainElevator.sv_updateClientData( self )
	local clientData = {
		locked = self:sv_isFloorLocked( self.sv.targetFloor ),
		logRevision = self.sv.logRevision,
		canGo = UndergroundElevatorManager.Sv_CanGo( self.sv.elevatorName, nil ),
	}
	self.network:setClientData( clientData )
end

function UndergroundMainElevator.client_onClientDataUpdate( self, params )
	self.cl.locked = params.locked == true
	self.cl.canGo = params.canGo == true
end

function UndergroundMainElevator.server_onFixedUpdate( self )
	-- The depthbot may not have registered itself in tile storage when this elevator was
	-- created, so keep polling until the display is reached and updated at least once.
	if not self.sv.displayInitialized then
		self.sv.displayInitialized = self:sv_notifyDepthBots()
	end

	local currentRevision = LogEntryManager.Sv_GetLogRevision()
	local scrapyardUnlocked = self.sv.elevatorName == "MAIN" and UndergroundElevatorManager.Sv_IsScrapyardUnlocked( "MAIN" )
	local canGo = UndergroundElevatorManager.Sv_CanGo( self.sv.elevatorName, nil )

	if ( not self.sv.logRevision ) or self.sv.logRevision < currentRevision or self.sv.scrapyardUnlocked ~= scrapyardUnlocked then
		self.sv.logRevision = currentRevision
		self.sv.scrapyardUnlocked = scrapyardUnlocked
		self:sv_updateClientData()
		self:sv_notifyDepthBots()
	elseif self.sv.canGo ~= canGo then
		self.sv.canGo = canGo
		self:sv_updateClientData()
		self:sv_notifyDepthBots()
	end
end

function UndergroundMainElevator.sv_isQuestLocked( self )
	if self.sv.elevatorName ~= "MAIN" then
		return false
	end
	if QuestManager.Sv_IsQuestActive( "quest_bosstrain" ) then
		return QuestManager.Sv_GetQuestStage( "quest_bosstrain" ) == BosstrainQuest.Stages.p1_unlock_elevator
	end
	return false
end

function UndergroundMainElevator.sv_getNumLocked( self )
	if self.sv.elevatorName ~= "MAIN" then
		return 0
	end
	local floors = UNDERGROUND_ELEVATORS[self.sv.elevatorName].floors
	local numLocked = 0
	for i = #floors, 1, -1 do
		local requiresKey = floors[i].requiresKey
		if requiresKey and type( requiresKey ) == "string" and not LogEntryManager.Sv_HasLog( requiresKey ) then
			numLocked = numLocked + 1
		else
			break
		end
	end
	return numLocked
end

function UndergroundMainElevator.sv_isFloorLocked( self, floorIndex )
	local floors = UNDERGROUND_ELEVATORS[self.sv.elevatorName].floors
	if self.sv.elevatorName == "MAIN" then
		return floorIndex > #floors - self:sv_getNumLocked()
	else
		local floor = floors[floorIndex]
		if floor and floor.requiresKey and type( floor.requiresKey ) == "string" then
			return not LogEntryManager.Sv_HasLog( floor.requiresKey )
		end
	end
	return false
end

-- Pushes the full display state to every depthbot on this floor. Returns true once at least
-- one existing depthbot has been notified, so the caller knows the display has been updated.
function UndergroundMainElevator.sv_notifyDepthBots( self )
	local storageKey = TileStorageManager.Sv_GetTileStorageKeyFromObject( self.interactable )
	if not storageKey then
		return false
	end
	local tileData = TileStorageManager.Sv_GetValueInSubTable( storageKey, UNDERGROUND_ELEVATOR_TABLE, self.sv.saved.connectionTag ) or {}
	if not tileData.depthbots then
		return false
	end
	local data = {
		selectedFloor = self.sv.targetFloor,
		numLocked = self:sv_getNumLocked(),
		scrapyardUnlocked = UndergroundElevatorManager.Sv_IsScrapyardUnlocked( "MAIN" ),
		displayDepth = UNDERGROUND_ELEVATORS[self.sv.elevatorName].floors[self.sv.elevatorFloorIndex].displayDepth
	}
	local markerLocked = not UndergroundElevatorManager.Sv_CanGo( self.sv.elevatorName, nil )
	local notified = false
	for _, depthbot in ipairs( tileData.depthbots ) do
		if sm.exists( depthbot ) then
			sm.event.sendToInteractable( depthbot, "sv_e_updateFloorDisplay", data, sm.event.types.instant )
			sm.event.sendToInteractable( depthbot, "sv_e_setMarkerLocked", { markerLocked = markerLocked }, sm.event.types.instant )
			notified = true
		end
	end
	return notified
end

function UndergroundMainElevator.sv_activateElevator( self, destinationFloor )
	destinationFloor = destinationFloor or self.sv.targetFloor
    if UndergroundElevatorManager.Sv_Go( self.sv.elevatorName, self.sv.elevatorFloorIndex, destinationFloor ) then
		local floor = UNDERGROUND_ELEVATORS[self.sv.elevatorName].floors[destinationFloor]
		sm.event.sendToGame( "sv_e_createUndergroundElevatorDestination", { depth = floor.depth, elevatorName = self.sv.elevatorName, connectionTag = floor.connectionTag } )
    end
end

function UndergroundMainElevator.sv_e_callButtonPressed( self )
	if self:sv_isQuestLocked() then
		return
	end

	UndergroundElevatorManager.Sv_Call( self.sv.elevatorName, self.sv.elevatorFloorIndex )
end

function UndergroundMainElevator.sv_n_onInteract( self, button )
	if buttons[button] == nil then
		return
	end

	if UndergroundElevatorManager.Sv_TryFailSafeTransfer( self.sv.elevatorName, self.sv.elevatorFloorIndex ) then
		return
	end

	if self:sv_isQuestLocked() then
		return
	end

	self.network:sendToClients( "cl_n_playButtonEffect", button )

	if button == "DOWN" then
		if UndergroundElevatorManager.Sv_CanGo( self.sv.elevatorName, nil ) then
			local currentFloor = self.sv.targetFloor
			self.sv.targetFloor = math.min( self.sv.targetFloor + 1, #UNDERGROUND_ELEVATORS[self.sv.elevatorName].floors )
			-- Skip scrapyard floor if quest not started or completed
			if self:sv_shouldSelectionSkipScrapyard() and self.sv.targetFloor == ScrapyardFloorIndex then
				self.sv.targetFloor = math.min( self.sv.targetFloor + 1, #UNDERGROUND_ELEVATORS[self.sv.elevatorName].floors )
			end
			-- Prevent selecting locked floors
			if self:sv_isFloorLocked( self.sv.targetFloor ) then
				self.sv.targetFloor = currentFloor
			end
		end
	elseif button == "UP" then
		if UndergroundElevatorManager.Sv_CanGo( self.sv.elevatorName, nil ) then
			self.sv.targetFloor = math.max( self.sv.targetFloor - 1, 1 )
			-- Skip scrapyard floor if quest not started or completed
			if self:sv_shouldSelectionSkipScrapyard() and self.sv.targetFloor == ScrapyardFloorIndex then
				self.sv.targetFloor = math.max( self.sv.targetFloor - 1, 1 )
			end
		end
	elseif button == "USE" then
		if not self:sv_isDrill1Blocked() and not self:sv_isScrapyardExitBlocked() then
			if self:sv_shouldRedirectToScrapyard() then
				self:sv_activateElevator( ScrapyardFloorIndex ) -- go to a floor different from the selected one.
			else
				self:sv_activateElevator()
			end
		end
	end
	self:sv_updateClientData()
	self:sv_notifyDepthBots()
end

function UndergroundMainElevator.sv_shouldSelectionSkipScrapyard( self )
	if self.sv.elevatorName ~= "MAIN" then
		return false
	end
	-- The scrapyard floor stays hidden from selection until the player has physically arrived there once.
	return not UndergroundElevatorManager.Sv_IsScrapyardUnlocked( "MAIN" )
end

function UndergroundMainElevator.sv_shouldRedirectToScrapyard( self )
	if self.sv.elevatorName ~= "MAIN" or self.sv.targetFloor < ScrapyardFloorIndex then
		return false
	end
	return not QuestManager.Sv_IsQuestComplete( "quest_scrapyard" )
end

function UndergroundMainElevator.sv_isScrapyardExitBlocked( self )
	if self.sv.elevatorName ~= "MAIN" or self.sv.elevatorFloorIndex ~= ScrapyardFloorIndex then
		return false
	end
	-- Higher floor index = greater depth. Only deeper-than-scrapyard targets are blocked.
	if self.sv.targetFloor <= ScrapyardFloorIndex then
		return false
	end
	if QuestManager.Sv_IsQuestComplete( "quest_scrapyard" ) then
		return false
	end
	-- Only play the blockage effect on cooldown
	local currentTick = sm.game.getCurrentTick()
	if not self.sv.scrapyardWarningTick or currentTick >= self.sv.scrapyardWarningTick + ScrapyardWarningCooldownTicks then
		self.sv.scrapyardWarningTick = currentTick
		EffectManager.Sv_ActivateEventEffect( sm.world.getCurrentWorld(), "scrapyard_elevator_blockage", self.shape.worldPosition )
	end
	return true
end

function UndergroundMainElevator.sv_isDrill1Blocked( self )
	if self.sv.elevatorName ~= "MAIN" or self.sv.targetFloor ~= Drill1FloorIndex then
		return false
	end
	if QuestManager.Sv_IsQuestComplete( "quest_mysterious_signal" )  then
		return false
	end
	-- Only play warning dialog on cooldown
	local currentTick = sm.game.getCurrentTick()
	if not self.sv.drill1WarningTick or currentTick >= self.sv.drill1WarningTick + Drill1WarningCooldownTicks then
		self.sv.drill1WarningTick = currentTick
		DialogManager.Sv_PlayDialogBeat( "lorenzo_stops_elevator_going_past_station1", nil )
	end
	return true
end

-- Client

function UndergroundMainElevator.cl_updateButtonPoseWeights( self )
	local poseWeight = self.cl.buttonPoseWeight or 0.0
	for button, data in pairs( buttons ) do
		self.interactable:setPoseWeight( data.poseIndex, self.cl.pressedButton == button and poseWeight or 0.0 )
	end
end

function UndergroundMainElevator.cl_pressButton( self, button )
	if buttons[button] == nil then
		return
	end

	self.cl.pressedButton = button
	self.cl.buttonPressTimer = ButtonPressDuration
	self.cl.buttonPoseWeight = math.max( self.cl.buttonPoseWeight or 0.0, 0.0 )
	self:cl_updateButtonPoseWeights()
end

function UndergroundMainElevator.cl_n_playButtonEffect( self, button )
	local buttonData = buttons[button]
	local effectName = buttonData and buttonData.effectName
	if effectName then
		local effectOffset = buttonData.effectOffset or sm.vec3.zero()
		local effectPosition = self.shape.worldPosition + self.shape.worldRotation * effectOffset
		sm.effect.playEffect( effectName, effectPosition, nil, nil )
	end
end

function UndergroundMainElevator.cl_getButton( self )
	local planeNormal = self.shape.worldRotation * sm.vec3.new( 0, 0.573462, 0.819232 )
	local rayDir = sm.localPlayer.getDirection()
	local rayDotNormal = rayDir:dot( planeNormal )
	if rayDotNormal < 0 then
		local planePoint = self.shape.worldPosition + planeNormal * 0.5
		local rayStart = sm.localPlayer.getRaycastStart()
		local distance = ( planePoint - rayStart ):dot( planeNormal ) / rayDotNormal
		local intersection = rayStart + rayDir * distance - planePoint;
		local rightAxis = self.shape.worldRotation * sm.vec3.new( 1, 0, 0 )
		local upAxis = sm.vec3.cross( planeNormal, rightAxis )
		local x = sm.vec3.dot( intersection, rightAxis )
		local y = sm.vec3.dot( intersection, upAxis )
		--sm.debugDraw.addArrow( "test", intersection + planePoint, intersection + planePoint + planeNormal )
		--sm.debugDraw.addArrow( "test", planePoint, planePoint + planeNormal )
		if y > -0.185 and y < 0.32 then
			if x > -0.72 and x < -0.22 then
				if y > 0.0675 then
					return "UP"
				else
					return "DOWN"
				end
			elseif x > 0.22 and x < 0.72 then
				return "USE"
			end
		end
	end
end

function UndergroundMainElevator.client_onInteract( self, _, state )
	if state then
		local button = self:cl_getButton()
		self:cl_pressButton( button )
    	self.network:sendToServer( "sv_n_onInteract", button )
	end
end

function UndergroundMainElevator.client_onUpdate( self, dt )
	if self.cl.buttonPressTimer > 0 then
		self.cl.buttonPressTimer = math.max( self.cl.buttonPressTimer - dt, 0 )
	end

	local targetWeight = self.cl.pressedButton ~= nil and self.cl.buttonPressTimer > 0 and 1.0 or 0.0
	if self.cl.buttonPoseWeight < targetWeight then
		self.cl.buttonPoseWeight = math.min( self.cl.buttonPoseWeight + dt * ButtonPoseSpeed, targetWeight )
	elseif self.cl.buttonPoseWeight > targetWeight then
		self.cl.buttonPoseWeight = math.max( self.cl.buttonPoseWeight - dt * ButtonPoseSpeed, targetWeight )
		if self.cl.buttonPoseWeight <= 0 and self.cl.buttonPressTimer == 0 then
			self.cl.pressedButton = nil
			self.cl.buttonPoseWeight = 0
		end
	end

	self:cl_updateButtonPoseWeights()
	if self.cl.canGo then
		self.cl.offTime = 0
		self.interactable:setGlowMultiplier( 1.0 )
	else
		self.cl.offTime = ( self.cl.offTime or LightOffDelay ) + dt
		self.interactable:setGlowMultiplier( self.cl.offTime < LightOffDelay and 1.0 or 0.0 )
	end
end

function UndergroundMainElevator.client_canInteract( self )
	local button = self:cl_getButton()
	if button == "DOWN" then
		sm.gui.setInteractionText( "", sm.gui.getKeyBinding( "Use", true ), "#{INTERACTION_DOWN}" )
		return true
	elseif button == "UP" then
		sm.gui.setInteractionText( "", sm.gui.getKeyBinding( "Use", true ), "#{INTERACTION_UP}" )
		return true
	elseif button == "USE" then
		if self.cl.locked then
			sm.gui.setInteractionText( "#{LOCKED}" )
			return false
		end
		sm.gui.setInteractionText( "", sm.gui.getKeyBinding( "Use", true ), "#{INTERACTION_USE}" )
		return true
	end
	return false
end