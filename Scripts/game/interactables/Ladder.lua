dofile("$SURVIVAL_DATA/Scripts/game/survival_constants.lua")

Ladder = class( nil )

function Ladder.client_onCreate( self )
	self:createTrigger()
end

function Ladder.createTrigger( self )
	local climbableBounds = self.shape:getBoundingBox() * 0.5
	if self.data and self.data.climbableOffset then
		climbableBounds.x = climbableBounds.x + self.data.climbableOffset.x
		climbableBounds.y = climbableBounds.y + self.data.climbableOffset.y
		climbableBounds.z = climbableBounds.z + self.data.climbableOffset.z
	end

	if self.areaTrigger == nil then
		self.areaTrigger = sm.areaTrigger.createAttachedBox( self.shape, climbableBounds, nil, nil, sm.areaTrigger.filter.character, nil, sm.areaTrigger.areaTriggerProxyType.ladder )
	end
end