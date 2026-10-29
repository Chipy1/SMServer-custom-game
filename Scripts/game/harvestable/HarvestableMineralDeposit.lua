dofile("$SURVIVAL_DATA/Scripts/game/survival_loot.lua")

HarvestableMineralDeposit = class()

local LeadHitEffects = {
	"Lead - Harvest01",
	"Lead - Harvest02",
	"Lead - Harvest03",
	"Lead - Destroy"
}
local SodiumHitEffects = {
	"Sodium - Harvest01",
	"Sodium - Harvest02",
	"Sodium - Harvest03",
	"Sodium - Destroy"
}

function HarvestableMineralDeposit.server_onCreate( self )
	self.sv = {}

    self.sv.saved = self.storage:load()
    if self.sv.saved == nil then
        self.sv.saved = {}
        self.sv.saved.damageStage = 0
        self.storage:save( self.sv.saved )
    end

	if self.data then
		if self.data.type == "lead" then
			self.sv.loot = obj_resource_lead
			self.sv.destructionEffect = "Lead - Destroy"
			self.sv.hitEffectList = LeadHitEffects
		elseif self.data.type == "sodium" then
			self.sv.loot = obj_resource_sodium -- placeholder
			self.sv.destructionEffect = "Sodium - Destroy"
			self.sv.hitEffectList = SodiumHitEffects
		end
		self.sv.submeshName = self.data.type
	else
		self.sv.destructionEffect = "Lead - Destroy"
		self.sv.loot = obj_resource_lead
		self.sv.submeshName = "lead"
	end

    self.network:setClientData( { damageStage = self.sv.saved.damageStage, submesh = self.sv.submeshName } )
end

function HarvestableMineralDeposit.sv_onHit( self )
	if self.sv.saved.damageStage < 4 and not self.destroyed then
        self.sv.saved.damageStage = self.sv.saved.damageStage + 1
		if SurvivalGame then
			local lootList = {}
			local slots = math.random( 1 )
			for i = 1, slots do
				lootList[i] = { uuid = self.sv.loot, quantity = 1 }
			end
			local angle = math.pi / math.random( 14, 24 )
			SpawnLoot( self.harvestable, lootList, self.harvestable.worldPosition + sm.vec3.new( 0, 0, 2.0 ), angle )
		end
		if self.sv.saved.damageStage >= 4 then
			sm.effect.playEffect( self.sv.destructionEffect, self.harvestable.worldPosition, nil, self.harvestable.worldRotation )
			self.harvestable:destroy()
			self.destroyed = true
			return
		end
		sm.effect.playEffect( self.sv.hitEffectList[self.sv.saved.damageStage], self.harvestable.worldPosition, nil, self.harvestable.worldRotation )

        self.storage:save( self.sv.saved )
        self.network:setClientData( { damageStage = self.sv.saved.damageStage, submesh = self.sv.submeshName } )
	end
end

function HarvestableMineralDeposit.server_onMelee( self, hitPos, attacker, damage, power, hitDirection )
	self:sv_onHit()
end

function HarvestableMineralDeposit.server_onExplosion( self, center, destructionLevel )
	self:sv_onHit()
end

function HarvestableMineralDeposit.server_onFloating( self )
	for damageStage = self.sv.saved.damageStage + 1, 4 do
		local lootList = { { uuid = self.sv.loot, quantity = 1 } }
		sm.effect.playEffect( self.sv.hitEffectList[damageStage], self.harvestable.worldPosition, nil, self.harvestable.worldRotation )
		local angle = math.pi / math.random( 14, 24 )
		SpawnLoot( self.harvestable, lootList, self.harvestable.worldPosition + sm.vec3.new( 0, 0, 2.0 ), angle )
		sm.effect.playEffect( self.sv.destructionEffect, self.harvestable.worldPosition, nil, self.harvestable.worldRotation )
		self.harvestable:destroy()
		self.destroyed = true
	end
end

-- Client

function HarvestableMineralDeposit.client_onClientDataUpdate( self, data )
	self:cl_updateSubmeshVisibility( data.damageStage, data.submesh )
end

function HarvestableMineralDeposit.cl_updateSubmeshVisibility( self, damageStage, submesh )
	local show0 = damageStage == 0
	self.harvestable:setSubMeshVisible( "submesh0_"..submesh, show0 )
	self.harvestable:setSubMeshVisible( "submesh0_rock", show0 )
	local show1 = damageStage == 1
	self.harvestable:setSubMeshVisible( "submesh1_"..submesh, show1 )
	self.harvestable:setSubMeshVisible( "submesh1_rock", show1 )
	local show2 = damageStage == 2
	self.harvestable:setSubMeshVisible( "submesh2_"..submesh, show2 )
	self.harvestable:setSubMeshVisible( "submesh2_rock", show2 )
	local show3 = damageStage == 3
	self.harvestable:setSubMeshVisible( "submesh3_"..submesh, show3 )
	self.harvestable:setSubMeshVisible( "submesh3_rock", show3 )
end