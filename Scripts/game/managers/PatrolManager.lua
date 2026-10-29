dofile "$SURVIVAL_DATA/Scripts/game/survival_constants.lua"
dofile "$SURVIVAL_DATA/Scripts/game/survival_units.lua"
dofile "$SURVIVAL_DATA/Scripts/game/util/Timer.lua"

PatrolManager = class( nil )



local LeaderMinTenureTicks = 80 -- Ticks before a bad leader can be swapped
local LeaderSwitchMargin2 = 1.5 * 1.5 -- new leader must beat by >1.5m
local LeaderMaxDeviate2 = 8.0 * 8.0 -- if leader lags >8m from avg, allow switch now
local MinCharacterRadius = 0.3 -- Patrollers will always be treated as at least this wide
local RadiusMultiplier = 4 -- The follower circle's radius will be calculated as RadiusMultiplier * largest character radius, 4 allows one character of the same size to pass between
local DefaultAnchorSpeed = 4 -- Default move speed of the patrol anchor, only used as fallback

--[[ Server ]]
function PatrolManager.server_onCreate( self )
	g_patrolManager = self
	self.sv = {}
	self.sv.saved = sm.storage.load( STORAGE_CHANNEL_PATROLMANAGER )
	if self.sv.saved == nil then
		self.sv.saved = {}
		-- State of patrols by ( patrolKey, { patrolNodes, waitTrigger, loop, currentNodeIdx, targetNodeIdx, virtualAnchor } ) pairs
		self.sv.saved.patrolInfo = {}
		sm.storage.save( STORAGE_CHANNEL_PATROLMANAGER, self.sv.saved )
	end
	self.sv.triggerVolumes = {}
	self.sv.patrolGroups = {} -- Units in patrols by ( patrolKey, { patrolUnits, idToIdx, leaderId, leaderCooldown } ) pairs
	self.sv.followerOffsets = {} -- Follower offset positions in patrols by ( unit.id, position ) pairs
end







function PatrolManager.sv_save( self )
    sm.storage.save( STORAGE_CHANNEL_PATROLMANAGER, self.sv.saved )
end

