-- PowerCoreSocket.lua --
dofile("$SURVIVAL_DATA/Scripts/game/survival_shapes.lua")

PowerCoreSocket = class( nil )
PowerCoreSocket.maxParentCount = 0
PowerCoreSocket.maxChildCount = 255
PowerCoreSocket.colorNormal = sm.color.new( 0xdeadbeef )
PowerCoreSocket.colorHighlight = sm.color.new( 0xdeadbeef )
PowerCoreSocket.connectionInput = sm.interactable.connectionType.none
PowerCoreSocket.connectionOutput = sm.interactable.connectionType.logic
PowerCoreSocket.poseWeightCount = 1

-- Server

function PowerCoreSocket.server_onCreate( self )
	self.sv = {}
	self.sv.saved = self.storage:load()
	
	if self.sv.saved == nil then
		self.sv.saved = {}
		self.interactable.active = false
		self.sv.saved.active = false
	else
		self.interactable.active = self.sv.saved.active
	end
	
	if self.params then
		if self.params.lightInteractables then
			self.sv.saved.lightInteractables = self.params.lightInteractables
		end
		if self.params.shipworkbenchInteractables then
			self.sv.saved.shipworkbenchInteractables = self.params.shipworkbenchInteractables
		end
		if self.params.noteterminalInteractables then
			self.sv.saved.noteterminalInteractables = self.params.noteterminalInteractables
		end
		if self.params.dispenserbotInteractables then
			self.sv.saved.dispenserbotInteractables = self.params.dispenserbotInteractables
		end
	end
	self.storage:save( self.sv.saved )

	self.sv.area = "generic"
	if self.sv.saved.lightInteractables then
		for _, interactable in ipairs( self.sv.saved.lightInteractables ) do
			self.interactable:connect( interactable )
		end
	end
	if self.sv.saved.shipworkbenchInteractables then
		for _, interactable in ipairs( self.sv.saved.shipworkbenchInteractables ) do
			self.interactable:connect( interactable )
		end
	end
	if self.sv.saved.noteterminalInteractables then
		for _, interactable in ipairs( self.sv.saved.noteterminalInteractables ) do
			self.interactable:connect( interactable )
		end
		if #self.sv.saved.noteterminalInteractables > 0 then
			self.sv.area = "ship"
		end
	end
	if self.sv.saved.dispenserbotInteractables then
		for _, interactable in ipairs( self.sv.saved.dispenserbotInteractables ) do
			self.interactable:connect( interactable )
		end
		if #self.sv.saved.dispenserbotInteractables > 0 then
			self.sv.area = "mechanicstation"
		end
	end
	self.interactable.publicData = { area = self.sv.area }

	self.sv.playShipEffect = self.sv.saved.noteterminalInteractables and #self.sv.saved.noteterminalInteractables > 0
	self.network:setClientData( { playShipEffect = self.sv.playShipEffect, area = self.sv.area } )
end

function PowerCoreSocket.sv_e_unlock( self, params )
	if self.sv.area == "ship" then
		local quest = QuestManager.Sv_GetQuest( "quest_tutorial" )
		if quest and quest.publicData and not quest.publicData.canActivate then
			return
		end
	end
	if self.interactable.active == false and params.player and sm.exists( params.player ) then
		if params.keyId == obj_survivalobject_powercore then
			local inventory = params.player:getInventory()
			sm.container.beginTransaction()
			sm.container.spend( inventory, obj_survivalobject_powercore, 1, true )
			if sm.container.endTransaction() then
				self.sv.saved.active = true
				self.interactable.active = true
				self.storage:save( self.sv.saved )

				if not self.sv.playShipEffect and self.sv.saved.noteterminalInteractables and #self.sv.saved.noteterminalInteractables > 0  then
					self.sv.playShipEffect = true
					self.network:setClientData( self.sv.playShipEffect )
				end

				sm.effect.playEffect( "PowerSocket - Activate", self.shape.worldPosition, nil, self.shape.worldRotation )
				if self.shape.body:isStatic() then
					if g_tileStorageManager then
						local tileStorageKey = TileStorageManager.Sv_GetTileStorageKeyFromObject( self.interactable )
						TileStorageManager.Sv_SetValueInSubTable( tileStorageKey, POWER_CORE_SOCKET_TABLE, "power_restored", true )
						SetTileStorageFlag(tileStorageKey, "mechanicstation.activation" )
						EffectManager.Sv_UpdateTagFilteredEffectsForTile( self.shape.body:getWorld(), self.shape.worldPosition, { "mechanicstation.activation" }  )
					end
					if self.sv.saved.noteterminalInteractables and #self.sv.saved.noteterminalInteractables > 0 then
						QuestManager.Sv_SendEvent( "event.quest_tutorial.power_restored" )
					end
					if self.sv.saved.dispenserbotInteractables and #self.sv.saved.dispenserbotInteractables > 0 then
						local terrainData = GetTerrainData( self.shape.body:getWorld().id )
						local x = math.floor( self.shape.worldPosition.x / 64 )
						local y = math.floor( self.shape.worldPosition.y / 64 )
						local tileUuid = terrainData.uid[y][x]
						local tileData = GetTileData( self.shape.body:getWorld().id )
						local poiType = tileData[tostring( tileUuid )].poiType
						if poiType == 124 then
							QuestManager.Sv_SendEvent( "event.quest_mechanicstation.power_restored" )
						end
					end
				end
			end
		end
	end
