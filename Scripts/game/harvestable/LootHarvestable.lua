-- LootHarvestable.lua --
dofile "$SURVIVAL_DATA/Scripts/util.lua"
dofile "$SURVIVAL_DATA/Scripts/game/survival_constants.lua"

LootHarvestable = class( nil )

function LootHarvestable.server_onCreate( self )
	self.sv = {}
	self.sv.saved = self.storage:load() or {}
	local save = false
	if self.params then
		self.sv.saved.uuid = self.params.uuid
		self.sv.saved.quantity = self.params.quantity
		self.sv.saved.epic = self.params.epic
		self.sv.saved.questItem = self.params.questItem
		save = true
	end
	self.sv.saved.uuid = self.sv.saved.uuid or sm.uuid.getNil()
	self.sv.saved.quantity = self.sv.saved.quantity or 0
	self.sv.saved.epic = self.sv.saved.epic or nil
	self.sv.saved.questItem = self.sv.saved.questItem or nil
	self.sv.saved.killTick = self.sv.saved.killTick or ( sm.game.getCurrentTick() + 144000 ) -- 1 hour until removed
	if save then
		self.storage:save( self.sv.saved )
	end
	self.network:setClientData( { uuid = self.sv.saved.uuid, quantity = self.sv.saved.quantity, epic = self.sv.saved.epic, questItem = self.sv.saved.questItem } )
	self.harvestable.publicData = { uuid = self.sv.saved.uuid, quantity = self.sv.saved.quantity, vacuumable = true }
end

function LootHarvestable.server_onReceiveUpdate( self )
	if sm.exists( self.harvestable ) and not self.harvestable.publicData.harvested and sm.game.getCurrentTick() >= self.sv.saved.killTick then
		self.harvestable.publicData.harvested = true
		self.harvestable:destroy()
	end
end

function LootHarvestable.server_canErase( self ) return true end
function LootHarvestable.client_canErase( self ) return true end

function LootHarvestable.server_onRemoved( self, player )
	self:sv_n_harvest( nil, player )
end

function LootHarvestable.server_onFloating( self )
	if sm.exists( self.harvestable ) and not self.harvestable.publicData.harvested then
		self.harvestable.publicData.harvested = true
		SpawnLoot( self.harvestable, { { uuid = self.sv.saved.uuid, quantity = self.sv.saved.quantity, epic = self.sv.saved.epic } }, nil, nil, 2 )
		self.harvestable:destroy()
	end
end

function LootHarvestable.cl_n_onInventoryFull( self )
	NotificationManager.Cl_AddGenericNotification( "#{INFO_INVENTORY_FULL}", 4 )
end

function LootHarvestable.sv_n_harvest( self, params, player )
	if sm.exists( self.harvestable ) and not self.harvestable.publicData.harvested then
		-- Give the represented items to the interacting player and destroy the harvestable
		local container = player:getInventory()
		if sm.container.beginTransaction() then
			sm.container.collect( container, self.sv.saved.uuid, self.sv.saved.quantity )
			if sm.container.endTransaction() then
				self.harvestable.publicData.harvested = true
				sm.event.sendToPlayer( player, "sv_e_onLoot", { uuid = self.sv.saved.uuid, quantity = self.sv.saved.quantity, pos = self.harvestable:getPosition() } )
				self.harvestable:destroy()
			else
				self.network:sendToClient( player, "cl_n_onInventoryFull" )
			end
		end
	end
end

function LootHarvestable.client_onCreate( self )
	-- Create the loot renderable effect with a random starting rotation
	self.cl = {}
	self.cl.rotation = math.random() * math.pi * 2
end

function LootHarvestable.client_onClientDataUpdate( self, params )
	-- Set the effect renderable
	self.cl.uuid = params.uuid
	self.cl.quantity = params.quantity
	self.cl.epic = params.epic
	self.cl.questItem = params.questItem
	local scale = 0.25
	local effectUuid = self.cl.uuid
	if sm.item.isTool( self.cl.uuid ) then
		effectUuid = GetToolProxyItem( params.uuid )
	end

	if params.uuid == ITEMS.obj_outfitpackage_common then
		self.cl.itemEffect = sm.effect.createEffect( "Loot - OutfitCommonGlowItem" )
		self.cl.itemEffect:setPosition( self.harvestable:getPosition() + sm.vec3.new( 0, 0, 0.575 ) )
	elseif params.uuid == ITEMS.obj_outfitpackage_rare then
		self.cl.itemEffect = sm.effect.createEffect( "Loot - OutfitRareGlowItem" )
		self.cl.itemEffect:setPosition( self.harvestable:getPosition() + sm.vec3.new( 0, 0, 0.575 ) )
	elseif params.uuid == ITEMS.obj_outfitpackage_epic then
		self.cl.itemEffect = sm.effect.createEffect( "Loot - OutfitEpicGlowItem" )
		self.cl.itemEffect:setPosition( self.harvestable:getPosition() + sm.vec3.new( 0, 0, 0.575 ) )
	else
		if effectUuid then
			local bounds = sm.item.getShapeSize( effectUuid )
			scale = sm.construction.constants.subdivideRatio / ( ( bounds.x + bounds.y + bounds.z ) / 3.0 );
		end

		local offset = sm.vec3.new( 0, 0, 0.375 )
		if self.cl.questItem then
			self.cl.itemEffect = sm.effect.createEffect( "Quest - RewardItem" )
			offset = sm.vec3.new( 0, 0, 0 )
		elseif self.cl.epic then
			self.cl.itemEffect = sm.effect.createEffect( "EpicLoot - GlowItem" )
		else
			self.cl.itemEffect = sm.effect.createEffect( "Loot - GlowItem" )
		end
		self.cl.itemEffect:setPosition( self.harvestable:getPosition() + offset )

	end
	local forward = sm.vec3.new( 0, 1, 0 )
	self.cl.itemEffect:setRotation( sm.vec3.getRotation( forward, forward:rotateZ( self.cl.rotation ) ) )
	if effectUuid then
		self.cl.itemEffect:setParameter( "uuid", effectUuid )
		self.cl.itemEffect:setParameter( "Color", sm.shape.getShapeTypeColor( params.uuid ) )
	end
	-- Set the effect scale and offset
	self.cl.itemEffect:setScale( sm.vec3.new( scale, scale, scale ) )
	self.cl.itemEffect:start()
end

function LootHarvestable.client_onDestroy( self )
	if sm.exists( self.cl.itemEffect ) then
		self.cl.itemEffect:stop()
		self.cl.itemEffect:destroy()
	end
end

function LootHarvestable.client_onInteract( self, _, state )
	if state then
		self.network:sendToServer( "sv_n_harvest" )
	end
end


function LootHarvestable.client_canInteract( self )
	if self.cl.uuid then
		local keyBindingText = GetInteractionKeybinding()
		sm.gui.setInteractionText( "", keyBindingText, "#{INTERACTION_PICK_UP} #FFFFC0" .. sm.shape.getShapeTitle( self.cl.uuid ) .. "#FFFFFF"..( self.cl.quantity > 1 and (" x " .. self.cl.quantity) or "" ) )
	end
	return true
end
