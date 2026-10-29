dofile("$SURVIVAL_DATA/Scripts/blueprint_util.lua")
dofile( "$SURVIVAL_DATA/Scripts/game/managers/QuestManager.lua" )

BuilderGuidePlatform = class( nil )

BuilderGuidePlatform.DefaultStageCompleteEffect = "Builderguide - Stagecomplete"
BuilderGuidePlatform.DefaultPlatformLoopEffect = "BuilderguideQuest - Loop"
BuilderGuidePlatform.DefaultPlatformStageCompleteEffect = "BuilderguideQuest - StageComplete"
BuilderGuidePlatform.DefaultPlatformBuildCompleteEffect = "BuilderguideQuest - BuildComplete"
BuilderGuidePlatform.DefaultPlatformActiveEffect = "BuilderguideQuest - Active"

-- Server

function BuilderGuidePlatform.server_onCreate( self )
	self.sv = {}
	self.sv.rebuildTick = sm.game.getCurrentTick()
	self.sv.storageKey = TileStorageManager.Sv_GetTileStorageKeyFromObject( self.interactable )
	self.sv.saved = self.storage:load()
	if self.sv.saved == nil then
		self.sv.saved = {}

		self.sv.saved.complete = self.params and self.params.complete or false

		local tileData = TileStorageManager.Sv_GetValue( self.sv.storageKey, BUILDERGUIDE_PLATFORM_TABLE )
		tileData = SafeSetKVPs( tileData, { path = self.data.filepath, platform = self.interactable, questName = self.data.questName, speakerName = self.data.speakerName, dialog = self.data.dialog } )
		TileStorageManager.Sv_SetValue( self.sv.storageKey, BUILDERGUIDE_PLATFORM_TABLE, tileData )
	end
	self.sv.pimpUid = sm.uuid.new( self.data.pimpHarvestable or "" )

	self.storage:save( self.sv.saved )

	self:sv_saveToTile()
	self.sv.lift = sm.lift.createVirtualLift( self.shape.body:getWorld(),self.shape.body )
end

function BuilderGuidePlatform.sv_saveToTile( self )
	TileStorageManager.Sv_SetValueInSubTable( self.sv.storageKey, BUILDERGUIDE_PLATFORM_TABLE, "platformQuest", { path = self.data.filepath, questName = self.data.questName, bodyId = self.shape.body.id } )
end

function BuilderGuidePlatform.sv_e_onQuestEvent( self, data )
	if data.event == "NEXT" then -- this event means the platform should be replaced with the next one.

		--notify the panel to fetch the contents again when it is written.
		local infoPanel = TileStorageManager.Sv_GetValueInSubTable( self.sv.storageKey, BUILDERGUIDE_PLATFORM_TABLE, "infoPanel" )
		if infoPanel then
			sm.event.sendToHarvestable( infoPanel, "sv_e_storageUpdated" )
		end

		local tileData = TileStorageManager.Sv_GetValue( self.sv.storageKey, BUILDERGUIDE_PLATFORM_TABLE )
		if tileData and tileData.pimpHarvestable then
			tileData.pimpHarvestable:destroy()
		end

		-- reset all platform information, prepare to write new information with the new platform
		TileStorageManager.Sv_SetValue( self.sv.storageKey, BUILDERGUIDE_PLATFORM_TABLE, nil )

		-- destroy this platform and replace it with the next one
		self:sv_replace( data.nextBuilderGuidePlatform, false )
	end
end

function BuilderGuidePlatform.server_onUnload( self )
	if self.sv.lift and sm.exists( self.sv.lift ) then
		self.sv.lift:destroy()
		self.sv.lift = nil
	end
end

function BuilderGuidePlatform.server_onDestroy( self )
	if self.sv.lift and sm.exists( self.sv.lift ) then
		self.sv.lift:destroy()
		self.sv.lift = nil
	end
end

function BuilderGuidePlatform.server_onFixedUpdate( self )

	-- disable all function if guide is already completed or quest has not started
	if QuestManager.Sv_IsQuestActive( self.data.questName ) and not self.sv.saved.complete then
		local bodies = sm.body.getCreationBodies( self.shape:getBody() )
		if #bodies ~= self.sv.lastBodyCount or self.shape:getBody():getId() ~= self.sv.lastBodyId then
			self:sv_checkBuilderGuide()
			self.sv.lastBodyCount = #bodies
		else
			for _, body in ipairs( bodies ) do
				if body:hasChanged( self.sv.rebuildTick ) then
					self:sv_checkBuilderGuide()
					self.sv.lastBodyCount = #bodies
					break
				end
			end
		end
	end
end

function BuilderGuidePlatform.sv_replace( self, blueprint, complete )
	if self.data.filepath then
		local world = self.shape.body:getWorld()
		local position = self.shape:getWorldPosition()
		local rotation = self.shape:getWorldRotation()
		local halfExtents = self.shape:getBoundingBox() / 2
		local rotatedBounds = rotation * halfExtents
		local importCreation = sm.creation.importFromFile( world, blueprint, position - rotatedBounds, rotation )
		local myUid = self.shape.uuid
		for _, body in ipairs( importCreation ) do
			for _,shape in ipairs( body:getShapes() ) do
				if shape.uuid == myUid then
					local interactable = shape:getInteractable()
					interactable:setParams( { complete = complete } )
				end
			end
			if complete then
				body:setErasable( false )
				body:setBuildable( false )
				body:setDestructable( false )
			end
		end
		self.shape:getBody():destroyCreation()
	end

end

