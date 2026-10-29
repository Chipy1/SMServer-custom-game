dofile( "$SURVIVAL_DATA/Scripts/game/util/Timer.lua" )
dofile( "$SURVIVAL_DATA/Scripts/util.lua" )

AmbienceManager = class( nil )

local CombatMusicCooldownTicks = 40 * 10 -- 5 seconds

function AmbienceManager.Cl_OnCellLoaded( world, x, y )
    if g_ambienceManager then
        g_ambienceManager:client_onCellLoaded( world, x, y )
    end
end

function AmbienceManager.client_onCellLoaded( self, world, x, y )
	local nodes = sm.cell.getNodesByTag( x, y, "AMBIENCE_OVERRIDE", world )
	local cellKey = CellKey( x, y )

	self.areaTriggers[world.id] = self.areaTriggers[world.id] or {}
	for _,node in ipairs( nodes ) do
		local trigger = self:cl_createAreaTrigger( node )
		self.areaTriggers[world.id][cellKey] = self.areaTriggers[world.id][cellKey] or {}
		self.areaTriggers[world.id][cellKey][#self.areaTriggers[world.id][cellKey] + 1] = trigger
		self.effectNames[trigger.id] = node.params.effect.name
		self.toggleFlagNames[trigger.id] = node.params.ts_flag
		self.exitEffectNames[trigger.id] = node.params.exit_effect
	end

	local paramNodes = sm.cell.getNodesByTag( x, y, "GLOBAL_AUDIO_PARAMETER", world )
	self.audioParamTriggers[world.id] = self.audioParamTriggers[world.id] or {}
	for _,node in ipairs( paramNodes ) do
		local trigger = self:cl_createAreaTrigger( node )
		self.audioParamTriggers[world.id][cellKey] = self.audioParamTriggers[world.id][cellKey] or {}
		self.audioParamTriggers[world.id][cellKey][#self.audioParamTriggers[world.id][cellKey] + 1] = trigger
		self.audioParamData[trigger.id] = { parameterName = node.params.parameterName, value = node.params.value }
	end
end

function AmbienceManager.cl_createAreaTrigger( self, node )
    local areaTrigger = sm.areaTrigger.createBox( node.scale / 2, node.position, node.rotation, sm.areaTrigger.filter.character )
    areaTrigger:bindOnEnter( "cl_t_onEnter", self )
	areaTrigger:bindOnExit( "cl_t_onExit", self )
    return areaTrigger
end

function AmbienceManager.cl_t_onEnter( self, trigger, results )
	if not TriggerResultContainsLocalPlayer( results ) then
		return
	end

	self.playerId[trigger.id] = sm.localPlayer.getPlayer().character.id
	if self.audioParamData[trigger.id] then
		local paramData = self.audioParamData[trigger.id]
		self.audioParamOriginalValues[trigger.id] = sm.audio.getGlobalParameter( paramData.parameterName )
		sm.audio.setGlobalParameter( paramData.parameterName, paramData.value )
	else
		local tsFlagName = self.toggleFlagNames[trigger.id]
		if tsFlagName then
			local position = trigger:getWorldPosition()
			local world = trigger:getWorld()	
			local tsKey = TileStorageManager.Cl_GetTileStorageKeyFromPosition(world,position)
			if tsKey == nil then
				return
			end
			local flags = TileStorageManager.Cl_GetValueSynced(tsKey,TILESTORAGE_FLAGS_TABLE)
			if flags and flags[tsFlagName] == true then
				self.areaAudio = self.effectNames[trigger.id]
			end
		else
			self.areaAudio = self.effectNames[trigger.id]
		end
	end
end

function AmbienceManager.cl_t_onExit( self, trigger, results )
	if results == nil then return false end
	for _,result in ipairs( results ) do
		if result.id == self.playerId[trigger.id] then
			if self.audioParamData[trigger.id] then
				local paramData = self.audioParamData[trigger.id]
				local original = self.audioParamOriginalValues[trigger.id]
				if original ~= nil then
					sm.audio.setGlobalParameter( paramData.parameterName, original )
					self.audioParamOriginalValues[trigger.id] = nil
				end
			else
				local tsFlagName = self.toggleFlagNames[trigger.id]
				local exitEffect = self.exitEffectNames[trigger.id]
				if tsFlagName then
					local position = trigger:getWorldPosition()
					local world = trigger:getWorld()	
					local tsKey = TileStorageManager.Cl_GetTileStorageKeyFromPosition(world,position)
					if tsKey == nil then
						return
					end
					local flags = TileStorageManager.Cl_GetValueSynced(tsKey,TILESTORAGE_FLAGS_TABLE)
					if flags and flags[tsFlagName] == true then
						if exitEffect then
							sm.effect.playEffect( exitEffect )
						end
					end
				else
					if exitEffect then
						sm.effect.playEffect( exitEffect )
					end
				end
				self.areaAudio = nil
			end
			self.playerId[trigger.id] = nil
		end
	end
end

function AmbienceManager.Cl_OnCellUnloaded( world, x, y )
    if g_ambienceManager then
        g_ambienceManager:client_onCellUnloaded( world, x, y )
    end
end

function AmbienceManager.client_onCellUnloaded( self, world, x, y )
	local cellKey = CellKey( x, y )
	if self.areaTriggers[world.id] then
		if self.areaTriggers[world.id][cellKey] then
			for index, trigger in pairs( self.areaTriggers[world.id][cellKey] ) do
				self.toggleFlagNames[trigger.id] = nil
				sm.areaTrigger.destroy( trigger )
			end
			self.areaTriggers[world.id][cellKey] = nil
		end
	end
	if self.audioParamTriggers[world.id] then
		if self.audioParamTriggers[world.id][cellKey] then
			for index, trigger in pairs( self.audioParamTriggers[world.id][cellKey] ) do
				self.audioParamData[trigger.id] = nil
				self.audioParamOriginalValues[trigger.id] = nil
				self.playerId[trigger.id] = nil
				sm.areaTrigger.destroy( trigger )
			end
			self.audioParamTriggers[world.id][cellKey] = nil
		end
	end
end

function AmbienceManager.client_onCreate( self )
	g_ambienceManager = self

	self.currentWorld = self.scriptableObject:getWorld()
	self.birdAmbienceTimer = Timer()
	self.birdAmbienceTimer:start( 40 )
	self.birdAmbience = { near = {}, far = {} }
	self.toggleFlagNames = {}
	self.exitEffectNames = {}
	self.areaTriggers = {}
	self.effectNames = {}
	self.playerId = {}
	self.audioParamTriggers = {}
	self.audioParamData = {}
	self.audioParamOriginalValues = {}

	self.worldPlayerEffect = nil

	self.pauseWorldAudio = false

	self.worldAudio = nil
	self.worldAudioEffect = nil
	self.zoneAudio = nil
	self.zoneAudioEffect = nil
	self.areaAudio = nil
	self.areaAudioEffect = nil

	self.stoppingEffects = {}
	self.lastMusicParameter = nil

	self.nearWaterEffect = sm.effect.createEffect( "Water - Ambience" )

	self.combatMusicTimer = 0
	self.previousCombatParameter = 0

	sm.audio.setGlobalParameter( "combat", 0 )
end

function AmbienceManager.client_onDestroy( self )
	if sm.exists( self.birdAmbience.near.effect ) then
		self.birdAmbience.near.effect:destroy()
		self.birdAmbience.near.effect = nil
	end
	self.birdAmbience.near = {}
	if sm.exists( self.birdAmbience.far.effect ) then
		self.birdAmbience.far.effect:destroy()
		self.birdAmbience.far.effect = nil
	end
	self.birdAmbience.far = {}

	if self.worldAudioEffect then
		self.worldAudioEffect:destroy()
	end
	if self.zoneAudioEffect then
		self.zoneAudioEffect:destroy()
	end
	if self.areaAudioEffect then
		self.areaAudioEffect:destroy()
	end
	for index, value in ipairs( self.stoppingEffects ) do
		value:destroy()
	end
end

function AmbienceManager.cl_stopAreaEffect( self )
	if self.areaAudioEffect then
		if sm.exists( self.areaAudioEffect ) then
			self.areaAudioEffect:stop()
			self.stoppingEffects[#self.stoppingEffects + 1] = self.areaAudioEffect
		end
		self.areaAudioEffect = nil
	end
end

function AmbienceManager.cl_stopZoneEffect( self )
	if self.zoneAudioEffect then
		if sm.exists( self.zoneAudioEffect ) then
			self.zoneAudioEffect:stop()
			self.stoppingEffects[#self.stoppingEffects + 1] = self.zoneAudioEffect
		end
		self.zoneAudioEffect = nil
	end
end

function AmbienceManager.cl_stopWorldEffect( self )
	if self.worldAudioEffect then
		if sm.exists( self.worldAudioEffect ) then
			self.worldAudioEffect:stop()
			self.stoppingEffects[#self.stoppingEffects + 1] = self.worldAudioEffect
		end
		self.worldAudioEffect = nil
	end
end

function AmbienceManager.client_onFixedUpdate( self )
	if self.areaAudio then
		if self.areaAudioEffect == nil then
			self.areaAudioEffect = sm.effect.createEffect( self.areaAudio )
			self.areaAudioEffect:setWorldAny()
		end
		if self.areaAudioEffect and not self.areaAudioEffect:isPlaying() then
			self.areaAudioEffect:start()
		end
		self:cl_stopZoneEffect()
		self:cl_stopWorldEffect()
	elseif self.zoneAudio then
		if self.zoneAudioEffect == nil then
			self.zoneAudioEffect = sm.effect.createEffect( self.zoneAudio )
			self.zoneAudioEffect:setWorldAny()
		end
		if self.zoneAudioEffect and not self.zoneAudioEffect:isPlaying() then
			self.zoneAudioEffect:start()
		end
		self:cl_stopAreaEffect()
		self:cl_stopWorldEffect()
	elseif self.worldAudio then
		if self.pauseWorldAudio and self.worldAudioEffect then
			self.worldAudioEffect:stop()
		else
			if self.worldAudioEffect == nil then
				self.worldAudioEffect = sm.effect.createEffect( self.worldAudio )
				self.worldAudioEffect:setWorldAny()
			end
			if self.worldAudioEffect and not self.worldAudioEffect:isPlaying() then
				self.worldAudioEffect:start()
			end
		end

		self:cl_stopAreaEffect()
		self:cl_stopZoneEffect()
	else
		self:cl_stopAreaEffect()
		self:cl_stopZoneEffect()
		self:cl_stopWorldEffect()
	end

	if #self.stoppingEffects > 0 then
		if self.stoppingEffects[1] then
			if self.stoppingEffects[1]:isDone() then
				self.stoppingEffects[1]:destroy()
				table.remove( self.stoppingEffects, 1 )
			end
		end
	end

	-- Update ambient birds
	self.birdAmbienceTimer:tick()
	if self.birdAmbienceTimer:done() then
		self.birdAmbienceTimer:reset()
		local myCharacter = sm.localPlayer.getPlayer().character
		if sm.exists( myCharacter ) then
			local nearbyTree = sm.ai.getClosestTree( myCharacter.worldPosition, self.scriptableObject:getWorld() )
			if sm.exists( nearbyTree ) then
				if self.birdAmbience.near.harvestable ~= nearbyTree then
					if nearbyTree.clientPublicData and nearbyTree.clientPublicData.crownPosition then
						-- Remove far bird
						if sm.exists( self.birdAmbience.far.effect ) then
							self.birdAmbience.far.effect:destroy()
						end
						self.birdAmbience.far = {}

						-- Move previous near bird to far
						self.birdAmbience.far.effect = self.birdAmbience.near.effect
						self.birdAmbience.far.harvestable = self.birdAmbience.near.harvestable

						-- Setup new near bird
						self.birdAmbience.near.harvestable = nearbyTree
						self.birdAmbience.near.effect = sm.effect.createEffect( "Tree - Ambient Birds" )
						self.birdAmbience.near.effect:setPosition( nearbyTree.clientPublicData.crownPosition )
						self.birdAmbience.near.effect:start()
					end
				end
			else
				if self.birdAmbience.near.effect and self.birdAmbience.near.effect:isPlaying() then
					self.birdAmbience.near.effect:stop()
				end
				if self.birdAmbience.far.effect and self.birdAmbience.far.effect:isPlaying() then
					self.birdAmbience.far.effect:stop()
				end
			end
		end
	end
end

function AmbienceManager.triggerCombatMusic( self )
    self.combatMusicTimer = CombatMusicCooldownTicks 
end

function AmbienceManager.triggerCombatMusicForTarget( self, target )
	if self.combatMusicTimer <= CombatMusicCooldownTicks * 0.75 then
		if target == sm.localPlayer.getPlayer():getCharacter() then
			self:triggerCombatMusic()
		end
	end
end

function AmbienceManager.cl_updateSurvivalMusic( self )
	if sm.exists( self.currentWorld ) and self.currentWorld.clientPublicData ~= nil then
		local musicParameter = nil
		if self.currentWorld.clientPublicData.musicUpdateProcedure then
			musicParameter = self.currentWorld.clientPublicData.musicUpdateProcedure()
		elseif self.currentWorld.clientPublicData.musicParameter then
			musicParameter = self.currentWorld.clientPublicData.musicParameter
		end

		if musicParameter ~= nil and musicParameter ~= self.lastMusicParameter then
			sm.audio.setGlobalParameter( "music", musicParameter )
			self.lastMusicParameter = musicParameter
		end

		if musicParameter == 9 then
			local combatMusicParameter = self.combatMusicTimer > 0 and 1 or 0
			self.combatMusicTimer = math.max( 0, self.combatMusicTimer - 1 )

			if self.previousCombatParameter ~= combatMusicParameter then
				sm.audio.setGlobalParameter( "combat", combatMusicParameter )
			end
			
			self.previousCombatParameter = combatMusicParameter
		else
			self.combatMusicTimer = 0
		end
	end
end

function AmbienceManager.client_onLocalPlayerChangedWorld( self, world )

	if sm.exists( self.currentWorld ) then
		if SafeGet( self.currentWorld.clientPublicData, "type" ) == "UndergroundWorld" and SafeGet( world.clientPublicData, "type" ) == "Overworld" then
			sm.effect.playEffect( "audio:event:/music/underground_exit" )
		end
	end
	
	self.currentWorld = world

	-- stop player effect
	if self.worldPlayerEffect then
		if sm.exists( self.worldPlayerEffect ) then
			self.worldPlayerEffect:stop()
			self.worldPlayerEffect:destroy()
		end
		self.worldPlayerEffect = nil
	end

	self.worldAudio = nil
	self:cl_stopWorldEffect()
	
	if self.currentWorld.clientPublicData ~= nil then
		-- start player effect
		if self.currentWorld.clientPublicData.playerEffect then
			self.worldPlayerEffect = sm.effect.createEffect( self.currentWorld.clientPublicData.playerEffect, sm.localPlayer.getPlayer():getCharacter() )
			self.worldPlayerEffect:start()
		end
			
		-- set world ambience
		if self.currentWorld.clientPublicData.ambience then
			self.worldAudio = self.currentWorld.clientPublicData.ambience
		end
	end

	if not g_radioTransmitter:isPlaying() then
		g_radioTransmitter:start( sm.game.getServerTick() / 40 )
	end

	if not g_boomboxTransmitter:isPlaying() then
		g_boomboxTransmitter:start( sm.game.getServerTick() / 40 )
	end

	self:cl_updateSurvivalMusic()
end

function AmbienceManager.client_onUpdate( self )
	self:cl_updateSurvivalMusic()
	
	if sm.exists( self.currentWorld ) and self.worldAudio and self.worldAudioEffect and self.currentWorld.clientPublicData ~= nil and self.currentWorld.clientPublicData.ambienceUpdateProcedure then
		self.currentWorld.clientPublicData.ambienceUpdateProcedure( self.worldAudioEffect )
	end
	
	local character = sm.localPlayer.getPlayer():getCharacter()
	if character then
		local pos = character:getWorldPosition()
		local radius = 2.0
		if( sm.physics.isSphereHittingLiquid( pos, radius, self.currentWorld ) ) then
			if not self.nearWaterEffect:isPlaying() then
				self.nearWaterEffect:start()
				self.nearWaterEffect:setWorld( self.currentWorld )
			end
		else
			if self.nearWaterEffect:isPlaying() then
				self.nearWaterEffect:stop()
			end
		end
	end
end

function AmbienceManager.Cl_UpdateZone( zoneId )
	if g_ambienceManager then
		sm.event.sendToScriptableObject( g_ambienceManager.scriptableObject, "cl_updateZone", zoneId, sm.event.types.instant )
	end
end

function AmbienceManager.cl_updateZone( self, zoneId )
	
	local zoneAudio = nil
	local world = sm.localPlayer.getWorld()
	if zoneId then		
		if world == nil then
			return
		end
		if world.clientPublicData and world.clientPublicData.zoneSettings then
			if world.clientPublicData.zoneSettings ~= nil then
				for _, zoneData in ipairs( world.clientPublicData.zoneSettings.zoneData ) do
					if zoneData.id == zoneId and zoneData.ambientEffect ~= "" then
						zoneAudio = zoneData.ambientEffect
						break
					end
				end
			end
		end
	end

	self.zoneAudio = zoneAudio
end

function AmbienceManager.Cl_SetPauseWorldAmbience( value )
    if g_ambienceManager then
        g_ambienceManager:cl_setPauseWorldAmbience( value )
    end
end

function AmbienceManager.cl_setPauseWorldAmbience( self, value )
	self.pauseWorldAudio = value
end
