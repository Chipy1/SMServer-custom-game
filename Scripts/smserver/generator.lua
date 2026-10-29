generator = class()
generator.colorHighlight = sm.color.new( "#ff3030" )
generator.colorNormal = sm.color.new( "#890202" )
generator.maxParentCount = -1
generator.connectionInput = sm.interactable.connectionType.electricity

generator.uuid = sm.uuid.new( "910a7f2c-52b0-46eb-8873-ad13255539af" )
generator.minSpeed = 10
generator.maxSpeed = 100
generator.batteriesPerTick = 1 / 40 / 60

local function pushBattery( self )
	local parents = self.interactable:getParents()
	if #parents == 0 then
		return false
	end

	local parent = parents[math.random( 1, #parents )]
	local container = parent:getContainer()
	if container then
		sm.container.beginTransaction()
		sm.container.collect( container, generator.uuid, 1 )
		if sm.container.endTransaction() then
			return true
		end
	end

	for _, parent in ipairs( parents ) do
		local container = parent:getContainer()
		if container then
			sm.container.beginTransaction()
			sm.container.collect( container, generator.uuid, 1 )
			if sm.container.endTransaction() then
				return true
			end
		end
	end

	return false
end

function generator:server_onCreate()
	self.power = 0
end

function generator:server_onFixedUpdate()
	local velocity = math.abs( self.shape:getBody():getAngularVelocity():dot( self.shape:getAt() ) )
	if velocity > generator.maxSpeed then
		velocity = generator.maxSpeed
	end
	if velocity > generator.minSpeed then
		self.power = self.power + ( velocity / generator.maxSpeed ) * generator.batteriesPerTick
	end

	for _ = 1, 10 do
		if self.power < 1 then
			break
		end

		if not pushBattery( self ) then
			break
		end

		self.network:sendToClients( "cl_pushEffect" )
		self.power = self.power - 1
	end

	if self.power < 0 then
		self.power = 0
	end
end

function generator:client_onCreate()
	self.effects = {}
end

function generator:client_onFixedUpdate()
	local ctick = sm.game.getCurrentTick()
	for effect, deadline in pairs( self.effects ) do
		if sm.exists( effect ) then
			if type( deadline ) == "number" and ctick >= deadline then
				effect:stop()
			end

			if not effect:isPlaying() then
				effect:destroy()
				self.effects[effect] = nil
			end
		else
			self.effects[effect] = nil
		end
	end
end

function generator:cl_pushEffect()
	local effect = sm.effect.createEffect( "Shipwreck - sparks01", self.interactable )
	effect:start()
	self.effects[effect] = sm.game.getCurrentTick() + 20

	effect = sm.effect.createEffect( "Part - Electricity", self.interactable )
	effect:start()
	self.effects[effect] = true
end
