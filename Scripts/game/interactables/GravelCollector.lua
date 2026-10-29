dofile( "$SURVIVAL_DATA/Scripts/game/survival_collections.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/survival_items.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/interactables/ResourceContainer.lua" )
dofile( "$SURVIVAL_DATA/Scripts/util.lua")

GravelCollector = class( ResourceContainer )
GravelCollector.ContainerSize = 36
GravelCollector.AcceptedItems = g_gravelCollectorHarvests
GravelCollector.connectionInput = sm.interactable.connectionType.logic
GravelCollector.maxParentCount = 1
GravelCollector.maxChildCount = 0
GravelCollector.colorNormal = sm.color.new( 0xaf6114ff )
GravelCollector.colorHighlight = sm.color.new( 0xaf6114ff )
local HarvestScale = 0.13
local CenterOffset = 0.63
local ColumnOffset = 0.3
local RowOffset = 0.3
local CollectionRange = 3.0

local CollectModes = { input = 1, output = 2 }
local CollectorStealFrequency = math.floor( 0.05 * 40 )

function GravelCollector.server_onCreate( self )
    self.sv = {}
    self.sv.collectionRange = CollectionRange
	ResourceContainer.server_onCreate( self )
	self.sv.saved = self.storage:load()
    if self.sv.saved == nil then
        self.sv.saved = self.interactable:getCarryData() or {}
	end
	self.sv.saved.itemContents = self.sv.saved.itemContents or {}
	self.sv.saved.mode = self.sv.saved.mode or CollectModes.input

    local container = self.interactable:getContainer( 0 )
    if container then
        local itemQuantities = sm.container.quantity( container )
        for index,quantity in ipairs( itemQuantities ) do
            if quantity == 0 then
                self.sv.saved.itemContents[index] = nil
            end
        end
    end

	self.storage:save( self.sv.saved )
    self.interactable.publicData = { itemContents = {}, mode = self.sv.saved.mode }
    for index, data in pairs( self.sv.saved.itemContents ) do
        self.interactable.publicData.itemContents[index] = data
    end
    self.sv.collectorsLastStealTick = {}
    self.interactable:setCarryData( self.sv.saved )
end

local f_removedHarvests = { lastTick = 0, shapes = {} }
local clearFrequency = 5

function GravelCollector.server_onFixedUpdate( self )
    local currentTick = sm.game.getCurrentTick()
    if currentTick - f_removedHarvests.lastTick > clearFrequency then
        f_removedHarvests = { lastTick = currentTick, shapes = {} }
    end

    local parent = self.shape:getInteractable():getSingleParent()
    if parent then
        local wantedState = parent.active and CollectModes.output or CollectModes.input
        if self.sv.saved.mode ~= wantedState then
            self.sv.saved.mode = wantedState
            self.interactable.publicData.mode = self.sv.saved.mode
            self.storage:save( self.sv.saved )
        end
    elseif self.sv.saved.mode == CollectModes.output then
        self.sv.saved.mode = CollectModes.input
        self.interactable.publicData.mode = self.sv.saved.mode
        self.storage:save( self.sv.saved )
    end
end

