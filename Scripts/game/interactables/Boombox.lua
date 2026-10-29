
Boombox = class()
Boombox.keepActiveOnLift = true

function Boombox.sv_n_syncInteract( self )
    self.interactable.active = not self.interactable.active
end

function Boombox.client_onCreate( self )
    self.cl = {}
    self.cl.audioEffect = sm.effect.createEffect( "Boombox - Reciever", self.interactable )
    self.cl.wasActive = false
end

function Boombox.client_onDestroy( self )
    if self.cl.audioEffect then
        self.cl.audioEffect:stopImmediate()
        self.cl.audioEffect:destroy()
    end
end

function Boombox.client_canInteract( self )
    return true
end

function Boombox.client_onInteract( self, character, state )
    if state then
        self.network:sendToServer( "sv_n_syncInteract" )
    end
end

function Boombox.client_onFixedUpdate( self )
    if self.cl.wasActive ~= self.interactable.active then
        if self.interactable.active then
            self.cl.audioEffect:start()
        else
            self.cl.audioEffect:stopImmediate()
        end
        self.cl.wasActive = self.interactable.active
    end
end