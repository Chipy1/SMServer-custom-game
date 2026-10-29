privateblock = class()
privateblock.poseWeightCount = 1
privateblock.maxInteractDistance = 8
privateblock.maxUnlockedDistance = 64
privateblock.unlockedMessage = "#ffff00the creation is available for all players to change"
privateblock.lockedMessage = "#00ff00private is enabled again"
privateblock.notYourPrivateBlock = "#ff0000not your private block. owner: \"#ffffff"
privateblock.notYourPrivateBlockEnd = "#ff0000\""
privateblock.autolockMessage = " (creation will be automatically locked if you go more than " .. privateblock.maxUnlockedDistance .. " meters away or exit the game)"

local function distanceSquared( pos1, pos2 )
	return ( ( pos1.x - pos2.x ) ^ 2 ) + ( ( pos1.y - pos2.y ) ^ 2 ) + ( ( pos1.z - pos2.z ) ^ 2 )
end

function privateblock:server_onCreate()
	self.storageData = self.storage:load() or {}
	self.unlocked = false
end

function privateblock:isOwner( player )
	if self.storageData.steamId ~= nil then
		return self.storageData.steamId == player.id
	end
	-- Legacy saves stored only the nickname.
	return self.storageData.nickname ~= nil and self.storageData.nickname == player.name
end

function privateblock:findOwner()
	for _, player in ipairs( sm.player.getAllPlayers() ) do
		if self:isOwner( player ) then
			return player
		end
	end
	return nil
end

function privateblock:server_onFixedUpdate()
	local owner = self:findOwner()

	if self.unlocked then
		if owner ~= nil and owner.character ~= nil then
			if distanceSquared( owner.character.worldPosition, self.shape.worldPosition ) > privateblock.maxUnlockedDistance ^ 2 then
				self.network:sendToClient( owner, "cl_alert", privateblock.lockedMessage )
				self.unlocked = false
				self:privateblock_sendData()
			end
		else
			self.unlocked = false
		end
	end

	local lock = self.storageData.nickname ~= nil and not self.unlocked
	if lock ~= self._lock then
		for _, body in ipairs( self.shape.body:getCreationBodies() ) do
			body.paintable = not lock
			body.destructable = not lock
			body.liftable = not lock
			body.erasable = not lock
			body.buildable = not lock
			body.connectable = not lock
		end

		self._lock = lock
	end
end

function privateblock:privateblock_sendData( player )
	local data = {
		nickname = self.storageData.nickname,
		steamId = self.storageData.steamId,
		unlocked = self.unlocked
	}

	if player then
		self.network:sendToClient( player, "cl_response", data )
	else
		self.network:sendToClients( "cl_response", data )
	end
end

function privateblock:sv_request( ... )
	local player = smserver_getNetworkCaller( ... )
	if player == nil or player.character == nil then
		return
	end
	if distanceSquared( player.character.worldPosition, self.shape.worldPosition ) > privateblock.maxInteractDistance ^ 2 then
		return
	end
	self:privateblock_sendData( player )
end

function privateblock:sv_interact( ... )
	local player = smserver_getNetworkCaller( ... )
	if player == nil or player.character == nil then
		return
	end

	if distanceSquared( player.character.worldPosition, self.shape.worldPosition ) > privateblock.maxInteractDistance ^ 2 then
		self.network:sendToClient( player, "cl_alert", "#ff0000you're too far away, you can't switch the block" )
		return
	end

	if self.storageData.nickname ~= nil then
		if self:isOwner( player ) then
			self.unlocked = not self.unlocked
			if self.unlocked then
				self.network:sendToClient( player, "cl_alert", privateblock.unlockedMessage )
			else
				self.network:sendToClient( player, "cl_alert", privateblock.lockedMessage )
			end
			self:privateblock_sendData()
		else
			self.network:sendToClient( player, "cl_alert", privateblock.notYourPrivateBlock .. self.storageData.nickname .. privateblock.notYourPrivateBlockEnd )
		end
	else
		self.storageData.steamId = player.id
		self.storageData.nickname = player.name
		self.storage:save( self.storageData )
		self.network:sendToClient( player, "cl_alert", "#00ff00you have successfully linked the private block to yourself" )
		self:privateblock_sendData()
	end
end

function privateblock:client_onCreate()
	self.network:sendToServer( "sv_request" )
end

function privateblock:client_onFixedUpdate()
	-- The server rejects requests from far away; retry while nearby so the
	-- block becomes usable after the player walks up to it.
	if self.cl_data ~= nil then
		return
	end
	local now = sm.game.getCurrentTick()
	if self.lastRequestTick == nil or now - self.lastRequestTick >= 40 then
		self.lastRequestTick = now
		self.network:sendToServer( "sv_request" )
	end
end

function privateblock:client_onInteract( _, state )
	if state then
		self.network:sendToServer( "sv_interact" )
	end
end

function privateblock:client_canInteract( character )
	local player = sm.localPlayer.getPlayer()
	if not self.cl_data or not player then
		return false
	end

	local isOwner
	if self.cl_data.steamId ~= nil then
		isOwner = self.cl_data.steamId == player.id
	else
		isOwner = self.cl_data.nickname ~= nil and self.cl_data.nickname == player.name
	end

	local action, title
	if self.cl_data.nickname ~= nil then
		if isOwner then
			if self.cl_data.unlocked then
				action = "lock"
				title = "after being blocked, you will not be able to edit the creation yourself" .. privateblock.autolockMessage
			else
				action = "unlock"
				title = "when unlocking, the creation will be available for all players to change" .. privateblock.autolockMessage
			end
		else
			title = privateblock.notYourPrivateBlock .. self.cl_data.nickname .. privateblock.notYourPrivateBlockEnd
		end
	else
		action = "to claim private block"
	end

	if action then
		sm.gui.setInteractionText( "", sm.gui.getKeyBinding( "Use", true ), action )
	end
	sm.gui.setInteractionText( "", title or "" )

	return true
end

function privateblock:cl_response( data )
	self.cl_data = data
	self.interactable:setPoseWeight( 0, ( self.cl_data.unlocked or self.cl_data.nickname == nil ) and 1 or 0 )
end

function privateblock:cl_alert( text )
	sm.gui.displayAlertText( text )
end
