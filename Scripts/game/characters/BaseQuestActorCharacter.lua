dofile( "$SURVIVAL_DATA/Scripts/game/characters/BaseCharacter.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/managers/QuestEntityManager.lua" )
dofile( "$SURVIVAL_DATA/Scripts/util.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/characters/shared_animation.lua" )

BaseQuestActorCharacter = class( BaseCharacter )

local HeldItemOffset = sm.vec3.new( 0.2, 0, -0.5 )

function BaseQuestActorCharacter.server_onCreate( self )
	BaseCharacter.server_onCreate( self )
	
	self.sv.unit = self.character:getUnit()
	if self.sv.unit then
		sm.event.sendToUnit( self.sv.unit, "sv_e_onSpawnCharacter" )
	end

	print( "-- BaseQuestActorCharacter created --", self.data )

	if self.data and self.data.questMarkerName then
		QuestEntityManager.Sv_RegisterHostedQuestMarker( self.character, sm.vec3.new( 0, 0, 2 ), true, self.data.questMarkerName )
	end
	self.sv.currentCommand = nil

	SafeSet( self.character.publicData, "speakerName", self.data.questUnitName )
end

function BaseQuestActorCharacter.server_onDestroy( self )
	if self.data.questMarkerName then
		QuestEntityManager.Sv_UpdateHostedMarkerBasePosition( self.data.questMarkerName, self.lastKnownLocation )
		QuestEntityManager.Sv_ReleaseHostedQuestMarker( self.data.questMarkerName )
	end
end

function BaseQuestActorCharacter.client_onCreate( self )
	BaseCharacter.client_onCreate( self )
	print( "-- BaseQuestActorCharacter created --" )
	if self.data.questUnitName then
		DialogManager.Cl_RegisterSpeaker( self.character, DialogSpeakerName[self.data.questUnitName] )
	end
	self.lastKnownLocation = self.character.worldPosition
end

function BaseQuestActorCharacter.client_onDestroy( self )
	print( "-- BaseQuestActorCharacter destroyed --" )
	if WorldMarkerManager.Cl_GetMarkerHost( self.data.questMarkerName ) == self.character then
		WorldMarkerManager.Cl_DetachMarker( self.data.questMarkerName )
	end
end

function BaseQuestActorCharacter.client_onRefresh( self )
	print( "-- BaseQuestActorCharacter refreshed --" )
	self:client_onGraphicsLoaded()
end

function BaseQuestActorCharacter.server_onFixedUpdate( self, timeStep )
	-- Track last known location for quest marker updates
	self.lastKnownLocation = self.character.worldPosition

	local actorData = QuestActorManager.Sv_GetActor( SafeGet( self.sv.unit.publicData, "questUnitName" ) )
	if actorData and actorData.stateData.commandList then
		local currentCommand = actorData.stateData.commandList[actorData.stateData.currentCommandIndex]
		if currentCommand then
			if currentCommand.name == "giveItem" or currentCommand.name == "awaitInteraction" or currentCommand.name == "interactiveWait" then
				self.sv.currentCommand = currentCommand
			else
				self.sv.currentCommand = nil
			end
		end
	else
		self.sv.currentCommand = nil
	end
	
	self.network:setClientData(	self.sv.currentCommand, 2 )
end

function BaseQuestActorCharacter.client_onGraphicsLoaded( self )
	BaseCharacter.client_onGraphicsLoaded( self )
end

function BaseQuestActorCharacter.client_onGraphicsUnloaded( self )
	BaseCharacter.client_onGraphicsUnloaded( self )
	
	-- interaction effect cleanup
	if self.cl.giveEffect then
		self.cl.giveEffect:destroy()
		self.cl.giveEffect = nil
	end
	if self.cl.giveInteractionTrigger then
		self.cl.giveInteractionTrigger:destroy()
		self.cl.giveInteractionTrigger = nil
	end
end

