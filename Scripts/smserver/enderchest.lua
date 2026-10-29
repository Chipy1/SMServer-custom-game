dofile( "$CONTENT_DATA/Scripts/smserver/skycontainer.lua" )

enderchest = class()
enderchest.poseWeightCount = 1
enderchest.step = ( 1 / 0.1 ) / 40

local MaxInteractDistance = 12
local MaxOpenDistance = 24
local RequestCooldownTicks = 40

local function findPlayerById( id )
	for _, player in ipairs( sm.player.getAllPlayers() ) do
		if player.id == id then
			return player
		end
	end
	return nil
end

function enderchest_user( ownerId, displayName )
	local container = skycontainer_getContainer( "@" .. tostring( ownerId ) )
	if not container then
		return nil
	end
	return { ( displayName or "player" ) .. " chest", container }
end

function enderchest_public()
	return { "#ff0000public#ffffff chest", skycontainer_getContainer( "enderchest" ) }
end

function enderchest:isNear( player )
	return smserver_inRange( player, self.shape.worldPosition, MaxInteractDistance )
end

function enderchest:canRequest( player )
	local now = sm.game.getCurrentTick()
	local last = self.requestCooldown[player.id]
	if last ~= nil and now - last < RequestCooldownTicks then
		return false
	end
	self.requestCooldown[player.id] = now
	return true
end

function enderchest:server_onCreate()
	self.opened = {}
	self.requestCooldown = {}
end

function enderchest:server_onFixedUpdate()
	if self.timer then
		self.timer = self.timer - 1
		if self.timer <= 0 then
			if self.func then
				self.func()
				self.func = nil
			end
			self.timer = nil
		end
	end

	-- Do not keep a container GUI usable after the player leaves the chest.
	local hadOpen = false
	for playerId in pairs( self.opened ) do
		hadOpen = true
		local player = findPlayerById( playerId )
		if player == nil or not smserver_inRange( player, self.shape.worldPosition, MaxOpenDistance ) then
			if player ~= nil then
				self.network:sendToClient( player, "cl_forceClose" )
			end
			self.opened[playerId] = nil
		end
	end
	if hadOpen and next( self.opened ) == nil then
		self.network:sendToClients( "cl_setTargetAnim", 0 )
	end
end

function enderchest:sv_requestUserchest( ... )
	local player = smserver_getNetworkCaller( ... )
	if player == nil or player.character == nil or not self:isNear( player ) or not self:canRequest( player ) then
		return
	end

	self.func = function()
		local data = enderchest_user( player.id, player.name )
		if not data then
			self.network:sendToClient( player, "cl_alert", "#ff0000your ender chest is not ready yet, try again" )
			return
		end
		self.network:sendToClient( player, "cl_gui", data )
		self.network:sendToClients( "cl_setTargetAnim", 1 )
		self.opened[player.id] = true
	end

	if skycontainer_addContainer( "@" .. tostring( player.id ), skycontainer_enderchestSize ) then
		self.timer = 40
	else
		self.func()
		self.func = nil
	end
end

function enderchest:sv_requestEnderchest( ... )
	local player = smserver_getNetworkCaller( ... )
	if player == nil or player.character == nil or not self:isNear( player ) or not self:canRequest( player ) then
		return
	end

	self.func = function()
		self.network:sendToClient( player, "cl_gui", enderchest_public() )
		self.network:sendToClients( "cl_setTargetAnim", 1 )
		self.opened[player.id] = true
	end

	if skycontainer_addContainer( "enderchest", skycontainer_enderchestSize ) then
		self.timer = 40
	else
		self.func()
		self.func = nil
	end
end

function enderchest:sv_close( ... )
	local player = smserver_getNetworkCaller( ... )
	if player == nil then
		return
	end
	self.opened[player.id] = nil
	for _ in pairs( self.opened ) do
		return
	end
	self.network:sendToClients( "cl_setTargetAnim", 0 )
end

function enderchest:client_onCreate()
	self.targetAnim = 0
	self.currentAnim = 0
end

function enderchest:client_onInteract( _, state )
	if state then
		self.network:sendToServer( "sv_requestUserchest" )
	end
end

function enderchest:client_onTinker( _, state )
	if state then
		self.network:sendToServer( "sv_requestEnderchest" )
	end
end

function enderchest:client_onFixedUpdate()
	if self.targetAnim > self.currentAnim then
		self.currentAnim = self.currentAnim + enderchest.step
		if self.currentAnim >= self.targetAnim then
			self.currentAnim = self.targetAnim
		end
	elseif self.targetAnim < self.currentAnim then
		self.currentAnim = self.currentAnim - enderchest.step
		if self.currentAnim <= self.targetAnim then
			self.currentAnim = self.targetAnim
		end
	end
	self.interactable:setPoseWeight( 0, self.currentAnim )
end

function enderchest:cl_gui( data )
	if type( data ) == "string" then
		sm.gui.displayAlertText( data )
		return
	end

	if self.gui and self.gui:isActive() then
		self.ignoreCloseCallback = true
		self.gui:close()
	end

	self.gui = sm.gui.createContainerGui( true )
	self.gui:setText( "UpperName", data[1] )
	self.gui:setContainer( "UpperGrid", data[2] )
	self.gui:setText( "LowerName", "#{INVENTORY_TITLE}" )
	self.gui:setContainer( "LowerGrid", sm.localPlayer.getInventory() )
	self.gui:setOnCloseCallback( "cl_onGuiClosed" )
	self.gui:open()
	self.ignoreCloseCallback = nil
end

function enderchest:cl_onGuiClosed()
	self.gui = nil
	if not self.ignoreCloseCallback then
		self.network:sendToServer( "sv_close" )
	end
	self.ignoreCloseCallback = nil
end

function enderchest:cl_forceClose()
	if self.gui ~= nil then
		self.ignoreCloseCallback = true
		self.gui:close()
		self.gui = nil
	end
end

function enderchest:cl_alert( text )
	sm.gui.displayAlertText( text )
end

function enderchest:cl_setTargetAnim( targetValue )
	self.targetAnim = targetValue
end

function enderchest:client_canInteract()
	sm.gui.setInteractionText( "", sm.gui.getKeyBinding( "Use", true ), "personal ender chest" )
	sm.gui.setInteractionText( "", sm.gui.getKeyBinding( "Tinker", true ), "public ender chest" )
	return true
end
