dofile( "$SURVIVAL_DATA/Scripts/game/survival_constants.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/survival_dialogs.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/units/states/BaseState.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/units/states/PathingState.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/managers/WaypointQuestUnitManager.lua" )
dofile( "$GAME_DATA/Scripts/game/managers/EffectManager.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/util/Timer.lua" )

QuestActorState = class( BaseState )

local PathingTolerance = 0.5 -- Excluding the character's radius
local ShortcutTolerance = 2.0 -- Extra tolerance distance from where the unit may take a shortcut for smoother turns
local WaitForPlayerDistance = 6.0

-- Detect if stuck within this radius for the specified amount of time
local StuckDistance = 0.5
local UnstuckTime = 10.0 * 40

-- Teleport actors back to their held position if displaced beyond this distance for this long
local DisplacedDistance = 1.0
local DisplacedTime = 10.0 * 40



function QuestActorState.sv_onCreate( self, unit, customPathingState, actorName )
	self.unit = unit

	self.actorName = actorName

	self.nextCommandIndex = 0
	self.currentCommand = nil
	self.currentNonBlockingCommands = {}
	self.nonBlockingCommandsCounter = 0

	self.immovable = false -- save removable state before changing it

	self.saveState = false

	self.stuckTimer = Timer()
	self.stuckTimer:start( UnstuckTime )
	self.stuckCenterPosition = nil

	self.displacedTimer = Timer()
	self.displacedTimer:start( DisplacedTime )

	-- Idle
	self.idleState = self.unit:createState( "idle" )
	self.idleState.debugName = "idleState"

	-- Delay
	self.delayPositioningState = self.unit:createState( "positioning" )
	self.delayPositioningState.debugName = "delayPositioningState"
	self.delayTimer = Timer()
	self.delayTimer:start( 0 )

	-- Pathing
	if customPathingState then
		self.pathingState = customPathingState
	else
		self.pathingState = PathingState()
	end
	self.pathingState:sv_onCreate( self.unit )
	self.pathingState:sv_setTolerance( self.unit.character:getRadius() + PathingTolerance )
	self.pathingState:sv_setMovementType( "walk" )
	self.pathingState:sv_setWaterAvoidance( false )
	self.pathingState:sv_setCliffAvoidance( true )
	self.pathingState.debugName = "pathingState"

	-- apply saved state
	local actorData = QuestActorManager.Sv_GetActor( self.actorName )
	if actorData then
		self.pathingState:sv_setMovementType( actorData.stateData.movementType or "walk" )
	end
	
	self.currentState = self.idleState
	self.currentState:start()
end

