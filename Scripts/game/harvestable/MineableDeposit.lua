dofile( "$SURVIVAL_DATA/Scripts/game/survival_items.lua" )

MineableDeposit = class()

local LootSources = {
	[tostring( hvs_deposit_common_small )] = "lootsource_deposit_common_small",
	[tostring( hvs_deposit_common_big )] = "lootsource_deposit_common_big",
	[tostring( hvs_deposit_rare_small )] = "lootsource_deposit_rare_small",
	[tostring( hvs_deposit_rare_big )] = "lootsource_deposit_rare_big",
	[tostring( hvs_deposit_blue_small )] = "lootsource_deposit_blue_small",
	[tostring( hvs_deposit_blue_big )] = "lootsource_deposit_blue_big",
	[tostring( hvs_deposit_purple_small )] = "lootsource_deposit_purple_small",
	[tostring( hvs_deposit_purple_big )] = "lootsource_deposit_purple_big",
	[tostring( hvs_deposit_red_small )] = "lootsource_deposit_red_small",
	[tostring( hvs_deposit_red_big )] = "lootsource_deposit_red_big",
}

function MineableDeposit.server_onCreate( self )
    self.sv = {}
    self.sv.damage = 0
    self.harvestable.publicData = { drillLevel = 1 }
end

function MineableDeposit.sv_e_plasmaDrill( self, params )

    if not self.sv.destroyed then
        self.sv.damage = self.sv.damage + params.progress
        if self.sv.damage >= self.data.destructionTime then
			self.sv.destroyed = true
			if self.data.breakEffect then
				sm.effect.playEffect( self.data.breakEffect, self.harvestable.worldPosition )
			end
			local lootSource = LootSources[tostring( self.harvestable.uuid )]
			if lootSource then
				local lootList = SelectLoot( lootSource )
				SpawnLoot( self.harvestable, lootList, self.harvestable.worldPosition + sm.vec3.new( 0, 0, 1.0 ) )
				sm.effect.playEffect( "Stone - BreakChunk", self.harvestable.worldPosition, nil, self.harvestable.worldRotation, nil, { size = 10000 / AUDIO_MASS_DIVIDE_RATIO } )
			end
			self.harvestable:destroy()
		elseif self.data.impactEffect then
            local rotation = sm.quat.identity()
            local direction = ( params.position - self.harvestable.worldPosition ):safeNormalize( sm.vec3.new( 1, 0, 0 ) )
            rotation = sm.vec3.getRotation( sm.vec3.new( 0, 0, 1 ), direction )
            self.sv.impactEffect = sm.effect.playEffect( self.data.impactEffect, params.position, nil, rotation )
        end
    end

end

function MineableDeposit.server_onMelee( self, hitPos, attacker, damage, power, hitDirection )
	--self.network:sendToClient( attacker, "cl_n_onMessage", "Requires explosives" )

	--print( LootSources[tostring( self.harvestable.uuid )] )
    self.sv.damage = self.sv.damage + damage * 0.035
	if self.sv.damage >= self.data.destructionTime and not self.sv.destroyed then
		self.sv.destroyed = true
		if self.data.breakEffect then
			sm.effect.playEffect( self.data.breakEffect, self.harvestable.worldPosition )
		end
		local lootSource = LootSources[tostring( self.harvestable.uuid )]
		if lootSource then
			local lootList = SelectLoot( lootSource )
			SpawnLoot( self.harvestable, lootList, self.harvestable.worldPosition - hitDirection )
			sm.effect.playEffect( "Stone - BreakChunk", self.harvestable.worldPosition, nil, self.harvestable.worldRotation, nil, { size = 10000 / AUDIO_MASS_DIVIDE_RATIO } )
		end
		self.harvestable:destroy()
	end

end

function MineableDeposit.server_onFloating( self )

	if not self.sv.destroyed then
		self.sv.destroyed = true
		if self.data.breakEffect then
			sm.effect.playEffect( self.data.breakEffect, self.harvestable.worldPosition )
		end
		local lootSource = LootSources[tostring( self.harvestable.uuid )]
		if lootSource then
			local lootList = SelectLoot( lootSource )
			SpawnLoot( self.harvestable, lootList, self.harvestable.worldPosition )
			sm.effect.playEffect( "Stone - BreakChunk", self.harvestable.worldPosition, nil, self.harvestable.worldRotation, nil, { size = 10000 / AUDIO_MASS_DIVIDE_RATIO } )
		end
		self.harvestable:destroy()
	end

end

function MineableDeposit.cl_n_onMessage( self, msg )
	NotificationManager.Cl_AddGenericNotification( msg, 2 )
end

function MineableDeposit.server_onExplosion( self, center, destructionLevel )
	if not self.sv.destroyed then
		self.sv.destroyed = true
		if self.data.breakEffect then
			sm.effect.playEffect( self.data.breakEffect, self.harvestable.worldPosition )
		end
		local lootSource = LootSources[tostring( self.harvestable.uuid )]
		if lootSource then
			local lootList = SelectLoot( lootSource )
			SpawnLoot( self.harvestable, lootList, self.harvestable.worldPosition, math.pi / 9 )
			sm.effect.playEffect( "Stone - BreakChunk", self.harvestable.worldPosition, nil, self.harvestable.worldRotation, nil, { size = 10000 / AUDIO_MASS_DIVIDE_RATIO } )
		end
		self.harvestable:destroy()
	end
end
