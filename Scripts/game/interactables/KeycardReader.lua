-- KeycardReader.lua --
dofile("$SURVIVAL_DATA/Scripts/game/survival_shapes.lua")
dofile( "$SURVIVAL_DATA/Scripts/game/managers/TutorialManager.lua" )

KeycardReader = class( nil )
KeycardReader.maxParentCount = 0
KeycardReader.maxChildCount = 1
KeycardReader.connectionInput = sm.interactable.connectionType.none
KeycardReader.connectionOutput = sm.interactable.connectionType.logic

local KEYREADER_LOCKED = 1
local KEYREADER_ERROR = 2
local KEYREADER_OPEN = 3

local log_entries = dofile ( "$SURVIVAL_DATA/Logs/log_entries.json" ).logList

function KeycardReader.server_onCreate( self )
	self.saved = self.storage:load()
	if self.saved == nil then
		self.saved = {}
	end
	if self.saved.unlocked == nil then
		self.saved.unlocked = false
	end
	if self.params then
		self.saved.isQuestCardReader = self.params.isQuestCardReader;
	end
	self.storage:save( self.saved )
	self.interactable.active = self.saved.unlocked

	self.network:setClientData( self.saved )
	self.interactable:setPublicData( { showError = false } )

	-- Fallback: if a quest card reader is already unlocked.
	if self.saved.isQuestCardReader and self.saved.unlocked then
		self:sv_tryAdvanceQuest()
	end
end

function KeycardReader.sv_tryAdvanceQuest( self )
	if self.saved.isQuestCardReader and LogEntryManager.Sv_HasLog( LOGS.log_warehouse_key ) then
		QuestManager.Sv_SendEvent( "event.quest_clear_warehouse.enter" )
	end
end

function KeycardReader.client_onInteract( self )
	if not self.cl.unlocked then
		self.network:sendToServer( "sv_n_questUnlock" )
	end
end

function KeycardReader.client_canInteract( self )
	if self.cl.isQuestCardReader then
		if not self.cl.unlocked then
			local logItemTitle = ""
			for _, log in ipairs( log_entries ) do
				if log.uuid == LOGS.log_warehouse_key then
					logItemTitle = log.title
				end
			end
			if LogEntryManager.Sv_HasLog( LOGS.log_warehouse_key ) and not self.cl.unlocked then
				local keyBindingText =  sm.gui.getKeyBinding( "Use", true )
				SetNeedResourceInteractionText( "", keyBindingText, "#{INTERACTION_INSERT}", logItemTitle )
				return true
			end
			SetNeedResourceInteractionText( "", "", "#{INFO_REQUIRES}", logItemTitle )
		end
		return false
	end

	if not self.cl.unlocked then
		local canUnlock
		local inventory = sm.localPlayer.getInventory()
		if sm.container.canSpend( inventory, obj_survivalobject_keycard, 1 ) then
			canUnlock = ( sm.localPlayer.getActiveItem() == obj_survivalobject_keycard )
		end

		local itemName = sm.shape.getShapeTitle( obj_survivalobject_keycard )
		if canUnlock then
			local keyBindingText =  sm.gui.getKeyBinding( "Create", true )
			SetNeedResourceInteractionText( "", keyBindingText, "#{INTERACTION_INSERT}", itemName )
		else
			SetNeedResourceInteractionText( "", "", "#{INFO_REQUIRES}", itemName )
		end
	end

	return false
end

function KeycardReader.client_onCreate( self )
	if self.cl == nil then
		self.cl = {}
	end
	self:client_onRefresh()
	self.cl.isQuestCardReader = false
	if self.cl.unlocked == true then
		self:client_setReaderState( KEYREADER_OPEN )
	else
		self:client_setReaderState( KEYREADER_LOCKED )
	end

end

function KeycardReader.client_onClientDataUpdate( self, clientData )
	if self.cl == nil then
		self.cl = {}
	end

	self.cl.unlocked = clientData.unlocked
	self.cl.isQuestCardReader = clientData.isQuestCardReader

	if self.cl.unlocked == true then
		self:client_setReaderState( KEYREADER_OPEN )
	else
		self:client_setReaderState( KEYREADER_LOCKED )
	end
end

function KeycardReader.client_onRefresh( self )

	self.client_updateElapsed = 0
	self.client_updateTime = 0.125
	self.client_stateCountdown = 0
	self.client_animationTime = 1.7
	self.client_animationElapsedTime = 0
	self.interactable:setAnimEnabled( "keycardreader_activate", true )

	if self.cl.unlocked == true then
		self:client_setReaderState( KEYREADER_OPEN )
	else
		self:client_setReaderState( KEYREADER_LOCKED )
	end

