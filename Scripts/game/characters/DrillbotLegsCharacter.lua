dofile( "$SURVIVAL_DATA/Scripts/util.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/survival_constants.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/managers/DrillbotManager.lua" )

DrillbotLegsCharacter = class( nil )

local KinematicSettings = {
	["upperbody_append_jnt"] = { uuid = sm.uuid.new( "2f0e01ee-a842-43c5-bf71-c9b71f283633" ) }, --lowerbody
}

local CenterRunAnimation = "c_run01"

local BodyToLegAnimation = {
	["ani_left_attackidle"] = "l_run01",
	["ani_left_attack01"] = "l_run01",
	["ani_left_attack02"] = "l_run01",
	["ani_left_attack03"] = "l_run01",
	["ani_left_attack04"] = "l_run01",
	["ani_left_attack05"] = "l_run01",
	["ani_left_attack06"] = "l_run01",
	["ani_left_attack07"] = "l_run01",
	["ani_left_combo01"] = "l_run01",
	["ani_left_combo02"] = "l_run01",

	["ani_right_attackidle"] = "r_run01",
	["ani_right_attack01"] = "r_run01",
	["ani_right_attack02"] = "r_run01",
	["ani_right_attack03"] = "r_run01",
	["ani_right_attack04"] = "r_run01",
	["ani_right_attack05"] = "r_run01",
	["ani_right_attack06"] = "r_run01",
	["ani_right_attack07"] = "r_run01",

	["ani_center_indrill"] = "c_run02",
	["ani_center_drillloop"] = "c_run02",
	["ani_center_outdrill"] = "c_run02",
	["ani_center_inshoot"] = "c_run03",
	["ani_center_shootloop"] = "c_run03",
	["ani_center_outshoot"] = "c_run03",
	["ani_add_shoot_shoot01"] = "c_run03",
	["ani_add_shoot_shoot02"] = "c_run03",
	["ani_add_shoot_shoot03"] = "c_run03"
}

--[[ Server ]]
function DrillbotLegsCharacter.server_onCreate( self )
	self.sv = {}
	self.sv.kinematics = {}
	for boneName, kinematicSetting in pairs( KinematicSettings ) do
		local kinematic = sm.harvestable.createHarvestable( kinematicSetting.uuid, self.character.worldPosition )
		kinematic:setParams( { drillbot = self.character:getUnit() } )
		self.sv.kinematics[boneName] = { kinematic = kinematic }
	end
	self.network:setClientData( { kinematics = self.sv.kinematics }, 1 )
end

function DrillbotLegsCharacter.server_onDestroy( self )
	for _, kinematic in pairs( self.sv.kinematics ) do
		if sm.exists( kinematic.kinematic ) then
			kinematic.kinematic:destroy()
		end
	end
end

--[[ Client ]]
function DrillbotLegsCharacter.client_onCreate( self )
	self.cl = {}
	self.cl.animations = {}
	self.cl.stuckOutLatched = false
	self.cl.previousTrackAnimation = nil

	self.cl.kinematics = {}

	DrillbotManager.Cl_RegisterLowerCharacter( self.character )
end

function DrillbotLegsCharacter.client_onDestroy( self )

end

function DrillbotLegsCharacter.client_onGraphicsLoaded( self )
	self:cl_initAnimations()
	self.character:setGlowMultiplier( 1 )
	if not self.character:isVisible() then
		self.cl.visibilityCountdown = 0.5 -- Delay before showing character to avoid animation pop-in when spawning
	end
	self.cl.graphicsLoaded = true
end

function DrillbotLegsCharacter.client_onGraphicsUnloaded( self )
	self.cl.graphicsLoaded = false
end

function DrillbotLegsCharacter.cl_initAnimations( self )
	self.cl.animationsLoaded = true
	self.cl.blendSpeed = 5.0

	local initAnimation = function( animationName, time, weight )
		if not self.cl.animations[animationName] then
			self.cl.animations[animationName] = {
				info = self.character:getAnimationInfo( animationName ),
				time = time or 0,
				weight = weight or 0
			}
		end
	end

	initAnimation( "c_run01" )
	initAnimation( "c_run02" )
	initAnimation( "c_run03" )

	initAnimation( "r_run_in" )
	initAnimation( "r_run01" )
	initAnimation( "r_run_out" )

	initAnimation( "l_run_in" )
	initAnimation( "l_run01" )
	initAnimation( "l_run_out" )

	initAnimation( "enter_start" )
	initAnimation( "enter_ceiling" )
	initAnimation( "enter_wall_right" )
	initAnimation( "enter_wall_left" )
	initAnimation( "enter_floor" )
	initAnimation( "enter_destructcinematic" )

	initAnimation( "stuck_in_prep" )
	initAnimation( "stuck_in" )
	initAnimation( "stuck_loop" )
	initAnimation( "stuck_out" )
	initAnimation( "stuck_out_loop" )
	initAnimation( "stuck_out_run" )

