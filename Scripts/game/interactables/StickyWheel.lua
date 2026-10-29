-- StickyWheel.lua --

StickyWheel = class( nil )
StickyWheel.maxParentCount = 2
StickyWheel.maxChildCount = 0
StickyWheel.connectionInput = bit.bor( sm.interactable.connectionType.logic, sm.interactable.connectionType.chemical )
StickyWheel.connectionOutput = sm.interactable.connectionType.none
StickyWheel.colorNormal = sm.color.new( 0xd962d8ff )
StickyWheel.colorHighlight = sm.color.new( 0xd962d8ff )
StickyWheel.connectIcon = "chemical"
StickyWheel.connectIconScale = 0.75

StickyWheel.poseWeightCount = 1

StickyLevelSettings = {
	[1] = {
		maxStickyConnections = 9,
		maxPointDistance = 2.1,
		newPointDistance = 0.4,
		maxStickyStrength = 167,
	},
	[2] = {
		maxStickyConnections = 9,
		maxPointDistance = 2.1,
		newPointDistance = 0.4,
		maxStickyStrength = 333,
	},
	[3] = {
		maxStickyConnections = 9,
		maxPointDistance = 2.1,
		newPointDistance = 0.4,
		maxStickyStrength = 500,
	},
	[4] = {
		maxStickyConnections = 9,
		maxPointDistance = 2.1,
		newPointDistance = 0.4,
		maxStickyStrength = 1000,
	},
	[5] = {
		maxStickyConnections = 9,
		maxPointDistance = 2.1,
		newPointDistance = 0.4,
		maxStickyStrength = 1500,
	}
}

local StickyRaycastsPerTick = 9
local StickyPoseSpeedOn = 3
local StickyPoseSpeedOff = 1
local StickyDotCheckDistance = 0.05 -- Disregard the dot angle of the sticky when within this distance

local LineMaxThicknessX = 0.2175
local LineMaxThicknessY = 0.4175
local LineMinThicknessX = 0.125
local LineMinThicknessY = 0.125
local BlobMaxThicknessX = 0.5
local BlobMaxThicknessY = 0.5
local BlobMaxThicknessZ = 0.3
local BlobMinThicknessX = 0.12
local BlobMinThicknessY = 0.12
local BlobMinThicknessZ = 0.7

local PointsPerChemical = 2500
local CostPerConnection = 1

local NonStickShapes = {
	ITEMS.blk_ice,
	ITEMS.wdg_ice
}

local function StickyPowerCurve( p )
	p = 1.0 - p
	-- QuadraticEaseInOut
	if p < 0.5 then
		return 2.0 * p * p;
	end
	return ( -2.0 * p * p ) + ( 4.0 * p) - 1.0
end

function StickyWheel.getInputs( self )
	local parents = self.interactable:getParents()
	local active = false
	local chemicalContainer = nil
	if parents[2] then
		if parents[2]:hasOutputType( sm.interactable.connectionType.logic ) then
			active = parents[2]:isActive()
		end
		if parents[2]:hasOutputType( sm.interactable.connectionType.chemical ) then
			chemicalContainer = parents[2]
		end
	end
	if parents[1] then
		if parents[1]:hasOutputType( sm.interactable.connectionType.logic ) then
			active = parents[1]:isActive()
		end
		if parents[1]:hasOutputType( sm.interactable.connectionType.chemical ) then
			chemicalContainer = parents[1]
		end
	end

	return active, chemicalContainer
end

-- Server

function StickyWheel.server_onCreate( self )
	self.saved = self.storage:load()
	if self.saved == nil then
		self.saved = {}
	end
	if self.saved.chemicalPoints == nil then
		self.saved.chemicalPoints = 0
		self.saved.currentSettingsLevel = 3
	end
	if self.saved.currentSettingsLevel == nil then
		self.saved.currentSettingsLevel = 3
	end

	self.sv = {}
	if not self.sv.container then
		local container = self.shape.interactable:getContainer( 0 )
		if container then
			self.sv.container = container
		else
			self.sv.container = self.shape:getInteractable():addContainer( 0, 1, 10 )
		end
	end
	self.sv.container:setFilters( { ITEMS.obj_consumable_chemical } )

	self.sv.chemicalPoints = self.saved.chemicalPoints
	self.sv.active = false
	self.sv.dirty = false
	self.sv.savedThisTick = false
	self.network:setClientData( self.saved.currentSettingsLevel )
