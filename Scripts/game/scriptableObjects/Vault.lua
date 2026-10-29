dofile( "$SURVIVAL_DATA/Scripts/game/managers/QuestManager.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/managers/ProgressionManager.lua" )

ITEM_VALUES = {
	[tostring( ITEMS.obj_resource_wonkstonks )] = 50,

	[tostring( ITEMS.obj_nugget_t1 )] = 1,
	[tostring( ITEMS.obj_nugget_t2 )] = 2,
	[tostring( ITEMS.obj_nugget_t3 )] = 5,
	[tostring( ITEMS.obj_nugget_t4 )] = 10,
	[tostring( ITEMS.obj_nugget_t5 )] = 20,

	[tostring( ITEMS.obj_castedpart_t1 )] = 500,
	[tostring( ITEMS.obj_castedpart_t2 )] = 1000,
	[tostring( ITEMS.obj_castedpart_t3 )] = 2000,
	[tostring( ITEMS.obj_castedpart_t4 )] = 3000,
	[tostring( ITEMS.obj_castedpart_t5 )] = 5000,

	[tostring( ITEMS.obj_resource_coralium )] = 25,
	[tostring( ITEMS.obj_resource_refinedcoralium )] = 200,
	[tostring( ITEMS.obj_resource_nimbolium )] = 10,
	[tostring( ITEMS.obj_resource_refinednimbolium )] = 400,
	[tostring( ITEMS.obj_resource_lemonium )] = 50,
	[tostring( ITEMS.obj_resource_refinedlemonium )] = 1000,
	[tostring( ITEMS.obj_resource_sapphire )] = 300,
	[tostring( ITEMS.obj_resource_refinedsapphire )] = 5000,
	[tostring( ITEMS.obj_resource_crystal )] = 100,
	[tostring( ITEMS.obj_resource_refinedcrystal )] = 10000,

	[tostring( ITEMS.obj_jewel_01 )] = 2500,
	[tostring( ITEMS.obj_jewel_02 )] = 10000,
	[tostring( ITEMS.obj_jewel_03 )] = 25000,
	[tostring( ITEMS.obj_jewel_04 )] = 100000,

	[tostring( ITEMS.obj_artifact_fossil01 )] = 5000,
	[tostring( ITEMS.obj_artifact_fossil05 )] = 5000,
	[tostring( ITEMS.obj_artifact_fossil08 )] = 5000,
	[tostring( ITEMS.obj_artifact_fossil09 )] = 5000,
	[tostring( ITEMS.obj_artifact_fossil11 )] = 5000,
	[tostring( ITEMS.obj_artifact_fossil13 )] = 5000,
}

CASTED_PARTS = {
	[tostring( ITEMS.obj_castedpart_t1 )] = true,
	[tostring( ITEMS.obj_castedpart_t2 )] = true,
	[tostring( ITEMS.obj_castedpart_t3 )] = true,
	[tostring( ITEMS.obj_castedpart_t4 )] = true,
	[tostring( ITEMS.obj_castedpart_t5 )] = true,
}

VAULT_MILESTONES = {
	0,
	100000,
	250000
}

WEDGE_TO_BLOCK = {
}

-- Big vault text display
local VaultTextScaleNormal = 18
local VaultTextScaleLarge = 14        -- shrink the font once the amount goes over 999.999
local LargeNumberThreshold = 999999   -- 999.999
local MaxDisplayTotal = 999999999     -- cap the displayed amount to 999.999.999

Vault = class( nil )
Vault.isSaveObject = true

