FlightPathfinding = class( nil )





local MaxNodeVisits = 140000 -- Approximation of one full sphere with 32 radius and node size 1
local MaxPathCount = 20
local PossibleDirections = {
	sm.vec3.new( 0, 1, 0 ),
	sm.vec3.new( 0, -1, 0 ),
	sm.vec3.new( 1, 0, 0 ),
	sm.vec3.new( -1, 0, 0 ),
	sm.vec3.new( 0, 0, 1 ),
	sm.vec3.new( 0, 0, -1 ),

	-- Diagonal edge
	sm.vec3.new( 1, 1, 0 ),
	sm.vec3.new( 1, -1, 0 ),
	sm.vec3.new( -1, 1, 0 ),
	sm.vec3.new( -1, -1, 0 ),
	sm.vec3.new( 1, 0, 1 ),
	sm.vec3.new( 1, 0, -1 ),
	sm.vec3.new( -1, 0, 1 ),
	sm.vec3.new( -1, 0, -1 ),
	sm.vec3.new( 0, 1, 1 ),
	sm.vec3.new( 0, 1, -1 ),
	sm.vec3.new( 0, -1, 1 ),
	sm.vec3.new( 0, -1, -1 ),

	-- Diagonal corner
	sm.vec3.new( 1, 1, 1 ),
	sm.vec3.new( 1, 1, -1 ),
	sm.vec3.new( 1, -1, -1 ),
	sm.vec3.new( -1, -1, -1 ),
	sm.vec3.new( -1, -1, 1 ),
	sm.vec3.new( -1, 1, 1 ),
	sm.vec3.new( -1, 1, -1 ),
}

local function NodeKey( worldPosition, nodeSize )
	local nodePos = sm.vec3.new( math.floor( worldPosition.x / nodeSize ), math.floor( worldPosition.y / nodeSize ), math.floor( worldPosition.z / nodeSize )  )
	return sm.util.hash( nodePos )
end

local function PosToNodeCenter( worldPosition, nodeSize )
	local adjustedPosition = worldPosition + ( sm.vec3.one() * nodeSize * 0.5 )
	local nodeCenterPos = sm.vec3.new( math.floor( adjustedPosition.x / nodeSize ), math.floor( adjustedPosition.y / nodeSize ), math.floor( adjustedPosition.z / nodeSize )  ) * nodeSize
	return nodeCenterPos
end

local function PredictDistanceCost( positionA, positionB )
	-- Euclidean distance
	return ( positionA - positionB ):length()
end

local function InLineOfSight( nodeA, nodeB, nodeSize )
	return not sm.physics.capsuleHasContact( nodeA.position, nodeB.position, nodeSize * 0.5, bit.bor( sm.physics.filter.static, sm.physics.filter.waterArea ) )
end

function FlightPathfinding.init( self, startPosition, targetPosition, nodeSize )
	self.nodeVisits = 0
	self.nodeData = {} -- The node data
	self.openNodes = {} -- Node keys of interest
	self.closedNodes = {} -- Node keys of no interest
	self.blockedNodes = {}
	self.currentPath = {}

	self.nodeSize = nodeSize and nodeSize or 1
	self.startPosition = PosToNodeCenter( startPosition, self.nodeSize )
	self.targetPosition = PosToNodeCenter( targetPosition, self.nodeSize )
	self.startKey = NodeKey( self.startPosition, self.nodeSize )
	self.targetKey = NodeKey( self.targetPosition, self.nodeSize )

	-- Init start node
	local startNode = {}
	startNode.position = self.startPosition
	startNode.key = self.startKey
	startNode.fromCost = 0
	startNode.toCost = 0
	startNode.fromKey = nil
	self.nodeData[self.startKey] = startNode
	self.openNodes[self.startKey] = true





end


function FlightPathfinding.reset( self )
	local startNode
	if self.startKey then
		startNode = self.nodeData[self.startKey]
		if startNode then
			startNode.fromCost = 0
			startNode.toCost = 0
			startNode.fromKey = nil
		end
	end

	local targetNode
	if self.targetKey then
		targetNode = self.nodeData[self.targetKey]
		if targetNode then
			targetNode.fromCost = 0
			targetNode.toCost = 0
			targetNode.fromKey = nil
		end
	end

	self.nodeData = {}
	if startNode then
		self.nodeData[startNode.key] = startNode
		self.openNodes[startNode.key] = true
	end

	self.nodeVisits = 0
	self.openNodes = {}
	self.closedNodes = {}
	self.blockedNodes = {}



end

