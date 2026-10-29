-- LogKeycardReader.lua --
dofile("$SURVIVAL_DATA/Scripts/game/survival_shapes.lua")
dofile( "$SURVIVAL_DATA/Scripts/game/managers/TutorialManager.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/managers/QuestManager.lua" )

local log_entries = dofile ( "$SURVIVAL_DATA/Logs/log_entries.json" ).logList

LogKeycardReader = class( nil )
LogKeycardReader.maxParentCount = 0
LogKeycardReader.maxChildCount = 1
LogKeycardReader.connectionInput = sm.interactable.connectionType.none
LogKeycardReader.connectionOutput = sm.interactable.connectionType.logic

local KEYREADER_LOCKED = 1
local KEYREADER_ERROR = 2
local KEYREADER_OPEN = 3

function LogKeycardReader.server_onCreate( self )
	self.saved = self.storage:load()
	if self.saved == nil then
		self.saved = {}
	end

	if self.saved.unlocked == nil then
		self.saved.unlocked = false
	end
	
	if self.params then
		self.saved.requiredLogItem = self.params.requiredLogItem
		self.saved.keyTag = self.params.keyTag
	end

	local tileStorageKey = TileStorageManager.Sv_GetTileStorageKeyFromObject( self.interactable )
	if TileStorageManager.Sv_GetValueInSubTable( tileStorageKey, KEY_LOCK_TABLE, self.saved.keyTag ) then
		self.saved.unlocked = true
	end

	self.storage:save( self.saved )
	self.interactable.active = self.saved.unlocked

	self.network:setClientData( self.saved )
	self.interactable:setPublicData( { showError = false } )
end

function LogKeycardReader.client_canInteract( self )
	if not self.cl.unlocked then
		local canUnlock = LogEntryManager.Cl_HasLog( self.cl.requiredLogItem )
		local logItemTitle = ""
		for _, log in ipairs( log_entries ) do
			if log.uuid == self.cl.requiredLogItem then
				logItemTitle = log.title
			end
		end
		if canUnlock then
			local keyBindingText =  sm.gui.getKeyBinding( "Use", true )
			SetNeedResourceInteractionText( "", keyBindingText, "#{INTERACTION_INSERT}", logItemTitle )
		else
			SetNeedResourceInteractionText( "", "", "#{INFO_REQUIRES}", logItemTitle )
			return false
		end
		return true
	end

	sm.gui.setInteractionText( "#{UNLOCKED}" )
	return false
end

function LogKeycardReader.client_onCreate( self )
	if self.cl == nil then
		self.cl = {}
	end
	self:client_onRefresh()
	if self.cl.unlocked == true then
		self:client_setReaderState( KEYREADER_OPEN )
	else
		self:client_setReaderState( KEYREADER_LOCKED )
	end
end

function LogKeycardReader.client_onClientDataUpdate( self, clientData )
	if self.cl == nil then
		self.cl = {}
	end

	
	
	self.cl.unlocked = clientData.unlocked
	self.cl.requiredLogItem = clientData.requiredLogItem

	if self.cl.unlocked == true then
		self:client_setReaderState( KEYREADER_OPEN )
	else
		self:client_setReaderState( KEYREADER_LOCKED )
	end
end

function LogKeycardReader.client_onRefresh( self )
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

function LogKeycardReader.client_onInteract( self, player, state )
	if state then
		self.network:sendToServer( "sv_e_unlock" )
	end
end

function LogKeycardReader.sv_e_unlock( self )
	if self.saved.unlocked == false then
		if LogEntryManager.Sv_HasLog( self.saved.requiredLogItem ) then
			self.saved.unlocked = true
			self.storage:save( self.saved )

			local tileStorageKey = TileStorageManager.Sv_GetTileStorageKeyFromObject( self.interactable )
			TileStorageManager.Sv_SetValueInSubTable( tileStorageKey, KEY_LOCK_TABLE, self.saved.keyTag, true )
			QuestManager.Sv_SendEvent( QuestEvent.LogCardReaderUnlock, { keyTag = self.saved.keyTag } )

			self.network:setClientData( self.saved )
			self.network:sendToClients( "client_setReaderState", KEYREADER_OPEN )
			sm.effect.playEffect( "Elevator - Keycarduse", self.shape.worldPosition, nil, self.shape.worldRotation )
			self.interactable.active = true
		else
			self.network:sendToClients( "client_setReaderState", KEYREADER_ERROR )
		end
	end
end

function LogKeycardReader.server_onFixedUpdate( self )
	local publicData = self.interactable:getPublicData()
	if publicData.showError and self.saved.unlocked == false then
		self.network:sendToClients( "client_setReaderState", KEYREADER_ERROR )
		publicData.showError = false
	end
end

-- Client

function LogKeycardReader.client_onUpdate( self, deltaTime )

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

function LogKeycardReader.client_setReaderState( self, index )
	if index == KEYREADER_LOCKED then
		self.client_frameStart = 0
		self.client_frameEnd = 3
		self.client_looping = true
		self.client_frame = self.client_frameStart
		self.client_state = index
	elseif index == KEYREADER_ERROR then
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
