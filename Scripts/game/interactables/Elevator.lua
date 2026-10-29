dofile( "$SURVIVAL_DATA/Scripts/game/survival_shapes.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/survival_constants.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/managers/WarehouseManager.lua" )

Elevator = class()
Elevator.maxParentCount = 255
Elevator.maxChildCount = 255
Elevator.connectionInput = sm.interactable.connectionType.logic
Elevator.connectionOutput = sm.interactable.connectionType.logic + sm.interactable.connectionType.power

Elevator.antiTheftEffectScale = sm.vec3.new( 0.25, 0.25, 0.25 )
Elevator.antiTheftEffectOffsetPosition = sm.vec3.new( 0.0, 0.0, -0.5 )

local ELEVATOR_PORTAL_OFFSET = sm.vec3.new( 0, 1.875, 0 )

Elevator.antiTheftAreatriggerBounds = sm.vec3.new( 4, 4, 0.005 )
Elevator.antiTheftAreatriggerOffsetPosition = sm.vec3.new( 0, 1, 3.0)

Elevator.BarrierFloorColorParam = sm.color.new( 0.0, 0.4, 1.0, 1.0 )
Elevator.BarrierFloorFadeTime = 0.5
Elevator.BarrierFloorFadeDelay = 1.5

Elevator.MaxAntiTheftInteractCount = 16

local BarrierFloorRendEffects = {
	"Warehouse - Barrierfloor_nn_rend",
	"Warehouse - Barrierfloor_nnne_rend",
	"Warehouse - Barrierfloor_wwne_rend",
	"Warehouse - Barrierfloor_stragglerhideout_rend"
}

local BarrierFloorEffects = {
	"Warehouse - Barrierfloor_nn",
	"Warehouse - Barrierfloor_nnne",
	"Warehouse - Barrierfloor_wwne",
	"Warehouse - Barrierfloor_stragglerhideout"
}