function Vault.server_onCreate( self )
	self.sv = {}
	self.sv.saved = self.storage:load() or {}
	if self.params then
		if self.params.node then
			self.sv.saved.position = self.params.node.position
			self.sv.saved.rotation = self.params.node.rotation
			self.sv.saved.scale = self.params.node.scale
		end
	end
	assert( self.sv.saved.position )
	assert( self.sv.saved.rotation )
	assert( self.sv.saved.scale )
	self.sv.areaShapes = {}
	self.sv.areaBodies = {}
	self.sv.trackedShapes = {}

	self.sv.countTick = -1
	self.sv.vaultArea = sm.areaTrigger.createBox( self.sv.saved.scale / 2, self.sv.saved.position, self.sv.saved.rotation, sm.areaTrigger.filter.staticBody )
	self.sv.vaultArea:setIncludeShapesInContent( true )
	self.sv.vaultArea:bindOnEnter( "sv_trigger_onEnterVaultArea" )
	self.sv.vaultArea:bindOnExit( "sv_trigger_onExitVaultArea" )
	self.sv.tileStorageKey = TileStorageManager.Sv_GetTileStorageKeyFromPosition( self.scriptableObject.world, self.sv.saved.position )

	-- The big vault text only appears once the mininghub is fully activated (the moment the lights turn on).
	if TileStorageManager.Sv_SyncedGetValueInSubTable( self.sv.tileStorageKey, TILESTORAGE_FLAGS_TABLE, "minehub:lights.activated" ) == true then
		self.network:setClientData( {}, 2 )
	else
		QuestManager.Sv_SubscribeEvent( "mininghub_lights_on", self.scriptableObject, "sv_e_onMininghubLightsOn" )
	end

	QuestManager.Sv_SubscribeEvent( QuestEvent.VaultQuotaReached, self.scriptableObject, "sv_e_onQuotaReached" )

	self:sv_count()
	self.network:setClientData( self.sv.saved.position, 3 )
	self.storage:save( self.sv.saved )
end

function Vault.sv_e_onMininghubLightsOn( self )
	self.network:setClientData( {}, 2 )
end

function Vault.sv_e_onQuotaReached( self )
	EffectManager.Sv_ActivateEventEffect( self.scriptableObject.world, "effectEvent.vaultQuotaReached", self.sv.saved.position )
end

function Vault.client_onCreate( self )
	self.cl = {}
	self.cl.bigvault_textEffect = sm.effect.createEffect( "Mininghub - VaultTextBig" )
	local rotation = sm.quat.angleAxis( math.pi / 2, sm.vec3.new( 1, 0, 0 ) )
	rotation = rotation * sm.quat.angleAxis( math.pi / 2, sm.vec3.new( 0, 1, 0 ) )
	self.cl.bigvault_textEffect:setRotation( rotation )
	self.cl.bigvault_textEffect:setParameter( "Color", sm.color.new( "ffb119" ) )
	self.cl.bigvault_textEffect:setParameter( "ASG", sm.vec3.new( 0, 0, 1 ) )
	self.cl.bigvault_textEffect:setScale( sm.vec3.new( VaultTextScaleNormal, VaultTextScaleNormal, VaultTextScaleNormal ) )
end

function Vault.sv_trigger_onEnterVaultArea( self )
	if sm.game.getCurrentTick() > self.sv.countTick then
		self:sv_count()
	end
end

function Vault.sv_trigger_onExitVaultArea( self )
	if sm.game.getCurrentTick() > self.sv.countTick then
		self:sv_count()
	end
end

function Vault.server_onFixedUpdate( self, dt )
	if not IsEmptyTable( self.sv.areaBodies ) then
		for _, body in ipairs( self.sv.areaBodies ) do
			if sm.exists( body ) and body:hasChanged( self.sv.countTick ) then
				sm.event.sendToScriptableObject( self.scriptableObject, "sv_count" ) -- delay by one tick to avoid issues with bodies splitting and triggering onEnterVaultArea
				break
			end
		end
	end
end

-- 0 is bottom of the shape, 1 is top of the shape
local placementEffectOffset = 1.0
local barPlacementEffectOffset = 0.0
local textEffectOffset = 0.55
local barTextEffectOffset = 0.55
local textNegativeEffectOffset = 0.35
local additionEffectColor = sm.color.new( "5ef16eff" )
local removalEffectColor = sm.color.new( "ec1313ff" )

local function GetShapeEffectPosition( shape, offsetFraction )
	local topOffset = shape.worldRotation * sm.vec3.new( 0, shape:getBoundingBox().y * 0.5, 0 )
	return shape.worldPosition + topOffset * lerp( -1, 1, offsetFraction )
end

