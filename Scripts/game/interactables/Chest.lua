---@class Chest : ShapeClass
---@field sv table
---@field cl table
Chest = class( nil )
Chest.maxParentCount = 1
Chest.poseWeightCount = 1
Chest.connectionInput = sm.interactable.connectionType.logic

local AreaTriggerSize = 6

function Chest.server_onCreate( self )
	self.sv = {}
	local container = self.shape.interactable:getContainer( 0 )
	if not container then
		container = self.shape:getInteractable():addContainer( 0, self.data.slots or 30 )
	end
end

function Chest.server_onFixedUpdate( self )
	local parent = self.interactable:getSingleParent()
	if parent and parent:isActive() then
		if self.sv.areaTrigger == nil then
			local size = sm.vec3.new( AreaTriggerSize, AreaTriggerSize, AreaTriggerSize )
			local filter = sm.areaTrigger.filter.harvestable + sm.areaTrigger.filter.areaTrigger
			self.sv.areaTrigger = sm.areaTrigger.createAttachedBox( self.interactable, size, sm.vec3.zero(), sm.quat.identity(), filter )
		end
		local container = self.shape.interactable:getContainer( 0 )
		local areaContent = self.sv.areaTrigger:getContents()
		local looted = {}
        for _, result in ipairs( areaContent ) do
            if sm.exists( result ) then
                local resultType = type( result )
                if resultType == "Harvestable" then
                    if result:getUuid() == hvs_loot then
                        local pubData = result.publicData
                        if pubData and not pubData.harvested then
                            sm.container.beginTransaction()
                            sm.container.collect( container, pubData.uuid, pubData.quantity, true )
                            if sm.container.endTransaction() then
                                looted[#looted + 1] = { uuid = pubData.uuid, pos = result:getPosition() }
                                pubData.harvested = true
                                result:destroy()
                            end
                        end
                    end
                elseif resultType == "AreaTrigger" then
                    local userData = result:getUserData()
                    if userData and ( userData.ice == true or userData.beewax == true ) then
                        local hostInteractable = result:getHostInteractable()
                        local pubData = hostInteractable and sm.exists( hostInteractable ) and hostInteractable:getPublicData()
                        if pubData and pubData.uuid and pubData.amount and pubData.amount > 0 then
                            sm.container.beginTransaction()
                            sm.container.collect( container, pubData.uuid, pubData.amount, true )
                            if sm.container.endTransaction() then
                                looted[#looted + 1] = { uuid = pubData.uuid, pos = result:getWorldPosition() }
                                sm.event.sendToInteractable( hostInteractable, "sv_e_onSpend", { uuid = pubData.uuid, amount = pubData.amount }, sm.event.types.instant )
                            end
                        end
                    end
                end
            end
        end
		if #looted > 0 then
			self.network:sendToClients( "cl_n_looted", looted )
		end
	end
end

function Chest.sv_n_open( self, _, player )
	self.sv.playersLookingInChest = self.sv.playersLookingInChest or {}
	self.sv.playersLookingInChest[#self.sv.playersLookingInChest + 1] = player
	self.network:setClientData( #self.sv.playersLookingInChest > 0 )
end

function Chest.sv_n_close( self, _, player )
	for i = #self.sv.playersLookingInChest, 1, -1 do
		local p = self.sv.playersLookingInChest[i]
		if p == player or not p:isActive() then
			table.remove( self.sv.playersLookingInChest, i )
		end
	end
	self.network:setClientData( #self.sv.playersLookingInChest > 0 )
end

function Chest.client_onCreate( self )
	self.cl = {}
	self.cl.weight = 0
end

function Chest.client_onClientDataUpdate( self, isOpen )
	self.cl.isOpen = isOpen
end

function Chest.client_onDestroy( self )
	local gui = self.cl.gui
	if gui and gui:isActive() then
		gui:close()
		self.cl.gui = nil
	end
end

function Chest.client_onInteract( self, _, state )
	if state == true then
		local container = self.shape.interactable:getContainer( 0 )
		local gui = sm.gui.createContainerGui( true )
		
		gui:setContainer( "UpperGrid", container )
		gui:setText( "LowerName", "#{INVENTORY_TITLE}" )
		gui:setContainer( "LowerGrid", sm.localPlayer.getInventory() )
		gui:setOnCloseCallback( "cl_e_onClose" )
		gui:open()
		self.cl.gui = gui
		self.network:sendToServer( "sv_n_open", true )
	end
end

function Chest.cl_e_onClose( self )
	self.cl.gui = nil
	self.network:sendToServer( "sv_n_close" )
end

function Chest.client_canCarry( self )
	local container = self.shape.interactable:getContainer( 0 )
	if container and sm.exists( container ) then
		return not container:isEmpty()
	end
	return false
end

function Chest.client_onRefresh(self)
	self.cl.effect = nil
end

function Chest.client_onUpdate( self, dt )
	local isOpen = self.cl.isOpen
	if self.cl.lootTrails then
		for i = #self.cl.lootTrails, 1, -1 do
			local trail = self.cl.lootTrails[i]
			trail.time = trail.time - dt
			if trail.time <= 0 then
				if trail.effect then
					trail.effect:stopImmediate()
				end
				table.remove( self.cl.lootTrails, i )
			else
				trail.pos = magicPositionInterpolation( trail.pos, self.shape:getWorldPosition(), dt )
				if trail.effect == nil then
					trail.effect = trail.effect or sm.effect.createEffect( "LootProjectile - Attached" )
					trail.effect:start()
				end
				trail.effect:setPosition( trail.pos )
				isOpen = true
			end
		end
	end

	local weight = self.cl.weight
	if isOpen then
		weight = math.min( weight + dt * 10.0, 1.0 )
	else
		weight = math.max( weight - dt * 10.0, 0.0 )
	end
	self.cl.weight = weight

	local parent = self.interactable:getSingleParent()
	if parent and parent:isActive() then
		if self.cl.effect == nil then
			self.cl.effect = self.cl.effect or sm.effect.createEffect( "Interactive - ChestLootsuction_active", self.shape )
			self.cl.effect:setOffsetPosition( sm.vec3.new( 0, -0.75, 0 ) )
			self.cl.effect:setOffsetRotation( sm.quat.rotNegX90() )
			self.cl.effect:start()
		end
		self.cl.time = ( self.cl.time or 0 ) + dt -- Restarts non looping effect
		if self.cl.time > 1 then
			self.cl.time = self.cl.time % 1
			self.cl.effect:start()
		end
		weight = math.max( weight, 0.4 )
	else
		if self.cl.effect then
			self.cl.effect:stopImmediate()
			self.cl.effect = nil
		end
		self.cl.time = nil
	end

    self.shape.interactable:setPoseWeight( 0, weight )
end

function Chest.cl_n_looted( self, looted )
	self.cl.lootTrails = self.cl.lootTrails or {}
	for _, item in ipairs( looted ) do
		local color = sm.shape.getShapeTypeColor( item.uuid )
		sm.effect.playEffect( "LootProjectile - Hit", item.pos, sm.vec3.zero(), sm.quat.identity(), sm.vec3.one(), { ["Color"] = color } )
		self.cl.lootTrails[#self.cl.lootTrails + 1] = { pos = item.pos + sm.vec3.new( 0, 0, 0.375 ), time = 0.25, color = color}
	end
end