-- Wardrobe.lua --
dofile( "$SURVIVAL_DATA/Scripts/util.lua" )
dofile "$SURVIVAL_DATA/Scripts/game/survival_constants.lua"

Wardrobe = class( nil )

local OpenShutterDistance = 4.0
local CloseShutterDistance = 6.0

-- Server

function Wardrobe.server_onCreate( self )
	self:sv_init()
end

function Wardrobe.server_canErase( self )
	if self.sv.saved.currentProcess ~= nil then
		return false
	end
	return true
end

function Wardrobe.server_onUnload( self )
	self.storage:save( self.sv.saved )
end

function Wardrobe.server_onRefresh( self )
	self:sv_init()
end

function Wardrobe.sv_init( self ) 
	self.sv = {}
	
	self.sv.saved = self.storage:load()

	if self.sv.saved == nil then
		self.sv.saved = {}
		self.sv.saved.currentProcess = nil
		self.storage:save( self.sv.saved )
		self.network:setClientData( true, 2 )
	end
	self.network:setClientData( self.sv.saved.currentProcess )
end

function Wardrobe.server_onFixedUpdate( self )
	if self.sv.saved.currentProcess then
		local recipe = self:getRecipe( self.sv.saved.currentProcess.itemId )

		if self.sv.saved.currentProcess.time < recipe.craftTime * 40 then
			self.sv.saved.currentProcess.time = self.sv.saved.currentProcess.time + 1

			self.network:setClientData( self.sv.saved.currentProcess ) --TODO: Less frequent
		end
	end
end

function Wardrobe.sv_n_craft( self, params, player )
	local recipe = self:getRecipe( params.itemId )
	-- Charge container
	sm.container.beginTransaction()
	for _,ingredient in ipairs( recipe.ingredientList ) do
		sm.container.spend( player:getInventory(), ingredient.itemId, ingredient.quantity )
	end
	if sm.container.endTransaction() or not sm.game.getLimitedInventory() then -- Can afford
		print( "Crafting:", params.itemId )
		self.sv.saved.currentProcess = { itemId = params.itemId, time = -1 }
		self.storage:save( self.sv.saved )		
	else
		print( "Can't afford to craft" )
	end
end

function Wardrobe.sv_n_unbox( self, params, player )
	self.sv.saved.currentProcess = nil
	self.storage:save( self.sv.saved )
	self.network:setClientData( self.sv.saved.currentProcess )
	self.network:sendToClients( "cl_n_onUnbox", player )
end

-- Common util
function Wardrobe.getRecipe( self, stringUuid )
		local recipe = g_craftingRecipeSets["dressbot"].recipes[stringUuid]
		if recipe then
			return recipe
		end
	return nil
end
-- Client

function Wardrobe.client_onCreate( self )
	self:cl_init()
end

function Wardrobe.client_onDestroy( self )
	if self.cl.guiCustomizationInterface and self.cl.guiCustomizationInterface:isActive() then
		self.cl.guiCustomizationInterface:close()
		self.cl.guiCustomizationInterface:destroy()
		local player = sm.localPlayer.getPlayer()
		player.clientPublicData.interactableCameraData = nil
	end
	if self.cl.guiDressbotInterface and self.cl.guiDressbotInterface:isActive() then
		self.cl.guiDressbotInterface:close()
		self.cl.guiDressbotInterface:destroy()
	end
	if self.cl.audioEffect:isPlaying() then
		self.cl.audioEffect:stop()
	end
end

function Wardrobe.client_onRefresh( self )

	if self.cl then
		if self.cl.user then
			local player = sm.localPlayer.getPlayer()
			player.clientPublicData.interactableCameraData = nil
			self.cl.user:setLockingInteractable( nil )
		end
	end
	self.cl.guiCustomizationInterface:close()
	self:cl_init()
end

function Wardrobe.client_canErase( self )
	if self.cl.currentProcess ~= nil then
		NotificationManager.Cl_AddGenericNotification( "#{INFO_BUSY}", BUSY_NOTIFICATION_DURATION )
		return false
	end
	return true
end

