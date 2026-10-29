-- DriverSeat.lua --
dofile("$SURVIVAL_DATA/Scripts/game/survival_constants.lua")
dofile("$SURVIVAL_DATA/Scripts/game/survival_shapes.lua")
dofile("$SURVIVAL_DATA/Scripts/game/interactables/Seat.lua")
dofile("$SURVIVAL_DATA/Scripts/util.lua")

DriverSeat = class( Seat )
DriverSeat.maxChildCount = 20
DriverSeat.connectionOutput = sm.interactable.connectionType.seated + sm.interactable.connectionType.power + sm.interactable.connectionType.bearing
DriverSeat.colorNormal = sm.color.new( 0x80ff00ff )
DriverSeat.colorHighlight = sm.color.new( 0x80ff00ff )
DriverSeat.connectIcon = "driverSeat"
DriverSeat.connectIconScale = 1.0
DriverSeat.bearingGuiTitle = "#{DRIVERS_SEAT_UPGRADE_TITLE}"
DriverSeat.Levels = {
	[tostring(ITEMS.obj_scrap_driverseat)] = { maxConnections = 4 },
	[tostring(ITEMS.obj_interactive_driverseat_01)] = { maxConnections = 6, upgrade = ITEMS.obj_interactive_driverseat_02, cost = 1, levelNumber = 1 },
	[tostring(ITEMS.obj_interactive_driverseat_02)] = { maxConnections = 8, upgrade = ITEMS.obj_interactive_driverseat_03, cost = 2,levelNumber = 2 },
	[tostring(ITEMS.obj_interactive_driverseat_03)] = { maxConnections = 12, upgrade = ITEMS.obj_interactive_driverseat_04, cost = 3, levelNumber = 3 },
	[tostring(ITEMS.obj_interactive_driverseat_04)] = { maxConnections = 16, upgrade = ITEMS.obj_interactive_driverseat_05, cost = 5, levelNumber = 4 },
	[tostring(ITEMS.obj_interactive_driverseat_05)] = { maxConnections = 20, allowAdjustingJoints = true, stepTitle = true, levelNumber = 5 },
}

local function setUpStepWidgets( json )
	local connectionsWidget = FindWidget( json, "Connections" )
	FindWidget( connectionsWidget, "Step5Default" ).Skin = "SeatTurretConnectionsBearing"
	local step5ActiveWidget = FindWidget( connectionsWidget, "Step5Active" )
	FindWidget( step5ActiveWidget, "FillBig" ).Visible = false
	FindWidget( step5ActiveWidget, "FillSmall" ).Visible = true
	step5ActiveWidget.Skin = "SeatTurretConnectionsBearing"
end

DriverSeat.tinkerGuiJson = Seat.initTinkerGui( sm.json.open( "$SURVIVAL_DATA/Gui/JsonGuis/SeatUpgrade.gui" ), DriverSeat.Levels )
DriverSeat.tinkerGuiJson.title.Caption = "#{DRIVERS_SEAT_UPGRADE_TITLE}"
setUpStepWidgets( DriverSeat.tinkerGuiJson.json )

function DriverSeat.server_onFixedUpdate( self )
	Seat.server_onFixedUpdate( self )
	if self.interactable:isActive() then
		self.interactable:setPower( self.interactable:getSteeringPower() )
	else
		self.interactable:setPower( 0 )
		self.interactable:setSteeringFlag( 0 )
	end
end

function DriverSeat.client_onInteract( self, character, state )
	if state then
		self:cl_seat()
		if self.shape.interactable:getSeatCharacter() ~= nil then
			NotificationManager.Cl_AddGenericNotification( "#{ALERT_DRIVERS_SEAT_OCCUPIED}", 4.0 )
		elseif self.shape.body:isOnLift() and not self.shape.body:isOnVirtualLift() then
			NotificationManager.Cl_AddGenericNotification( "#{ALERT_DRIVERS_SEAT_ON_LIFT}", 8.0 )
		end
	end
end

