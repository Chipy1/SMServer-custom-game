dofile( "$SURVIVAL_DATA/Scripts/game/survival_constants.lua" )

WorldMarkerManager = class( nil )

local updateFrequency = 40 * 10

-- Client

function WorldMarkerManager.client_onCreate( self )

    self.cl = {}
    self.cl.currentWorld = nil
    self.cl.markers = {}
    self.cl.compassEnabled = sm.game.getSettingBoolean( "CompassHud" )

    g_worldMarkerManager = self
end

function WorldMarkerManager.client_onFixedUpdate( self, dt )

















































































    local compassSetting = sm.game.getSettingBoolean( "CompassHud" )
    if self.cl.compassEnabled ~= compassSetting then
        self.cl.compassEnabled = compassSetting
    end
end

function WorldMarkerManager.Cl_CreateOrUpdateMarker( name, params )
    g_worldMarkerManager:cl_createOrUpdateMarker( name, params )
end

function WorldMarkerManager.cl_createOrUpdateMarker( self, name, params )
    local marker = self.cl.markers[name]
    local isNew = marker == nil
    if isNew then
        marker = {}
        self.cl.markers[name] = marker
        marker.effectName = params.effect
        marker.billboardEffect = sm.effect.createEffect( params.effect )
        marker.billboardEffect:setWorldAny()
        marker.hidden = true
        if g_compassHud then
            g_compassHud:compassAddIcon( name )
        end
    end

    marker.color = params.color or marker.color or sm.color.new( "7a3e8bff" )

    if params.compassOnly ~= nil then
        marker.compassOnly = params.compassOnly
    end

    if params.farEffect ~= nil and marker.farBillboardEffect == nil then
        marker.farBillboardEffect = sm.effect.createEffect( params.farEffect )
        marker.farBillboardEffect:setWorldAny()
    end

    if params.textureIndex ~= nil then
        marker.textureIndex = params.textureIndex
        marker.billboardEffect:setParameter( "textureIndex", params.textureIndex )
        if marker.farBillboardEffect then
            marker.farBillboardEffect:setParameter( "textureIndex", params.textureIndex )
        end
    end
    if params.textureName ~= nil then
        marker.textureName = params.textureName
        marker.billboardEffect:setParameter( "textureName", params.textureName )
    end
    if params.iconColor ~= nil then
        marker.iconColor = params.iconColor
        marker.billboardEffect:setParameter( "color", params.iconColor )
    end
    if params.lineOfSight ~= nil then
        marker.lineOfSight = params.lineOfSight
        marker.billboardEffect:setParameter( "lineOfSight", params.lineOfSight )
    end

    if g_compassHud then
        if params.compassImage ~= nil and name ~= "" then
            g_compassHud:setImage( name, params.compassImage )
        end
        if params.compassItemIcon ~= nil then
            g_compassHud:setItemIcon( name, params.compassItemIcon.resource, params.compassItemIcon.group, params.compassItemIcon.name )
        end
        if params.compassColor ~= nil then
            g_compassHud:setColor( name, params.compassColor )
        end
        if params.compassStacking ~= nil then
            g_compassHud:compassSetIconStacking( name, params.compassStacking )
        end
    end

    if params.position ~= nil and params.world ~= nil then
        self:cl_setWorldPosition( name, params.position, params.world )
    end
    if params.host ~= nil then
        self:cl_setHost( name, params.host, params.hostOffset )
    end

    if params.activate then
        self:cl_activateMarker( name )
    end
end

-- Determines whether a marker in the given world is currently reachable from the local player's world.
function WorldMarkerManager.cl_computeHasPath( self, world )
    if world == nil or self.cl.currentWorld == nil or self.cl.currentWorld.id == world.id then
        return true, nil
    end
    local character = sm.localPlayer.getPlayer():getCharacter()
    if character == nil then
        return true, nil
    end
    local portalPos, portal = sm.portal.findBestPortalToWorld( self.cl.currentWorld.id, world.id, character:getWorldPosition() )
    if portal and portal.id == -1 then
        return false, nil
    end
    return true, portalPos
end

function WorldMarkerManager.Cl_SetWorldPosition( name, position, world )
    g_worldMarkerManager:cl_setWorldPosition( name, position, world )
end

function WorldMarkerManager.cl_setWorldPosition( self, name, position, world )
    local marker = self.cl.markers[name]
    if marker ~= nil then
        marker.world = world
        marker.markerPosition = position
        local hasPath, portalPos = self:cl_computeHasPath( world )
        local displayPosition, displayWorld
        if hasPath then
            displayPosition = portalPos or position
            displayWorld = portalPos and self.cl.currentWorld or world
        end
        if displayPosition and displayWorld then
            marker.displayPosition = displayPosition
            if not sm.exists( marker.billboardEffect ) then
                marker.billboardEffect = sm.effect.createEffect( marker.effectName )
                if not marker.hosted then
                    marker.billboardEffect:setWorldAny()
                end
            end
            if not marker.hosted then
                marker.billboardEffect:setPosition( displayPosition )
                if marker.farBillboardEffect then
                    marker.farBillboardEffect:setPosition( displayPosition )
                end
                if g_compassHud then
                    g_compassHud:compassSetIconWorldPosition( name, displayPosition, displayWorld )
                end
            end
            if not marker.hidden then
                self:cl_activateMarker( name )
            end
        else
            if sm.exists( marker.billboardEffect ) then
                marker.billboardEffect:stop()
            end
            if marker.farBillboardEffect and sm.exists( marker.farBillboardEffect ) then
                marker.farBillboardEffect:stop()
            end
            if g_compassHud then
                g_compassHud:setVisible( name, false )
            end
        end
    end
