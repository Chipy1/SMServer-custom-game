dofile( "$SURVIVAL_DATA/Scripts/game/managers/UndergroundElevatorManager.lua" )

UndergroundSimpleElevator = class()
UndergroundSimpleElevator.poseWeightCount = 2

local buttonEffectName = "Survivalobject - Elevatorkeyreaderunlock_use"
local buttonPoseSpeed = 12.0
local LoopingSpeed = 4.0
local buttons = {
	UP = { poseIndex = 0, uvFrame = 8 },
	DOWN = { poseIndex = 1, uvFrame = 4 }
}

function UndergroundSimpleElevator.server_onCreate( self )
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
	self.sv.targetFloor = 3 - self.sv.elevatorFloorIndex
	self.network:setClientData( { goingUp = self.sv.targetFloor < self.sv.elevatorFloorIndex } )

	local transportArea = FindFirstNearbyNode( self.shape.worldPosition, { "UNDERGROUND_ELEVATOR_AREA", self.sv.saved.connectionTag } )
	if transportArea then
		UndergroundElevatorManager.Sv_RegisterElevatorFloor( self.sv.elevatorName, self.sv.elevatorFloorIndex, sm.world.getCurrentWorld(), self.shape.worldPosition, self.sv.saved.connectionTag, transportArea )
	end

	self:sv_updateClientData()
end

function UndergroundSimpleElevator.server_onFixedUpdate( self )
	self:sv_updateClientData()
end

function UndergroundSimpleElevator.sv_updateClientData( self )
	local clientData = {
		goingUp = self.sv.targetFloor < self.sv.elevatorFloorIndex,
		canGo = UndergroundElevatorManager.Sv_CanGo( self.sv.elevatorName, self.sv.targetFloor ),
		doorOpen = UndergroundElevatorManager.Sv_IsDoorOpen( self.sv.elevatorName, self.sv.elevatorFloorIndex )
	}
	if self.sv.clientData == nil or self.sv.clientData.goingUp ~= clientData.goingUp or self.sv.clientData.canGo ~= clientData.canGo or self.sv.clientData.doorOpen ~= clientData.doorOpen then
		self.sv.clientData = clientData
		self.network:setClientData( clientData )
	end
end

function UndergroundSimpleElevator.sv_activateElevator( self )
	local started = UndergroundElevatorManager.Sv_Go( self.sv.elevatorName, self.sv.elevatorFloorIndex, self.sv.targetFloor )
	if started and not self.destinationCreated then
		local floor = UNDERGROUND_ELEVATORS[self.sv.elevatorName].floors[self.sv.targetFloor]
		sm.event.sendToGame( "sv_e_createUndergroundElevatorDestination", { depth = floor.depth, elevatorName = self.sv.elevatorName, connectionTag = floor.connectionTag } )
		self.destinationCreated = true
	end
	return started
end

function UndergroundSimpleElevator.sv_e_callButtonPressed( self )
	UndergroundElevatorManager.Sv_Call( self.sv.elevatorName, self.sv.elevatorFloorIndex )
end

function UndergroundSimpleElevator.sv_n_onInteract( self, button )
	if self:sv_activateElevator() then
		self.network:sendToClients( "cl_n_pressButton", self.sv.targetFloor < self.sv.elevatorFloorIndex )
	end
	self:sv_updateClientData()
end

-- Client

function UndergroundSimpleElevator.client_onCreate( self )
	self.cl = {}
	self.cl.canGo = false
	self.cl.goingUp = false
	self.cl.doorOpen = false
	self.cl.pressedButton = nil
	self.cl.buttonPoseWeight = 0.0
	self.cl.loopingIndex = 0
	self.interactable:setUvFrameIndex( 0 )
end

function UndergroundSimpleElevator.cl_updateButtonUvFrame( self )
	self.interactable:setUvFrameIndex( math.floor( self.cl.loopingIndex ) )
end

function UndergroundSimpleElevator.client_onClientDataUpdate( self, params )
	local prevCanGo = self.cl.canGo
	local prevDoorOpen = self.cl.doorOpen
	self.cl.canGo = params.canGo == true
	self.cl.goingUp = params.goingUp == true
	self.cl.doorOpen = params.doorOpen == true
	if self.cl.doorOpen and not prevDoorOpen and self.cl.pressedButton ~= nil then
		self.cl.pressedButton = nil
		self.cl.buttonPoseWeight = 0.0
		self:cl_updateButtonPoseWeights()
	end
	if self.cl.canGo and not prevCanGo and self.cl.pressedButton == nil then
		if self.cl.goingUp then
			self.cl.loopingIndex = 1
		else
			self.cl.loopingIndex = 0
		end
	end
	self:cl_updateButtonUvFrame()
end

function UndergroundSimpleElevator.cl_updateButtonPoseWeights( self )
	local poseWeight = self.cl.buttonPoseWeight or 0.0
	for button, data in pairs( buttons ) do
		self.interactable:setPoseWeight( data.poseIndex, self.cl.pressedButton == button and poseWeight or 0.0 )
	end
end

function UndergroundSimpleElevator.cl_pressButton( self, goingUp )
	local pressedButton = goingUp and "UP" or "DOWN"
	if self.cl.pressedButton ~= pressedButton then
		self.cl.buttonPoseWeight = 0.0
		self.cl.loopingIndex = buttons[pressedButton].uvFrame
	end
	self.cl.pressedButton = pressedButton
	self:cl_updateButtonUvFrame()
	self:cl_updateButtonPoseWeights()
end

function UndergroundSimpleElevator.cl_n_pressButton( self, goingUp )
	self:cl_pressButton( goingUp )
	sm.effect.playHostedEffect( buttonEffectName, self.interactable )
end

function UndergroundSimpleElevator.client_onInteract( self, _, state )
	if state then
    	self.network:sendToServer( "sv_n_onInteract" )
	end
end

function UndergroundSimpleElevator.client_canInteract( self )
	return true
end

function UndergroundSimpleElevator.client_onUpdate( self, dt )
	if self.cl.pressedButton ~= nil then
		local startFrame = buttons[self.cl.pressedButton].uvFrame
		local endFrame = startFrame + 4
		self.cl.loopingIndex = self.cl.loopingIndex + dt * LoopingSpeed
		if self.cl.loopingIndex >= endFrame then
			self.cl.loopingIndex = startFrame
		end
	else
		if self.cl.canGo then
			self.cl.loopingIndex = self.cl.goingUp and 1 or 0
		else
			self.cl.loopingIndex = 3
		end
	end

	self:cl_updateButtonUvFrame()

	if self.cl.pressedButton == nil or self.cl.buttonPoseWeight >= 1.0 then
		return
	end

	self.cl.buttonPoseWeight = math.min( self.cl.buttonPoseWeight + dt * buttonPoseSpeed, 1.0 )
	self:cl_updateButtonPoseWeights()
end
