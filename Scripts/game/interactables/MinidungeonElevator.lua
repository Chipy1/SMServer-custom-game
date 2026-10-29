dofile( "$SURVIVAL_DATA/Scripts/game/survival_shapes.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/survival_constants.lua" )
dofile( "$SURVIVAL_DATA/Scripts/util.lua" )

MinidungeonElevator = class()
MinidungeonElevator.maxParentCount = 255
MinidungeonElevator.maxChildCount = 255
MinidungeonElevator.connectionInput = sm.interactable.connectionType.logic
MinidungeonElevator.connectionOutput = sm.interactable.connectionType.logic + sm.interactable.connectionType.power
local PortalOffset = sm.vec3.new( 0, 1.875, 0 )
local PortalSize = sm.vec3.new( 1.75, 1.75, 3.0 ) - sm.vec3.new( 0.05, 0.05, 0.05 )

function MinidungeonElevator.server_onCreate( self )
	self.sv = {}

	local world = self.shape.body:getWorld()
	self.sv.inDungeon = world.publicData.type ~= "Overworld"
	self.sv.poiType = self.sv.inDungeon and world.publicData.poiType or GetPoiTypeAtPosition( world, self.shape.worldPosition )
	if self.sv.poiType == nil and not self.sv.inDungeon then
		sm.log.warning( "MinidungeonElevator could not resolve its tile poiType; the portal destination will be unavailable." )
	end
	self.sv.name = self.sv.poiType and ( "MiniDungeon_"..self.sv.poiType ) or nil

	self.sv.saved = self.storage:load() or {}
	if self.sv.saved.portal == nil then
		local position = self.shape.worldPosition + self.shape.worldRotation * PortalOffset
		if not self.sv.inDungeon then
			local portal = sm.portal.createPortal( PortalSize )
			portal:setOpeningA( position, self.shape.worldRotation )
			self.sv.saved.portal = portal
			self.storage:save( self.sv.saved )
		else
			local portal = self.sv.name and sm.portal.popWorldPortalHook( self.sv.name ) or nil
			if portal then
				portal:setOpeningB( position, self.shape.worldRotation )
				self.sv.saved.portal = portal
				self.storage:save( self.sv.saved )
			else
				sm.log.warning( "Minidungeon elevator exit was created but not connected to any entrance. This will happen if you teleport into this world without visiting the corresponding dungeon exterior tile." )
			end
		end
	end

	if self.sv.saved.portal then
		MinidungeonElevatorManager.Sv_RegisterElevator( self.interactable, self.sv.saved.portal )
	end

	self.sv.storageKey = TileStorageManager.Sv_GetTileStorageKeyFromObject( self.interactable )

	self.sv.lastActiveState = self.interactable:isActive()
	self.sv.prevPower = self.interactable.power

	if self.sv.saved.portal then
		self.network:sendToClients( "cl_n_startElevatorSounds", { contentsA = self.sv.saved.portal:getContentsA(), contentsB = self.sv.saved.portal:getContentsB() } )
	end
end

function MinidungeonElevator.server_onDestroy( self )
	MinidungeonElevatorManager.Sv_RemoveElevator( self.interactable )
end

function MinidungeonElevator.server_onFixedUpdate( self )
	-- Inputs
	local elevatorPanelButton, elvatorCallButton, keycardReader = self:sv_getInputs()
	assert( elevatorPanelButton, "Elevator missing elevator panel button" )
	assert( elvatorCallButton, "Elevator missing elevator call button" )
	
	-- Is elevator locked
	local isLocked = elvatorCallButton:getPublicData().unlocked == false





	-- Elevator button is pressed
	if elevatorPanelButton:isActive() and not isLocked then
		self:sv_panelButtonPressed()
		elevatorPanelButton:setActive( false )
	end
	

	local destination, ticksToDestination = MinidungeonElevatorManager.Sv_GetElevatorDestination( self.interactable )
	local elevatorHome = MinidungeonElevatorManager.Sv_GetElevatorHome( self.interactable )

	local callButtonData = elvatorCallButton:getPublicData()

	callButtonData.destination = destination
	callButtonData.ticksToDestination = ticksToDestination
	callButtonData.elevatorHome = elevatorHome

	-- Elevator call button is pressed
	if elvatorCallButton:isActive() then
		
		if not isLocked then -- No locked keycard reader and button is pressed
			self:sv_callButtonPressed()
		end
		elvatorCallButton:setActive( false )
	end

	if not self.sv.lastActiveState and self.interactable:isActive() then
		self.network:sendToClients( "cl_n_doorOpen", { contentsA = self.sv.saved.portal:getContentsA(), contentsB = self.sv.saved.portal:getContentsB() } )
	elseif self.sv.lastActiveState and not self.interactable:isActive() then
		self.network:sendToClients( "cl_n_doorClose", { contentsA = self.sv.saved.portal:getContentsA(), contentsB = self.sv.saved.portal:getContentsB() } )
	end
	self.sv.lastActiveState = self.interactable:isActive()

	if self.sv.prevPower == 0 and self.sv.saved.portal and self.interactable.power ~= 0 then
		self.network:sendToClients( "cl_n_startMovingSounds", { contentsA = self.sv.saved.portal:getContentsA(), contentsB = self.sv.saved.portal:getContentsB() } )
	elseif self.sv.prevPower ~= 0 and self.interactable.power == 0 then
		self.network:sendToClients( "cl_n_stopMovingSounds", { contentsA = self.sv.saved.portal:getContentsA(), contentsB = self.sv.saved.portal:getContentsB() } ) 
	end

	self.sv.prevPower = self.interactable.power
