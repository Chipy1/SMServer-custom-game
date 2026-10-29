dofile( "$SURVIVAL_DATA/Scripts/game/quests/GenericBuilderQuest.lua" )

GenericBuilderQuestCharacter = class( nil )

local LookAtPlayerDistance = 20

local BlendSpeed = 4.0

local TotebotBreakoutEffect = "Builderguide Quest - Totebotbreakfree"
local KOEffect = "Mechanic - KoLoop"

local ScrapperRendBase = {
	"$SURVIVAL_DATA/Character/Char_Male/Animations/char_male_tp_npc_scrapperbuilder.rend",
}

function GenericBuilderQuestCharacter.server_onCreate( self )
	QuestManager.Sv_SubscribeEvent( QuestEvent.QuestCompleted, self.character, "sv_e_onQuestCompleted" )
	self.sv = {}
	self.sv.questName = nil
	self.sv.dialog = nil
	self.sv.tileStorageKey = TileStorageManager.Sv_GetTileStorageKeyFromObject( self.character )

	self.sv.questStage = nil
end

function GenericBuilderQuestCharacter.sv_getScrapperCompletion( self )
	if self.character:getCharacterType() ~= unit_builderguideScrapper then
		return nil
	end

	local count = 0
	for _, scrapperQuestName in ipairs( GenericBuilderQuest.ScrapperQuestNames ) do
		if QuestManager.Sv_IsQuestComplete( scrapperQuestName ) then
			count = count + 1
		end
	end
	return count
end

function GenericBuilderQuestCharacter.sv_e_onQuestCompleted( self, data )
	local completedThisQuest = data.params.questName == self.sv.questName

	if not sm.exists( self.character ) then
		return
	end

	local scrapperCompleteCount = self:sv_getScrapperCompletion()

	if completedThisQuest == true or ( scrapperCompleteCount ~= nil and scrapperCompleteCount > 0 ) then
		self.network:sendToClients( "cl_n_onQuestCompleted", { animate = completedThisQuest, scrapperQuestCompletion = scrapperCompleteCount } )
	end

end

function GenericBuilderQuestCharacter.cl_n_onQuestCompleted( self, params )
	if params.animate then
		self:cl_setCurrentAnimation( "reward" )
	end

	if self.character:getCharacterType() == unit_builderguideScrapper then
		if params and params.scrapperQuestCompletion then
			self:cl_updateScrapperRends( params.scrapperQuestCompletion )
		end
	end
end

function GenericBuilderQuestCharacter.cl_updateScrapperRends( self, scrapperCompletionCount )
	local count = 0
	if scrapperCompletionCount ~= nil then
		count = scrapperCompletionCount
	else
		for _, questName in ipairs( GenericBuilderQuest.ScrapperQuestNames ) do
			if QuestManager.Cl_IsQuestComplete( questName ) then
				count = count + 1
			end
		end
	end

	local list = shallowcopy( ScrapperRendBase )

	if count >= 1 then -- feet
		table.insert( list, "$SURVIVAL_DATA/Character/Char_Male/Body/Male/char_male_body_shoes.rend" )
	else
		table.insert( list, "$SURVIVAL_DATA/Character/Char_Male/Outfit/Shoes/Outfit_scrapper_shoes/char_shared_outfit_scrapper_shoes.rend" )
	end
	if count >= 2 then -- pants
		table.insert( list, "$SURVIVAL_DATA/Character/Char_Male/Body/Male/char_male_body_pants.rend" )
	else
		table.insert( list, "$SURVIVAL_DATA/Character/Char_Male/Outfit/Pants/Outfit_scrapper_pants/char_male_outfit_scrapper_pants.rend" )
	end
	if count >= 3 then -- torso
		table.insert( list, "$SURVIVAL_DATA/Character/Char_Male/Body/Male/char_male_body_jacket.rend" )
	else
		table.insert( list, "$SURVIVAL_DATA/Character/Char_Male/Outfit/Jacket/Outfit_scrapper_jacket/char_male_outfit_scrapper_jacket.rend" )
	end
	if count >= 4 then -- gloves
		table.insert( list, "$SURVIVAL_DATA/Character/Char_Male/Body/Male/char_male_body_gloves.rend" )
	else
		table.insert( list, "$SURVIVAL_DATA/Character/Char_Male/Outfit/Gloves/Outfit_scrapper_gloves/char_male_outfit_scrapper_gloves.rend" )
	end
	if count >= 5 then -- backpack
		-- nothing
	else
		table.insert( list, "$SURVIVAL_DATA/Character/Char_Male/Outfit/Backpack/Outfit_scrapper_backpack/char_shared_outfit_scrapper_backpack.rend" )
	end
	if count >= 6 then -- hat
		table.insert( list, "$SURVIVAL_DATA/Character/Char_Male/Head/Male/char_male_head06/char_male_head06.rend" )
		table.insert( list, "$SURVIVAL_DATA/Character/Char_Male/Facialfeatures/char_male_facialhair_12/char_male_facialhair_12.rend" )
		table.insert( list, "$SURVIVAL_DATA/Character/Char_Male/Hair/Male/char_male_hair_05/char_male_hair_05.rend" )
	else
		table.insert( list, "$SURVIVAL_DATA/Character/Char_Male/Outfit/Hat/Outfit_scrapper_hat/char_male_outfit_scrapper_hat.rend" )
	end

	self.character:overrideRenderableList( list )