end

function DrillbotLegsCharacter.cl_selectLegAnimationFromBody( self, bodyAnimationName )
	if bodyAnimationName == nil then
		return CenterRunAnimation
	end
	return BodyToLegAnimation[bodyAnimationName] or ( self.cl.animations[bodyAnimationName] and bodyAnimationName ) or CenterRunAnimation
end

function DrillbotLegsCharacter.client_onUpdate( self, deltaTime )
	if not self.cl.graphicsLoaded then
		return
	end


	-- Toggle visibility
	if self.cl.visibilityCountdown then
		self.cl.visibilityCountdown = self.cl.visibilityCountdown - deltaTime
		if self.cl.visibilityCountdown <= 0 then
			self.character:setVisible( true )
			self.cl.visibilityCountdown = nil
		end
	end

	-- Get upper character's current animation
	local upperCharacter = DrillbotManager.Cl_GetUpperCharacter()
	local bodyAnimationName = nil
	local bodyAnimationPlayRate = 1.0
	if sm.exists( upperCharacter ) then
		bodyAnimationName = SafeGet( upperCharacter.clientPublicData, "currentAnimation" )
		bodyAnimationPlayRate = SafeGet( upperCharacter.clientPublicData, "playRate" ) or bodyAnimationPlayRate
	end
	local selectedAnimationName = self:cl_selectLegAnimationFromBody( bodyAnimationName )

	-- Check for animations from the track
	local trackData = DrillbotManager.Cl_GetTrackData()
	local trackAnimationName = trackData and trackData.legsAnimationName or nil
	trackAnimationName = trackAnimationName ~= "" and trackAnimationName or nil -- Empty string same as no animation
	local bodyAnimationTrackOverride = nil
	if trackAnimationName and isAnyOf( trackAnimationName, DrillbotManager.DrillbotTrackOverrideAnimations ) then
		-- Special animation set by track
		bodyAnimationTrackOverride = trackAnimationName
	end

	-- Detect if stuck_out animation finished (track ended while playing stuck_out)
	self.cl.stuckOutLatched = self.cl.stuckOutLatched or ( self.cl.previousTrackAnimation == "stuck_out" and not ( trackData and bodyAnimationTrackOverride == "stuck_out" ) )
	self.cl.previousTrackAnimation = ( trackData and bodyAnimationTrackOverride ) or nil
	if self.cl.stuckOutLatched then
		-- After stuck_out the drillbot will be destroyed so stop updating animations
		return
	end

	for name, animation in pairs( self.cl.animations ) do
		if animation.info then
			if trackData and bodyAnimationTrackOverride then
				-- Play animation from track
				if name == bodyAnimationTrackOverride then
					animation.time = trackData.trackProgress * animation.info.duration
					animation.weight = 1
				else
					animation.weight = 0
					animation.time = 0.0
				end
			elseif selectedAnimationName then
				if name == selectedAnimationName then
					animation.time = ( animation.time + deltaTime * bodyAnimationPlayRate )
					if animation.info and animation.info.looping then
						animation.time = animation.time % animation.info.duration
					end
					animation.weight = 1
				else
					animation.weight = 0
					animation.time = 0.0
				end
			else
				animation.weight = 0
				animation.time = 0.0
			end

			self.character:updateAnimation( animation.info.name, animation.time, animation.weight, animation.additive )
		end
	end
end

function DrillbotLegsCharacter.client_onEvent( self, event )
	self:cl_handleEvent( event )
end

function DrillbotLegsCharacter.cl_handleEvent( self, event )
	if not self.cl.animationsLoaded then return end
end

function DrillbotLegsCharacter.client_onClientDataUpdate( self, clientData, channel )
	self.cl.kinematics = clientData.kinematics
end

function DrillbotLegsCharacter.client_onFixedUpdate( self )
	self:cl_updateKinematics()
end

function DrillbotLegsCharacter.cl_updateKinematics( self )
	for boneName, kinematicSetting in pairs( KinematicSettings ) do
		if self.cl.kinematics[boneName] and sm.exists( self.cl.kinematics[boneName].kinematic ) then
			local bonePosition = self.character:getTpBonePos( boneName )
			local boneRotation = self.character:getTpBoneRot( boneName )
			if bonePosition and boneRotation then
				self.cl.kinematics[boneName].kinematic:setPosition( bonePosition )
				self.cl.kinematics[boneName].kinematic:setRotation( boneRotation )
			end
		end
	end
end