dofile( "$SURVIVAL_DATA/Scripts/game/survival_items.lua" )

RewardLockerBase = class()

local RecipeUnlockList = {
	{ tostring( blk_metalnet ), tostring( blk_tryponet ) },
	{ tostring( blk_plastic ), tostring( blk_bubblewrap ) },
	{ tostring( blk_glasstile ), tostring( blk_caution ) },
	{ tostring( blk_tiles ), tostring( blk_restroom ), tostring( blk_bricks ) },
	{ tostring( blk_concretetiles ), tostring( blk_stripednet ), tostring( blk_squarenet  ) },
	{ tostring( blk_treadplate ), tostring( blk_beam ), tostring( blk_warehousefloor ) },
	{ tostring( blk_wornmetal ), tostring( blk_metalbricks ), tostring( blk_crackedconcrete ), tostring( blk_drywall ), tostring( blk_insulation ), tostring( blk_plasticwall )}
}

local BlockRewardAmount = {
	[tostring( blk_sand )] = 200,
	[tostring( blk_concrete1 )] = 200,
	[tostring( blk_plastic )] = 200,
	[tostring( blk_carpet )] = 200,
	[tostring( blk_metalnet )] = 200,
	[tostring( blk_tryponet )] = 200,
	[tostring( blk_plastic )] = 500,
	[tostring( blk_bubblewrap )] = 500,
	[tostring( blk_glasstile )] = 500,
	[tostring( blk_caution )] = 500,
	[tostring( blk_concrete3 )] = 200,
	[tostring( blk_wood3 )] = 200,
	[tostring( blk_metal3 )] = 200,
	[tostring( blk_tiles )] = 200,
	[tostring( blk_restroom )] = 200,
	[tostring( blk_bricks )] = 200,
	[tostring( blk_treadplate )] = 200,
	[tostring( blk_wornmetal )] = 200,
	[tostring( blk_crackedconcrete )] = 200,
	[tostring( blk_beam )] = 50,
	[tostring( blk_metalbricks )] = 50,
	[tostring( blk_drywall )] = 50,
	[tostring( blk_insulation )] = 50,
	[tostring( blk_plasticwall )] = 50,
	[tostring( blk_warehousefloor )] = 50,
	[tostring( blk_concretetiles )] = 50,
	[tostring( blk_stripednet )] = 50,
	[tostring( blk_squarenet )] = 50
}

local MinimumStackSize = 20
local MaximumStackSize = 40
local LootSpawnTickInterval = math.floor( 0.1 * 40 )
local DamageCooldownTickTime = math.floor( 1 * 40 )

local RewardRotationSpeedPerSecond = 720.0

local ReplacementHarvestable = sm.uuid.new( "4b735c21-f3d5-41c1-bd1a-054064ab5088" )

function RewardLockerBase.server_onCreate( self )
	self.sv = {}
	self.sv.saved = self.storage:load()
	if self.sv.saved == nil then
		self.sv.saved = {}
		self.sv.saved.health = 5
		self.sv.saved.destroyed = false
	end
	self.sv.isSpawningLoot = false
	self.sv.spawnTable = {}
	self.sv.spawnIndex = 1
	self.sv.lootSpawnTickCounter = 0
	self.sv.damageTickCooldown = 0
	self.sv.spawnDirection = self.harvestable.worldRotation * sm.vec3.new( 1, 0, 0 )
	self.sv.upDirection = self.harvestable.worldRotation * sm.vec3.new( 0, 1, 0 )

	self.network:setClientData( { health = self.sv.saved.health, startup = true } )
end

function RewardLockerBase.server_onFixedUpdate( self, dt )
	if self.sv.damageTickCooldown > 0 then
		self.sv.damageTickCooldown = self.sv.damageTickCooldown - 1
	end
	if self.sv.isSpawningLoot then
		self.sv.lootSpawnTickCounter = self.sv.lootSpawnTickCounter + 1
		if self.sv.lootSpawnTickCounter % LootSpawnTickInterval == 0 then
			self:sv_spawnLoot()
		end
	end
end