function Elevator.cl_getAvailableEffect(self)
	for _, effect in ipairs( self.cl.antiTheftEffectInteract ) do
		if effect:isDone() then
			return effect
		end
	end

	if #self.cl.antiTheftEffectInteract < Elevator.MaxAntiTheftInteractCount then
		self.cl.antiTheftEffectInteract[#self.cl.antiTheftEffectInteract + 1] = sm.effect.createEffect( "Warehouse - Antitheftbarrier Interact" )
		return self.cl.antiTheftEffectInteract[#self.cl.antiTheftEffectInteract]

	elseif  #self.cl.antiTheftEffectInteract >= Elevator.MaxAntiTheftInteractCount then
		--if we run out of effects to use, reuse last effect
		if Elevator.MaxAntiTheftInteractCount-1 < #self.cl.antiTheftEffectInteract and self.cl.antiTheftEffectInteract[Elevator.MaxAntiTheftInteractCount -1] then
			return self.cl.antiTheftEffectInteract[Elevator.MaxAntiTheftInteractCount -1]
		end
	end

	return nil
end


function Elevator.cl_n_onAntiTheftEnter( self, collisions )
	if self.cl.antiTheftActivated then
		for _, collision in ipairs( collisions ) do
			if collision.normal:length2() > FLT_EPSILON * FLT_EPSILON then
				local selectedEffectInstance = self:cl_getAvailableEffect()
				
				if selectedEffectInstance ~= nil then
					selectedEffectInstance:setPosition( collision.worldPoint )
					local rot = sm.vec3.getRotation( sm.vec3.new( 0, 0, 1 ), -collision.normal )
					selectedEffectInstance:setRotation( rot )
					selectedEffectInstance:start()
				end
			end
		end
	end
end

function Elevator.cl_activateAntiTheftEffect( self, params )
	if self.cl.antiTheftEffect == nil and self.cl.antiTheftEffectInteract == nil then
		self.cl.antiTheftEffectInteract = {}
		self.cl.antiTheftEffect = sm.effect.createEffect( "Warehouse - AntitheftElevatorEffect", self.interactable )
		self.cl.antiTheftEffect:setScale( Elevator.antiTheftEffectScale )
		self.cl.antiTheftEffect:setOffsetPosition( Elevator.antiTheftEffectOffsetPosition )
		self.cl.antiTheftEffect:start()

	end
end

function Elevator.cl_disableAntiTheftEffect( self, params )
	if self.cl.antiTheftEffect ~= nil then
		self.cl.antiTheftEffect:stop()
		if self.cl.barrierFloorRenderableEffect then
			self.cl.barrierFloorRenderableEffect:stop()
		end
		if self.cl.barrierFloorEffect then
			self.cl.barrierFloorEffect:stop()
		end
	end
end

function Elevator.server_antiTheftOnEnter( self, trigger, results )
	local collisions = {}
	for _, result in ipairs( results ) do
		if sm.exists( result ) then
			if type( result ) == "Character" then
				local normalizedCharacterVelocity = result.velocity:safeNormalize(sm.vec3.new(0, 1, 0))
				local characterPos = result:getWorldPosition()
				local from = characterPos
				local to = characterPos + normalizedCharacterVelocity
				local success, hitResult = sm.physics.raycastTarget( from, to, self.sv.antiTheftAreatrigger )
				if success then
					collisions[#collisions +1] = { worldPoint = hitResult.pointWorld, normal = hitResult.normalWorld  }
				end
			end
		end
	end
	self.network:sendToClients( "cl_n_onAntiTheftEnter", collisions )
end

function Elevator.client_onCreate( self )
	self.cl = {}
	self.cl.moveEffect = sm.effect.createEffect( "ElevatorWall", self.interactable )
	self.cl.moveEffectOutside = sm.effect.createEffect( "Elevator - MoveOutside", self.interactable )
	self.cl.musicEffect = sm.effect.createEffect( "ElevatorMusic", self.interactable )
	self.cl.ambienceEffect = sm.effect.createEffect( "ElevatorAmbiance", self.interactable )
	self.playerId = {}

	if self.interactable:isActive() then
		self:startElevatorSounds()
	end

	self.cl.antiTheftActivated = false
	
	self.cl.barrierFloorEffect = nil
	self.cl.barrierFloorRenderableEffect = nil
	self.cl.exitElevatorEffectColor = Elevator.BarrierFloorColorParam

	local world = self.shape.body:getWorld()
	if world and world:isIndoor() then
		local elevatorPosition = self.shape:getWorldPosition()
		local effectNodes = sm.cell.getNodesByTag( 0, 0, "UNMANAGED_EFFECT" )
		for _, node in ipairs( effectNodes ) do
			if node.params.effect and node.params.effect then
				if (node.position - elevatorPosition):length2() <= CELL_SIZE*CELL_SIZE then
					if isAnyOf( node.params.effect.name, BarrierFloorEffects ) then
						self.cl.barrierFloorEffect = sm.effect.createEffect( node.params.effect.name )
						self.cl.barrierFloorEffect:setPosition( node.position )
						self.cl.barrierFloorEffect:setRotation( node.rotation )
						self.cl.barrierFloorEffect:setScale( node.scale )
					end
					if isAnyOf( node.params.effect.name, BarrierFloorRendEffects ) then
						self.cl.barrierFloorRenderableEffect = sm.effect.createEffect( node.params.effect.name )
						self.cl.barrierFloorRenderableEffect:setPosition( node.position )
						self.cl.barrierFloorRenderableEffect:setRotation( node.rotation )
						self.cl.barrierFloorRenderableEffect:setScale( node.scale )
						self.cl.barrierFloorRenderableEffect:setParameter( "maxColor", self.cl.exitElevatorEffectColor )
					end
				end
			end
		end

		local areaTriggers = sm.cell.getNodesByTag( 0, 0, "VOLUME" )
		for _, node in ipairs( areaTriggers ) do
			if (node.position - elevatorPosition):length2() <= 64*64 then
				if node.params and node.params.name == "ElevatorInside" then
					self.cl.elevatorInsideArea = sm.areaTrigger.createBox( node.scale/2, node.position, node.rotation, sm.areaTrigger.filter.character )
					self.cl.elevatorInsideArea:setCharacterDetection( true )
					self.cl.elevatorInsideArea:bindOnExit( "cl_trigger_exitElevator" )
					self.cl.elevatorInsideArea:bindOnEnter( "cl_trigger_enterElevator" )
					break
				end
			end
		end
	end
	self.cl.exitElevatorFadeTime = 0

	local position = self.shape.worldPosition + self.shape.worldRotation * ELEVATOR_PORTAL_OFFSET
	local size = sm.vec3.new( 1.75, 1.75, 3.0 ) - sm.vec3.new( 0.05, 0.05, 0.05 )

	self.cl.insideArea = sm.areaTrigger.createBox( size, position, self.shape.worldRotation, sm.areaTrigger.filter.character )
    self.cl.insideArea:bindOnEnter( "cl_t_onEnter", self )
	self.cl.insideArea:bindOnExit( "cl_t_onExit", self )
end

function Elevator.cl_trigger_enterElevator( self, trigger, result )
	if TriggerResultContainsLocalPlayer( result ) then
		sm.effect.playHostedEffect( "Warehouse - BarrierExit", self.interactable )
		WarehouseManager.Cl_EnterElevatorFromWarehouse( sm.localPlayer.getWorld() )
	end
end

function Elevator.cl_trigger_exitElevator( self, trigger, result )
	if TriggerResultContainsLocalPlayer( result ) then
		if self.cl.exitElevatorFadeTime == 0 then
			sm.effect.playHostedEffect( "Warehouse - BarrierEnter", self.interactable )
			if self.cl.barrierFloorRenderableEffect and self.cl.barrierFloorRenderableEffect:isPlaying() then
				self.cl.exitElevatorFadeTime = Elevator.BarrierFloorFadeTime + Elevator.BarrierFloorFadeDelay
				if self.cl.barrierFloorEffect then
					self.cl.barrierFloorEffect:start()
				end
			end
		end
		WarehouseManager.Cl_EnterWarehouseFromElevator( sm.localPlayer.getWorld() )
	end
end

function Elevator.client_onClientDataUpdate( self, clientData )
	if not self.cl then
		self.cl = {}
	end
	if clientData.antiTheftActivated then
		self:cl_activateAntiTheftEffect()
	else
		self:cl_disableAntiTheftEffect()
	end
	self.cl.antiTheftActivated = clientData.antiTheftActivated
end

function Elevator.client_onDestroy( self )
	if self.cl.antiTheftEffectInteract ~= nil then
		for _, effect in ipairs( self.cl.antiTheftEffectInteract ) do
			effect:destroy()
		end
		self.cl.antiTheftEffectInteract = nil
	end

	if self.cl.barrierFloorEffect then
		self.cl.barrierFloorEffect:destroy()
	end
	if self.cl.barrierFloorRenderableEffect then
		self.cl.barrierFloorRenderableEffect:destroy()
	end
	if self.cl.elevatorInsideArea then
		sm.areaTrigger.destroy( self.cl.elevatorInsideArea )
	end
	
	if self.cl.insideArea then
		sm.areaTrigger.destroy( self.cl.insideArea )
	end
end

function Elevator.server_onCreate( self )
	self.saved = self.storage:load()
	self.sv = {}
	
	assert( ( self.saved == nil ) ~= ( self.params == nil ), "Warehouse elevator created without params." )

	if self.saved == nil then
		self.saved = self.params
		self.saved.isUnlocked = false
		self:findOrCreatePortal()
		self.storage:save( self.saved )
	else
		if self.saved.isUnlocked == nil then
			self.saved.isUnlocked = false
			self.storage:save( self.saved )
		end
		if self.saved.portal then
			ElevatorManager.Sv_RegisterElevator( self.interactable, self.saved.portal )
		end
	end

	self.sv.lastActiveState = self.interactable:isActive()
	self.sv.prevPower = self.interactable.power

	self.sv.antiTheftActivated = false
	if self.saved.level then
		--indoor
		if self.saved.name == "ELEVATOR_ENTRANCE" or self.saved.name == "ELEVATOR_DOWN" or self.saved.name == "ELEVATOR_UP" or self.saved.name == "ELEVATOR_EXIT" then
			self.sv.antiTheftActivated = true
			local rotation = sm.quat.identity()
			self.sv.antiTheftAreatrigger = sm.areaTrigger.createAttachedBox( self.interactable, Elevator.antiTheftAreatriggerBounds, Elevator.antiTheftAreatriggerOffsetPosition, rotation, sm.areaTrigger.filter.character )
			self.sv.antiTheftAreatrigger:bindOnEnter( "server_antiTheftOnEnter" )
		end
	end

	if self.saved.portal then
		self.network:sendToClients( "cl_n_startElevatorSounds", { contentsA = self.saved.portal:getContentsA(), contentsB = self.saved.portal:getContentsB() } )
	end

	self.network:setClientData( { antiTheftActivated = self.sv.antiTheftActivated } )
end

function Elevator.server_onDestroy( self )
	if self.sv.antiTheftAreatrigger then
		sm.areaTrigger.destroy( self.sv.antiTheftAreatrigger )
		self.sv.antiTheftAreatrigger = nil
	end
	ElevatorManager.Sv_RemoveElevator( self.interactable )
end


function Elevator.server_onRefresh( self )
end

function Elevator.sv_getInputs( self )
	local elevatorButton, elvatorCallButton, keycardReader
	for _, parent in ipairs( self.interactable:getParents() ) do
		local uid = parent.shape.shapeUuid
		if uid == obj_survivalobject_elevatorbutton then
			elevatorButton = parent
		elseif uid == obj_survivalobject_elevatorcallbutton then
			elvatorCallButton = parent
		elseif uid == obj_survivalobject_cardreader then
			keycardReader = parent
		end
	end
	return elevatorButton, elvatorCallButton, keycardReader
end

function Elevator.server_onFixedUpdate( self )
	-- Roof exit hookup
	if self.saved.portal == nil and self.saved.level == nil and self.saved.name == "ELEVATOR_EXIT" then
		-- No world hook was found when the elevator was created. Keep looking for the exit elevator...
		self.saved.portal = self:findPortal( self.saved.name.." "..self.saved.x..","..self.saved.y )
		if self.saved.portal then
			self.storage:save( self.saved )
		end
	end

	-- Inputs
	local elevatorPanelButton, elvatorCallButton, keycardReader = self:sv_getInputs()
	assert( elevatorPanelButton, "Elevator missing elevator panel button" )
	assert( elvatorCallButton, "Elevator missing elevator call button" )

	if not self.sv.lastActiveState and self.interactable:isActive() then
		sm.event.sendToInteractable( elevatorPanelButton, "sv_e_shutOff" )
		self.network:sendToClients( "cl_n_doorOpen", { contentsA = self.saved.portal:getContentsA(), contentsB = self.saved.portal:getContentsB() } )
	elseif self.sv.lastActiveState and not self.interactable:isActive() then
		self.network:sendToClients( "cl_n_doorClose", { contentsA = self.saved.portal:getContentsA(), contentsB = self.saved.portal:getContentsB() } )
	end
	self.sv.lastActiveState = self.interactable:isActive()

	if self.sv.prevPower == 0 and self.saved.portal and self.interactable.power ~= 0 then
		self.network:sendToClients( "cl_n_startMovingSounds", { contentsA = self.saved.portal:getContentsA(), contentsB = self.saved.portal:getContentsB() } )
	elseif self.sv.prevPower ~= 0 and self.interactable.power == 0 then
		self.network:sendToClients( "cl_n_stopMovingSounds", { contentsA = self.saved.portal:getContentsA(), contentsB = self.saved.portal:getContentsB() } ) 
	end

	self.sv.prevPower = self.interactable.power

	-- Is elevator locked
	local isLocked = keycardReader and not keycardReader:isActive()
	local forceCall = false
	if self.saved.isUnlocked ~= nil and not self.saved.isUnlocked then
		if not isLocked then
			forceCall = true
			self.saved.isUnlocked = true
			self.storage:save( self.saved )
		end
	end
	if not self.saved.isUnlocked and self.interactable:isActive() then
		self.saved.isUnlocked = true
		if keycardReader then
			sm.event.sendToInteractable( keycardReader, "sv_e_forceUnlock" )
		end
	end

	if not isLocked then

		local destination, ticksToDestination = ElevatorManager.Sv_GetElevatorDestination( self.interactable )
		assert( destination )
		assert( ticksToDestination )
		local elevatorHome = ElevatorManager.Sv_GetElevatorHome( self.interactable )
		assert( elevatorHome )

		local callbuttonData = elvatorCallButton:getPublicData()

		callbuttonData.destination = destination
		callbuttonData.ticksToDestination = ticksToDestination
		callbuttonData.elevatorHome = elevatorHome
	end

	-- Elevator button is pressed
	if elevatorPanelButton:isActive() then
		self:sv_panelButtonPressed()
		elevatorPanelButton:setActive( false )
	end

	-- Elevator call button is pressed
	if elvatorCallButton:isActive() or ( forceCall and keycardReader ) then

		if not isLocked then -- No locked keycard reader and button is pressed
			self:sv_callButtonPressed()
		elseif keycardReader then
			keycardReader:getPublicData().showError = true
		end
		elvatorCallButton:setActive( false )
	end

	local antiTheftWasActivated = self.sv.antiTheftActivated
	local warehouse = WarehouseManager.Sv_GetWarehouseFromIndex( self.saved.warehouseIndex )
	if warehouse then
		self.sv.antiTheftActivated = warehouse.countdownEvent == nil
	end
	if self.sv.antiTheftActivated ~= antiTheftWasActivated then
		self.network:setClientData( { antiTheftActivated = self.sv.antiTheftActivated } )
	end
end

function Elevator.client_onUpdate( self, deltaTime )	
	if self.cl.exitElevatorFadeTime > 0 then
		self.cl.exitElevatorFadeTime = self.cl.exitElevatorFadeTime - deltaTime
		self.cl.exitElevatorFadeTime = max( 0, self.cl.exitElevatorFadeTime )

		if self.cl.barrierFloorRenderableEffect then
			if self.cl.exitElevatorFadeTime == 0 then
				self.cl.barrierFloorRenderableEffect:stop()
			else
				local norm = min( 1, inverseLerp( 0, Elevator.BarrierFloorFadeTime, self.cl.exitElevatorFadeTime ) )
				self.cl.exitElevatorEffectColor.a = norm
				self.cl.barrierFloorRenderableEffect:setParameter( "maxColor", self.cl.exitElevatorEffectColor )
			end
		end
	end
end

function Elevator.sv_callButtonPressed( self )
	print( "Elevator call button was pressed" )
	ElevatorManager.Sv_Call( self.interactable )
end

function Elevator.sv_panelButtonPressed( self )
	--print( "Elevator panel button was pressed" )
	if self.saved.portal == nil then
		print( "Elevator has no destination yet" )
		return
	end

	local worldA, worldB = self.saved.portal:getWorldA(), self.saved.portal:getWorldB()
	if worldA and worldB then
		local warehouse = WarehouseManager.Cl_GetWarehouseFromWorld( worldB )
		if warehouse and warehouse.destroyed == true then
			return
		end
		warehouse = WarehouseManager.Cl_GetWarehouseFromWorld( worldA )
		if warehouse and warehouse.destroyed == true then
			return
		end
	end

	if self.saved.portal:hasOpeningA() and self.saved.portal:hasOpeningB() then
		ElevatorManager.Sv_Go( self.interactable )
	else
		self:sv_createElevatorDestination()
		ElevatorManager.Sv_Go( self.interactable )
	end
end

function Elevator.cl_n_doorOpen( self, params )
	local inside = ( params.contentsA and TriggerContentsContainsLocalPlayer( params.contentsA ) ) or ( params.contentsB and TriggerContentsContainsLocalPlayer( params.contentsB ) )
	if inside then
		AmbienceManager.Cl_SetPauseWorldAmbience( false )
	end

	self:stopMovingSounds()
	self:startElevatorSounds()

	sm.effect.playHostedEffect( "Elevator - Opendoor", self.interactable )

	if self.cl.elevatorInsideArea and self.cl.antiTheftActivated then
		local foundCharacters = self.cl.elevatorInsideArea:getCharacters()
		for _, characterResult in ipairs(foundCharacters) do
			if characterResult.character:isPlayer() then
				local player = characterResult.character:getPlayer()
				local localPlayer = sm.localPlayer.getPlayer()
				if player == localPlayer then
					if self.cl.barrierFloorRenderableEffect then
						self.cl.barrierFloorRenderableEffect:start()
					end
					return
				end
			end
		end
	end
end

function Elevator.stopMovingSounds( self )
	if not self.cl.moveEffect:isBreakSustaining() then
		self.cl.moveEffect:stopBreakSustain()
	end	

	if not self.cl.moveEffectOutside:isBreakSustaining() then
		self.cl.moveEffectOutside:stopBreakSustain()
	end	
end

function Elevator.startElevatorSounds( self )
	if not self.cl.musicEffect:isPlaying() or self.cl.musicEffect:isBreakSustaining() then
		self.cl.musicEffect:start()
	end
	if not self.cl.ambienceEffect:isPlaying() or self.cl.ambienceEffect:isBreakSustaining() then
		self.cl.ambienceEffect:start()
	end
end

function Elevator.stopElevatorSounds( self )
	if self.cl.musicEffect:isPlaying() or not self.cl.musicEffect:isBreakSustaining() then
		self.cl.musicEffect:stopImmediate()
	end
	if self.cl.ambienceEffect:isPlaying() then
		self.cl.ambienceEffect:stop();
	end
end

function Elevator.cl_n_startElevatorSounds( self, params )
	if ( params.contentsA and TriggerContentsContainsLocalPlayer( params.contentsA ) ) or ( params.contentsB and TriggerContentsContainsLocalPlayer( params.contentsB ) ) then
		self:startElevatorSounds()
	end
end

function Elevator.cl_n_doorClose( self, params )

	sm.effect.playHostedEffect( "Elevator - Closedoor", self.interactable )
	
	local inside = ( params.contentsA and TriggerContentsContainsLocalPlayer( params.contentsA ) ) or ( params.contentsB and TriggerContentsContainsLocalPlayer( params.contentsB ) )
	if inside then
		AmbienceManager.Cl_SetPauseWorldAmbience( true )
	else
		self:stopElevatorSounds()
	end
end

function Elevator.cl_n_startMovingSounds( self, params )
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

function Elevator.cl_n_stopMovingSounds( self, params )
	local inside = ( params.contentsA and TriggerContentsContainsLocalPlayer( params.contentsA ) ) or ( params.contentsB and TriggerContentsContainsLocalPlayer( params.contentsB ) )
	if not inside then
		AmbienceManager.Cl_SetPauseWorldAmbience( false )
	end
	self:stopMovingSounds()
end

function Elevator.sv_createElevatorDestination( self )
	assert( self.saved.portal:hasOpeningA(), "Portal has no opening" )
	if not self.destinationCreated then
		--print( "Contents A:" )
		--print( self.saved.portal:getContentsA() )
		ElevatorManager.Sv_CreateElevatorDestination( self.saved )
		self.destinationCreated = true
	end
end


function Elevator.createPortal( self, name )
	local position = self.shape.worldPosition + self.shape.worldRotation * ELEVATOR_PORTAL_OFFSET
	self.saved.position = position
	local size = sm.vec3.new( 1.75, 1.75, 3.0 ) - sm.vec3.new( 0.05, 0.05, 0.05 )
	local portal = sm.portal.createPortal( size )

	print( "Created portal "..name.." "..portal.id )
	ElevatorManager.Sv_RegisterElevator( self.interactable, portal )
	portal:setOpeningA( position, self.shape.worldRotation )

	return portal
end


function Elevator.findPortal( self, name )
	local position = self.shape.worldPosition + self.shape.worldRotation * ELEVATOR_PORTAL_OFFSET
	--print( "Looking for portal '"..name.."' in world "..sm.world.getCurrentWorld().id )
	local portal = sm.portal.popWorldPortalHook( name )
	if portal == nil and name == "ELEVATOR_DOWN" then
		--print( "Looking for portal 'ELEVATOR_ENTRANCE' in world "..sm.world.getCurrentWorld().id, "(fallback)")
		portal = sm.portal.popWorldPortalHook( "ELEVATOR_ENTRANCE" )
	end
	if portal then
		--print( "Portal "..portal.id.." found" )
		ElevatorManager.Sv_RegisterElevator( self.interactable, portal )
		portal:setOpeningB( position, self.shape.worldRotation )
	end
	return portal
end


function Elevator.findOrCreatePortal( self )
	if self.saved.level then
		-- Indoor
		if self.saved.name == "ELEVATOR_ENTRANCE" or self.saved.name == "ELEVATOR_DOWN" then
			print( "Looking for portal '"..self.saved.name.."' in world "..sm.world.getCurrentWorld().id )
			self.saved.portal = self:findPortal( self.saved.name )
		elseif self.saved.name == "ELEVATOR_UP" or self.saved.name == "ELEVATOR_EXIT" then
			self.saved.portal = self:createPortal( self.saved.name )
		end
	else
		-- Outdoor
		if self.saved.name == "ELEVATOR_ENTRANCE"  then
			self.saved.portal = self:createPortal( self.saved.name )
		elseif self.saved.name == "ELEVATOR_EXIT" then
			local name = self.saved.name.." "..self.saved.x..","..self.saved.y
			print( "Looking for portal '"..self.saved.name.."' in world "..sm.world.getCurrentWorld().id )
			self.saved.portal = self:findPortal( name )
			if self.saved.portal then
				print( "Portal", self.saved.portal, "found" )
			else
				print( "No portal found" )
			end
		end
	end
end

function Elevator.cl_t_onEnter( self, trigger, results )
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

function Elevator.cl_t_onExit( self, trigger, results )
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