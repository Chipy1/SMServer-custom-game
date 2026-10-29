dofile( "$SURVIVAL_DATA/Scripts/game/survival_constants.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/units/states/BaseState.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/units/states/PathingState.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/managers/WaypointQuestUnitManager.lua" )
dofile( "$GAME_DATA/Scripts/game/managers/EffectManager.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/util/Timer.lua" )

QuestWaypointState = class( BaseState )

local PathingTolerance = 0.5 -- Excluding the character's radius
local ShortcutTolerance = 2.0 -- Extra tolerance distance from where the unit may take a shortcut for smoother turns
local WaitForPlayerDistance = 6.0

-- Detect if stuck within this radius for the specified amount of time
local StuckDistance = 0.5
local UnstuckTime = 10.0 * 40

-- quest environment helper functions
function QuestWaypointState.SetWaypointObject( quest, waypointQuestUnitId, waypointObject )
	InitializeNestedTables( quest, "publicData", "waypointObject" )
	quest.publicData.waypointObject[waypointQuestUnitId] = waypointObject
end
function QuestWaypointState.SetUpcomingWaypointObject( quest, waypointQuestUnitId, upcomingWaypointObject )
	InitializeNestedTables( quest, "publicData", "upcomingWaypointObject" )
	quest.publicData.upcomingWaypointObject[waypointQuestUnitId] = upcomingWaypointObject
end
function QuestWaypointState.SetDialogOptions( quest, waypointQuestUnitId, dialogOptions )
	InitializeNestedTables( quest, "publicData", "dialogOptions" )
	quest.publicData.dialogOptions[waypointQuestUnitId] = dialogOptions
end
function QuestWaypointState.SetWaitInteraction( quest, waypointQuestUnitId, waitInteraction )
	InitializeNestedTables( quest, "publicData", "waitInteraction" )
	quest.publicData.waitInteraction[waypointQuestUnitId] = waitInteraction
end
function QuestWaypointState.SetWaypointCondition( quest, waypointQuestUnitId, name, enable )
	InitializeNestedTables( quest, "publicData", "waypointCondition", waypointQuestUnitId )
	quest.publicData.waypointCondition[waypointQuestUnitId][name] = enable
end

-- fetching data from the quest's publicData depending on which unit this is
function QuestWaypointState.sv_getWaypointObject( self, quest )
	local waypointQuestUnitId = WaypointQuestUnitManager.Sv_GetWaypointQuestUnitIdByUnit( self.unit )
	if quest.publicData and quest.publicData.waypointObject and quest.publicData.waypointObject[waypointQuestUnitId] then
		return quest.publicData.waypointObject[waypointQuestUnitId]
	end
	return nil
end
function QuestWaypointState.sv_getUpcomingWaypointObject( self, quest )
	local waypointQuestUnitId = WaypointQuestUnitManager.Sv_GetWaypointQuestUnitIdByUnit( self.unit )
	if quest.publicData and quest.publicData.upcomingWaypointObject and quest.publicData.upcomingWaypointObject[waypointQuestUnitId] then
		return quest.publicData.upcomingWaypointObject[waypointQuestUnitId]
	end
	return nil
end
function QuestWaypointState.sv_getWaitInteraction( self, quest )
	local waypointQuestUnitId = WaypointQuestUnitManager.Sv_GetWaypointQuestUnitIdByUnit( self.unit )
	if quest.publicData and quest.publicData.waitInteraction and quest.publicData.waitInteraction[waypointQuestUnitId] then
		return quest.publicData.waitInteraction[waypointQuestUnitId]
	end
	return nil
end
function QuestWaypointState.sv_getDialogOptions( self, quest )
	local waypointQuestUnitId = WaypointQuestUnitManager.Sv_GetWaypointQuestUnitIdByUnit( self.unit )
	if quest.publicData and quest.publicData.dialogOptions and quest.publicData.dialogOptions[waypointQuestUnitId] then
		return quest.publicData.dialogOptions[waypointQuestUnitId]
	end
	return nil
