-- Bed.lua --

Bed = class( nil )

function Bed.server_onDestroy( self )
	if SurvivalGame then
		if self.loaded then
			g_respawnManager:sv_destroyBed( self.shape )
			self.loaded = false
		end
	end
end

function Bed.server_onUnload( self )
	if SurvivalGame then
		if self.loaded then
			g_respawnManager:sv_updateBed( self.shape )
			self.loaded = false
		end
	end
end

function Bed.sv_activateBed( self, character )
	g_respawnManager:sv_registerBed( self.shape, character )
end

function Bed.server_onCreate( self )
	self.loaded = true
end

function Bed.server_onFixedUpdate( self )
	if SurvivalGame then
		local prevWorld = self.currentWorld
		self.currentWorld = self.shape.body:getWorld()
		if prevWorld ~= nil and self.currentWorld ~= prevWorld then
			g_respawnManager:sv_updateBed( self.shape )
		end
	end
end

-- Client

function Bed.cl_shouldBlockSleep( self )
	
	local world = self.shape.body:getWorld()
	local pubData = world.clientPublicData
	-- General block bed by world setting
	if world and pubData and pubData.blockBed then
		return true
	end

	local pos = self.shape.worldPosition

	-- Block bed in trashbot two fight
	if world and pubData and pubData.type == "UndergroundWorld" and pubData.depth == 5 and pos.z < 50 then
		return true
	end

	-- Block bed in trashbot one fight	
	local cellX = math.floor( pos.x / 64 )
	local cellY = math.floor( pos.y / 64 )
	if pos.z > 200 and isAnyOf( "WAREHOUSE4QUEST", sm.cell.getTags( cellX, cellY ) ) then
		return true
	end

	return false
end

function Bed.client_onInteract( self, character, state )
	if SurvivalGame then
		if state == true then
			local blockSleep = self:cl_shouldBlockSleep()
			if blockSleep then
				NotificationManager.Cl_AddGenericNotification( "#{INFO_HOME_NOT_STORED}" )
			else
				self.network:sendToServer( "sv_activateBed", character )
				self:cl_seat()
				NotificationManager.Cl_AddGenericNotification( "#{INFO_HOME_STORED}" )
			end
		end
	else
		if state == true then
			self:cl_seat()
		end
	end
end

function Bed.cl_seat( self )
	if sm.localPlayer.getPlayer() and sm.localPlayer.getPlayer():getCharacter() then
		self.interactable:setSeatCharacter( sm.localPlayer.getPlayer():getCharacter() )
	end
end

function Bed.client_onAction( self, controllerAction, state )
	local consumeAction = true
	if state == true then
		if controllerAction == sm.interactable.actions.use or controllerAction == sm.interactable.actions.jump then
			self:cl_seat()
		elseif not ( controllerAction == sm.interactable.actions.attack ) then
			consumeAction = false
		end
	else
		consumeAction = false
	end
	return consumeAction
end