function Wardrobe.cl_init( self )
	self.cl = {}
	self.cl.pullback = 1
	self.cl.pullbackSeated = 1
	self.cl.cameraDirection = sm.vec3.new( 0, 1, 0 )
	self.cl.cameraHeading = 0
	self.cl.cameraDesiredHeading = self.cl.cameraHeading
	self.cl.cameraPitch = 0
	self.cl.cameraDesiredPitch = self.cl.cameraPitch
	self.cl.cameraPosition = self.shape.worldPosition - self.cl.cameraDirection
	self.cl.input = sm.vec3.new( 0, 0, 0 )
	self.cl.mouseInput = sm.vec3.new( 0, 0, 0 )
	self.cl.cameraPullback = 4
	self.cl.desiredCameraPullback = self.cl.cameraPullback
	
	self.cl.currentProcess = nil
	self.cl.guiCustomizationInterface = sm.gui.createCharacterCustomizationGui()
	self.cl.guiCustomizationInterface:setOnCloseCallback( "cl_onClose" )
	self.cl.guiCustomizationInterface:setOnOpenCallback( "cl_onOpen" )
	
	self.cl.guiDressbotInterface = sm.gui.createDressBotGui()
	self.cl.guiDressbotInterface:setGridButtonCallback( "CraftButton", "cl_onCraft" )
	self.cl.guiDressbotInterface:setButtonCallback( "UnboxButton", "cl_onUnbox" )
	self.cl.guiDressbotInterface:setButtonCallback( "CollectButton", "cl_onCollect" )
	self.cl.guiDressbotInterface:addGridItemsFromFile( "BoxGrid", "$SURVIVAL_DATA/CraftingRecipes/dressbot.json" )
	self.cl.guiDressbotInterface:setOnCloseCallback( "cl_onCloseDressbot" )
	self.cl.guiDressbotInterface:setDressbotUnlockCallback( "cl_onUnlock" )

	-- Setup animations
	local animations = {}
	animations["Unfold"] = self:cl_createAnimation( "Unfold", true )
	animations["Idle"] = self:cl_createAnimation( "Idle", true )
	animations["Craft_start"] = self:cl_createAnimation( "Craft_start", true )
	animations["Craft_loop01"] = self:cl_createAnimation( "Craft_loop01", true )
	animations["Craft_loop02"] = self:cl_createAnimation( "Craft_loop02", true )
	animations["Craft_finish"] = self:cl_createAnimation( "Craft_finish", true )

	self.cl.animations = animations
	self:cl_setAnimation( self.cl.animations["Idle"], 0.0 )

	self.cl.doorAnimation = self:cl_createAnimation( "Control_doors", true )
	self.cl.doorAnimation.isActive = true

	-- Setup effects
	self.cl.idleEffect = sm.effect.createEffect( "Dressbot - Idle", self.interactable )
	self.cl.work01Effect = sm.effect.createEffect( "Dressbot - Work01", self.interactable )
	self.cl.work02Effect = sm.effect.createEffect( "Dressbot - Work02", self.interactable )
	self.cl.workHeadEffect = sm.effect.createEffect( "Dressbot - HeadWork01", self.interactable, "spool_jnt"  )
	self.cl.doorEffect = sm.effect.createEffect( "Dressbot - Opendoors", self.interactable )
	self.cl.audioEffect = sm.effect.createEffect( "Dressbot - CraftAudio", self.interactable )
end

function Wardrobe.client_canInteract( self )
	local interactRange = 7.5
	local success, result = sm.localPlayer.getRaycast(interactRange)
	
	local outputPosition = sm.shape.getWorldPosition(self.shape) + self.shape.right * -1.85  + self.shape.up * 0.5 + self.shape.at * -0.5
	local outputDistance = (result.pointWorld - outputPosition):length()
	local outputSphereRadius = 2.0
	local outputWeightedValue = outputDistance / outputSphereRadius
	
	local keyBindingText =  sm.gui.getKeyBinding( "Use", true )
	
	if outputWeightedValue < 1.0 then
		sm.gui.setInteractionText( "", keyBindingText, "#{INTERACTION_USE_DRESSBOT}" )
	else
		sm.gui.setInteractionText( "", keyBindingText, "#{INTERACTION_USE_WARDROBE}" )
	end
	
	return true
end

