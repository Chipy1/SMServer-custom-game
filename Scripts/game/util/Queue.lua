Queue = class( nil )

function Queue.push( self, value )
	if self.back == nil then
		self.back = 1
		self.front = 1
		self.array = {}
	end
	self.array[self.back] = value
	self.back = self.back + 1
end

function Queue.pop( self )
	if self.front == self.back then
		return nil
	end
	local value = self.array[self.front]
	self.array[self.front] = nil
	self.front = self.front + 1
	if self.front > 32 then
		table.move( self.array, self.front, self.back - 1, 1 )
		self.back = self.back - self.front + 1
		self.front = 1
	end
	return value
end

function Queue.peek( self )
	if self.front == self.back then
		return nil
	end
	local value = self.array[self.front]
	return value
end

function Queue.empty( self )
	return self.front == self.back
end

function Queue.size( self )
	return self.back and self.back - self.front or 0
end

function Queue.contains( self, predicate )
	if self.array == nil then
		return false
	end

	for index, value in pairs( self.array ) do
		if predicate( value ) then
			return true
		end
	end
	return false
end

function Queue.replace( self, predicate, value )
	if self.array == nil then
		return false
	end

	for index, queuedValue in pairs( self.array ) do
		if predicate( queuedValue ) then
			self.array[index] = value
			return true
		end
	end
	return false
end