end

function MinidungeonElevator.server_onRefresh( self )
end

function MinidungeonElevator.sv_getInputs( self )
	local elevatorButton, elvatorCallButton, keycardReader
	for _, parent in ipairs( self.interactable:getParents() ) do
		local uid = parent.shape.shapeUuid
		if uid == obj_survivalobject_elevatorbutton then
			elevatorButton = parent
		elseif uid == obj_survivalobject_elevatorcallbutton then
			elvatorCallButton = parent
		elseif uid == obj_survivalobject_keylock_growlab then
			keycardReader = parent
			elvatorCallButton = parent -- Overworld version uses card reader as both call button and reader
		end
	end
	return elevatorButton, elvatorCallButton, keycardReader
end

function MinidungeonElevator.sv_callButtonPressed( self )
	print( "Minidungeon elevator call button was pressed" )
	MinidungeonElevatorManager.Sv_Call( self.interactable )
end

function MinidungeonElevator.sv_panelButtonPressed( self )
	if self.sv.saved.portal == nil then
		print( "Elevator has no destination yet" )
		return
	end

	if not ( self.sv.saved.portal:hasOpeningA() and self.sv.saved.portal:hasOpeningB() ) then
		self:sv_createElevatorDestination()
	end
	QuestManager.Sv_SendEvent( QuestEvent.GrowlabElevatorActivated, { poiType = self.sv.poiType } )
	MinidungeonElevatorManager.Sv_Go( self.interactable )
end

function MinidungeonElevator.sv_createElevatorDestination( self )
	assert( self.sv.saved.portal:hasOpeningA(), "Portal has no opening" )
	if not self.destinationCreated then
		MinidungeonElevatorManager.Sv_CreateMinidungeonDestination(
			{
				path = POI_TYPE_TO_GROWLAB_WORLD_PATH[self.sv.poiType],
				poiType = self.sv.poiType,
				name = self.sv.name,
				portal = self.sv.saved.portal
			} )

		self.destinationCreated = true
	end
end

function MinidungeonElevator.client_onCreate( self )
	self.cl = {}
	self.cl.moveEffect = sm.effect.createEffect( "ElevatorWall", self.interactable )
	self.cl.moveEffectOutside = sm.effect.createEffect( "Elevator - MoveOutside", self.interactable )
	self.cl.musicEffect = sm.effect.createEffect( "ElevatorMusic", self.interactable )
	self.cl.ambienceEffect = sm.effect.createEffect( "ElevatorAmbiance", self.interactable )
	if self.interactable:isActive() then
		self:startElevatorSounds()
	end

	self.playerId = {}
	local position = self.shape.worldPosition + self.shape.worldRotation * PortalOffset

	self.cl.insideArea = sm.areaTrigger.createBox( PortalSize, position, self.shape.worldRotation, sm.areaTrigger.filter.character )
    self.cl.insideArea:bindOnEnter( "cl_t_onEnter", self )
	self.cl.insideArea:bindOnExit( "cl_t_onExit", self )
end

function MinidungeonElevator.client_onDestroy( self )
	if self.cl.insideArea then
		sm.areaTrigger.destroy( self.cl.insideArea )
	end
end

function MinidungeonElevator.cl_n_doorOpen( self, params )
		
	local inside = ( params.contentsA and TriggerContentsContainsLocalPlayer( params.contentsA ) ) or ( params.contentsB and TriggerContentsContainsLocalPlayer( params.contentsB ) )
	if inside then
		AmbienceManager.Cl_SetPauseWorldAmbience( false )
	end

	self:stopMovingSounds()
	self:startElevatorSounds()

	sm.effect.playHostedEffect( "Elevator - Opendoor", self.interactable )
