GarageChest = class()
GarageChest.poseWeightCount = 1


-- Server

function GarageChest.server_onCreate( self )
    local container = self.shape:getInteractable():getContainer( 0 )
    if not container then
        container = self.shape:getInteractable():addContainer( 0, 30 )
    end
    self.sv = {}
    self.sv.containerHash = self:sv_getContainerHash()
    self.sv.lastUpdatedTick = sm.game.getCurrentTick()

    GarageImportManager.Sv_AssignContainers( GARAGE_IDS.SCRAP_CITY_GARAGE, self:sv_getContainers() )
end

function GarageChest.server_onFixedUpdate(self)
    if self.shape:getBody():hasChanged(self.sv.lastUpdatedTick) then
        local newHash = self:sv_getContainerHash()
        self.sv.lastUpdatedTick = sm.game.getCurrentTick()

        if self.sv.containerHash ~= newHash then
            GarageImportManager.Sv_AssignContainers( GARAGE_IDS.SCRAP_CITY_GARAGE, self:sv_getContainers() )
            self.sv.containerHash = newHash
        end
       
    end
end

function GarageChest.sv_getContainers( self )
        local containerShapes = sm.pipeGraph.getInputContainers( self.shape )
        table.insert( containerShapes, 1, self.shape )
        local containers = {}
        for _, shape in ipairs( containerShapes ) do
            local interactable = shape:getInteractable()
            local container    = interactable:getContainer()
            table.insert( containers, container )
        end
        return containers
end

function GarageChest.sv_getContainerHash( self )
    local containerShapes = sm.pipeGraph.getInputContainers( self.shape )
    table.insert( containerShapes, 1, self.shape )

     local hash = ""
    for _, shape in ipairs( containerShapes ) do
            local c = shape:getInteractable():getContainer( 0 )
            local id = sm.container.getId(c)
            hash = hash .. tostring( id ) .. ","
    end
    return hash
end
-- Client

function GarageChest.client_onCreate( self )
    self.cl = {}
    self.cl.weight = 0
    self.cl.isOpen = false
end



function GarageChest.client_onUpdate(self,dt)
	local isOpen = self.cl.isOpen

    local weight = self.cl.weight
	if isOpen then
		weight = math.min( weight + dt * 10.0, 1.0 )
	else
		weight = math.max( weight - dt * 10.0, 0.0 )
	end
	self.cl.weight = weight
    if self.shape.interactable then
        self.shape.interactable:setPoseWeight( 0, weight )
    end
end

function GarageChest.client_canInteract( self )
    if self.shape:getInteractable():getContainer( 0 ) then
        return true
    end
    return false
end

function GarageChest.client_onInteract( self, _, state )
    if state == true then
        local gui = sm.gui.createContainerGui( true )
        gui:setText( "UpperName", "#{TUTORIAL_GARAGE_TITLE}" )
        gui:setContainer( "UpperGrid", self.shape:getInteractable():getContainer( 0 ) )
        gui:setText( "LowerName", "#{INVENTORY_TITLE}" )
		gui:setOnCloseCallback( "cl_e_onClose" )
        gui:setContainer( "LowerGrid", sm.localPlayer.getInventory() )
        gui:setOpenCloseEffect( "Gui - ChestOpen", "Gui - ChestClose" )
        gui:open()
        self.cl.isOpen = true

    end
end

function GarageChest.cl_e_onClose(self)
    self.cl.isOpen = false
end

