AutoDoorSensorController = class( nil )

AutoDoorSensorController.maxParentCount = 0
AutoDoorSensorController.maxChildCount = 2
AutoDoorSensorController.connectionInput = sm.interactable.connectionType.none
AutoDoorSensorController.connectionOutput = sm.interactable.connectionType.logic

local DoorCheckTickFrequency = 0.3 * 40
local TriggerAreaSize = sm.vec3.new( 6.5, 6.5, 3.5 )
local TriggerOffset = sm.vec3.new( 0, 0, -4 )
local ScanEffectWaitTicks = 3.0 * 40
local EffectOffset1 = sm.vec3.new( 0, -0.4, 1.5 )
local EffectOffset2 = sm.vec3.new( 0.1, 0.7, 1.5 )

function AutoDoorSensorController.server_onCreate( self )
    self.sv = {}
    self.sv.doorFound = false
    self.sv.tickCounter = 0
    self.sv.scanTickCounter = 0
    self.sv.door = nil
    self.sv.isOpen = false
    self.sv.isMoving = false
    self.sv.scanInProgress = false
    self.sv.areaTrigger = sm.areaTrigger.createBox( TriggerAreaSize , self.shape.worldPosition + self.shape.worldRotation * TriggerOffset, self.shape.worldRotation, sm.areaTrigger.filter.character )
end

function AutoDoorSensorController.sv_startOpeningScan( self, areaContents )
    local characterPos = areaContents[1].worldPosition
    local localPos = self.shape:transformPoint( characterPos )
    if localPos.x < 0.0 then
        sm.effect.playEffect( "Growlab - Doorscannerlaser_activate", self.shape.worldPosition + self.shape.worldRotation * EffectOffset1, nil, self.shape.worldRotation )
    else
        sm.effect.playEffect( "Growlab - Doorscannerlaser_activate", self.shape.worldPosition + self.shape.worldRotation * EffectOffset2, nil, self.shape.worldRotation * sm.quat.new( 0, 0, 1, 0. ) )
    end
    self.network:setClientData( { showIdleEffect = false }, 1 )
    self.sv.scanInProgress = true
end

function AutoDoorSensorController.server_onFixedUpdate( self )
    if not self.sv.doorFound then
        self.sv.tickCounter = self.sv.tickCounter + 1
        if self.sv.tickCounter >= DoorCheckTickFrequency then
            self:sv_tryFindDoor()
            self.sv.tickCounter = 0
        end
    else
        if not sm.exists( self.sv.door ) then
            return
        end

        if self.sv.door.publicData.moving ~= self.sv.isMoving then
            self.sv.isMoving = not self.sv.isMoving
            if not self.sv.isMoving then
                self.sv.isOpen = not self.sv.isOpen
                self.network:setClientData( { showIdleEffect = not self.sv.isOpen } )
            end
        end
        
        local areaContents = self.sv.areaTrigger:getContents()
        local shouldBeOpen = #areaContents > 0
        if shouldBeOpen and not self.sv.isOpen and not self.sv.scanInProgress and not self.sv.isMoving then
            self:sv_startOpeningScan( areaContents )
        end
        if not self.sv.scanInProgress then
            return
        end

        if self.sv.scanTickCounter < ScanEffectWaitTicks then
            self.sv.scanTickCounter = self.sv.scanTickCounter + 1
            if self.sv.scanTickCounter >= ScanEffectWaitTicks and shouldBeOpen and not self.sv.isMoving and not self.sv.isOpen then
                sm.event.sendToHarvestable( self.sv.door, "sv_e_activate" )
                self.interactable.active = true
            elseif self.sv.scanTickCounter >= ScanEffectWaitTicks and ( self.sv.isMoving or self.sv.isOpen or not shouldBeOpen ) then
                self:sv_resetAndBroadcast()
            end
        else
            if not shouldBeOpen and self.sv.isOpen then
                sm.event.sendToHarvestable( self.sv.door, "sv_e_activate" )
                self.interactable.active = false
                self:sv_resetAndBroadcast()
            end
        end
    end
end

function AutoDoorSensorController.sv_resetAndBroadcast( self )
    self.sv.scanInProgress = false
    self.sv.scanTickCounter = 0
    self.network:setClientData( { showIdleEffect = true } )
end

function AutoDoorSensorController.sv_tryFindDoor( self )
    local contacts = sm.physics.getSphereContacts( self.shape:getWorldPosition() + sm.vec3.new( 0, 0, -3 ), 2 )
    for _, harvestable in ipairs( contacts.harvestables ) do
        if harvestable.publicData and harvestable:isKinematic() then
            self.sv.doorFound = true
            self.sv.door = harvestable
            break
        end
    end
end

-- Client

function AutoDoorSensorController.client_onCreate( self )
    self.cl = {}
    self.cl.idleEffect1 = sm.effect.createEffect( "Growlab - Doorscannerlaser", self.shape )
    self.cl.idleEffect2 = sm.effect.createEffect( "Growlab - Doorscannerlaser", self.shape )
    self.cl.idleEffect1:setOffsetPosition( EffectOffset1 )
    self.cl.idleEffect2:setOffsetPosition( EffectOffset2 )
    self.cl.idleEffect2:setOffsetRotation( sm.quat.new( 0, 0, 1, 0. ) )
    self.cl.idleEffect1:start()
    self.cl.idleEffect2:start()
end

function AutoDoorSensorController.client_onDestroy( self )
    self.cl.idleEffect1:stop()
    self.cl.idleEffect1:destroy()
    self.cl.idleEffect2:stop()
    self.cl.idleEffect2:destroy()
end

function AutoDoorSensorController.client_onClientDataUpdate( self, data )
    if data.showIdleEffect then
        self.cl.idleEffect1:start()
        self.cl.idleEffect2:start()
    else
        self.cl.idleEffect1:stop()
        self.cl.idleEffect2:stop()
    end
end