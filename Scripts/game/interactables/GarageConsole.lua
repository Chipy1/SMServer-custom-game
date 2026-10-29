dofile( "$GAME_DATA/Scripts/gui/GridScrollView.lua" )
GarageConsole = class()

local GarageGui = dofile( "$SURVIVAL_DATA/Gui/JsonGuis/GarageImporter.gui" )
ReplaceSubLayouts( GarageGui )
GarageGui.GridHolder = FindWidget( GarageGui, "GridHolder" )
local PreviewBox = FindWidget( GarageGui, "PreviewCanvas" )
local BlueprintNameBox = FindWidget( GarageGui, "BlueprintName" )
local ProgressText = FindWidget( GarageGui, "ProgressPercentages" )
local ProgressBarBackground = FindWidget( GarageGui, "ProgressBarBackground" )
local ProgressBar = FindWidget( GarageGui, "ProgressBar" )
local LoadButton = FindWidget( GarageGui, "LoadButton" )
local AssembleButton = FindWidget( GarageGui, "AssembleButton" )

local ItemSlot = dofile( "$SURVIVAL_DATA/Gui/JsonGuis/GarageImportItem.gui" )
local ItemRootWidget = FindWidget( ItemSlot, "Item" )
local ItemImageWidget = FindWidget( ItemSlot, "Image" )
local ItemQuantityWidget = FindWidget( ItemSlot, "Quantity" )
local ItemTypeWidget = FindWidget( ItemSlot, "Type" )
local ItemTypeCheckbox = FindWidget( ItemSlot, "Checkbox" )
local EffectGroundPosTweak = sm.vec3.new(0,0,11)
-- Server

function GarageConsole.server_onCreate( self )
    self.sv = {}

    self.sv.saved = self.storage:load() or {}

    local saveChanged = false

    if self.sv.saved.spawnAreaNode == nil then
        -- the cell ranges for this tile
        local xMin, xMax, yMin, yMax = GetTileRanges( self.shape:getWorldPosition(), self.shape.body:getWorld().id )

        -- Search for the spawn area node in this tile
        for x = xMin, xMax, 1 do
            for y = yMin, yMax, 1 do
                local areaTriggerNodes = sm.cell.getNodesByTag( x, y, "VOLUME" )
                for _, node in ipairs( areaTriggerNodes ) do
                    if node.params and node.params.name == "garage" then
                        self.sv.saved.spawnAreaNode = { scale = node.scale,position = node.position }
                        saveChanged = true
                        break
                    end
                end
                if self.sv.saved.spawnAreaNode then break end
            end
            if self.sv.saved.spawnAreaNode then break end
        end
    end
    
    self.sv.logAreaTrigger = sm.areaTrigger.createAttachedBox( self.shape, sm.vec3.new( 30, 11, 20 ), sm.vec3.new( 0, 0, -10 ), nil, sm.areaTrigger.filter.character )
    self.sv.logAreaTrigger:bindOnEnter( "sv_t_onLogAreaEnter", self )

    if self.sv.garage == nil and self.sv.saved.spawnAreaNode ~= nil then
        self.sv.garage = sm.garage.createGarage( GARAGE_IDS.SCRAP_CITY_GARAGE, self.shape:getBody():getWorld(), self.sv.saved.spawnAreaNode.scale / 2 ,  self.sv.saved.spawnAreaNode.position )
    end

    if saveChanged then
        self.storage:save( self.sv.saved )
    end
    self.network:setClientData( { spawnAreaNode = self.sv.saved.spawnAreaNode } )
end

function GarageConsole.server_onDestroy( self )
    self.sv.logAreaTrigger:destroy()
    self.sv.logAreaTrigger = nil
end

function GarageConsole.sv_t_onLogAreaEnter( self, trigger, results )
    for _, result in pairs( results ) do
        if result:isPlayer() then
            TutorialManager.Sv_TutorialEvent( TutorialEvent.Garage, result:getPlayer() )
            if not LogEntryManager.Sv_HasLog( LOGS.log_garage ) then
                LogEntryManager.Sv_AddLog( LOGS.log_garage )
            end
            break
        end
    end
end

