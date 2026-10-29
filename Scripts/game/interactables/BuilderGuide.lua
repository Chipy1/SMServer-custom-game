dofile("$SURVIVAL_DATA/Scripts/blueprint_util.lua")
dofile( "$SURVIVAL_DATA/Scripts/game/managers/TutorialManager.lua" )

BuilderGuide = class( nil )

-- Server

function BuilderGuide.server_onCreate( self )
	self.sv = {}
	self.sv.rebuildTick = sm.game.getCurrentTick()
	self.sv.saved = self.storage:load()
	if self.sv.saved == nil then
		self.sv.saved = {}
		self.sv.saved.completed = false

		if self.params then
			self.sv.saved.questName = self.params.questName
			self.sv.saved.filepath = self.params.filepath
		end

		self.storage:save( self.sv.saved )
	end
	self.network:setClientData( { isComplete = self.sv.saved.completed, filepath = self.sv.saved.filepath } )

	self.sv.currentPos = self.shape.worldPosition
end

function BuilderGuide.server_onUnload( self )
	self.sv.unloaded = true
end

function BuilderGuide.server_onFixedUpdate( self )
	local bodies = sm.body.getCreationBodies( self.shape:getBody() )
	self.sv.currentPos = self.shape.worldPosition
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

function BuilderGuide.sv_checkBuilderGuide( self )
	if self.sv.saved.completed or not self.sv.saved.filepath then
		return
	end
	self.sv.lastBodyId = self.shape:getBody():getId()
	if self.shape:getBody():getId() ~= self.sv.lastBodyId and self.sv.builderGuide then
		self.sv.builderGuide:destroy()
		self.sv.builderGuide = nil
	end

	if self.sv.builderGuide == nil then
		local ignoreBlockUuid = self.data and self.data.ignoreBlockUuid == true
		self.sv.builderGuide = sm.builderGuide.createBuilderGuide( self.sv.saved.filepath, self.shape, ignoreBlockUuid )
	end

	self.sv.builderGuide:update()
	self.sv.rebuildTick = sm.game.getCurrentTick()

	local data = {
		isComplete = self.sv.builderGuide:isComplete(),
		currentStageIndex = self.sv.builderGuide:getCurrentStageIndex(),
		filepath = self.sv.saved.filepath
	}
	self.network:setClientData( data )

	data.interactable = self.interactable
	data.stageInfo = self.sv.builderGuide:getStageInfo()
	QuestManager.Sv_SendEvent( "event.".. self.sv.saved.questName ..".update", data )
	if self.sv.builderGuide:isComplete() then
		self.sv.builderGuide:destroy()
		self.sv.saved.completed = true
		self.storage:save( self.sv.saved )
	end
end

-- Client

function BuilderGuide.client_onClientDataUpdate( self, data )
	if data.isComplete then
		if not self.cl.serverWasComplete then
			self.cl.serverWasComplete = true
		end
	else
		local stageCompleted = data.currentStageIndex
		if self.cl.serverLastStage ~= stageCompleted or self.cl.serverWasComplete then
			self.cl.serverLastStage = stageCompleted
		end

		self.cl.serverWasComplete = false
	end

	if not self.cl.filepath then
		self.cl.filepath = data.filepath
		self:cl_rebuildVisualization()
	end
end

function BuilderGuide.cl_rebuildVisualization( self )
	if self.cl.filepath == nil then
		return
	end

	if self.cl.serverWasComplete then
		return
	end
	if self.shape:getBody():getId() ~= self.cl.lastBodyId and self.cl.builderGuideVis then
		self.cl.builderGuideVis:destroy()
		self.cl.builderGuideVis = nil
	end

	if self.cl.builderGuideVis then
		self.cl.builderGuideVis:updateBuilderGuide()
	else
		self.cl.lastBodyId = self.shape:getBody():getId()
		local ignoreBlockUuid = self.data and self.data.ignoreBlockUuid == true
		self.cl.builderGuideVis = sm.visualization.createBuilderGuide( self.cl.filepath, self.shape, ignoreBlockUuid, "Builderguide - Stagecomplete" )
	end

	self.cl.rebuildTick = sm.game.getCurrentTick()
end

function BuilderGuide.client_onCreate( self )
	self.cl = {}
	self.cl.serverWasComplete = false
	self.cl.serverLastStage = 0
	self.cl.rebuildTick = sm.game.getCurrentTick()
	self:cl_rebuildVisualization()
	self.cl.markerBumped = false
	self.cl.backgroundEffect = sm.effect.createEffect( "Builderguide - Background", self.interactable )

	self.cl.markerBumped = QuestEntityManager.Cl_BumpHostedQuestMarker( "quest_build_car.marker" )
end

function BuilderGuide.client_onRefresh( self )
	self:cl_rebuildVisualization()
end

function BuilderGuide.client_onDestroy( self )
	if self.cl.builderGuideVis then
		self.cl.builderGuideVis:destroy()
		self.cl.builderGuideVis = nil
	end
	self.cl.backgroundEffect:destroy()
	WorldMarkerManager.Cl_DetachMarker( "quest_build_car.marker" )
end

function BuilderGuide.client_onFixedUpdate( self )
	if not self.cl.markerBumped then
		self.cl.markerBumped = QuestEntityManager.Cl_BumpHostedQuestMarker( "quest_build_car.marker" )
	end
	if self.shape.body:isOnLift() and not self.shape.body:isOnVirtualLift() then
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

		if self.cl.serverWasComplete then
			if self.cl.backgroundEffect:isPlaying() then
				sm.effect.playHostedEffect( "Builderguide - Buildcomplete", self.interactable )
				self.cl.backgroundEffect:stop()
			end
		else
			if not self.cl.backgroundEffect:isPlaying() then
				sm.effect.playHostedEffect( "Builderguide - Active", self.interactable )
				self.cl.backgroundEffect:start()
			end
		end
	else
		if self.cl.backgroundEffect:isPlaying() then
			sm.effect.playHostedEffect( "Builderguide - Deactivate", self.interactable )
			self.cl.backgroundEffect:stop()
		end
		if self.cl.builderGuideVis then
			self.cl.builderGuideVis:destroy()
			self.cl.builderGuideVis = nil
		end
	end
end

function BuilderGuide.client_canInteract( self, character )
	return false
end