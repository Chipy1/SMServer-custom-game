dofile( "$SURVIVAL_DATA/Scripts/util.lua" )

PartUnlockStation = class( nil )

local LookAtRange = 10.0
local HeadUpOffset = 0.0
local HeadForwardOffset = -3.0
local HeadLerpSpeed = 1.0 / 15.0

local ItemButtonToIndex = {
	["Item1"] = 1,
	["Item2"] = 2,
	["Item3"] = 3,
}
local ResearchDuration = 2.0

local GuiData = sm.json.open( "$SURVIVAL_DATA/Gui/JsonGuis/SchematicbotJson.gui" )
local Listing = FindWidget( GuiData, "InventoryListing" )
local ItemButtons = {}
ItemButtons[#ItemButtons+1] = Listing.Childs[1]
ItemButtons[#ItemButtons+1] = Listing.Childs[2]
ItemButtons[#ItemButtons+1] = Listing.Childs[3]
local InactiveScanBackground = FindWidget( GuiData, "InactiveScanBackground" )
local ActiveScanBackground = FindWidget( GuiData, "ActiveScanHolder" )
local ProgressHolder = FindWidget( GuiData, "ProgressHolder" )
local ProgressBar = ProgressHolder.Childs[3]
local ProgressBarBackground = ProgressHolder.Childs[1]
local ResearchImage = FindWidget(GuiData, "ResearchImage" )
local InactiveScanButton = FindWidget( GuiData, "ScanButtonInactive" )
local ActiveScanButton = FindWidget( GuiData, "ScanButtonActive" )
local UnlockButton = FindWidget( GuiData, "UnlockButton" )
local CountText = FindWidget( GuiData, "SchematicCountText" )
local ResearchDragImage = FindWidget( GuiData, "ResearchDragImage" )
local ItemDragImage = FindWidget( GuiData, "ItemDragImage" )
local LeftButton = FindWidget( GuiData, "LeftButton" )
local RightButton = FindWidget( GuiData, "RightButton" )

function PartUnlockStation.sv_n_unlockPart( self, uuidStr, player )
	local uuid = sm.uuid.new( uuidStr )
	if uuid == ITEMS.obj_loot_schematic then
		sm.container.beginTransaction()
		sm.container.spend( player:getInventory(), uuid, 1 )
		if sm.container.endTransaction() then
			RecipeManager.Sv_UnlockRandom()
		end
	else
		RecipeManager.Sv_UnlockRecipe( uuidStr )
	end
end

function PartUnlockStation.client_onCreate( self )
	self.cl = {}
	self.cl.indexOffset = 0
	self.cl.pressedSlot = 0
	self.cl.researching = false
	self.cl.researchTime = 0.0

	self.cl.animState = nil
	self.cl.animName = nil
	self.cl.animDuration = 1
	self.cl.animTime = 0

	self.cl.upDownControl = 0.5
	self.cl.leftRightControl = 0.5
	self.interactable:setAnimEnabled( "aimbend_updown", true )
	self.interactable:setAnimEnabled( "aimbend_leftright", true )
end

function PartUnlockStation.client_canInteract( self )
	return true
end

function PartUnlockStation.client_onInteract( self, character, state )
	if state == true then
		self.cl.gui = sm.jsonGui.createGui( { isInteractive = true, bNeedsCursor = true } )

		if self.cl.researchData then
			ResearchImage.ImageName = self.cl.researchData.ImageName
			ResearchImage.ImageResource = self.cl.researchData.ImageResource
			ResearchImage.ImageGroup = self.cl.researchData.ImageGroup
		end
		self:cl_redrawGui()

		-- Popup layout widget placement corrections
		for _,index in pairs( ItemButtonToIndex ) do
			local left, top = self.cl.gui:getWidgetAbsolutePosition( ItemButtons[index].Childs[1].Name )
			ItemButtons[index].Childs[2].x = left
			ItemButtons[index].Childs[2].y = top
		end
		local left, top = self.cl.gui:getWidgetAbsolutePosition( "ResearchImage" )
		ResearchDragImage.x = left
		ResearchDragImage.y = top
		
		self.cl.scanEffectBox = self.cl.gui:getWidget( "ScanEffectBox" )
		self.cl.inactiveScanBackgroundEffectBox = self.cl.gui:getWidget( "InactiveScanBackgroundEffectBox" )

		self.cl.itemDragImage = self.cl.gui:getWidget( "ItemDragImage" )
		self.cl.currentDragEffectBox = nil

		self.cl.researchDragImage = self.cl.gui:getWidget( "ResearchDragImage" )

		self.cl.researchButtonEffectBox = self.cl.gui:getWidget( "ResearchButtonEffectBox" )
		self.cl.unlockButtonEffectBox = self.cl.gui:getWidget( "UnlockButtonEffectBox" )
		
		if self.cl.researching then
			self:cl_setResearchingVisibility()
			if self.cl.researchTime >= ResearchDuration then
				self:cl_setResearchingFinishedVisibility()
			else
				self.cl.scanEffectBox:startEffect( "scan" )
				ProgressHolder.Visible = true
			end
			self:cl_redrawGui()
		else
			self:cl_renderGui()
		end
	end
end

function PartUnlockStation.cl_onPressed( self, name, x, y )
	if not self.cl.researching and ItemButtons[ItemButtonToIndex[name]].Childs[1].Visible then
		local left, top = self.cl.gui:getWidgetAbsolutePosition( ItemButtons[ItemButtonToIndex[name]].Childs[1].Name )
		self.cl.pressedSlot = ItemButtonToIndex[name]
		ItemButtons[self.cl.pressedSlot].Childs[1].Visible = false
		ItemDragImage.Visible = true
		ItemDragImage.ImageName = ItemButtons[self.cl.pressedSlot].Childs[1].ImageName
		ItemDragImage.ImageResource = ItemButtons[self.cl.pressedSlot].Childs[1].ImageResource
		ItemDragImage.ImageGroup = ItemButtons[self.cl.pressedSlot].Childs[1].ImageGroup
		ItemDragImage.x = left
		ItemDragImage.y = top
		self.cl.currentDragX = left
		self.cl.currentDragY = top
		self.cl.previousDragX = x
		self.cl.previousDragY = y
		self.cl.currentStartLeft = left
		self.cl.currentStartTop = top
		self.cl.currentDragEffectBox = self.cl.gui:getWidget( ItemButtons[ItemButtonToIndex[name]].Childs[2].Name )
		self.cl.currentDragEffectBox:startEffect( "drag" )
		self:cl_renderGui()
	end
end

function PartUnlockStation.cl_onReleased( self, name, x, y )
	if not self.cl.researching and self.cl.pressedSlot > 0 then
		if self:cl_isDropInResearchArea( x, y ) then
			ItemButtons[self.cl.pressedSlot].Childs[1].Visible = false
			self.cl.researchData = {}
			self.cl.researchData.ImageName = ItemButtons[self.cl.pressedSlot].Childs[1].ImageName
			self.cl.researchData.ImageResource = ItemButtons[self.cl.pressedSlot].Childs[1].ImageResource
			self.cl.researchData.ImageGroup = ItemButtons[self.cl.pressedSlot].Childs[1].ImageGroup
			ResearchImage.Visible = true
			ResearchImage.ImageName = self.cl.researchData.ImageName
			ResearchImage.ImageResource = self.cl.researchData.ImageResource
			ResearchImage.ImageGroup = self.cl.researchData.ImageGroup
			self.cl.inactiveScanBackgroundEffectBox:startEffect( "activate" )
		end
		ItemDragImage.Visible = false
		if self.cl.currentDragEffectBox and sm.exists( self.cl.currentDragEffectBox ) then
			self.cl.currentDragEffectBox:stopEffect( "drag" )
			self.cl.currentDragEffectBox:setPosition( self.cl.currentStartLeft, self.cl.currentStartTop )
			self.cl.currentDragEffectBox = nil
		end
		self.cl.pressedSlot = 0
		self:cl_redrawGui()
	end
end

function PartUnlockStation.cl_onDrag( self, name, x, y )
	if not self.cl.researching and self.cl.pressedSlot > 0 then
		local xChange = x - self.cl.previousDragX
		local yChange = y - self.cl.previousDragY
		self.cl.previousDragX = x
		self.cl.previousDragY = y
		self.cl.currentDragX = self.cl.currentDragX + xChange
		self.cl.currentDragY = self.cl.currentDragY + yChange
		self.cl.itemDragImage:setPosition( self.cl.currentDragX, self.cl.currentDragY )
		self.cl.currentDragEffectBox:setPosition( self.cl.currentDragX, self.cl.currentDragY )
	end
end

function PartUnlockStation.cl_onResearchAreaPressed( self, name, x, y )
	if not self.cl.researching and self.cl.researchData then
		local left, top = self.cl.gui:getWidgetAbsolutePosition( "ResearchImage" )
		ResearchImage.Visible = false
		ResearchDragImage.Visible = true
		ResearchDragImage.ImageName = self.cl.researchData.ImageName
		ResearchDragImage.ImageResource = self.cl.researchData.ImageResource
		ResearchDragImage.ImageGroup = self.cl.researchData.ImageGroup
		self.cl.previousDragX = x
		self.cl.previousDragY = y
		self.cl.currentDragX = left
		self.cl.currentDragY = top
		ResearchDragImage.x = left
		ResearchDragImage.y = top
		self.cl.inactiveScanBackgroundEffectBox:startEffect( "drag" )
		self:cl_redrawGui()
	end
end

function PartUnlockStation.cl_onResearchAreaReleased( self, name, x, y )
	if not self.cl.researching and self.cl.researchData then
		if self:cl_isDropInResearchArea( x, y ) then
			ResearchImage.Visible = true
			self.cl.inactiveScanBackgroundEffectBox:startEffect( "activate" )
		else
			self.cl.researchData = nil
		end
		ResearchDragImage.Visible = false
		if sm.exists( self.cl.inactiveScanBackgroundEffectBox ) then
			self.cl.inactiveScanBackgroundEffectBox:stopEffect( "drag" )
			self:cl_redrawGui()
		end
	end
end

function PartUnlockStation.cl_onResearchDrag( self, name, x, y )
	if not self.cl.researching and self.cl.previousDragX then
		local xChange = x - self.cl.previousDragX
		local yChange = y - self.cl.previousDragY
		self.cl.previousDragX = x
		self.cl.previousDragY = y
		self.cl.currentDragX = self.cl.currentDragX + xChange
		self.cl.currentDragY = self.cl.currentDragY + yChange
		self.cl.researchDragImage:setPosition( self.cl.currentDragX, self.cl.currentDragY )
	end
end

function PartUnlockStation.cl_isDropInResearchArea( self, x, y )
	local left, top = self.cl.gui:getWidgetAbsolutePosition( "InactiveScanBackground" )
	if left ~= nil and top ~= nil then
		return  x > left and x < left + InactiveScanBackground.width and y > top and y < top + InactiveScanBackground.height
	end
	return false
end

function PartUnlockStation.cl_getResearchableShapeUuids( self )
	local player = sm.localPlayer.getPlayer()
	local playerContainer = player:getInventory()
	local containerUuids = sm.container.uniqueItemUuids( playerContainer )
	local unlockedRecipes = RecipeManager.Cl_GetUnlockedRecipes()
	local researchableParts = {}
	local schematicBoxAmount = 0
	for _, uid in ipairs( containerUuids ) do
		if ( RecipeManager.IsDisassemblableItem( uid ) and not unlockedRecipes[tostring( uid )] ) or ( uid == ITEMS.obj_loot_schematic and RecipeManager.Cl_CanUnlockRandom() ) then
			researchableParts[#researchableParts+1] = uid
			if uid == ITEMS.obj_loot_schematic and sm.game.getLimitedInventory() then
				schematicBoxAmount = math.min( sm.container.totalQuantity( playerContainer, uid ), RecipeManager.Cl_GetUnlockableAmount() )
			end
		end
	end
	return researchableParts, math.max( schematicBoxAmount - 1, 0 )
end

function PartUnlockStation.cl_redrawGui( self )
	if not self.cl.researching then
		if self.cl.researchData then
			InactiveScanButton.Visible = false
			ActiveScanButton.Visible = true
		else
			InactiveScanButton.Visible = true
			ActiveScanButton.Visible = false
		end
	end

	local itemIcons = {}
	itemIcons[#itemIcons+1] = ItemButtons[1].Childs[1]
	itemIcons[#itemIcons+1] = ItemButtons[2].Childs[1]
	itemIcons[#itemIcons+1] = ItemButtons[3].Childs[1]

	local researchableShapes, schematicBoxAmount = self:cl_getResearchableShapeUuids()
	local counter = 1
	LeftButton.Visible = not ( self.cl.indexOffset == 0 )
	RightButton.Visible = not ( self.cl.indexOffset > #researchableShapes - 4 )
	
	for i = 1, #researchableShapes - self.cl.indexOffset do
		if counter <= #itemIcons then
			local resource, group, name = sm.gui.getItemIconFromUuid( researchableShapes[i + self.cl.indexOffset] )
			if ( self.cl.researchData and name ~= self.cl.researchData.ImageName ) or not self.cl.researchData then
				itemIcons[counter].ImageResource = resource
				itemIcons[counter].ImageGroup = group
				itemIcons[counter].ImageName = name
				ItemButtons[counter].Visible = true
				ItemButtons[counter].Childs[1].Visible = true
			else
				ItemButtons[counter].Childs[1].Visible = false
			end
			counter = counter + 1
		else
			break
		end
	end
	if counter < 4 then
		for i = counter, 3 do
			ItemButtons[i].Visible = false
		end
	end

	CountText.Caption = string.format( sm.gui.translateLocalizationTags( "#{SCHEMATICBOT_COUNT}" ), #researchableShapes + schematicBoxAmount )

	self:cl_renderGui()

	self.cl.renderRevision = RecipeManager.Cl_GetUnlockedRevision()
end

function PartUnlockStation.cl_renderGui( self )
	self.cl.gui:render( GuiData )
end

function PartUnlockStation.client_onUpdate( self, dt )
	if self.cl.gui and self.cl.renderRevision ~= RecipeManager.Cl_GetUnlockedRevision() then
		self:cl_redrawGui()
	end
	local isResearching = false
	if self.cl.researching then
		if self.cl.researchTime <= ResearchDuration then
			self.cl.researchTime = self.cl.researchTime + dt
			isResearching = true
			if self.cl.gui then
				local progressWidth = math.floor( lerp( 10, ProgressBarBackground.width, self.cl.researchTime / ResearchDuration ) )
				ProgressBar.width = progressWidth
				if self.cl.researchTime >= ResearchDuration then
					self:cl_setResearchingFinishedVisibility()
					sm.effect.playEffect("audio:event:/ui/trading/schematicbot_scan_complete")
				end
				self:cl_renderGui()
			end
		end
	end

	self.cl.animState = isResearching and "craft" or "idle"
	self.cl.animTime = self.cl.animTime + dt
	local animDone = false
	if self.cl.animTime > self.cl.animDuration then
		self.cl.animTime = math.fmod( self.cl.animTime, self.cl.animDuration )
		animDone = true
	end
	local prevAnimName = self.cl.animName

	if self.cl.animState == "idle" then
		if self.cl.animName == nil then
			self.cl.animName = "idle"
		elseif self.cl.animName == "idle" then
			if animDone then
				local rand = math.random( 1, 5 )
				if rand == 1 then
					self.cl.animName = "idlespecial01"
				elseif rand == 2 then
					self.cl.animName = "idlespecial02"
				else
					self.cl.animName = "idle"
				end
			end
		elseif self.cl.animName == "idlespecial01" or self.cl.animName == "idlespecial02" then
			if animDone then
				self.cl.animName = "idle"
			end
		else
			if animDone then
				self.cl.animName = "idle"
			end
		end
	elseif self.cl.animState == "craft" then
		if isAnyOf( self.cl.animName, { "idle", "idlespecial01", "idlespecial02" } ) or self.cl.animName == nil then
			self.cl.animName = "craft_start"
			animDone = true
		elseif self.cl.animName == "craft_start" then
			if animDone then
				self.cl.animName = "craft_loop"
			end
		elseif self.cl.animName == "craft_loop" then
			if animDone then
				local researchTimeRemaining = math.max( ResearchDuration - self.cl.researchTime, 0.0 )
				if researchTimeRemaining <= 2 then
					self.cl.animName = "craft_finish"
				else
					--keep looping
				end
			end
		end
	end

	if self.cl.animName ~= prevAnimName then
		if prevAnimName then
			self.interactable:setAnimEnabled( prevAnimName, false )
			self.interactable:setAnimProgress( prevAnimName, 0 )
		end

		self.cl.animDuration = self.interactable:getAnimDuration( self.cl.animName )
		self.cl.animTime = 0

		self.interactable:setAnimEnabled( self.cl.animName, true )
	end
	self.interactable:setAnimProgress( self.cl.animName, self.cl.animTime / self.cl.animDuration )

	-- Look at animations
	local stationUp = self.shape:getAt()
	local stationRight = -self.shape:getRight()
	local upDownControl = 0.5
	local leftRightControl = 0.5
	local lookDirection = self.shape:getUp()
	if self.cl.animName == "idle" then
		local closestPlayer = GetClosestPlayer( self.shape.worldPosition, LookAtRange, self.shape.body:getWorld() )
		if closestPlayer then
			local lookAtPosition = closestPlayer.character.worldPosition
			local lookFromPosition = self.shape.worldPosition + self.shape:getAt() * HeadUpOffset + self.shape:getUp() * HeadForwardOffset
			lookDirection = ( lookAtPosition - lookFromPosition ):safeNormalize( lookDirection )

			-- Project look direction onto the stations's up-forward plane and right-forward plane
			local upProjection = lookDirection:dot( stationUp )
			local rightProjection = lookDirection:dot( stationRight )

			-- Map the projections to the control values assuming the valid range is non-negative
			upDownControl = clamp( 1.0 - ( ( upProjection + 1 ) / 2 ), 0, 1 )
			leftRightControl = clamp( ( rightProjection + 1 ) / 2, 0, 1 )
		end
	end

	self.cl.upDownControl = magicInterpolation( self.cl.upDownControl, upDownControl, dt, HeadLerpSpeed )
	self.cl.leftRightControl = magicInterpolation( self.cl.leftRightControl, leftRightControl, dt, HeadLerpSpeed )
	self.interactable:setAnimProgress( "aimbend_updown", self.cl.upDownControl )
	self.interactable:setAnimProgress( "aimbend_leftright", self.cl.leftRightControl )
end

function PartUnlockStation.cl_onGuiClosed( self )
	self.cl.indexOffset = 0
	if self.cl.gui then
		ItemDragImage.Visible = false
		self.cl.gui:close()
		self.cl.gui = nil
	end
end

function PartUnlockStation.cl_onLeftArrowClicked( self )
	self.cl.indexOffset = math.max( self.cl.indexOffset - 1, 0 )
	self:cl_redrawGui()
end

function PartUnlockStation.cl_onRightArrowClicked( self )
	local maximumOffset = math.max( 0, #self:cl_getResearchableShapeUuids() - 3 )
	self.cl.indexOffset = math.min( self.cl.indexOffset + 1, maximumOffset )
	self:cl_redrawGui()
end

function PartUnlockStation.cl_onScanClicked( self )
	self.cl.researching = true
	if self.cl.gui then
		sm.effect.playEffect("audio:event:/ui/trading/schematicbot_scan")
		self:cl_setResearchingVisibility()
		self.cl.scanEffectBox:startEffect( "scan" )
		self.cl.researchButtonEffectBox:startEffect( "scanbutton" )
		self:cl_redrawGui()
	end
end

function PartUnlockStation.cl_onUnlockedClicked( self )
	self.network:sendToServer( "sv_n_unlockPart", self.cl.researchData.ImageName )
	self.cl.researching = false
	self.cl.researchData = nil
	self.cl.researchTime = 0.0
	self.cl.unlockButtonEffectBox:startEffect( "collect" )
	self:cl_setPostUnlockVisibility()
	self:cl_redrawGui()
end

function PartUnlockStation.updateProgressBar( self )
	if self.widgets.progress then
		self.widgets.progress.x = math.floor( self.progressAnchorPos.x )
		self.widgets.progress.y = math.floor( self.progressAnchorPos.y )
		self.widgets.progress.width = math.floor( self.progressAnchorPos.x + self.widgets.handle.x )
	end
end

function PartUnlockStation.cl_setResearchingVisibility( self )
	InactiveScanBackground.Visible = false
	InactiveScanButton.Visible = false
	ActiveScanBackground.Visible = true
	ActiveScanButton.Visible = false
	ProgressHolder.Visible = true
end

function PartUnlockStation.cl_setResearchingFinishedVisibility( self )
	ProgressHolder.Visible = false
	UnlockButton.Visible = true
	self.cl.scanEffectBox:startEffect( "scandone" )
	self.cl.scanEffectBox:startEffect( "scandoneloop" )
	self.cl.scanEffectBox:stopEffect( "scan", true )
end

function PartUnlockStation.cl_setPostUnlockVisibility( self )
	UnlockButton.Visible = false
	InactiveScanBackground.Visible = true
	ActiveScanBackground.Visible = false
	ResearchImage.Visible = false
	self.cl.scanEffectBox:stopEffect( "scandoneloop", true )
end