end

function WorldMarkerManager.Cl_SetHost( name, host, offset )
    g_worldMarkerManager:cl_setHost( name, host, offset )
end

function WorldMarkerManager.cl_setHost( self, name, host, offset )
    local marker = self.cl.markers[name]
    if marker ~= nil then
        if marker.billboardEffect and sm.exists( marker.billboardEffect ) then
            marker.billboardEffect:stop()
            marker.billboardEffect:setHost( host )
            if offset then
                marker.billboardEffect:setOffsetPosition( offset )
                marker.billboardEffect:setHostAxisIgnore( sm.effect.axis.all )
            end
        end
        if marker.farBillboardEffect and sm.exists( marker.farBillboardEffect ) then
            marker.farBillboardEffect:stop()
            marker.farBillboardEffect:setHost( host )
            if offset then
                marker.farBillboardEffect:setOffsetPosition( offset )
                marker.farBillboardEffect:setHostAxisIgnore( sm.effect.axis.all )
            end
        end

        marker.hosted = true
        marker.host = host
        marker.hostOffset = offset
        if type( host ) == "Shape" then
            marker.world = host.body:getWorld()
        elseif type( host ) == "Character" then
            marker.world = host:getWorld()
        end
        
        local hasPath = self:cl_computeHasPath( marker.world )

        if g_compassHud then
            g_compassHud:compassSetIconHost( name, host )
            if not marker.hidden and hasPath then
                g_compassHud:setVisible( name, true )
            end
        end
        if not marker.hidden and not marker.compassOnly and hasPath then
            if marker.billboardEffect and sm.exists( marker.billboardEffect ) then
                marker.billboardEffect:start()
            end
            if marker.farBillboardEffect and sm.exists( marker.farBillboardEffect ) then
                marker.farBillboardEffect:start()
            end
        end
    end
end

function WorldMarkerManager.Cl_ActivateMarker( name )
    g_worldMarkerManager:cl_activateMarker( name )
end

function WorldMarkerManager.cl_activateMarker( self, name )
    local marker = self.cl.markers[name]
    if marker ~= nil then
        
        if not self:cl_computeHasPath( marker.world ) then
            return
        end

        if not marker.compassOnly then
            if sm.exists( marker.billboardEffect ) and not marker.billboardEffect:isPlaying() then
                if not marker.billboardEffect:hasHost() then
                    marker.billboardEffect:setWorldAny()
                end
                marker.billboardEffect:start()
            end
            if marker.farBillboardEffect and sm.exists( marker.farBillboardEffect ) and not marker.farBillboardEffect:isPlaying() then
                if not marker.farBillboardEffect:hasHost() then
                    marker.farBillboardEffect:setWorldAny()
                end
                marker.farBillboardEffect:start()
            end
        end
        if g_compassHud then
            g_compassHud:setVisible( name, true )
            if marker.hidden then
                g_compassHud:compassPingMarker( name, "Gui - Pingnavigation", marker.color )
            end
        end
        marker.hidden = false
    end
end

function WorldMarkerManager.Cl_HideMarker( name )
    g_worldMarkerManager:cl_hideMarker( name )
end

function WorldMarkerManager.cl_hideMarker( self, name )
    local marker = self.cl.markers[name]
    if marker ~= nil then
        if marker.billboardEffect and sm.exists( marker.billboardEffect ) then
            marker.billboardEffect:stop()
        end
        if marker.farBillboardEffect and sm.exists( marker.farBillboardEffect ) then
            marker.farBillboardEffect:stop()
        end
        if g_compassHud then
            g_compassHud:setVisible( name, false )
        end
        marker.hidden = true
    end
end

function WorldMarkerManager.Cl_IsMarkerHidden( name )
    return g_worldMarkerManager:cl_isMarkerHidden( name )
end

function WorldMarkerManager.cl_isMarkerHidden( self, name )
    local marker = self.cl.markers[name]
    if marker ~= nil then
        return marker.hidden
    end
    return nil
end

function WorldMarkerManager.Cl_DetachMarker( name )
    g_worldMarkerManager:cl_detachMarker( name )
end

function WorldMarkerManager.cl_detachMarker( self, name )
    local marker = self.cl.markers[name]
    if marker ~= nil then
        if sm.exists( marker.billboardEffect ) then
            marker.billboardEffect:detach()
            marker.billboardEffect:setWorldAny()
        end
        if marker.farBillboardEffect and sm.exists( marker.farBillboardEffect ) then
            marker.farBillboardEffect:detach()
            marker.farBillboardEffect:setWorldAny()
        end
        marker.hosted = false
        -- The host is gone (e.g. its world unloaded). Fall back to the host's last known world position
        -- so the marker stays visible, including through a portal when it lives in another world.
        if marker.world ~= nil and marker.markerPosition ~= nil then
            self:cl_setWorldPosition( name, marker.markerPosition, marker.world )
        elseif g_compassHud and marker.displayPosition then
            g_compassHud:compassSetIconWorldPosition( name, marker.displayPosition, marker.world )
        end
    end
