dofile("$SURVIVAL_DATA/Scripts/game/survival_shapes.lua")
dofile( "$SURVIVAL_DATA/Scripts/game/survival_constants.lua" )
dofile( "$SURVIVAL_DATA/Scripts/util.lua" )

MinidungeonKeycardReader = class( nil )
MinidungeonKeycardReader.maxParentCount = 0
MinidungeonKeycardReader.maxChildCount = 1
MinidungeonKeycardReader.connectionInput = sm.interactable.connectionType.none
MinidungeonKeycardReader.connectionOutput = sm.interactable.connectionType.logic

function MinidungeonKeycardReader.server_onCreate( self )
	self.sv = {}

	local world = self.shape.body:getWorld()
	self.sv.poiType = GetPoiTypeAtPosition( world, self.shape.worldPosition )
	if self.sv.poiType == nil then
		sm.log.warning( "MinidungeonKeycardReader could not resolve its tile poiType; the keycard reader will be unavailable." )
	end

	self.sv.saved = self.storage:load()
	if self.sv.saved == nil then
		self.sv.saved = {}
		self.sv.saved.fullAnimation = true
		self.sv.saved.unlocked = false
		self.storage:save( self.sv.saved )
	end

	self:sv_setClientData()
	self.interactable:setPublicData( { unlocked = self.sv.saved.unlocked } )
end

function MinidungeonKeycardReader.sv_setClientData( self )
	self.network:setClientData( { unlocked = self.sv.saved.unlocked, fullAnimation = self.sv.saved.fullAnimation, poiType = self.sv.poiType }, 1 )
end

function MinidungeonKeycardReader.server_onProjectile( self, hitPos, hitTime, hitVelocity, _, attacker, damage, userData, hitNormal, projectileUuid )
	if damage > 0 and self.sv.saved.unlocked == true then
		self:sv_n_onInteract()
	end
end

function MinidungeonKeycardReader.sv_n_onInteract( self )
	if LogEntryManager.Sv_HasLog( POI_TYPE_TO_LOG_UUID[self.sv.poiType] ) then
		if self.sv.saved.unlocked then
			self:sv_n_callElevator()
			QuestManager.Sv_SendEvent( QuestEvent.GrowlabElevatorCalled, { poiType = self.sv.poiType } )
			self.network:sendToClients( "cl_n_tryPlayUseAnimation" )
		else
			self.sv.saved.unlocked = true
			self.interactable:setPublicData( { unlocked = true } )
			QuestManager.Sv_SendEvent( QuestEvent.GrowlabUnlocked, { poiType = self.sv.poiType } )
			self:sv_setClientData()
			self.sv.saved.fullAnimation = false
			self.storage:save( self.sv.saved )

			if self.sv.poiType == POI_RUINCITY_XL then
				-- unlock the power ladder
				local tileKey = TileStorageManager.Sv_GetTileStorageKeyFromObject( self.interactable )
				SetRailPower( true, "ts:rail:scrap.city.growlab.entrance", tileKey )
			end
		end
	end
end

function MinidungeonKeycardReader.sv_n_callElevator( self )
	self.interactable:setActive( true )
end

-- Client

function MinidungeonKeycardReader.client_onCreate( self )
	self.cl = {}
	self.cl.unlocked = false
	self.cl.animations = {}
	self.cl.animations["Unlock"] = self:cl_createAnimation( "unlock" )
	self.cl.animations["Use"] = self:cl_createAnimation( "use" )
	self.cl.animations["Pose"] = self:cl_createAnimation( "unlock_pose" )
end

function MinidungeonKeycardReader.client_onClientDataUpdate( self, data, channel )
	if channel == 1 then
		self.cl.unlocked = data.unlocked
		self.cl.poiType = data.poiType
		local logData = nil
		for _, log in pairs( g_growlabLogs ) do
			if log.uuid == POI_TYPE_TO_LOG_UUID[self.cl.poiType] then
				logData = log
				break
			end
		end
		if data.unlocked and data.fullAnimation then
			self:cl_setAnimation( self.cl.animations["Unlock"], 0.0 )
			sm.effect.playHostedEffect( "Survivalobject - Growlabkeyreaderunlock_key", self.shape, "key_jnt", { Color = logData and sm.color.new( logData.color ) or sm.color.new( "FFFFFFFF" ) } )
			sm.effect.playHostedEffect( "Survivalobject - Elevatorkeyreaderunlock", self.shape, "button_jnt" )
		elseif data.unlocked then
			self:cl_setAnimation( self.cl.animations["Pose"], 0.0 )
		end
	end
end

function MinidungeonKeycardReader.client_canInteract( self )
	if not LogEntryManager.Cl_HasLog( POI_TYPE_TO_LOG_UUID[self.cl.poiType] ) then
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

function MinidungeonKeycardReader.client_onInteract( self, _, state )
	if state then
        self.network:sendToServer( "sv_n_onInteract" )
    end
end

function MinidungeonKeycardReader.cl_n_tryPlayUseAnimation( self )
	if self.cl.unlocked then
		self:cl_setAnimation( self.cl.animations["Use"], 0.0 )
	end
end

function MinidungeonKeycardReader.client_onUpdate( self, dt )
	self:cl_updateAnimations( dt )
end

function MinidungeonKeycardReader.cl_createAnimation( self, name )
	local animation =
	{
		name = name,
		playProgress = 0.0,
		playTime = self.interactable:getAnimDuration( name )
	}
	return animation
end

function MinidungeonKeycardReader.cl_setAnimation( self, animation, playProgress )
	self:cl_unsetAnimations()
	animation.isActive = true
	animation.playProgress = playProgress
	self.interactable:setAnimEnabled( animation.name, true )
end

function MinidungeonKeycardReader.cl_unsetAnimations( self )
	for _, animation in pairs( self.cl.animations ) do
		animation.isActive = false
		animation.playProgress = 0.0
		self.interactable:setAnimEnabled( animation.name, false )
		self.interactable:setAnimProgress( animation.name, animation.playProgress )
	end
end

function MinidungeonKeycardReader.cl_updateAnimations( self, dt )
    for _, animation in pairs( self.cl.animations ) do
		self:cl_updateAnimation( animation, dt )
	end
end

function MinidungeonKeycardReader.cl_updateAnimation( self, animation, dt )
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