function Wardrobe.client_onInteract( self, character, state ) 
	if state == true then
		local interactRange = 7.5
		local success, result = sm.localPlayer.getRaycast(interactRange)
		
		local outputPosition = sm.shape.getWorldPosition(self.shape) + self.shape.right * -1.85  + self.shape.up * 0.5 + self.shape.at * -0.5
		local outputDistance = (result.pointWorld - outputPosition):length()
		local outputSphereRadius = 2.0
		local outputWeightedValue = outputDistance / outputSphereRadius
		
		if outputWeightedValue < 1.0 then
			self.cl.guiDressbotInterface:open()
		else
			self.cl.interactingCharacter = character
			self.cl.guiCustomizationInterface:open()
		end
	end
end

function Wardrobe.cl_onOpen( self )
	if self.cl.user == nil and self.cl.interactingCharacter then
		self.cl.interactingCharacter:setLockingInteractable( self.interactable )
		self.cl.user = self.cl.interactingCharacter
		--audio event
		
		
		
		self.cl.cameraDirection = -self.cl.interactingCharacter:getDirection()
		local direction = sm.vec3.new( self.cl.cameraDirection.x, self.cl.cameraDirection.y, 0 )
		if direction:length() >= FLT_EPSILON then
			self.cl.cameraDirection = direction:normalize()
		end
		self.cl.cameraPosition = self.cl.interactingCharacter.worldPosition - self.cl.cameraDirection * self.cl.cameraPullback
		self.cl.cameraDesiredHeading = math.atan2( -self.cl.cameraDirection.x, self.cl.cameraDirection.y )
		self.cl.cameraHeading = self.cl.cameraDesiredHeading
		self.cl.cameraDesiredPitch = math.asin( self.cl.cameraDirection.z )
		self.cl.cameraPitch = self.cl.cameraDesiredPitch
	end
end

function Wardrobe.cl_onUnlock( self, uuid )
    if uuid and not uuid:isNil() then
        self.cl.lastUnboxed = uuid
    end
end

function Wardrobe.cl_onCloseDressbot( self )
	if self.cl.clearOnClose then
		if self.cl.lastUnboxed then
			NotificationManager.Cl_AddQuestRewardNotification( self.cl.lastUnboxed )
			self.cl.lastUnboxed = nil
		end

		if self.cl.guiDressbotInterface then
			self.cl.clearOnClose = false
			self.cl.guiDressbotInterface:clearGrid( "ProcessGrid" )
		end
	end
end

function Wardrobe.cl_onClose( self )
	if self.cl.user then
		local player = sm.localPlayer.getPlayer()
		player.clientPublicData.interactableCameraData = nil
		if sm.exists( self.cl.user ) then
			self.cl.user:setLockingInteractable( nil )
		end
		self.cl.user = nil
		self.cl.input = sm.vec3.new( 0, 0, 0 )
		self.cl.cameraDirection = sm.vec3.new( 0, 1, 0 )
		self.cl.cameraPosition = self.shape.worldPosition - self.cl.cameraDirection
		self.cl.cameraHeading = 0
		self.cl.cameraDesiredHeading = self.cl.cameraHeading
		self.cl.cameraPitch = 0
		self.cl.cameraDesiredPitch = self.cl.cameraPitch
	end
end

function Wardrobe.client_onAction( self, controllerAction, state )
	if state == true then
		if controllerAction == sm.interactable.actions.left then
			self.cl.input.x = -1
		elseif controllerAction == sm.interactable.actions.right then
			self.cl.input.x = 1
		elseif controllerAction == sm.interactable.actions.forward then
			self.cl.input.y = 1
		elseif controllerAction == sm.interactable.actions.backward then
			self.cl.input.y = -1
		else
			return false
		end
	else		
		if controllerAction == sm.interactable.actions.left then
			self.cl.input.x = 0
		elseif controllerAction == sm.interactable.actions.right then
			self.cl.input.x = 0
		elseif controllerAction == sm.interactable.actions.forward then
			self.cl.input.y = 0
		elseif controllerAction == sm.interactable.actions.backward then
			self.cl.input.y = 0
		else
			return false
		end
	end
	return true
end