end

function GenericBuilderQuestCharacter.sv_n_talk( self )
	if self.sv.questName then
		if not QuestManager.Sv_IsQuestActive( self.sv.questName ) and not QuestManager.Sv_IsQuestComplete( self.sv.questName ) then
			local dialogId = tostring( self.sv.dialog )
			local dialogEntryName = "StartQuest"
			if not DialogManager.Sv_IsDialogQueued( dialogId, dialogEntryName ) then
				DialogManager.Sv_PlayDialog( dialogId, dialogEntryName, nil, DialogType.Person, nil, DialogPriority.SideQuest, self.character:getUnit() )
			end
		else
			local stage = QuestManager.Sv_GetQuestStage( self.sv.questName )
			
			if stage == GenericBuilderQuest.Stages.build_thing then
				self.network:sendToClients( "cl_n_setCurrentAnimation", { animationName = "confused" } )
			elseif stage == GenericBuilderQuest.Stages.talk_to_person then
				local dialogId = tostring( self.sv.dialog )
				local dialogEntryName = "FinishQuest"
				DialogManager.Sv_PlayDialog( dialogId, dialogEntryName, nil, DialogType.Person, nil, DialogPriority.SideQuest, self.character:getUnit() )
			end
		end
	end
end

function GenericBuilderQuestCharacter.sv_n_startQuest( self )
	if self.sv.questName then
		QuestManager.Sv_ActivateQuest( self.sv.questName, { world = self.character:getWorld(), pos = self.character:getWorldPosition(), path = self.sv.path } )
	end
end

function GenericBuilderQuestCharacter.sv_n_finishQuest( self, params )
	local stage = QuestManager.Sv_GetQuestStage( self.sv.questName )
	if stage == GenericBuilderQuest.Stages.talk_to_person then --  if quest is waiting for finish dialog
		QuestManager.Sv_SendEvent( "generic.builder.finish."..self.sv.questName, { isScrapper = self.data.isScrapper } )
		if self.character:getCharacterType() == unit_builerguideTotebot then
			sm.effect.playEffect( TotebotBreakoutEffect, self.character.worldPosition )
			local spawnDirection = self.character:getDirection()
			local yaw = math.atan2( spawnDirection.y, spawnDirection.x ) - math.pi / 2
			sm.event.sendToWorld( self.character:getWorld(), "sv_e_spawnUnit", { uuid = unit_totebot_green, position = self.character.worldPosition - sm.vec3.new( 0,0,0.5), yaw = yaw, amount = 1, customParams = { overrideHP = 300 } } )

			local unit = self.character:getUnit()
			if unit then
				unit:destroy()
			end
		end
	else
		print( "error: dialog finished but quest stage is not waiting for finish dialog" )
	end
