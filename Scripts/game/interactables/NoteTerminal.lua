-- NoteTerminal.lua --
dofile( "$SURVIVAL_DATA/Scripts/game/managers/QuestManager.lua" )

NoteTerminal = class( nil )
NoteTerminal.maxParentCount = 1
NoteTerminal.maxChildCount = 0
NoteTerminal.colorNormal = sm.color.new( 0xdeadbeef )
NoteTerminal.colorHighlight = sm.color.new( 0xdeadbeef )
NoteTerminal.connectionInput = sm.interactable.connectionType.logic
NoteTerminal.connectionOutput = sm.interactable.connectionType.none
NoteTerminal.poseWeightCount = 1

local UnfoldSpeed = 5

-- Client

function NoteTerminal.client_onCreate( self )
	self.cl = {}
	self.cl.unfoldWeight = 0
	self.cl.activeEffect = sm.effect.createEffect( "NoteTerminal - Active", self.interactable )
end

function NoteTerminal.client_canInteract( self )
	local quest = QuestManager.Cl_GetActiveQuest( "quest_tutorial" )
	if quest and sm.exists( quest ) and quest.clientPublicData then
		return quest.clientPublicData.canUseNoteTerminal == true
	end
	return false
end

function NoteTerminal.sv_n_interact( self, character, state )
	if QuestManager.Sv_IsQuestActive( "quest_tutorial" ) then
		QuestManager.Sv_SendEvent( "event.quest_tutorial.note_terminal_used" )
	end
end

function NoteTerminal.client_onInteract( self, character, state )
	if state == true then
		sm.effect.playEffect( "NoteTerminal - Interact", self.shape.worldPosition )
		self.network:sendToServer( "sv_n_interact" )
	end
end

function NoteTerminal.client_onUpdate( self, deltaTime )
	local parent = self.interactable:getSingleParent()
	local shouldOpen = false
	if QuestManager.Cl_IsQuestComplete( "quest_tutorial" ) then
		shouldOpen = true
	else
		local quest = QuestManager.Cl_GetActiveQuest( "quest_tutorial" )
		if quest and sm.exists( quest ) and quest.clientPublicData then
			shouldOpen = quest.clientPublicData.openNoteTerminal
		end
	end
	if parent and parent.active then
		if self.cl.unfoldWeight < 1.0 and shouldOpen then
			if( self.cl.unfoldWeight <= 0.0 ) then 
				sm.effect.playEffect( "audio:event:/props/installations/doors/terminal_small_open", self.shape.worldPosition )
			end
			self.cl.unfoldWeight = math.min( self.cl.unfoldWeight + deltaTime * UnfoldSpeed, 1.0 )
			self.interactable:setPoseWeight( 0, self.cl.unfoldWeight )
		end
	else
		if self.cl.unfoldWeight > 0.0 then
			self.cl.unfoldWeight = math.max( self.cl.unfoldWeight - deltaTime * UnfoldSpeed, 0.0 )
			self.interactable:setPoseWeight( 0, self.cl.unfoldWeight )
		end
	end

	local canUseNoteTerminal = false
	local quest = QuestManager.Cl_GetActiveQuest( "quest_tutorial" )
	if quest and sm.exists( quest ) and quest.clientPublicData then
		canUseNoteTerminal = quest.clientPublicData.canUseNoteTerminal == true
	end

	local playActiveEffect = parent and parent.active and shouldOpen and canUseNoteTerminal
	if playActiveEffect and not self.cl.activeEffect:isPlaying() then
		self.cl.activeEffect:start()
	elseif not playActiveEffect and self.cl.activeEffect:isPlaying() then
		self.cl.activeEffect:stop()
	end
end 