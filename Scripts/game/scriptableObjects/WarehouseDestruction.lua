dofile( "$SURVIVAL_DATA/Scripts/game/survival_constants.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/survival_units.lua" )
dofile( "$CHALLENGE_DATA/Scripts/challenge/world_util.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/managers/WarehouseManager.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/managers/HudManager.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/managers/WorldManager.lua" )

WarehouseDestruction = class( nil )
WarehouseDestruction.isSaveObject = true

local FireWallTickDelay = 40 * 5.75
local NearWarehouseDistance = 360.0

local CameraShakeBurstInterval = 40 * 60 * 2 --2 minutes

local OverrideRenderSettings = "$GAME_DATA/Render/RenderSettings/World/world_warehouse_countdown.rendersettings"

local WallEffectDistance = 110.0
local WallSpeed = 21.0

local ExplosionActivationDelay = 40 * 1

local ExplosionState = {
	LOADING = 1,
	READY = 2,
	PLAYING = 3,
	MISSED = 4
}

--[[ Server ]]
function WarehouseDestruction.server_onCreate( self )
	self.sv = {}
	self.sv.saved = self.storage:load() or {}
	self.sv.destroyed = false

	local countdownTicks = WAREHOUSE_DESTRUCTION_TICKS
	if self.params then
		if self.params.warehouseIndex then
			self.sv.saved.warehouseIndex = self.params.warehouseIndex
		end
		if self.params.countdownTicks then
			countdownTicks = self.params.countdownTicks
		end
	end

	local delayedDestructionTime = countdownTicks + FireWallTickDelay
	if self.sv.saved.fireWallTick == nil then self.sv.saved.fireWallTick = sm.game.getCurrentTick() + countdownTicks end
	if self.sv.saved.destructionTick == nil then self.sv.saved.destructionTick = sm.game.getCurrentTick() + delayedDestructionTime end

	local sharedData = { fireWallTick = self.sv.saved.fireWallTick, destructionTick = self.sv.saved.destructionTick, warehouseIndex = self.sv.saved.warehouseIndex }
	self.scriptableObject.publicData = sharedData
	self.network:setClientData( sharedData, 1 )
	if self.sv.saved.effectStartTick then
		self.network:setClientData( { startTick = self.sv.saved.effectStartTick }, 2 )
	end
	self.storage:save( self.sv.saved )
end

function WarehouseDestruction.server_onFixedUpdate( self, dt )
	if self.sv.saved.effectStartTick then
		local currentTick = sm.game.getCurrentTick()
		if currentTick >= self.sv.saved.effectStartTick + 40 * 60 * 10 then
			self.scriptableObject:destroy()
		end
		return
	end
	if self.sv.destroyed then return end
	local currentTick = sm.game.getCurrentTick()
	if currentTick >= self.sv.saved.destructionTick then
		self.sv.destroyed = true
		WarehouseManager.Sv_DestroyWarehouse( self.sv.saved.warehouseIndex )
		self:sv_startExplosion( {} )
	end
end

function WarehouseDestruction.sv_startExplosion( self, params )
	local warehouse = WarehouseManager.Sv_GetWarehouseFromIndex( self.sv.saved.warehouseIndex )
	if not warehouse then
		sm.log.error( "WarehouseDestruction: Could not find warehouse with index ", self.sv.saved.warehouseIndex )
		self.scriptableObject:destroy()
		return
	end

	local zeroCell = warehouse.zeroCell
	if not zeroCell then
		sm.log.error( "WarehouseDestruction: Warehouse with index ", self.sv.saved.warehouseIndex, " does not have a zero cell" )
		warehouse.countdownEvent = nil
		self.scriptableObject:destroy()
		return
	end

	local startTick = sm.game.getCurrentTick() + ExplosionActivationDelay

	self.sv.saved.effectStartTick = startTick
	self.storage:save( self.sv.saved )

	self.network:setClientData( { startTick = startTick }, 2 )
	sm.game.pauseSaving( "warehouseExplosion_" .. warehouse.tileStorageKey, 40 * 60 )
end

