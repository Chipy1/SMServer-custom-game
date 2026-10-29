--camera_util.lua

dofile( "$SURVIVAL_DATA/Scripts/game/survival_constants.lua" )


function SetWantedCameraData( wantedCameraData )
	if wantedCameraData.hideGui ~= nil then
		sm.gui.hideGui( wantedCameraData.hideGui )
	end
	if wantedCameraData.cameraState then
		sm.camera.setCameraState( wantedCameraData.cameraState )
		sm.render.setCinematic( wantedCameraData.cameraState == sm.camera.state.cutsceneFP or wantedCameraData.cameraState == sm.camera.state.cutsceneTP )
	end
	if wantedCameraData.cameraPosition then
		sm.camera.setPosition( wantedCameraData.cameraPosition )
	end
	if wantedCameraData.cameraRotation then
		sm.camera.setRotation( wantedCameraData.cameraRotation )
	end
	if wantedCameraData.cameraDirection then
		sm.camera.setDirection( wantedCameraData.cameraDirection )
	end
	if wantedCameraData.cameraFov then
		sm.camera.setFov( wantedCameraData.cameraFov )
	end
	if wantedCameraData.seatLockedLocalDirection then
		sm.camera.setSeatLockedLocalDirection( wantedCameraData.seatLockedLocalDirection )
	end
	if wantedCameraData.seatLockedLocalUp then
		sm.camera.setSeatLockedLocalUp( wantedCameraData.seatLockedLocalUp )
	end
	if wantedCameraData.seatLockedCameraPullback then
		sm.camera.setSeatLockedCameraPullback( wantedCameraData.seatLockedCameraPullback )
	end
	if wantedCameraData.seatLockedCameraUpOffset then
		sm.camera.setSeatLockedCameraUpOffset( wantedCameraData.seatLockedCameraUpOffset )
	end
	if wantedCameraData.lockedControls ~= nil then
		sm.localPlayer.setLockedControls( wantedCameraData.lockedControls )
	end
end


function UpdateVendorCamera(vendor, dt)
		local currentCameraDirection
		local currentCameraPosition

		if vendor.cl.user.clientPublicData.interactableCameraData == nil then
			currentCameraDirection = sm.camera.getDirection()
			currentCameraPosition = sm.camera.getPosition()
		else
			currentCameraDirection = vendor.cl.user.clientPublicData.interactableCameraData.cameraDirection
			currentCameraPosition = vendor.cl.user.clientPublicData.interactableCameraData.cameraPosition
		end
		local cameraDesiredDirection = currentCameraDirection
		local cameraDesiredPosition = currentCameraPosition

		if vendor.cl.cameraNode then
			cameraDesiredDirection = vendor.cl.cameraNode.rotation * sm.vec3.new( 0, 1, 0 )
			cameraDesiredPosition = vendor.cl.cameraNode.position
		end

		local cameraDirection = magicDirectionInterpolation( currentCameraDirection, cameraDesiredDirection, dt, 1.0 / 10.0 )
		local cameraPosition = magicPositionInterpolation( currentCameraPosition, cameraDesiredPosition, dt, 1.0 / 10.0 )

		-- Finalize
		local interactableCameraData = {}
		interactableCameraData.hideGui = false
		interactableCameraData.cameraState = sm.camera.state.scriptedTP
		interactableCameraData.cameraPosition = cameraPosition
		interactableCameraData.cameraDirection = cameraDirection
		interactableCameraData.cameraFov = sm.camera.getDefaultFov()
		interactableCameraData.lockedControls = true
		vendor.cl.user.clientPublicData.interactableCameraData = interactableCameraData
end