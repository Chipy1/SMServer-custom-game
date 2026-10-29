dofile( "$SURVIVAL_DATA/Scripts/game/characters/BaseQuestWaypointCharacter.lua" )

WarehouseLorenzoCharacter = class( BaseQuestWaypointCharacter )

local InspectionLiftSpawnTime = 0.3
local InspectionLiftDespawnTime = 47.2
local InspectionLiftMaxHeight = 5.75

function WarehouseLorenzoCharacter.client_onCreate( self )
	BaseQuestWaypointCharacter.client_onCreate( self )
	print( "-- WarehouseLorenzoCharacter created --" )
end

function WarehouseLorenzoCharacter.client_onGraphicsLoaded( self )
	
	self.cl.animations = self.cl.animations or {}
	local animTable = self.cl.animations
	local char = self.character
	INIT_ANIMATION( animTable, char, "emote_trashbot_standup" )
	INIT_ANIMATION( animTable, char, "emote_inspectscreen" )
	INIT_ANIMATION( animTable, char, "emote_countdown_in" )
	INIT_ANIMATION( animTable, char, "emote_countdown_loop" )
	INIT_ANIMATION( animTable, char, "emote_countdown_loop_notalk" )
	INIT_ANIMATION( animTable, char, "emote_bash_console" )
	INIT_ANIMATION( animTable, char, "emote_hack_door_in" )
	INIT_ANIMATION( animTable, char, "emote_hack_door_loop" )
	INIT_ANIMATION( animTable, char, "emote_hack_door_out" )
	
	self.cl.gooDripEffect = sm.effect.createEffect( "Lorenzo - Dripping_goo", char, "jnt_head" )
	self.cl.inspectionLiftEffect = sm.effect.createEffect( "Lorenzo - Lift", char, "root_jnt" )
	BaseQuestWaypointCharacter.client_onGraphicsLoaded( self )
end

function WarehouseLorenzoCharacter.client_onGraphicsUnloaded( self )
	BaseQuestWaypointCharacter.client_onGraphicsUnloaded( self )
	if self.cl.gooDripEffect then
		self.cl.gooDripEffect:destroy()
		self.cl.gooDripEffect = nil
	end
	if self.cl.inspectionLiftEffect then
		self.cl.inspectionLiftEffect:destroy()
		self.cl.inspectionLiftEffect = nil
	end
end

function WarehouseLorenzoCharacter.client_onUpdate( self, deltaTime )
	BaseQuestWaypointCharacter.client_onUpdate( self, deltaTime )
	if not self.cl.graphicsLoaded then
		return
	end

	local inspectionLiftVisibility = self.cl.animator.currentAnimation == "emote_inspectscreen" and
									self.cl.animations.emote_inspectscreen.time >= InspectionLiftSpawnTime and
									self.cl.animations.emote_inspectscreen.time <= InspectionLiftDespawnTime
	if inspectionLiftVisibility then
		if not self.cl.inspectionLiftEffect:isPlaying() then
			self.cl.inspectionLiftEffect:start()
		end
		local pose0 = 0.0
		local rootPos = self.character:getTpBonePos( "root_jnt" )
		local heightPos = self.character:getTpBonePos( "jnt_height" )
		if rootPos and heightPos then
			local liftHeight = ( heightPos - rootPos ):length()
			pose0 = clamp( liftHeight / InspectionLiftMaxHeight, 0, 1 )
		end
		self.cl.inspectionLiftEffect:setParameter( "pose0", pose0 )
	else
		if self.cl.inspectionLiftEffect:isPlaying() then
			self.cl.inspectionLiftEffect:stop()
		end
	end
end

function WarehouseLorenzoCharacter.cl_handleEvent( self, event )
	if BaseQuestWaypointCharacter.cl_handleEvent( self, event ) then
		return true
	end

	if event == "goopAwake" then
		self.cl.gooDripEffect:start()
		self:cl_setCurrentAnimation( "emote_trashbot_standup" )
		return true
	end

	return false
end