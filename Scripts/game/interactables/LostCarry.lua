dofile "$SURVIVAL_DATA/Scripts/game/survival_constants.lua"
dofile "$SURVIVAL_DATA/Scripts/game/survival_shapes.lua"
dofile "$SURVIVAL_DATA/Scripts/util.lua"

LostCarry = class( nil )

function LostCarry.server_onCreate( self )
	local container = self.shape.interactable:getContainer( 0 )
	if container then
		container.allowSpend = true
		container.allowCollect = false
	end
	self.sv = {}
	self.sv.collected = false

	for i = 0, container:getSize() do
		local item = container:getItem( i )
		if RADIOACTIVE_CARRY_ITEMS[tostring( item.uuid )] then
			local radius = RADIOACTIVE_CARRY_ITEMS[tostring( item.uuid )].radius or 4.0
			local filter = sm.areaTrigger.filter.character
			self.sv.areaTrigger = sm.areaTrigger.createAttachedSphere( self.shape, radius, nil, nil, filter )
			self.sv.areaTrigger:bindOnEnter( "sv_onTriggerEnter" )
			self.sv.areaTrigger:bindOnStay( "sv_onTriggerStay" )
		end
	end
end

function LostCarry.sv_onTriggerEnter( self, _, results )
    FireTriggerEventForPlayers( results, "sv_e_onEnterRadiation" )
end

function LostCarry.sv_onTriggerStay( self, _, results )
    FireTriggerEventForPlayers( results, "sv_e_onStayRadiation" )
end

function LostCarry.server_onDestroy( self )
	if self.sv.areaTrigger and sm.exists( self.sv.areaTrigger ) then
		self.sv.areaTrigger:destroy()
		self.sv.areaTrigger = nil
	end
end

function LostCarry.sv_n_tryPickUp( self, player )
	if not self.sv.collected then
		local carryInventory = player:getCarry()
		if carryInventory then
			sm.container.beginTransaction()
			local container = self.shape.interactable:getContainer( 0 )
			for i = 0, container:getSize() do
				local item = container:getItem( i )
				if item.uuid ~= sm.uuid.getNil() then
					sm.container.setItem( carryInventory, i, item.uuid, item.quantity, item.instance )
				end
			end
			if sm.container.endTransaction() then
				self.sv.collected = true
				sm.shape.destroyShape( self.shape )
			end
		end
	end
end

function LostCarry.client_canInteract( self )
	return true
end

function LostCarry.client_onInteract( self, character, state )
	if state == true then
		local container = self.shape.interactable:getContainer( 0 )
		if container then
			local player = character:getPlayer()
			if player then
				self.network:sendToServer( "sv_n_tryPickUp", player )
			end
		end
	end
end
