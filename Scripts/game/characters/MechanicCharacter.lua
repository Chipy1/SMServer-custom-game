dofile( "$SURVIVAL_DATA/Scripts/game/characters/BaseCharacter.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/SurvivalPlayer.lua")

MechanicCharacter = class( BaseCharacter )

-- Goop feature constants (player-only)
local GoopLevelSettings = {
	{ speedFraction = 0.8, tickTime = 40 * 5, goopBlobBones = { "jnt_left_leg", "jnt_right_leg" }, goopLineBones = { "jnt_left_leg", "jnt_right_leg" } },
	{ speedFraction = 0.6, tickTime = 40 * 3, goopBlobBones = { "jnt_spine3" }, goopLineBones = { "jnt_spine3" } },
	{ speedFraction = 0.4, tickTime = 40 * 2, goopBlobBones = { "jnt_head" }, goopLineBones = {} }
}

local GoopScreenLoactions = {
	{ x = -0.5, y = -0.5 }, -- Top Left
	{ x = 0.5, y = -0.5 }, -- Top Right
	{ x = -0.5, y = 0.5 }, -- Bottom Left
	{ x = 0.5, y = 0.5 }, -- Bottom Right
}

local GoopGuiData = sm.json.open( "$GAME_DATA/Gui/JsonGuis/Goop.gui" )
local GoopEffect = FindWidget( GoopGuiData, "GoopEffect" )

local GoopNewPointDistance = 0.5
local GoopMaxPointDistance = 2.1
local GoopLineMaxThicknessX = 0.2175
local GoopLineMaxThicknessY = 0.4175
local GoopLineMinThicknessX = 0.125
local GoopLineMinThicknessY = 0.125
local GoopLineUuid = sm.uuid.new( "9483438c-bb40-4cd6-8f34-1a1a250d622a" )
local GoopBlobUuid = sm.uuid.new( "f3012975-5006-4a3a-b441-14f433070600" )
local GoopColor = sm.color.new( 1.0, 1.0, 1.0 )

local BaguetteSteps = 10

local multiknifeRenderableTp = "$GAME_DATA/Character/Char_Tools/Char_multiknife/char_multiknife_tp.rend"
local multiknifeRenderableFp = "$GAME_DATA/Character/Char_Tools/Char_multiknife/char_multiknife_fp.rend"

local baguetteRenderableTp = "$SURVIVAL_DATA/Character/Char_Tools/Char_longsandwich/char_male_headsandwich.rend"
sm.character.preloadRenderables( { multiknifeRenderableTp, baguetteRenderableTp } )

function MechanicCharacter.server_onCreate( self )
	BaseCharacter.server_onCreate( self )
	local player = self.character:getPlayer()
	if player then
		sm.event.sendToPlayer( player, "sv_e_onSpawnCharacter" )
	end

	self.sv.jumpSpeedMultiplier = 1.0
	self:sv_updatePerks()
	
	self.sv.status = self.sv.status or {}
	self.sv.status.gooped = { level = 0, ticksLeft = 0, previousLevel = 0 }
	self:sv_setClientData()
end

function MechanicCharacter.sv_setClientData( self )
	self.network:setClientData( { status = self.sv.status, jumpSpeedMultiplier = self.sv.jumpSpeedMultiplier }, 2 )
end

function MechanicCharacter.server_onFixedUpdate( self )
	self:sv_updatePerks()
	-- Update goop status effects (player-only)
	local statusChanged = false
	
	-- Update gooped status
	if self.sv.status.gooped.ticksLeft > 0 then
		self.sv.status.gooped.ticksLeft = self.sv.status.gooped.ticksLeft - 1
	end
	if self.sv.status.gooped.ticksLeft <= 0 then
		local nextGoopLevel = math.max( self.sv.status.gooped.level - 1, 0 )
		statusChanged = nextGoopLevel ~= self.sv.status.gooped.level
		self.sv.status.gooped.previousLevel = self.sv.status.gooped.level
		self.sv.status.gooped.level = nextGoopLevel
		if self.sv.status.gooped.level > 0 then
			self.sv.status.gooped.ticksLeft = GoopLevelSettings[self.sv.status.gooped.level].tickTime
		end
	end

	if statusChanged then
		self:sv_setClientData()
	end
end

function MechanicCharacter.cl_n_addGoop( self )
	self:cl_playGoopScreenEffct()
end