end

local function GetStickyWorldPosition( sticky )
	if sticky.otherShape then
		if sm.exists( sticky.otherShape ) then
			return sticky.otherShape:transformLocalPoint( sticky.otherShapeLocalPosition )
		end
	elseif sticky.otherHarvestable then
		if sm.exists( sticky.otherHarvestable ) then
			if sticky.isKinematic then
				return sticky.otherHarvestable:transformLocalPoint( sticky.otherHarvestableLocalPosition )
			end
			return sticky.worldPosition
		end
	else
		return sticky.worldPosition
	end
	return nil
end

function StickyWheel.sv_updateSaved( self )
	if self.saved.chemicalPoints ~= self.sv.chemicalPoints then
		self.saved.chemicalPoints = self.sv.chemicalPoints
		self.storage:save( self.saved )
		self.sv.savedThisTick = true
	end
end

function StickyWheel.server_onFixedUpdate( self )
	local active, chemicalContainer = self:getInputs()
	if not self.sv.active and active then
		self.shape:setPhysicsMaterial( sm.shape.material.sticky )
		self.shape:setCollisionSoundEnabled( false )
		self.sv.active = active
	elseif self.sv.active and not active then
		self.shape:setPhysicsMaterial( sm.shape.material.rubber )
		self.shape:setCollisionSoundEnabled( true )
		self.sv.active = active
	end

	-- Activate the sticky wheel with chemicals
	if active and self.sv.chemicalPoints <= 0 and sm.game.getEnableFuelConsumption() then
		if chemicalContainer then
			sm.container.beginTransaction()
			local amount = TrySpendFromConnectedContainer( chemicalContainer, obj_consumable_chemical, 1 )
			if  amount ~= 0 then
				sm.container.abortTransaction()
			else
				if sm.container.endTransaction() then
					self.sv.chemicalPoints = PointsPerChemical
				end
			end
		end
		
		if self.sv.container and ( self.sv.chemicalPoints ~= PointsPerChemical ) then
			sm.container.beginTransaction()
			sm.container.spend( self.sv.container, obj_consumable_chemical, 1, true )
			if sm.container.endTransaction() then
				self.sv.chemicalPoints = PointsPerChemical
			end
		end
	end
	self:sv_updateSaved()
	self.interactable.active = active and ( self.sv.chemicalPoints > 0 or not sm.game.getEnableFuelConsumption() )
	if self.sv.dirty then
		self.sv.dirty = false
		self.network:setClientData( self.saved.currentSettingsLevel )
		if not self.sv.savedThisTick then
			self.storage:save( self.saved )
		end
	end
	self.sv.savedThisTick = false
end

function StickyWheel.sv_n_setLevel( self, level )
	self.saved.currentSettingsLevel = level
	self.sv.dirty = true
end

function StickyWheel.client_onCreate( self )
	self.cl = {}
	self.cl.prevStickyPoseWeight = 0.0
	self.cl.stickyPoseWeight = 0.0
	self.cl.stickyConnections = {}
	self.cl.stickyRaycastIdx = 0
	self.cl.stickyEffectsArray = {}
	self.cl.currentSettingsLevel = 3
end

function StickyWheel.client_onDestroy( self )
	if self.gui then
		self.gui:destroy()
		self.gui = nil
	end
end

function StickyWheel.cl_cleanUpEffects( self, newLevel )
	if StickyLevelSettings[newLevel].maxStickyConnections < StickyLevelSettings[self.cl.currentSettingsLevel].maxStickyConnections then
		for i = StickyLevelSettings[self.cl.currentSettingsLevel].maxStickyConnections, StickyLevelSettings[newLevel].maxStickyConnections, -1 do
			local stickyEffects = self.cl.stickyEffectsArray[i]
			if stickyEffects then
				if stickyEffects.lineEffect and sm.exists( stickyEffects.lineEffect ) then
					stickyEffects.lineEffect:destroy()
				end
				if stickyEffects.blobEffect and sm.exists( stickyEffects.blobEffect ) then
					stickyEffects.blobEffect:destroy()
				end
			end
		end
	end
