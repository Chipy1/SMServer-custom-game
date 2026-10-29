dofile( "$SURVIVAL_DATA/Scripts/game/powerladder_util.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/harvestable/PowerLadderRail.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/kinematics/Kinematic.lua" )

PowerLadderHandle = class( Kinematic )

-- Constants for camera behavior when player is seated on the handle
-- When you are seated the camera will lerp to a target FOV over a duration.
local FovLerpDuration = 0.5
local FovTarget = 110.0
-- Uses a camera mode that is lockedControls to the seat/handle orientation.
-- Adjusts the camera position relative to the handle when seated. 
local SeatLocalCameraDirection = sm.vec3.new( 0, 1, 0 )
local SeatLocalCameraUp = sm.vec3.new( 0, 0, -1 )
local SeatLockedCameraPullback = 1.2
local SeatLockedCameraUpOffset = 1.2
-- The unseat look direction is the -Z of the final track key, in world space.
local FinalKeyLookAxis = sm.vec3.new( 0, 0, -1 )

function PowerLadderHandle.server_onCreate( self )
    Kinematic.server_onCreate( self )

    if self.params then
        self.network:sendToClient( self.params.rider:getPlayer(),  "cl_seat" )
    end

	self.sv.tileStorageKey = TileStorageManager.Sv_GetTileStorageKeyFromObject( self.harvestable )
	if self.params.railTag then
		local rail = GetRailStorage( self.sv.tileStorageKey, self.params.railTag )
		if rail then
			self.sv.railCollection = rail.collection
			for _, railPart in pairs( self.sv.railCollection ) do
				if sm.exists( railPart ) then
				    sm.event.sendToHarvestable( railPart, "sv_e_addHandle", self.params.backwards )
				end
			end
		end
	end
end

function PowerLadderHandle.server_onFixedUpdate( self, dt )
	if TileStorageManager.Sv_SyncedGetValueInSubTable( self.sv.tileStorageKey, TILESTORAGE_FLAGS_TABLE, "destroyed" ) == true then
		self.harvestable:destroy()
	end

    Kinematic.server_onFixedUpdate( self, dt )
    if not self:sv_isMoving() then
		if self.sv.railCollection then
			for _, railPart in pairs( self.sv.railCollection ) do
				if sm.exists( railPart ) then
				    sm.event.sendToHarvestable( railPart, "sv_e_removeHandle" )
				end
			end
		end
        self.harvestable:destroy()
    end
end

function PowerLadderHandle.client_onCreate( self )
	self.cl = {}
	Kinematic.client_onCreate( self )

	self.cl.sparksEffect1 = sm.effect.createEffect( "WarehouseLadder - Sparktrail02", self.harvestable )
	self.cl.sparksEffect2 = sm.effect.createEffect( "WarehouseLadder - Sparktrail02", self.harvestable )
	self.cl.sparksEffect3 = sm.effect.createEffect( "WarehouseLadder - Sparktrail01", self.harvestable )
	self.cl.sparksEffect4 = sm.effect.createEffect( "WarehouseLadder - Sparktrail01", self.harvestable )
	
	local sparkEffectSideOffset = 1.75

	self.cl.sparksEffect1:setOffsetPosition( sm.vec3.new( sparkEffectSideOffset, -0.5, 0  ) )
	local quat1 = sm.quat.angleAxis( math.rad( 180 ), sm.vec3.new( 0,1,0 ) ) * sm.quat.angleAxis( math.rad( -90 ) , sm.vec3.new( 1,0,0 ) )
	self.cl.sparksEffect1:setOffsetRotation( quat1 )
	local quat2 = sm.quat.angleAxis( math.rad( -90 ) , sm.vec3.new( 1,0,0 ) )
	self.cl.sparksEffect2:setOffsetPosition( sm.vec3.new( -sparkEffectSideOffset, -0.5, 0  ) )
	self.cl.sparksEffect2:setOffsetRotation( quat2 )

	local quat3 = sm.quat.angleAxis( math.rad( 180 ), sm.vec3.new( 0,1,0 ) ) * sm.quat.angleAxis( math.rad( -90 ) , sm.vec3.new( 1,0,0 ) )
	self.cl.sparksEffect3:setOffsetPosition( sm.vec3.new( sparkEffectSideOffset, 0.25, 0  ) )
	self.cl.sparksEffect3:setOffsetRotation( quat3 )
	local quat4 = sm.quat.angleAxis( math.rad( -90 ) , sm.vec3.new( 1,0,0 ) )
	self.cl.sparksEffect4:setOffsetPosition( sm.vec3.new( -sparkEffectSideOffset, 0.25, 0  ) )
	self.cl.sparksEffect4:setOffsetRotation( quat4 )

	self.cl.sparksEffect1:start()
	self.cl.sparksEffect2:start()
	self.cl.sparksEffect3:start()
	self.cl.sparksEffect4:start()

	self.cl.maxSpeedAudio = self.data.maxSpeedAudio or 70.0
	self.cl.prevPosition = 0.0
	self.cl.speed = 0.0
