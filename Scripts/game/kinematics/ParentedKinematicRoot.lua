dofile( "$SURVIVAL_DATA/Scripts/game/kinematics/Kinematic.lua" )

ParentedKinematicRoot = class( Kinematic )

ParentedKinematicRoot.executionOrder = 100

function ParentedKinematicRoot.server_onCreate( self )
    Kinematic.server_onCreate( self )

    self.sv.tileStorageKey = TileStorageManager.Sv_GetTileStorageKeyFromObject( self.harvestable )

    if self.params and self.params.name then
        self.sv.rootName = self.params.name
        if self.sv.rootName ~= "" then
            TileStorageManager.Sv_SetValueInSubTable( self.sv.tileStorageKey, KINEMATIC_ROOT_NAME_TABLE, self.sv.rootName, self.harvestable )
        end
    else
        sm.log.error( "RootKinematic params missing name" )
    end
    self.sv.hierarchy = {}
    self.sv.childs = {}
end

function ParentedKinematicRoot.server_onDestroy( self )
    Kinematic.server_onDestroy( self )
    
    if self.sv.dirtyHierarchy then
        self.sv.hierarchy = {}
        self:sv_buildHierarchy( self.sv.rootName, self.sv.hierarchy )
        self.sv.dirtyHierarchy = false
    end

    self:sv_destroyChilds( self.sv.hierarchy )
end

function ParentedKinematicRoot.server_onFixedUpdate( self, timeStep )
    Kinematic.server_onFixedUpdate( self, timeStep )
    if self.sv.rootName == "" then
        return
    end

    if self.sv.dirtyHierarchy then
        self.sv.hierarchy = {}
        
        for key, value in pairs( self.sv.childs ) do
            if not sm.exists( value.kinematic ) then
                self.sv.childs[key] = nil
            end
        end

        self:sv_buildHierarchy( self.sv.rootName, self.sv.hierarchy )
        self.sv.dirtyHierarchy = false
        self.network:setClientData( { hierarchy = self.sv.hierarchy }, 3 )
    end

    self:sv_updatePositions( self.sv.hierarchy, self.harvestable )
end

function SetChildTransform( childKinematic, childTransform, parentKinematic )
    local offsetPos = parentKinematic.worldRotation * sm.quat.inverse( parentKinematic.initialRotation ) * ( childKinematic.kinematic.initialPosition - parentKinematic.initialPosition)
    local localPos = childTransform.worldPosition - childKinematic.kinematic.initialPosition
    childKinematic.kinematic:setPosition( parentKinematic.worldPosition + offsetPos + localPos )
    childKinematic.kinematic:setRotation( parentKinematic.worldRotation * sm.quat.inverse( parentKinematic.initialRotation ) * childTransform.worldRotation )
end

function ParentedKinematicRoot.sv_destroyChilds( self, childs )
    for _, child in ipairs( childs ) do
        if sm.exists( child.kinematic ) then
            child.kinematic:destroy()
            self:sv_destroyChilds( child.childs )
        end
    end
end

function ParentedKinematicRoot.sv_updatePositions( self, childs, parentKinematic )
    for _, child in ipairs( childs ) do
        if sm.exists( child.kinematic ) then
            local childWorldTransform = child.kinematic.publicData.transform
            SetChildTransform( child, childWorldTransform, parentKinematic )
            self:sv_updatePositions( child.childs, child.kinematic )
        end
    end
end

function ParentedKinematicRoot.cl_updatePositions( self, childs, parentKinematic )
    for _, child in ipairs( childs ) do
        if sm.exists( child.kinematic ) then
            local childWorldTransform = child.kinematic.clientPublicData.transform
            SetChildTransform( child, childWorldTransform, parentKinematic )
            self:cl_updatePositions( child.childs, child.kinematic )
        end
    end
end

function ParentedKinematicRoot.sv_e_registerChildKinematic( self, params )

    local key = params.name
    if key == nil or key == "" then
        key = params.kinematic.id
    end
    self.sv.childs[key] = {
        kinematic = params.kinematic,
        parentName = params.parentName
    }
    self.sv.dirtyHierarchy = true
end

function ParentedKinematicRoot.sv_buildHierarchy( self, nodeName, childList )
    for childName, childParams in pairs( self.sv.childs ) do
        if childParams.parentName == nodeName then
            local newNode = { kinematic = childParams.kinematic, childs = {} }
            self:sv_buildHierarchy( childName, newNode.childs )
            childList[#childList+1] = newNode
        end
    end

    self.harvestable.publicData = self.harvestable.publicData or {}
    self.harvestable.publicData.childs = self.sv.childs
end

function ParentedKinematicRoot.client_onClientDataUpdate( self, data, channel )
    if channel == 3 then
        if data.hierarchy ~= nil then
            self.cl.hierarchy = data.hierarchy
        end
    else
        Kinematic.client_onClientDataUpdate( self, data, channel )
    end
end

function ParentedKinematicRoot.client_onCreate( self )
    Kinematic.client_onCreate( self )
    self.cl.hierarchy = {}
end


function ParentedKinematicRoot.client_onFixedUpdate( self )
    if sm.isHost then
        return
    end
    Kinematic.client_onFixedUpdate( self )
    self:cl_updatePositions( self.cl.hierarchy, self.harvestable )
end

function ParentedKinematicRoot.cl_n_hide( self )
    if sm.exists( self.harvestable ) then
        self.harvestable:setAllSubMeshVisible( false )
        self:cl_hideChilds( self.cl.hierarchy )
    end
end

function ParentedKinematicRoot.cl_hideChilds( self, childs )
    for _, child in ipairs( childs ) do
        if sm.exists( child.kinematic ) then
            child.kinematic:setAllSubMeshVisible( false )
            self:cl_hideChilds( child.childs )
        end
    end
end