end

function WorldMarkerManager.Cl_DestroyMarker( name )
    g_worldMarkerManager:cl_destroyMarker( name )
end

function WorldMarkerManager.cl_destroyMarker( self, name )
    local marker = self.cl.markers[name]
    if marker ~= nil then
        if sm.exists( marker.billboardEffect ) then
            marker.billboardEffect:destroy()
        end
        if marker.farBillboardEffect and sm.exists( marker.farBillboardEffect ) then
            marker.farBillboardEffect:destroy()
        end
        if g_compassHud then
            g_compassHud:compassRemoveIcon( name )
        end
    end
    self.cl.markers[name] = nil
end

function WorldMarkerManager.Cl_GetMarkerHost( name )
    return g_worldMarkerManager:cl_getMarkerHost( name )
end

function WorldMarkerManager.cl_getMarkerHost( self, name )
    local marker = self.cl.markers[name]
    if marker ~= nil then
       return marker.host
    end
    return nil
end

function WorldMarkerManager.Cl_GetMarkerPosition( name )
    return g_worldMarkerManager:cl_getMarkerPosition( name )
end

function WorldMarkerManager.cl_getMarkerPosition( self, name )
    local marker = self.cl.markers[name]
    if marker ~= nil then
       return marker.displayPosition
    end
    return sm.vec3.new( 0, 0, 0 )
end

function WorldMarkerManager.Cl_GetMarkerWorldPosition( name )
    return g_worldMarkerManager:cl_getMarkerWorldPosition( name )
end

function WorldMarkerManager.cl_getMarkerWorldPosition( self, name )
    local marker = self.cl.markers[name]
    if marker ~= nil then
        local player = sm.localPlayer.getPlayer()
        local character = player:getCharacter()
        local playerWorld = character:getWorld()
        if marker.hosted and marker.host ~= nil and sm.exists( marker.host ) then
            local hostWorld, hostPosition
            if type( marker.host ) == "Shape" and sm.exists( marker.host.body ) then
                hostWorld = marker.host.body:getWorld()
                hostPosition = marker.host.worldPosition
            else
                return marker.billboardEffect:getWorldPosition()
            end
            if hostPosition ~= nil and hostWorld ~= nil and hostWorld == playerWorld then
                return hostPosition
            end
            return marker.displayPosition
        else
            if marker.world == nil or marker.world == playerWorld then
                return marker.billboardEffect:getWorldPosition()
            else
                return marker.displayPosition
            end
        end
    end
    return nil
end

function WorldMarkerManager.client_onLocalPlayerChangedWorld( self, world )
    self.cl.currentWorld = world
    self:cl_refreshHostedMarkers()
    self:cl_updateMarkersPositions()
    if g_beaconManager then
        g_beaconManager:cl_onLocalPlayerChangedWorld( world.id )
    end
end

function WorldMarkerManager.cl_updateMarkersPositions( self )
    for name, markerData in pairs( self.cl.markers ) do
        if markerData.world ~= nil and not markerData.hosted then
            self:cl_setWorldPosition( name, markerData.markerPosition, markerData.world )
        end
    end
end

-- Re-evaluate hosted markers when the local player changes world.
function WorldMarkerManager.cl_refreshHostedMarkers( self )
    for name, marker in pairs( self.cl.markers ) do
        if marker.host ~= nil then
            local hostExists = sm.exists( marker.host )
            local hostWorld = marker.world
            if hostExists then
                if type( marker.host ) == "Shape" then
                    hostWorld = marker.host.body:getWorld()
                elseif type( marker.host ) == "Character" then
                    hostWorld = marker.host:getWorld()
                end
                marker.world = hostWorld
            end

            local inHostWorld = self.cl.currentWorld ~= nil and hostWorld ~= nil and self.cl.currentWorld.id == hostWorld.id

            if inHostWorld and hostExists then
                -- Back in the host's world: (re)attach the billboard so it tracks the host exactly.
                self:cl_setHost( name, marker.host, marker.hostOffset )
            else
                -- Host is in another world (or unloaded): detach and show the marker at its world
                -- position so it is displayed at the portal.
                if marker.hosted then
                    if sm.exists( marker.billboardEffect ) then
                        marker.billboardEffect:detach()
                        marker.billboardEffect:setWorldAny()
                    end
                    if marker.farBillboardEffect and sm.exists( marker.farBillboardEffect ) then
                        marker.farBillboardEffect:detach()
                        marker.farBillboardEffect:setWorldAny()
                    end
                    marker.hosted = false
                end
                if hostWorld ~= nil and marker.markerPosition ~= nil then
                    self:cl_setWorldPosition( name, marker.markerPosition, hostWorld )
                end
            end
        end
    end
end