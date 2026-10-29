KinematicAreaTrigger = class( nil )
KinematicAreaTrigger.isSaveObject = true

function KinematicAreaTrigger.server_onCreate( self )
    self.sv = {}
    self.sv.saved = self.storage:load()
    if self.sv.saved == nil then
        self.sv.saved = {}
        if self.params then
            self.sv.saved.kinematicEventTrigger = self.params.kinematicEventTrigger
            self.sv.saved.singleTrigger = self.params.singleTrigger
            self.sv.saved.reactToNonPlayers = self.params.reactToNonPlayers
            self.sv.saved.node = self.params.node
        end
        self.storage:save( self.sv.saved )
    end
    self.sv.activated = false
    self:sv_createAreaTrigger()
end

function KinematicAreaTrigger.server_onDestroy( self )
    if self.sv.areaTrigger then
        sm.areaTrigger.destroy( self.sv.areaTrigger )
    end
end

function KinematicAreaTrigger.sv_createAreaTrigger( self )
    self.sv.areaTrigger = sm.areaTrigger.createBox( self.sv.saved.node.scale / 2, self.sv.saved.node.position, self.sv.saved.node.rotation, sm.areaTrigger.filter.character )
    self.sv.areaTrigger:setCharacterDetection( true )
    self.sv.areaTrigger:bindOnEnter( "sv_e_onEnter", self )
    self.sv.areaTrigger:bindOnExit( "sv_e_onExit", self )
end

function KinematicAreaTrigger.sv_e_onEnter( self, trigger, results )
    if self.sv.activated or ( not self.sv.saved.reactToNonPlayers and not TriggerResultContainsAnyPlayer( results ) ) then
		return
	end

    self:sv_activateKinematics()
    self.sv.activated = true
    if self.sv.saved.singleTrigger then
        sm.areaTrigger.destroy( self.sv.areaTrigger )
        self.sv.areaTrigger = nil
        self.scriptableObject:destroy()
    end
end

function KinematicAreaTrigger.sv_e_onExit( self, trigger, results )
    if not self.sv.saved.reactToNonPlayers and not TriggerResultContainsAnyPlayer( results ) then
		return
	end
    local charactersInTrigger = self.sv.areaTrigger:getCharacters()
    local viableCharacterCount = 0

    for _,characterData in ipairs( charactersInTrigger ) do
        if characterData.character:isPlayer() or self.sv.saved.reactToNonPlayers then
            viableCharacterCount = viableCharacterCount + 1
        end
    end
    if viableCharacterCount == 0 then
        self:sv_activateKinematics()
        self.sv.activated = false
    end
end

function KinematicAreaTrigger.sv_activateKinematics( self )
    local tileStorageKey = TileStorageManager.Sv_GetTileStorageKeyFromPosition( self.scriptableObject.world, self.sv.saved.node.position )
    if tileStorageKey then
        KinematicManager.Sv_Activate( tileStorageKey, self.sv.saved.kinematicEventTrigger )
    else
        sm.log.error( "KinematicAreaTrigger.sv_activateKinematics could not calculate tile storage key for position: " .. tostring( self.sv.saved.node.position ) .. " in world: " .. tostring( self.scriptableObject.world.id ) )
    end
end