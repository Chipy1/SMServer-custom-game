dofile("$SURVIVAL_DATA/Scripts/util.lua")
dofile( "$GAME_DATA/Scripts/gui/GridScrollView.lua" )

BuilderGuideInfoPanel = class( nil )

local guiData = dofile( "$SURVIVAL_DATA/Gui/JsonGuis/InfoPanel.gui" )
ReplaceSubLayouts( guiData )
local ItemSlot = dofile( "$SURVIVAL_DATA/Gui/JsonGuis/InfoPanelItem.gui" )
local ItemRootWidget = FindWidget( ItemSlot, "Item" )
local ItemImageWidget = FindWidget( ItemSlot, "Image" )
local ItemQuantityWidget = FindWidget( ItemSlot, "Quantity" )
local ItemKeyItemWidget = FindWidget( ItemSlot, "KeyItem" )
local ItemTypeWidget = FindWidget( ItemSlot, "Type")

function BuilderGuideInfoPanel.server_onCreate( self )
	self.sv = {}
	self.sv.storageFetched = false
	self.sv.saved = self.storage:load()
	if self.sv.saved == nil then
		self.sv.saved = {}

		local storageKey = TileStorageManager.Sv_GetTileStorageKeyFromObject( self.harvestable )
		TileStorageManager.Sv_SetValueInSubTable( storageKey, BUILDERGUIDE_PLATFORM_TABLE, "infoPanel", self.harvestable )
		self.storage:save( self.sv.saved )
	end
end

function BuilderGuideInfoPanel.server_onFixedUpdate( self )
	if self.sv.storageFetched == false then
		local storageKey = TileStorageManager.Sv_GetTileStorageKeyFromObject( self.harvestable )
		local value = TileStorageManager.Sv_GetValueInSubTable( storageKey, BUILDERGUIDE_PLATFORM_TABLE, "platformQuest" )
		if value then
			self.network:setClientData( value )
			self.sv.storageFetched = true
		end
	end
end

function BuilderGuideInfoPanel.sv_e_storageUpdated( self )
	self.sv.storageFetched = false
end

function BuilderGuideInfoPanel.sv_n_interact( self )
	QuestManager.Sv_SendEvent( "infoPanel" )
end

function BuilderGuideInfoPanel.client_onCreate( self )
	self.cl = {}
end

function BuilderGuideInfoPanel.client_onInteract( self, _, state )
	if state and self.cl.questName and not QuestManager.Cl_IsQuestComplete( self.cl.questName ) then
		self.network:sendToServer( "sv_n_interact" )
		self:cl_showGui()
	end
end

function BuilderGuideInfoPanel.cl_showGui( self )
	local content = sm.creation.getBlueprintCost( self.cl.blueprintPath, self.cl.platformBodyId )
	local playerInventory = sm.localPlayer.getPlayer():getInventory()
	self.cl.scrollView = GridScrollView()
	self.cl.gui = sm.jsonGui.createGui( { isInteractive = true, bNeedsCursor = true } )
	self.cl.scrollViewHolder = FindWidget( guiData, "ScrollViewParent" )
	self.cl.scrollView:setup( self.cl.scrollViewHolder, self.cl.gui )
	self.cl.scrollView:setGridItemSize( 77, 77 )
	self.cl.scrollView:setScrollStrength( 1 )
	self.cl.scrollView:clearGrid()
	self.cl.scrollView:resetScroll()
	for _, shapeData in ipairs( content ) do
		local resource, group, name, keyItem, type = sm.gui.getItemIconFromUuid( shapeData.uuid )
		local playerCount = sm.container.totalQuantity( playerInventory, shapeData.uuid )
		ItemImageWidget.ImageResource = resource
		ItemImageWidget.ImageGroup = group
		ItemImageWidget.ImageName = name
		local title = sm.shape.getShapeTitle( shapeData.uuid )
		ItemRootWidget.ToolTip.Text = title
		ItemKeyItemWidget.ImageTexture = keyItem
		ItemQuantityWidget.Caption = FormatGuiNumberCount( playerCount, shapeData.quantity )
		ItemTypeWidget.ImageName = type
		self.cl.scrollView:addGridItem( ItemSlot )
	end
	self.cl.gui:render( guiData )
end

function BuilderGuideInfoPanel.cl_onGuiClosed( self )
	self.cl.gui:close()
	self.cl.gui = nil
	self.cl.scrollView = nil
end

function BuilderGuideInfoPanel.client_canInteract( self )
	if not self.cl.questName then
		return false
	end

	if not QuestManager.Cl_IsQuestActive( self.cl.questName ) then
		return false
	end
	
	local keyBindingText = sm.gui.getKeyBinding( "Use", true )
    sm.gui.setInteractionText( "", keyBindingText, "#{INTERACTION_USE}" )
    return true
end

function BuilderGuideInfoPanel.cl_onHandleMouseWheel( self, _, scrollValue )
	self.cl.scrollView:handleScroll( scrollValue )
	self.cl.guiDirty = true
end

function BuilderGuideInfoPanel.cl_onScrollButtonPressed( self, _, x, y )
	self.cl.scrollView:handleScrollButtonPressed( x, y )
end

function BuilderGuideInfoPanel.cl_onScrollButtonReleased( self, _, x, y )
	self.cl.scrollView:handleScrollButtonReleased( x, y )
end

function BuilderGuideInfoPanel.cl_onScrollButtonDrag( self, _, x, y )
	self.cl.scrollView:handleScrollButtonDrag( x, y )
	self.cl.guiDirty = true
end

function BuilderGuideInfoPanel.cl_onScrollBarPressed( self, _, x, y )
	self.cl.scrollView:handleScrollBarPressed( x, y )
	self.cl.guiDirty = true
end

function BuilderGuideInfoPanel.client_onUpdate( self )
	if self.cl.guiDirty then
		self.cl.guiDirty = false
		self.cl.gui:render( guiData )
	end
end

function BuilderGuideInfoPanel.client_onClientDataUpdate( self, data )
	self.cl.blueprintPath = data.path
	self.cl.questName = data.questName
	self.cl.platformBodyId = data.bodyId
end