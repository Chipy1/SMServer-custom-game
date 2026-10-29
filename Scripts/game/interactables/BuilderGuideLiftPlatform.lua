dofile("$SURVIVAL_DATA/Scripts/blueprint_util.lua")
dofile( "$SURVIVAL_DATA/Scripts/game/managers/QuestManager.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/quests/LiftPlatformBuilderQuest.lua" )

BuilderGuideLiftPlatform = class( nil )

local FinishedBuilderGuide = sm.uuid.new( "cc5f3b6e-d2de-45ed-bc26-d640bd1663ec" )
local PlatformEffect = "Builderguide Questplatform - Car Activate"
local PlatformEffectLoop = "Builderguide Questplatform - Car Loop"

-- Server

function BuilderGuideLiftPlatform.server_onCreate( self )
	self.sv = {}
	self.sv.storageKey = TileStorageManager.Sv_GetTileStorageKeyFromObject( self.interactable )
	self.sv.saved = self.storage:load()
	if self.sv.saved == nil then
		self.sv.saved = {}

		self.sv.saved.complete = false

		local tileData = TileStorageManager.Sv_GetValue( self.sv.storageKey, BUILDERGUIDE_PLATFORM_TABLE )
		tileData = SafeSetKVPs( tileData, { platform = self.interactable, questName = self.data.questName, speakerName = self.data.speakerName, dialog = self.data.dialog } )
		TileStorageManager.Sv_SetValue( self.sv.storageKey, BUILDERGUIDE_PLATFORM_TABLE, tileData )

		self.storage:save( self.sv.saved )
	end

	TileStorageManager.Sv_SetValueInSubTable( self.sv.storageKey, BUILDERGUIDE_PLATFORM_TABLE, "platformQuest", { path = self.data.filepath, questName = self.data.questName, bodyId = self.shape.body.id } )
end

function BuilderGuideLiftPlatform.server_onUnload( self )
	if self.sv.lift and sm.exists( self.sv.lift ) then
		self.sv.lift:destroy()
		self.sv.lift = nil
	end
end

function BuilderGuideLiftPlatform.server_onDestroy( self )
	if self.sv.lift and sm.exists( self.sv.lift ) then
		self.sv.lift:destroy()
		self.sv.lift = nil
	end
end

function BuilderGuideLiftPlatform.server_onFixedUpdate( self )

	if self.sv.saved.complete then
		return
	end

	if self.sv.lift and sm.exists( self.sv.lift ) then
		local liftLevel = self.sv.lift:getLevel()
		if self.sv.saved.liftLevel ~= liftLevel then
			self.sv.saved.liftLevel = liftLevel
			self.storage:save( self.sv.saved )
		end
	end

	if QuestManager.Sv_IsQuestActive( self.data.questName ) and not self.sv.saved.complete then
		local stage = QuestManager.Sv_GetQuestStage( self.data.questName )
		if stage ~= self.sv.stage then
			self.sv.stage = stage
			if stage == LiftPlatformBuilderQuest.Stages.place_lift then
				
				local body = sm.body.createBody( self.shape.worldPosition - sm.vec3.new( 0, 0, 5 ), sm.quat.identity(), false )
				if body then
					self.sv.saved.buildShape = body:createPart( sm.uuid.new( self.data.builderGuideShape ), sm.vec3.zero(), sm.vec3.new( 0, -1, 0 ), sm.vec3.new( 1, 0, 0 ) )
					self.sv.saved.buildShape.interactable:setParams( { questName = self.data.questName, filepath = self.data.filepath } )
					self.sv.saved.buildShape.body:setConvertibleToDynamic( false )
					self.storage:save( self.sv.saved )
				else
					print( "Failed to create builderguide shape!" )
				end
			end
			if stage == LiftPlatformBuilderQuest.Stages.build_thing then
				if self.sv.lift == nil then
					self:sv_spawnLift()
				end
			end
			self.network:setClientData( { stage = stage, buildShape = self.sv.saved.buildShape } )
		end
	elseif QuestManager.Sv_IsQuestComplete( self.data.questName ) then
		self.sv.saved.buildShape.body:setConvertibleToDynamic( true )
		self.sv.saved.buildShape:replaceShape( FinishedBuilderGuide )

		if not self.sv.saved.complete then
			self.sv.saved.complete = true
			self.storage:save( self.sv.saved )
			self.network:setClientData( { completed = true } )
		end
		if self.sv.lift and sm.exists( self.sv.lift ) then
			self.sv.lift:destroy()
			self.sv.lift = nil
		end
	end
end

