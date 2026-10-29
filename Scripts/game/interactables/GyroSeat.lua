-- GyroSeat.lua --
dofile("$SURVIVAL_DATA/Scripts/game/survival_constants.lua")
dofile("$SURVIVAL_DATA/Scripts/game/survival_shapes.lua")
dofile("$SURVIVAL_DATA/Scripts/game/interactables/Seat.lua")
dofile("$SURVIVAL_DATA/Scripts/util.lua")

GyroSeat = class( Seat )
GyroSeat.maxChildCount = 20
GyroSeat.connectionOutput = sm.interactable.connectionType.seated + sm.interactable.connectionType.power + sm.interactable.connectionType.bearing
GyroSeat.colorNormal = sm.color.new( 0x80ff00ff )
GyroSeat.colorHighlight = sm.color.new( 0x80ff00ff )
GyroSeat.upgradeCostItem = ITEMS.obj_consumable_multicomponent
GyroSeat.connectIcon = "driverSeat"
GyroSeat.connectIconScale = 0.75
GyroSeat.bearingGuiTitle = "#{TURRET_SEAT_UPGRADE_TITLE}"
GyroSeat.Levels = {
	[tostring(ITEMS.obj_interactive_turretseat_01_sphere)] = {
		cost = 2,
		responseLimit = 2,
		upgrade = ITEMS.obj_interactive_turretseat_02_sphere,
		upgradeBase = ITEMS.obj_interactive_turretseat_02_base,
		maxConnections = 6,
		levelNumber = 1
	},
	[tostring(ITEMS.obj_interactive_turretseat_02_sphere)] = {
		cost = 4,
		responseLimit = 4,
		upgrade = ITEMS.obj_interactive_turretseat_03_sphere,
		upgradeBase = ITEMS.obj_interactive_turretseat_03_base,
		maxConnections = 8,
		levelNumber = 2
	},
	[tostring(ITEMS.obj_interactive_turretseat_03_sphere)] = {
		stepTitle = true,
		cost = 6,
		responseLimit = 6,
		upgrade = ITEMS.obj_interactive_turretseat_04_sphere,
		upgradeBase = ITEMS.obj_interactive_turretseat_04_base,
		maxConnections = 12,
		bearingPower = true,
		levelNumber = 3
	},
	[tostring(ITEMS.obj_interactive_turretseat_04_sphere)] = {
		stepTitle = true,
		cost = 10,
		responseLimit = 8,
		upgrade = ITEMS.obj_interactive_turretseat_05_sphere,
		upgradeBase = ITEMS.obj_interactive_turretseat_05_base,
		maxConnections = 16,
		allowAdjustingJoints = true,
		bearingPower = true,
		levelNumber = 4,
	},
	[tostring(ITEMS.obj_interactive_turretseat_05_sphere)] = {
		stepTitle = true,
		responseLimit = 10,
		maxConnections = 20,
		allowAdjustingJoints = true,
		bearingPower = true,
		submersible = true,
		levelNumber = 5
	}
}

GyroSeat.tinkerGuiJson = Seat.initTinkerGui( sm.json.open( "$SURVIVAL_DATA/Gui/JsonGuis/TurretSeatUpgrade.gui" ), GyroSeat.Levels )
GyroSeat.tinkerGuiJson.title.Caption = "#{TURRET_SEAT_UPGRADE_TITLE}"
GyroSeat.tinkerGuiJson.responseSlider = FindWidget( GyroSeat.tinkerGuiJson.json, "ResponseSlider" )
GyroSeat.tinkerGuiJson.responseSlider.Snapping = true
GyroSeat.tinkerGuiJson.responseSlider.HighlightIndex = true

local GyroseatBases = {
	ITEMS.obj_interactive_turretseat_01_base,
	ITEMS.obj_interactive_turretseat_02_base,
	ITEMS.obj_interactive_turretseat_03_base,
	ITEMS.obj_interactive_turretseat_04_base,
	ITEMS.obj_interactive_turretseat_05_base
}

local function centerHorizontally( parentWidth, widgetWidth )
	return round( parentWidth / 2 - widgetWidth / 2 )
end

local hudGui = {}
hudGui.json = sm.json.open( "$SURVIVAL_DATA/Gui/JsonGuis/TurretSeatHUD.gui" )
hudGui.sideRulers = FindWidget( hudGui.json, "SideRulers" )
hudGui.arrowBox = FindWidget( hudGui.json, "ArrowBox" )
hudGui.rulerBox = FindWidget( hudGui.json, "RulerBox" )
hudGui.rotationDial = FindWidget( hudGui.json, "RotationDial" )

