dofile( "$SURVIVAL_DATA/Scripts/game/managers/QuestManager.lua" )

WarehouseConsole = class()

local DamageCooldownTickTime = 40 * 0.125

function WarehouseConsole.server_onCreate( self )
	self.saved = self.storage:load()
	if self.saved == nil then
		self.saved = {}
	end
	if self.params then
		self.saved.isQuestConsole = self.params.isQuestConsole
	end
	self.storage:save( self.saved )

	self.sv = {}
	self.sv.damageCooldownTicks = 0
	self.sv.damageStage = 0
	if self.params then
		self.sv.damageStage = self.params.damageStage
		self.network:setClientData( { damageStage = self.params.damageStage, init = true } )
	else
		if sm.exists( self.shape ) then
			self.shape:destroyShape()
		end
	end
end

function WarehouseConsole.server_onFixedUpdate( self, dt )
	if not ( self.params and self.params.consoleBase and sm.exists( self.params.consoleBase ) ) then
		if sm.exists( self.shape ) then
			self.shape:destroyShape()
			return
		end
	end

	self.sv.damageCooldownTicks = math.max( self.sv.damageCooldownTicks - 1, 0 )
end

function WarehouseConsole.server_onMelee( self, hitPos, attacker, damage, power, hitDirection )
	if sm.exists( attacker) and type( attacker ) == "Player" then
		self:sv_onHit()
	end
end

function WarehouseConsole.sv_onHit( self )
	local canHit = not self.saved.isQuestConsole
	if self.saved.isQuestConsole then
		local quest = QuestManager.Sv_GetQuest( "quest_warehouse_destruction" )
		if sm.exists( quest ) and quest.publicData then
			canHit = quest.publicData.canDestroyConsole
		end
	end
	if canHit and self.sv.damageCooldownTicks <= 0 then
		self.sv.damageStage = math.min( self.sv.damageStage + 1, 4 )

		QuestManager.Sv_SendEvent( QuestEvent.QuestConsoleHit, { hits = self.sv.damageStage } )
		if self.sv.damageStage == 4 then
			sm.event.sendToHarvestable( self.params.consoleBase, "sv_e_destructionCountDown" )
		end

		self.sv.damageCooldownTicks = DamageCooldownTickTime
		self.network:setClientData( { damageStage = self.sv.damageStage } )
	end
end

function WarehouseConsole.client_onCreate( self )
	self.cl = {}
	self.cl.damageStage = 0
	self:cl_updateSubmeshVisibility( self.cl.damageStage )
	self.cl.idleSound = sm.effect.createEffect( "Controlconsole - IdleSound", self.interactable )
	self.cl.idleSound:start()
end

function WarehouseConsole.client_onDestroy( self )
	self.cl.idleSound:stop()
	self.cl.idleSound:destroy()
	self.cl.idleSound = nil
end

function WarehouseConsole.client_onMelee( self, hitPos, attacker, damage, power, hitDirection )
	if sm.exists( attacker) and type( attacker ) == "Player" then
		sm.effect.playHostedEffect( "Controlconsole - TakingDamage", self.shape.interactable )
	end
end

function WarehouseConsole.cl_updateSubmeshVisibility( self, damageStage )
	local show0 = damageStage == 0
	self.interactable:setSubMeshVisible( "submesh0_display", show0 )
	self.interactable:setSubMeshVisible( "submesh0_display02", show0 )
	self.interactable:setSubMeshVisible( "submesh0_display03", show0 )
	self.interactable:setSubMeshVisible( "submesh0_t_trimsheet_uvmaterial_industrial", show0 )
	local show1 = damageStage == 1
	self.interactable:setSubMeshVisible( "submesh1_display", show1 )
	self.interactable:setSubMeshVisible( "submesh1_display02", show1 )
	self.interactable:setSubMeshVisible( "submesh1_display03", show1 )
	self.interactable:setSubMeshVisible( "submesh1_t_trimsheet_uvmaterial_industrial", show1 )
	local show2 = damageStage == 2
	self.interactable:setSubMeshVisible( "submesh2_display", show2 )
	self.interactable:setSubMeshVisible( "submesh2_display02", show2 )
	self.interactable:setSubMeshVisible( "submesh2_display03", show2 )
	self.interactable:setSubMeshVisible( "submesh2_t_trimsheet_uvmaterial_industrial", show2 )
	local show3 = damageStage == 3
	self.interactable:setSubMeshVisible( "submesh3_display", show3 )
	self.interactable:setSubMeshVisible( "submesh3_display03", show3 )
	self.interactable:setSubMeshVisible( "submesh3_display04", show3 )
	self.interactable:setSubMeshVisible( "submesh3_t_trimsheet_uvmaterial_industrial", show3 )
	local show4 = damageStage == 4
	self.interactable:setSubMeshVisible( "submesh4_display", show4 )
	self.interactable:setSubMeshVisible( "submesh4_display04", show4 )
	self.interactable:setSubMeshVisible( "submesh4_t_trimsheet_uvmaterial_industrial", show4 )
end

function WarehouseConsole.client_onClientDataUpdate( self, data, channel )
	if self.cl.damageStage == nil then
		self:cl_updateSubmeshVisibility( data.damageStage )
	else
		if data.damageStage > self.cl.damageStage then
			self:cl_updateSubmeshVisibility( data.damageStage )
			if self.cl.damageStage < 1 and data.damageStage >= 1 then
				if not data.init then
					sm.effect.playEffect( "Controlconsole - DamageSound1", self.shape.worldPosition )
				end
			end
			if self.cl.damageStage < 2 and data.damageStage >= 2 then
				if not data.init then
					sm.effect.playEffect( "Controlconsole - DamageSound2", self.shape.worldPosition )
				end
				sm.effect.playEffect( "Controlconsole - DestroyMemorystickLeft", self.shape.worldPosition, nil, self.shape.worldRotation )
			end
			if self.cl.damageStage < 3 and data.damageStage >= 3 then
				if not data.init then
					sm.effect.playEffect( "Controlconsole - DamageSound3", self.shape.worldPosition )
				end
				sm.effect.playEffect( "Controlconsole - DestroyMemorystickRight", self.shape.worldPosition, nil, self.shape.worldRotation )
			end
			if self.cl.damageStage < 4 and data.damageStage >= 4 then
				if not data.init then
					sm.effect.playEffect( "Controlconsole - DamageSound4", self.shape.worldPosition )
				end
				sm.effect.playEffect( "Controlconsole - DestroyKeyboard", self.shape.worldPosition, nil, self.shape.worldRotation )
				sm.effect.playEffect( "Controlconsole - Buildup", self.shape.worldPosition, nil, self.shape.worldRotation )

				g_hudManagerClient:Cl_WarehouseTransition()
			end
		end
	end

	self.cl.damageStage = data.damageStage
	self.cl.idleSound:setParameter( "damage", self.cl.damageStage * 0.2 )
end
