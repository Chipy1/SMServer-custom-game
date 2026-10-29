dofile( "$SURVIVAL_DATA/Scripts/game/managers/UndergroundElevatorManager.lua" )

UndergroundElevatorCallButton = class( nil )

function UndergroundElevatorCallButton.server_onCreate( self )
	self.sv = {}
	self.sv.saved = self.storage:load()
	if self.sv.saved == nil then
		self.sv.saved = {}
		if self.tags == nil then
			sm.log.error( "UndergroundElevatorCallButton missing tags! Shape id:"..tostring( self.shape:getId() ) )
		end
		self.sv.saved.connectionTag = UndergroundElevatorManager.Sv_FindUndergroundConnectionTag( self.tags )

		local _, floorData = UndergroundElevatorManager.Sv_FindElevatorFloor( sm.world.getCurrentWorld(), self.sv.saved.connectionTag )
		local startLocked = floorData ~= nil and floorData.callButtonLocked == true
		self.sv.saved.unlocked = not startLocked
		self.sv.saved.fullAnimation = startLocked

		self.storage:save( self.sv.saved )
	end
	self.network:setClientData( self.sv.saved )

	self.sv.storageKey = TileStorageManager.Sv_GetTileStorageKeyFromObject( self.interactable )
	self.sv.tileData = TileStorageManager.Sv_GetValueInSubTable( self.sv.storageKey, UNDERGROUND_ELEVATOR_TABLE, self.sv.saved.connectionTag )
end

function UndergroundElevatorCallButton.server_onFixedUpdate( self )
	if self.sv.tileData == nil then
		self.sv.tileData = TileStorageManager.Sv_GetValueInSubTable( self.sv.storageKey, UNDERGROUND_ELEVATOR_TABLE, self.sv.saved.connectionTag )
	end
end

function UndergroundElevatorCallButton.sv_n_onInteract( self )
	if self.sv.tileData == nil then
		return
	end
	local isLocked = self.sv.tileData.locked
	if isLocked == nil then
		isLocked = true
	end
	if isLocked then
		if LogEntryManager.Sv_HasLog( self.sv.tileData.lockUuid ) then
			self.sv.tileData.locked = false
			isLocked = false
			TileStorageManager.Sv_SetValueInSubTable( self.sv.storageKey, UNDERGROUND_ELEVATOR_TABLE, self.sv.saved.connectionTag, self.sv.tileData )
		end
	end
	if self.sv.saved.unlocked then
		if self.sv.tileData.elevator and sm.exists( self.sv.tileData.elevator ) and not isLocked then
			sm.event.sendToInteractable( self.sv.tileData.elevator, "sv_e_callButtonPressed" )
		end
	elseif not isLocked then
		QuestManager.Sv_SendEvent( "mininghub_elevator_unlock" )
		self.sv.saved.unlocked = true
		self.network:setClientData( self.sv.saved )
		self.sv.saved.fullAnimation = false
		self.storage:save( self.sv.saved )
	end
end

function UndergroundElevatorCallButton.server_onRefresh( self )
end

-- Client

function UndergroundElevatorCallButton.client_onCreate( self )
	self.cl = {}
	self.cl.unlocked = false
	self.cl.animations = {}
	self.cl.animations["Unlock"] = self:cl_createAnimation( "unlock" )
	self.cl.animations["Use"] = self:cl_createAnimation( "use" )
	self.cl.animations["Pose"] = self:cl_createAnimation( "unlock_pose" )
end

function UndergroundElevatorCallButton.client_onClientDataUpdate( self, data, channel )
	self.cl.unlocked = data.unlocked
	if data.unlocked and data.fullAnimation then
		self:cl_setAnimation( self.cl.animations["Unlock"], 0.0 )
		sm.effect.playHostedEffect( "Survivalobject - Elevatorkeyreaderunlock_key", self.shape, "key_jnt", { Color = sm.color.new( "ff7d00ff" ) } )
		sm.effect.playHostedEffect( "Survivalobject - Elevatorkeyreaderunlock", self.shape, "button_jnt" )
	elseif data.unlocked then
		self:cl_setAnimation( self.cl.animations["Pose"], 0.0 )
	end
	self.cl.lockUuid = UNDERGROUND_CONNECTION_TO_KEY_UUID[data.connectionTag]
end

function UndergroundElevatorCallButton.client_onInteract( self, _, state )
	if state then
		self.network:sendToServer( "sv_n_onInteract" )
		if self.cl.unlocked then
			self:cl_setAnimation( self.cl.animations["Use"], 0.0 )
		end
	end
end

function UndergroundElevatorCallButton.client_canInteract( self )
	if self.cl.lockUuid and not LogEntryManager.Cl_HasLog( self.cl.lockUuid ) then
		sm.gui.setInteractionText( "#{LOCKED}" )
		return false
	end
	if not self.cl.unlocked then
		sm.gui.setInteractionText( "", sm.gui.getKeyBinding( "Use", true ), "#{UNLOCK}" )
		return true
	end
	local animationsDone = true
	for _, animation in pairs( self.cl.animations ) do
		if animation.isActive then
			animationsDone = false
			break
		end
	end
	if animationsDone then
		sm.gui.setInteractionText( "", sm.gui.getKeyBinding( "Use", true ), "#{INTERACTION_USE}" )
	end
	return animationsDone
end

function UndergroundElevatorCallButton.client_onUpdate( self, dt )
	self:cl_updateAnimations( dt )
end

function UndergroundElevatorCallButton.cl_createAnimation( self, name )
	local animation =
	{
		name = name,
		playProgress = 0.0,
		playTime = self.interactable:getAnimDuration( name )
	}
	return animation
end

function UndergroundElevatorCallButton.cl_setAnimation( self, animation, playProgress )
	self:cl_unsetAnimations()
	animation.isActive = true
	animation.playProgress = playProgress
	self.interactable:setAnimEnabled( animation.name, true )
end

function UndergroundElevatorCallButton.cl_unsetAnimations( self )
	for _, animation in pairs( self.cl.animations ) do
		animation.isActive = false
		animation.playProgress = 0.0
		self.interactable:setAnimEnabled( animation.name, false )
		self.interactable:setAnimProgress( animation.name, animation.playProgress )
	end
end

function UndergroundElevatorCallButton.cl_updateAnimations( self, dt )
	for _, animation in pairs( self.cl.animations ) do
		self:cl_updateAnimation( animation, dt )
	end
end

function UndergroundElevatorCallButton.cl_updateAnimation( self, animation, dt )
	if animation.isActive then
		self.interactable:setAnimEnabled( animation.name, true )
		animation.playProgress = animation.playProgress + dt / animation.playTime

		if animation.playProgress > 1.0 then
			animation.playProgress = 1.0
			animation.isActive = false
		end

		self.interactable:setAnimProgress( animation.name, animation.playProgress )
	end
end










