end

function MinidungeonElevator.startElevatorSounds( self )
	if not self.cl.musicEffect:isPlaying() or self.cl.musicEffect:isBreakSustaining() then
		self.cl.musicEffect:start()
	end
	if not self.cl.ambienceEffect:isPlaying() or self.cl.ambienceEffect:isBreakSustaining() then
		self.cl.ambienceEffect:start()
	end
end

function MinidungeonElevator.stopMovingSounds( self )
	if not self.cl.moveEffect:isBreakSustaining() then
		self.cl.moveEffect:stopBreakSustain()
	end	

	if not self.cl.moveEffectOutside:isBreakSustaining() then
		self.cl.moveEffectOutside:stopBreakSustain()
	end	
end

function MinidungeonElevator.stopElevatorSounds( self )
	if self.cl.musicEffect:isPlaying() or not self.cl.musicEffect:isBreakSustaining() then
		self.cl.musicEffect:stopImmediate()
	end
	if self.cl.ambienceEffect:isPlaying() then
		self.cl.ambienceEffect:stop();
	end
end

function MinidungeonElevator.cl_n_startElevatorSounds( self, params )
	if ( params.contentsA and TriggerContentsContainsLocalPlayer( params.contentsA ) ) or ( params.contentsB and TriggerContentsContainsLocalPlayer( params.contentsB ) ) then
		self:startElevatorSounds()
	end
end

function MinidungeonElevator.cl_n_doorClose( self, params )
	sm.effect.playHostedEffect( "Elevator - Closedoor", self.interactable )

	local inside = ( params.contentsA and TriggerContentsContainsLocalPlayer( params.contentsA ) ) or ( params.contentsB and TriggerContentsContainsLocalPlayer( params.contentsB ) )
	if inside then
		if g_ambienceManager then
			g_ambienceManager:cl_setPauseWorldAmbience( true )
		end
	else
		self:stopElevatorSounds()
	end
end

function MinidungeonElevator.cl_n_startMovingSounds( self, params )
	if ( params.contentsA and TriggerContentsContainsLocalPlayer( params.contentsA ) ) or ( params.contentsB and TriggerContentsContainsLocalPlayer( params.contentsB ) ) then
		if self.cl.moveEffect:isBreakSustaining() then
			self.cl.moveEffect:start()
		end
	else
		if self.cl.moveEffectOutside:isBreakSustaining() then
			self.cl.moveEffectOutside:start()
		end
	end
end

function MinidungeonElevator.cl_n_stopMovingSounds( self, params )
	local inside = ( params.contentsA and TriggerContentsContainsLocalPlayer( params.contentsA ) ) or ( params.contentsB and TriggerContentsContainsLocalPlayer( params.contentsB ) )
	if not inside then
		AmbienceManager.Cl_SetPauseWorldAmbience( false )
	end
	self:stopElevatorSounds()
end

function MinidungeonElevator.cl_t_onEnter( self, trigger, results )
	if not TriggerResultContainsLocalPlayer( results ) then
		return
	end

	if not self.interactable:isActive() then
		self:startElevatorSounds()
		if self.interactable.power ~= 0 then
			if not self.cl.moveEffect:isPlaying() or self.cl.moveEffect:isBreakSustaining() then
				self.cl.moveEffect:start()
			end
			if self.cl.moveEffectOutside:isPlaying() or not self.cl.moveEffectOutside:isBreakSustaining() then
				self.cl.moveEffectOutside:stopImmediate()
			end
		end
	end

	self.playerId = sm.localPlayer.getPlayer().character.id
	self:startElevatorSounds()
end

function MinidungeonElevator.cl_t_onExit( self, trigger, results )
	if results == nil then return end
	for _,result in ipairs( results ) do
		if result.id == self.playerId then
			self.playerId = nil
			AmbienceManager.Cl_SetPauseWorldAmbience( false )

			if not self.interactable:isActive() then
				self:stopElevatorSounds()

				if self.interactable.power ~= 0 then
					if self.cl.moveEffect:isPlaying() or not self.cl.moveEffect:isBreakSustaining() then
						self.cl.moveEffect:stopImmediate()
					end
					if not self.cl.moveEffectOutside:isPlaying() or self.cl.moveEffectOutside:isBreakSustaining() then
						self.cl.moveEffectOutside:start()
					end
				end
			end
		end
	end
end