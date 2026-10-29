SyncOverTime = class( nil )

function SyncOverTime.set( self, myValue )
    self.myValue = myValue
    self.targetValue = nil
end

function SyncOverTime.sync( self, targetValua, duration )
	self.targetValue = targetValua
    self.interp = 0
    self.duration = duration or 1
end

function SyncOverTime.update( self, progress, dt )
    self.myValue = self.myValue + progress
    
    if self.targetValue then
        self.interp = min( self.interp + dt / self.duration, 1 )
        self.targetValue = self.targetValue + progress

        if self.interp >= 1 then
            self.myValue = self.targetValue
            self.interp = nil
            self.targetValue = nil

            return self.myValue
        end
        return lerp( self.myValue, self.targetValue, self.interp )
    end

    return self.myValue
end

function SyncOverTime.get( self )
    return self.myValue
end

