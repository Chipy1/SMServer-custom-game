dofile( "$SURVIVAL_DATA/Scripts/game/units/unit_util.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/units/states/QuestActorState.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/managers/QuestManager.lua" )

QuestActorUnit = class( BaseUnit )

function QuestActorUnit.server_onCreate( self )

	self.saved = self.storage:load()
	if self.saved == nil then
		self.saved = {}
	end

    self.unit:setWhiskerData( 4, math.rad( 70.0 ), 1.0, 4.75 )

	local questUnitEnum = nil
	if self.data and self.data.questUnitName then
		questUnitEnum = QuestUnits[self.data.questUnitName]
		QuestManager.Sv_RegisterQuestUnit( questUnitEnum, self.unit )
	end
	QuestManager.Sv_SendEvent( QuestEvent.QuestUnitCreated, { character = self.unit.character, questUnitEnum = questUnitEnum } )

	if self.data then
		self.actorName = self.data.questUnitName
	end

	if self.params then
		if self.params.characterSpawnEvent and not self.params.characterSpawnEvent == "" then
			self.unit:sendCharacterEvent( self.params.characterSpawnEvent )
		end
		if self.params.questActorParams then
			if self.params.questActorParams.actorName ~= "" then
				self.saved.actorName = self.params.questActorParams.actorName
			elseif not self.actorName then
				sm.log.warning( "QuestActorUnit: No actorName provided for unit " .. tostring( self.unit ) .. "with character uuid " .. tostring( self.unit.character:getCharacterType() ) .. ". Quest actor will not be tracked." )
			end
		end
	end

	self.actorName = self.actorName or self.saved.actorName

	-- Begin the spawn track only after actorName is resolved, so it is registered under the final name.
	if self.params and self.params.questActorParams and self.params.questActorParams.spawnTrack then
		QuestActorManager.Sv_BeginActorTrack( self.params.questActorParams.spawnTrack, self.actorName )
	end

	if not IsEmptyTable( self.saved ) then
		self.storage:save( self.saved )
	end

	QuestActorManager.Sv_RegisterUniqueActor( self.actorName, self.unit )
	InitializeNestedTables( self.unit, "publicData" ).questUnitName = self.actorName

	self.idleState = self.unit:createState( "idle" )
	self.idleState.debugName = "idleState"

	self.actorState = QuestActorState()
	self.actorState:sv_onCreate( self.unit, nil, self.actorName )
	self.actorState.debugName = "actorState"

	self.currentState = self.idleState
	self.currentState:start()

	print( "-- QuestActorUnit created --" )
end

function QuestActorUnit.server_onRefresh( self )
	print( "-- QuestActorUnit refreshed --" )
end

function QuestActorUnit.server_onFixedUpdate( self, dt )
	if self.currentState then
		self.currentState:onFixedUpdate( dt )
		self.unit:setMovementDirection( self.currentState:getMovementDirection() )
		self.unit:setMovementType( self.currentState:getMovementType())
		self.unit:setFacingDirection( self.currentState:getFacingDirection() )
	end
end

function QuestActorUnit.sv_e_forceUnitUpdate( self )
	-- Force an immediate unit update
	self:server_onUnitUpdate( 0 )
end

function QuestActorUnit.server_onUnitUpdate( self, dt )
	if not sm.exists( self.unit ) then
		return
	end
	if self.currentState then
		self.currentState:onUnitUpdate( dt )
	end
	local prevState = self.currentState

	local done
	if self.currentState then
		done = self.currentState:isDone()
	else
		done = true
	end

	if done then
		-- Select state
		local actorData = QuestActorManager.Sv_GetActor( self.actorName )
		if actorData and actorData.stateData.commandList then
			self.currentState = self.actorState
		else
			self.currentState = self.idleState
		end
	end

	if prevState ~= self.currentState then
		if prevState then
			prevState:stop()
		end
		self.currentState:start()
	end
end

function QuestActorUnit.sv_e_onInteract( self, params )
	local questInteraction = true
	local saveState = false
	if self.currentState == self.actorState then
		if SafeNestedAccess( self.actorState, "currentCommand", "name" ) == "giveItem" then
			local giveItemCommand = self.actorState.currentCommand
			if giveItemCommand.type == "log" then
				LogEntryManager.Sv_AddLog( giveItemCommand.uuid )
				giveItemCommand.complete = true
				saveState = true
			else
				print( "Unsupported Npc give item type: " .. tostring( giveItemCommand.type ) )
			end
			QuestManager.Sv_SendEvent( giveItemCommand.questEvent, nil )
		elseif SafeNestedAccess( self.actorState, "currentCommand", "name" ) == "awaitInteraction" then
			local command = self.actorState.currentCommand
			if not command.complete then
				QuestManager.Sv_SendEvent( command.questEvent, { player = params.player } )
				if not command.externalCompletion then
					command.complete = true
					saveState = true
				end
			end
		elseif SafeNestedAccess( self.actorState, "currentCommand", "name" ) == "interactiveWait" then
			local command = self.actorState.currentCommand
			local currentTick = sm.game.getCurrentTick()
			local cooldownReady = not command.lastInteractionTick or ( currentTick >= command.lastInteractionTick + ( command.cooldownTicks or 0 ) )
			if not command.exhausted and cooldownReady then
				command.lastInteractionTick = currentTick
				-- Send character event on interaction if specified
				if command.characterEvent then
					self.unit:sendCharacterEvent( command.characterEvent )
				end
				-- Play shout dialog on interaction if uuid is specified
				if command.uuid then
					if not command.interactionCounter then
						command.interactionCounter = 1
					end
					local entryCount = DialogManager.Sv_GetShoutEntryCount( command.uuid )
					if command.interactionCounter > entryCount then
						if command.repeating then
							command.interactionCounter = 1
						else
							command.exhausted = true
						end
					end
					if not command.exhausted then
						local entryName = DialogManager.Sv_GetShoutEntryName( command.uuid, command.interactionCounter )
						if entryName then
							local speakerName = SafeGet( self.unit.character.publicData, "speakerName" )
							DialogManager.Sv_PlayShoutDialog( command.uuid, entryName, nil, DialogSpeakerName[speakerName], self.unit )
							command.interactionCounter = command.interactionCounter + 1
						else
							sm.log.error( "QuestActorUnit: InteractiveWait dialog entry not found for uuid "..tostring( command.uuid ).." on interaction counter "..tostring( command.interactionCounter ) )
						end
					end
				end
				saveState = true
			end
			questInteraction = false
		end
		if saveState then
			QuestActorManager.Sv_SaveActorState( self.actorName )
		end
	end
	if questInteraction then
		QuestManager.Sv_SendEvent( QuestEvent.QuestUnitInteract, { questUnitEnum = QuestUnits[self.actorName], player = params.player } )
	end
end

function QuestActorUnit.sv_e_notifyActor( self, eventName )
	self.actorState:sv_onNotifyActor( eventName )
end