-- move into getNextCommand?
function QuestActorState.setupCommandState( self, actorData )
	local commandList = actorData.stateData.commandList

	-- Skip past blocking commands that were already marked complete by Sv_NotifyActor
	-- (notifyActorEvent / notifySkip may fire before the actor reaches the command).
	-- This avoids stepping through one onUnitUpdate per skipped command.
	while actorData.stateData.currentCommandIndex ~= 0
			and commandList[actorData.stateData.currentCommandIndex]
			and commandList[actorData.stateData.currentCommandIndex].complete == true do
		local i = actorData.stateData.currentCommandIndex + 1
		while commandList[i] and not ( commandList[i].blocking == true ) do
			i = i + 1
		end
		if commandList[i] and commandList[i].blocking == true then
			actorData.stateData.currentCommandIndex = i
		else
			actorData.stateData.currentCommandIndex = 0
		end
		actorData.stateData.commandStartTick = sm.game.getCurrentTick()
		self.saveState = true
	end

	if actorData.stateData.currentCommandIndex ~= 0 then
		assert( commandList[actorData.stateData.currentCommandIndex] and commandList[actorData.stateData.currentCommandIndex].blocking == true,
			"QuestActorState.getNextCommand: No blocking command found at index "..tostring( actorData.stateData.currentCommandIndex ) )

		-- grab all non-blocking commands after the current blocking command
		self.currentNonBlockingCommands = {}
		self.nonBlockingCommandsCounter = 0
		local i = actorData.stateData.currentCommandIndex + 1
		while( commandList[i] and not commandList[i].blocking == true ) do
			table.insert( self.currentNonBlockingCommands, commandList[i] )
			i = i + 1
		end

		-- look ahead for next blocking command
		if commandList[i] and commandList[i].blocking == true then
			self.nextCommandIndex = i
		else
			self.nextCommandIndex = 0 -- end of commands
		end
	end

	if actorData.stateData.currentCommandIndex == 0 then
		self.currentCommand = nil
	else
		self.currentCommand = commandList[actorData.stateData.currentCommandIndex]
	end

	-- Sort non-blocking commands by delay when not using incremental delay
	if self.currentCommand and not self.currentCommand.incrementalDelay then
		table.sort( self.currentNonBlockingCommands, function( a, b )
			return (a.delay or 0) < (b.delay or 0)
		end )
	end

	local setCurrentState = function( newState )
		if newState ~= self.currentState then
			self.currentState:stop()
			newState:start()
		end
		self.currentState = newState
	end

	if self.currentCommand then
		if self.currentCommand.name == "move" then
			self.pathingState:sv_setDestination( self.currentCommand.position )
			setCurrentState( self.pathingState )
		elseif self.currentCommand.name == "giveItem" then
			self.delayPositioningState.desiredPosition = self.currentCommand.position or self.unit.character.worldPosition
			setCurrentState( self.delayPositioningState )
		elseif self.currentCommand.name == "awaitInteraction" then
			self.delayPositioningState.desiredPosition = self.currentCommand.position or self.unit.character.worldPosition
			setCurrentState( self.delayPositioningState )
		elseif self.currentCommand.name == "blockingDialog" then
			self.delayPositioningState.desiredPosition = actorData.home.position or self.unit.character.worldPosition
			setCurrentState( self.delayPositioningState )
		elseif self.currentCommand.name == "blockingCharacterEvent" then
			self.delayPositioningState.desiredPosition = actorData.home.position or self.unit.character.worldPosition
			setCurrentState( self.delayPositioningState )
		elseif self.currentCommand.name == "interactiveWait" then
			self.delayPositioningState.desiredPosition = actorData.home.position or self.unit.character.worldPosition
			setCurrentState( self.delayPositioningState )
		elseif self.currentCommand.name == "wait" then
			if self.currentCommand.idle then
				setCurrentState( self.idleState )
			else
				setCurrentState( self.delayPositioningState )
				self.delayPositioningState.desiredPosition = actorData.home.position or self.unit.character.worldPosition
			end
			if self.currentCommand.immovable ~= nil then
				self.unit.character:setImmovable( self.currentCommand.immovable )
			else
				self.unit.character:setImmovable( false )
			end
			if self.currentCommand.ticks and not self.currentCommand.notifyActorEvent then
				self.delayTimer:start( self.currentCommand.ticks )
			end
		end
	end

	if self.currentCommand == nil or self.currentCommand.name ~= "wait" then
		self.unit.character:setImmovable( false )
	end

	self.stuckTimer:reset()
	self.displacedTimer:reset()
end

function QuestActorState.getNextCommand( self, actorData )
	actorData.stateData.currentCommandIndex = self.nextCommandIndex
	actorData.stateData.commandStartTick = sm.game.getCurrentTick()
	self:setupCommandState( actorData )
	self.saveState = true
end

--[[API functions]]
function QuestActorState.start( self )
	self.immovable = self.unit.character:getImmovable()
	self.currentState:stop()
	self.currentState = self.idleState
	self.currentState:start()
end

function QuestActorState.stop( self )
	self.currentState:stop()
	self.unit.character:setImmovable( self.immovable )
end