function RewardLockerBase.sv_spawnLoot( self )
	if IsEmptyTable( self.sv.spawnTable ) then
		self.sv.isSpawningLoot = false
		self.harvestable:destroy()
		sm.harvestable.createHarvestable( ReplacementHarvestable, self.harvestable.worldPosition, self.harvestable.worldRotation )
		return
	end
	local amountLeft = self.sv.spawnTable[self.sv.spawnIndex].amountLeft
	local stackSize = math.random( MinimumStackSize, MaximumStackSize )
	if amountLeft < stackSize then
		stackSize = amountLeft
	end
    
	local uuid = sm.uuid.new( self.sv.spawnTable[self.sv.spawnIndex].strUid )
	local params = { lootUid = uuid, lootQuantity = stackSize or 1, epic = false }
	self.sv.spawnDirection = self.sv.spawnDirection:rotateZ( math.rad( RewardRotationSpeedPerSecond * 0.025 ) )
	local velocity = ( self.sv.spawnDirection * 2 ) + ( self.sv.upDirection + self.sv.upDirection * math.random() * 2 )
	
	sm.projectile.harvestableCustomProjectileAttack( params, projectile_loot, 0, self.harvestable.worldPosition + sm.vec3.new( 0, 0, 2 ), velocity, self.harvestable )
	self.sv.spawnTable[self.sv.spawnIndex].amountLeft = amountLeft - stackSize

	if self.sv.spawnTable[self.sv.spawnIndex].amountLeft <= 0 then
		table.remove( self.sv.spawnTable, self.sv.spawnIndex )
	end
	if not IsEmptyTable( self.sv.spawnTable ) then
		self.sv.spawnIndex = ModuloIndex( self.sv.spawnIndex + 1, #self.sv.spawnTable )
	end
end

function RewardLockerBase.server_onMelee( self, hitPos, attacker, damage, power, hitDirection )
	if attacker and type( attacker ) == "Player" then
		self:sv_onHit()
	end
end

function RewardLockerBase.sv_onHit( self )
	if self.sv.damageTickCooldown <= 0 and self.sv.saved.destroyed == false then
		self.sv.saved.health = self.sv.saved.health - 1
		self.sv.damageTickCooldown = DamageCooldownTickTime
		if self.sv.saved.health <= 0 then
			self.sv.saved.destroyed = true
			self.sv.isSpawningLoot = true
			local unlockTable = {}
			for index,itemTable in ipairs( RecipeUnlockList ) do
				for _,strUid in ipairs( itemTable ) do
					if not RecipeManager.Sv_IsUnlocked( strUid ) then
						unlockTable = RecipeUnlockList[index]
						break
					end
				end
				if not IsEmptyTable( unlockTable ) then
					break
				end
			end
			if IsEmptyTable( unlockTable ) then
				unlockTable = RecipeUnlockList[math.random( 1, #RecipeUnlockList )]
			end
			for index,strUid in ipairs( unlockTable ) do
				RecipeManager.Sv_UnlockRecipe( strUid )
				self.sv.spawnTable[index] = { strUid = strUid,  amountLeft = BlockRewardAmount[strUid] }
			end
		end
		self.storage:save( self.sv.saved )
		self.network:setClientData( self.sv.saved )
	end
end

function RewardLockerBase.client_onCreate( self )
	self.cl = {}
	self.cl.blockEffect = sm.effect.createEffect( "Minidungeon_rewardlocker - Mysteryblock", self.harvestable )
end

function RewardLockerBase.client_onDestroy( self )
	if self.cl.blockEffect then
		self.cl.blockEffect:stop()
	end
end

function RewardLockerBase.client_onMelee( self, hitPos, attacker, damage, power, hitDirection )
	if sm.exists( attacker) and type( attacker ) == "Player" then
		sm.effect.playHostedEffect( "Minidungeon_rewardlocker - Impact", self.harvestable )
	end
end

function RewardLockerBase.cl_updateSubmeshVisibility( self, health )
	local show0 = health == 5
	self.harvestable:setSubMeshVisible( "submesh0_m_glass", show0 )
	self.harvestable:setSubMeshVisible( "submesh0_m_lightcone", show0 )
	self.harvestable:setSubMeshVisible( "submesh0_m_uvmaterial_industrial", show0 )
	local show1 = health == 4
	self.harvestable:setSubMeshVisible( "submesh1_m_glass", show1 )
	self.harvestable:setSubMeshVisible( "submesh0_m_lightcone", show1 )
	self.harvestable:setSubMeshVisible( "submesh1_m_uvmaterial_industrial", show1 )
	local show2 = health == 3
	self.harvestable:setSubMeshVisible( "submesh2_m_glass", show2 )
	self.harvestable:setSubMeshVisible( "submesh0_m_lightcone", show2 )
	self.harvestable:setSubMeshVisible( "submesh2_m_uvmaterial_industrial", show2 )
	local show3 = health == 2
	self.harvestable:setSubMeshVisible( "submesh3_m_glass", show3 )
	self.harvestable:setSubMeshVisible( "submesh0_m_lightcone", show3 )
	self.harvestable:setSubMeshVisible( "submesh3_m_uvmaterial_industrial", show3 )
	local show4 = health == 1
	self.harvestable:setSubMeshVisible( "submesh4_m_glass", show4 )
	self.harvestable:setSubMeshVisible( "submesh0_m_lightcone", show4 )
	self.harvestable:setSubMeshVisible( "submesh4_m_uvmaterial_industrial", show4 )
	local show5 = health == 0
	self.harvestable:setSubMeshVisible( "submesh5_m_glass", show5 )
	--self.harvestable:setSubMeshVisible( "submesh0_m_lightcone", show5 )
	self.harvestable:setSubMeshVisible( "submesh5_m_uvmaterial_industrial", show5 )
end

function RewardLockerBase.cl_triggerBreakEffects( self, health )
	if health == 4 then
		sm.effect.playEffect( "Minidungeon_rewardlocker - Destruction_level1", self.harvestable.worldPosition )
	elseif health == 3 then
		sm.effect.playEffect( "Minidungeon_rewardlocker - Destruction_level2", self.harvestable.worldPosition )
	elseif health == 2 then
		sm.effect.playEffect( "Minidungeon_rewardlocker - Destruction_level3", self.harvestable.worldPosition )
	elseif health == 1 then
		sm.effect.playEffect( "Minidungeon_rewardlocker - Destruction_level4", self.harvestable.worldPosition )
	else
		if self.cl.blockEffect and self.cl.blockEffect:isPlaying() then
			self.cl.blockEffect:stop()
		end
		sm.effect.playEffect( "Minidungeon_rewardlocker - Destruction_level5", self.harvestable.worldPosition )
	end
end

function RewardLockerBase.client_onClientDataUpdate( self, data )
	self:cl_updateSubmeshVisibility( data.health )
	if not data.startup then
		self:cl_triggerBreakEffects( data.health )
	else
		if data.health > 0 and self.cl.blockEffect and not self.cl.blockEffect:isPlaying() then
			self.cl.blockEffect:start()
		end
	end
end
