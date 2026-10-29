
DelayedPushback = class( nil )
DelayedPushback.isSaveObject = true

local TumbleForceModifier = 0.1

function DelayedPushback.server_onCreate( self )
    self.sv = {}
    self.sv.saved = self.storage:load()
    if self.sv.saved == nil then
        self.sv.saved = {}
        self.sv.saved.buildupDelaySeconds = self.params.buildupDelaySeconds or 0.0
        self.sv.saved.pushbackForce = self.params.pushbackForce or 0.0
        self.sv.saved.pushbackDuration = self.params.pushbackDuration or 0.0
        self.sv.saved.pushbackRadius = self.params.pushbackRadius or 0.0
        self.sv.saved.position = self.params.position
        self.sv.saved.effect = self.params.effect
        self.sv.saved.tumbleRadius = self.params.tumbleRadius or 0.0
        self.sv.saved.tumbleDelay = self.params.tumbleDelay or nil
        self.sv.saved.createTick = sm.game.getCurrentTick()
        self.storage:save( self.sv.saved )
    end
    self.sv.startTick = self.sv.saved.createTick + math.floor( self.sv.saved.buildupDelaySeconds * 40.0 )
    if self.sv.saved.tumbleDelay then
        self.sv.tumbleTickDelay = math.floor( self.sv.saved.tumbleDelay * 40 )
    end
    self.sv.endTick = self.sv.startTick + math.floor( self.sv.saved.pushbackDuration * 40.0 )
    self.sv.areaTrigger = sm.areaTrigger.createSphere( self.sv.saved.pushbackRadius, self.sv.saved.position, nil, sm.areaTrigger.filter.character, nil, self.scriptableObject.world )
    self.sv.areaTrigger:setCharacterDetection( true )
    self.sv.currentForce = 0.0
    if self.sv.saved.effect then
        self.network:setClientData( { effect = self.sv.saved.effect, startTick = self.sv.startTick, position = self.sv.saved.position } )
    end
end

function DelayedPushback.server_onFixedUpdate( self )
    local currentTick = sm.game.getCurrentTick()
    if self.sv.areaTrigger then
        local characters = self.sv.areaTrigger:getCharacters()
        self.sv.currentForce = math.min( self.sv.currentForce + ( self.sv.saved.pushbackForce / ( self.sv.saved.pushbackDuration * 40.0 ) ), self.sv.saved.pushbackForce )
        for _,characterInfo in ipairs( characters ) do
            local fromToTarget = characterInfo.character.worldPosition - self.sv.saved.position
            local distanceToTargetSqr = fromToTarget:length2()
            local pushbackDirection = -fromToTarget:safeNormalize( sm.vec3.new( 1,0,0 ) )
            if self.sv.tumbleTickDelay then
                if currentTick >= self.sv.startTick + self.sv.tumbleTickDelay and distanceToTargetSqr <= self.sv.saved.tumbleRadius * self.sv.saved.tumbleRadius then
                    characterInfo.character:setTumbling( true )
                end
            end
            if distanceToTargetSqr <= self.sv.saved.pushbackRadius * self.sv.saved.pushbackRadius then
                ApplyCharacterImpulse( characterInfo.character, -pushbackDirection, self.sv.currentForce, nil, TumbleForceModifier )
            end
        end
        if currentTick > self.sv.endTick then
            self.sv.areaTrigger:destroy()
            self.sv.areaTrigger = nil
            self.scriptableObject:destroy()
        end
    end
end

function DelayedPushback.client_onCreate( self )
    self.cl = {}
    self.cl.effect = nil
    self.cl.startTick = nil
end

function DelayedPushback.client_onClientDataUpdate( self, clientData )
    self.cl.effect = sm.effect.createEffect( clientData.effect )
    self.cl.effect:setPosition( clientData.position )
    self.cl.effect:setWorld( self.scriptableObject.world )
    self.cl.startTick = clientData.startTick
end

function DelayedPushback.client_onFixedUpdate( self )
    local currentTick = sm.game.getCurrentTick()
    if self.cl.effect and self.cl.startTick and currentTick >= self.cl.startTick then
        self.cl.effect:start()
        self.cl.startTick = nil
    end
end

function DelayedPushback.client_onDestroy( self )
    if self.cl.effect then
        self.cl.effect:stop()
        self.cl.effect:destroy()
        self.cl.effect = nil
    end
end