function PatrolManager.server_onFixedUpdate( self, dt )







	local shouldSave = false
	self.sv.followerOffsets = {} -- Follower offset positions in patrols by ( unit.id, position ) pairs

	-- Update active patrols, iterate over patrolKeys that have units loaded
	for patrolKey, patrolGroup in pairs( self.sv.patrolGroups ) do
		local patrolUnits = patrolGroup.patrolUnits or {}
		local idToIdx = patrolGroup.idToIdx or {}



		local patrolInfo = self.sv.saved.patrolInfo[patrolKey]
		if patrolInfo and patrolInfo.patrolNodes and #patrolInfo.patrolNodes >= 2 then

			-- LEADER
			-- Find the average position of this group's patrollers
			local sumPositions = sm.vec3.zero()
			local activeCharacters = {}
			local largestCharacterRadius = MinCharacterRadius
			local fastestMoveSpeed
			local slowestSprintSpeed
			local anchorSpeed = DefaultAnchorSpeed
			for idx, patrolUnit in pairs( patrolUnits ) do
				local patrolCharacter = ( sm.exists( patrolUnit.unit ) and sm.exists( patrolUnit.unit.character ) ) and patrolUnit.unit.character or nil
				if patrolCharacter then
					sumPositions = sumPositions + patrolCharacter.worldPosition
					activeCharacters[#activeCharacters+1] = patrolCharacter
					largestCharacterRadius = math.max( largestCharacterRadius, patrolCharacter:getRadius() )

					local moveSpeed = patrolCharacter:getMoveSpeed()
					fastestMoveSpeed = fastestMoveSpeed and math.max( fastestMoveSpeed, moveSpeed ) or moveSpeed

					local sprintSpeed = patrolCharacter:getSprintSpeed()
					slowestSprintSpeed = slowestSprintSpeed and math.min( slowestSprintSpeed, sprintSpeed ) or sprintSpeed
				end
			end
			local avgPatrolPosition = #activeCharacters > 0 and sumPositions / #activeCharacters or nil
			if fastestMoveSpeed and slowestSprintSpeed then
				if slowestSprintSpeed > fastestMoveSpeed then
					-- Allow fastest move speed, stragglers can sprint to rejoin
					anchorSpeed = fastestMoveSpeed
				else
					-- There exists a unit that can't keep up by sprinting, faster units will have to wait
					anchorSpeed = slowestSprintSpeed
				end
			end













			-- Select the unit closest to the average as leader candidate
			local closestDistance2 = math.huge
			local selectedUnit
			if #activeCharacters == 2 then
				-- When avg of 2 take the first one
				local _, patroller = next( patrolUnits )
				selectedUnit = patroller and patroller.unit or nil
			else
				for idx, patrolUnit in pairs( patrolUnits ) do
					local patrolCharacter = ( sm.exists( patrolUnit.unit ) and sm.exists( patrolUnit.unit.character ) ) and patrolUnit.unit.character or nil
					if patrolCharacter then
						local distance2 = ( avgPatrolPosition - patrolCharacter.worldPosition ):length2()
						if distance2 < closestDistance2 then
							closestDistance2 = distance2
							selectedUnit = patrolUnit.unit
						end
					end
				end
			end

			-- Get candidate leader character
			local candidateId = selectedUnit and selectedUnit.id or nil
			local candidateIdx = candidateId and idToIdx[candidateId] or nil
			local candidateUnit = ( candidateIdx and patrolUnits[candidateIdx] and sm.exists( patrolUnits[candidateIdx].unit ) ) and patrolUnits[candidateIdx].unit or nil
			local candidateCharacter = ( candidateUnit and sm.exists( candidateUnit.character ) ) and candidateUnit.character or nil

			-- Get leader character
			local leaderIdx = patrolGroup.leaderId and idToIdx[patrolGroup.leaderId] or nil
			local leaderUnit = ( leaderIdx and patrolUnits[leaderIdx] and sm.exists( patrolUnits[leaderIdx].unit ) ) and patrolUnits[leaderIdx].unit or nil
			local leaderCharacter = ( leaderUnit and sm.exists( leaderUnit.character ) ) and leaderUnit.character or nil

			if patrolGroup.leaderId ~= candidateId and candidateCharacter and leaderCharacter then
				-- Switch if cooldown elapsed AND candidate is better by a margin
				patrolGroup.leaderCooldown = patrolGroup.leaderCooldown and math.max( patrolGroup.leaderCooldown - 1, 0 ) or LeaderMinTenureTicks - 1
				local dLeader2  = ( avgPatrolPosition - leaderCharacter.worldPosition ):length2()
        		local dCandidate2 = ( avgPatrolPosition - candidateCharacter.worldPosition ):length2()
				local allowNow = dLeader2 > LeaderMaxDeviate2
				if ( patrolGroup.leaderCooldown <= 0 and ( dCandidate2 + LeaderSwitchMargin2 ) < dLeader2 ) or allowNow then
					patrolGroup.leaderId = candidateId
					patrolGroup.leaderCooldown = LeaderMinTenureTicks
					shouldSave = true
					leaderCharacter = candidateCharacter
				end
			elseif not patrolGroup.leaderId and candidateId then
				-- Initial leader
				patrolGroup.leaderId = candidateId
				patrolGroup.leaderCooldown = LeaderMinTenureTicks
				shouldSave = true
				leaderCharacter = candidateCharacter
			else
				-- All is well
				patrolGroup.leaderCooldown = LeaderMinTenureTicks
			end

			-- Update current destination, check leader closeness
			if leaderCharacter then
				if patrolInfo.currentNodeIdx and patrolInfo.targetNodeIdx then
					-- Has a target, check if leader has arrived
					local targetNode = patrolInfo.patrolNodes[patrolInfo.targetNodeIdx]
					local targetDestination = targetNode and targetNode.position or nil
					if targetDestination then
						local distance2 = ( targetDestination - leaderCharacter.worldPosition ):length2()
						local tolerance = PATROL_LEADER_TOLERANCE + math.max( leaderCharacter:getRadius(), leaderCharacter:getHeight() )
						if distance2 <= tolerance * tolerance then
							-- New destination
							if targetNode.tickDelay == 0 or ( targetNode.tickDelay > 0 and targetNode.tickCounter >= targetNode.tickDelay ) then
								local previousTargetNodeIdx = patrolInfo.targetNodeIdx
								if patrolInfo.targetNodeIdx == 1 then
									patrolInfo.targetNodeIdx = math.min( 2, #patrolInfo.patrolNodes )
								elseif patrolInfo.targetNodeIdx == #patrolInfo.patrolNodes then
									if patrolInfo.loop then
										patrolInfo.targetNodeIdx = 1
									else
										patrolInfo.targetNodeIdx = math.max( #patrolInfo.patrolNodes - 1, 1 )
									end
								else
									-- Same direction
									local direction = patrolInfo.targetNodeIdx - patrolInfo.currentNodeIdx
									patrolInfo.targetNodeIdx = patrolInfo.targetNodeIdx + ( direction == 1 and 1 or -1 )
								end
								patrolInfo.currentNodeIdx = previousTargetNodeIdx
								shouldSave = true
								targetNode.tickCounter = 0
							else
								targetNode.tickCounter = targetNode.tickCounter + 1
							end
						end
					end
				else
					-- First setup, start by going to the first node
					patrolInfo.targetNodeIdx = 1
					if patrolInfo.loop then
						-- Act as if looping around from the last node
						patrolInfo.currentNodeIdx = #patrolInfo.patrolNodes
					else
						-- Act as if coming back from the second node
						patrolInfo.currentNodeIdx = 2
					end
					shouldSave = true
				end
			end
			local currentNode
			local targetNode
			if patrolInfo.currentNodeIdx and patrolInfo.targetNodeIdx then
				currentNode = patrolInfo.patrolNodes[patrolInfo.currentNodeIdx]
				targetNode = patrolInfo.patrolNodes[patrolInfo.targetNodeIdx]
			end

			-- Patrol direction
			local patrolDirection = leaderCharacter and leaderCharacter.smoothDirection or sm.vec3.new( 0, 1, 0 )
			if currentNode and targetNode then
				local previousDestination = currentNode and currentNode.position or nil
				local targetDestination = targetNode and targetNode.position or nil
				if previousDestination and targetDestination then
					local nodeDirection = targetDestination - previousDestination
					nodeDirection.z = 0
					patrolDirection = nodeDirection:safeNormalize( patrolDirection )
				end
			end

			-- Setup or update the virtual anchor that estimates where the patrol should be
			if patrolInfo.virtualAnchor then
				if targetNode then
					local moveBudget = anchorSpeed * dt
					local toTarget = targetNode.position - patrolInfo.virtualAnchor
					local anchorDirection = toTarget:safeNormalize( patrolDirection )
					local distanceLeft = toTarget:length()
					if distanceLeft <= moveBudget then
						-- Arrived
						patrolInfo.virtualAnchor = targetNode.position
					else
						-- Move
						patrolInfo.virtualAnchor = patrolInfo.virtualAnchor + anchorDirection * moveBudget
					end
				end
			else
				if currentNode then
					patrolInfo.virtualAnchor = currentNode.position
				end
			end

			-- FOLLOWERS
			-- Distribute follower offsets
			local radius = largestCharacterRadius * RadiusMultiplier
			local zeroIndexedNumFollowers = #activeCharacters - 1
			local angleBetweenFollowers = zeroIndexedNumFollowers > 0 and 2 * math.pi / zeroIndexedNumFollowers or 0
			local currentAngle = math.atan2( patrolDirection.y, patrolDirection.x ) - math.pi / 2
			for i, followerCharacter in ipairs( activeCharacters ) do
				if followerCharacter ~= leaderCharacter then
					-- Save the offset for the character
					local followerUnit = followerCharacter:getUnit()
					if followerUnit then
						self.sv.followerOffsets[followerUnit.id] = sm.vec3.new( radius * math.cos( currentAngle ), radius * math.sin( currentAngle ), 0 )
					end
					-- Update the angle for the next character
					currentAngle = currentAngle + angleBetweenFollowers
				end
			end































































		end
	end

	if shouldSave then
		self:sv_save()
	end
end

function PatrolManager.Sv_OnCellLoaded( x, y, world )
	if g_patrolManager then
		g_patrolManager:sv_onCellLoaded( x, y, world )
	end
end

function PatrolManager.sv_onCellLoaded( self, x, y, world )
	local shouldSave = false
	local nodes = sm.cell.getNodesByTag( x, y, "PATROL", world )
	if #nodes > 0 then
		for _, node in ipairs( nodes ) do
			local patrolParamData = node.params and node.params.patrol or nil
			local patrolData = patrolParamData and patrolParamData.patrol or nil
			local patrolTag = node.params and node.params.patrolTag or nil
			local waitTrigger = node.params and node.params.waitForTrigger or nil
			local loop = node.params and node.params.loop or nil
			if patrolData and patrolTag then
				local tileStorageKey = TileStorageManager.Sv_GetTileStorageKeyFromPosition( world, node.position )
				if tileStorageKey == nil then
					sm.log.error( "PatrolManager.sv_onCellLoaded could not calculate tile storage key for position: " .. tostring( node.position ) .. " in world: " .. tostring( world.id ) )
					return
				end
				local patrolKey = GetTileTagKey( tileStorageKey, patrolTag )
				local patrolInfo = {}
				patrolInfo.patrolNodes = {}
				patrolInfo.waitTrigger = waitTrigger
				patrolInfo.loop = loop
				for i, subNode in ipairs( patrolData.patrol ) do
					local subNodePos = Vec3IfArray( subNode.position )
					local worldPosition = node.position + node.rotation * ( subNodePos * node.scale )
					local tickDelay = subNode.delay ~= nil and math.floor( subNode.delay * 40 ) or 0
					patrolInfo.patrolNodes[#patrolInfo.patrolNodes+1] = { position = worldPosition, tickDelay = tickDelay, tickCounter = 0 }
				end
				if self.sv.saved.patrolInfo[patrolKey] then
					local savedCurrentNodeIdx = self.sv.saved.patrolInfo[patrolKey].currentNodeIdx
					local savedTargetNodeIdx = self.sv.saved.patrolInfo[patrolKey].targetNodeIdx
					if savedCurrentNodeIdx and savedTargetNodeIdx then
						if #patrolInfo.patrolNodes <= savedCurrentNodeIdx and #patrolInfo.patrolNodes <= savedTargetNodeIdx then
							-- Remember what the patrol was last doing
							patrolInfo.currentNodeIdx = self.sv.saved.patrolInfo[patrolKey].currentNodeIdx
							patrolInfo.targetNodeIdx = self.sv.saved.patrolInfo[patrolKey].targetNodeIdx
						end
					end
					self.sv.saved.patrolInfo[patrolKey] = patrolInfo
				else
					-- First time seeing this patrol
					self.sv.saved.patrolInfo[patrolKey] = patrolInfo
				end
				shouldSave = true
			end
		end
	end

	local triggerVolumes = sm.cell.getNodesByTag( x, y, "PATROL_TRIGGER", world )
	if #triggerVolumes > 0 then
		for _,node in ipairs( triggerVolumes ) do
			local patrolTrigger = node.params and node.params.patrolTrigger or nil
			if patrolTrigger then
				local cellKey = CellKey( x, y )
				local areaTrigger = sm.areaTrigger.createBox( node.scale / 2, node.position, node.rotation, sm.areaTrigger.filter.character, { patrolTrigger = patrolTrigger } )
				if self.sv.triggerVolumes[world.id] == nil then
					self.sv.triggerVolumes[world.id] = {}
				end
				if self.sv.triggerVolumes[world.id][cellKey] == nil then
					self.sv.triggerVolumes[world.id][cellKey] = {}
				end
				areaTrigger:bindOnEnter( "sv_t_onEnter", self )
				self.sv.triggerVolumes[world.id][cellKey][#self.sv.triggerVolumes[world.id][cellKey]+1] = areaTrigger
			end
		end
	end

    if shouldSave then
        self:sv_save()
    end
end

function PatrolManager.Sv_OnCellUnloaded( x, y, world )
	if g_patrolManager then
		g_patrolManager:sv_onCellUnloaded( x, y, world )
	end
end

function PatrolManager.sv_onCellUnloaded( self, x, y, world )
	local cellKey = CellKey( x, y )
	if self.sv.triggerVolumes[world.id] then
		if self.sv.triggerVolumes[world.id][cellKey] then
			for _, areaTrigger in ipairs( self.sv.triggerVolumes[world.id][cellKey] ) do
				areaTrigger:destroy()
			end
			self.sv.triggerVolumes[world.id][cellKey] = nil
		end
	end
end

function PatrolManager.sv_t_onEnter( self, trigger, results )
	if not TriggerResultContainsAnyPlayer( results ) then
		return
	end
	local triggerData = trigger:getUserData()
	local world = trigger:getWorld()
	local position = trigger:getWorldPosition()
	if triggerData then
		local tileStorageKey = TileStorageManager.Sv_GetTileStorageKeyFromPosition( world, position )
		TileStorageManager.Sv_SetValueInSubTable( tileStorageKey, PATROL_WAIT_TABLE, triggerData.patrolTrigger, true )
	end
end

function PatrolManager.Sv_AddUnit( patrolKey, unit )
	if g_patrolManager then
		g_patrolManager:sv_addUnit( patrolKey, unit )
	end
end

function PatrolManager.sv_addUnit( self, patrolKey, unit )
	local patrolGroup = self.sv.patrolGroups[patrolKey] or {}
	local patrolUnits = patrolGroup.patrolUnits or {}
	local idToIdx = patrolGroup.idToIdx or {}

	if idToIdx[unit.id] == nil then
		local idx = #patrolUnits + 1
		patrolUnits[idx] = { unit = unit }
		idToIdx[unit.id] = idx
		self.sv.patrolGroups[patrolKey] = { patrolUnits = patrolUnits, idToIdx = idToIdx }
	end
end

function PatrolManager.Sv_RemoveUnit( patrolKey, unit )
	if g_patrolManager then
		g_patrolManager:sv_removeUnit( patrolKey, unit )
	end
end

function PatrolManager.sv_removeUnit( self, patrolKey, unit )
	local patrolGroup = self.sv.patrolGroups[patrolKey] or {}
	local patrolUnits = patrolGroup.patrolUnits or {}
	local idToIdx = patrolGroup.idToIdx or {}

	local idx = idToIdx[unit.id]
	if idx then
		local lastIdx = #patrolUnits
		-- Replace and pop, id to index table
		idToIdx[patrolUnits[lastIdx].unit.id] = idx
		idToIdx[unit.id] = nil
		-- Swap and pop, unit
		patrolUnits[idx], patrolUnits[lastIdx] = patrolUnits[lastIdx], patrolUnits[idx]
		patrolUnits[lastIdx] = nil

		if #patrolUnits == 0 then
			self.sv.patrolGroups[patrolKey] = nil
		else
			self.sv.patrolGroups[patrolKey] = { patrolUnits = patrolUnits, idToIdx = idToIdx }
		end
	end
end

function PatrolManager.Sv_GetPatrolLeader( patrolKey )
	if g_patrolManager then
		return g_patrolManager:sv_getPatrolLeader( patrolKey )
	end
	return nil
end

function PatrolManager.sv_getPatrolLeader( self, patrolKey )
	local patrolGroup = self.sv.patrolGroups[patrolKey] or {}
	local patrolUnits = patrolGroup.patrolUnits or {}
	local idToIdx = patrolGroup.idToIdx or {}
	if patrolGroup.leaderId then
		local idx = idToIdx[patrolGroup.leaderId]
		if idx then
			local leaderUnit = patrolUnits[idx] and patrolUnits[idx].unit or nil
			return sm.exists( leaderUnit ) and leaderUnit or nil
		end
	end
	return nil
end

function PatrolManager.Sv_IsPatrolLocked( patrolKey, world, position )
	if g_patrolManager then
		return g_patrolManager:sv_isPatrolLocked( patrolKey, world, position )
	end
	return false
end

function PatrolManager.sv_isPatrolLocked( self, patrolKey, world, position )
	local patrolInfo = self.sv.saved.patrolInfo[patrolKey]
	if patrolInfo and patrolInfo.waitTrigger ~= nil and patrolInfo.waitTrigger ~= "" then
		if patrolInfo.tileStorageKey == nil then
			patrolInfo.tileStorageKey = TileStorageManager.Sv_GetTileStorageKeyFromPosition( world, position )
		end
		local isUnlocked = TileStorageManager.Sv_GetValueInSubTable( patrolInfo.tileStorageKey, PATROL_WAIT_TABLE, patrolInfo.waitTrigger )
		return not isUnlocked
	end
	return false
end

function PatrolManager.Sv_GetPatrolDestination( patrolKey )
	if g_patrolManager then
		return g_patrolManager:sv_getPatrolDestination( patrolKey )
	end
	return nil
end

function PatrolManager.sv_getPatrolDestination( self, patrolKey )
	local patrolInfo = self.sv.saved.patrolInfo[patrolKey]
	if patrolInfo and patrolInfo.patrolNodes and patrolInfo.targetNodeIdx then
		local targetNode = patrolInfo.patrolNodes[patrolInfo.targetNodeIdx]
		if targetNode then
			return targetNode.position
		end
	end
	return nil
end

function PatrolManager.Sv_GetPatrolAnchor( patrolKey )
	if g_patrolManager then
		return g_patrolManager:sv_getPatrolAnchor( patrolKey )
	end
	return nil
end

function PatrolManager.sv_getPatrolAnchor( self, patrolKey )
	local patrolInfo = self.sv.saved.patrolInfo[patrolKey]
	if patrolInfo then
		return patrolInfo.virtualAnchor
	end
	return nil
end

function PatrolManager.Sv_GetFollowerOffset( unit )
	if g_patrolManager then
		return g_patrolManager:sv_getFollowerOffset( unit )
	end
	return nil
end

function PatrolManager.sv_getFollowerOffset( self, unit )
	return self.sv.followerOffsets[unit.id]
end

function PatrolManager.Sv_IsPatrolActive( patrolKey )
	if g_patrolManager then
		return g_patrolManager:sv_isPatrolActive( patrolKey )
	end
	return false
end

function PatrolManager.sv_isPatrolActive( self, patrolKey )
	local patrolGroup = self.sv.patrolGroups[patrolKey] or {}
	local patrolInfo = self.sv.saved.patrolInfo[patrolKey]
	if patrolInfo and patrolInfo.patrolNodes and #patrolInfo.patrolNodes >= 2 then
		if patrolGroup.leaderId and patrolInfo.targetNodeIdx then
			-- This group has selected a leader and a target 
			return true
		end
	end
	return false
end
