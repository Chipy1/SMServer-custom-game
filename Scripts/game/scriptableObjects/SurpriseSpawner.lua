SurpriseSpawner = class( nil )
SurpriseSpawner.isSaveObject = true

function SurpriseSpawner.server_onCreate( self )
    self.sv = {}
    self.sv.saved = self.storage:load()
    if self.sv.saved == nil then
        self.sv.saved = {}
        if self.params then
            self.sv.saved.keyTag = self.params.keyTag -- TODO This should not be keytag, not used as a key/lock
            self.sv.saved.node = self.params.node
            self.sv.saved.keyList = self.params.keyList
        end
        self.storage:save( self.sv.saved )
    end
    self:sv_createAreaTrigger()
end

function SurpriseSpawner.server_onDestroy( self )
    if self.sv.areaTrigger then
        sm.areaTrigger.destroy( self.sv.areaTrigger )
    end
end

function SurpriseSpawner.sv_createAreaTrigger( self )
    self.sv.areaTrigger = sm.areaTrigger.createBox( self.sv.saved.node.scale / 2, self.sv.saved.node.position, self.sv.saved.node.rotation, sm.areaTrigger.filter.character )
    self.sv.areaTrigger:bindOnEnter( "sv_e_onEnter", self )
end

function SurpriseSpawner.sv_e_onEnter( self, trigger, results )
    if not self:sv_resultsContainsPlayer( results ) then
		return
	end
    sm.areaTrigger.destroy( self.sv.areaTrigger )
    self.sv.areaTrigger = nil
    
    local function triggerRegisteredObjects( tileStorageKey, keyTag)
        local registeredObjects = TileStorageManager.Sv_GetValueInSubTable( tileStorageKey, SURPRISE_SPAWNER_TABLE, keyTag )
        if registeredObjects then
            for _, object in ipairs( registeredObjects ) do
                if sm.exists( object ) then
                    if type( object ) == "Harvestable" then
                        sm.event.sendToHarvestable( object, "sv_e_activate" )
                    elseif type( object ) == "Interactable" then
                        sm.event.sendToInteractable( object, "sv_e_activate" )
                    end
                end
            end
        end
    end

    local tileStorageKey = TileStorageManager.Sv_GetTileStorageKeyFromPosition( self.scriptableObject.world, self.sv.saved.node.position )
    if tileStorageKey == nil then
        sm.log.error( "SurpriseSpawner.sv_e_onEnter could not calculate tile storage key for position: " .. tostring( self.sv.saved.node.position ) .. " in world: " .. tostring( self.scriptableObject.world.id ) )
        return
    end
    if self.sv.saved.keyTag then
        triggerRegisteredObjects( tileStorageKey, self.sv.saved.keyTag )
    end
    if self.sv.saved.keyList then
        for _,key in ipairs( self.sv.saved.keyList.keyList ) do
            if key.keyTag ~= "" then
                triggerRegisteredObjects( tileStorageKey, key.keyTag )
            end
        end
    end

    self.scriptableObject:destroy()
end

function SurpriseSpawner.sv_resultsContainsPlayer( self, results )
	for _,result in ipairs( results ) do
		if sm.exists( result ) then
			if result:isPlayer() then
				return true
			end
		end
	end
	return false
end