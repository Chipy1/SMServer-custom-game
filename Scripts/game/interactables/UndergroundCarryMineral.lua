
UndergroundCarryMineral = class()

function UndergroundCarryMineral.server_onCreate( self )
	local canCollectStatic = self.interactable:getCarryData()
	if canCollectStatic then
		self.storage:save( true )
	else
		canCollectStatic = self.storage:load() or false
	end
	self.interactable.publicData = { canCollectStatic = canCollectStatic }
	self.interactable:setCarryData( true )
end

function UndergroundCarryMineral.client_onCreate( self )
	if self.data and self.data.hostedEffect then
		sm.effect.playHostedEffect( self.data.hostedEffect, self.interactable )
	end
end