end

function GenericBuilderQuestCharacter.cl_e_dialogStartQuest( self )
	if sm.isHost then
		self.network:sendToServer( "sv_n_startQuest" )
	end
end

function GenericBuilderQuestCharacter.server_onFixedUpdate( self )
	local init = false
	if self.sv.questName == nil then
		local value = TileStorageManager.Sv_GetValue( self.sv.tileStorageKey, BUILDERGUIDE_PLATFORM_TABLE )
		if value and not IsEmptyTable( value ) then
			self.sv.questName = value.questName
			self.sv.path = value.path
			self.sv.dialog = value.dialog
			init = true
		end
	end

	if self.sv.questName then -- got tilestorage
		local stage = QuestManager.Sv_GetQuestStage( self.sv.questName )
		local scrapperQuestCompletion = self:sv_getScrapperCompletion()
		if self.sv.questStage ~= stage then
			self.sv.questStage = stage
			if stage == GenericBuilderQuest.Stages.talk_to_person then
				-- do cheer loop until next animation
				self.network:setClientData( { questName = self.sv.questName, buildCompleteStage = true, scrapperQuestCompletion = scrapperQuestCompletion } )
			else
				self.network:setClientData( { questName = self.sv.questName, scrapperQuestCompletion = scrapperQuestCompletion } )
			end
		elseif init then
			self.network:setClientData( { questName = self.sv.questName, scrapperQuestCompletion = scrapperQuestCompletion } )
		end
	end
end

function GenericBuilderQuestCharacter.client_onCreate( self )
	self.cl = {}
    self.cl.animations = {}
	self.cl.questName = nil
	self.cl.startRotation = sm.vec3.getRotation( sm.vec3.new( 0, 1, 0 ), self.character.direction )

	self.cl.headAngle = 0.5
	self.cl.headSideAngle = 0.5

	self.cl.lastInteractionTick = 0
	
	if self.character:getCharacterType() == unit_builderguideScrapper then
		self:cl_updateScrapperRends()
	end
end

function GenericBuilderQuestCharacter.client_onDestroy( self )
	if self.cl.farmeballEffect then
		self.cl.farmeballEffect:destroy()
		self.cl.farmeballEffect = nil
	end
end

function GenericBuilderQuestCharacter.client_onClientDataUpdate( self, data, channel )
	if data.buildCompleteStage then
		if self.character:getCharacterType() == unit_builderguideFarmerko and self.cl.questName then
			-- if we have the quest name already, this means we are currenly completing the quest, do the revive animation
			-- otherwise this is an init, where the character appears after completion, then skip to cheer_loop
			self:cl_setCurrentAnimation( "revive" )
		else
			self:cl_setCurrentAnimation( "cheer_loop" )
		end
		self.cl.buildCompleteStage = true
	else
		if self.character:getCharacterType() == unit_builderguideFarmerko and self.cl.questName == nil then
			if not QuestManager.Cl_IsQuestComplete( data.questName ) then
				self:cl_setCurrentAnimation( "ko_idle" )
			end
		end
		self.cl.buildCompleteStage = false
	end

	self.cl.questName = data.questName

	if self.character:getCharacterType() == unit_builderguideScrapper and data.scrapperQuestCompletion ~= nil then
		self:cl_updateScrapperRends( data.scrapperQuestCompletion )
	end

	if self.cl.questName == "quest_build_crowbar" and not self.cl.farmeballEffect then
		self.cl.farmeballEffect = sm.effect.createEffect( "Builderguide_questplatform - Farmerball" )
		self.cl.farmeballEffect:setPosition( self.character.worldPosition )
		self.cl.farmeballEffect:setRotation( self.cl.startRotation * sm.quat.rotZ180() )
		self.cl.farmeballEffect:start()
	end
end

