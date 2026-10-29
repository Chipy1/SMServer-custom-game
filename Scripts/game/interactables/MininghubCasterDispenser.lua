dofile( "$SURVIVAL_DATA/Scripts/util.lua" )

MininghubCasterDispenser = class()

local CRAFT_INTERVAL = 40 -- ticks (1 seconds). This has to be _at least_ as long as output_loop animation!
local ANIMATION_NAME = "output_loop"
local OUTPUT_BONE = "out_pejnt"
local OUTPUT_BONE_WORLD = "spawn_pejnt"
local STORAGE_VALUE_KEY = "caster"

function MininghubCasterDispenser.server_onCreate( self )
	self.sv = {}
	self.sv.timer = 0
	self.sv.tileStorageKey = TileStorageManager.Sv_GetTileStorageKeyFromObject( self.interactable )
	self.sv.saved = self.storage:load()
	if self.sv.saved == nil then
		self.sv.saved = {}
		self.sv.saved.craftQueue = {}
		self.storage:save( self.sv.saved )
	end
end

function MininghubCasterDispenser.server_onFixedUpdate( self )
	local caster_outputs = TileStorageManager.Sv_GetValue( self.sv.tileStorageKey, STORAGE_VALUE_KEY )
	if caster_outputs ~= nil and not IsEmptyTable( caster_outputs ) then
		for _, uuid in ipairs( caster_outputs ) do
			table.insert( self.sv.saved.craftQueue, uuid )
		end

		TileStorageManager.Sv_SetValue( self.sv.tileStorageKey, STORAGE_VALUE_KEY, {} )
		TileStorageManager.Sv_Save()
		self.storage:save( self.sv.saved )
	end

	if #self.sv.saved.craftQueue > 0 then
		self.sv.timer = self.sv.timer + 1
		if self.sv.timer >= CRAFT_INTERVAL then
			self.sv.timer = 0

			local spawnPos = self.interactable:getWorldBonePosition( OUTPUT_BONE_WORLD )
			local newShape = sm.shape.createPart( table.remove( self.sv.saved.craftQueue, 1 ), spawnPos, self.shape:getWorldRotation(), true, true )
			self.storage:save( self.sv.saved )

			local direction = ( self.shape.at * -1.0 ) + ( self.shape.up * 0.0 );
			sm.physics.applyImpulse( newShape, direction:normalize() * newShape:getMass() * 5, true )

			-- This could be done with setClientData instead, where we post server tick at which the dispenser started and how many items we're spawning.
			-- Since this is not a frequent event, it's probably fine running the communication like this.
			self.network:sendToClients( "cl_n_startAnimation" )
		end
	end
end

function MininghubCasterDispenser.client_onCreate( self )
	self.cl = {}
	self.cl.currentDuration = self.interactable:getAnimDuration( ANIMATION_NAME )
	self.cl.animTimer = -1
	self.cl.fired = false
	self.cl.rollerEffect = sm.effect.createEffect( "Packingstation - Roller", self.interactable, OUTPUT_BONE )
end

function MininghubCasterDispenser.client_onUpdate( self, dt )
	if self.cl.animTimer >= 0 then
		self.cl.animTimer = self.cl.animTimer + dt
		self.interactable:setAnimProgress( ANIMATION_NAME, self.cl.animTimer / self.cl.currentDuration )
		
		if self.cl.fired == false and self.cl.animTimer > 0.2 then
			local effectPos = self.interactable:getWorldBonePosition( OUTPUT_BONE )
			sm.effect.playEffect( "Packingstation - Shoot", effectPos, sm.vec3.zero(), sm.quat.fromEuler( sm.vec3.new( 0, 180, 0 ) ) )
			self.cl.fired = true
		end
		
		if self.cl.animTimer > self.cl.currentDuration then
			self.cl.animTimer = -1
			self.cl.rollerEffect:stop()
			self.interactable:setAnimEnabled( ANIMATION_NAME, false )
		end
	end
end

function MininghubCasterDispenser.cl_n_startAnimation( self, data )
	self.cl.startingTick = data
	self.interactable:setAnimEnabled( ANIMATION_NAME, true )
	self.cl.rollerEffect:start()
	self.cl.animTimer = 0
	self.cl.fired = false
end
