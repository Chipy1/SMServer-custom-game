
dofile( "$SURVIVAL_DATA/Scripts/game/managers/QuestManager.lua" )
dofile( "$GAME_DATA/Scripts/game/managers/EffectManager.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/powerladder_util.lua" )

MininghubPowerActivator = class( nil )

local PowerRailTags = {
    "ts:rail:powerrail_blue",
    "ts:rail:powerrail_cyan",
    "ts:rail:powerrail_gray",
    "ts:rail:powerrail_green",
    "ts:rail:powerrail_orange",
    "ts:rail:powerrail_pink",
    "ts:rail:powerrail_red",
    "ts:rail:powerrail_violet",
    "ts:rail:powerrail_yellow",
}

local PutTime = 0.2
local PutTimeTicks = PutTime * 40
local KinematicCloseDelay = 1.1 * 40

function MininghubPowerActivator.server_onCreate( self )
    self.sv = {}
    self.sv.saved = self.storage:load()
    if self.sv.saved == nil then
        self.sv.saved = {}
        self.sv.saved.active = false
        self.sv.saved.bootingUp = false
        self.sv.saved.activatorStorageFlag = self.params.activatorStorageFlag
        self.storage:save( self.sv.saved )
    end
    self.sv.tickCounter = 0
    self.network:setClientData( { active = self.sv.saved.active } )
end

function MininghubPowerActivator.server_onFixedUpdate( self )
    if self.sv.saved.bootingUp then
        self.sv.tickCounter = self.sv.tickCounter + 1
        if self.sv.tickCounter >= PutTimeTicks and self.sv.saved.active == false then
            self.sv.saved.active = true
            self.sv.tickCounter = 0
            local tileStorageKey = TileStorageManager.Sv_GetTileStorageKeyFromObject( self.harvestable )
            KinematicManager.Sv_Activate( tileStorageKey, self.sv.saved.activatorStorageFlag )
            self.storage:save( self.sv.saved )
            self.network:setClientData( { active = self.sv.saved.active } )
        elseif self.sv.saved.active and self.sv.tickCounter >= KinematicCloseDelay then
            local tileStorageKey = TileStorageManager.Sv_GetTileStorageKeyFromObject( self.harvestable )

            -- Set tilestorage flag for show/hide of station-specific objects
            SetTileStorageFlag( tileStorageKey, self.sv.saved.activatorStorageFlag )
            EffectManager.Sv_UpdateTagFilteredEffectsForTile( self.harvestable:getWorld(), self.harvestable.worldPosition, { self.sv.saved.activatorStorageFlag } )
            sm.event.sendToGame( "sv_reloadTile", { pos = self.harvestable.worldPosition, world = self.harvestable:getWorld() } )

            QuestManager.Sv_SendEvent( "mininghub_station_activated", { activatorStorageFlag = self.sv.saved.activatorStorageFlag } )

            -- Power on all rails when the powerrails station activates
            if self.sv.saved.activatorStorageFlag == "minehub:powerrails.activated" then
                for _, tag in ipairs( PowerRailTags ) do
                    SetRailPower( true, tag, tileStorageKey )
                end
            end

            self.sv.saved.bootingUp = false
            self.storage:save(self.sv.saved)
            sm.effect.playEffect("Poweractivationstation - Activation",
                self.harvestable.worldPosition + self.harvestable.worldRotation * sm.vec3.new(0.0, 0.0, -2.5), nil,
                self.harvestable.worldRotation * sm.quat.new(0.5, -0.5, -0.5, -0.5))
        end
    end
end

function MininghubPowerActivator.sv_e_receiveItem( self, params )
    if not self.sv.saved.active and not self.sv.saved.bootingUp then
        sm.container.beginTransaction()
        sm.container.spendFromSlot( params.containerA, 0, params.itemA, params.quantityA, true )
        if sm.container.endTransaction() then
            self.network:sendToClients( "cl_n_activate", { fromPosition = params.fromPosition, fromRotation = params.fromRotation } )
            sm.effect.playEffect( "Poweractivationstation - Insert", self.harvestable.worldPosition )
            self.sv.saved.bootingUp = true
            self.storage:save( self.sv.saved )
        end
    end
end

function MininghubPowerActivator.client_onCreate( self )
    self.cl = {}
    self.cl.effectData = nil
end

function MininghubPowerActivator.client_onClientDataUpdate( self, data )
    if self.cl == nil then
        self.cl = {}
    end
    if data.active then
        self.harvestable:setUvFrameIndex( 1 )
        self.harvestable:setColor( sm.color.new( 0x1799aa7f ) )
    else
        self.harvestable:setUvFrameIndex( 0 )
    end
end

function MininghubPowerActivator.client_onUpdate( self, dt )
    if self.cl.effectData ~= nil then
        self.cl.effectData.elapsedTime = self.cl.effectData.elapsedTime + dt
        if self.cl.effectData.elapsedTime <= PutTime then
            local progress = math.min( self.cl.effectData.elapsedTime / PutTime, 1.0 )
            local toPosition = self.harvestable.worldPosition + self.harvestable.worldRotation * sm.vec3.new( 0.0, 1.0, 1.5 )
            local toRotation = sm.quat.new( 0.707107, 0, 0, 0.707107 )
            local startPosition = sm.vec3.lerp( self.cl.effectData.fromPosition, toPosition, 0.5 )
            self.cl.effectData.effect:setRotation( toRotation )
            self.cl.effectData.effect:setPosition( sm.vec3.lerp( startPosition, toPosition, progress ) )
        end
    end
end

function MininghubPowerActivator.cl_n_activate( self, data )
    self.cl.effectData = {}
    self.cl.effectData.effect = sm.effect.createEffect( "ShapeRenderable" )
    self.cl.effectData.effect:setParameter( "uuid", obj_powerstation_battery )
    self.cl.effectData.effect:setPosition( data.fromPosition )
    self.cl.effectData.effect:setRotation( data.fromRotation )
    self.cl.effectData.effect:setScale( sm.vec3.new( 0.25, 0.25, 0.25 ) )
    self.cl.effectData.effect:start()
    self.cl.effectData.elapsedTime = 0.0
    self.cl.effectData.fromPosition = data.fromPosition
    self.cl.effectData.fromRotation = data.fromRotation
end