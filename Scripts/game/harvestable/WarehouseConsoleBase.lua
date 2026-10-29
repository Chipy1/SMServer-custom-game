dofile( "$SURVIVAL_DATA/Scripts/game/managers/WarehouseManager.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/managers/QuestManager.lua" )

WarehouseConsoleBase = class()

local ConsoleShapeUuid = sm.uuid.new( "6f8d188f-b14a-4b57-aa30-c4f81df1b271" )
local DestroyedConsoleUuid = sm.uuid.new( "f811de38-5b13-49a8-8d33-ee4e05e7eb52" )
local ShapePlacementOffset = sm.vec3.new( 0.0, 1.0, 0.0 )

local DestructionBuildupTickTime = 40 * 5.0

local ProjectileChaos = sm.uuid.new( "fa80ba7f-b60c-4929-85ba-402af0b1cbd3" )

function WarehouseConsoleBase.server_onCreate( self )
	self.sv = {}
	self.sv.saved = self.storage:load() or {}
	if self.params then
		self.sv.saved.isQuestConsole = self.params.isQuestConsole
	end
	self.storage:save( self.sv.saved )
end

function WarehouseConsoleBase.server_onFixedUpdate( self, dt )
	if self.sv.consoleShape == nil or not sm.exists( self.sv.consoleShape ) then
		local spawnPosition = self.harvestable.worldPosition - self.harvestable.worldRotation * sm.item.getShapeOffset( ConsoleShapeUuid ) + self.harvestable.worldRotation * ShapePlacementOffset
		self.sv.consoleShape = sm.shape.createPart( ConsoleShapeUuid, spawnPosition, self.harvestable.worldRotation, false, true )
		self.sv.consoleShape.interactable:setParams( { isQuestConsole = self.sv.saved.isQuestConsole, consoleBase = self.harvestable, damageStage = self.sv.saved.destructionCountdown and 4 or 0 } )
	end

	if self.sv.saved.destructionCountdown and self.sv.saved.destructionCountdown > 0 then
		self.sv.saved.destructionCountdown = self.sv.saved.destructionCountdown - 1
		if self.sv.saved.destructionCountdown <= 0 then
			sm.effect.playEffect( "Controlconsole - DestroyExplosion", self.sv.consoleShape.worldPosition, nil, self.sv.consoleShape.worldRotation )
			sm.effect.playEffect( "Controlconsole - DestroyMainconsole", self.sv.consoleShape.worldPosition, nil, self.sv.consoleShape.worldRotation )
			sm.effect.playEffect( "Controlconsole - DestroySidescreenRight", self.sv.consoleShape.worldPosition, nil, self.sv.consoleShape.worldRotation )
			sm.effect.playEffect( "Controlconsole - DestroySidescreenLeft", self.sv.consoleShape.worldPosition, nil, self.sv.consoleShape.worldRotation )
			if sm.exists( self.sv.consoleShape ) then
				self.sv.consoleShape:destroyShape( 0 )
			end
			self:destroy()
		end
	end
end

function WarehouseConsoleBase.destroy( self )
	local world = self.harvestable:getWorld()
	local warehouse = WarehouseManager.Sv_GetWarehouseFromWorld( world )
	if warehouse then
		WarehouseManager.Sv_ConsoleDestroyed( warehouse.index )
		if not self.sv.saved.isQuestConsole then -- Quest warehouse begins countdown from the quest
			WarehouseManager.Sv_BeginCountdown( warehouse.index )
		end

		local projectileNodes = sm.cell.getNodesByTag( 0, 0, "PROJECTILE_SPAWNER" )
		sm.scriptableObject.createScriptableObject( ProjectileChaos, { projectileNodes = projectileNodes }, world )

		if self.sv.saved.isQuestConsole then
			QuestManager.Sv_SendEvent( QuestEvent.QuestConsoleDestroyed, { warehouseIndex = warehouse.index } )
		end
	end
	sm.harvestable.createHarvestable( DestroyedConsoleUuid, self.harvestable.worldPosition, self.harvestable.worldRotation )

	self.harvestable:destroy()
end

function WarehouseConsoleBase.sv_e_destructionCountDown( self )
	if self.sv.saved.destructionCountdown == nil then
		self.sv.saved.destructionCountdown = DestructionBuildupTickTime
		self.storage:save( self.sv.saved )
	end
end
