dofile( "$SURVIVAL_DATA/Scripts/game/survival_items.lua" )

VoxelMaterialChunk = class()

function VoxelMaterialChunk.sv_plasmaDrill( self, progress )
	self.drillProgress = self.drillProgress or 0
	self.drillProgress = self.drillProgress + progress
	if self.drillProgress >= self.data.drillTime and not self.harvested then
		self.harvested = true
		if self.data.breakEffect then
			sm.effect.playEffect( self.data.breakEffect, self.shape:getWorldPosition(), nil, self.shape:getWorldRotation(), nil, { size = 1 } )
		end
		self.shape:destroyShape()
		return { uuid = self.saved.uuid, quantity = self.saved.quantity }
	end
	return nil
end

function VoxelMaterialChunk.server_onCreate( self )
	if self.params then
		self.saved = { uuid = self.params.uuid, quantity = self.params.quantity }
		self.storage:save( self.saved )
	else
		self.saved = self.storage:load()
	end
	self.interactable.publicData = { plasmaDrill = function( progress ) return self:sv_plasmaDrill( progress ) end }
	if not self.saved then
		print( "Created test VoxelMaterialChunk" )
		self.saved = { uuid = ITEMS.obj_voxelmaterial_t1, quantity = 1 }
	end



end








