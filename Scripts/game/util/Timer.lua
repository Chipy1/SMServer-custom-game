Timer = class( nil )

function Timer.start( self, ticks )
	self.ticks = ticks or 0
	self.count = 0
	self.active = true
end

function Timer.reset( self )
	self.ticks = self.ticks or -1
	self.count = 0
	self.active = true
end

function Timer.stop( self )
	self.ticks = -1
	self.count = 0
	self.active = false
end

function Timer.tick( self )
	self.count = math.min( self.count + 1, self.ticks )
end

function Timer.done( self )
	return self.ticks >= 0 and self.count >= self.ticks
end

function Timer.isActive( self )
	return self.active
end

function Timer.getTick( self )
	return self.count
end

function Timer.getFraction( self )
	return self.count / self.ticks
end