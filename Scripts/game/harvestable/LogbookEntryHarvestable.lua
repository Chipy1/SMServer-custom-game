dofile "$SURVIVAL_DATA/Scripts/util.lua"
dofile "$SURVIVAL_DATA/Scripts/game/survival_constants.lua"
dofile "$SURVIVAL_DATA/Scripts/game/tools/LogBook.lua"
dofile "$SURVIVAL_DATA/Scripts/game/harvestable/QuestRewardBase.lua"

LogbookEntryHarvestable = class( QuestRewardBase )

-- Server
function LogbookEntryHarvestable.server_onCreate( self )
    self.sv = {}
    self.sv.saved = self.storage:load()
    if self.sv.saved == nil then
        self.sv.saved = {}
        if self.params then
            self.sv.saved = self.params
        end
        self.storage:save( self.sv.saved )
    end
    self.network:setClientData( self.sv.saved )
	self.harvestable.publicData = { vacuumable = false }
end

function LogbookEntryHarvestable.server_canErase( self )
    return true
end

function LogbookEntryHarvestable.sv_n_harvest( self, params, player )
    if not self.sv.removed then
        sm.event.sendToPlayer( player, "sv_e_onLoot", { uuid = self.sv.saved.uuid, quantity = self.sv.saved.quantity, pos = self.harvestable:getPosition() } )
        LogEntryManager.Sv_AddLog( self.sv.saved.logUuid )
        sm.harvestable.destroy( self.harvestable )
        self.sv.removed = true
    end
end

-- Client

function LogbookEntryHarvestable.cl_startEffect( self )

    local displayedUuid = self.cl.displayItemUuid

    local bounds = sm.item.getShapeSize( displayedUuid )
    local scale = sm.construction.constants.subdivideRatio / ( ( bounds.x + bounds.y + bounds.z ) / 3.0 );

    self.cl.itemEffect = sm.effect.createEffect( "Questeffects - Quest_lootitem" )

    self.cl.itemEffect:setPosition( self.harvestable:getPosition() )

    local forward = sm.vec3.new( 0, 1, 0 )
    self.cl.itemEffect:setRotation( sm.vec3.getRotation( forward, forward:rotateZ( self.cl.rotation ) ) )
    self.cl.itemEffect:setParameter( "uuid", displayedUuid )
    self.cl.itemEffect:setParameter( "color", self.cl.color and sm.color.new( self.cl.color ) or sm.shape.getShapeTypeColor( displayedUuid ) )
    -- Set the effect scale and offset

    self.cl.itemEffect:setScale( sm.vec3.new( scale, scale, scale ) )

    self.cl.itemEffect:start()
end

function LogbookEntryHarvestable.client_canErase( self )
    return true
end

function LogbookEntryHarvestable.client_onCreate( self )
    self.cl = {}
    self.cl.rotation = math.random() * math.pi * 2
end

function LogbookEntryHarvestable.client_onDestroy( self )
    self.cl.itemEffect:stop()
end

function LogbookEntryHarvestable.client_onUpdate( self, dt )
    -- Slowly rotate the effect
	local rotationSpeed = 0.1875 -- Revolutions per second
	self.cl.rotation = self.cl.rotation + math.pi * 2 * dt * rotationSpeed
	while self.cl.rotation > math.pi * 2 do
		self.cl.rotation = self.cl.rotation - math.pi * 2
	end
	self.cl.rotation = math.max( math.min( self.cl.rotation, math.pi * 2 ), 0 )
	local forward = sm.vec3.new( 0, 1, 0 )
	self.cl.itemEffect:setRotation( sm.vec3.getRotation( forward, forward:rotateZ( self.cl.rotation ) ) )
end

function LogbookEntryHarvestable.client_onInteract( self, _, state )
    self.network:sendToServer( "sv_n_harvest", state )
end

function LogbookEntryHarvestable.client_canInteract( self )
    local keyBindingText = GetInteractionKeybinding()
    sm.gui.setInteractionText( "", keyBindingText, "#{INTERACTION_PICK_UP}" )
    return true
end

function LogbookEntryHarvestable.client_onClientDataUpdate( self, data )
    self.cl.displayItemUuid = data.displayItemUuid
    self.cl.color = data.color
    self:cl_startEffect()
end