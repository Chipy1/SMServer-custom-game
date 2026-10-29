dofile( "$SURVIVAL_DATA/Scripts/game/kinematics/Kinematic.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/kinematics/ParentedKinematicRoot.lua" )
dofile( "$SURVIVAL_DATA/Scripts/util.lua" )

CombatRoomButton = class( ParentedKinematicRoot )

function CombatRoomButton.server_onCreate( self )
    ParentedKinematicRoot.server_onCreate( self )
    self.sv.node = nil
    self:sv_tryGetNode()
    if self.params.eventTrigger ~= "" then
        KinematicManager.Sv_RegisterToEvent( self.harvestable, self.sv.tileStorageKey, self.params.eventTrigger )
    end
end

function CombatRoomButton.sv_e_interact( self )
    if self.sv.node == nil then
        self:sv_tryGetNode()
    end

    if self.sv.node then
        self.sv.node.params.world = self.harvestable:getWorld()
        self.sv.node.params.roomNameTag = self.sv.node.params.name..self.sv.tileStorageKey
        if self.params.eventTrigger ~= "" then
            self.sv.node.params.buttonTag = self.params.eventTrigger
        end
        CombatRoomManager.Sv_ActivateCombatRoom( self.sv.node, self.harvestable )
    else
        sm.log.error( "No matching node was found for the combat room button with room name:", self.params.connectedNodeName )
    end
end

function CombatRoomButton.sv_tryGetNode( self )
    if self.sv.node == nil then
        local matchingNode = nil
        local xMin, xMax, yMin, yMax = GetTileRanges( self.harvestable.worldPosition, self.harvestable:getWorld().id )
        local breakAll = false
        for  x = xMin, xMax  do
			for y = yMin, yMax do
                local cellNodes = sm.cell.getNodesByTag( x, y, "GROWLAB_COMBAT_ROOM" )
                for _, node in ipairs( cellNodes ) do
                    if node.params.name == self.params.connectedNodeName then
                        matchingNode = node
                        breakAll = true
                    end
                    if breakAll then break end
                end
                if breakAll then break end
            end
            if breakAll then break end
        end
        if matchingNode then
            self.sv.node = matchingNode
            self.network:setClientData( { roomName = self.sv.node.params.name..self.sv.tileStorageKey }, 4 )
        end
    end
end

-- Client

function CombatRoomButton.client_onClientDataUpdate( self, data, channel )
    if channel == 4 then
        self.cl.roomName = data.roomName
    else
        ParentedKinematicRoot.client_onClientDataUpdate( self, data, channel )
    end
end

function CombatRoomButton.client_canInteract( self )
    if self.cl.roomName and CombatRoomManager.Cl_IsRoomActive( self.cl.roomName ) then
        return false
    end
    local keyBindingText = sm.gui.getKeyBinding( "Use", true )
    sm.gui.setInteractionText( "", keyBindingText, "#{INTERACTION_USE}" )
    return true
end

function CombatRoomButton.client_onInteract( self, _, state )
    if state then
        self.network:sendToServer( "sv_e_interact" )
    end
end