end

-- Client

function PowerCoreSocket.client_onCreate( self )
	self.interactable:setPoseWeight( 0, self.interactable.active and 1 or 0 )
	self.shipEffect = sm.effect.createEffect( "Shipwreck - AmbianceSound", self.shape )

	if self.cl == nil then
		self.cl = {}
	end
	self.cl.playShipEffect = false
	self.cl.area = "generic"
end

function PowerCoreSocket.client_canInteract( self )
	if not self.interactable.active then
		if self.cl.area == "ship" then
			local quest = QuestManager.Cl_GetActiveQuest( "quest_tutorial" )
			if quest and quest.clientPublicData and not quest.clientPublicData.canActivate then
				return false
			end
		end

		if sm.localPlayer.getActiveItem() == ITEMS.obj_survivalobject_powercore then
			self.cl.canUnlock = sm.container.canSpend( sm.localPlayer.getInventory(), ITEMS.obj_survivalobject_powercore, 1 )
		end

		local itemName = sm.shape.getShapeTitle( ITEMS.obj_survivalobject_powercore )

		if self.cl.canUnlock then
			local keyBindingText =  sm.gui.getKeyBinding( "Create", true )
			SetNeedResourceInteractionText( "", keyBindingText, "#{INTERACTION_PLACE}", itemName )
		else
			SetNeedResourceInteractionText( "", "", "#{INTERACTION_PLACE}", itemName )
		end
	end
	return false
end

function PowerCoreSocket.client_onUpdate( self, deltaTime )
	if self.cl.canUnlock then
		if not self.cl.visualization then
			local blueprint = {
				bodies = {
					{
						childs = {
							{
								shapeId = "c654a023-ca53-4109-9f18-d297c18e9a02",
								pos = { x = 0.0, y = 0.0, z = 0.0 },
								xaxis = 1.0,
								zaxis = 3.0,
								color = "4A4A4A"
							}
						},
						type = 1.0
					}
				}
			}
			self.cl.visualization = sm.visualization.createBlueprint( blueprint )
			self.cl.visualization:setPosition( self.shape.worldPosition + self.shape.worldRotation * sm.vec3.new( -0.25, -0.599, -0.087 ) )
			self.cl.visualization:setRotation( self.shape.worldRotation )
			self.cl.visualization:setVisualizationColor( "Hand Place Valid" )
		end
	else
		if self.cl.visualization then
			self.cl.visualization:destroy()
			self.cl.visualization = nil
		end
	end
	self.interactable:setPoseWeight( 0, self.interactable.active and 1 or 0 )
	if self.interactable.active then
		self.interactable:setGlowMultiplier( 1.0 )

		if self.cl.playShipEffect then
			if not self.shipEffect:isPlaying() then
				self.shipEffect:start();
			end
		end
	else
		self.time = self.time and self.time + deltaTime or 0
		self.interactable:setGlowMultiplier( math.sin( self.time * math.pi ) * 0.25 + 0.5 )
	end
	self.cl.canUnlock = false
end

function PowerCoreSocket.client_onDestroy( self )
	self.shipEffect:stop()
end









function PowerCoreSocket.client_onClientDataUpdate( self, clientData )
	self.cl.playShipEffect = clientData.playShipEffect
	self.cl.area = clientData.area
end