function GenericBuilderQuestCharacter.client_canInteract( self )
	if self.cl.questName == nil or DialogManager.Cl_IsRunning() or QuestManager.Cl_IsQuestComplete( self.cl.questName ) or self.cl.currentAnimation == "revive" then
		return false
	end

    local keyBindingText = sm.gui.getKeyBinding( "Use", true )
    sm.gui.setInteractionText( "", keyBindingText, "#{INTERACTION_TALK}" )
    return true
end

function GenericBuilderQuestCharacter.client_onInteract( self, character, state )
	local tick = sm.game.getCurrentTick()
	if tick - self.cl.lastInteractionTick < 20 or self.cl.currentAnimation == "revive" then
		return -- cap network spam
	end
	self.cl.lastInteractionTick = tick

	if state == true then
		self.network:sendToServer( "sv_n_talk" )
	end
end

function GenericBuilderQuestCharacter.client_onGraphicsLoaded( self )
	-- this character needs to preserve animation state when graphics are reloaded because of the scrapper rends
	self.cl.animations = self.cl.animations or {}

	if self.cl.currentAnimation == nil then
		self.cl.currentAnimation = ""
	end

	local initAnimation = function( animationName, settings )
		if settings == nil then
			settings = {}
		end
		self.cl.animations[animationName] = {
			info = self.character:getAnimationInfo( animationName ),
			time = settings.time or 0,
			weight = settings.weight or 0,
			additive = settings.additive or false,
			nextAnimation = settings.nextAnimation,
			nextWeight = settings.nextWeight or 0
		}
	end

	initAnimation( "greet" )
	initAnimation( "talk" )
	initAnimation( "talkidle" )
	initAnimation( "confused" )
	initAnimation( "cheer_loop" )
	initAnimation( "bye" )
	initAnimation( "reward" )

	if self.character:getCharacterType() == unit_builderguideFarmersleepy then
		initAnimation( "reward", { nextAnimation = "sleep_in", nextWeight = 1 } )
		initAnimation( "sleep_in", { nextAnimation = "sleep_idle", nextWeight = 1 } )
		initAnimation( "sleep_idle" )
		if QuestManager.Cl_IsQuestComplete( "quest_build_cozybed" ) then
			self:cl_setCurrentAnimation( "sleep_idle", 0, 1 )
		end
	elseif self.character:getCharacterType() == unit_builderguideFarmerko then
		initAnimation( "confused", { nextAnimation = "ko_idle" } )
		initAnimation( "ko_idle" )
		initAnimation( "ko_talk" )
		initAnimation( "ko_talkidle" )
		initAnimation( "revive", { nextAnimation = "cheer_loop" } )

		if self.cl.koEffect == nil then
			self.cl.koEffect = sm.effect.createEffect( KOEffect, self.character, "jnt_head" )
		end
		if not QuestManager.Cl_IsQuestActive( "quest_build_baguette" ) and not QuestManager.Cl_IsQuestComplete( "quest_build_baguette" ) then
			self:cl_setCurrentAnimation( "ko_idle", 0, 1 )
		end
	end

	self.cl.graphicsLoaded = true
end

function GenericBuilderQuestCharacter.client_onGraphicsUnloaded( self )
	self.cl.graphicsLoaded = false
end

function GenericBuilderQuestCharacter.sv_n_updateTarget( self, params )
	self.network:sendToClients( "cl_n_updateTarget", params )
end

function GenericBuilderQuestCharacter.cl_n_setCurrentAnimation( self, params )
	self:cl_setCurrentAnimation( params.animationName )
end

function GenericBuilderQuestCharacter.cl_setCurrentAnimation( self, animationName, time, weight )
	if self.cl.currentAnimation == animationName then
		return
	end

	if animationName == "revive" then
		if self.cl.koEffect and sm.exists( self.cl.koEffect ) then
			self.cl.koEffect:stop()
			self.cl.koEffect = nil
		end
	elseif animationName == "ko_idle" then
		if self.cl.koEffect and sm.exists( self.cl.koEffect ) then
			if not self.cl.koEffect:isPlaying() then
				self.cl.koEffect:start()
			end
		end
	end

	self.cl.currentAnimation = animationName
	if self.cl.animations[animationName] then
		self.cl.animations[animationName].time = time or 0
		if weight then
			self.cl.animations[animationName].weight = weight
		end
	end