end

function PowerLadderHandle.client_onFixedUpdate( self, dt )
	Kinematic.client_onFixedUpdate( self )

	local currentPosition = self.harvestable.worldPosition
	if self.cl.prevPosition then
		local deltaPosition = currentPosition - self.cl.prevPosition
		self.cl.speed = deltaPosition:length() / dt
	else
		self.cl.speed = 0
	end
	self.cl.prevPosition = currentPosition

	local speed = clamp( self.cl.speed / self.cl.maxSpeedAudio, 0, 1 )
	self.cl.sparksEffect1:setParameter( "velocity", speed )
	self.cl.sparksEffect2:setParameter( "velocity", speed )
	self.cl.sparksEffect3:setParameter( "velocity", speed )
	self.cl.sparksEffect4:setParameter( "velocity", speed )
end

function PowerLadderHandle.client_onDestroy( self )
	Kinematic.client_onDestroy( self )

	if self.cl.localPlayerSeated then
		sm.localPlayer.getPlayer().clientPublicData.seatLockedCameraData = nil
	end
	self.cl.sparksEffect1:stop()
	self.cl.sparksEffect2:stop()
	self.cl.sparksEffect3:stop()
	self.cl.sparksEffect4:stop()


end

function PowerLadderHandle.client_onAction( self, action, state )
	 if action == sm.interactable.actions.use or action == sm.interactable.actions.jump then
        return true  -- consume action, prevent exit
    end
    return false
end

-- World-space look direction applied on unseat: the -Z of the final track key.
-- Cached once the track data has arrived from the server.
function PowerLadderHandle.cl_getUnseatLookDirection( self )
	if self.cl.unseatLookDirection == nil and self.cl.trackdata and self.cl.trackInstances then
		for trackName, instance in pairs( self.cl.trackInstances ) do
			local trackDataList = self:getTrackData( instance, trackName, self.cl.trackdata )
			if trackDataList and #trackDataList > 0 then
				local nodes = trackDataList[#trackDataList].nodes
				if nodes and #nodes > 0 then
					self.cl.unseatLookDirection = nodes[#nodes].rotation * FinalKeyLookAxis
					self.cl.unseatLookDirection.z = 0 -- Flatten to horizontal plane
					self.cl.unseatLookDirection = self.cl.unseatLookDirection:safeNormalize( FinalKeyLookAxis )
					break
				end
			end
		end
	end
	return self.cl.unseatLookDirection
end

function PowerLadderHandle.client_onUpdate( self, dt )
	local player = sm.localPlayer.getPlayer()
	if self.harvestable:getSeatCharacter() == player:getCharacter() then
		self.cl.localPlayerSeated = true
		-- Lerp FOV when seated
		self.cl.fovTimer = math.min( ( self.cl.fovTimer or 0 ) + dt, FovLerpDuration )
		local fovProgress = self.cl.fovTimer / FovLerpDuration
		local defaultFov = sm.camera.getDefaultFov()
		local fov = defaultFov + ( FovTarget - defaultFov ) * fovProgress

		if player.clientPublicData.seatLockedCameraData == nil then
			player.clientPublicData.seatLockedCameraData = {
				hideGui = false,
				cameraState = sm.camera.state.seatLockedCamera,
				seatLockedLocalDirection = SeatLocalCameraDirection,
				seatLockedLocalUp = SeatLocalCameraUp,
				seatLockedCameraPullback = SeatLockedCameraPullback,
				seatLockedCameraUpOffset = SeatLockedCameraUpOffset
			}
			sm.camera.setUnseatDirection( self:cl_getUnseatLookDirection() )
		end
		player.clientPublicData.seatLockedCameraData.cameraFov = fov
	elseif self.cl.localPlayerSeated then
		player.clientPublicData.seatLockedCameraData = nil
		self.cl.localPlayerSeated = false
	end
end

function PowerLadderHandle.cl_seat( self )
	if sm.localPlayer.getPlayer() and sm.localPlayer.getPlayer():getCharacter() then
		self.harvestable:setSeatCharacter( sm.localPlayer.getPlayer():getCharacter() )
	end
end