function GravelCollector.processShapes( self, shapes )
    for _, shape in ipairs( shapes ) do
        if shape:getBody():getCreationId() ~= self.shape:getBody():getCreationId() then
            if isAnyOf( shape:getShapeUuid(), self.AcceptedItems ) then
                if self:canCollect( shape ) then
                    if not f_removedHarvests.shapes[shape:getId()] then
                        local container = self.interactable:getContainer( 0 )
                        if container then
                            local transactionSlot = nil
                            for i = 1, self.ContainerSize do
                                local slotItem = container:getItem( i - 1 )
                                if slotItem.quantity == 0 then
                                    transactionSlot = i - 1
                                    break
                                end
                            end
                            if transactionSlot then
                                sm.container.beginTransaction()
                                sm.container.collectToSlot( container, transactionSlot, shape:getShapeUuid(), 1, true )
                                local luaIndex = transactionSlot + 1
                                -- Check for itemContents in the shape
                                local itemContents = nil
                                if self.sv.saved and self.sv.saved.itemContents then
                                    -- Get shape interactable container if it exists
                                    local shapeInteractable = shape:getInteractable()
                                    if shapeInteractable and shapeInteractable.publicData then
                                        itemContents = shapeInteractable.publicData
                                    end
                                end

                                if sm.container.endTransaction() then
                                    if itemContents then
                                        self.sv.saved.itemContents[luaIndex] = itemContents
                                        self.interactable.publicData.itemContents[luaIndex] = itemContents
                                        self.interactable:setCarryData( self.sv.saved )
                                        self.storage:save( self.sv.saved )
                                    end
                                    local params = {
                                        shapeUuid = shape:getShapeUuid(),
                                        fromPosition = shape.worldPosition,
                                        fromRotation = shape.worldRotation,
                                        velocity = shape.body.velocity,
                                        angularVelocity = shape.body.angularVelocity,
                                        slotIndex = transactionSlot,
                                        showRenderable = true,
										scale = HarvestScale

                                    }
                                    self.network:sendToClients( "cl_n_addPickupItem", params )
                                    f_removedHarvests.lastTick = sm.game.getCurrentTick()
                                    f_removedHarvests.shapes[shape:getId()] = true
                                    shape:destroyShape()
                                end
                            end
                        end
                    end
                end
            end
            if self.shape:getId() ~= shape:getId() and self.shape:getShapeUuid() == shape:getShapeUuid() then
                if shape.interactable.publicData and shape.interactable.publicData.itemContents and shape.interactable.publicData.mode == CollectModes.output then
                    local toContainer = self.interactable:getContainer( 0 )
                    local fromContainer = shape.interactable:getContainer( 0 )
                    if toContainer and fromContainer then
                        if self.sv.collectorsLastStealTick[shape:getId()] == nil or sm.game.getCurrentTick() - self.sv.collectorsLastStealTick[shape:getId()] > CollectorStealFrequency then
                            local toTransactionSlot = nil
                            for i = 1, self.ContainerSize do
                                local slotItem = toContainer:getItem( i - 1 )
                                if slotItem.quantity == 0 then
                                    toTransactionSlot = i - 1
                                    break
                                end
                            end
                            local fromTransactionSlot = nil
                            local slotItem = nil
                            for i = fromContainer.size, 1, -1 do
                                slotItem = fromContainer:getItem( i - 1 )
                                if slotItem.quantity ~= 0 then
                                    fromTransactionSlot = i - 1
                                    break
                                end
                            end
                            if fromTransactionSlot and toTransactionSlot then
                                sm.container.beginTransaction()
                                sm.container.collectToSlot( toContainer, toTransactionSlot, slotItem.uuid, 1, true )
                                sm.container.spendFromSlot( fromContainer, fromTransactionSlot, slotItem.uuid, 1 )
                                if sm.container.endTransaction() then
                                    local contentData = shape.interactable.publicData.itemContents[fromTransactionSlot + 1]
                                    if contentData then
                                        self.sv.saved.itemContents[toTransactionSlot + 1] = contentData
                                        self.interactable.publicData.itemContents[toTransactionSlot + 1] = contentData
                                    end
                                    self.interactable:setCarryData( self.sv.saved )
                                    self.storage:save( self.sv.saved )
                                    local fromPos, fromRot = self:calculateSlotItemOffset( fromTransactionSlot )
                                    fromPos = shape.worldPosition + shape.worldRotation * fromPos
                                    fromRot = shape.worldRotation * fromRot
                                    self.network:sendToClients( "cl_n_addPickupItem", {
                                        shapeUuid = slotItem.uuid,
                                        fromPosition = fromPos,
                                        fromRotation = fromRot,
                                        velocity = shape.body.velocity,
                                        angularVelocity = shape.body.angularVelocity,
                                        slotIndex = toTransactionSlot,
                                        showRenderable = true,
										scale = HarvestScale,
										fromScale = HarvestScale

                                    } )
                                    self.sv.collectorsLastStealTick[shape:getId()] = sm.game.getCurrentTick()
                                else
                                    print("fail")
                                end
                            end
                        end
                    end
                end
            end
        end
    end
end

