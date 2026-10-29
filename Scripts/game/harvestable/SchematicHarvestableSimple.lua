dofile "$SURVIVAL_DATA/Scripts/util.lua"
dofile "$SURVIVAL_DATA/Scripts/game/survival_constants.lua"


---@class SchematicHarvestableSimple : HarvestableClass
---@field sv table
---@field cl table
SchematicHarvestableSimple = class( nil )

function SchematicHarvestableSimple.server_onCreate( self )
	self.sv = {}
end

function SchematicHarvestableSimple.server_canErase( self )
	return true
end

function SchematicHarvestableSimple.sv_n_harvest( self )
	if not self.sv.removed then
		RecipeManager.Sv_UnlockRecipe( tostring( self.data.unlockItemUuid ) )
		sm.harvestable.destroy( self.harvestable )
		self.sv.removed = true
	end
end

function SchematicHarvestableSimple.server_onRemoved( self, player )
	self:sv_n_harvest()
end

function SchematicHarvestableSimple.client_onCreate( self )
	self.cl = {}
	self.cl.itemUuid = sm.uuid.new( self.data.unlockItemUuid )

	self.cl.itemEffect = sm.effect.createEffect( self.data.effectName )

	self.cl.itemEffect:setPosition( self.harvestable:getPosition() + sm.vec3.new( 0, 0, 0.575 ) )

	local forward = sm.vec3.new( 0, 1, 0 )
	self.cl.rotation = math.random() * math.pi * 2
	self.cl.itemEffect:setRotation( sm.vec3.getRotation( forward, forward:rotateZ( self.cl.rotation ) ) )
	
	local scale = 0.25
	self.cl.itemEffect:setScale( sm.vec3.new( scale, scale, scale ) )
	
	self.cl.itemEffect:setParameter( "Color", sm.color.new( "ff00ff" ) )
	
	self.cl.itemEffect:start()
end

function SchematicHarvestableSimple.client_onDestroy( self )
	self.cl.itemEffect:destroy()
end

function SchematicHarvestableSimple.client_canInteract( self )
	local keyBindingText = GetInteractionKeybinding()
	sm.gui.setInteractionText( "", keyBindingText, "#{INTERACTION_LEARN} [" .. sm.shape.getShapeTitle( self.cl.itemUuid ) .. "]" )
	return true
end

function SchematicHarvestableSimple.client_canErase( self )
	return true
end

function SchematicHarvestableSimple.client_onInteract( self, state )
	self.network:sendToServer( "sv_n_harvest" )
end