function GarageConsole.sv_n_tryFillChest( self,_ ,player )
    local contentToFill = {}
    local containers = GarageImportManager.Sv_GetContainers( GARAGE_IDS.SCRAP_CITY_GARAGE )
    local _,bpTable = self.sv.garage:getTrackedBlueprint()
    local bpCost = sm.creation.getBlueprintCost( bpTable )

    if containers then
        local neededQuantity = 0
        local playerInventory = player:getInventory()
        if playerInventory then
            for _, shapeData in ipairs( bpCost ) do
                neededQuantity = shapeData.quantity
                local availableQuantity = sm.container.totalQuantity( playerInventory, shapeData.uuid )
                for _, container in ipairs( containers ) do
                    if sm.exists( container ) then
                        neededQuantity = neededQuantity - sm.container.totalQuantity( container, shapeData.uuid )
                        if neededQuantity < 1 then
                            break
                        end
                    end
                end
                if neededQuantity > 0  and availableQuantity > 0 then
                    table.insert( contentToFill, { uuid = shapeData.uuid, amount = math.min( neededQuantity,availableQuantity ) } )
                end
            end

            sm.container.beginTransaction()
            for _, content in pairs( contentToFill ) do
                for _, container in ipairs( containers ) do
                    local collected = sm.container.collect( container, content.uuid, content.amount,false )
                    local amount = sm.container.spend( playerInventory, content.uuid, collected )
                    content.amount = content.amount - amount
                    if content.amount < 1 then
                        break
                    end
                end
            end
            sm.container.endTransaction()
        end
    end
end

function GarageConsole.sv_n_assembleBlueprint( self,_, player )
    local _, blueprint = self.sv.garage:getTrackedBlueprint()
    if type( blueprint ) ~= "table" or not blueprint.bodies then
        return
    end

    local containers = GarageImportManager.Sv_GetContainers(GARAGE_IDS.SCRAP_CITY_GARAGE)

    if containers then
        local content = sm.creation.getBlueprintCost( blueprint )

        for _, shapeData in ipairs( content ) do
            if not sm.shape.uuidExists( shapeData.uuid ) then
                print( "Blueprint contains invalid part: " .. tostring( shapeData.uuid ) )
                return
            end
            if shapeData.quantity < 0 then
                print( "Blueprint contains invalid quantity: " .. tostring( shapeData.quantity ) )
                return
            end
            local available = 0
            for _, container in ipairs( containers ) do
                if sm.exists( container ) then
                    available = available + sm.container.totalQuantity( container, shapeData.uuid )
                    if available >= shapeData.quantity then
                        break
                    end
                end
            end
            if available < shapeData.quantity then
                print( "Not enough resources in chest to assemble blueprint" )
                return
            end
        end

        for _, shapeData in ipairs( content ) do
            local requiredAmount = shapeData.quantity
            for _, container in ipairs( containers ) do
                if sm.exists( container ) then
                    sm.container.beginTransaction()
                    local amount = sm.container.spend( container, shapeData.uuid, requiredAmount, false )
                    sm.container.endTransaction()
                    requiredAmount = requiredAmount - amount
                    if requiredAmount <= 0 then
                        break
                    end
                end
            end
        end
    else
        print( "No garage chest found to assemble from" )
        return
    end

    self.network:sendToClient( player, "cl_n_assemble" )
end

function GarageConsole.sv_n_onCancelTracking( self )
    self.network:sendToClients( "cl_n_onCancelTrack" )
end

function GarageConsole.sv_n_triggerSpawnEffect( self )
    self.network:sendToClients( "cl_n_triggerSpawnEffect" )
end
-- Client
function GarageConsole.client_onCreate( self )
    self.cl = {}
    self.cl.stateChangeRequested = false
    self.cl.closeGui = false
    self.cl.garageChestsRevisions = {}
    self.cl.effects = {}
    self.cl.effectsPlaying = false
    self.cl.assembleTimer = 0
    self.cl.effects.swapColor = false
    self.cl.effects.baseProjection = sm.effect.createEffect( "Scrapcitygarage - BaseActive" )
    self.cl.effects.creationActive = sm.effect.createEffect( "Scrapcitygarage - CreationActive" )
end

function GarageConsole.client_onDestroy( self )
    
    self:cl_onGuiClosed()
end

function GarageConsole.client_onClientDataUpdate( self, data )
 if self.cl.garage == nil  then
        if sm.isHost == false then
            
            if data.spawnAreaNode then
                self.cl.garage = sm.garage.createGarage( GARAGE_IDS.SCRAP_CITY_GARAGE,
                    self.shape:getBody():getWorld(),
                    data.spawnAreaNode.scale / 2,
                    data.spawnAreaNode.position
                )
            end

        else 
            self.cl.garage = self.sv.garage
        end
    end
end
function GarageConsole.client_canInteract( self )
    if self.cl.garage then
        return true
    end
    return false
end

