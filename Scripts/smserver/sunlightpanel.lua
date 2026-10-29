sunlightpanel = class()
sunlightpanel.uuid = sm.uuid.new( "910a7f2c-52b0-46eb-8873-ad13255539af" )
sunlightpanel.outputEvery = 40 * 60 * 5

sunlightpanel.colorHighlight = sm.color.new( "#ff3030" )
sunlightpanel.colorNormal = sm.color.new( "#890202" )
sunlightpanel.maxParentCount = -1
sunlightpanel.connectionInput = sm.interactable.connectionType.electricity

local function pushBattery( self )
	local parents = self.interactable:getParents()
	if #parents == 0 then
		return false
	end

	local parent = parents[math.random( 1, #parents )]
	local container = parent:getContainer()
	if container then
		sm.container.beginTransaction()
		sm.container.collect( container, sunlightpanel.uuid, 1 )
		if sm.container.endTransaction() then
			return true
		end
	end

	for _, parent in ipairs( parents ) do
		local container = parent:getContainer()
		if container then
			sm.container.beginTransaction()
			sm.container.collect( container, sunlightpanel.uuid, 1 )
			if sm.container.endTransaction() then
				return true
			end
		end
	end

	return false
end

function sunlightpanel:server_onCreate()
	self.timer = 0
end

function sunlightpanel:server_onFixedUpdate()
	local value = math.max( 1 - math.abs( ( sm.game.getTimeOfDay() - 0.5 ) * 2 ), 0 )
	if value >= 0.6 then
		self.timer = self.timer + 1
		if self.timer >= sunlightpanel.outputEvery then
			self.timer = 0
			if pushBattery( self ) then
				self.network:sendToClients( "cl_pushEffect" )
			end
		end
	end
end

function sunlightpanel:client_onCreate()
	self.effects = {}
end

function sunlightpanel:client_onFixedUpdate()
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

function sunlightpanel:cl_pushEffect()
	local effect = sm.effect.createEffect( "Shipwreck - sparks01", self.interactable )
	effect:start()
	self.effects[effect] = sm.game.getCurrentTick() + 20

	effect = sm.effect.createEffect( "Part - Electricity", self.interactable )
	effect:start()
	self.effects[effect] = true
end
