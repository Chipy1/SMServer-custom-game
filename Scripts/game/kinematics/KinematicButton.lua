dofile( "$SURVIVAL_DATA/Scripts/game/kinematics/KinematicBase.lua" )

KinematicButton = class( KinematicBase )

-- Server

function KinematicButton.server_onCreate( self )
	self.sv = {}
	self.sv.unlocked = true
	if g_tileStorageManager then
		self.sv.tileStorageKey = TileStorageManager.Sv_GetTileStorageKeyFromObject( self.harvestable )

		if self.params and self.params.lockTag and self.params.lockTag ~= "" then
			self.sv.unlocked = TileStorageManager.Sv_GetValueInSubTable( self.sv.tileStorageKey, KEY_LOCK_TABLE, self.params.lockTag ) == true
		end
	end
	self.sv.kinematicMoving = false
	self.network:setClientData( { unlocked = self.sv.unlocked }, 2 )
end

function KinematicButton.server_onFixedUpdate( self, timeStep )
	if self.sv == nil then
		return
	end
	if not self.sv.unlocked then
		if g_tileStorageManager then
			if self.params and self.params.lockTag and self.params.lockTag ~= "" then
				local keyLock = TileStorageManager.Sv_GetValueInSubTable( self.sv.tileStorageKey, KEY_LOCK_TABLE, self.params.lockTag )
				if keyLock then
					self.sv.unlocked = keyLock
					self.network:setClientData( { unlocked = self.sv.unlocked }, 2 )
				end
			end
		end
	end

	local isDirty = false
	if self.params and self.params.eventTrigger and self.params.eventTrigger ~= "" then
		if g_kinematicManager then
			local registered = KinematicManager.Sv_GetRegistered( self.sv.tileStorageKey, self.params.eventTrigger )
			if registered  then
				local anyIsMoving = false
				for _, kinematic in ipairs( registered ) do
					if sm.exists( kinematic ) then
						if kinematic.publicData then
							if kinematic.publicData.moving then
								anyIsMoving = true
								break
							end
						end
					end
				end
				if anyIsMoving ~= self.sv.kinematicMoving then
					isDirty = true
					self.sv.kinematicMoving = anyIsMoving
				end
			end
		end
	end
	if isDirty then
		self.network:setClientData( { moving =  self.sv.kinematicMoving }, 1 )
	end
end

function KinematicButton.server_onProjectile( self, hitPos, hitTime, hitVelocity, _, attacker )
	if type( attacker ) == "Player" and not self.sv.kinematicMoving then
		self:sv_n_activate()
	end
end

function KinematicButton.sv_n_activate( self )
	if not self.sv.unlocked then
		return
	end

	-- Activation
	if self.params and self.params.eventTrigger and self.params.eventTrigger ~= "" then
		if g_kinematicManager then
			sm.effect.playEffect( "Elevator Button", self.harvestable.worldPosition )
			KinematicManager.Sv_Activate( self.sv.tileStorageKey, self.params.eventTrigger )
		end
	end

	-- Key
	if self.params and self.params.keyTag and self.params.keyTag ~= "" then
		if g_tileStorageManager then
			TileStorageManager.Sv_SetValueInSubTable( self.sv.tileStorageKey, KEY_LOCK_TABLE, self.params.keyTag, true )
		end
	end
end

-- Client
function KinematicButton.client_onCreate( self )
	KinematicBase.client_onCreate( self )
	self.cl = {}
	self.cl.unlocked = false
	self.cl.kinematicMoving = false
end

function KinematicButton.client_onClientDataUpdate( self, clientData, channel )
	if channel == 2 then
		self.cl.unlocked = clientData.unlocked
	elseif channel == 1 then
		self.cl.kinematicMoving = clientData.moving
		if not self.cl.kinematicMoving then
			self.harvestable:setUvFrameIndex( 1 )
		end
	end
end

function KinematicButton.client_canInteract( self )
	if self.cl.unlocked and not self.cl.kinematicMoving then
		sm.gui.setInteractionText( "", sm.gui.getKeyBinding( "Use", true ), "#{INTERACTION_USE}" )
		return true
	end
	sm.gui.setInteractionText( "#{LOCKED}" )
	return false
end

function KinematicButton.client_onInteract( self, character, state )
	if self.cl.unlocked then
		if state == true then
			self.network:sendToServer( "sv_n_activate" )
		end
	end
end