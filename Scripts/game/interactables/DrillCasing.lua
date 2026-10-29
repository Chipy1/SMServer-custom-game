
GRAVEL_CASING_CAPACITY = 10000 -- Max 65535. This is the max amount of items in a container slot, if we need more we can use multiple slots.

DrillCasing = class( nil )

function DrillCasing.server_onCreate( self )
	self.sv = {}
	self.sv.saved = self.storage:load()
	if self.sv.saved == nil then
		if self.params then
			self.sv.saved = self.params
		else
			self.sv.saved = self.interactable:getCarryData()
		end
		self.storage:save( self.sv.saved )
	end
	self.sv.saved = self.sv.saved or {}
	self.interactable:setCarryData( self.sv.saved )
	self.interactable.publicData = self.sv.saved



end




















