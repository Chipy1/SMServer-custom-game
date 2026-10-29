dofile( "$SURVIVAL_DATA/Scripts/game/survival_constants.lua" )
-- LostItems.lua --

LostItems = class( nil )

function LostItems.server_onCreate( self )
	local container = self.shape.interactable:getContainer( 0 )
	if container then
		container.allowSpend = true
		container.allowCollect = false
	end
	
	self.sv = {}
	self.sv.loaded = true
	
	self.sv.saved = self.storage:load()
	if self.sv.saved == nil then
		self.sv.saved = {}
		self.sv.saved.creationTick = sm.game.getCurrentTick()
	end
	if self.sv.saved.creationTick == nil then
		self.sv.saved.creationTick = sm.game.getCurrentTick()
	end
	if self.params then
		if self.params.owner then
			self.sv.saved.owner = self.params.owner
		end
	end
	self.storage:save( self.sv.saved )
	self.network:setClientData( self.sv.saved )
 
	g_respawnManager:sv_unmarkBag( self.shape )
end

function LostItems.server_onUnload( self )
	if self.sv.loaded then
		if sm.game.getCurrentTick() - self.sv.saved.creationTick < LOST_BAG_SHOW_TICKS then
			g_respawnManager:sv_markBag( self.shape, self.sv.saved.owner, self.sv.saved.creationTick )
		end
		self.sv.loaded = false
	end
end

function LostItems.server_onDestroy( self )
	if self.sv.loaded then
		g_respawnManager:sv_unmarkBag( self.shape )
		self.sv.loaded = false
	end
end

function LostItems.client_onCreate( self )
	if self.cl == nil then
		self.cl = {}
	end
	self.cl.compassEnabled = sm.game.getSettingBoolean( "CompassHud" )
end

function LostItems.client_onDestroy( self )
	if self.cl.iconGui then
		if self.cl.iconGui.compassIconName and g_compassHud then
			g_compassHud:compassRemoveIcon( self.cl.iconGui.compassIconName )
		end
	end
	if self.cl.effectMarker then
		self.cl.effectMarker:destroy()
	end
	if self.cl.containerGui then
		if sm.exists( self.cl.containerGui ) then
			self.cl.containerGui:close()
			self.cl.containerGui:destroy()
		end
	end
end

function LostItems.client_onClientDataUpdate( self, clientData )
	if self.cl == nil then
		self.cl = {}
	end
	self.cl.owner = clientData.owner
	self.cl.creationTick = clientData.creationTick or sm.game.getServerTick()
	
	if sm.localPlayer.getPlayer() == self.cl.owner then
		if clientData.creationTick then
			if sm.game.getServerTick() - clientData.creationTick >= LOST_BAG_SHOW_TICKS then
				return
			end
		end
		self.cl.iconGui = { compassIconName = nil, world = nil }
		if g_compassHud then
			self.cl.iconGui.compassIconName = "LostItems"..self.shape.id
			g_compassHud:compassAddIcon( self.cl.iconGui.compassIconName, "icon_compass_lostitem.png" )
		end
		
		self.cl.effectMarker = sm.effect.createEffect( "LostItem", self.shape )
		if self.cl.iconGui.compassIconName and g_compassHud then
			g_compassHud:compassSetIconHost( self.cl.iconGui.compassIconName, self.shape )
			g_compassHud:setVisible( self.cl.iconGui.compassIconName, true )
		end
		self.cl.effectMarker:setHost( self.shape )
		self.cl.effectMarker:start()
		if self.cl.compassEnabled then
            self.cl.effectMarker:setParameter( "maxRenderDistance", 50 )
        else
            self.cl.effectMarker:setParameter( "maxRenderDistance", 1000000 )
        end
		self.cl.effectMarker:setParameter( "distanceFadeRange", 1 )
	end
end

function LostItems.server_onFixedUpdate( self )
	local container = self.shape.interactable:getContainer( 0 )
	if container == nil or container:isEmpty() then
		sm.shape.destroyShape( self.shape )
	end
end

function LostItems.client_onFixedUpdate( self , dt )
	if self.cl.iconGui then
		local compassSetting = sm.game.getSettingBoolean( "CompassHud" )
		if self.cl.compassEnabled ~= compassSetting then
			self.cl.compassEnabled = compassSetting
			if self.cl.compassEnabled then
				self.cl.iconGui.world:setMaxRenderDistance( 50 )
			else
				self.cl.iconGui.world:setMaxRenderDistance( 1000000 )
			end
		end
	end
	if self.cl.creationTick then
		if sm.game.getServerTick() - self.cl.creationTick >= LOST_BAG_SHOW_TICKS then
			if self.cl.iconGui and g_compassHud and self.cl.iconGui.compassIconName then
				g_compassHud:compassRemoveIcon( self.cl.iconGui.compassIconName )
				self.cl.iconGui = nil
			end
			if self.cl.effectMarker then
				self.cl.effectMarker:destroy()
				self.cl.effectMarker = nil
			end
			self.cl.creationTick = nil
		end
	end
end

function LostItems.client_onInteract( self, character, state )
	if state == true then
		local container = self.shape.interactable:getContainer( 0 )
		if container then
			self.cl.containerGui = sm.gui.createContainerGui( true )
			self.cl.containerGui:setText( "UpperName", "#{CHEST_TITLE_LOST_ITEMS}" )
			self.cl.containerGui:setVisible( "ChestIcon", false )
			self.cl.containerGui:setVisible( "LostItemsIcon", true )
			self.cl.containerGui:setVisible( "TakeAll", true )
			self.cl.containerGui:setContainer( "UpperGrid", container );
			self.cl.containerGui:setText( "LowerName", "#{INVENTORY_TITLE}" )
			self.cl.containerGui:setContainer( "LowerGrid", sm.localPlayer.getInventory() )
			self.cl.containerGui:open()
		end
	end
end