function GarageConsole.client_onFixedUpdate( self )
    if self.cl.garage == nil then return end

    local hasActiveTracking = self.cl.garage:hasActiveTracking()
    local garageContainers = GarageImportManager.Cl_GetContainers( GARAGE_IDS.SCRAP_CITY_GARAGE )

    local refreshGui = false
    local refreshPreview = false

    local trackingRevision = self.cl.garage:getTrackingRevision()
    if trackingRevision ~= self.cl.trackingRevision then
        self.cl.trackingRevision = trackingRevision
        if self.cl.gui then
            local name, data = self.cl.garage:getTrackedBlueprint()
            if data ~= nil and name ~= nil then
                refreshGui = true
                refreshPreview = true
              
            end
        end
    end
    if self.cl.gui and garageContainers and self.cl.stateChangeRequested then
        self.cl.stateChangeRequested = false
        if self.cl.openSelection then
            self.cl.openSelection = false
            self:cl_onGuiClosed()
            self.cl.delayedOpen = true
        elseif self.cl.closeGui then
            self.cl.closeGui = false
            self:cl_onGuiClosed()
        else
            local name, data = self.cl.garage:getTrackedBlueprint()
            if data ~= nil and name ~= nil then
                refreshGui = true
                refreshPreview = true
            end
        end  
    elseif garageContainers and self.cl.gui then
        local currentRevisions = {}
        for _, container in ipairs( garageContainers ) do
            if sm.exists( container ) then
                local currentRevision = container:getRevision()
                if currentRevision ~= self.cl.garageChestsRevisions[container.id] then
                    refreshGui = true
                end
                currentRevisions[container.id] = currentRevision
            end
        end
        self.cl.garageChestsRevisions = currentRevisions
    elseif self.cl.delayedOpen then
        self.cl.delayedOpen = false
        sm.gui.openGarageImportGui()
        sm.gui.setGarageButtonCallback( "cl_e_trackBlueprint" )
        sm.gui.setGarageErrorCallback( "cl_onError" )
    end

    if refreshGui and self.cl.gui then
        local name, data = self.cl.garage:getTrackedBlueprint( )
        local validBlueprint = type( data ) == "table" and data.bodies ~= nil and name ~= nil
        if validBlueprint then
            self:cl_updateData(  name, garageContainers )
            self.cl.gui:render( GarageGui )
        end
        if refreshPreview  then
            if validBlueprint then
                local previewBox = self.cl.gui:getWidget( "PreviewCanvas" )
                previewBox:setPreview( data )
            end
        end
    end

    local shouldShowEffects = hasActiveTracking
    if shouldShowEffects and not self.cl.effectsPlaying then
        self:cl_startGarageEffects()
        self.cl.effectsPlaying = true
    elseif not shouldShowEffects and self.cl.effectsPlaying then
        self:cl_stopGarageEffects()
        self.cl.effectsPlaying = false
    end


    if self.cl.assembleTimer then
        self.cl.assembleTimer = self.cl.assembleTimer - 1 / 40
        if self.cl.assembleTimer <= 0 then
            self.cl.assembleTimer = nil

            if self.cl.assemblePhase == "prespawn" then
                self.network:sendToServer( "sv_n_assembleBlueprint" )
                self.cl.assemblePhase = nil
            end
        end
    end

    if hasActiveTracking then
        local fits = self.cl.garage:creationFits()
        if fits and self.cl.effects.swapColor ~= true then
            self:cl_setEffectColors( fits )
            self.cl.effects.swapColor = true
        elseif not fits and self.cl.effects.swapColor ~= false then
            self:cl_setEffectColors( fits )
            self.cl.effects.swapColor = false
        end
    end
end

function GarageConsole.cl_setEffectColors( self,fits )
    if fits then
        local color = sm.color.new( "0075ffff" )
        self.cl.effects.baseProjection:setParameter( "Color", color )
        self.cl.effects.baseProjection:setParameter( "renderableColor", color )
        self.cl.effects.creationActive:setParameter( "Color", color )
        self.cl.effects.creationActive:stop()
        self.cl.effects.creationActive:start()
        self.cl.effects.baseProjection:stopImmediate()
        self.cl.effects.baseProjection:start()
    else
        local color = sm.color.new( "ff1700ff" )
        self.cl.effects.baseProjection:setParameter( "Color", color )
        self.cl.effects.baseProjection:setParameter( "renderableColor", color )
        self.cl.effects.creationActive:setParameter( "Color", color )
        self.cl.effects.creationActive:stop()
        self.cl.effects.creationActive:start()
        self.cl.effects.baseProjection:stopImmediate()
        self.cl.effects.baseProjection:start()
        
    end
end

function GarageConsole.cl_onError( self, error )
    NotificationManager.Cl_AddGenericNotification( error )
