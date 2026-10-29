dofile( "$SURVIVAL_DATA/Scripts/game/survival_items.lua" )

BlowupHarvestablePart = class( nil )

function BlowupHarvestablePart.server_onExplosion( self, center, destructionLevel )
	if not self.destroyed then
		if self.data.blowupHarvestablePart.onExplosionBlueprint then
			local bodies = sm.creation.importFromFile( nil, self.data.blowupHarvestablePart.onExplosionBlueprint, self.shape.worldPosition, self.shape.worldRotation )
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
		if self.data.blowupHarvestablePart.destroyEffect then
			sm.effect.playEffect( self.data.blowupHarvestablePart.destroyEffect, self.shape.worldPosition )
		end
		self.shape:destroyShape()
		self.destroyed = true
	end
end