end

function StickyWheel.client_onClientDataUpdate( self, serverLevel, channel )
	self:cl_cleanUpEffects( serverLevel )
	self.cl.currentSettingsLevel = serverLevel
end

function StickyWheel.client_onUpdate( self, dt )
	self.cl.stickyPoseWeight = self.interactable.active and math.min( self.cl.stickyPoseWeight + dt * StickyPoseSpeedOn, 1.0 ) or math.max( self.cl.stickyPoseWeight - dt * StickyPoseSpeedOff, 0 )
	if self.cl.stickyPoseWeight ~= self.cl.prevStickyPoseWeight then
		self.interactable:setPoseWeight( 0, self.cl.stickyPoseWeight )
		self.cl.prevStickyPoseWeight = self.cl.stickyPoseWeight
	end

	self:cl_updateEffects()
end

function StickyWheel.cl_updateEffects( self )

	if self.interactable.active and self.cl.wasActive == false then
		sm.effect.playHostedEffect( "Stickywheels - On", self.interactable )
	end
	if not self.interactable.active and self.cl.wasActive then
		sm.effect.playHostedEffect( "Stickywheels - Off", self.interactable )
	end

	self.cl.wasActive = self.interactable.active

	for i = 1, StickyLevelSettings[self.cl.currentSettingsLevel].maxStickyConnections do
		local radius = sm.item.getShapeOffset( self.shape.uuid ).y -- 0.625
		local spokesDirection = self.shape.up
		local wheelDirection = self.shape.at
		local degrees = ( 360 / StickyLevelSettings[self.cl.currentSettingsLevel].maxStickyConnections ) * i
		local stickyDirection = wheelDirection:rotate( math.rad( degrees ), spokesDirection )
		local selfWorldPosition = self.shape.worldPosition + stickyDirection * radius

		local slimeLineUuid = sm.uuid.new( "70673852-7f5e-4731-8c75-c1b9fdf0008b" )
		local slimeBlobUuid = sm.uuid.new( "f7744922-3b4d-4deb-a593-129c449acd09" )
		local slimeLeftoverUuid = sm.uuid.new( "a6c6ce30-dd47-4587-b475-085d55c6a3b4" )

		local stickyColor = sm.color.new( 0.6, 0.8, 0.25 )

		local stickyEffects = self.cl.stickyEffectsArray[i]
		local stickyConnection = self.cl.stickyConnections[i]
		if stickyEffects then
			-- Update or remove effects
			if stickyConnection then
				local stickyPosition = GetStickyWorldPosition( stickyConnection )
				if stickyPosition then
					local halfwayPosition = selfWorldPosition + ( stickyPosition - selfWorldPosition ) * 0.5
					local stickyLineFromTo = stickyPosition - selfWorldPosition
					local stickyLineLength = stickyLineFromTo:length()
					local stickyLineDirection = stickyLineFromTo:safeNormalize( stickyDirection )
					stickyLineLength = math.max( stickyLineLength, FLT_EPSILON )
					local stickyScale = 1.0 - math.max( math.min( stickyLineLength / StickyLevelSettings[self.cl.currentSettingsLevel].maxPointDistance, 1.0 ), 0.0 )
					local stickyLineRotation = sm.vec3.getRotation( sm.vec3.new( 0, 0, 1 ), stickyLineDirection )

					stickyEffects.halfwayPosition = halfwayPosition
					stickyEffects.stickyPosition = stickyPosition
					stickyEffects.stickyLineRotation = stickyLineRotation
					stickyEffects.type = stickyConnection.type
					stickyEffects.normalWorld = stickyConnection.normalWorld

					if stickyEffects.lineEffect and sm.exists( stickyEffects.lineEffect ) then
						stickyEffects.lineEffect:setPosition( halfwayPosition )
						stickyEffects.lineEffect:setRotation( stickyLineRotation )
						stickyEffects.lineEffect:setScale( sm.vec3.new( lerp( LineMinThicknessX, LineMaxThicknessX, stickyScale ), lerp( LineMinThicknessY, LineMaxThicknessY, stickyScale ), stickyLineLength ) )
					end
					if stickyEffects.blobEffect and sm.exists( stickyEffects.blobEffect ) then
						stickyEffects.blobEffect:setPosition( stickyPosition )
						stickyEffects.blobEffect:setRotation( stickyLineRotation )
						local blobScaleX = lerp( BlobMinThicknessX, BlobMaxThicknessX, stickyScale )
						local blobScaleY = lerp( BlobMinThicknessY, BlobMaxThicknessY, stickyScale )
						local blobScaleZ = lerp( BlobMinThicknessZ, BlobMaxThicknessZ, stickyScale )
						stickyEffects.blobEffect:setScale( sm.vec3.new( blobScaleX, blobScaleY, blobScaleZ ) )
					end
				else
					-- Forget invalid sticky
					if stickyEffects.lineEffect and sm.exists( stickyEffects.lineEffect ) then
						stickyEffects.lineEffect:destroy()
					end
					if stickyEffects.blobEffect and sm.exists( stickyEffects.blobEffect ) then
						stickyEffects.blobEffect:destroy()
					end
					stickyEffects = nil
				end
			else
				if stickyEffects.halfwayPosition and stickyEffects.stickyLineRotation then
					sm.effect.playEffect( "Stickywheels - Snap", stickyEffects.halfwayPosition, nil, stickyEffects.stickyLineRotation )
				end

				-- Destroy old effect
				if stickyEffects.lineEffect and sm.exists( stickyEffects.lineEffect ) then
					stickyEffects.lineEffect:destroy()
				end
				if stickyEffects.blobEffect and sm.exists( stickyEffects.blobEffect ) then
					stickyEffects.blobEffect:destroy()
				end
				stickyEffects = nil
			end
		else
			-- Create new effects
			if stickyConnection then
				stickyEffects = {}
				local stickyPosition = GetStickyWorldPosition( stickyConnection )
				if stickyPosition then
					local halfwayPosition = selfWorldPosition + ( stickyPosition - selfWorldPosition ) * 0.5
					local stickyLineFromTo = stickyPosition - selfWorldPosition
					local stickyLineLength = stickyLineFromTo:length()
					local stickyLineDirection = stickyLineFromTo:safeNormalize( stickyDirection )
					stickyLineLength = math.max( stickyLineLength, FLT_EPSILON )
					local stickyScale = 1.0 - math.max( math.min( stickyLineLength / StickyLevelSettings[self.cl.currentSettingsLevel].maxPointDistance, 1.0 ), 0.0 )
					local stickyLineRotation = sm.vec3.getRotation( sm.vec3.new( 0, 0, 1 ), stickyLineDirection )

					stickyEffects.halfwayPosition = halfwayPosition
					stickyEffects.stickyPosition = stickyPosition
					stickyEffects.stickyLineRotation = stickyLineRotation
					stickyEffects.type = stickyConnection.type
					stickyEffects.normalWorld = stickyConnection.normalWorld

					stickyEffects.lineEffect = sm.effect.createEffect( "ShapeRenderable" )
					stickyEffects.lineEffect:setParameter( "uuid", slimeLineUuid )
					stickyEffects.lineEffect:setParameter( "color", stickyColor )
					stickyEffects.lineEffect:setPosition( halfwayPosition )
					stickyEffects.lineEffect:setRotation( stickyLineRotation )
					stickyEffects.lineEffect:setScale( sm.vec3.new( lerp( LineMinThicknessX, LineMaxThicknessX, stickyScale ), lerp( LineMinThicknessY, LineMaxThicknessY, stickyScale ), stickyLineLength ) )
					stickyEffects.lineEffect:start()

					stickyEffects.blobEffect = sm.effect.createEffect( "ShapeRenderable" )
					stickyEffects.blobEffect:setParameter( "uuid", slimeBlobUuid )
					stickyEffects.blobEffect:setParameter( "color", stickyColor )
					stickyEffects.blobEffect:setPosition( stickyPosition )
					stickyEffects.blobEffect:setRotation( stickyLineRotation )
					local blobScaleX = lerp( BlobMinThicknessX, BlobMaxThicknessX, stickyScale )
					local blobScaleY = lerp( BlobMinThicknessY, BlobMaxThicknessY, stickyScale )
					local blobScaleZ = lerp( BlobMinThicknessZ, BlobMaxThicknessZ, stickyScale )
					stickyEffects.blobEffect:setScale( sm.vec3.new( blobScaleX, blobScaleY, blobScaleZ ) )
					stickyEffects.blobEffect:start()

					
					if math.random(1,10)>=8 then
						sm.effect.playEffect( "Stickywheels - Splash", stickyPosition, nil, stickyLineRotation )
					end
					if stickyEffects.type == "terrainSurface" or stickyEffects.type == "terrainAsset" or stickyEffects.type == "voxelTerrain" then
						local puddleRotation = stickyEffects.stickyLineRotation
						if stickyEffects.normalWorld then
							puddleRotation = sm.vec3.getRotation( sm.vec3.new( 0, 0, 1 ), stickyEffects.normalWorld )
						end
						if math.random(1,2)==2 then
							-- sm.effect.playEffect( "Stickywheels - Puddle" , stickyEffects.stickyPosition, nil, puddleRotation, sm.vec3.one() * (math.random(1,2)*0.001) , { uuid = slimeLeftoverUuid, color = stickyColor } )
							sm.effect.playEffect( "Stickywheels - Puddle" , stickyEffects.stickyPosition, nil, puddleRotation, sm.vec3.one() * 100, { uuid = slimeLeftoverUuid, color = stickyColor } )
						end
					end
				end
			end
		end
		self.cl.stickyEffectsArray[i] = stickyEffects
	end
