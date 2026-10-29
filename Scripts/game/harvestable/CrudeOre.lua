dofile "$SURVIVAL_DATA/Scripts/util.lua"
dofile "$SURVIVAL_DATA/Scripts/game/survival_constants.lua"

-- obj_resource_crudestone = sm.uuid.new( "4732ba60-67c7-44a3-ba69-89c6e8467756" ),
-- obj_resource_crudesilver = sm.uuid.new( "25af71d6-523c-45d2-99fd-41f8345e3909" ),
-- obj_resource_crudegold = sm.uuid.new( "21903a2f-9e38-47ca-aa77-beb849049765" ),

CrudeOre = class( nil )
--CrudeOre.floatingThreshold = 0.4

function CrudeOre.server_onCreate( self )
	self.sv = {}
	self.sv.saved = self.storage:load() or {}
	if self.params then
		self.sv.saved.uuid = self.params.uuid or sm.uuid.getNil()
		self.sv.saved.quantity = self.params.quantity or 0
		self.storage:save( self.sv.saved )
	end
	self.sv.saved.uuid = self.sv.saved.uuid or sm.uuid.getNil()
	self.sv.saved.quantity = self.sv.saved.quantity or 0
	self.network:setClientData( { uuid = self.sv.saved.uuid, quantity = self.sv.saved.quantity } )
end

function CrudeOre.server_canErase( self ) return true end
function CrudeOre.client_canErase( self ) return true end

function CrudeOre.server_onRemoved( self, player )
	self:sv_n_harvest( nil, player )
end

function CrudeOre.sv_n_harvest( self, params, player )
	if not self.sv.harvested and sm.exists( self.harvestable ) then
		local container = player:getInventory()
		if sm.container.beginTransaction() then
			sm.container.collect( container, self.sv.saved.uuid, self.sv.saved.quantity )
			if sm.container.endTransaction() then
				self.sv.harvested = true
				self.harvestable:destroy()
			else
				self.network:sendToClient( player, "cl_n_onInventoryFull" )
			end
		end
	end
end

function CrudeOre.server_onFloating( self )
	if not self.sv.harvested then
		self.sv.harvested = true
		SpawnLoot( self.harvestable, { { uuid = self.sv.saved.uuid, quantity = self.sv.saved.quantity, epic = self.sv.saved.epic, questItem = self.sv.saved.questItem } }, nil, nil, 2 )
		self.harvestable:destroy()
	end
end

function CrudeOre.cl_n_onInventoryFull( self )
	NotificationManager.Cl_AddGenericNotification( "#{INFO_INVENTORY_FULL}", 4 )
end

function CrudeOre.client_onCreate( self )
	self.cl = {}
end

function CrudeOre.client_onClientDataUpdate( self, params )
	local scale = 0.25
	self.cl.itemEffect = sm.effect.createEffect( "ShapeRenderable" )
	local pos = self.harvestable:getPosition()
	self.cl.itemEffect:setPosition( self.harvestable:getPosition() )
	local rand1 = ( pos.x + pos.y * 57.0 + pos.z * 113.0 ) % 27 / 27
	local rand2 = ( pos.y + pos.z * 29.0 + pos.x * 137.0 ) % 41 / 41
	local randRot = sm.quat.angleAxis( math.pi * 2 * rand2, sm.vec3.new( 0, 0, 1 ) ) * sm.quat.angleAxis( math.pi * rand1, sm.vec3.new( 1, 0, 0 ) )
	self.cl.itemEffect:setRotation( randRot )
	self.cl.itemEffect:setScale( sm.vec3.new( scale, scale, scale ) )
	self.cl.itemEffect:setParameter( "uuid", params.uuid )
	self.cl.itemEffect:setParameter( "Color", sm.shape.getShapeTypeColor( params.uuid ) )
	self.cl.itemEffect:start()
	
	self.cl.uuid = params.uuid
	self.cl.quantity = params.quantity
end

function CrudeOre.client_onDestroy( self )
	self.cl.itemEffect:stop()
	self.cl.itemEffect:destroy()
	--sm.debugDraw.removeText( "CrudeOre"..self.harvestable:getId() )
end

--function CrudeOre.client_onUpdate( self )
--	local weightedDensity = self.harvestable:getWorld():getWeightedVoxelDensityInWorldPoint( self.harvestable:getPosition() )
--	sm.debugDraw.addText( "CrudeOre"..self.harvestable:getId(), tostring( weightedDensity ), self.harvestable:getPosition() + sm.vec3.new( 0, 0, 0.3 ) )
--end

function CrudeOre.client_canInteract( self )
	sm.gui.setInteractionText( "", GetInteractionKeybinding(), "#{INTERACTION_PICK_UP}" )
	return true
end

function CrudeOre.client_onInteract( self, state )
	self.network:sendToServer( "sv_n_harvest" )
end
