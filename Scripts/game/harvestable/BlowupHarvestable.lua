dofile( "$SURVIVAL_DATA/Scripts/game/survival_items.lua" )

BlowupHarvestable = class( nil )

function BlowupHarvestable.server_onExplosion( self, center, destructionLevel )
	if not self.destroyed then
		if self.data.blowupHarvestable.onExplosionBlueprint then
			local bodies = sm.creation.importFromFile( nil, self.data.blowupHarvestable.onExplosionBlueprint, self.harvestable.worldPosition, self.harvestable.worldRotation )
			local closestShape = nil
			local closestDistance2 = math.huge
			for _, body in ipairs( bodies ) do
				local shapes = body:getShapes()
				for _, shape in ipairs( shapes ) do
					local distance = ( shape:getWorldPosition() - center ):length2()
					if distance < closestDistance2 then
						closestShape = shape
						closestDistance2 = distance
					end
				end
			end
			if closestShape then
				closestShape.interactable:setParams( { inheritedDamage = 100 } )
			end
		end
		if self.data.blowupHarvestable.destroyEffect then
			sm.effect.playEffect( self.data.blowupHarvestable.destroyEffect, self.harvestable.worldPosition )
		end
		self.harvestable:destroy()
		self.destroyed = true
	end
end

function BlowupHarvestable.server_onFloating( self )
	if not self.destroyed then
		if self.data.blowupHarvestable.onFloatingPart then
			local partOnFloating = ITEMS[self.data.blowupHarvestable.onFloatingPart]
			local size = sm.item.getShapeSize( partOnFloating ) * 0.25
			sm.shape.createPart( partOnFloating, self.harvestable.worldPosition - self.harvestable.worldRotation * size * 0.5, self.harvestable.worldRotation )
		end
		self.harvestable:destroy()
		self.destroyed = true
	end
end