function Wardrobe.client_onUpdate( self, dt )

	self:cl_selectAnimation()
	self:cl_updateAnimations( dt )

	local character = sm.localPlayer.getPlayer().character
	if self.cl.user and ( not sm.exists( self.cl.user ) or self.cl.user ~= character ) then
		if self.cl.guiCustomizationInterface and self.cl.guiCustomizationInterface:isActive() then
			self.cl.guiCustomizationInterface:close()
		else
			self:cl_onClose()
		end
		return
	end

	if self.cl.user and self.cl.user == character then
	
		local epsilon = 0.000244140625
		--local mouseSpeed = 1.0
		local mouseSpeed = 12.0

		if self.cl.input.x ~= 0 or self.cl.input.y ~= 0 then
			local relX = self.cl.input.x * mouseSpeed * math.pi * 0.001
			local relY = self.cl.input.y * mouseSpeed * math.pi * 0.001

			self.cl.cameraDesiredPitch = self.cl.cameraDesiredPitch - relY
			self.cl.cameraDesiredHeading = self.cl.cameraDesiredHeading + relX

			self.cl.mouseInput.x = 0
			self.cl.mouseInput.y = 0
		elseif self.cl.mouseInput.x ~= 0 or self.cl.mouseInput.y ~= 0 then
			local relX = self.cl.mouseInput.x * mouseSpeed * math.pi * 0.001
			local relY = self.cl.mouseInput.y * mouseSpeed * math.pi * 0.001
			self.cl.mouseInput = self.cl.mouseInput * 0.3
			if self.cl.mouseInput:length2() < 0.002 then
				self.cl.mouseInput.x = 0
				self.cl.mouseInput.y = 0
			end

			self.cl.cameraDesiredPitch = self.cl.cameraDesiredPitch - relY
			self.cl.cameraDesiredHeading = self.cl.cameraDesiredHeading + relX
		end

		-- Avoid pitching beyond straight up and straight down
		if self.cl.cameraDesiredPitch > math.pi * 0.5 - epsilon then
			self.cl.cameraDesiredPitch = math.pi * 0.5 - epsilon
		end
		if self.cl.cameraDesiredPitch < -math.pi * 0.5 + epsilon then
			self.cl.cameraDesiredPitch = -math.pi * 0.5 + epsilon
		end
		
		-- Keep heading within 0 and 2*pi
		while self.cl.cameraDesiredHeading > math.pi * 2 do
			self.cl.cameraDesiredHeading = self.cl.cameraDesiredHeading - math.pi * 2
			self.cl.cameraHeading = self.cl.cameraHeading - math.pi * 2
		end
		while self.cl.cameraDesiredHeading < 0 do
			self.cl.cameraDesiredHeading = self.cl.cameraDesiredHeading + math.pi * 2
			self.cl.cameraHeading = self.cl.cameraHeading + math.pi * 2
		end
		
		-- Smooth heading and pitch movement
		local cameraLerpSpeed = 1.0 / 6.0
		local blend = 1 - math.pow( 1 - cameraLerpSpeed, dt * 60 )
		self.cl.cameraHeading = sm.util.lerp( self.cl.cameraHeading, self.cl.cameraDesiredHeading, blend )
		self.cl.cameraPitch = sm.util.lerp( self.cl.cameraPitch, self.cl.cameraDesiredPitch, blend )
		self.cl.cameraDirection = sm.vec3.new( 0, 1, 0 )
		self.cl.cameraDirection = self.cl.cameraDirection:rotateX( self.cl.cameraPitch )
		self.cl.cameraDirection = self.cl.cameraDirection:rotateZ( self.cl.cameraHeading )
		
		-- Smooth pullback
		local pullbackSteps = 0.5
		self.cl.cameraPullback = sm.util.lerp( self.cl.cameraPullback, self.cl.desiredCameraPullback, blend )
				
		local left = sm.vec3.new( 0, 0, 1 ):cross( self.cl.cameraDirection )
		left.z = 0.0
		if left:length() >= FLT_EPSILON then
			left = left:normalize()
		end
		
		-- calculate offset based on distance and fov
		local fov = sm.camera.getFov()
		local angleRad = DegToRad( fov / 2 )
		local desiredDistance = self.cl.cameraPullback * pullbackSteps
		local opposite = math.tan( angleRad ) * desiredDistance * 1.5
		local cameraOffset = left * ( opposite / 2 )

		local cameraPosition = character.worldPosition + cameraOffset - self.cl.cameraDirection * desiredDistance
		local vectorToCamera = cameraPosition - character.worldPosition
		
		-- Adjust camera position if the view is blocked
		local fraction = sm.camera.cameraSphereCast( 0.2, character.worldPosition, vectorToCamera )
		if fraction ~= 1 then
			cameraOffset = left * ( opposite / 2 * fraction )
			cameraPosition = character.worldPosition + cameraOffset - self.cl.cameraDirection * desiredDistance * fraction
		end
		
		self.cl.cameraPosition = cameraPosition
		
		-- Finalize
		local interactableCameraData = {}
		interactableCameraData.hideGui = false
		interactableCameraData.cameraState = sm.camera.state.scriptedTP
		interactableCameraData.cameraPosition = self.cl.cameraPosition
		interactableCameraData.cameraDirection = self.cl.cameraDirection
		interactableCameraData.cameraFov = sm.camera.getDefaultFov()
		interactableCameraData.lockedControls = false
		self.cl.user:getPlayer().clientPublicData.interactableCameraData = interactableCameraData
	end