function DriverSeat.client_onAction( self, controllerAction, state )
	if state == true then
		if controllerAction == sm.interactable.actions.forward then
			self.interactable:setSteeringFlag( sm.interactable.steering.forward )
		elseif controllerAction == sm.interactable.actions.backward then
			self.interactable:setSteeringFlag( sm.interactable.steering.backward )
		elseif controllerAction == sm.interactable.actions.left then
			self.interactable:setSteeringFlag( sm.interactable.steering.left )
		elseif controllerAction == sm.interactable.actions.right then
			self.interactable:setSteeringFlag( sm.interactable.steering.right )
		elseif controllerAction == sm.interactable.actions.sprint then
			self.interactable:setSteeringFlag( sm.interactable.steering.sprint )
		else
			return Seat.client_onAction( self, controllerAction, state )
		end
	else
		if controllerAction == sm.interactable.actions.forward then
			self.interactable:unsetSteeringFlag( sm.interactable.steering.forward )
		elseif controllerAction == sm.interactable.actions.backward then
			self.interactable:unsetSteeringFlag( sm.interactable.steering.backward )
		elseif controllerAction == sm.interactable.actions.left then
			self.interactable:unsetSteeringFlag( sm.interactable.steering.left )
		elseif controllerAction == sm.interactable.actions.right then
			self.interactable:unsetSteeringFlag( sm.interactable.steering.right )
		elseif controllerAction == sm.interactable.actions.sprint then
			self.interactable:unsetSteeringFlag( sm.interactable.steering.sprint )
		else
			return Seat.client_onAction( self, controllerAction, state )
		end
	end
	return true
end

function DriverSeat.client_onCreate( self )
	Seat.client_onCreate( self )
	self.animWeight = 0.5
	self.interactable:setAnimEnabled("j_ratt", true)
	self.cl.tutorialTimer = 0
end

function DriverSeat.client_onFixedUpdate( self, timeStep )
	if not TutorialManager.Cl_HasWatched( TutorialEvent.FlippedCreation ) then
		if sm.vec3.dot( sm.vec3.cross( self.shape.up, self.shape.right ), sm.vec3.new( 0, 0, -1 ) ) > 0.5 then
			self.cl.tutorialTimer = self.cl.tutorialTimer + 1
			if self.cl.tutorialTimer >= 80 then -- show prompt if we have been upside down for 2 seconds
				TutorialManager.Cl_TutorialEvent( TutorialEvent.FlippedCreation )
			end
		else
			self.cl.tutorialTimer = 0
		end
	end
end

function DriverSeat.client_onUpdate( self, dt )
	Seat.client_onUpdate( self, dt )

	local steeringAngle = self.interactable:getSteeringAngle();
	local angle = self.animWeight * 2.0 - 1.0 -- Convert anim weight 0,1 to angle -1,1

	if angle < steeringAngle then
		angle = min( angle + 4.2441*dt, steeringAngle )
	elseif angle > steeringAngle then
		angle = max( angle - 4.2441*dt, steeringAngle )
	end

	self.animWeight = angle * 0.5 + 0.5; -- Convert back to 0,1
	self.interactable:setAnimProgress("j_ratt", self.animWeight)
end

DriverSaddle = class( DriverSeat )
DriverSaddle.bearingGuiTitle = "#{DRIVERS_SADDLE_UPGRADE_TITLE}"
DriverSaddle.Levels = {
	[tostring(ITEMS.obj_interactive_driversaddle_01)] = { maxConnections = 6, upgrade = ITEMS.obj_interactive_driversaddle_02, cost = 1, levelNumber = 1 },
	[tostring(ITEMS.obj_interactive_driversaddle_02)] = { maxConnections = 8, upgrade = ITEMS.obj_interactive_driversaddle_03, cost = 2, levelNumber = 2 },
	[tostring(ITEMS.obj_interactive_driversaddle_03)] = { maxConnections = 12, upgrade = ITEMS.obj_interactive_driversaddle_04, cost = 3, levelNumber = 3 },
	[tostring(ITEMS.obj_interactive_driversaddle_04)] = { maxConnections = 16, upgrade = ITEMS.obj_interactive_driversaddle_05, cost = 5, levelNumber = 4 },
	[tostring(ITEMS.obj_interactive_driversaddle_05)] = { maxConnections = 20, allowAdjustingJoints = true, stepTitle = true, levelNumber = 5 },
}

DriverSaddle.tinkerGuiJson = Seat.initTinkerGui( sm.json.open( "$SURVIVAL_DATA/Gui/JsonGuis/SeatUpgrade.gui" ), DriverSaddle.Levels )
DriverSaddle.tinkerGuiJson.title.Caption = "#{DRIVERS_SADDLE_UPGRADE_TITLE}"
setUpStepWidgets( DriverSaddle.tinkerGuiJson.json )