function BuilderGuidePlatform.sv_checkBuilderGuide( self )
	self.sv.lastBodyId = self.shape:getBody():getId()

	if self.shape:getBody():getId() ~= self.sv.lastBodyId and self.sv.builderGuide then
		self.sv.builderGuide:destroy()
		self.sv.builderGuide = nil
	end

	if self.sv.builderGuide == nil then
		local ignoreBlockUuid = self.data.ignoreBlockUuid ~= nil and self.data.ignoreBlockUuid ~= false
		self.sv.builderGuide = sm.builderGuide.createBuilderGuide( self.data.filepath, self.shape, ignoreBlockUuid, false, false )
	end

	self.sv.builderGuide:update()
	self.sv.rebuildTick = sm.game.getCurrentTick()

	if self.sv.builderGuide:isComplete() then
		sm.effect.playEffect( self.data.platformBuildCompleteEffect or BuilderGuidePlatform.DefaultPlatformBuildCompleteEffect, self.shape.worldPosition, nil, self.shape.worldRotation )
		self:sv_replace( self.data.completeBlueprint, true )
		self:sv_spawnPimpMesh()
		QuestManager.Sv_SendEvent( "event." .. self.data.questName .. ".update", { isComplete = true } )
	else
		self.network:setClientData( { active = true } ) -- there is an incomplete builder guide on the platform, start client visualization
	end
end

function BuilderGuidePlatform.sv_spawnPimpMesh( self )
	if self.sv.saved.pimpMesh == nil then
		if not sm.uuid.isNil( self.sv.pimpUid ) then
			local pos = self.shape:getWorldPosition()
			local rot = self.shape:getWorldRotation()
			local rot_x_90 = sm.quat.fromEuler( sm.vec3.new( 90,0,0 ) )
			self.sv.saved.pimpMesh = sm.harvestable.createHarvestable( self.sv.pimpUid, pos, rot * rot_x_90 )
			self.sv.saved.pimpMesh:setParams( true )

			local tileData = TileStorageManager.Sv_GetValue( self.sv.storageKey, BUILDERGUIDE_PLATFORM_TABLE )
			tileData = SafeSetKVPs( tileData, { pimpHarvestable = self.sv.saved.pimpMesh } )
			TileStorageManager.Sv_SetValue( self.sv.storageKey, BUILDERGUIDE_PLATFORM_TABLE, tileData )

			self.storage:save( self.sv.saved )
		end
	end
end













-- Client

function BuilderGuidePlatform.client_onClientDataUpdate( self, data )
	self.cl.active = data.active
end

function BuilderGuidePlatform.cl_rebuildVisualization( self )

	if self.shape:getBody():getId() ~= self.cl.lastBodyId and self.cl.builderGuideVis then
		self.cl.builderGuideVis:destroy()
		self.cl.builderGuideVis = nil
	end

	if self.cl.builderGuideVis then
		self.cl.builderGuideVis:updateBuilderGuide()
	else
		self.cl.lastBodyId = self.shape:getBody():getId()
		local ignoreBlockUuid = self.data.ignoreBlockUuid ~= nil and self.data.ignoreBlockUuid ~= false
		self.cl.builderGuideVis = sm.visualization.createBuilderGuide( self.data.filepath, self.shape, ignoreBlockUuid,
			self.data.stageCompleteEffect or BuilderGuidePlatform.DefaultStageCompleteEffect,
			self.data.platformStageCompleteEffect or BuilderGuidePlatform.DefaultPlatformStageCompleteEffect )
	end

	self.cl.rebuildTick = sm.game.getCurrentTick()
end

function BuilderGuidePlatform.client_onCreate( self )
	self.cl = {}
	self.cl.rebuildTick = sm.game.getCurrentTick()

	self.cl.active = false -- don't show the visualization until server confirms that we should

	self.cl.backgroundEffect = sm.effect.createEffect( self.data.platformLoopEffect or BuilderGuidePlatform.DefaultPlatformLoopEffect, self.interactable )
end

function BuilderGuidePlatform.client_onDestroy( self )
	if self.cl.builderGuideVis then
		self.cl.builderGuideVis:destroy()
		self.cl.builderGuideVis = nil
	end
	self.cl.backgroundEffect:destroy()
end

function BuilderGuidePlatform.client_onFixedUpdate( self )
	if QuestManager.Cl_IsQuestActive( self.data.questName ) and self.cl.active then
		local quest = QuestManager.Cl_GetActiveQuest( self.data.questName )
		quest = sm.exists( quest ) and quest or nil
		if quest and quest.clientPublicData then
			if quest.clientPublicData.guideActive then
				if not self.cl.backgroundEffect:isPlaying() then
					sm.effect.playHostedEffect( self.data.platformActiveEffect or BuilderGuidePlatform.DefaultPlatformActiveEffect, self.interactable )
					self.cl.backgroundEffect:start()
				end

				local bodies = sm.body.getCreationBodies( self.shape:getBody() )
		
				if #bodies ~= self.cl.lastBodyCount or self.shape:getBody():getId() ~= self.cl.lastBodyId then
					self:cl_rebuildVisualization()
					self.cl.lastBodyCount = #bodies
				else
					for _, body in ipairs( bodies ) do
						if body:hasChanged( self.cl.rebuildTick ) then
								self:cl_rebuildVisualization()
								self.cl.lastBodyCount = #bodies
							break
						end
					end
				end
			else
				if self.cl.backgroundEffect:isPlaying() then
					self.cl.backgroundEffect:stop()
				end
			end
		end
	else
		if self.cl.backgroundEffect:isPlaying() then
			self.cl.backgroundEffect:stop()
		end
		if self.cl.builderGuideVis then
			self.cl.builderGuideVis:destroy()
			self.cl.builderGuideVis = nil
		end
	end
end