function FlightPathfinding.tick( self )
	local currentFinalNode = self.currentPath[#self.currentPath]
	if currentFinalNode and currentFinalNode.key == self.targetKey then
		-- No need for further updates
		return
	end
	if self.blockedNodes[self.targetKey] or self.closedNodes[self.targetKey] then
		-- Impossible to complete, stop further updates
		return
	end
	if self.nodeVisits >= MaxNodeVisits then
		-- Node data has grown too large, stop further updates
		return
	end

	-- Get the cheapest open node to visit
	local cheapestNodeKey
	local cheapestCost = math.huge
	local cheapestFromCost = math.huge
	for openNodeKey, _ in pairs( self.openNodes ) do
		local openNode = self.nodeData[openNodeKey]
		local openNodeCost = openNode.toCost + openNode.fromCost

		if openNodeCost < cheapestCost then
			cheapestNodeKey = openNodeKey
			cheapestCost = openNodeCost
			cheapestFromCost = openNode.fromCost
		elseif openNodeCost == cheapestCost and openNode.fromCost < cheapestFromCost then
			cheapestNodeKey = openNodeKey
			cheapestCost = openNodeCost
			cheapestFromCost = openNode.fromCost
		end
	end

	-- Get nodes
	local nodeToVisit = cheapestNodeKey and self.nodeData[cheapestNodeKey] or nil
	if nodeToVisit then
		self.nodeVisits = self.nodeVisits + 1

		-- Close the node
		self.closedNodes[nodeToVisit.key] = true
		self.openNodes[nodeToVisit.key] = nil

		self:checkBlocked( nodeToVisit )

		-- Open adjacent nodes
		for _, nodeOffset in ipairs( PossibleDirections) do
			local adjacentNode = {}
			adjacentNode.position = nodeToVisit.position + nodeOffset * self.nodeSize
			adjacentNode.key = NodeKey( adjacentNode.position, self.nodeSize )
			adjacentNode.fromCost = 0
			adjacentNode.toCost = 0
			if self.blockedNodes[adjacentNode.key] == nil then -- Skip blocked nodes
				if self.closedNodes[adjacentNode.key] == nil then -- Skip closed nodes
					-- Inherit the from node if in line of sight
					local fromNode = nodeToVisit.fromKey and self.nodeData[nodeToVisit.fromKey] or nil
					if fromNode == nil or not InLineOfSight( fromNode, adjacentNode, self.nodeSize ) then
						fromNode = self.nodeData[nodeToVisit.key]
					end

					local toAdjacentCost = fromNode.toCost + PredictDistanceCost( fromNode.position, adjacentNode.position )
					if self.openNodes[adjacentNode.key] == nil or toAdjacentCost < adjacentNode.toCost then
						-- Open the adjacent node
						adjacentNode.fromKey = fromNode.key
						adjacentNode.toCost = toAdjacentCost
						adjacentNode.fromCost = PredictDistanceCost( adjacentNode.position, self.targetPosition )
						self.nodeData[adjacentNode.key] = adjacentNode
						self.openNodes[adjacentNode.key] = true
					end
				end
			else
				-- Close blocked nodes
				adjacentNode.toCost = math.huge
				adjacentNode.fromCost = math.huge
				self.nodeData[adjacentNode.key] = adjacentNode
				self.closedNodes[adjacentNode.key] = true
			end
		end

		-- Check if this path is better
		local shouldUpdatePath = nodeToVisit.key == self.targetKey -- Found the target
		if not shouldUpdatePath then
			if currentFinalNode then
				local foundDistance2 = ( nodeToVisit.position - self.targetPosition ):length2()
				local currentDistance2 = ( currentFinalNode.position - self.targetPosition ):length2()
				shouldUpdatePath = foundDistance2 < currentDistance2 -- Found a path closer to the target
			else
				shouldUpdatePath = true -- This is the first path node
			end
		end

		-- Update path
		if shouldUpdatePath then
			local backwardPath = {}
			local currentNode = nodeToVisit
			local pathCount = 0
			while currentNode and pathCount < MaxPathCount do
				pathCount = pathCount + 1
				backwardPath[#backwardPath+1] = currentNode
				currentNode = self.nodeData[currentNode.fromKey]
			end

			-- Reverse the path list
			self.currentPath = {}
			for _, node in reverse_ipairs( backwardPath ) do
				self.currentPath[#self.currentPath+1] = node
			end
		end

	end























end

function FlightPathfinding.result( self )
	local finalNode = self.currentPath[#self.currentPath]
	local result
	if finalNode and finalNode.key == self.targetKey then
		result = "finished"
	elseif self.blockedNodes[self.targetKey] or self.closedNodes[self.targetKey] then
		result = "blocked"
	end
	local path = {}
	for _, node in ipairs( self.currentPath ) do
		path[#path+1] = node.position
	end
	return path, result
end

function FlightPathfinding.getNodePosition( self, worldPosition )
	return PosToNodeCenter( worldPosition, self.nodeSize )
end

function FlightPathfinding.inSameNode( self, worldPositionA, worldPositionB )
	local nodePosA = PosToNodeCenter( worldPositionA, self.nodeSize )
	local nodeKeyA = NodeKey( nodePosA, self.nodeSize )
	local nodePosB = PosToNodeCenter( worldPositionB, self.nodeSize )
	local nodeKeyB = NodeKey( nodePosB, self.nodeSize )
	return nodeKeyA == nodeKeyB
end

function FlightPathfinding.checkBlocked( self, node )
	-- Check neighbouring nodes
	for _, nodeOffset in ipairs( PossibleDirections ) do
		local otherNodePos = node.position + nodeOffset * self.nodeSize
		local otherNodeKey = NodeKey( otherNodePos, self.nodeSize )
		local filter = bit.bor( sm.physics.filter.static, sm.physics.filter.waterArea )
		if sm.physics.sphereHasContact( otherNodePos, self.nodeSize * 0.5, true, true, filter ) then
			self.blockedNodes[otherNodeKey] = otherNodePos
		else
			local material, density = sm.world.getCurrentWorld():getVoxelMaterialFromWorldPosition( otherNodePos )
			if density >= 16 then
				self.blockedNodes[otherNodeKey] = otherNodePos
			else
				self.blockedNodes[otherNodeKey] = nil
			end
		end
	end
end

