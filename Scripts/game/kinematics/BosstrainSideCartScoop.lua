dofile( "$SURVIVAL_DATA/Scripts/game/kinematics/ParentedKinematic.lua" )

BosstrainSideCartScoop = class( ParentedKinematic )

local AreaTriggerDimensions = sm.vec3.new( 10, 10, 10 )
local AreaTriggerOffset = sm.vec3.zero()

local TumbleTime = 40*3

function BosstrainSideCartScoop.server_onCreate( self )
    ParentedKinematic.server_onCreate( self )

    local filter = sm.areaTrigger.filter.character
	self.sv.areaTrigger = sm.areaTrigger.createAttachedBox( self.harvestable, AreaTriggerDimensions, AreaTriggerOffset, sm.quat.identity(), filter )
	self.sv.areaTrigger:setCharacterDetection( true )

    DrillbotManager.Sv_RegisterKinematic( self.harvestable:getWorld(), self.harvestable, self.params )
end

function BosstrainSideCartScoop.server_onFixedUpdate( self, timeStep )
    ParentedKinematic.server_onFixedUpdate( self, timeStep )

    local isMoving = self:sv_isMoving()
    
    if self.sv.wasMoving == false and isMoving then
        local contents = self.sv.areaTrigger:getContents()
        for _, character in ipairs( contents ) do
            local unit = character:getUnit()
            if unit then
                sm.event.sendToUnit( unit, "sv_e_tumble", { tumbleTickTime = TumbleTime } )
            end
        end
    end

    self.sv.wasMoving = isMoving
end

function BosstrainSideCartScoop.client_onClientDataUpdate( self, data, channel )
    ParentedKinematic.client_onClientDataUpdate( self, data, channel )
end

function BosstrainSideCartScoop.client_onCreate( self )
    ParentedKinematic.client_onCreate( self )
end

function BosstrainSideCartScoop.client_onFixedUpdate( self )
    if sm.isHost then
        return
    end
    ParentedKinematic.client_onFixedUpdate( self )
end