end

function GenericBuilderQuestCharacter.cl_n_updateTarget( self, params )
	if self.cl.graphicsLoaded and self.cl.currentAnimation ~= "cheer_loop" and self.cl.currentAnimation ~= "revive" then
		if self.cl.target == nil and params.target then
			self.cl.currentAnimation = "greet"
			self.cl.animations.greet.time = 0
		elseif params.target == nil then
			self.cl.currentAnimation = "bye"
			self.cl.animations.bye.time = 0
		end
	end
	self.cl.target = params.target
end

function GenericBuilderQuestCharacter.client_onUpdate( self, deltaTime )
	if not self.cl.graphicsLoaded then
		return
	end
		
	-- Update spine bending animation
	local lookZ = 0.0
	
	local headLerpSpeed = 1.0 / 40.0
	local blend = math.pow( 1 - ( 1 - headLerpSpeed ), ( deltaTime * 60 ) )

	local followPlayer = true
	if self.character:getCharacterType() == unit_builderguideFarmersleepy then
		followPlayer = not QuestManager.Cl_IsQuestComplete( self.cl.questName ) -- stop follow when sleeping
	elseif self.character:getCharacterType() == unit_builderguideFarmerko then
		followPlayer = QuestManager.Cl_IsQuestComplete( self.cl.questName ) or ( self.cl.buildCompleteStage and not self.cl.currentAnimation == "revive" ) -- follow after revived
	end
	
	local isWoc = self.character:getCharacterType() == unit_builderguideWoc
	local horizontalAngle = nil

	if not followPlayer then
		self.cl.headAngle = lerp( self.cl.headAngle, 0.5, blend )
		if isWoc then
			self.cl.headSideAngle = lerp( self.cl.headSideAngle, 0.5, blend )
		end
	else
		if self.cl.target and sm.exists( self.cl.target ) then
			local distance = sm.vec3.getDistance( self.cl.target.worldPosition, self.character.worldPosition )

			local levelPos = self.cl.target.worldPosition
			levelPos.z = self.character.worldPosition.z

			local headPos = self.cl.target.worldPosition + sm.vec3.new( 0, 0, 0.5 )
			local lookPos = sm.vec3.lerp( headPos, levelPos, 1 - saturate( distance / 2 ) )

			if distance <= LookAtPlayerDistance then
				local origin = ( self.character.worldPosition )
				lookZ = ( lookPos - origin ):safeNormalize( sm.vec3.zero() ).z
			end

			if isWoc then
				local dir = self.character.direction
				local targetDir = ( levelPos - self.character.worldPosition ):safeNormalize( dir )
				horizontalAngle = math.acos( clamp( sm.vec3.dot( targetDir, dir ), -1, 1 ) )
				local determinant = ( dir.x * targetDir.y - dir.y * targetDir.x )
				if determinant < 0 then
					horizontalAngle = -horizontalAngle
				end
			end
		end

		local angle = math.asin( lookZ ) / ( math.pi / 2 )
		local desiredHeadAngle = ( 0.5 + angle * 0.5 )
		self.cl.headAngle = lerp( self.cl.headAngle, desiredHeadAngle, blend )

		if horizontalAngle then
			local angle = horizontalAngle / ( math.pi / 2 )
			local desiredHeadAngle = ( 0.5 + angle * 0.5 )

			if desiredHeadAngle > 1 or desiredHeadAngle < 0 then
				self.cl.headSideAngle = lerp( self.cl.headSideAngle, 0.5, blend * 0.5 )
			else
				self.cl.headSideAngle = lerp( self.cl.headSideAngle, desiredHeadAngle, blend )
			end

		end
	end
	
	if isWoc then
		self.character:updateAnimation( "aimbend_updown", 1 - self.cl.headAngle, 1.0, true )
		self.character:updateAnimation( "aimbend_leftright", 1 - self.cl.headSideAngle, 1.0, true )
	else
		self.character:updateAnimation( "spine_bend", 1 - self.cl.headAngle, 1.0, true )
	end

	-- Third person animations

	local currentAnimationExists = false
	for name, animation in pairs( self.cl.animations ) do
		if animation.info then
			animation.time = animation.time + deltaTime
			if animation.info.looping == true then
				if animation.time >= animation.info.duration then
					animation.time = animation.time - animation.info.duration
				end
			end
			
			if name == self.cl.currentAnimation then
				currentAnimationExists = true
				animation.weight = math.min( animation.weight + ( BlendSpeed * deltaTime ), 1.0 )
				if animation.time >= animation.info.duration then
					if animation.nextAnimation then
						self.cl.currentAnimation = animation.nextAnimation
						self.cl.animations[animation.nextAnimation].time = 0
						if animation.nextWeight > 0 then
							animation.weight = 1 - animation.nextWeight
							self.cl.animations[animation.nextAnimation].weight = animation.nextWeight
						end
					else
						self.cl.currentAnimation = ""
					end
				end
			else
				animation.weight = math.max( animation.weight - ( BlendSpeed * deltaTime ), 0.0)
			end

			self.character:updateAnimation( animation.info.name, animation.time, animation.weight )
		end
	end

	if not currentAnimationExists then
		self.cl.currentAnimation = ""
	end

	if self.cl.currentAnimation == "revive" then
		self.character:setMovementWeights( 0, 0 )
	else
		self.character:setMovementWeights( 1, 1 )
	end

	if self.cl.talking then
		if self.character:getCharacterType() == unit_builderguideFarmerko and not self.cl.buildCompleteStage then -- talking before revive
			if self.cl.currentAnimation == "" then
				self.cl.currentAnimation = "ko_talkidle"
			end
		else
			if self.cl.currentAnimation == "" then
				self.cl.currentAnimation = "talkidle"
			end
		end
	end