end

function GarageConsole.cl_loadData( self, bpTable, name, containers )
    self.cl.gui = sm.jsonGui.createGui( { isInteractive = true, bNeedsCursor = true } )
    self.cl.scrollView = GridScrollView()
    self.cl.scrollViewHolder = FindWidget( GarageGui, "GridHolder" )
    self.cl.scrollView:setup( self.cl.scrollViewHolder, self.cl.gui )
    self.cl.scrollView:setGridItemSize( 77, 77 )
    self.cl.scrollView:setScrollStrength( 1 )
    self.cl.scrollView:clearGrid()
    self.cl.scrollView:resetScroll()
    self.cl.content = sm.creation.getBlueprintCost( bpTable )
    self:cl_updateData( name, containers )
    self.cl.gui:render( GarageGui )
    local previewBox = self.cl.gui:getWidget( "PreviewCanvas" )
    if previewBox then
        previewBox:setPreview( bpTable )
    end
    self.cl.assembleEffectBox = self.cl.gui:getWidget( "AssembleEffectBox" )
end

function GarageConsole.cl_updateData( self, name, containers )
    self.cl.scrollView:clearGrid()
    BlueprintNameBox.Caption = name
    local totalCount = 0
    local currentCount = 0
    for _, shapeData in ipairs( self.cl.content ) do
        local resource, group, name, keyItem, type = sm.gui.getItemIconFromUuid( shapeData.uuid )
        local chestCount = 0
        for _, container in ipairs( containers ) do
            if sm.exists( container ) then
                chestCount = chestCount + sm.container.totalQuantity( container, shapeData.uuid )
            end
        end

        ItemImageWidget.ImageResource = resource
        ItemImageWidget.ImageGroup = group
        ItemImageWidget.ImageName = name
        local title = sm.shape.getShapeTitle( shapeData.uuid )
        ItemRootWidget.ToolTip.Text = title

        ItemQuantityWidget.Caption = FormatGuiNumberCount( chestCount, shapeData.quantity )
        totalCount = totalCount + shapeData.quantity
        currentCount = currentCount + math.min( chestCount, shapeData.quantity )
        if chestCount >= shapeData.quantity then
            ItemTypeCheckbox.Visible = true
        else
            ItemTypeCheckbox.Visible = false
        end
        ItemTypeWidget.ImageName = type
        self.cl.scrollView:addGridItem( ItemSlot )
    end
    local fraction = totalCount > 0 and currentCount / totalCount or 1
    local percentage = math.floor( fraction * 100 )
    ProgressBar.width = math.floor( fraction * ProgressBarBackground.width * 0.98 )
    ProgressText.Caption = tostring( percentage ) .. "%"
    if percentage == 100 then
        LoadButton.Visible = false
        AssembleButton.Visible = true
    else
        LoadButton.Visible = true
        AssembleButton.Visible = false
    end
end

function GarageConsole.cl_e_trackBlueprint( self, path, name )
    -- only possible to track blueprints you have locally on disk.
    local _, trackedData = self.cl.garage:getTrackedBlueprint()
    
    if trackedData == nil then
        if sm.json.fileExists( path ) == false then
            return
        end
        self.cl.currentTrackedBlueprintPath = path
        local data = sm.json.open( path, true )
        self.cl.garage:trackBlueprint( path )
        local garageContainers = GarageImportManager.Cl_GetContainers( GARAGE_IDS.SCRAP_CITY_GARAGE )
        -- update gui
        self:cl_loadData( data, name, garageContainers )
    else
        NotificationManager.Cl_AddGenericNotification(  "#{GARAGE_ALREADY_TRACKED_CREATION}" )
    end
end

function GarageConsole.client_onInteract( self, _, state )
    self.cl.stateChangeRequested = false
    self.cl.closeGui = false

    if not state then
        return
    end
   
    local garageContainers = GarageImportManager.Cl_GetContainers( GARAGE_IDS.SCRAP_CITY_GARAGE )

    if garageContainers then
        sm.gui.setGarageImportGuiStorage( garageContainers )
    else
        print( "Garage Error: containers missing" )
        return
    end

    local name, data = self.cl.garage:getTrackedBlueprint()
    if data ~= nil then
        self:cl_loadData( data, name,garageContainers )
        return
    end
    if  garageContainers then
        sm.gui.openGarageImportGui()
        sm.gui.setGarageButtonCallback( "cl_e_trackBlueprint" )
        sm.gui.setGarageErrorCallback( "cl_onError" )
    end
end

