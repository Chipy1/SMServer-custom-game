dofile( "$SURVIVAL_DATA/Scripts/game/characters/BaseCharacter.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/characters/shared_animation.lua" )

BaseQuestWaypointCharacter = class( BaseCharacter )

local HeldItemOffset = sm.vec3.new( 0.2, 0, -0.5 )

function BaseQuestWaypointCharacter.server_onCreate( self )
	BaseCharacter.server_onCreate( self )
	
	self.sv.unit = self.character:getUnit()
	if self.sv.unit then
		sm.event.sendToUnit( self.sv.unit, "sv_e_onSpawnCharacter" )
	end
	QuestEntityManager.Sv_RegisterHostedQuestMarker( self.character, sm.vec3.new( 0, 0, 2 ), true, self.data.questMarkerName )
	self.sv.waitInteraction = nil
	self.sv.giveItem = nil -- this will be a new name to replace waitInteraction
end

function BaseQuestWaypointCharacter.client_onCreate( self )
	BaseCharacter.client_onCreate( self )
	print( "-- BaseQuestWaypointCharacter created --" )
	if self.data.questMarkerName then
		QuestEntityManager.Cl_BumpHostedQuestMarker( self.data.questMarkerName )
	end
	if self.data.questUnitName then
		DialogManager.Cl_RegisterSpeaker( self.character, DialogSpeakerName[self.data.questUnitName] )
	end
	self.cl.waitInteraction = nil
end

function BaseQuestWaypointCharacter.client_onDestroy( self )
	print( "-- BaseQuestWaypointCharacter destroyed --" )
	WorldMarkerManager.Cl_DetachMarker( self.data.questMarkerName )
end

function BaseQuestWaypointCharacter.client_onRefresh( self )
	print( "-- BaseQuestWaypointCharacter refreshed --" )
end

function BaseQuestWaypointCharacter.server_onFixedUpdate( self, timeStep )
	if self.sv.waitInteraction ~= self.character.publicData.waitInteraction then
		self.network:setClientData( { waitInteraction = self.character.publicData.waitInteraction }, 1 )
	end
	self.sv.waitInteraction = self.character.publicData.waitInteraction
end

function BaseQuestWaypointCharacter.client_onGraphicsLoaded( self )
	self.cl.animations = self.cl.animations or {}
	INIT_ANIMATION_REND( self.cl.animations, self.character, "char_male_tp_npc_emote" )
	-- Create master key effect for wait interactions
	self.cl.masterKeyEffect = sm.effect.createEffect( "Lorenzo - Lootitem_masterkey", self.character, self:cl_getGiveItemJoint() )
	BaseCharacter.client_onGraphicsLoaded( self )
end

function BaseQuestWaypointCharacter.client_onGraphicsUnloaded( self )
	BaseCharacter.client_onGraphicsUnloaded( self )
	if self.cl.masterKeyEffect then
		self.cl.masterKeyEffect:destroy()
		self.cl.masterKeyEffect = nil
	end
	if self.cl.waitInteractionTrigger then
		self.cl.waitInteractionTrigger:destroy()
		self.cl.waitInteractionTrigger = nil
	end
end

function BaseQuestWaypointCharacter.client_onUpdate( self, deltaTime )
	BaseCharacter.client_onUpdate( self, deltaTime )
	
	if not self.cl.graphicsLoaded then
		return
	end

	-- Handle waitInteraction animations
	local currentAnimation = self.cl.animator.currentAnimation
	if self.cl.waitInteraction and self.cl.waitInteraction.animate then
		if currentAnimation ~= "emote_give_in" and currentAnimation ~= "emote_give_loop" then
			-- Start giving animation
			self:cl_setCurrentAnimation( "emote_give_loop" )
		end
		-- Start master key effect if it exists
		if self.cl.masterKeyEffect and not self.cl.masterKeyEffect:isPlaying() then
			self.cl.masterKeyEffect:start()
		end
	else
		if currentAnimation == "emote_give_loop" then
			-- Stop giving animation
			self:cl_endAnimation( currentAnimation )
		end
		-- Stop master key effect if it exists
		if self.cl.masterKeyEffect and self.cl.masterKeyEffect:isPlaying() then
			self.cl.masterKeyEffect:stop()
		end
	end
end



function BaseQuestWaypointCharacter.client_canInteract( self )
	if DialogManager.Cl_IsRunning() then
		return false
	end
	if self.cl.waitInteraction then
		local text = self.cl.waitInteraction.text or "#{INTERACTION_INTERACT}"
		local keyBindingText = sm.gui.getKeyBinding( "Use", true )
		sm.gui.setInteractionText( "", keyBindingText, text )
		return true
	end
    return false
end

function BaseQuestWaypointCharacter.client_onInteract( self, character, state )
	if state == true then
		self.network:sendToServer( "sv_n_interact" )
	end
end

function BaseQuestWaypointCharacter.sv_n_interact( self, _, player )
	local unit = self.character:getUnit()
	if sm.exists( unit ) then
		sm.event.sendToUnit( unit, "sv_e_onInteract", { player = player } )
	end
end

function BaseQuestWaypointCharacter.client_onClientDataUpdate( self, data, channel )
	BaseCharacter.client_onClientDataUpdate( self, data, channel )
	if channel == 1 then
		self.cl.waitInteraction = data.waitInteraction and data.waitInteraction or nil
		if self.cl.waitInteraction and self.cl.waitInteraction.animate then
			self:cl_createWaitInteractionTrigger()
		elseif self.cl.waitInteractionTrigger then
			self.cl.waitInteractionTrigger:destroy()
			self.cl.waitInteractionTrigger = nil
		end
	end
end

function BaseQuestWaypointCharacter.cl_createWaitInteractionTrigger( self )
	if self.cl.waitInteractionTrigger then
		return -- Already exists
	end
	
	local offset = self:cl_getGiveItemOffset()
	local joint = self:cl_getGiveItemJoint()
	
	self.cl.waitInteractionTrigger = sm.areaTrigger.createAttachedSphere( self.character, 0.5, offset, nil, nil, nil, sm.areaTrigger.areaTriggerProxyType.interactable, joint )
	self.cl.waitInteractionTrigger:bindCanInteract( "cl_waitInteractionTrigger_canInteract", self )
	self.cl.waitInteractionTrigger:bindOnInteract( "cl_waitInteractionTrigger_onInteract", self )
end

-- override this
function BaseQuestWaypointCharacter.cl_getGiveItemOffset( self )
	return HeldItemOffset
end

-- override this
function BaseQuestWaypointCharacter.cl_getGiveItemJoint( self )
	return "jnt_right_hand" -- Default joint, can be overridden
end

function BaseQuestWaypointCharacter.cl_waitInteractionTrigger_canInteract( self )
	local keyBindingText = sm.gui.getKeyBinding( "Use", true )
	local text = "#{INTERACTION_PICK_UP}"
	sm.gui.setInteractionText( "", keyBindingText, text )
	return true
end

function BaseQuestWaypointCharacter.cl_waitInteractionTrigger_onInteract( self, trigger, character, state )
	if state then
		self.network:sendToServer( "sv_n_interact" )
	end
end