-- The unit is only active in its home world. If it ends up in the wrong world it stays
-- passive and waits for QuestActorManager to destroy and respawn it in the correct world.
function QuestActorState.sv_isInHomeWorld( self, actorData )
	return actorData.home == nil or actorData.home.world == nil or self.unit.character.world == actorData.home.world
end

-- Force idle so a stale current state (e.g. pathing) doesn't move the actor in the wrong world.
function QuestActorState.sv_forceIdle( self )
	if self.currentState ~= self.idleState then
		self.currentState:stop()
		self.currentState = self.idleState
		self.currentState:start()
	end
end

function QuestActorState.onFixedUpdate( self, dt )
	local actorData = QuestActorManager.Sv_GetActor( self.actorName )

	-- Stay passive while in the wrong world; force idle so a stale current state doesn't
	-- move the actor. The manager handles destruction/respawn.
	if not actorData or ( actorData and not self:sv_isInHomeWorld( actorData ) ) then
		self:sv_forceIdle()
		self.currentState:onFixedUpdate( dt )
		return
	else
		self.currentState:onFixedUpdate( dt )
	end

	if self.currentCommand then
		local commandName = self.currentCommand.name

		-- facing update
		if self.currentState == self.delayPositioningState then
			if actorData.stateData.lookAtPlayer then
				local closestPlayerCharacter = GetClosestPlayerCharacter( self.unit.character.worldPosition, self.unit.character:getWorld() )
				if closestPlayerCharacter then
					-- Align character rotation towards nearest player
					local facingDirection = closestPlayerCharacter.worldPosition - self.unit.character.worldPosition
					facingDirection = sm.vec3.new( facingDirection.x, facingDirection.y, 0.0 ):safeNormalize( self.unit.character.direction )
					self.delayPositioningState.desiredDirection = facingDirection
				end
			elseif actorData.home.direction then
				-- add the direction offset to the home direction
				local desiredDirection = sm.vec3.rotateZ( actorData.home.direction, math.rad( actorData.stateData.facingAngle ) )
				self.delayPositioningState.desiredDirection = desiredDirection
			else
				self.delayPositioningState.desiredDirection = self.unit.character.direction
			end
		end

		if commandName == "move" then
			if self.currentState == self.pathingState then
				self.stuckCenterPosition = self.stuckCenterPosition or self.unit.character.worldPosition
				local distanceToStuckposition2 = ( self.stuckCenterPosition - self.unit.character.worldPosition ):length2()
				if distanceToStuckposition2 > StuckDistance * StuckDistance then
					self.stuckTimer:reset()
					self.stuckCenterPosition = nil
				else
					self.stuckTimer:tick()
				end
			else
				self.stuckTimer:reset()
			end
		elseif commandName == "wait" or commandName == "blockingCharacterEvent" then
			self.delayTimer:tick()
		end

		-- Holding position: teleport back to the held position if displaced for too long
		if self.currentState == self.delayPositioningState and self.delayPositioningState.desiredPosition then
			local heldPosition = self.delayPositioningState.desiredPosition
			local distanceToHeld2 = ( heldPosition - self.unit.character.worldPosition ):length2()
			if distanceToHeld2 > DisplacedDistance * DisplacedDistance then
				self.displacedTimer:tick()
				if self.displacedTimer:done() then
					local hit, result = sm.physics.raycast( heldPosition + sm.vec3.new( 0, 0, self.unit.character:getHeight() * 0.5 ),
													heldPosition + sm.vec3.new( 0, 0, -self.unit.character:getHeight() ) )
					if hit then
						self.unit.character:setWorldPosition( result.pointWorld + sm.vec3.new( 0, 0, self.unit.character:getHeight() * 0.5 ) )
					else
						self.unit.character:setWorldPosition( heldPosition + sm.vec3.new( 0, 0, self.unit.character:getHeight() * 0.5 ) )
					end
					self.displacedTimer:reset()
				end
			else
				self.displacedTimer:reset()
			end
		end
	end

	local elapsedTicks = sm.game.getCurrentTick() - actorData.stateData.commandStartTick
	if self.currentCommand and self.currentCommand.incrementalDelay == true then
		local incrementalDelay = 0
		for i, command in ipairs( self.currentNonBlockingCommands ) do
			incrementalDelay = incrementalDelay + ( command.delay or 0 )
			if elapsedTicks >= incrementalDelay and  i > self.nonBlockingCommandsCounter then
				self:executeNonBlockingCommand( command, actorData )
				self.nonBlockingCommandsCounter = i
			end
		end
	else
		for i, command in ipairs( self.currentNonBlockingCommands ) do
			if elapsedTicks >= ( command.delay or 0 ) and i > self.nonBlockingCommandsCounter then
				self:executeNonBlockingCommand( command, actorData )
				self.nonBlockingCommandsCounter = i
			end
		end
	end

	if actorData.stateData.currentCommandIndex == 0 then -- reached end of command list
		if self.nonBlockingCommandsCounter == #self.currentNonBlockingCommands then -- all non-blocking commands done
			QuestActorManager.Sv_EndActorTrack( self.actorName )
		end
	end
