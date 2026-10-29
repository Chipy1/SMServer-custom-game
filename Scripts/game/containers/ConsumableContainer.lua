dofile( "$SURVIVAL_DATA/Scripts/game/survival_items.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/survival_projectiles.lua" )

ConsumableContainer = class( nil )
ConsumableContainer.maxChildCount = 255

local ContainerSize = 5

function ConsumableContainer.server_onCreate( self )
	local container = self.shape.interactable:getContainer( 0 )
	local expected = self.data.filterUid and sm.uuid.new( self.data.filterUid )

	if container and expected then
		-- Validate that loaded container only holds the expected item
		local hasMismatchedItem = false
		for slot = 0, container:getSize() - 1 do
			local item = container:getItem( slot )
			if not item.uuid:isNil() and item.uuid ~= expected then
				hasMismatchedItem = true
				break
			end
		end
		if hasMismatchedItem then
			self.shape.interactable:removeContainer( 0 )
			container = nil
		end
	end
	if not container then
		container = self.shape:getInteractable():addContainer( 0, ContainerSize, self.data.stackSize )
	end
	if expected then
		container:setFilters( { expected } )
	end

	-- Remove any excess containers, keeping the container at index 0
	for i = 1, 15 do
		if self.shape.interactable:getContainer( i ) then
			self.shape.interactable:removeContainer( i )
		end
	end

end

function ConsumableContainer.client_canCarry( self )
	local container = self.shape.interactable:getContainer( 0 )
	if container and sm.exists( container ) then
		return not container:isEmpty()
	end
	return false
end

function ConsumableContainer.client_onInteract( self, character, state )
	if state == true then
		local container = self.shape.interactable:getContainer( 0 )
		if container then
			self.gui = nil

			local shapeUuid = self.shape:getShapeUuid()

			if shapeUuid == obj_container_ammo then
				self.gui = sm.gui.createAmmunitionContainerGui( true )

			elseif shapeUuid == obj_container_battery then
				self.gui = sm.gui.createBatteryContainerGui( true )

			elseif shapeUuid == obj_container_chemical then
				self.gui = sm.gui.createChemicalContainerGui( true )

			elseif shapeUuid == obj_container_fertilizer then
				self.gui = sm.gui.createFertilizerContainerGui( true )

			elseif shapeUuid == obj_container_gas then
				self.gui = sm.gui.createGasContainerGui( true )

			elseif shapeUuid == obj_container_seed then
				self.gui = sm.gui.createSeedContainerGui( true )

			elseif shapeUuid == obj_container_water then
				self.gui = sm.gui.createWaterContainerGui( true )
			end

			if self.gui == nil then
				self.gui = sm.gui.createContainerGui( true )
				self.gui:setText( "UpperName", "#{CONTAINER_TITLE_GENERIC}" )
			end

			self.gui:setContainer( "UpperGrid", container )
			self.gui:setText( "LowerName", "#{INVENTORY_TITLE}" )
			self.gui:setContainer( "LowerGrid", sm.localPlayer.getInventory() )
			self.gui:setOnCloseCallback( "cl_e_onClose" )
			self.gui:open()
		end
	end
end

function ConsumableContainer.client_onDestroy( self )
	if self.gui and self.gui:isActive() then
		self.gui:close()
		self.gui:destroy()
	end
end

function ConsumableContainer.cl_e_onClose( self )
	self.gui = nil
end

function ConsumableContainer.client_onUpdate( self, dt )
	local container = self.shape.interactable:getContainer( 0 )
	if container and self.data.stackSize then
		local quantities = sm.container.quantity( container )

		local quantity = 0
		for _,q in ipairs( quantities ) do
			quantity = quantity + q
		end

		local frame = ContainerSize - math.ceil( quantity / self.data.stackSize )
		self.interactable:setUvFrameIndex( frame )
	end
end

SeedContainer = class( ConsumableContainer )

function SeedContainer.server_onCreate( self )
	local container = self.shape.interactable:getContainer( 0 )
	if not container then
		container =	self.shape:getInteractable():addContainer( 0, ContainerSize, self.data.stackSize )
	end
	container:setFilters( sm.item.getPlantableUuids() )
end

WaterContainer = class( ConsumableContainer )
WaterContainer.connectionOutput = sm.interactable.connectionType.water
WaterContainer.colorNormal = sm.color.new( 0x00acfcff )
WaterContainer.colorHighlight = sm.color.new( 0x00acfcff )
WaterContainer.connectIcon = "water"
WaterContainer.connectIconScale = 0.75


-- function WaterContainer.server_onProjectile( self, hitPos, hitTime, hitVelocity, _, attacker, damage, userData, hitNormal, projectileUuid )
-- 	if projectileUuid == projectile_water and ( self.hitTick == nil or self.hitTick <= sm.game.getCurrentTick() - 4 ) then
-- 		local container = self.shape.interactable:getContainer( 0 )
-- 		if sm.container.beginTransaction() then
-- 			sm.container.collect( container, obj_consumable_water, 1, false )
-- 			sm.container.endTransaction()
-- 		end
-- 		self.hitTick = sm.game.getCurrentTick()
-- 	end
-- end

ChemicalContainer = class( ConsumableContainer )
ChemicalContainer.connectionOutput = sm.interactable.connectionType.chemical
ChemicalContainer.colorNormal = sm.color.new( 0xd962d8ff )
ChemicalContainer.colorHighlight = sm.color.new( 0xd962d8ff )
ChemicalContainer.connectIcon = "chemical"
ChemicalContainer.connectIconScale = 0.75

BatteryContainer = class( ConsumableContainer )
BatteryContainer.connectionOutput = sm.interactable.connectionType.electricity
BatteryContainer.colorNormal = sm.color.new( 0xffca1aff )
BatteryContainer.colorHighlight = sm.color.new( 0xffca1aff )
BatteryContainer.connectIcon = "electrical"
BatteryContainer.connectIconScale = 0.75

GasolineContainer = class( ConsumableContainer )
GasolineContainer.connectionOutput = sm.interactable.connectionType.gasoline
GasolineContainer.colorNormal = sm.color.new( 0xff8000ff )
GasolineContainer.colorHighlight = sm.color.new( 0xff8000ff )
GasolineContainer.connectIcon = "gas"
GasolineContainer.connectIconScale = 0.75

AmmoContainer = class( ConsumableContainer )
AmmoContainer.connectionOutput = sm.interactable.connectionType.ammo
AmmoContainer.colorNormal = sm.color.new( 0xcb0a00ff )
AmmoContainer.colorHighlight = sm.color.new( 0xcb0a00ff )
AmmoContainer.connectIcon = "ammo"
AmmoContainer.connectIconScale = 0.75


FoodContainer = class( ConsumableContainer )

local FoodUuids = {
	obj_plantables_banana,
	obj_plantables_blueberry,
	obj_plantables_orange,
	obj_plantables_pineapple,
	obj_plantables_carrot,
	obj_plantables_redbeet,
	obj_plantables_tomato,
	obj_plantables_broccoli,
	obj_plantables_potato,
	obj_consumable_sunshake,
	obj_consumable_carrotburger,
	obj_consumable_pizzaburger,
	obj_consumable_longsandwich,
	obj_consumable_milk,
	obj_resource_steak,
	obj_resource_corn,
}

function FoodContainer.server_onCreate( self )
	local container = self.shape.interactable:getContainer( 0 )
	if not container then
		container =	self.shape:getInteractable():addContainer( 0, 20 )
	end
	container:setFilters( FoodUuids )
end

FoodContainer.client_onUpdate = nil