function GravelCollector.trigger_onEnter( self, trigger, contents )
    if self.sv.saved.mode == CollectModes.input then
        local shapes = {}
        for _, result in ipairs( contents ) do
            if sm.exists( result ) and type( result ) == "Shape" then
                shapes[#shapes+1] = result
            end
        end
        if #shapes > 0 then
            self:processShapes( shapes )
        end
    end
end

function GravelCollector.client_onCreate( self )
	ResourceContainer.client_onCreate( self )
    self.cl.gravelCollector = true
    self.cl.updateEffects = true
	self.cl.effect = sm.effect.createEffect( "Gravelcollector - Forcefield", self.interactable )
	self.cl.effect:setOffsetRotation(sm.vec3.getRotation( sm.vec3.new( 0, 1, 0 ), sm.vec3.new( 0, 0, 1 ) ))
	self.cl.effect:start()
    for _, value in ipairs(self.cl.harvestItems) do
        value.effect:setScale( sm.vec3.new( HarvestScale, HarvestScale, HarvestScale ) )
    end
end

function GravelCollector.cl_getRaycastSlot( self )
	local interactRange = 7.5
	local success, result = sm.localPlayer.getRaycast( interactRange )
	if success then
		local normalLocal = self.shape:transformDirection( result.normalWorld )
        local sideNumber = 0
        if normalLocal:dot(sm.vec3.new( -1, 0, 0 )) > 0.95 then sideNumber = 1
        elseif normalLocal:dot(sm.vec3.new( 0, 0, -1 )) > 0.95 then sideNumber = 2
        elseif normalLocal:dot(sm.vec3.new( 1, 0, 0 )) > 0.95 then sideNumber = 3
        elseif normalLocal:dot(sm.vec3.new( 0, 0, 1 )) > 0.95 then sideNumber = 4
        end
        if sideNumber ~= 0 then
            local intersectionWorldPos = result.originWorld + result.directionWorld * ( result.fraction)
            local localPoint = self.shape:transformPoint( intersectionWorldPos )
            local heightLocation = localPoint.y
            local rowNr = 0
            if heightLocation > RowOffset/2 then rowNr = 3
            elseif heightLocation < -RowOffset/2 then rowNr = 1
            else rowNr = 2
            end
            local columnPosition = 0
			local columnNr = 0
            if sideNumber == 1 then columnPosition = localPoint.z
            elseif sideNumber == 2 then columnPosition = -localPoint.x
            elseif sideNumber == 3 then columnPosition = -localPoint.z
            elseif sideNumber == 4 then columnPosition = localPoint.x
            end
            if columnPosition > ColumnOffset/2 then columnNr = 1
            elseif columnPosition < -ColumnOffset/2 then columnNr = 3
            else columnNr = 2
            end

            local rowSpot = ((sideNumber-1) * 3) + columnNr
            local index = ((rowNr-1) * 12) + rowSpot

            return index-1
        end
	end
	return 0
end

function GravelCollector.calculateSlotItemOffset( self, slotIndex )
    local xValues = {
        -CenterOffset, -CenterOffset, -CenterOffset,   --side 1
        -ColumnOffset, 0, ColumnOffset,                 --side 2
        CenterOffset, CenterOffset, CenterOffset,      --side 3
        ColumnOffset, 0, -ColumnOffset                  --side 4
    }
    local zValues = {
        ColumnOffset, 0, -ColumnOffset,               --side 1
        -CenterOffset, -CenterOffset, -CenterOffset, --side 2
        -ColumnOffset, 0, ColumnOffset,               --side 3
        CenterOffset, CenterOffset, CenterOffset     --side 4
    }
    local numberInLayer = (slotIndex % 12)
    local yValue = math.floor(slotIndex / 12) * RowOffset 
    local offsetBasePosition = sm.vec3.new( 0, -RowOffset, 0.0 )
    local positionOffset = offsetBasePosition + sm.vec3.new(xValues[numberInLayer+1], yValue, zValues[numberInLayer+1])
    local rotationValues = {
        sm.vec3.new( -1, 1, 0 ),
        sm.vec3.new( 0, 1, -1 ),
        sm.vec3.new( 1, 1, 0 ),
        sm.vec3.new( 0, 1, 1 ),
    }
    local sideNumber = math.floor((numberInLayer) / 3)
    local rotationOffset = sm.vec3.getRotation( sm.vec3.new( 0, 1, 0 ), rotationValues[sideNumber+1] )
	return positionOffset, rotationOffset
end

function GravelCollector.client_onDestroy( self )
	for _, harvestItem in ipairs( self.cl.harvestItems ) do
		if harvestItem.effect then
			harvestItem.effect:stop()
		end
	end
end