-- Client
function BuilderGuideLiftPlatform.client_onClientDataUpdate( self, data )
	if data.buildShape then
		if not self.cl.buildShape then
			self.cl.buildShape = data.buildShape
		end
	end

	local liftPos = ( self.shape.worldPosition + sm.vec3.new( 0,0,0.25 ) ) * 4
	liftPos = sm.vec3.new( math.floor( liftPos.x + 0.5 ), math.floor( liftPos.y + 0.5 ), math.floor( liftPos.z + 0.5 ) )

	if data.stage == LiftPlatformBuilderQuest.Stages.place_lift then
		
		self.interactable:setClientPublicData( { liftPlacement = liftPos } )
		if not self.cl.liftIndicator then
			self.cl.liftIndicator = sm.effect.createEffect( "PlaceLift", self.shape )
			self.cl.liftIndicator:setOffsetPosition( sm.vec3.new( 0, 0.275, 0 ) )
		end
		self.cl.liftIndicator:start()
	else
		if data.completed then
			self.interactable:setClientPublicData( {} )
		else
			self.interactable:setClientPublicData( { liftPlacement = liftPos } )
		end
		if self.cl.liftIndicator and sm.exists( self.cl.liftIndicator ) then
			self.cl.liftIndicator:destroy()
			self.cl.liftIndicator = nil
		end
	end
	self.cl.stage = data.stage
end

function BuilderGuideLiftPlatform.client_onCreate( self )
	self.cl = {}

	self.cl.backgroundEffect = sm.effect.createEffect( PlatformEffectLoop, self.interactable )
end

function BuilderGuideLiftPlatform.client_onDestroy( self )
	self.cl.backgroundEffect:destroy()
end

function BuilderGuideLiftPlatform.cl_onLiftPlacement( self )
	self.network:sendToServer( "sv_n_requestPlaceLift" )
end

function BuilderGuideLiftPlatform.sv_n_requestPlaceLift( self )
	if self.sv.lift == nil then
		self:sv_spawnLift()
		QuestManager.Sv_SendEvent( "event."..self.data.questName..".place_lift" )
	end
end

function BuilderGuideLiftPlatform.sv_spawnLift( self )
	local liftPos = ( self.shape.worldPosition + sm.vec3.new( 0,0,0.25 ) ) * 4
	liftPos = sm.vec3.new( math.floor( liftPos.x + 0.5 ), math.floor( liftPos.y + 0.5 ), math.floor( liftPos.z + 0.5 ) )

	assert( self.sv.saved.buildShape:getBody(), "No build shape" )

	local liftRotationIndex = self.data and self.data.liftRotationIndex or 0
	self.sv.lift = sm.lift.createNonPlayerLift( self.shape.body:getWorld(), liftPos, self.sv.saved.buildShape:getBody(), self.sv.saved.liftLevel or 0, liftRotationIndex or 0 )
end

function BuilderGuideLiftPlatform.client_onFixedUpdate( self )
	if self.cl.stage == LiftPlatformBuilderQuest.Stages.place_lift then
		if self.cl.buildShape and sm.exists( self.cl.buildShape ) then
			if self.cl.liftIndicator and sm.exists( self.cl.liftIndicator ) and self.cl.liftIndicator:isPlaying() then
				local indicatorPos = (self.shape.worldPosition + sm.vec3.new( 0,0,0.25 )) * 4
				indicatorPos = sm.vec3.new( math.floor( indicatorPos.x + 0.5 ), math.floor( indicatorPos.y + 0.5 ), math.floor( indicatorPos.z + 0.5 ) )
				if sm.tool.checkLiftCollision( { self.cl.buildShape:getBody() } , indicatorPos, 0 ) then
					local placeValid = false
					local _, raycastResult = sm.localPlayer.getLatestRaycast()
					local player = sm.localPlayer.getPlayer()
					if raycastResult and raycastResult.valid and player and player:getCurrentToolUuid() == tool_lift then
						local lookPos = raycastResult.pointWorld * 4
						lookPos = sm.vec3.new( math.floor( lookPos.x + 0.5 ), math.floor( lookPos.y + 0.5 ), math.floor( lookPos.z + 0.5 ) )
						if lookPos == indicatorPos then
							placeValid = true
						end
					end

					if placeValid then
						self.cl.liftIndicator:setParameter( "visualizationColor", "Lift Valid" )
					else
						self.cl.liftIndicator:setParameter( "visualizationColor", "Builder Guide Build" )
					end
				else
					self.cl.liftIndicator:setParameter( "visualizationColor", "Lift Invalid" )
				end
			end
		end
	end

	if QuestManager.Cl_IsQuestActive( self.data.questName ) then
		local quest = QuestManager.Cl_GetActiveQuest( self.data.questName )
		quest = sm.exists( quest ) and quest or nil
		if quest and quest.clientPublicData then
			if quest.clientPublicData.guideActive then
				if not self.cl.backgroundEffect:isPlaying() then
					sm.effect.playHostedEffect( PlatformEffect, self.interactable )
					self.cl.backgroundEffect:start()
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
	end
end