function Vault.sv_count( self )
	if sm.game.getCurrentTick() <= self.sv.countTick then
		return
	end

	-- Get shape contents from the area trigger
	local allContents = self.sv.vaultArea:getContents()
	local shapeContents = {}
	local bodies = {}
	for _, result in ipairs( allContents ) do
		if type( result ) == "Body" then
			if not result:isOnLift() then
				bodies[#bodies+1] = result
			end
		elseif type( result ) == "Shape" then
			if not result:getBody():isOnLift() then
				shapeContents[#shapeContents+1] = result
			end
		end
	end
	self.sv.areaShapes = shapeContents
	self.sv.areaBodies = bodies
	if IsEmptyTable( self.sv.areaShapes ) then
		return -- Assuming Vault has been unloaded!
	end

	-- effect handling for Shapes, not-block/wedge
	if self.sv.countTick < 0 and IsEmptyTable( self.sv.trackedShapes ) then --init
		for _, shape in ipairs( self.sv.areaShapes ) do
			if not shape.isBlock and not shape.isWedge then
				local shapeId = shape.id
				local itemUuid
				if sm.shape.getIsStackable( shape.uuid ) then
					itemUuid = tostring( shape.stackedItem )
				else
					itemUuid = tostring( shape.uuid )
				end
				if ITEM_VALUES[itemUuid] then
					self.sv.trackedShapes[shapeId] = { pos = shape:getWorldPosition(), effectPos = GetShapeEffectPosition( shape, textNegativeEffectOffset ), value = ITEM_VALUES[itemUuid] or 0
					}
				end
			end
		end
	else
		local currentShapes = {}
		local effectBatch = {}

		-- Find new shapes and update tracked shapes
		for _, shape in ipairs( self.sv.areaShapes ) do
			if not shape.isBlock and not shape.isWedge then
				local shapeId = shape.id
				local itemUuid
				if sm.shape.getIsStackable( shape.uuid ) then
					itemUuid = tostring( shape.stackedItem )
				else
					itemUuid = tostring( shape.uuid )
				end
				if ITEM_VALUES[itemUuid] then
					currentShapes[shapeId] = true
					if not self.sv.trackedShapes[shapeId] then
						local playEffectArgs = {}
						local isCastedPart = CASTED_PARTS[itemUuid] ~= nil
						local effectRot = shape.worldRotation * sm.quat.rotNegX90()

						local textPos = GetShapeEffectPosition( shape, isCastedPart and barTextEffectOffset or textEffectOffset )
						table.insert( playEffectArgs, { "Miningvault - AmmountText", textPos, nil, effectRot, nil, { TextContent = "a"..FormatVaultNumber( ITEM_VALUES[itemUuid] ), Color = additionEffectColor }, 0 } )

						local placementPos = GetShapeEffectPosition( shape, isCastedPart and barPlacementEffectOffset or placementEffectOffset )
						local placementEffectName = isCastedPart and "Miningvault - placementbar01" or "Miningvault - placement01"
						table.insert( playEffectArgs, { placementEffectName, placementPos, nil, effectRot, nil, { shapeId = shapeId }, 0 } )

						table.insert( effectBatch, {
							pos = shape:getWorldPosition(),
							playEffectArgs = playEffectArgs,
						} )
					end
					self.sv.trackedShapes[shapeId] = { pos = shape:getWorldPosition(), effectPos = GetShapeEffectPosition( shape, textNegativeEffectOffset ), value = ITEM_VALUES[itemUuid] }
				end
			end
		end

		-- Check for removed shapes
		for shapeId, trackedShape in pairs( self.sv.trackedShapes ) do
			if not currentShapes[shapeId] then
				table.insert( effectBatch, {
					pos = trackedShape.pos, playEffectArgs = {
						{ "Miningvault - AmountTextNegative", trackedShape.effectPos, nil, nil, nil, { TextContent = "a"..FormatVaultNumber( trackedShape.value ), Color = removalEffectColor }, 0 }
					},
				} )
				self.sv.trackedShapes[shapeId] = nil
			end
		end

		local playerPositions = {}
		local players = sm.player.getAllPlayers()
		for _, player in ipairs( players ) do
			if player.character and player.character:getWorld() == self.scriptableObject.world then
				table.insert( playerPositions, { playerPos = player.character.worldPosition, effects = {} } )
			end
		end

		--move each effect to to the batch of the closest player
		for _, effectData in ipairs( effectBatch ) do
			local closestDist = nil
			local closestPlayer = nil
			for _, playerData in ipairs( playerPositions ) do
				local dist = sm.vec3.getDistanceSquared( effectData.pos, playerData.playerPos )
				if closestDist == nil or dist < closestDist then
					closestDist = dist
					closestPlayer = playerData
				end
			end
			if closestPlayer then
				table.insert( closestPlayer.effects, { playEffectArgs = effectData.playEffectArgs, distance = closestDist } )
			end
		end

		for _, playerData in ipairs( playerPositions ) do
			-- sort each player's effects by distance
			table.sort( playerData.effects, function( a, b ) return a.distance < b.distance end )
			local delay = 0
			for _, effect in ipairs( playerData.effects ) do
				for _, args in ipairs( effect.playEffectArgs ) do
					args[7] = -delay
					sm.effect.playEffect( unpack( args ) )
				end
				delay = delay + 0.2
			end
		end
	end

	-- todo maybe handle effects together with counting total

	self.sv.countTick = sm.game.getCurrentTick()
	
	local valuables = {}
	local total = 0
	for _, shape in ipairs( self.sv.areaShapes ) do
		local itemUuid
		local count
		local value
		if shape.isBlock then
			itemUuid = tostring( shape.uuid )
			local size = shape:getBoundingBox() * 4
			count = size.x * size.y * size.z
			value = ITEM_VALUES[itemUuid]
		elseif shape.isWedge then
			itemUuid = WEDGE_TO_BLOCK[tostring( shape.uuid )]
			local size = shape:getBoundingBox() * 4
			count = ( size.x * size.y * size.z ) / 2
			value = itemUuid and ITEM_VALUES[itemUuid] or nil
		else
			if sm.shape.getIsStackable( shape.uuid ) then
				itemUuid = tostring( shape.stackedItem )
				count = shape.stackedAmount
			else
				itemUuid = tostring( shape.uuid )
				count = 1
			end
			value = ITEM_VALUES[itemUuid]
		end
		if value then
			valuables[itemUuid] = ( valuables[itemUuid] or 0 ) + count
			total = total + value * count

			--achievement vault

			sm.achievement.setf("e2e3fc16-0769-4623-b99e-ca0d184aee47", total,nil)
		end
	end

	local items = {}
	for k, v in pairs( valuables ) do
		local sum = ( ITEM_VALUES[k] or 0 ) * v
		items[#items+1] = { uuid = k, count = v, sum = sum }
	end
	table.sort( items, function( a, b ) return a.sum == b.sum and a.count > b.count or a.sum > b.sum end )

	local total = 0
	for i = 1, #items do
		local item = items[i]
		local value = ITEM_VALUES[item.uuid]
		assert( value )
		if value then
			total = total + item.count * value
		end
	end

	self.network:setClientData( total, 1 )
	ProgressionManager.Sv_SetVaultTotal( total )
	QuestManager.Sv_SendEvent( QuestEvent.VaultTotalUpdated, { total = total } )

	local currentVaultMilestone = TileStorageManager.Sv_GetValue( self.sv.tileStorageKey, "vaultMilestone" ) or 0
	if total >= ( VAULT_MILESTONES[currentVaultMilestone] or 0 ) then
		for index, milestone in ipairs( VAULT_MILESTONES ) do
			if total >= milestone and index > currentVaultMilestone then
				TileStorageManager.Sv_SetValue( self.sv.tileStorageKey, "vaultMilestone", index )
			end
		end
	end
end

function Vault.client_onClientDataUpdate( self, data, channel )
	if channel == 1 then
		local scale = data > LargeNumberThreshold and VaultTextScaleLarge or VaultTextScaleNormal
		self.cl.bigvault_textEffect:setScale( sm.vec3.new( scale, scale, scale ) )
		self.cl.bigvault_textEffect:setParameter( "TextContent", "a"..FormatVaultNumber( data ).."\n" )
	elseif channel == 2 then
		self.cl.bigvault_textEffect:start()
	else
		self.cl.bigvault_textEffect:setPosition( data + sm.vec3.new( 47.35, 0.5, 10.95 ) )
	end
end