-- Effect server callback
function WarehouseDestruction.sv_e_blowUpWarehouseFloor( self, params, callbackData )
	local warehouse = WarehouseManager.Sv_GetWarehouseFromIndex( self.sv.saved.warehouseIndex )
	local world = warehouse.world
	local zeroCell = warehouse.zeroCell

	TileStorageManager.Sv_SyncedSetValueInSubTable( warehouse.tileStorageKey, TILESTORAGE_FLAGS_TABLE, params.explosion, true )
	TileStorageManager.Sv_Save()

	local xMin, xMax, yMin, yMax = GetTileRangesFromCell( zeroCell.x, zeroCell.y, world.id )
	self.network:sendToClients( "cl_n_reloadTile", { xMin = xMin, xMax = xMax, yMin = yMin, yMax = yMax, world = world, explosion = params.explosion } )

	if params.explosion == "destroyed" then
		sm.game.resumeSaving( "warehouseExplosion_" .. warehouse.tileStorageKey )
		warehouse.countdownEvent = nil
	end
end

--[[ Client ]]
function WarehouseDestruction.client_onCreate( self )
	self.cl = {}
	self.cl.eventTimer = NotificationManager.Cl_CreateEventTimer( HudManager.Priority.WarehouseCountdown, "explosion" )
	self.cl.dangerZoneBorder = HudManager.Cl_CreateBorder( HudManager.Priority.WarehouseCountdown, HudManager.BorderType.Alert )

	self.cl.fireWallDistance = 0
	self.cl.explosionState = nil
end

function WarehouseDestruction.client_onDestroy( self )
	if self.cl.eventTimer then
		self.cl.eventTimer:destroy()
		self.cl.eventTimer = nil
	end
	if self.cl.dangerZoneBorder then
		self.cl.dangerZoneBorder:destroy()
		self.cl.dangerZoneBorder = nil
	end
	if self.cl.fireWallEffect then
		if sm.exists( self.cl.fireWallEffect ) then
			self.cl.fireWallEffect:destroy()
		end
		self.cl.fireWallEffect = nil
	end

	if self.cl.fireWallAudio then
		if sm.exists( self.cl.fireWallAudio ) then
			self.cl.fireWallAudio:destroy()
		end
		self.cl.fireWallAudio = nil
	end

	if self.cl.fallingDustEffect then
		if sm.exists( self.cl.fallingDustEffect ) then
			self.cl.fallingDustEffect:destroy()
		end
		self.cl.fallingDustEffect = nil
	end
	if self.cl.fallingDustEffectBurst then
		if sm.exists( self.cl.fallingDustEffectBurst ) then
			self.cl.fallingDustEffectBurst:destroy()
		end
		self.cl.fallingDustEffectBurst = nil
	end

	-- Explosion cleanup
	if self.cl.explosionEffect and sm.exists( self.cl.explosionEffect ) then
		self.cl.explosionEffect:destroy()
	end
	if self.cl.explosionEffectCellHandle then
		self.cl.explosionEffectCellHandle:release()
	end
end

function WarehouseDestruction.client_onClientDataUpdate( self, data, channel )
	self.cl = self.cl or {}
	if channel == 1 then
		self.cl.fireWallTick = data.fireWallTick
		self.cl.warehouseIndex = data.warehouseIndex
	elseif channel == 2 then
		local warehouse = WarehouseManager.Cl_GetWarehouseFromIndex( self.cl.warehouseIndex )
		if not warehouse or not warehouse.zeroCell then return end
		local world = warehouse.world
		local serverTick = sm.game.getServerTick()
		if serverTick >= data.startTick then
			self.cl.explosionState = ExplosionState.MISSED
		else
			self.cl.explosionState = ExplosionState.LOADING
			self.cl.explosionStartTick = data.startTick
			self.cl.explosionEffectCellHandle = world:loadCellWithHandle( warehouse.zeroCell.x, warehouse.zeroCell.y, "cl_loadedExplosionEffectCell", {} )
		end
	end
end