hudGui.rulerBox.x = centerHorizontally( 1280, hudGui.rulerBox.width )
hudGui.sideRulers.x = centerHorizontally( hudGui.rulerBox.width, hudGui.sideRulers.width )
hudGui.arrowBox.x = centerHorizontally( hudGui.rulerBox.width, hudGui.arrowBox.width )
hudGui.slideRulerStartPositionY = hudGui.sideRulers.y
hudGui.pitchoffset = FindWidget( hudGui.json, "LeftMarker" ).height / 2

local jnt_gyroseat = sm.uuid.new( "645a592e-b015-4ca6-b5a7-cc33612870eb" )

local BaseResponse = 1.0
local ResponseStep = 0.3 -- for each response slider tick over 1 add this value to response speed

local GyroSpeed = 3
local GyroForce = 890000

function GyroSeat.server_onCreate( self )
	self.sv = {}
	self.sv.saved = self.storage:load() or { responseSlider = 1 }
	self.network:setClientData( self.sv.saved.responseSlider, 2 )
end

function GyroSeat.server_onFixedUpdate( self )
	Seat.server_onFixedUpdate( self )
	if self.interactable:isActive() then
		self.interactable:setPower( self.interactable:getSteeringPower() )
	else
		self.interactable:setPower( 0 )
		self.interactable:setSteeringFlag( 0 )
	end
end

function GyroSeat.client_onInteract( self, character, state )
	if state then
		self:cl_seat()
		if self.shape.interactable:getSeatCharacter() ~= nil then
			NotificationManager.Cl_AddGenericNotification( "#{ALERT_DRIVERS_SEAT_OCCUPIED}", 4.0 )
		elseif self.shape.body:isOnLift() and not self.shape.body:isOnVirtualLift() then
			NotificationManager.Cl_AddGenericNotification( "#{ALERT_DRIVERS_SEAT_ON_LIFT}", 8.0 )
		end
	end
end

function GyroSeat.cl_updateTinkerGui( self, forceLevel, quantity )
	Seat.cl_updateTinkerGui( self, forceLevel, quantity )
	local level = GyroSeat.Levels[tostring( forceLevel or self.shape:getShapeUuid() )]
	local _, responseLimit = GetHighestValue( GyroSeat.Levels, "responseLimit" )
	self.tinkerGuiJson.responseSlider.RangeLimitPosition = responseLimit .. "," .. level.responseLimit .. "," .. self.cl.responseSlider
end

function GyroSeat.cl_getUpgradeInfoCaption( self, level, nextLevel )
	local baseCaption = self.upgradeTextDefaultColor
		.. "#{CONTROLLER_UPGRADE_Response} "
		.. self.upgradeTextNumberColor
		.. "+"
		.. ( nextLevel.responseLimit - level.responseLimit )
		.. "\n" .. Seat.cl_getUpgradeInfoCaption( self, level, nextLevel )

	if level.bearingPower ~= nextLevel.bearingPower then
		baseCaption = baseCaption
			.. "\n"
			.. self.upgradeTextDefaultColor
			.. "#{CONTROLLER_UPGRADE_Bearings} "
			.. self.upgradeTextNumberColor
			.. "#{UNLOCKED}"
	end

	return level.submersible ~= nextLevel.submersible and baseCaption
		.. "\n"
		.. self.upgradeTextDefaultColor
		.. "#{CONTROLLER_UPGRADE_Oxygen} "
		.. self.upgradeTextNumberColor
		.. "#{UNLOCKED}" or baseCaption
end

function GyroSeat.client_onAction( self, controllerAction, state )
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

function GyroSeat.cl_getBaseShape( self )
	local shapes = self.shape:getMultiShapeShapes()
	if shapes ~= nil then
		for _, shape in ipairs( shapes ) do
			if isAnyOf( shape:getShapeUuid(), GyroseatBases ) then
				return shape
			end
		end
	end
	return nil
end

function GyroSeat.client_onCreate( self )
	Seat.client_onCreate( self )

	self.animWeight = 0.5
	self.interactable:setAnimEnabled("j_ratt", true)

	self.interactable:setGyroMaxSpeed( GyroSpeed )
	self.interactable:setGyroForce( GyroForce )
	self.interactable:setGyroDirection( self.shape:getUp() )

	local gyroFeatureData = sm.item.getFeatureData( self.shape:getShapeUuid() )
	self.yawSensitivityModifier = gyroFeatureData.gyro.yawSensitivityModifier
	self.pitchSensitivityModifier = gyroFeatureData.gyro.pitchSensitivityModifier

	local jointFeatureData = sm.item.getFeatureData( jnt_gyroseat )
	self.minPitchAngle = jointFeatureData.x.min - 5.0
	self.maxPitchAngle = jointFeatureData.x.max + 5.0

	self.cl.hudGui = nil

	local level = GyroSeat.Levels[tostring( self.shape:getShapeUuid() )].levelNumber
	self.cl.rotateEffect = sm.effect.createEffect( "TurretSeat - Rotate", self.interactable )
	self.cl.rotateEffect:setParameter( "level", level )