end

function QuestActorState.executeNonBlockingCommand( self, command, actorData )
	-- not saving the state here, rely on the blocking command to save the state after execution.
	if command.name == "setFacingDirection" then
		actorData.stateData.facingAngle = command.angle
		actorData.stateData.lookAtPlayer = false
	elseif command.name == "questEvent" then
		QuestManager.Sv_SendEvent( command.questEvent, nil )
	elseif command.name == "characterEvent" then
		self.unit:sendCharacterEvent( command.characterEvent )
	elseif command.name == "setFacePlayer" then
		actorData.stateData.lookAtPlayer = command.enabled
		actorData.stateData.facingAngle = 0
	elseif command.name == "setMovementType" then
		self.pathingState:sv_setMovementType( command.movementType )
		actorData.stateData.movementType = command.movementType
	elseif command.name == "dialog" then
		local uuid = command.uuid
		local dialogEntry = command.dialogEntry
		if command.dialogBeatLookup and dialog_beats_lookup[command.dialogBeatLookup] then
			local beat = dialog_beats_lookup[command.dialogBeatLookup]
			uuid = beat.dialog
			dialogEntry = beat.entry
		end
		local speakerName = SafeGet( self.unit.character.publicData, "speakerName" )
		if not DialogManager.Sv_IsDialogQueued( uuid, dialogEntry ) then
			DialogManager.Sv_PlayDialog( uuid, dialogEntry, nil, DialogType.Person, DialogSpeakerName[speakerName], nil, self.unit )
		end
	end
end

function QuestActorState.sv_canCompleteMove( self, command )
	assert( command.name == "move" )
	if command.waitForPlayer then
		local closestPlayer = GetClosestPlayer( self.unit.character.worldPosition, nil, self.unit.character:getWorld() )
		if closestPlayer then
			local closestPlayerCharacter = sm.exists( closestPlayer.character ) and closestPlayer.character or nil
			if closestPlayerCharacter then
				return ( closestPlayerCharacter.worldPosition - self.unit.character.worldPosition ):length2() <= WaitForPlayerDistance * WaitForPlayerDistance
			end
		end
		return false
	end
	return true
end