end

function StickyWheel.client_onFixedUpdate( self )

	if not self.interactable.active then
		self.cl.stickyConnections = {}
		self.cl.stickyRaycastIdx = 0
		return
	end

	-- Determine which indices to update
	local dirtySpheres = sm.world.getDirtySpheres( self.shape.worldPosition, StickyLevelSettings[self.cl.currentSettingsLevel].maxPointDistance )
	local stickyUpdates = {}
	local previousStickyRaycastIdx = self.cl.stickyRaycastIdx
	for stickyIdxOffset = 1, math.min( StickyLevelSettings[self.cl.currentSettingsLevel].maxStickyConnections, StickyRaycastsPerTick ) do
		self.cl.stickyRaycastIdx = math.fmod( previousStickyRaycastIdx + stickyIdxOffset - 1, StickyLevelSettings[self.cl.currentSettingsLevel].maxStickyConnections ) + 1
		-- Look for changes to the voxelTerrain
		local stickyConnection = self.cl.stickyConnections[self.cl.stickyRaycastIdx]
		if stickyConnection and stickyConnection.type == "voxelTerrain" then
			for _, dirtySphere in ipairs( dirtySpheres ) do
				if ( dirtySphere.center - stickyConnection.worldPosition ):length2() < dirtySphere.radius * dirtySphere.radius then
					self.cl.stickyConnections[self.cl.stickyRaycastIdx] = nil
					break
				end
			end
		end
		if self.cl.stickyConnections[self.cl.stickyRaycastIdx] == nil then
			stickyUpdates[#stickyUpdates+1] = self.cl.stickyRaycastIdx
		end
	end

	-- Perform spherecasts for each selected index
	local radius = sm.item.getShapeOffset( self.shape.uuid ).y -- 0.625
	local spokesDirection = self.shape.up
	local wheelDirection = self.shape.at
	local casts = {}

	local ignore = CreativeGame == nil and { hvs_loot } or {}

	for _, stickyIndex in ipairs( stickyUpdates ) do
		local degrees = ( 360 / StickyLevelSettings[self.cl.currentSettingsLevel].maxStickyConnections ) * stickyIndex
		local stickyDirection = wheelDirection:rotate( math.rad( degrees ), spokesDirection )
		local stickyEndPosition = self.shape.worldPosition + stickyDirection * ( radius + StickyLevelSettings[self.cl.currentSettingsLevel].newPointDistance )
		casts[#casts+1] = { type = "sphere",
							startPoint = self.shape.worldPosition,
							endPoint = stickyEndPosition,
							radius = 0.25,
							ignoreObject = self.shape,
							ignoreUuids = ignore
							}
	end

	local retTable = sm.physics.multicast( casts )
	local numAddedConnections = 0
	for i, stickyIndex in ipairs( stickyUpdates ) do
		local success = retTable[i][1]
		local result = retTable[i][2]
		if success then
			local addedConnection = false
			self.cl.stickyConnections[stickyIndex], addedConnection = self:cl_createUpdateSticky( result, stickyIndex )
			if addedConnection then
				numAddedConnections = numAddedConnections + 1
			end
		end
	end

	-- Consume chemical points
	if sm.isHost then
		self.sv.chemicalPoints = math.max( self.sv.chemicalPoints - CostPerConnection * numAddedConnections, 0 )
	end

	-- Check stress on sticky and apply impulse
	local stickyConnections = {}
	for i = 1, StickyLevelSettings[self.cl.currentSettingsLevel].maxStickyConnections do
		local degrees = ( 360 / StickyLevelSettings[self.cl.currentSettingsLevel].maxStickyConnections ) * i
		local stickyDirection = wheelDirection:rotate( math.rad( degrees ), spokesDirection )
		local selfWorldPosition = self.shape.worldPosition + stickyDirection * radius
		local stickyConnection = self.cl.stickyConnections[i]
		if stickyConnection then
			local otherWorldPosition = GetStickyWorldPosition( stickyConnection )
			if otherWorldPosition then
				local stickyVector = otherWorldPosition - selfWorldPosition
				local distanceToPoint = stickyVector:length()
				local stickyDot = stickyDirection:dot( stickyVector:safeNormalize( stickyDirection ) )
				local distanceOk = distanceToPoint <= StickyLevelSettings[self.cl.currentSettingsLevel].maxPointDistance
				local dotAngleOk = stickyDot >= -0.5 or distanceToPoint <= StickyDotCheckDistance
				if distanceOk and dotAngleOk then
					stickyConnections[i] = stickyConnection
					if stickyVector:length() > FLT_EPSILON then
						stickyDirection = stickyVector:normalize()
						local stickyPower = math.max( math.min( distanceToPoint / StickyLevelSettings[self.cl.currentSettingsLevel].maxPointDistance, 1.0 ), 0.0 )
						local stickyStrength = StickyLevelSettings[self.cl.currentSettingsLevel].maxStickyStrength * StickyPowerCurve( stickyPower )

						if stickyConnection.otherShape and stickyConnection.otherShape.body:isDynamic() then
							local massFraction = math.min( stickyConnection.otherShape.mass / self.shape.mass, 2.0 )
							local otherStickyStrength = stickyStrength * massFraction
							local offset = otherWorldPosition - stickyConnection.otherShape.worldPosition
							sm.physics.applyImpulse( stickyConnection.otherShape, -stickyDirection * otherStickyStrength, true, offset )
						end

						local offset = selfWorldPosition - self.shape.worldPosition
						sm.physics.applyImpulse( self.shape, stickyDirection * stickyStrength, true, offset )
					end
				end
			end
		end
	end
	self.cl.stickyConnections = stickyConnections
end

function StickyWheel.cl_createUpdateSticky( self, result, compareIndex )
	local newStickyConnection = nil
	if result.type == "body" then
		local resultBody = result:getBody()
		local resultShape = result:getShape()
		-- Only stick to static bodies. Avoid stickying to own creation and non stick shapes.
		if resultBody:isStatic() and resultBody:getCreationId() ~= self.shape.body:getCreationId() and not isAnyOf( resultShape.uuid, NonStickShapes ) then
			newStickyConnection = {}
			newStickyConnection.type = result.type
			newStickyConnection.otherShape = resultShape
			newStickyConnection.otherShapeLocalPosition = newStickyConnection.otherShape:transformPoint( result.pointWorld )
			if resultBody:isStatic() then
				newStickyConnection.normalWorld = result.normalWorld
			end
		end
	elseif result.type == "harvestable" then
		newStickyConnection = {}
		newStickyConnection.type = result.type
		newStickyConnection.otherHarvestable = result:getHarvestable()
		newStickyConnection.worldPosition = result.pointWorld
		newStickyConnection.normalWorld = result.normalWorld
		newStickyConnection.isKinematic = result:getHarvestable():isKinematic()
		if newStickyConnection.isKinematic then
			newStickyConnection.otherHarvestableLocalPosition = newStickyConnection.otherHarvestable:transformPoint( result.pointWorld )
		end
	elseif result.type == "terrainSurface" or result.type == "terrainAsset" or result.type == "voxelTerrain" then
		newStickyConnection = {}
		newStickyConnection.type = result.type
		newStickyConnection.worldPosition = result.pointWorld
		newStickyConnection.normalWorld = result.normalWorld
	end

	-- Update the sticky to the closest distance
	if compareIndex then
		local radius = sm.item.getShapeOffset( self.shape.uuid ).y --0.625
		local spokesDirection = self.shape.up
		local wheelDirection = self.shape.at
		local degrees = ( 360 / StickyLevelSettings[self.cl.currentSettingsLevel].maxStickyConnections ) * compareIndex
		local stickyDirection = wheelDirection:rotate( math.rad( degrees ), spokesDirection )
		local oldStickyConnection = self.cl.stickyConnections[compareIndex]
		if oldStickyConnection then
			local oldStickyWorldPosition = GetStickyWorldPosition( oldStickyConnection )
			if oldStickyWorldPosition then
				local stickyWheelPosition = self.shape.worldPosition + stickyDirection * radius

				local oldDistance = ( stickyWheelPosition - oldStickyWorldPosition ):length()
				local newDistance = ( stickyWheelPosition - result.pointWorld ):length()
				if oldDistance < newDistance then
					return oldStickyConnection, false
				end
			end
		end
	end
	return newStickyConnection, newStickyConnection ~= nil
end

function StickyWheel.client_canInteract( self )
	return true
end

function StickyWheel.client_canCarry( self )
	local chemicalContainer = self.shape.interactable:getContainer( 0 )
	if chemicalContainer then
		return not chemicalContainer:isEmpty()
	end
	return true
end

function StickyWheel.client_onInteract( self, character, state )
	if state == true then
		self.gui = sm.gui.createEngineGui()

		self.gui:setText( "Name", "#{CONTROLLER_STICKY_WHEELS_TITLE}" )
		self.gui:setText( "SubTitle", "" )
		self.gui:setText( "Interaction", "#{CONTROLLER_STICKY_WHEELS_INSTRUCTIONS}" )
		self.gui:setOnCloseCallback( "cl_onGuiClosed" )
		self.gui:setSliderCallback( "Setting", "cl_onSliderChange" )
		self.gui:setIconImage( "Icon", self.shape:getShapeUuid() )

		local chemicalContainer = self.shape.interactable:getContainer( 0 )
		if chemicalContainer then
			self.gui:setContainer( "Fuel", chemicalContainer )
		end

		self.gui:setSliderData( "Setting", #StickyLevelSettings, self.cl.currentSettingsLevel - 1 )
		self.gui:setSliderRangeLimit( "Setting", #StickyLevelSettings )
		self.gui:setData( "SliderCaptions", { min = "#{SLIDER_MIN}", max = "#{SLIDER_MAX}", center = "#{BALANCED_CAPS}" } )

		self.gui:open()
	end
end

function StickyWheel.cl_onGuiClosed( self )
	if self.gui then
		self.gui:destroy()
		self.gui = nil
	end
end

function StickyWheel.cl_onSliderChange( self, sliderName, sliderPos )
	self:cl_cleanUpEffects( sliderPos + 1 )
	self.cl.currentSettingsLevel = sliderPos + 1
	self.network:sendToServer( "sv_n_setLevel", self.cl.currentSettingsLevel )
end

function StickyWheel.client_getAvailableParentConnectionCount( self, connectionType )
	if bit.band( connectionType, self.connectionInput ) ~= 0 then
		return 1 - #self.interactable:getParents( connectionType )
	end
	return 0
end