end

function GyroSeat.client_onUpdate( self, dt )
	Seat.client_onUpdate( self, dt )

	local steeringAngle = self.interactable:getSteeringAngle()
	local angle = self.animWeight * 2.0 - 1.0 -- Convert anim weight 0,1 to angle -1,1

	if angle < steeringAngle then
		angle = min( angle + 4.2441*dt, steeringAngle )
	elseif angle > steeringAngle then
		angle = max( angle - 4.2441*dt, steeringAngle )
	end

	self.animWeight = angle * 0.5 + 0.5 -- Convert back to 0,1
	self.interactable:setAnimProgress( "j_ratt", self.animWeight )

	local seatedCharacter = self.interactable:getSeatCharacter()
	if seatedCharacter and seatedCharacter:getPlayer() and seatedCharacter:getPlayer():getId() == sm.localPlayer.getId() then
		local baseShape = self:cl_getBaseShape()
		if baseShape then
			if self.cameraState == "" then
				self.chaseDir = baseShape:transformDirection( self.shape:getUp() )
				self.virtualDir = self.chaseDir
			end

			local _, seatedCameraPullback = sm.camera.getCameraPullback()
			self.cameraState = seatedCameraPullback == 0 and "fp" or "tp"

			self:cl_updateCamera( baseShape, dt )
			self:cl_updateHudGui( baseShape )
		end
	else
		self.cameraState = ""
		if self.cl.hudGui then
			self.cl.hudGui:render( {} )
			self.cl.hudGui = nil
		end
	end

	if seatedCharacter and not self.cl.rotateEffect:isPlaying() then
		self.cl.rotateEffect:start()
	elseif not seatedCharacter and self.cl.rotateEffect:isPlaying() then
		self.cl.rotateEffect:stop()
	end
end

function GyroSeat.cl_onSliderReleased( self, name, value )
	if self.cl.responseSlider ~= value then
		self.network:sendToServer( "sv_n_onSliderReleased", value )
	end
end

function GyroSeat.sv_n_onSliderReleased( self, responseSliderValue )
	if self.sv.saved.responseSlider ~= responseSliderValue then
		self.sv.saved.responseSlider = responseSliderValue
		self.storage:save( self.sv.saved )
		self.network:setClientData( responseSliderValue, 2 )
	end
end

function GyroSeat.client_onClientDataUpdate( self, clientData, channel )
	Seat.client_onClientDataUpdate( self, clientData, channel )
	if channel == 2 then
		self.cl.responseSlider = clientData
		if self.cl.tinkerGui then
			self:cl_updateTinkerGui()
			self.cl.renderTinker = true
		end
	end
end

function GyroSeat.cl_updateHudGui( self, baseShape )
	if self.cameraState == "fp" then
		if not self.cl.hudGui then
			self.cl.hudGui = sm.jsonGui.createGui( { isHud = true, isInteractive = false, needsCursor = false } )
		end

		local baseUp = baseShape:getAt()
		local baseForward = baseShape:getRight()
		local baseSide = baseShape:getUp()
		local seatForward = self.shape:getUp()
		local sphereSide = self.shape:getRight()

		local upness = seatForward:dot( baseUp )
		local pitchAngleDeg = RadToDeg( math.asin( upness ) )

		local function remap( fromRangeA, fromRangeB, targetRangeA, targetRangeB, p )
			local frac = ( p - fromRangeA ) / ( fromRangeB - fromRangeA )
			return  lerp( targetRangeA, targetRangeB, frac )
		end

		local offset = round( remap( -90, 90, -hudGui.pitchoffset, hudGui.pitchoffset, pitchAngleDeg ) )
		hudGui.sideRulers.y = hudGui.slideRulerStartPositionY + offset
		local turn = sphereSide:dot( baseForward )
		local facingSign = sphereSide:dot( baseSide )
		local turnAngle = math.acos( turn )

		if facingSign < 0 then
			turnAngle = -turnAngle
		end

		hudGui.rotationDial.RotatingSkinAngle = turnAngle
		self.cl.hudGui:render( hudGui.json )
	elseif self.cameraState == "tp" then
		if self.cl.hudGui then
			self.cl.hudGui:render( {} )
			self.cl.hudGui = nil
		end
	end