function QuestActorState.onUnitUpdate( self, dt )
	local actorData = QuestActorManager.Sv_GetActor( self.actorName )

	-- Stay passive while in the wrong world; force idle so a stale current state doesn't
	-- move the actor. The manager handles destruction/respawn.
	if not actorData or ( actorData and not self:sv_isInHomeWorld( actorData ) ) then
		self:sv_forceIdle()
		return
	end

	local commandList = actorData.stateData.commandList
	if commandList then
		if self.currentCommand ~= nil and self.currentCommand ~= commandList[actorData.stateData.currentCommandIndex] then
			-- drop stale command when track was swapped externally
			self.currentCommand = nil
			self.currentNonBlockingCommands = {}
			self.nonBlockingCommandsCounter = 0
			self.nextCommandIndex = 0
		end

		if self.currentCommand == nil and actorData.stateData.currentCommandIndex ~= 0 then
			-- distinguish between first time playback and resumed playback.
			if actorData.stateData.commandStartTick == 0 then
				actorData.stateData.commandStartTick = sm.game.getCurrentTick()
				self.nextCommandIndex = 1
				self:getNextCommand( actorData )
			else
				-- ongoing playback, resume from saved state, move to last home and restart non blocking commands.
				actorData.stateData.commandStartTick = sm.game.getCurrentTick()
				if self.unit.character.world == actorData.home.world then
					local hit, result = sm.physics.raycast( actorData.home.position + sm.vec3.new( 0, 0, self.unit.character:getHeight() * 0.5 ),
															actorData.home.position + sm.vec3.new( 0, 0, -self.unit.character:getHeight() )  )
					if hit then
						self.unit.character:setWorldPosition( result.pointWorld + sm.vec3.new( 0, 0, self.unit.character:getHeight() * 0.5 ) )
					else
						self.unit.character:setWorldPosition( actorData.home.position + sm.vec3.new( 0, 0, self.unit.character:getHeight() * 0.5 ) )
					end
				end
				self:setupCommandState( actorData )
			end
		end
	end
	
	if self.currentCommand then
		local commandName = self.currentCommand.name
		if commandName == "move" then
			local destination = self.currentCommand.position
			local prevState = self.currentState
			
			self.currentState:onUnitUpdate( dt )

			local distanceToObjective = ( destination - self.unit.character.worldPosition ):length()
			local nextCommandIsMove = self.nextCommandIndex ~= 0 and commandList[self.nextCommandIndex] and commandList[self.nextCommandIndex].name == "move"
			local tolerance = PathingTolerance
			if nextCommandIsMove then
				tolerance = tolerance + ShortcutTolerance
			end
			local withinTolerance = distanceToObjective <= self.unit.character:getRadius() + tolerance

			if self.currentCommand.teleport == true and withinTolerance == false then
				self.unit.character:setWorldPosition( destination )
			end

			local abortState = self.stuckTimer:done() or 
				( self.currentState == self.pathingState and withinTolerance == true and nextCommandIsMove ) -- allow aborting pathing state to begin next move
			local done, result = self.currentState:isDone()
			if ( done or abortState ) then
				if self.currentState == self.pathingState then
					if done and result == "arrived" then
						self.stuckTimer:reset() -- position is ok.
					end
					
					if self.stuckTimer:done() then
						-- Pathing is stuck, teleport to objective
						self.unit.character:setWorldPosition( destination + sm.vec3.new( 0, 0, self.unit.character:getHeight() * 0.5 ) )
						self.stuckTimer:reset()
					elseif not abortState and result ~= "arrived" then
						-- Pathing has failed, restart
						self.currentState:stop()
						self.currentState:start()
					end
					
					-- Pathing success
					if withinTolerance then
						--update home position on successful pathing.
						QuestActorManager.Sv_SetActorHome( self.actorName, self.unit.character:getWorld(), self.currentCommand.position, self.currentCommand.direction )
						if self:sv_canCompleteMove( self.currentCommand ) then
							if nextCommandIsMove then
								self:getNextCommand( actorData )
								self.pathingState:onFixedUpdate( 0 )
							else
								self:getNextCommand( actorData )
							end
						else
							self.currentState = self.delayPositioningState
						end
					end
				elseif self.currentState == self.delayPositioningState then
					if not withinTolerance then
						-- moved, path back to the destination
						self.currentState = self.pathingState
						self.pathingState:onFixedUpdate( 0 )
					elseif self:sv_canCompleteMove( self.currentCommand ) then
						self:getNextCommand( actorData )
					end
				end
			end

			if prevState ~= self.currentState then
				prevState:stop()
				self.currentState:start()
			end
		elseif commandName == "giveItem" then
			-- check if the command has been completed by the character
			if self.currentCommand.complete == true then
				if sm.exists( self.unit.character ) then
					-- TODO: Consider writing a c++ function to do this iteration instead of using this code, which is both slower and creates a lot of garbage on the table returned by getActiveAnimations().
					local animations = self.unit.character:getActiveAnimations()
					local finishedAnimations = true
					for i, animation in ipairs( animations ) do
						if animation.name == "emote_give_loop" or animation.name == "emote_give_out" then
							finishedAnimations = false
							break
						end
					end
					if finishedAnimations then
						self:getNextCommand( actorData )
					end
				end
			end
		elseif commandName == "awaitInteraction" then
			-- check if the command has been completed by the character
			if self.currentCommand.complete == true then
				self:getNextCommand( actorData )
			end
		elseif commandName == "blockingDialog" then
			if self.currentCommand.complete == true and not self.currentCommand.started then
				-- Skipped by notifySkip before dialog started
				self:getNextCommand( actorData )
			elseif not self.currentCommand.started then
				-- Start the dialog on first update
				self.currentCommand.started = true
				local uuid = self.currentCommand.uuid
				local dialogEntry = self.currentCommand.dialogEntry
				if self.currentCommand.dialogBeatLookup and dialog_beats_lookup[self.currentCommand.dialogBeatLookup] then
					local beat = dialog_beats_lookup[self.currentCommand.dialogBeatLookup]
					uuid = beat.dialog
					dialogEntry = beat.entry
				end
				self.currentCommand.resolvedUuid = uuid
				self.currentCommand.resolvedEntry = dialogEntry
				local speakerName = SafeGet( self.unit.character.publicData, "speakerName" )
				DialogManager.Sv_PlayDialog( uuid, dialogEntry, self.unit.character, DialogType.Person, DialogSpeakerName[speakerName] )
			elseif not DialogManager.Sv_IsDialogQueued( tostring( self.currentCommand.resolvedUuid or self.currentCommand.uuid ), self.currentCommand.resolvedEntry or self.currentCommand.dialogEntry ) then
				-- Dialog has finished playing
				self:getNextCommand( actorData )
			end
		elseif commandName == "blockingCharacterEvent" then
			if not self.currentCommand.started then
				-- Send the character event and start the duration timer
				self.currentCommand.started = true
				self.unit:sendCharacterEvent( self.currentCommand.characterEvent )
				self.delayTimer:start( self.currentCommand.ticks or 0 )
			elseif self.delayTimer:done() then
				self:getNextCommand( actorData )
			end
		elseif commandName == "interactiveWait" then
			if self.currentCommand.complete == true then
				self:getNextCommand( actorData )
			end
		elseif commandName == "wait" then
			if ( self.currentCommand.ticks and not self.currentCommand.notifyActorEvent and self.delayTimer:done() ) or self.currentCommand.complete == true then
				self:getNextCommand( actorData )
			end
		elseif commandName == "beginTrack" then
			-- will begin a new track. if successful current playback will end.
			QuestActorManager.Sv_BeginActorTrack( self.currentCommand.trackName, self.actorName )
			self:setupCommandState( actorData )
		end
	end
	
	if self.saveState == true then
		QuestActorManager.Sv_SaveActorState( self.actorName )
		self.saveState = false
	end
end

function QuestActorState.isDone( self )
	return true, nil
end

function QuestActorState.getMovementDirection( self )
	return self.currentState:getMovementDirection()
end

function QuestActorState.getFacingDirection( self )
	return self.currentState:getFacingDirection()
end

function QuestActorState.getMovementType( self )
	return self.currentState:getMovementType()
end

function QuestActorState.getWantsJump( self )
	return self.currentState:getWantsJump()
end

function QuestActorState.getWantsCrouch( self )
	return self.currentState:getWantsCrouch()
end