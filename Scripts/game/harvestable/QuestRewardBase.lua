dofile "$SURVIVAL_DATA/Scripts/util.lua"
dofile "$SURVIVAL_DATA/Scripts/game/survival_constants.lua"

QuestRewardBase = class( nil )

-- Server

function QuestRewardBase.server_onCreate( self )
    self.sv = {}
    self.sv.saved = self.storage:load()
end

function QuestRewardBase.server_onUnload( self )
    self.storage:save( self.sv.saved )
end

function QuestRewardBase.server_canErase( self )
    return true
end

function QuestRewardBase.server_onRemoved( self, player )
    self:sv_n_harvest( nil, player )
end

function QuestRewardBase.sv_n_harvest( self, param, player )
    -- This function will be overwritten by the various child classes
end

-- Client

function QuestRewardBase.client_canErase( self )
    return true
end

function QuestRewardBase.client_onCreate( self )
    self.cl = {}
    self.cl.rotation = math.random() * math.pi * 2
end

function QuestRewardBase.client_onClientDataUpdate( self, params )
    -- This function will be overwritten by the various child classes
end

function QuestRewardBase.client_onDestroy( self )
    self.cl.itemEffect:stop()
end

function QuestRewardBase.client_onUpdate( self, dt )
    -- Slowly rotate the effect
	local rotationSpeed = 0.1875 -- Revolutions per second
	self.cl.rotation = self.cl.rotation + math.pi * 2 * dt * rotationSpeed
	while self.cl.rotation > math.pi * 2 do
		self.cl.rotation = self.cl.rotation - math.pi * 2
	end
	self.cl.rotation = math.max( math.min( self.cl.rotation, math.pi * 2 ), 0 )
	local forward = sm.vec3.new( 0, 1, 0 )
	self.cl.itemEffect:setRotation( sm.vec3.getRotation( forward, forward:rotateZ( self.cl.rotation ) ) )
end

function QuestRewardBase.client_onInteract( self, state )
    self.network:sendToServer( "sv_n_harvest" )
end

function QuestRewardBase.client_canInteract( self )
    -- This function will be overwritten by the various child classes
    return true
end