end
function QuestWaypointState.sv_getWaypointCondition( self, quest, name )
	local waypointQuestUnitId = WaypointQuestUnitManager.Sv_GetWaypointQuestUnitIdByUnit( self.unit )
	if quest.publicData and quest.publicData.waypointCondition and quest.publicData.waypointCondition[waypointQuestUnitId] and quest.publicData.waypointCondition[waypointQuestUnitId][name] then
		return quest.publicData.waypointCondition[waypointQuestUnitId][name]
	end
	return false
end

function QuestWaypointState.sv_triggerAdditionalEvents( self, waypointObject, dialogOptions, quest )
	if waypointObject.characterEvent ~= nil then
		self.unit:sendCharacterEvent( waypointObject.characterEvent )
	end

	if waypointObject.dialog ~= nil and waypointObject.dialog ~= "" then
		if dialogOptions ~= nil then
			DialogManager.Sv_PlayDialog( dialogOptions.dialogUuid, waypointObject.dialog, quest, dialogOptions.dialogType, dialogOptions.dialogSpeakerName )
		end
	end

	if waypointObject.triggerEvent ~= nil then
		if g_effectManager then
			EffectManager.Sv_ActivateEventEffect( self.unit.character:getWorld(), waypointObject.triggerEvent, self.unit.character.worldPosition )
		end
	end
end

function QuestWaypointState.sv_onCreate( self, unit, customPathingState )
	self.unit = unit

	self.stuckTimer = Timer()
	self.stuckTimer:start( UnstuckTime )
	self.stuckCenterPosition = nil

	-- Idle
	self.idleState = self.unit:createState( "idle" )
	self.idleState.debugName = "idleState"

	-- Delay
	self.delayPositioningState = self.unit:createState( "positioning" )
	self.delayPositioningState.debugName = "delayPositioningState"
	self.delayAfterCondition = false
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

	self.currentState = self.idleState
	self.currentState:start()
end

--[[API functions]]
function QuestWaypointState.start( self )
	self.currentState:stop()
	self.currentState = self.idleState
	self.currentState:start()
end

function QuestWaypointState.stop( self )
	self.currentState:stop()
end

function QuestWaypointState.onFixedUpdate( self, dt )
	self.currentState:onFixedUpdate( dt )

	local waypointUnitData = WaypointQuestUnitManager.Sv_GetWaypointQuestUnit( self.unit )
	local quest = waypointUnitData and waypointUnitData.quest
	local waypointObject = nil
	if sm.exists( quest ) then
		waypointObject = self:sv_getWaypointObject( quest )
	end

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

	if self.currentState == self.delayPositioningState then
		self.delayTimer:tick()

		if waypointObject and waypointObject.lookAtPlayer then
			local closestPlayerCharacter = GetClosestPlayerCharacter( self.unit.character.worldPosition, self.unit.character:getWorld() )
			if closestPlayerCharacter then
				-- Align character rotation towards nearest player
				local facingDirection = closestPlayerCharacter.worldPosition - self.unit.character.worldPosition
				facingDirection = sm.vec3.new( facingDirection.x, facingDirection.y, 0.0 ):safeNormalize( self.unit.character.direction )
				self.delayPositioningState.desiredDirection = facingDirection
			end
		end
	else
		self.delayTimer:reset()
	end
end

