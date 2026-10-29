NodeScriptableManager = class( nil )

function NodeScriptableManager.server_onCreate( self )
    g_nodeScriptableManagerServer = self
end

function NodeScriptableManager.Sv_OnCellCreated( x, y, world )
    g_nodeScriptableManagerServer:sv_onCellCreated( x, y, world )
end

function NodeScriptableManager.sv_onCellCreated( self, x, y, world )
    local nodes = sm.cell.getNodesByTag( x, y, "SCRIPTABLE_NODE", world )

    for _,node in ipairs( nodes ) do
        local params = node.params
        params.node = {}
        params.node.position = node.position
        params.node.rotation = node.rotation
        params.node.scale = node.scale
        local uuid = sm.uuid.new( node.params.scriptableUuid )
        sm.scriptableObject.createScriptableObject( uuid, params, world )
    end
end