dofile( "$SURVIVAL_DATA/Scripts/game/managers/QuestManager.lua" )

KinematicInteractiveDoor = class( Kinematic )

local InteractionTime = 4
local InteractionDecay = 0.25

function KinematicInteractiveDoor.server_onCreate( self )
	Kinematic.server_onCreate( self )
	self.sv.tileStorageKey = TileStorageManager.Sv_GetTileStorageKeyFromObject( self.harvestable )
	if self.params.eventTrigger and self.params.eventTrigger ~= "" then
        KinematicManager.Sv_RegisterToEvent( self.harvestable, self.sv.tileStorageKey, self.params.eventTrigger )
	else
		print("KinematicInteractiveDoor: No eventTrigger specified")
    end
end

function KinematicInteractiveDoor.sv_n_activateKinematics( self )
	self.network:sendToClients( "cl_n_stopAllInteractions" )
    if self.params and self.params.eventTrigger and self.params.eventTrigger ~= "" then
		if g_kinematicManager then
			local registered = KinematicManager.Sv_GetRegistered( self.sv.tileStorageKey, self.params.eventTrigger )
			if registered then
				for _, kinematic in ipairs( registered ) do
					if sm.exists( kinematic ) then
						sm.event.sendToHarvestable( kinematic, "sv_e_activate" )
					end
				end
			end
			sm.effect.playEffect( "Growlab - Interactivedooropen", self.harvestable.worldPosition )
		end
	end

	if self.params and self.params.keyTag and self.params.keyTag ~= "" then
		if g_kinematicManager then
			TileStorageManager.Sv_SetValueInSubTable( self.sv.tileStorageKey, KEY_LOCK_TABLE, self.params.keyTag, true )
		end
	end
end

function KinematicInteractiveDoor.client_onCreate( self )
    Kinematic.client_onCreate( self )
    self.cl.interactionState = false
	self.cl.interactionElapsed = 0.0
    self.cl.interactionFinished = false

	self.cl.interactEffect = sm.effect.createEffect( "Topdepartment - InteractDoor", self.harvestable )
end

function KinematicInteractiveDoor.cl_n_stopAllInteractions( self )
	self.cl.interactionFinished = true
end

function KinematicInteractiveDoor.client_canInteract( self, character )
	if not self.cl.interactionFinished then
        sm.gui.setInteractionText( "", sm.gui.getKeyBinding( "Use", true ), "#{INTERACTION_USE}" )
		return not character:isTumbling()
	end
	return false
end

function KinematicInteractiveDoor.client_onInteract( self, user, state )
	if not self.cl.interactionFinished then
		self.cl.interactionState = state
	else
		self.cl.interactionState = false
	end
end

function KinematicInteractiveDoor.client_onUpdate( self, dt )
	if self.cl.interactionState and not self.cl.interactionFinished then
		sm.gui.setProgressFraction( self.cl.interactionElapsed / InteractionTime )	
		if not self.cl.interactEffect:isPlaying() then
			self.cl.interactEffect:start()
		end

		self.cl.interactionElapsed = self.cl.interactionElapsed + dt
		if self.cl.interactionElapsed >= InteractionTime then
			self.cl.interactionElapsed = 0.0
            self.cl.interactionFinished = true
            self.network:sendToServer( "sv_n_activateKinematics" )
		end
	elseif self.cl.interactionElapsed > 0.0 then
		if not self.cl.interactionFinished and self.cl.interactEffect:isPlaying() then
			self.cl.interactEffect:stop()
			sm.effect.playEffect( "Topdepartment - ErrorDoor", self.harvestable.worldPosition )
		end
		self.cl.interactionElapsed = math.max( self.cl.interactionElapsed - InteractionDecay * ( InteractionTime - self.cl.interactionElapsed ) * dt, 0 )
	else
		self.cl.interactionElapsed = 0.0
	end
end