function WarehouseDestruction.cl_loadedExplosionEffectCell( self, world, x, y, params )
	if self.cl.explosionState ~= ExplosionState.LOADING then return end

	local nodes = sm.cell.getNodesByTag( x, y, "WAREHOUSE_EXPLOSION", world )
	local effect
	for _, node in ipairs( nodes ) do
		if node.params and node.params.effect then
			effect = sm.effect.createEffect( node.params.effect.name )
			effect:setWorld( world )
			effect:setPosition( node.position )
			effect:setRotation( node.rotation )
			effect:setScale( node.scale )
			if node.params.effect.params then
				for k, v in kvpairs( node.params.effect.params ) do
					effect:setParameter( k, v )
				end
			end
			break
		end
	end

	if not effect then
		print( "error: could not find warehouse explosion effect in cell" )
		self.cl.explosionState = ExplosionState.MISSED
	else
		self.cl.explosionEffect = effect
		self.cl.explosionState = ExplosionState.READY
	end
end

function WarehouseDestruction.cl_n_reloadTile( self, params )
	for x = params.xMin, params.xMax do
		for y = params.yMin, params.yMax do
			params.world:reloadCell( x, y, "cl_reloadCellCallback", self, params.explosion )
		end
	end
end

function WarehouseDestruction.cl_reloadCellCallback( self, world, x, y, result, explosion )
	if result == 1 then
		EffectManager.Cl_UpdateTagFilteredEffectsForCell( world, x, y, { explosion } )
	end
end

