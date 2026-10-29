dofile( "$SURVIVAL_DATA/Scripts/util.lua" )

UraniumOre = class()

function UraniumOre.server_onCreate( self )
    self.sv = {}

    local filter = sm.areaTrigger.filter.character
	self.sv.areaTrigger = sm.areaTrigger.createAttachedSphere( self.shape, self.data.damageRadius, nil, nil, filter )
	self.sv.areaTrigger:bindOnEnter( "sv_onTriggerEnter" )
    self.sv.areaTrigger:bindOnStay( "sv_onTriggerStay" )
end

function UraniumOre.server_onDestroy( self )
    if self.sv.areaTrigger and sm.exists( self.sv.areaTrigger ) then
        self.sv.areaTrigger:destroy()
        self.sv.areaTrigger = nil
    end
end

function UraniumOre.sv_onTriggerEnter( self, _, results )
    FireTriggerEventForPlayers( results, "sv_e_onEnterRadiation" )
end

function UraniumOre.sv_onTriggerStay( self, _, results )
    FireTriggerEventForPlayers( results, "sv_e_onStayRadiation" )
end

function UraniumOre.client_onCreate( self )
    self.cl = {}
    self.cl.effect = sm.effect.createEffect( "Reactor - Uranium_oreball_glow", self.shape, nil, sm.effect.axis.all )
    self.cl.effect:start()
end

function UraniumOre.client_onDestroy( self )
    if self.cl.effect and sm.exists( self.cl.effect ) then
        self.cl.effect:stop()
        self.cl.effect = nil
    end
end