function BaseQuestActorCharacter.client_onUpdate( self, deltaTime )
	BaseCharacter.client_onUpdate( self, deltaTime )
	
	if not self.cl.graphicsLoaded then
		return
	end

	-- Handle give item interactions and animations

	local legacyInteractionData = nil
	if self.data and self.data.questUnitName then
		legacyInteractionData = QuestManager.Cl_GetNpcInteractionData( QuestUnits[self.data.questUnitName] )
	end
	local hasLegacyInteraction = legacyInteractionData and ( legacyInteractionData.log or legacyInteractionData.item )
	local hasGiveItemCommand = self.cl.activeCommand and self.cl.activeCommand.name == "giveItem" and not self.cl.activeCommand.complete
	local currentAnimation = self.cl.animator.currentAnimation
	if hasLegacyInteraction or hasGiveItemCommand then
		if currentAnimation ~= "emote_give_in" and currentAnimation ~= "emote_give_loop" then
			self:cl_setCurrentAnimation( "emote_give_loop" )
		end
		
		-- Start effects only when give_loop is playing
		if ( currentAnimation == "emote_give_in" and  self.cl.animator.animations[currentAnimation].time >= 0.35 ) or
			 currentAnimation == "emote_give_loop" then
			self:cl_createGiveInteractionTrigger()
			self:cl_setUpGiveEffect( legacyInteractionData )
		end
	elseif not hasLegacyInteraction and not hasGiveItemCommand then
		if currentAnimation == "emote_give_loop" then
			self:cl_endAnimation( currentAnimation )
		end
		
		-- Stop effect
		if self.cl.giveEffect and self.cl.giveEffect:isPlaying() then
			self.cl.giveEffect:stop()
		end
		if self.cl.giveInteractionTrigger then
			self.cl.giveInteractionTrigger:destroy()
			self.cl.giveInteractionTrigger = nil
		end
	end
end

function BaseQuestActorCharacter.client_canInteract( self )
	if DialogManager.Cl_IsRunning() then
		return false
	end
	--legacy interaction path
	if QuestManager.Cl_NpcCanInteract( QuestUnits[self.data.questUnitName] ) then
		local keyBindingText = sm.gui.getKeyBinding( "Use", true )
		local text = "#{INTERACTION_TALK}"
		if sm.exists( self.cl.giveEffect ) and self.cl.giveEffect:isPlaying() then
			text = "#{INTERACTION_PICK_UP}"
		end
		sm.gui.setInteractionText( "", keyBindingText, text )
		return true
	end
	-- check give item or wait interaction
	if self.cl.activeCommand then
		local commandName = self.cl.activeCommand.name
		local text
		if commandName == "giveItem" then
			text = "#{INTERACTION_PICK_UP}"
		elseif commandName == "interactiveWait" then
			if self.cl.activeCommand.exhausted then
				return false
			end
			text = self.cl.activeCommand.interactionText or "#{INTERACTION_INTERACT}"
		else
			text = self.cl.activeCommand.interactionText or "#{INTERACTION_INTERACT}"
		end
		local keyBindingText = sm.gui.getKeyBinding( "Use", true )
		sm.gui.setInteractionText( "", keyBindingText, text )
		return true
	end
    return false
end

function BaseQuestActorCharacter.client_onInteract( self, character, state )
	if state == true then
		self.network:sendToServer( "sv_n_interact" )
	end
end

function BaseQuestActorCharacter.sv_n_interact( self, _, player )
	local unit = self.character:getUnit()
	if sm.exists( unit ) then
		sm.event.sendToUnit( unit, "sv_e_onInteract", { player = player } )
	end
end

function BaseQuestActorCharacter.client_onClientDataUpdate( self, data, channel )
	BaseCharacter.client_onClientDataUpdate( self, data, channel )
	if channel == 2 then
		local command = data
		if command and ( command.name == "giveItem" or command.name == "awaitInteraction" or command.name == "interactiveWait" )  then
			self.cl.activeCommand = command
		else
			self.cl.activeCommand = nil
		end
	end
end

function BaseQuestActorCharacter.cl_setUpGiveEffect( self, legacyInteractionData )
	if not sm.exists( self.cl.giveEffect ) or not self.cl.giveEffect:isPlaying() then
		if sm.exists( self.cl.giveEffect ) then
			self.cl.giveEffect:destroy() -- destroy before creating new
		end
		if self.cl.activeCommand and self.cl.activeCommand.name == "giveItem" and not self.cl.activeCommand.complete then
			local command = self.cl.activeCommand
			local effectName = nil
			if command.type == "log" then
				effectName = "Questeffects - Quest_lootitem"
			elseif command.type == "item" then
				effectName = "Quest - RewardItem"
			end
			if effectName then
				self:cl_createGiveEffect( effectName, command.shapeRenderableUuid or command.uuid )
			end
		elseif legacyInteractionData and ( legacyInteractionData.log or legacyInteractionData.item ) then
			local effectName = nil
			local uid = nil
			if legacyInteractionData.log then
				effectName = "Questeffects - Quest_lootitem"
				uid = legacyInteractionData.log
			elseif legacyInteractionData.item then
				effectName = "Quest - RewardItem"
				uid = legacyInteractionData.item
			end
			if effectName and uid then
				self:cl_createGiveEffect( effectName, uid )
			end
		end
	end
end