function WarehouseDestruction.client_onFixedUpdate( self, dt )

	local currentTick = sm.game.getServerTick()
	local insideWarehouse = false
	local nearWarehouseOutside = false
	local myPlayer = sm.localPlayer.getPlayer()
	local myCharacter = myPlayer and myPlayer.character or nil
	local myWorld = sm.exists( myCharacter ) and myCharacter:getWorld() or nil
	if myWorld then
		local warehouse = WarehouseManager.Cl_GetWarehouseFromIndex( self.cl.warehouseIndex )
		if warehouse then
			if not self.cl.appliedRendersettings then
				for _, warehouseWorld in ipairs( warehouse.worlds ) do
					RenderSettingsManager.Cl_ModifyWorldRenderSettingsDefault( warehouseWorld, OverrideRenderSettings  )
				end
				self.cl.appliedRendersettings = true
			end

			for _, warehouseWorld in ipairs( warehouse.worlds ) do
				if myWorld == warehouseWorld then
					-- Player is inside this warehouse
					insideWarehouse = true
					break
				end
			end

			-- Check if the player is near the warehouse tile
			local refX, refY
			if warehouse.exits and warehouse.exits[1] then
				refX = warehouse.exits[1].x * 64 + 32
				refY = warehouse.exits[1].y * 64 + 32
			elseif warehouse.tileRange then
				local tr = warehouse.tileRange
				refX = (tr.xMin + tr.xMax + 1) * 32
				refY = (tr.yMin + tr.yMax + 1) * 32
			end
			if refX then
				local dx = myCharacter.worldPosition.x - refX
				local dy = myCharacter.worldPosition.y - refY
				nearWarehouseOutside = (dx * dx + dy * dy) < NearWarehouseDistance * NearWarehouseDistance
			end
		end
	end

	if ( insideWarehouse or nearWarehouseOutside ) and not self.cl.explosionState then
		local ticksLeft = math.max( self.cl.fireWallTick - currentTick, 0 )
		local timeLeft = ticksLeft * 0.025
		self.cl.eventTimer:update( true, timeLeft )
		self.cl.dangerZoneBorder:update( true )
	else
		self.cl.eventTimer:update( false )
		self.cl.dangerZoneBorder:update( false )
	end

	if insideWarehouse then
		if currentTick >= self.cl.fireWallTick then
			if sm.exists( myCharacter ) then
				if self.cl.fireWallEffect == nil then
					self.cl.fireWallEffect = sm.effect.createEffect( "Warehousedestruction - Indoorexplosion01", myCharacter )
					self.cl.fireWallEffect:setOffsetRotation( sm.quat.fromEuler( sm.vec3.new( -90, 0, 0 ) ) )
				end

				if self.cl.fireWallAudio == nil then
					self.cl.fireWallAudio = sm.effect.createEffect( "audio:event:/props/installations/warehouse/explode/inside_explosion_fire" );
					self.cl.fireWallAudio:setWorld( myCharacter:getWorld() );
				end

				if self.cl.fireWallAudio then
					if not self.cl.fireWallAudio:isPlaying() then
						self.cl.fireWallAudio:start()
						self.cl.fireWallDistance = WallEffectDistance;
					end
	
					self.cl.fireWallDistance = clamp( self.cl.fireWallDistance - WallSpeed * dt, 0, WallEffectDistance )
					local charDirectrion = myCharacter.direction
					charDirectrion.z = 0
					charDirectrion = charDirectrion:normalize()
					
					local position = myCharacter.worldPosition + charDirectrion * self.cl.fireWallDistance
					self.cl.fireWallAudio:setPosition( position )
				end
			end

			if self.cl.fireWallEffect and not self.cl.fireWallEffect:isPlaying() then
				self.cl.fireWallEffect:start()
			end
		end

		if self.cl.fallingDustEffect == nil and sm.exists( myCharacter ) then
			self.cl.fallingDustEffect = sm.effect.createEffect( "Warehouse - Fallingsmoke", myCharacter )
			self.cl.fallingDustEffect:setOffsetPosition( sm.vec3.new( 0, 15, 0 ) )
			self.cl.fallingDustEffect:setOffsetRotation( sm.quat.fromEuler( sm.vec3.new( -90, 0, 0 ) ) )
			self.cl.fallingDustEffect:start()
		elseif self.cl.fallingDustEffect and sm.exists( self.cl.fallingDustEffect ) and not self.cl.fallingDustEffect:isPlaying() then
			self.cl.fallingDustEffect:start()
		end

		if self.cl.fallingDustEffectBurst == nil and sm.exists( myCharacter ) then
			self.cl.fallingDustEffectBurst = sm.effect.createEffect( "Warehouse - Fallingsmoke_burst", myCharacter )
			self.cl.fallingDustEffectBurst:setOffsetPosition( sm.vec3.new( 0, 15, 0 ) )
			self.cl.fallingDustEffectBurst:setOffsetRotation( sm.quat.fromEuler( sm.vec3.new( -90, 0, 0 ) ) )
		elseif self.cl.fallingDustEffectBurst and sm.exists( self.cl.fallingDustEffectBurst ) then
			if currentTick % CameraShakeBurstInterval == 0 then
				self.cl.fallingDustEffectBurst:start()
			end
		end

		-- trigers a recreate on player world change
		if self.cl.fallingDustEffect and not sm.exists( self.cl.fallingDustEffect ) then
			self.cl.fallingDustEffect = nil
		end
		if self.cl.fallingDustEffectBurst and not sm.exists( self.cl.fallingDustEffectBurst ) then
			self.cl.fallingDustEffectBurst = nil
		end
	else
		if sm.exists( self.cl.fireWallEffect ) then
			if self.cl.fireWallEffect and self.cl.fireWallEffect:isPlaying() then
				self.cl.fireWallEffect:stop()
			end
		end

		if self.cl.fireWallAudio then
			if sm.exists( self.cl.fireWallAudio ) then
				if self.cl.fireWallAudio:isPlaying() then
					self.cl.fireWallAudio:stop()
				end
			end
		end

		if sm.exists( self.cl.fallingDustEffect ) then
			if self.cl.fallingDustEffect and self.cl.fallingDustEffect:isPlaying() then
				self.cl.fallingDustEffect:stop()
			end
		end
		if sm.exists( self.cl.fallingDustEffectBurst ) then
			if self.cl.fallingDustEffect and self.cl.fallingDustEffectBurst:isPlaying() then
				self.cl.fallingDustEffectBurst:stop()
			end
		end
	end

	-- Explosion state machine
	if self.cl.explosionState then
		local serverTick = sm.game.getServerTick()
		if self.cl.explosionState == ExplosionState.LOADING then
			if serverTick >= self.cl.explosionStartTick then
				self.cl.explosionState = ExplosionState.MISSED
			end
		elseif self.cl.explosionState == ExplosionState.READY then
			if serverTick >= self.cl.explosionStartTick then
				if sm.isHost then
					self.cl.explosionEffect:bindEventServerCallback( {}, self )
				end
				self.cl.explosionEffect:start()
				self.cl.explosionState = ExplosionState.PLAYING
				if self.cl.explosionEffectCellHandle then
					self.cl.explosionEffectCellHandle:release()
					self.cl.explosionEffectCellHandle = nil
				end
			end
		end
	end
end
