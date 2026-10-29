PotatoAmmoSpawn = class( nil )

function PotatoAmmoSpawn.server_onCreate( self )
    local shape = sm.shape.createPart( obj_plantables_potato, self.params.node.position - self.params.node.scale, self.params.node.rotation, self.params.dynamic, true )
    shape.stackedAmount = math.random( self.params.minAmount, self.params.maxAmount )
    self.scriptableObject:destroy()
end