function QuestWaypointState.onUnitUpdate( self, dt )
	self.currentState:onUnitUpdate( dt )
	
	local destination = nil
	local canShortcut = false
	
	local waypointUnitData = WaypointQuestUnitManager.Sv_GetWaypointQuestUnit( self.unit )
	local quest = waypointUnitData and waypointUnitData.quest
	
	if sm.exists( quest ) then
		local waypointObject = self:sv_getWaypointObject( quest )
		if waypointObject and InSameWorld( waypointObject.world, self.unit ) then
			destination = waypointObject.position
		end

		-- Check if shortcut to an upcoming waypoint is available
		if waypointObject and not ( waypointObject.delay or waypointObject.lookInDirection or waypointObject.waitForPlayer ) then
			local upcomingWaypointObject = self:sv_getUpcomingWaypointObject( quest )
			if upcomingWaypointObject and InSameWorld( upcomingWaypointObject.world, self.unit ) then
				local distanceToObjective = destination and ( destination - self.unit.character.worldPosition ):length() or math.huge
				canShortcut = distanceToObjective <= self.unit.character:getRadius() + PathingTolerance + ShortcutTolerance
			end
		end

		-- Pass on data for waiting on interactions
		self.unit.character.publicData = self.unit.character.publicData and self.unit.character.publicData or {} -- Soft init
		self.unit.character.publicData.waitInteraction = self:sv_getWaitInteraction( quest )
	end	

	-- Update destination
	if destination then
		self.pathingState:sv_setDestination( destination )
	end

	local prevState = self.currentState
	local abortState = ( self.currentState == self.pathingState and self.stuckTimer:done() ) or
						( self.currentState == self.delayPositioningState and self.delayTimer:done() ) or
						( self.currentState == self.pathingState and canShortcut )
	local done, result = self.currentState:isDone()
	if ( done or abortState ) then
		-- Select state
		if self.currentState == self.pathingState then
			if done or canShortcut then
				self.stuckTimer:reset()
			end

			-- React to waypoint node
			if waypointUnitData and sm.exists( waypointUnitData.quest ) then
				local waypointObject = self:sv_getWaypointObject(  waypointUnitData.quest )
				local upcomingWaypointObject = self:sv_getUpcomingWaypointObject(  waypointUnitData.quest )
				local dialogOptions = self:sv_getDialogOptions( waypointUnitData.quest )
				if waypointObject and InSameWorld( waypointObject.world, self.unit ) then
					if self.stuckTimer:done() or ( result ~= "arrived" and not canShortcut ) then
						-- Pathing has failed, teleport to objective
						self.unit.character:setWorldPosition( waypointObject.position )
					end

					-- Arrived at objective, perform additional events
					local waitingForCondition = waypointObject.waitForCondition and not QuestWaypointState.sv_getWaypointCondition( self, waypointUnitData.quest, waypointObject.waitForCondition )
					if not waitingForCondition then
						self:sv_triggerAdditionalEvents( waypointObject, dialogOptions, waypointUnitData.quest )
					end

					if waypointObject.delay or waypointObject.lookInDirection or waypointObject.lookAtPlayer or waypointObject.waitForPlayer or waitingForCondition then
						-- Delay before starting the next objective
						local delay = 0
						if not waitingForCondition then -- delay starts after condition
							delay = waypointObject.delay ~= nil and waypointObject.delay or 0
						end
						self.delayPositioningState.desiredPosition = waypointObject.position
						if waypointObject.lookInDirection then
							-- Align character rotation with the waypoint
							local facingDirection = waypointObject.rotation * sm.vec3.new( 0, 0, 1 )
							facingDirection = sm.vec3.new( facingDirection.x, facingDirection.y, 0.0 ):safeNormalize( self.unit.character.direction )
							self.delayPositioningState.desiredDirection = facingDirection
						elseif waypointObject.lookAtPlayer then
							local closestPlayerCharacter = GetClosestPlayerCharacter( self.unit.character.worldPosition, self.unit.character:getWorld() )
							if closestPlayerCharacter then
								-- Align character rotation towards nearest player
								local facingDirection = closestPlayerCharacter.worldPosition - self.unit.character.worldPosition
								facingDirection = sm.vec3.new( facingDirection.x, facingDirection.y, 0.0 ):safeNormalize( self.unit.character.direction )
								self.delayPositioningState.desiredDirection = facingDirection
							end
						else
							self.delayPositioningState.desiredDirection = self.unit.character.direction
						end
						self.delayTimer:start( delay * 40 )
						self.currentState = self.delayPositioningState
					else
						-- Pathing success
						local distanceToObjective = ( waypointObject.position - self.unit.character.worldPosition ):length()
						if upcomingWaypointObject and InSameWorld( upcomingWaypointObject.world, self.unit ) then
							--  Shortcut to next objective
							if distanceToObjective <= self.unit.character:getRadius() + PathingTolerance + ShortcutTolerance then
								-- Replace destination ASAP to reduce stutter in shortcut path
								destination = upcomingWaypointObject.position
								self.pathingState:sv_setDestination( destination )
								self.pathingState:onFixedUpdate( 0 )
								self.currentState = self.pathingState -- Redundant
								-- Counts as completed
								sm.event.sendToScriptableObject( waypointUnitData.quest, "sv_e_waypointCompleted", { unit = self.unit } )
							end
						elseif distanceToObjective <= self.unit.character:getRadius() + PathingTolerance then
							-- Arrived at end point
							self.currentState = self.idleState
							sm.event.sendToScriptableObject( waypointUnitData.quest, "sv_e_waypointCompleted", { unit = self.unit } )
						end
					end
				end
			elseif destination then
				if self.stuckTimer:done() or result ~= "arrived" then
					-- Pathing has failed, teleport to objective
					self.unit.character:setWorldPosition( destination )
					self.currentState = self.idleState
				else
					self.currentState = self.pathingState
				end
			else
				self.currentState = self.idleState
			end
		elseif self.currentState == self.delayPositioningState then
			-- React to waypoint node
			if sm.exists( quest ) then
				if self.delayTimer:done() then
					local canComplete = false
					local waypointObject = self:sv_getWaypointObject( quest )
					if waypointObject and InSameWorld( waypointObject.world, self.unit ) then
						if waypointObject.waitForPlayer then
							-- Find closest player
							local closestPlayer = GetClosestPlayer( self.unit.character.worldPosition, nil, self.unit.character:getWorld() )
							if closestPlayer then
								local closestPlayerCharacter = sm.exists( closestPlayer.character ) and closestPlayer.character or nil
								if closestPlayerCharacter then
									canComplete = ( closestPlayerCharacter.worldPosition - self.unit.character.worldPosition ):length2() <= WaitForPlayerDistance * WaitForPlayerDistance
								end
							end
						elseif waypointObject.waitForCondition and not self.delayAfterCondition then
							local condition = QuestWaypointState.sv_getWaypointCondition( self, quest, waypointObject.waitForCondition )
							if condition then
								local dialogOptions = self:sv_getDialogOptions( quest )
								self:sv_triggerAdditionalEvents( waypointObject, dialogOptions, quest )
								local delay = waypointObject.delay ~= nil and waypointObject.delay or 0
								if delay > 0 then
									self.delayTimer:start( delay * 40 )
									self.delayAfterCondition = true
								else
									canComplete = true
								end
							end
						else
							canComplete = true
						end
					end
					if canComplete then
						-- Finished delay, tell the quest to update the objective
						sm.event.sendToScriptableObject( quest, "sv_e_waypointCompleted", { unit = self.unit } )
						self.currentState = self.idleState
						self.delayAfterCondition = false
					end
				end
			else
				self.currentState = self.idleState
			end
		elseif destination then
			self.currentState = self.pathingState
		else
			self.currentState = self.idleState
		end
	end

	if prevState ~= self.currentState then
		prevState:stop()
		self.currentState:start()
	end
end

function QuestWaypointState.isDone( self )
	return true, self.status
end

function QuestWaypointState.getMovementDirection( self )
	return self.currentState:getMovementDirection()
end

function QuestWaypointState.getFacingDirection( self )
	return self.currentState:getFacingDirection()
end

function QuestWaypointState.getMovementType( self )
	return self.currentState:getMovementType()
end

function QuestWaypointState.getWantsJump( self )
	return self.currentState:getWantsJump()
end

function QuestWaypointState.getWantsCrouch( self )
	return self.currentState:getWantsCrouch()
end