function BaseQuestActorCharacter.cl_createGiveEffect( self, effectName, uid )
	if not effectName or not uid then
		return
	end
	
	self.cl.giveEffect = sm.effect.createEffect( effectName, self.character, self:cl_getGiveItemJoint() )
	self.cl.giveEffect:setOffsetPosition( self:cl_getGiveItemOffset() )
	self.cl.giveEffect:setOffsetRotation( sm.quat.fromEuler( sm.vec3.new( 0, 180, 0 ) ) )
	
	if sm.item.isTool( uid ) then
		uid = GetToolProxyItem( uid )
	end
	self.cl.giveEffect:setParameter( "uuid", uid )
	local bounds = sm.item.getShapeSize( uid )
	local scale = 1.0
	if bounds then
		scale = sm.construction.constants.subdivideRatio / ( ( bounds.x + bounds.y + bounds.z ) / 3.0 );
	end
	self.cl.giveEffect:setScale( sm.vec3.new( scale, scale, scale ) )
	self.cl.giveEffect:start()
end

function BaseQuestActorCharacter.cl_createGiveInteractionTrigger( self )
	if self.cl.giveInteractionTrigger then
		return -- Already exists
	end
	
	local offset = self:cl_getGiveItemOffset()
	local joint = self:cl_getGiveItemJoint()
	
	self.cl.giveInteractionTrigger = sm.areaTrigger.createAttachedSphere( self.character, 0.5, offset, nil, nil, nil, sm.areaTrigger.areaTriggerProxyType.interactable, joint )
	self.cl.giveInteractionTrigger:bindCanInteract( "cl_giveInteractionTrigger_canInteract", self )
	self.cl.giveInteractionTrigger:bindOnInteract( "cl_giveInteractionTrigger_onInteract", self )
end

-- override this to specify a different properties for characters. a bit more explicit than normal variables.

-- override this
function BaseQuestActorCharacter.cl_getGiveItemOffset( self )
	return HeldItemOffset
end

-- override this
function BaseQuestActorCharacter.cl_getGiveItemJoint( self )
	return "jnt_right_hand"
end

-- override this
-- First entry is the animation that begins dialog.
function BaseQuestActorCharacter.cl_getLoopingDialogAnimations( self )
	return "explain_loop"
end

function BaseQuestActorCharacter.cl_giveInteractionTrigger_canInteract( self )
	if DialogManager.Cl_IsRunning() then
		return false
	end
	local keyBindingText = sm.gui.getKeyBinding( "Use", true )
	local text = "#{INTERACTION_PICK_UP}"
	sm.gui.setInteractionText( "", keyBindingText, text )
	return true
end

function BaseQuestActorCharacter.cl_giveInteractionTrigger_onInteract( self, trigger, character, state )
	if state then
		self.network:sendToServer( "sv_n_interact" )
	end
end

function BaseQuestActorCharacter.cl_e_onDialogLine( self, params )
	if not self.cl.graphicsLoaded then
		return
	end
	local currentAnimation = self.cl.animator.currentAnimation
	local dialogAnimations = { self:cl_getLoopingDialogAnimations() }
	local currentlyAnimatingTalking = isAnyOf( currentAnimation, dialogAnimations )
	if currentAnimation == nil or currentlyAnimatingTalking then
		if params.animation then
			self:cl_setCurrentAnimation( params.animation )
        elseif not currentlyAnimatingTalking then
			self:cl_setCurrentAnimation( dialogAnimations[1] )
		end
	end
end

function BaseQuestActorCharacter.cl_e_onDialogEnd( self )
	self:cl_endDialogAnimation()
end

function BaseQuestActorCharacter.cl_e_onDialogAbort( self )
	self:cl_endDialogAnimation()
end

function BaseQuestActorCharacter.cl_endDialogAnimation( self )
	if not self.cl.graphicsLoaded then
		return
	end
	-- ends the current dialog animation if it is a dialog animation, otherwise does nothing.
	local currentAnimation = self.cl.animator.currentAnimation
	local dialogAnimations = { self:cl_getLoopingDialogAnimations() }
	if isAnyOf( currentAnimation, dialogAnimations ) then
		local nextAnimation = self.cl.animator.animations[currentAnimation].nextAnimation
		local nextAnimationIsTalk = isAnyOf( nextAnimation, dialogAnimations )
		if nextAnimationIsTalk then
			-- next animation would lead to more dialog animations. end the animation immediately.
			self.cl.animator.currentAnimation = nil
		else
			-- use nextAnimation as dialog offramp
			self:cl_endAnimation( currentAnimation, nextAnimation )
		end
	end
end