end

function Wardrobe.cl_onCraft( self, buttonName, index, data )
	self.network:sendToServer( "sv_n_craft", { itemId = data.itemId } )
end

function Wardrobe.cl_onUnbox( self, buttonName )
	self.cl.clearOnClose = true
	self.network:sendToServer( "sv_n_unbox" )
end

function Wardrobe.cl_onCollect( self)
	self.cl.lastUnboxed = nil
end

function Wardrobe.cl_n_onUnbox( self, player )
	if player ~= sm.localPlayer.getPlayer() then
		self.cl.guiDressbotInterface:clearGrid( "ProcessGrid" )
	end
end

function Wardrobe.client_onClientDataUpdate( self, data, channel )
	if channel == 1 then
		self.cl.currentProcess = data
		if data ~= nil then
			local recipe = self:getRecipe( data.itemId )
			self.cl.clearOnClose = false
			self.cl.guiDressbotInterface:setGridItem( "ProcessGrid", 0, { itemId = data.itemId } )
			self.cl.guiDressbotInterface:setData( "Progress", { craftTime = recipe.craftTime * 40, elapsedTime = data.time } )
		end
	elseif channel == 2 then
		if data then
			self:cl_setAnimation( self.cl.animations["Unfold"], 0.0 )
		end
	end
end

-- Animations
function Wardrobe.cl_createAnimation( self, name, playForward )
	local animation =
	{
		-- Required
		name = name,
		playProgress = 0.0,
		playTime = self.interactable:getAnimDuration( name ),
		isActive = false,
		-- Optional
		playForward = ( playForward or playForward == nil )
	}
	return animation
end

function Wardrobe.cl_setAnimation( self, animation, playProgress )
	self:cl_unsetAnimation()
	animation.isActive = true
	animation.playProgress = playProgress
	self.interactable:setAnimEnabled(animation.name, true)
end

function Wardrobe.cl_unsetAnimation( self )
	for name, animation in pairs( self.cl.animations ) do
		animation.isActive = false
		animation.playProgress = 0.0
		self.interactable:setAnimEnabled( animation.name, false )
		self.interactable:setAnimProgress( animation.name, animation.playProgress )
	end
end

