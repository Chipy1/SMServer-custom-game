PackerPumpArea = class( nil )

function PackerPumpArea.sv_init( self, position, dimensions, orientation, filter, shape )
    self.sv = {}
    if shape then
        self.sv.vacuumAreaTrigger = sm.areaTrigger.createAttachedBox( shape, dimensions, position, orientation, filter )
    else
        self.sv.vacuumAreaTrigger = sm.areaTrigger.createBox( dimensions, position, orientation, filter )
    end
    self.sv.vacuumAreaTrigger:bindOnEnter( "sv_t_onEnter", self )
    self.sv.vacuumAreaTrigger:bindOnExit( "sv_t_onExit", self )
    self.sv.vacuumAreaTrigger:bindOnStay( "sv_t_onStay", self )
    self.sv.bodiesInPackingArea = {}
end

function PackerPumpArea.cl_init( self, position, dimensions, orientation, filter, shape )
    self.cl = {}
    if shape then
        self.cl.vacuumAreaTrigger = sm.areaTrigger.createAttachedBox( shape, dimensions, position, orientation, filter )
    else
        self.cl.vacuumAreaTrigger = sm.areaTrigger.createBox( dimensions, position, orientation, filter )
    end
    self.cl.vacuumAreaTrigger:bindOnEnter( "cl_t_onEnter", self )
    self.cl.vacuumAreaTrigger:bindOnExit( "cl_t_onExit", self )
    self.cl.vacuumAreaTrigger:bindOnStay( "cl_t_onStay", self )
    self.cl.bodiesInPackingArea = {}
end

local function handleBody( body, valueFunction )
    for _, shape in ipairs( body:getShapes() ) do
        if shape:getShapeUuid() == ITEMS.obj_pneumatic_pump then
            valueFunction( shape )
        end
    end
end

function PackerPumpArea.sv_setPumpValues( self, results, valueFunction )
    for _, result in ipairs( results ) do
        if sm.exists( result ) then
            if type( result ) == "Body" then
                handleBody( result, valueFunction )
            end
        else
            if type( result ) == "Body" then
                local pumpShapes = self.sv.bodiesInPackingArea[result:getId()].pumpsOnBody
                if next( pumpShapes ) ~= nil then
                    for i, pumpShape in ipairs( pumpShapes ) do
                        if sm.exists( pumpShape ) then
                            handleBody( pumpShape:getBody(), valueFunction )
                        end
                    end
                end
            end
        end
    end
end

function PackerPumpArea.sv_t_onEnter( self, _, results )
    self:sv_setPumpValues( results, function( shape )
        local publicData = shape:getInteractable():getPublicData()
        publicData.isInsidePackingStationArea = true
        local pumpsOnBody = {}
        local shapes = shape:getBody():getShapes()
        for _, shape in ipairs( shapes ) do
            if shape:getShapeUuid() == ITEMS.obj_pneumatic_pump then
                table.insert( pumpsOnBody, shape )
            end
        end
        self.sv.bodiesInPackingArea[shape:getBody():getId()] = { rebuildTick = sm.game.getCurrentTick(), pumpsOnBody = pumpsOnBody }
    end )
end

function PackerPumpArea.sv_t_onStay( self, _, results )
    local changedBodies = {}

    for _, result in ipairs( results ) do
        if sm.exists( result ) then
            if type( result ) == "Body" then
                local bodyId = result:getId()
                local pumpsOnBody = {}
                local shapes = result:getShapes()
                for i, shape in ipairs( shapes ) do
                    if shape:getShapeUuid() == ITEMS.obj_pneumatic_pump then
                        table.insert( pumpsOnBody, shape )
                    end
                end

                if self.sv.bodiesInPackingArea[bodyId] ~= nil then
                    if result:hasChanged( self.sv.bodiesInPackingArea[bodyId].rebuildTick ) then
                        self.sv.bodiesInPackingArea[bodyId] = { rebuildTick = sm.game.getCurrentTick(), pumpsOnBody = pumpsOnBody }
                        table.insert( changedBodies, result )
                    end
                else
                    self.sv.bodiesInPackingArea[bodyId] = { rebuildTick = sm.game.getCurrentTick(), pumpsOnBody = pumpsOnBody }
                    table.insert( changedBodies, result )
                end
            end
        end
    end

    if #changedBodies > 0 then
        self:sv_setPumpValues( changedBodies, function( shape )
            local publicData = shape:getInteractable():getPublicData()
            if publicData then
                publicData.isInsidePackingStationArea = true
            else
                shape:getInteractable():setPublicData( { isInsidePackingStationArea = true } )
            end
        end )
    end
