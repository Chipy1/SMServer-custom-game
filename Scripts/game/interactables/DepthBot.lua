dofile( "$SURVIVAL_DATA/Scripts/util.lua" )
DepthBot = class( nil )

-- UV frame grid: 17 columns x 9 rows
local UvColumns = 17

-- Selection-state marker hosted on the shape; indicates the selected floor on the screen.
local DepthscreenMarkerEffect = "Elevator - DepthscreenMarker"

-- Locked marker; shown in place of the selection marker once a target floor is confirmed and
-- the elevator sequence starts.
local DepthscreenMarkerLockedEffect = "Elevator - DepthscreenMarker_Locked"

local FloorDisplayChannel = 1
local MarkerLockChannel = 2

function DepthBot.server_onCreate( self )
    self.sv = {}
	self.sv.saved = self.storage:load()
	if not self.sv.saved then
		self.sv.saved = {}
		self.sv.saved.connectionTag = UndergroundElevatorManager.Sv_FindUndergroundConnectionTag( self.tags )
		self.storage:save( self.sv.saved )

		-- publish self so the elevator can find and update the display
		local storageKey = TileStorageManager.Sv_GetTileStorageKeyFromObject( self.interactable )
		local tileData = TileStorageManager.Sv_GetValueInSubTable( storageKey, UNDERGROUND_ELEVATOR_TABLE, self.sv.saved.connectionTag ) or {}
		tileData.depthbots = tileData.depthbots or {}
		tileData.depthbots[#tileData.depthbots + 1] = self.interactable
		TileStorageManager.Sv_SetValueInSubTable( storageKey, UNDERGROUND_ELEVATOR_TABLE, self.sv.saved.connectionTag, tileData )
	end
end

function DepthBot.client_onCreate( self )
	self.cl = {}
	self.cl.elevatorMoving = false
	self.cl.selectedFloor = 1
	self.cl.numLocked = 0
	self.cl.scrapyardUnlocked = false
	if self.data then
		if self.data.effectName then
			self.cl.textEffect = sm.effect.createEffect( self.data.effectName, self.interactable )
		end
		if self.cl.textEffect then
			if self.data.color then
				self.cl.textEffect:setParameter( "Color", sm.color.new( self.data.color.r, self.data.color.g, self.data.color.b, self.data.color.a ) )
			end
			if self.data.asg then
				self.cl.textEffect:setParameter( "ASG", sm.vec3.new( self.data.asg.a, self.data.asg.s, self.data.asg.g ) )
			end
			self.cl.textEffect:setOffsetPosition ( sm.vec3.new( 0.0, -0.8, 0.70 ) )
			self.cl.textEffect:setOffsetRotation( sm.quat.angleAxis( math.rad( 8 ), sm.vec3.new( 1, 0, 0 ) ) )
			self.cl.textEffect:setScale( sm.vec3.new( 8, 8, 8 ) )
			self.cl.textEffect:setParameter( "anchor", "CENTER" )
			self.cl.textEffect:start()
		end
	end

	-- Selection-state marker on the screen, hosted on the shape.
	self.cl.markerLocked = false
	self.cl.markerEffect = sm.effect.createEffect( DepthscreenMarkerEffect, self.interactable )
	self.cl.markerLockedEffect = sm.effect.createEffect( DepthscreenMarkerLockedEffect, self.interactable )
	self:cl_updateScreenMarker()
	self.cl.markerEffect:start()

	-- Submesh visibility: idle shown, direction submeshes hidden
	self.interactable:setSubMeshVisible( "display_idle", true )
	self.interactable:setSubMeshVisible( "display_up", false )
	self.interactable:setSubMeshVisible( "display_down", false )

	-- The m_locked submesh covers the scrapyard level light until the player has unlocked it.
	self:cl_updateLockedSubMesh()

	-- Set initial UV frame
	self:cl_updateUvFrame()
end

function DepthBot.client_onClientDataUpdate( self, data, channel )
	if channel == MarkerLockChannel then
		-- The marker stays locked while the elevator sequence is running. It is unlocked again once
		-- the elevator arrives AND the doors finish opening, i.e. when a floor can be selected once more.
		if data.markerLocked ~= nil then
			self:cl_setMarkerLocked( data.markerLocked )
		end
		return
	end

	if data.displayDepth ~= nil and self.cl.textEffect then
		self.cl.textEffect:setParameter( "TextContent", tostring( data.displayDepth ) )
	end
	if data.selectedFloor ~= nil then
		self.cl.selectedFloor = data.selectedFloor
		self:cl_updateScreenMarker()
	end
	if data.numLocked ~= nil then
		self.cl.numLocked = data.numLocked
	end
	if data.scrapyardUnlocked ~= nil then
		self.cl.scrapyardUnlocked = data.scrapyardUnlocked
		self:cl_updateLockedSubMesh()
	end
	if not self.cl.elevatorMoving then
		self:cl_updateUvFrame()
	end
end

function DepthBot.cl_updateScreenMarker( self )
	if not self.cl.markerEffect then
		return
	end

	-- Marker placement along the screen (tweak these).
	local baseY = 3.4		-- offset for the first selectable floor, metres
	local perFloorY = -0.7	-- offset added per floor above the first, metres
	
	local floorOffset = self.cl.selectedFloor - 1
	local posY = baseY + perFloorY * floorOffset
	local offsetPosition = sm.vec3.new( 0, posY, 0 )

	self.cl.markerEffect:stopImmediate()
	if not self.cl.markerLocked then
		self.cl.markerEffect:start() -- restart for some flair.
	end

	self.cl.markerEffect:setOffsetPosition( offsetPosition )
	if self.cl.markerLockedEffect then
		self.cl.markerLockedEffect:setOffsetPosition( offsetPosition )
	end
end

function DepthBot.cl_updateLockedSubMesh( self )
	local locked = not self.cl.scrapyardUnlocked
	self.interactable:setSubMeshVisible( "m_locked", locked )
end

function DepthBot.client_onDestroy( self )
	if self.cl.textEffect then
		self.cl.textEffect:destroy()
	end
	if self.cl.markerEffect then
		self.cl.markerEffect:destroy()
	end
	if self.cl.markerLockedEffect then
		self.cl.markerLockedEffect:destroy()
	end
end

function DepthBot.cl_updateUvFrame( self )
	local selectedFloor = self.cl.selectedFloor - 1
	local numLocked = self.cl.numLocked
	local column = selectedFloor
	local row = math.max( math.min( 8 - numLocked, 8 ), 0 )
	row = row - selectedFloor
	local frameIndex = row * UvColumns + column
	self.interactable:setUvFrameIndex( frameIndex )
end

function DepthBot.sv_e_updateFloorDisplay( self, data )
	self.network:setClientData( data, FloorDisplayChannel )
end

function DepthBot.sv_e_setMarkerLocked( self, data )
	self.network:setClientData( { markerLocked = data.markerLocked == true }, MarkerLockChannel )
end

function DepthBot.sv_e_goDown( self )
	self.network:sendToClients( "cl_n_goDown" )
end

function DepthBot.cl_n_goDown( self )
	self.cl.elevatorMoving = true
	self.interactable:setSubMeshVisible( "display_idle", false )
	self.interactable:setSubMeshVisible( "display_down", true )
	self.interactable:setSubMeshVisible( "display_up", false )
end

function DepthBot.sv_e_goUp( self )
	self.network:sendToClients( "cl_n_goUp" )
end

function DepthBot.cl_n_goUp( self )
	self.cl.elevatorMoving = true
	self.interactable:setSubMeshVisible( "display_idle", false )
	self.interactable:setSubMeshVisible( "display_down", false )
	self.interactable:setSubMeshVisible( "display_up", true )
end

function DepthBot.sv_e_arrived( self )
	self.network:sendToClients( "cl_n_arrived" )
end

function DepthBot.cl_n_arrived( self )
	self.cl.elevatorMoving = false
	self.interactable:setSubMeshVisible( "display_idle", true )
	self.interactable:setSubMeshVisible( "display_up", false )
	self.interactable:setSubMeshVisible( "display_down", false )
	self:cl_updateUvFrame()
end

function DepthBot.cl_setMarkerLocked( self, locked )
	self.cl.markerLocked = locked
	if locked then
		if self.cl.markerEffect and self.cl.markerEffect:isPlaying() then
			self.cl.markerEffect:stopImmediate()
		end
		if self.cl.markerLockedEffect and not self.cl.markerLockedEffect:isPlaying() then
			self.cl.markerLockedEffect:start()
		end
	else
		if self.cl.markerLockedEffect and self.cl.markerLockedEffect:isPlaying() then
			self.cl.markerLockedEffect:stopImmediate()
		end
		if self.cl.markerEffect and not self.cl.markerEffect:isPlaying() then
			self.cl.markerEffect:start()
		end
	end
end