function Wardrobe.cl_selectAnimation( self )

	-- Open/Close shutter
	if self.cl.doorAnimation.isActive then
		if math.abs( self.cl.doorAnimation.playProgress ) >= 1.0 then
			if GetClosestPlayer( self.shape.worldPosition, OpenShutterDistance, self.shape.body:getWorld() ) ~= nil then
				if self.cl.doorAnimation.playForward == false then
					self.cl.doorEffect:start()
				end
				self.cl.doorAnimation.playForward = true
			elseif GetClosestPlayer( self.shape.worldPosition, CloseShutterDistance, self.shape.body:getWorld() ) == nil then
				if self.cl.doorAnimation.playForward == true then
					self.cl.doorEffect:start()
				end
				self.cl.doorAnimation.playForward = false
			end
		end
	end

	if self.cl.currentProcess then
		local recipe = self:getRecipe( self.cl.currentProcess.itemId )
		if self.cl.currentProcess.time < recipe.craftTime * 40 then
			-- Crafting
			if self.cl.animations["Idle"].isActive then
				self:cl_setAnimation( self.cl.animations["Craft_start"], 0.0 )
			elseif self.cl.animations["Craft_start"].isActive and self.cl.animations["Craft_start"].playProgress >= 1.0 then
				self:cl_setAnimation( self.cl.animations["Craft_loop01"], 0.0 )
				self.cl.work01Effect:start()
				self.cl.workHeadEffect:start()
				if not self.cl.audioEffect:isPlaying() then
					self.cl.audioEffect:start()
				end
			elseif ( self.cl.animations["Craft_loop01"].isActive and self.cl.animations["Craft_loop01"].playProgress >= 1.0 ) or ( self.cl.animations["Craft_loop02"].isActive and self.cl.animations["Craft_loop02"].playProgress >= 1.0 ) then
				self.cl.work01Effect:stop()
				self.cl.work02Effect:stop()
				local craftLoop = randomStackAmount( 1, 1.285, 2 ) --67% craftloop1, 33% craftloop2
				if craftLoop == 2 and self.cl.animations["Craft_loop02"].playTime * 40 <= recipe.craftTime * 40 - self.cl.currentProcess.time then
					self:cl_setAnimation( self.cl.animations["Craft_loop02"], 0.0 )
					self.cl.work02Effect:start()
					self.cl.workHeadEffect:start()
					self.cl.audioEffect:setParameter( "craftbot", 2 )
					if not self.cl.audioEffect:isPlaying() then
						self.cl.audioEffect:start()
					end
				else
					self:cl_setAnimation( self.cl.animations["Craft_loop01"], 0.0 )
					self.cl.work01Effect:start()
					self.cl.workHeadEffect:start()
					self.cl.audioEffect:setParameter( "craftbot", 1 )
					if not self.cl.audioEffect:isPlaying() then
						self.cl.audioEffect:start()
					end
				end
			end
		else
			-- Finish crafting
			if not self.cl.animations["Craft_finish"].isActive and not self.cl.animations["Idle"].isActive then
				self:cl_setAnimation( self.cl.animations["Craft_finish"], 0.0 )
				self.cl.work01Effect:stop()
				self.cl.work02Effect:stop()
				self.cl.audioEffect:stop()
			end
		end
	else
		-- Idle
		if self.cl.animations["Craft_finish"].isActive or self.cl.animations["Craft_loop02"].isActive or self.cl.animations["Craft_start"].isActive then
			self:cl_setAnimation( self.cl.animations["Idle"], 0.0 )
			self.cl.idleEffect:start()
		elseif self.cl.animations["Unfold"].isActive and self.cl.animations["Unfold"].playProgress >= 1.0 then
			self:cl_setAnimation( self.cl.animations["Idle"], 0.0 )
			self.cl.idleEffect:start()
		elseif self.cl.animations["Idle"].isActive and self.cl.animations["Idle"].playProgress >= 1.0 then
			self:cl_setAnimation( self.cl.animations["Idle"], ( self.cl.animations["Idle"].playProgress - 1.0 ) * self.cl.animations["Idle"].playTime )
			self.cl.idleEffect:start()
		end
	end

end

function Wardrobe.cl_updateAnimations( self, dt )
	for name, animation in pairs( self.cl.animations ) do
		self:cl_updateAnimation( animation, dt )
	end
	self:cl_updateAnimation( self.cl.doorAnimation, dt )
end

function Wardrobe.cl_updateAnimation( self, animation, dt )
	if animation.isActive then
		self.interactable:setAnimEnabled( animation.name, true )
		if animation.playForward then
			animation.playProgress = animation.playProgress + dt / animation.playTime
			if animation.playProgress > 1.0 then
				animation.playProgress = 1.0
			end
			self.interactable:setAnimProgress( animation.name, animation.playProgress )
		else
			animation.playProgress = animation.playProgress - dt / animation.playTime
			if animation.playProgress < -1.0 then
				animation.playProgress = -1.0
			end
			self.interactable:setAnimProgress(animation.name, 1.0 + animation.playProgress )
		end
	end
end

function Wardrobe.cl_onDragZoneUsed( self, deltaX, deltaY )
	self.cl.mouseInput.x = self.cl.mouseInput.x + deltaX * 180;
	self.cl.mouseInput.y = self.cl.mouseInput.y + deltaY * 180;
end

function Wardrobe.cl_onScroll( self, scrollValue )
	if scrollValue > 0 then
		self.cl.desiredCameraPullback = math.max( self.cl.desiredCameraPullback - 1, 3 )
	else
		self.cl.desiredCameraPullback = math.min( self.cl.desiredCameraPullback + 1, 10 )
	end
end