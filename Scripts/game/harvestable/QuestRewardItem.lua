dofile "$SURVIVAL_DATA/Scripts/util.lua"
dofile "$SURVIVAL_DATA/Scripts/game/survival_constants.lua"
dofile( "$SURVIVAL_DATA/Scripts/game/harvestable/QuestRewardBase.lua" )
dofile( "$CUSTOMIZATION_DATA/Scripts/game/quest_reward_util.lua" )

QuestRewardItem = class( QuestRewardBase )

function QuestRewardItem.server_onCreate( self )
    QuestRewardBase.server_onCreate( self )
    if self.sv.saved == nil then
        self.sv.saved = {}
        self.sv.saved.uuid = sm.uuid.getNil()
        self.sv.saved.quantity = 0
        if self.params then
            self.sv.saved.pickupEvent = self.params.pickupEvent
            self.sv.saved.rewardList = self.params.rewardList
        end

        self.storage:save( self.sv.saved )
    end
    self.network:setClientData( self.sv.saved.rewardList )
	self.harvestable.publicData = { vacuumable = false }
end

function QuestRewardItem.sv_n_harvest( self, _, player )
    if not self.sv.removed then
        local container = player:getInventory()
        if Sv_GrantItems( container, self.sv.saved.rewardList ) then
            self.event.sendToGame( "sv_e_grantAdditionalRewards", self.sv.saved.rewardList )
            self.sv.removed = true
            self.harvestable.publicData.harvested = true
            sm.event.sendToPlayer( player, "sv_e_onLoot", { uuid = self.sv.saved.uuid, quantity = self.sv.saved.quantity, pos = self.harvestable:getPosition() } )
            sm.harvestable.destroy( self.harvestable )
            if self.sv.saved.pickupEvent then
                QuestManager.Sv_SendEvent( self.sv.saved.pickupEvent )
            end
        else
            self.network:sendToClient( player, "cl_n_onInventoryFull" )
        end
    end
end

function QuestRewardItem.client_onClientDataUpdate( self, rewardList )
	local scale = 0.25
	local effectUuid = obj_plantables_banana -- replace with correct shape later

    if effectUuid then
        local bounds = sm.item.getShapeSize( effectUuid )
        scale = sm.construction.constants.subdivideRatio / ( ( bounds.x + bounds.y + bounds.z ) / 3.0 );
    end

    self.cl.itemEffect = sm.effect.createEffect( "Quest - RewardItem" )

    self.cl.itemEffect:setPosition( self.harvestable:getPosition() )

    local forward = sm.vec3.new( 0, 1, 0 )
    self.cl.itemEffect:setRotation( sm.vec3.getRotation( forward, forward:rotateZ( self.cl.rotation ) ) )
    if effectUuid then
        self.cl.itemEffect:setParameter( "uuid", effectUuid )
        self.cl.itemEffect:setParameter( "Color", sm.shape.getShapeTypeColor( obj_plantables_banana ) )
    end

    self.cl.itemEffect:setScale( sm.vec3.new( scale, scale, scale ) )
    self.cl.itemEffect:start()
end

function QuestRewardItem.client_canInteract( self )
    local keyBindingText = GetInteractionKeybinding()
    sm.gui.setInteractionText( "", keyBindingText, "#{INTERACTION_PICK_UP}" )	
    return true
end