function GarageConsole.cl_onGuiClosed( self )
    if self.cl.gui then
        self.cl.gui:close()
        self.cl.gui = nil
        self.cl.scrollView = nil
    end
end

function GarageConsole.cl_onHandleMouseWheel( self, _, scrollValue )
    self.cl.scrollView:handleScroll( scrollValue )
    self.cl.guiDirty = true
end

function GarageConsole.cl_onScrollButtonPressed( self, _, x, y )
    self.cl.scrollView:handleScrollButtonPressed( x, y )
end

function GarageConsole.cl_onScrollButtonReleased( self, _, x, y )
    self.cl.scrollView:handleScrollButtonReleased( x, y )
end

function GarageConsole.cl_onScrollButtonDrag( self, _, x, y )
    self.cl.scrollView:handleScrollButtonDrag( x, y )
    self.cl.guiDirty = true
end

function GarageConsole.cl_onScrollBarPressed( self, _, x, y )
    self.cl.scrollView:handleScrollBarPressed( x, y ) 
    self.cl.guiDirty = true
    end

function GarageConsole.client_onUpdate( self )
    if self.cl.guiDirty then
        self.cl.guiDirty = false
        self.cl.gui:render( GarageGui )
    end
end

function GarageConsole.cl_onLoadClick( self )
        self.network:sendToServer( "sv_n_tryFillChest" )
        self.cl.stateChangeRequested = true
        self.cl.closeGui = false
end

function GarageConsole.cl_onAssembleClick( self )
    if self.cl.assembleTimer and self.cl.assembleTimer > 0 then 
        return 
    end

    local name, data = self.cl.garage:getTrackedBlueprint( )
    local fits = self.cl.garage:creationFits(  )
    
    if data ~= nil and not self.cl.stateChangeRequested and fits then
        self.cl.closeGui = true
        self.cl.stateChangeRequested = true
        self.cl.assemblePhase = "prespawn"
        self.cl.assembleTimer = 1.0
        self.network:sendToServer( "sv_n_triggerSpawnEffect" )
       

    else
        self:cl_onError( "#{CLEAR_BUILD_AREA}" )
    end
end

function GarageConsole.cl_n_assemble( self )
    local activeTracking = self.cl.garage:hasActiveTracking(  )

    if activeTracking and not self.cl.stateChangeRequested then
        self.cl.stateChangeRequested = true
        self.cl.closeGui = true
        self.cl.garage:importBlueprint( )
    end
end

function GarageConsole.cl_onCancelClick( self )
    if not self.cl.stateChangeRequested then
        self.network:sendToServer( "sv_n_onCancelTracking" )
    end
end

function GarageConsole.cl_n_onCancelTrack( self )
    sm.effect.playEffect( "audio:event:/ui/blueprint/bp_delete", self.cl.garage:getPosition() )
    self.cl.garage:untrackBlueprint( )
    self.cl.openSelection = true
    self.cl.stateChangeRequested = true
    self.cl.content = nil

end

function GarageConsole.cl_startGarageEffects( self )
    local effectPosGround = self.cl.garage:getPosition() - EffectGroundPosTweak
    self.cl.effects.baseProjection:start()
    self.cl.effects.baseProjection:setPosition( effectPosGround )
    self.cl.effects.creationActive:start()
    self.cl.effects.creationActive:setPosition( effectPosGround )
    local fits = self.cl.garage:creationFits(  )
    self:cl_setEffectColors(fits)

    local position = self.cl.garage:getPlacement(  )
    if position then
        self.cl.effects.creationActive:setPosition( effectPosGround )
    end
end

function GarageConsole.cl_stopGarageEffects( self )
    self.cl.effects.baseProjection:stop()
    self.cl.effects.creationActive:stop()
end

function GarageConsole.cl_n_triggerSpawnEffect( self )
    self:cl_stopGarageEffects()
    local pos = self.cl.garage:getPlacement( )
    local blueprintBounds = self.cl.garage:getBlueprintBounds()
    local min = blueprintBounds[1]
    local max = blueprintBounds[2]

    local blueprintScale = sm.vec3.getDistance( min, max )

    if blueprintScale < 2 then
        sm.effect.playEffect( "Scrapcitygarage - Spawneffecttiny", pos )
    elseif blueprintScale < 4 then
        sm.effect.playEffect( "Scrapcitygarage - Spawneffectsmall", pos )
    elseif blueprintScale < 7 then
        sm.effect.playEffect( "Scrapcitygarage - Spawneffectmedium", pos )
    elseif blueprintScale >= 7 then
        sm.effect.playEffect( "Scrapcitygarage - Spawneffectlarge", pos )
    end
end
