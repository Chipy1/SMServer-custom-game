dofile( "$SURVIVAL_DATA/Scripts/game/util/PackerPumpArea.lua" )

MininghubSmelterPacker = class( nil )
MininghubSmelterPacker.isSaveObject = true

local StartupTicks = 5 * 40
local SpawnDelayTicks = 1 * 40
local SpawnOffset = sm.vec3.new( -1, -1, -1 ) -- Just getting the parts out of the center. We could just as well move the scriptable node in the tile!
local Filter = sm.areaTrigger.filter.staticBody + sm.areaTrigger.filter.dynamicBody

function MininghubSmelterPacker.server_onCreate( self )
	self.sv = {}
	self.sv.saved = self.storage:load()
	if self.sv.saved == nil then
		self.sv.saved = {}
		self.sv.saved.queue = {}
		self.sv.saved.currentPackage = nil
		self.sv.saved.position = self.params.node.position
		self:sv_save()
	end
	self.sv.cellPos = { x = math.floor( self.sv.saved.position.x / 64 ), y = math.floor( self.sv.saved.position.y / 64 ) }
	self.sv.tileStorageKey = TileStorageManager.Sv_GetTileStorageKeyFromPosition( self.scriptableObject.world, self.sv.saved.position )
	self.sv.tickCounter = 0
	self.sv.startupDone = false
	self.sv.isSpawning = false
	self.sv.packingAreaInitialized = false
end

function MininghubSmelterPacker.sv_save( self )
	self.storage:save( self.sv.saved )
end

function MininghubSmelterPacker.sv_checkQueue( self )
	local value = TileStorageManager.Sv_GetValueInSubTable( self.sv.tileStorageKey, MININGHUB_CRAFTERS_TABLE, "smelter" )
	if value and not IsEmptyTable( value ) then
		for _, data in ipairs( value ) do
			self.sv.saved.queue[#self.sv.saved.queue + 1] = data
		end
		TileStorageManager.Sv_SetValueInSubTable( self.sv.tileStorageKey, MININGHUB_CRAFTERS_TABLE, "smelter", {} )
	end
end

function MininghubSmelterPacker.sv_initPackingArea( self )

	local xMin, xMax, yMin, yMax = GetTileRanges( self.sv.saved.position, self.scriptableObject.world:getId() )
	local packingNode = nil
	local locGetNodesByTag = sm.cell.getNodesByTag
	for x = xMin, xMax do
		for y = yMin, yMax do
			local areaNodes = locGetNodesByTag( x, y, "VOLUME" )
			for _, node in ipairs( areaNodes ) do
				if node.params.name == "PackerPumpArea" then
					packingNode = node
					goto found
				end
			end
		end
	end

	::found::
	if packingNode then
		self.sv.packerPumpArea = PackerPumpArea()
		self.sv.packerPumpArea:sv_init( packingNode.position, packingNode.scale * 0.5, packingNode.rotation, Filter )
		self.network:setClientData( { position = packingNode.position, orientation = packingNode.rotation, scale = packingNode.scale }, 1 )

	else
		--TODO: Make sure node is used
		local nodeFallbackPositionOffset = sm.vec3.new( -45.7462, 0.245697, 93.67 )
		local nodeFallbackScale = sm.vec3.new( 15.5672, 9.15992, 17.1197 )
		local nodeFallbackOrientation = sm.quat.new( 0, 0.707107, 0.707107, 0 ):normalize()

		self.sv.packerPumpArea = PackerPumpArea()
		self.sv.packerPumpArea:sv_init( self.sv.saved.position - nodeFallbackPositionOffset, nodeFallbackScale * 0.5, nodeFallbackOrientation, Filter )
		self.network:setClientData( { position = self.sv.saved.position - nodeFallbackPositionOffset, orientation = nodeFallbackOrientation, scale = nodeFallbackScale }, 1 )
		sm.log.error( "Could not initialize packing area because PackerPumpArea node could not be found!" )
	end
	self.sv.packingAreaInitialized = true
end

function MininghubSmelterPacker.server_onFixedUpdate( self )
	if (not sm.exists( self.scriptableObject.world )) or (not self.scriptableObject.world:isCellLoadedServer( self.sv.cellPos.x, self.sv.cellPos.y )) then
		return
	end
	if self.scriptableObject.world:isCellLoadedServer( self.sv.cellPos.x, self.sv.cellPos.y ) and not self.sv.packingAreaInitialized then
		self:sv_initPackingArea()
	end

	self:sv_checkQueue()
	if self.sv.saved.currentPackage == nil then
		if not IsEmptyTable( self.sv.saved.queue ) then
			self.sv.saved.currentPackage = self.sv.saved.queue[1]
			table.remove( self.sv.saved.queue, 1 )
			self:sv_save()
		end
	end

	if self.sv.saved.currentPackage == nil then
		return
	end
	if self.sv.tickCounter == 0 and not self.sv.startupDone then
		sm.effect.playEffect( "Smelter - PackerOutput", self.sv.saved.position )
		-- sm.effect.playEffect( "Miningvault - Smelter_glow", self.sv.saved.position + sm.vec3.new(0,0,-14), nil, sm.quat.angleAxis(math.rad(90),sm.vec3.new(1,0,0)), nil )
		self.sv.startupDone = true
	end
	self.sv.tickCounter = self.sv.tickCounter + 1
	if not self.sv.isSpawning and self.sv.tickCounter >= StartupTicks then
		self.sv.isSpawning = true
		self.sv.tickCounter = 0
		-- sm.effect.playEffect( "Miningvault - Smelter_smoke", self.sv.saved.position )
	end
	if self.sv.isSpawning and self.sv.tickCounter >= SpawnDelayTicks then
		local rng = math.random() * math.pi * 2
		local newShape = sm.shape.createPart( self.sv.saved.currentPackage, self.sv.saved.position + SpawnOffset, sm.quat.identity(), true, true )
		sm.physics.applyTorque( newShape.body, sm.vec3.new( math.sin( rng ), math.cos( rng ), 0 ) * newShape.mass * 3, true )

		self.sv.tickCounter = 0
		self.sv.saved.currentPackage = nil
		if not IsEmptyTable( self.sv.saved.queue ) then
		-- sm.effect.playEffect( "Smelter - Spawn", self.sv.saved.position )
		else
			self.sv.isSpawning = false
			self.sv.startupDone = false
		end
		
        self:sv_save()
	end
end

function MininghubSmelterPacker.client_onClientDataUpdate( self, data, channel )
	self:cl_initPumpArea( data.position, data.orientation, data.scale )
end

function MininghubSmelterPacker.cl_initPumpArea( self, position, orientation, scale )
	self.cl = {}
	self.cl.packerPumpArea = PackerPumpArea()
	self.cl.packerPumpArea:cl_init( position, scale * 0.5, orientation, Filter )
end