end

function KeycardReader.sv_n_questUnlock( self )
	if LogEntryManager.Sv_HasLog( LOGS.log_warehouse_key ) then
		self.saved.unlocked = true
		self.storage:save( self.saved )
		self.network:setClientData( self.saved )
		self.network:sendToClients( "client_setReaderState", KEYREADER_OPEN )
		sm.effect.playEffect( "Elevator - Keycarduse", self.shape.worldPosition, nil, self.shape.worldRotation )
		self.interactable.active = true
		self:sv_tryAdvanceQuest()
	end
end

function KeycardReader.sv_e_unlock( self, params )
	if self.saved.isQuestCardReader then
		return
	end
	if self.saved.unlocked == false and params.player and sm.exists( params.player )  then
		if params.keyId == obj_survivalobject_keycard then
			local inventory = params.player:getInventory()
			sm.container.beginTransaction()
			sm.container.spend( inventory, obj_survivalobject_keycard, 1, true )
			if sm.container.endTransaction() then
				self.saved.unlocked = true
				self.storage:save( self.saved )
				self.network:setClientData( self.saved )
				self.network:sendToClients( "client_setReaderState", KEYREADER_OPEN )
				sm.effect.playEffect( "Elevator - Keycarduse", self.shape.worldPosition, nil, self.shape.worldRotation )
				self.interactable.active = true
			else
				self.network:sendToClients( "client_setReaderState", KEYREADER_ERROR )
			end
		end
	end
end

function KeycardReader.sv_e_forceUnlock( self )
	self.saved.unlocked = true
	self.interactable.active = true
	self.storage:save( self.saved )
	self.network:setClientData( self.saved )
	self.network:sendToClients( "client_setReaderState", KEYREADER_OPEN )
end

function KeycardReader.server_onFixedUpdate( self )

	local publicData = self.interactable:getPublicData()
	if publicData.showError and self.saved.unlocked == false then
		self.network:sendToClients( "client_setReaderState", KEYREADER_ERROR )
		publicData.showError = false
	end

end

-- Client

function KeycardReader.client_onUpdate( self, deltaTime )

	if self.client_stateCountdown > 0 then
		self.client_stateCountdown = self.client_stateCountdown - deltaTime
		if self.client_stateCountdown <= 0 then
			self.client_stateCountdown = 0
			if self.client_state == KEYREADER_ERROR then
				self:client_setReaderState( KEYREADER_LOCKED )
			end
		end
	end

	self.client_updateElapsed = self.client_updateElapsed + deltaTime
	if self.client_updateElapsed >= self.client_updateTime then
		self.client_updateElapsed = self.client_updateElapsed - self.client_updateTime
		self.client_frame = self.client_frame + 1
		if self.client_frame > self.client_frameEnd then
			if self.client_looping then
				self.client_frame = self.client_frameStart
			else
				self.client_frame = self.client_frameEnd
			end
		end
		self.interactable:setUvFrameIndex( self.client_frame )
	end

	if self.cl.unlocked then
		self.client_animationElapsedTime = math.min( self.client_animationElapsedTime + deltaTime, self.client_animationTime )
		self.interactable:setAnimProgress( "keycardreader_activate", self.client_animationElapsedTime / self.client_animationTime )
	else
		self.interactable:setAnimProgress( "keycardreader_activate", 1.0 )
	end

end

function KeycardReader.client_setReaderState( self, index )

	if index == KEYREADER_LOCKED then
		self.client_frameStart = 0
		self.client_frameEnd = 3
		self.client_looping = true
		self.client_frame = self.client_frameStart
		self.client_state = index
	elseif index == KEYREADER_ERROR then
		if self.client_state ~= KEYREADER_ERROR then
			sm.effect.playEffect( "Elevator - Error", self.shape.worldPosition, nil, self.shape.worldRotation )
		end
		self.client_frameStart = 12
		self.client_frameEnd = 15
		self.client_looping = false
		self.client_frame = self.client_frameStart
		self.client_state = index
		self.client_stateCountdown = 1.0
	elseif index == KEYREADER_OPEN then
		self.client_frameStart = 4 --9 checkmark
		self.client_frameEnd = 11
		self.client_looping = false
		self.client_frame = self.client_frameStart
		self.client_state = index
	end

end