end

function GenericBuilderQuestCharacter.client_onEvent( self, event )
	self:cl_handleEvent( event )
end

function GenericBuilderQuestCharacter.cl_handleEvent( self, event )
	if not self.cl.graphicsLoaded then
		return
	end

	if event then
		if self.cl.animations[event] then
			self.cl.currentAnimation = event
			self.cl.animations[event].time = 0
		else
			self.cl.currentAnimation = ""
		end
	end
end

function GenericBuilderQuestCharacter.cl_e_onDialogLine( self, params )
	if not self.cl.talking then
		self.cl.talking = true
		if self.character:getCharacterType() == unit_builderguideFarmerko and not self.cl.buildCompleteStage then
			self:cl_setCurrentAnimation( "ko_talkidle" )
		else
			self:cl_setCurrentAnimation( "talkidle" )
		end
	end

	if params.animation then
		self:cl_setCurrentAnimation( params.animation )
	end
end

function GenericBuilderQuestCharacter.cl_e_onDialogEnd( self )
	self.cl.talking = false
	if self.cl.currentAnimation == "talkidle" then
		self:cl_setCurrentAnimation( "" )
	elseif self.character:getCharacterType() == unit_builderguideFarmerko and not self.cl.buildCompleteStage then
		self:cl_setCurrentAnimation( "ko_idle" )
	end

	if sm.isHost then
		if self.cl.questName then
			if not QuestManager.Cl_IsQuestActive( self.cl.questName ) and not QuestManager.Cl_IsQuestComplete( self.cl.questName ) then
				self.network:sendToServer( "sv_n_startQuest" )
			else
				self.network:sendToServer( "sv_n_finishQuest" )
			end
		end
	end
end

function GenericBuilderQuestCharacter.cl_e_onDialogAbort( self )
	self.cl.talking = false
	if self.cl.currentAnimation == "talkidle" then
		self:cl_setCurrentAnimation( "" )
	elseif self.character:getCharacterType() == unit_builderguideFarmerko and not self.cl.buildCompleteStage then
		self:cl_setCurrentAnimation( "ko_idle" )
	end
end