end

function PackerPumpArea.sv_t_onExit( self, _, results )
    self:sv_setPumpValues( results, function( shape )
        local publicData = shape:getInteractable():getPublicData()
        publicData.isInsidePackingStationArea = false
        table.remove( self.sv.bodiesInPackingArea, shape:getBody():getId() )
    end )
end

-- Client
function PackerPumpArea.cl_setPumpValues( self, results, valueFunction )
    for _, result in ipairs( results ) do
        if sm.exists( result ) then
            if type( result ) == "Body" then
                handleBody( result, valueFunction )
            end
        else
            if type( result ) == "Body" then
                local pumpShapes = self.cl.bodiesInPackingArea[result:getId()].pumpsOnBody
                if pumpShapes and next( pumpShapes ) ~= nil then
                    for _, pumpShape in ipairs( pumpShapes ) do
                        if sm.exists( pumpShape ) then
                            handleBody( pumpShape:getBody(), valueFunction )
                        end
                    end
                end
            end
        end
    end
end

function PackerPumpArea.cl_t_onEnter( self, _, results )
    self:cl_setPumpValues( results, function( shape )
        local publicData = shape:getInteractable():getClientPublicData()
        publicData.isInsidePackingStationArea = true
        local pumpsOnBody = {}
        local shapes = shape:getBody():getShapes()
        for _, shape in ipairs( shapes ) do
            if shape:getShapeUuid() == ITEMS.obj_pneumatic_pump then
                table.insert( pumpsOnBody, shape )
            end
        end
        self.cl.bodiesInPackingArea[shape:getBody():getId()] = { rebuildTick = sm.game.getCurrentTick(), pumpsOnBody = pumpsOnBody }
    end )
end

function PackerPumpArea.cl_t_onStay( self, _, results )
    local changedBodies = {}

    for _, result in ipairs( results ) do
        if sm.exists( result ) then
            if type( result ) == "Body" then
                local bodyId = result:getId()

                local pumpsOnBody = {}
                local shapes = result:getShapes()
                for i, shape in ipairs( shapes ) do
                    if shape:getShapeUuid() == ITEMS.obj_pneumatic_pump then
                        table.insert( pumpsOnBody, shape )
                    end
                end

                if self.cl.bodiesInPackingArea[bodyId] ~= nil then
                    if result:hasChanged( self.cl.bodiesInPackingArea[bodyId].rebuildTick ) then
                        self.cl.bodiesInPackingArea[bodyId] = { rebuildTick = sm.game.getCurrentTick(), pumpsOnBody = pumpsOnBody }
                        table.insert( changedBodies, result )
                    end
                else
                    self.cl.bodiesInPackingArea[bodyId] = { rebuildTick = sm.game.getCurrentTick(), pumpsOnBody = pumpsOnBody }
                    table.insert( changedBodies, result )
                end
            end
        end
    end

    if #changedBodies > 0 then
        self:cl_setPumpValues( changedBodies, function( shape )
            local publicData = shape:getInteractable():getClientPublicData()
            if publicData then
                publicData.isInsidePackingStationArea = true
            else
                shape:getInteractable():setClientPublicData( { isInsidePackingStationArea = true } )
            end
        end )
    end
end

function PackerPumpArea.cl_t_onExit( self, _, results )
    self:cl_setPumpValues( results, function( shape )
        local publicData = shape:getInteractable():getClientPublicData()
        publicData.isInsidePackingStationArea = false
        table.remove( self.cl.bodiesInPackingArea, shape:getBody():getId() )
    end )
end