end

function GyroSeat.cl_updateCamera( self, baseShape, dt )
	local dx, dy = sm.localPlayer.getMouseDelta()
	local sens = sm.localPlayer.getAimSensitivity()








	local lerpDir = function( fromDirection, toDirection, p )
		local fromHeading = math.atan2( fromDirection.x, fromDirection.z )
		local fromPitch = math.asin( clamp( -fromDirection.y, -1, 1 ) )

		local toHeading = math.atan2( toDirection.x, toDirection.z )
		local toPitch = math.asin( clamp( -toDirection.y, -1, 1 ) )

		local shortestAngle = ( ( ( toHeading - fromHeading ) % ( 2 * math.pi ) + 3 * math.pi ) % ( 2 * math.pi ) ) - math.pi
		toHeading = fromHeading + shortestAngle

		fromHeading = sm.util.lerp( fromHeading, toHeading, p )
		fromPitch = sm.util.lerp( fromPitch, toPitch, p )

		local outDirection = sm.vec3.new( 0, 0, 1 )
		outDirection = outDirection:rotateX( fromPitch )
		outDirection = outDirection:rotateY( fromHeading )

		return outDirection
	end

	if self.cameraState == "fp" then
		local newDir = self.virtualDir
		local right = self.virtualDir:cross( sm.vec3.new( 0, 1, 0 ) )
		if right:length2() == 0 then
			right = sm.vec3.new( 0, 1, 0 ) -- this should not happen bcs of the pitch limit
		else
			right = right:normalize()
		end

		newDir = newDir:rotate( dy * sens * self.pitchSensitivityModifier, right )
		newDir = newDir:rotateY( dx * sens * self.yawSensitivityModifier )
		
		local currentDotUpdated = baseShape:transformDirection( self.shape:getUp() ):dot( newDir )
		if currentDotUpdated > 0.45 then
			local newDirectionPitch = math.asin( newDir.y )
			if newDirectionPitch < DegToRad( self.minPitchAngle ) or newDirectionPitch > DegToRad( self.maxPitchAngle ) then
				newDir = self.virtualDir
				newDir = newDir:rotateY( dx * sens * self.yawSensitivityModifier )
			end
			self.virtualDir = newDir
		end
	elseif self.cameraState == "tp" then
		self.virtualDir = baseShape:transformDirection( sm.camera.getDirection() )
	end






	local angleBetween = math.acos( saturate( sm.vec3.dot( self.chaseDir, self.virtualDir ) ) )
	if angleBetween ~= 0 then
		local radiansToMove = ( BaseResponse + ( self.cl.responseSlider - 1 ) * ResponseStep ) * dt
		local t = clamp(  radiansToMove / angleBetween , 0, 1 )
		self.chaseDir = self.chaseDir:normalize()
		self.virtualDir = self.virtualDir:normalize()
		self.chaseDir = lerpDir( self.chaseDir, self.virtualDir, t )
	end

	if self.cameraState == "fp" then
		sm.camera.setCameraState( sm.camera.state.gyroSeatFP )
	elseif self.cameraState == "tp" then
		sm.camera.setCameraState( sm.camera.state.gyroSeatTP )
	end

	local joints = self.shape:getMultiShapeJoints()
	if joints[1] and sm.exists( joints[1] ) then
		local angVel = joints[1]:getAngularVelocityVector():length()
		self.cl.rotateEffect:setParameter( "velocity", angVel > 0.1 and angVel or 0 )
	end

	self.interactable:setGyroDirection( baseShape:transformLocalDirection( self.chaseDir ) )
end

function GyroSeat.sv_n_tryUpgrade( self, _, player )
	local level = self.Levels[tostring( self.shape:getShapeUuid() )]
	if Seat.sv_n_tryUpgrade( self, _, player ) then
		for _, shape in ipairs( self.shape:getMultiShapeShapes() ) do
			local shapeUuid = shape:getShapeUuid()
			if isAnyOf( shapeUuid, GyroseatBases ) then
				shape:replaceShape( level.upgradeBase )
				return
			end
		end
	end
end

function GyroSeat.cl_n_onUpgrade( self, params )
	Seat.cl_n_onUpgrade( self, params )
	self.cl.rotateEffect:setParameter( "level", self.Levels[tostring( params.upgrade )].levelNumber )

	for _, shape in ipairs( self.shape:getMultiShapeShapes() ) do
		local shapeUuid = shape:getShapeUuid()
		if isAnyOf( shapeUuid, GyroseatBases ) then
			sm.effect.playHostedEffect( "Part - Upgrade", shape )
			return
		end
	end
end