function MechanicCharacter.sv_e_addStatusEffect( self, params )
	if params.status == "goop" then
		local addedLevels = params.strength or 1
		local previousLevel = self.sv.status.gooped.level
		local nextLevel = math.min( self.sv.status.gooped.level + addedLevels, #GoopLevelSettings )
		local tickTimeLeft = GoopLevelSettings[nextLevel].tickTime
		self.sv.status.gooped = { level = nextLevel, ticksLeft = tickTimeLeft, previousLevel = previousLevel }
		local player = self.character:getPlayer()
		self.network:sendToClient( player, "cl_n_addGoop" )
	end
	self:sv_setClientData()
end

function MechanicCharacter.sv_updatePerks( self )
	local player = self.character:getPlayer()
	if player and player.publicData and player.publicData.perks then
		local currentMult = self.sv.jumpSpeedMultiplier or 1.0
		if player.publicData.perks[SurvivalPlayer.Perks.HighJump] then
			self.sv.jumpSpeedMultiplier = SurvivalPlayer.BuffHighJumpMult
		else
			self.sv.jumpSpeedMultiplier = 1.0
		end
		if currentMult ~= self.sv.jumpSpeedMultiplier then
			self:sv_setClientData()
		end
	end
end

function MechanicCharacter.client_onCreate( self )
	BaseCharacter.client_onCreate( self )
	
	--legacy support values for the golf mod
	self.animations = {}
	self.isLocal = false
	self.baguetteDesiredElapsed = 0.0
	self.hasBaguette = false
	self.chewing = false
	
	self.cl.waterMovementSpeedFraction = 1.0
	--self.cl.isLocal = self.character:getPlayer() == sm.localPlayer.getPlayer()
	--TODO isLocal check that works the first frame, sm.localPlayer.getPlayer() crashes the game
	self.cl.isLocal = false
	self.cl.baguetteDesiredElapsed = 0.0
	self.cl.hasBaguette = false
	self.cl.chewing = false
	
	-- Player name tag setup (player-only)
	local player = self.character:getPlayer()
	if sm.exists( player ) then
		if player ~= sm.localPlayer.getPlayer() then
			self.character:setNameTag( player:getName() )




		end
	end
	
	-- Goop client-side setup (player-only)
	self.cl.status = {}
	self.cl.goopEffects = {}
	self.cl.effectCount = 0
	self.cl.previousEffectIndex = 0
	self.cl.gui = sm.jsonGui.createGui( { layer = "Wallpaper", isHud = true, needsCursor = false, isInteractive = false  } )
	self:cl_renderGui()
	self.cl.goopEffectBox = self.cl.gui:getWidget( "GoopEffect" )
	self.cl.goopEffectStartTick = {}
	self.cl.lastEffectTick = sm.game.getCurrentTick()
	
	self:client_onRefresh()
end

function MechanicCharacter.client_onDestroy( self )
end

function MechanicCharacter.client_onRefresh( self )
end

function MechanicCharacter.cl_renderGui( self )
	self.cl.gui:render( GoopGuiData )
end

function MechanicCharacter.cl_playGoopScreenEffct( self )
	if self.cl.status.gooped and self.cl.status.gooped.level > 0 then
		local delay = 0.5
		if sm.game.getCurrentTick() - self.cl.lastEffectTick <= delay * 40 then
			return
		end

		if self.cl.status.gooped.previousLevel <= self.cl.status.gooped.level then
				
			self.cl.effectCount = self.cl.effectCount + 1
			local locationIndex = self.cl.effectCount % ( #GoopScreenLoactions ) + 1
			
			if GoopEffect and GoopEffect.Effects then
				local effectIndex =  math.random( 1, #GoopEffect.Effects )
				while effectIndex == self.cl.previousEffectIndex do
					effectIndex = math.random( 1, #GoopEffect.Effects )
				end
				self.cl.previousEffectIndex = effectIndex

				self.cl.goopEffectBox = self.cl.gui:getWidget( "GoopEffect" )
				if self.cl.goopEffectBox:isEffectPlaying( GoopEffect.Effects[effectIndex].Name ) then
					return
				end
				
				local screenWidth, screenHeight = sm.jsonGui.getViewSize()
				local offset = 4
				local screenPosition = GoopScreenLoactions[locationIndex]
				local stepX = screenWidth / offset
				local stepY = screenHeight / offset
				local randomX = screenPosition.x * ( screenWidth - stepX )
				local randomY = screenPosition.y * ( screenHeight - stepY )

				for _, value in ipairs( GoopEffect.Effects ) do
					if value.Offset.x == randomX and value.Offset.y == randomY then
						if self.cl.goopEffectBox:isEffectPlaying( value.Name ) then
							return
						end
					end
				end
				GoopEffect.Effects[effectIndex].Offset.x = randomX
				GoopEffect.Effects[effectIndex].Offset.y = randomY
				
				self:cl_renderGui()
				self.cl.goopEffectBox:startEffect( GoopEffect.Effects[effectIndex].Name )
			end
			self.cl.lastEffectTick = sm.game.getCurrentTick()
		end
	end
end

function MechanicCharacter.client_onGraphicsLoaded( self )
	if self.cl.diveEffect == nil or not sm.exists( self.cl.diveEffect ) then
		self.cl.diveEffect = sm.effect.createEffect( "Mechanic underwater", self.character, "jnt_head" )
	end
	self.cl.isLocal = self.character:getPlayer() == sm.localPlayer.getPlayer()
	self.cl.refineEffect = sm.effect.createEffect( "Multiknife - Use" )
	self.cl.chewEffect = sm.effect.createEffect( "Mechanic - EatBaguette", self.character, "jnt_head" )
	self.cl.koEffect = sm.effect.createEffect( "Mechanic - KoLoop", self.character, "jnt_head" )
	
	-- Goop visual effects (player-only)
	self.cl.goopEffects = {}
	for i, setting in ipairs( GoopLevelSettings ) do
		local goopBlobs = {}
		for k, bone in ipairs( setting.goopBlobBones ) do
			local goopBlob = {}
			goopBlob.effect = sm.effect.createEffect( "ShapeRenderable", self.character, bone )
			goopBlob.effect:setParameter( "uuid", GoopBlobUuid )
			goopBlob.effect:setParameter( "color", GoopColor )
			goopBlob.effect:setScale( sm.vec3.new( 0.5, 0.5, 0.5 ) )
			goopBlob.bone = bone
			goopBlobs[k] = goopBlob
		end
		local goopLines = {}
		for k, bone in ipairs( setting.goopLineBones ) do
			local goopLine = {}
			goopLine.effect = sm.effect.createEffect( "ShapeRenderable" )
			goopLine.effect:setParameter( "uuid", GoopLineUuid )
			goopLine.effect:setParameter( "color", GoopColor )
			goopLine.effect:setScale( sm.vec3.new( 0.5, 0.5, 0.5 ) )
			goopLine.stickyPosition = nil
			goopLine.stickyNormal = nil
			goopLine.bone = bone
			goopLines[k] = goopLine
		end
		self.cl.goopEffects[i] = { goopBlobs = goopBlobs, goopLines = goopLines }
	end
	
	self.cl.animations = self.cl.animations or {}
	-- Third person animations
	self.cl.animations.refine = {
		info = self.character:getAnimationInfo( "multiknife_use" ),
		time = 0,
		weight = 0
	}

	self.cl.animationBaguetteIdle = {
		info = self.character:getAnimationInfo( "sandwich_eat" ),
		time = 0,
		weight = 0
	}
	self.cl.animationBaguetteChew = {
		info = self.character:getAnimationInfo( "sandwich_idle" ),
		time = 0,
		weight = 0
	}
	self.cl.animationBaguette = {
		info = self.character:getAnimationInfo( "headsandwich_eat" ),
		time = 0,
		weight = 0
	}
	
	--Dramatics
	self.cl.animations.dramatics_standup = {
		info = self.character:getAnimationInfo( "dramatics_standup" ),
		time = 0,
		weight = 0
	}
	
	self.cl.animations.dramatics_victory_in = {
		info = self.character:getAnimationInfo( "dramatics_victory_in" ),
		time = 0,
		weight = 0
	}
	
	self.cl.animations.dramatics_victory_loop = {
		info = self.character:getAnimationInfo( "dramatics_victory_loop" ),
		time = 0,
		weight = 0
	}
	
	self.cl.cutsceneAnimations = { "dramatics_standup", "look_around" }
	
	-- First person animations
	if self.cl.isLocal then
		self.cl.FPanimations = {}
		self.cl.FPanimations.refine = {
			info = sm.localPlayer.getFpAnimationInfo( "multiknife_use" ),
			time = 0,
			weight = 0
		}
		self.cl.currentFPAnimation = ""
	end
	self.cl.mechanicAnimationsLoaded = true
	BaseCharacter.client_onGraphicsLoaded( self )
end

function MechanicCharacter.client_onGraphicsUnloaded( self )
	BaseCharacter.client_onGraphicsUnloaded( self )
	if self.cl.refineEffect then
		self.cl.refineEffect:destroy()
		self.cl.refineEffect = nil
	end
	if self.cl.chewEffect then
		self.cl.chewEffect:destroy()
		self.cl.chewEffect = nil
	end
	if self.cl.koEffect then
		self.cl.koEffect:destroy()
		self.cl.koEffect = nil
	end
	if self.cl.diveEffect then
		self.cl.diveEffect:destroy()
		self.cl.diveEffect = nil
	end
	
	-- Cleanup goop effects (player-only)
	for _, goopEffects in ipairs( self.cl.goopEffects ) do
		for _, goopBlob in ipairs( goopEffects.goopBlobs ) do
			goopBlob.effect:destroy()
		end
		for _, goopLine in ipairs( goopEffects.goopLines ) do
			goopLine.effect:destroy()
		end
	end
	self.cl.goopEffects = {}
end

function MechanicCharacter.client_onFixedUpdate( self, deltaTime )
	self.cl.waterMovementSpeedFraction = 1.0
	if self.character.clientPublicData and self.character.clientPublicData.waterMovementSpeedFraction then
		self.cl.waterMovementSpeedFraction = self.character.clientPublicData.waterMovementSpeedFraction
	end
end

function MechanicCharacter.client_onUpdate( self, deltaTime )
	-- Apply water and goop movement speed modifiers
	local totalMovementSpeedFraction = self.cl.waterMovementSpeedFraction
	if self.cl.status.gooped and self.cl.status.gooped.level > 0 then
		totalMovementSpeedFraction = totalMovementSpeedFraction * GoopLevelSettings[self.cl.status.gooped.level].speedFraction
	end
	self.character.movementSpeedFraction = totalMovementSpeedFraction

	BaseCharacter.client_onUpdate( self, deltaTime )

	if not self.cl.graphicsLoaded then
		return
	end

	-- Control diving effect
	if self.cl.diveEffect then
		if self.character:isDiving() then
			if not self.cl.diveEffect:isPlaying() then
				self.cl.diveEffect:start()
			end
		elseif not self.character:isDiving() then
			if self.cl.diveEffect:isPlaying() then
				self.cl.diveEffect:stop()
			end
		end
	end

	-- Control KO effect
	if self.character:isDowned() and not self.cl.koEffect:isPlaying() then
		self.cl.koEffect:start()
	elseif not self.character:isDowned() and self.cl.koEffect:isPlaying() then
		self.cl.koEffect:stop()
	end

	-- Control goop visual effects (player-only)
	for i, goopBoneEffects in ipairs( self.cl.goopEffects ) do
		for _, goopBlob in ipairs( goopBoneEffects.goopBlobs ) do
			if self.cl.status.gooped and self.cl.status.gooped.level >= i then
				if not goopBlob.effect:isPlaying() then
					goopBlob.effect:start()
				end
			else
				if goopBlob.effect:isPlaying() then
					goopBlob.effect:stop()
					local goopBlobPosition = goopBlob.bone and self.character:getTpBonePos( goopBlob.bone ) or self.character.worldPosition
					local goopBlobRotation = goopBlob.bone and self.character:getTpBoneRot( goopBlob.bone ) or sm.quat.identity()
					sm.effect.playEffect( "Paintgoop - Splash", goopBlobPosition, nil, goopBlobRotation )
				end
			end
		end

		for _, goopLine in ipairs( goopBoneEffects.goopLines ) do
			local puddlePosition = goopLine.stickyPosition
			local snapPosition
			local snapRotation

			-- Update sticky position
			if self.cl.status.gooped and self.cl.status.gooped.level >= i then
				if not goopLine.stickyPosition then
					-- Find new sticky position
					local startPosition = self.character.worldPosition
					local endPosition = startPosition + sm.vec3.new( 0, 0, -GoopNewPointDistance )
					local radius = 0.25
					local success, result = sm.physics.spherecast( startPosition, endPosition, radius, self.character )
					if success then
						goopLine.stickyPosition = result.pointWorld
						goopLine.stickyNormal = result.normalWorld
					else
						goopLine.stickyPosition = nil
					end
				end
			else
				goopLine.stickyPosition = nil
			end

			-- Update effect
			if goopLine.stickyPosition then
				puddlePosition = goopLine.stickyPosition
				local selfWorldPosition = goopLine.bone and self.character:getTpBonePos( goopLine.bone ) or self.character.worldPosition
				local halfwayPosition = selfWorldPosition + ( goopLine.stickyPosition - selfWorldPosition ) * 0.5
				snapPosition = halfwayPosition
				local stickyLineFromTo = goopLine.stickyPosition - selfWorldPosition
				local stickyLineLength = stickyLineFromTo:length()
				local stickyLineDirection = stickyLineFromTo:safeNormalize( sm.vec3.new( 0, 0, -1 ) )
				stickyLineLength = math.max( stickyLineLength, FLT_EPSILON )
				local stickyScale = 1.0 - math.max( math.min( stickyLineLength / GoopMaxPointDistance, 1.0 ), 0.0 )
				local stickyLineRotation = sm.vec3.getRotation( sm.vec3.new( 0, 0, 1 ), stickyLineDirection )
				snapRotation = stickyLineRotation

				if stickyScale >= FLT_EPSILON then
					goopLine.effect:setPosition( halfwayPosition )
					goopLine.effect:setRotation( stickyLineRotation )
					goopLine.effect:setScale( sm.vec3.new( lerp( GoopLineMinThicknessX, GoopLineMaxThicknessX, stickyScale ), lerp( GoopLineMinThicknessY, GoopLineMaxThicknessY, stickyScale ), stickyLineLength ) )
				else
					goopLine.stickyPosition = nil
				end
			end

			-- Toggle effect
			if goopLine.stickyPosition then
				if not goopLine.effect:isPlaying() then
					goopLine.effect:start()
				end
			else
				if goopLine.effect:isPlaying() then
					goopLine.effect:stop()
					if snapPosition and snapRotation then
						sm.effect.playEffect( "Paintgoop - Snap", snapPosition, nil, snapRotation )
					end
					if puddlePosition and goopLine.stickyNormal then
						local puddleRotation = sm.vec3.getRotation( sm.vec3.new( 0, 0, 1 ), goopLine.stickyNormal )
						sm.effect.playEffect( "Paintgoop - Puddle" , puddlePosition, nil, puddleRotation, sm.vec3.one() * 100, { color = GoopColor } )
						goopLine.stickyNormal = nil
					end
				end
			end
		end
	end

	-- Baguette animations
	if self.cl.hasBaguette then
		self.cl.animationBaguetteIdle.weight = math.min( self.cl.animationBaguetteIdle.weight + ( self.cl.animator.blendSpeed * deltaTime ), 1.0 )
		self.cl.animationBaguette.weight = math.min( self.cl.animationBaguette.weight + ( self.cl.animator.blendSpeed * deltaTime ), 1.0 )
	else
		self.cl.animationBaguetteIdle.weight = math.max( self.cl.animationBaguetteIdle.weight - ( self.cl.animator.blendSpeed * deltaTime ), 0.0 )
		self.cl.animationBaguette.weight = math.max( self.cl.animationBaguette.weight - ( self.cl.animator.blendSpeed * deltaTime ), 0.0 )
	end
	if self.cl.chewing then
		self.cl.animationBaguetteChew.weight = math.min( self.cl.animationBaguetteChew.weight + ( self.cl.animator.blendSpeed * deltaTime ), 1 )
	else
		self.cl.animationBaguetteChew.weight = math.max( self.cl.animationBaguetteChew.weight - ( self.cl.animator.blendSpeed * deltaTime ), 0.0 )
	end

	self.character:setAllowTumbleAnimations( self.cl.hasBaguette or self.cl.chewing )
	if self.cl.animationBaguetteIdle.info then
		self.cl.animationBaguetteIdle.time = self.cl.animationBaguetteIdle.time + deltaTime
		if self.cl.animationBaguetteIdle.time >= self.cl.animationBaguetteIdle.info.duration then
			self.cl.animationBaguetteIdle.time = self.cl.animationBaguetteIdle.time - self.cl.animationBaguetteIdle.info.duration
		end
		self.character:updateAnimation( self.cl.animationBaguetteIdle.info.name, self.cl.animationBaguetteIdle.time, self.cl.animationBaguetteIdle.weight, true )
	end
	if self.cl.animationBaguetteChew.info then
		if self.cl.chewing then
			self.cl.animationBaguetteChew.time = self.cl.animationBaguetteChew.time + deltaTime
			if self.cl.animationBaguetteChew.time >= self.cl.animationBaguetteChew.info.duration then
				self.cl.animationBaguetteChew.time = 0.0
				self.cl.chewing = false
			end
		end
		self.character:updateAnimation( self.cl.animationBaguetteChew.info.name, self.cl.animationBaguetteChew.time, self.cl.animationBaguetteChew.weight, true )
	end
	if self.cl.animationBaguette.info then
		self.cl.animationBaguette.time = self.cl.animationBaguette.time + deltaTime
		self.cl.animationBaguette.time = math.min( self.cl.animationBaguette.time, math.min( self.cl.baguetteDesiredElapsed, self.cl.animationBaguette.info.duration ) )
		self.character:updateAnimation( self.cl.animationBaguette.info.name, self.cl.animationBaguette.time, self.cl.animationBaguette.weight, true )
	end

	-- Play refine effects
	if self.cl.isLocal then
		if self.cl.animator.currentAnimation == "refine" then
			local mayaFrameDuration = 1.0/30.0
			local refineTime = self.cl.animations["refine"].time
			local frameTime = 6 * mayaFrameDuration
			if refineTime >= frameTime and frameTime ~= 0 then
				if self.cl.pendingRefineFlag then
					self.cl.pendingRefineFlag = false

					local sucess, result = sm.localPlayer.getRaycast( 7.5, sm.localPlayer.getRaycastStart(), sm.localPlayer.getDirection() )
					local hitShape = result:getShape()
					if sucess and hitShape then
						if sm.localPlayer.isInFirstPersonView() then

							local effectPos = sm.localPlayer.getFpBonePos( "pejnt_lazer" )
							if effectPos then

								local rot = sm.vec3.getRotation( sm.vec3.new( 0, 0, 1 ), sm.localPlayer.getUp() )
								rot = sm.vec3.getRotation( sm.localPlayer.getUp(), sm.localPlayer.getUp():rotate( ( 40 ) * math.pi / 180, sm.localPlayer.getDirection() ) ) * rot

								local fovScale = ( sm.camera.getFov() - 45 ) / 45

								local xOffset45 = sm.localPlayer.getRight() * 0.035
								local yOffset45 = sm.localPlayer.getDirection() * 0.6
								local zOffset45 = sm.localPlayer.getUp() * 0.1
								local offset45 = xOffset45 + yOffset45 + zOffset45

								local xOffset90 = sm.localPlayer.getRight() * 0.035
								local yOffset90 = sm.localPlayer.getDirection() * 0.2
								local zOffset90 = sm.localPlayer.getUp() * 0.1
								local offset90 = xOffset90 + yOffset90 + zOffset90

								local offset = sm.vec3.lerp( offset45, offset90, fovScale )

								self.cl.refineEffect:setParameter( "Material", hitShape:getMaterialId() )
								self.cl.refineEffect:setPosition( effectPos + offset )
								self.cl.refineEffect:setRotation( rot )
								self.cl.refineEffect:start()
							end
						end

						local params = { effectName = "Multiknife - Hit",
										position = result.pointWorld, 
										rotation = sm.vec3.getRotation( sm.vec3.new( 0, 0, 1 ), 
										result.normalWorld ), 
										effectParams = { Material = hitShape:getMaterialId(), Size = 0.005, Velocity = 10 }, 
										player = sm.localPlayer.getPlayer() }
						self:cl_onEffect( params )
						self.network:sendToServer( "sv_n_onEffect", params )
					end
				end
			elseif refineTime < frameTime and frameTime ~= 0 then
				self.cl.pendingRefineFlag = true
			end
		end
	end

	-- First person animations
	if self.cl.isLocal then
		for name, animation in pairs( self.cl.FPanimations ) do
			if animation.info then
				animation.time = animation.time + deltaTime

				if animation.info.looping == true then
					if animation.time >= animation.info.duration then
						animation.time = animation.time - animation.info.duration
					end
				end
				if name == self.cl.currentFPAnimation then
					animation.weight = math.min(animation.weight+(self.cl.animator.blendSpeed * deltaTime), 1.0)
					if animation.time >= animation.info.duration then
						self.cl.currentFPAnimation = ""
					end
				else
					animation.weight = math.max(animation.weight-(self.cl.animator.blendSpeed * deltaTime ), 0.0)
				end
				sm.localPlayer.updateFpAnimation( animation.info.name, animation.time, animation.weight, animation.info.looping )
			end
		end
	end
end

-- kept for backwards compatibility with old animation events
function MechanicCharacter.cl_e_onEvent( self, event )
	self:cl_handleEvent( event )
end

function MechanicCharacter.cl_handleEvent( self, event )
	local handled = BaseCharacter.cl_handleEvent( self, event )
	if handled then
		return true
	end
	
	if not self.cl.mechanicAnimationsLoaded then
		return true
	end

	if self.cl.animator.currentAnimation == "" or self.cl.animator.currentAnimation == nil then
		if event == "refineStart" then
			self.character:addRenderable( multiknifeRenderableTp )
			self.cl.animator:setCurrentAnimation("refine")
			if self.cl.isLocal then
				sm.localPlayer.addRenderable( multiknifeRenderableFp )
				self.cl.currentFPAnimation = "refine"
				self.cl.FPanimations.refine.time = 0
			end
		elseif event == "hit" then
			sm.effect.playEffect( "Character - Hit", self.character.worldPosition )
		else
			self.cl.animator.currentAnimation = ""
			self.cl.currentFPAnimation = ""
		end
	elseif self.cl.animator.currentAnimation == "refine" and event == "refineEnd" then
		self.character:removeRenderable( multiknifeRenderableTp )
		self.cl.animator.currentAnimation = ""
		if self.cl.isLocal then
			sm.localPlayer.removeRenderable( multiknifeRenderableFp )
			self.cl.currentFPAnimation = ""
		end
	end

	if event == "baguette" then
		if sm.exists(self.character) then
			self.character:addRenderable( baguetteRenderableTp )
		end
		self.cl.baguetteDesiredElapsed = 0.0
		self.cl.hasBaguette = true
	elseif event == "revive" then
		if sm.exists(self.character) then
			self.character:removeRenderable( baguetteRenderableTp )
		end
		self.cl.hasBaguette = false
	elseif event == "chew" then
		if self.cl.animationBaguette.info then
			self.cl.baguetteDesiredElapsed = math.min( self.cl.baguetteDesiredElapsed + self.cl.animationBaguette.info.duration / BaguetteSteps, self.cl.animationBaguette.info.duration )
		end
		self.cl.chewing = true
		if self.cl.graphicsLoaded then
			self.cl.chewEffect:start()
		end
	elseif event == "dramatics_standup" then
		self.cl.animator:setCurrentAnimation("dramatics_standup")
	elseif event == "look_around" then
		self.cl.animator:setCurrentAnimation("look_around")
	elseif event == "dramatics_victory_in" then
		self.cl.animator:setCurrentAnimation("dramatics_victory_in")
	elseif event == "dramatics_victory_loop" then
		self.cl.animator:setCurrentAnimation("dramatics_victory_loop")
	end
end

function MechanicCharacter.cl_e_onCancel( self )
	-- Abort cutscene animations
	if isAnyOf( self.cl.animator.currentAnimation, self.cl.cutsceneAnimations ) then
		self.cl.animations[self.cl.animator.currentAnimation].time = 0
		self.cl.animations[self.cl.animator.currentAnimation].weight = 0
		self.character:updateAnimation( self.cl.animator.currentAnimation, 0, 0 )

		self.cl.animator.currentAnimation = ""
	end
end

function MechanicCharacter.cl_onEffect( self, params )
	sm.effect.playEffect( params.effectName, params.position, params.velocity, params.rotation, params.scale, params.effectParams )
end

function MechanicCharacter.cl_n_onEffect( self, params ) 
	if params.player ~= sm.localPlayer.getPlayer() then
		self:cl_onEffect( params )
	end
end

function MechanicCharacter.sv_n_onEffect( self, params )
	self.network:sendToClients( "cl_n_onEffect", params )
end

function MechanicCharacter.client_onClientDataUpdate( self, data, channel )
	BaseCharacter.client_onClientDataUpdate( self, data, channel )
	if channel == 2 then
		self.character:setJumpSpeedFraction( data.jumpSpeedMultiplier or 1.0 )
		self.cl.status = data.status
	end
end
