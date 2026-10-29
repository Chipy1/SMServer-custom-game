dofile( "$SURVIVAL_DATA/Scripts/util.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/survival_constants.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/managers/DrillbotManager.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/survival_collections.lua" )

DrillbotCharacter = class( nil )


local DamageTickCooldown = 5
local DrillAcceleration = 20.0
local DrillMaxBouncyVelocity = 20.0
local DrillMaxVelocity = 6.5
local DrillXWidthMultiplier = 1/DRILLBOT_ARENA_WIDTH -- Based on the width of the drill area (scales the fractional movement speed)
local DrillZDepthMultiplier = 1/DRILLBOT_ARENA_LENGTH -- Based on the depth of the drill area (scales the fractional movement speed)
local DrillDampeningDistance = 8.0 -- Distance where dampening will occur
local DrillDamage = 10
local DrillBounces = 6

local ScytheAttackDelay = 2.5
local ScytheDamage = 35
local ScytheSwingsBeforeAbort = 3
local ComboSwingsBeforeAbort = 1

local AimAcceleration = 15.0
local AimMaxVelocity = 8.0
local AimXWidthMultiplier = 1/DRILLBOT_ARENA_WIDTH -- Based on the width of the aim area (scales the fractional movement speed)
local AimDampeningDistance = 5.0 -- Distance where dampening will occur
local AimDampeningFactor = 0.75
local ShotsBeforeAbort = 5
local MagmaBallDelay = 0.6
local MagmaBallUuid = sm.uuid.new( "d8c1819f-14ed-48cc-9ef5-ae148271d74c" )
local MagmaBallHeightOffset = 4

local AttackCatchupGain = 2.0
local AttackCatchupMaxPlayRate = 3.0
local GameTickRate = 40

local KinematicSettings = {
	["spine01_jnt"] = { uuid = sm.uuid.new( "abbb4d72-3ed1-44b8-9f31-ec206acdbdbd" ) }, --back section
	["spine07_jnt"] = { uuid = sm.uuid.new( "d637c2ba-abfa-4a90-8b8b-4aa137be9247" ) }, --mid section
	["left_arm02_jnt"] = { uuid = sm.uuid.new( "742c38b4-6558-4de6-96fd-3cf93cd9c4ea" ) }, --arm01
	["left_arm03_jnt"] = { uuid = sm.uuid.new( "3d359e3a-95f9-46e3-adf1-01749960c2d9" ) }, --arm02
	["left_arm04_jnt"] = { uuid = sm.uuid.new( "9c03f4dd-73f3-4616-9749-28bb662b3e53" ) }, --scythe
	["right_arm02_jnt"] = { uuid = sm.uuid.new( "aeecdda7-4b3b-4bdd-b79a-5481de80790d" ) }, --arm01
	["right_arm03_jnt"] = { uuid = sm.uuid.new( "16957bb2-c61c-4943-9995-90a3814194d4" ) }, --arm02
	["right_arm04_jnt"] = { uuid = sm.uuid.new( "58254360-dad3-4d83-a05c-f242c9632a52" ) }, --scythe
	["head_rot_jnt"] = { uuid = sm.uuid.new( "c40877e2-70cb-4a20-89bb-b5121d6fad79" ) }, --head
	["drill_jnt"] = { uuid = sm.uuid.new( "cb69a434-0809-4315-aaaa-b3d9ea8311ae" ) }, --drill
}

local CenterRunAnimation = "c_run01"

local AttackStateAnimations =
{
	[DrillbotAttack.DELAY] = nil, -- DELAY follows the track
	[DrillbotAttack.ATTACK_LEFT] =
	{
		inAnimation = "l_run_in",
		idleAnimation = "ani_left_attackidle",
		outAnimation = "l_run_out"
	},
	[DrillbotAttack.ATTACK_RIGHT] =
	{
		inAnimation = "r_run_in",
		idleAnimation = "ani_right_attackidle",
		outAnimation = "r_run_out"
	},
	[DrillbotAttack.DRILL] =
	{
		inAnimation = "ani_center_indrill",
		idleAnimation = "ani_center_drillloop",
		outAnimation = "ani_center_outdrill"
	},
	[DrillbotAttack.SHOOT] =
	{
		inAnimation = "ani_center_inshoot",
		idleAnimation = "ani_center_shootloop",
		outAnimation = "ani_center_outshoot"
	},
	[DrillbotAttack.COMBO_LEFT01] =
	{
		inAnimation = "l_run_in",
		idleAnimation = "ani_left_attackidle",
		outAnimation = "l_run_out"
	},
	[DrillbotAttack.COMBO_LEFT02] =
	{
		inAnimation = "l_run_in",
		idleAnimation = "ani_left_attackidle",
		outAnimation = "l_run_out"
	}
}

ScytheLeftAttacks = {
	"ani_left_attack01",
	"ani_left_attack02",
	"ani_left_attack03",
	"ani_left_attack04",
	"ani_left_attack05",
	"ani_left_attack06",
	"ani_left_attack07"
}
ScytheRightAttacks = {
	"ani_right_attack01",
	"ani_right_attack02",
	"ani_right_attack03",
	"ani_right_attack04",
	"ani_right_attack05",
	"ani_right_attack06",
	"ani_right_attack07"
}
local ScytheTriggerIndices = 7

ComboLeftAttacks = {
	"ani_left_combo01",
	"ani_left_combo02"
}
local ComboDelays = {
	{ --Combo01
		[1] = 1.7,
		[2] = 3.0,
		[3] = 4.2,
		[4] = 5.5,
		[5] = 6.8,
		[6] = 8.0,
		[7] = 10.25,
	},
	{ --Combo02
		[1] = 5.16,
		[2] = 3.4,
		[3] = 5.16,
		[4] = nil,
		[5] = 1.66,
		[6] = 3.4,
		[7] = 1.66,
	}
}

local function ResolveDrillbotTarget( bossState )
	local targetPlayer = bossState and bossState.targetPlayer or nil
	if targetPlayer and sm.exists( targetPlayer ) and sm.exists( targetPlayer.character ) then
		return targetPlayer.character
	end

	local hostPlayer = sm.player.getHostPlayer()
	if hostPlayer and sm.exists( hostPlayer ) and sm.exists( hostPlayer.character ) then
		return hostPlayer.character
	end

	return nil
end

local function GetCatchupRate( expectedProgress, localProgress )
	if not expectedProgress or not localProgress then
		return 1.0
	end
	local lag = expectedProgress - localProgress
	if lag <= 0 then
		return 1.0
	end
	return clamp( 1.0 + lag * AttackCatchupGain, 1.0, AttackCatchupMaxPlayRate )
end

--[[ Server ]]
function DrillbotCharacter.server_onCreate( self )
	self.sv = {}
	self.sv.kinematics = {}
end

function DrillbotCharacter.server_onDestroy( self )
	for _, kinematic in pairs( self.sv.kinematics ) do
		if sm.exists( kinematic.kinematic ) then
			kinematic.kinematic:destroy()
		end
	end
end

function DrillbotCharacter.server_onFixedUpdate( self, dt )
	local updated = false
	for boneName, kinematicSetting in pairs( KinematicSettings ) do
		if self.sv.kinematics[boneName] == nil or not sm.exists( self.sv.kinematics[boneName].kinematic ) then
			local bonePosition = self.character:getTpBonePos( boneName )
			local boneRotation = self.character:getTpBoneRot( boneName )
			local kinematic = sm.harvestable.createHarvestable( kinematicSetting.uuid, bonePosition, boneRotation )
			self.sv.kinematics[boneName] = { kinematic = kinematic }
			updated = true
		end
	end
	if updated then
		self.network:setClientData( { kinematics = self.sv.kinematics }, 1 )
	end
end

--[[ Client ]]
function DrillbotCharacter.client_onCreate( self )
	self.cl = {}
	self.cl.animations = {}
	self.cl.stuckOutLatched = false
	self.cl.previousTrackAnimation = nil

	self.cl.attackStateRevision = 0
	self.cl.currentAttackState = nil
	self.cl.desiredAttackState = nil
	self.cl.desiredAttackStartTick = nil

	self.cl.relativeDrillVelocity = sm.vec3.new( 0, 0, 0 )
	self.cl.damagedCharacters = {}
	self.cl.drillBounces = 0

	self.cl.scytheSwingsLeft = 0
	self.cl.scytheSwingsRight = 0

	self.cl.relativeAimVelocity = sm.vec3.zero()
	self.cl.shotsFired = 0

	self.cl.cartTriggerDelaysComboLeft01 = {}
	self.cl.cartTriggerDelaysComboLeft02 = {}
	self.cl.scytheSwingsComboLeft01 = 0
	self.cl.scytheSwingsComboLeft02 = 0

	self.cl.kinematics = {}

	self.character.clientPublicData = self.character.clientPublicData or {}
	self.character.clientPublicData.currentAnimation = nil

	DrillbotManager.Cl_RegisterUpperCharacter( self.character )
end

function DrillbotCharacter.client_onDestroy( self )

end

function DrillbotCharacter.client_onGraphicsLoaded( self )
	self:cl_initAnimations()
	self.character:setGlowMultiplier( 1 )
	self.cl.graphicsLoaded = true
	self.cl.drillLoopEffect = sm.effect.createEffect( "Drillbot - drill_loop01", self.character, "drill_jnt", sm.effect.axis.yaxis )
	self.cl.drillImpactEffect = sm.effect.createEffect( "Drillbot - drill_impact01" )
	if not self.character:isVisible() then
		self.cl.visibilityCountdown = 0.5 -- Delay before showing character to avoid animation pop-in when spawning
	end
end

function DrillbotCharacter.client_onGraphicsUnloaded( self )
	self.cl.graphicsLoaded = false
	if self.cl.drillStartupEffect then
		self.cl.drillStartupEffect:destroy()
		self.cl.drillStartupEffect = nil
	end
	if self.cl.drillLoopEffect then
		self.cl.drillLoopEffect:destroy()
		self.cl.drillLoopEffect = nil
	end
	if self.cl.drillImpactEffect then
		self.cl.drillImpactEffect:destroy()
		self.cl.drillImpactEffect = nil
	end
	if sm.exists( self.character ) then
		self.character:removeAnimationCallbacks()
	end
end

function DrillbotCharacter.cl_initAnimations( self )
	self.cl.animationsLoaded = true
	self.cl.blendSpeed = 5.0
	self.cl.blendTime = 0.2

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
	initAnimation( "l_run_in" )
	initAnimation( "l_run_out" )
	initAnimation( "r_run_in" )
	initAnimation( "r_run_out" )

	initAnimation( "enter_start" )
	initAnimation( "enter_ceiling" )
	initAnimation( "enter_wall_right" )
	initAnimation( "enter_wall_left" )
	initAnimation( "enter_floor" )
	initAnimation( "enter_destructcinematic" )
	initAnimation( "ani_destructcinematic" )

	initAnimation( "stuck_in_prep" )
	initAnimation( "stuck_in" )
	initAnimation( "stuck_loop" )
	initAnimation( "stuck_out" )
	initAnimation( "stuck_out_loop")
	initAnimation( "stuck_out_run" )

	-- Special animations
	if not self.cl.stuck_hit then
		self.cl.stuck_hit = {
			info = self.character:getAnimationInfo( "stuck_hit" ),
			time = 0,
			weight = 0
		}
	end

	initAnimation( "ani_center_indrill" )
	initAnimation( "ani_center_outdrill" )
	initAnimation( "ani_center_drillloop" )
	if not self.cl.drillXBendAnimation then
		self.cl.drillXBendAnimation = {
			info = self.character:getAnimationInfo( "ani_add_drill_xaxis_bend" ),
			time = 0.5,
			weight = 0
		}
	end
	if not self.cl.drillZBendAnimation then
		self.cl.drillZBendAnimation = {
			info = self.character:getAnimationInfo( "ani_add_drill_zaxis_bend" ),
			time = 0.0,
			weight = 0
		}
	end

	initAnimation( "ani_center_inshoot" )
	initAnimation( "ani_center_outshoot" )
	initAnimation( "ani_center_shootloop" )
	if not self.cl.shootXBendAnimation then
		self.cl.shootXBendAnimation = {
			info = self.character:getAnimationInfo( "ani_add_shoot_xaxis_bend" ),
			time = 0.5,
			weight = 0
		}
	end
	initAnimation( "ani_add_shoot_shoot01" )
	initAnimation( "ani_add_shoot_shoot02" )
	initAnimation( "ani_add_shoot_shoot03" )

	initAnimation( "ani_left_inattack" )
	initAnimation( "ani_left_outattack" )
	initAnimation( "ani_left_attackidle" )

	initAnimation( "ani_right_inattack" )
	initAnimation( "ani_right_outattack" )
	initAnimation( "ani_right_attackidle" )
	initAnimation( "ani_left_attack01" )
	initAnimation( "ani_left_attack02" )
	initAnimation( "ani_left_attack03" )
	initAnimation( "ani_left_attack04" )
	initAnimation( "ani_left_attack05" )
	initAnimation( "ani_left_attack06" )
	initAnimation( "ani_left_attack07" )

	initAnimation( "ani_right_attack01" )
	initAnimation( "ani_right_attack02" )
	initAnimation( "ani_right_attack03" )
	initAnimation( "ani_right_attack04" )
	initAnimation( "ani_right_attack05" )
	initAnimation( "ani_right_attack06" )
	initAnimation( "ani_right_attack07" )

	initAnimation( "ani_left_combo01" )
	initAnimation( "ani_left_combo02" )

	self.cl.attackEventAnimation = nil

	self.character:bindAnimationCallback( "ani_center_shootloop", MagmaBallDelay, "cl_e_shootEvent" )

	self.character:bindAnimationCallback( "ani_left_attack01", ScytheAttackDelay, "cl_e_scytheAttackEvent" )
	self.character:bindAnimationCallback( "ani_left_attack02", ScytheAttackDelay, "cl_e_scytheAttackEvent" )
	self.character:bindAnimationCallback( "ani_left_attack03", ScytheAttackDelay, "cl_e_scytheAttackEvent" )
	self.character:bindAnimationCallback( "ani_left_attack04", ScytheAttackDelay, "cl_e_scytheAttackEvent" )
	self.character:bindAnimationCallback( "ani_left_attack05", ScytheAttackDelay, "cl_e_scytheAttackEvent" )
	self.character:bindAnimationCallback( "ani_left_attack06", ScytheAttackDelay, "cl_e_scytheAttackEvent" )
	self.character:bindAnimationCallback( "ani_left_attack07", ScytheAttackDelay, "cl_e_scytheAttackEvent" )

	self.character:bindAnimationCallback( "ani_right_attack01", ScytheAttackDelay, "cl_e_scytheAttackEvent" )
	self.character:bindAnimationCallback( "ani_right_attack02", ScytheAttackDelay, "cl_e_scytheAttackEvent" )
	self.character:bindAnimationCallback( "ani_right_attack03", ScytheAttackDelay, "cl_e_scytheAttackEvent" )
	self.character:bindAnimationCallback( "ani_right_attack04", ScytheAttackDelay, "cl_e_scytheAttackEvent" )
	self.character:bindAnimationCallback( "ani_right_attack05", ScytheAttackDelay, "cl_e_scytheAttackEvent" )
	self.character:bindAnimationCallback( "ani_right_attack06", ScytheAttackDelay, "cl_e_scytheAttackEvent" )
	self.character:bindAnimationCallback( "ani_right_attack07", ScytheAttackDelay, "cl_e_scytheAttackEvent" )
end

function DrillbotCharacter.cl_e_shootEvent( self, animationName )
	if sm.isHost then
		local fightCenter = DrillbotManager.Cl_GetFightCenter()
		if fightCenter then
			-- Convert animation time to an aim offset based on the cart width
			local cartAimOffset = ( self.cl.shootXBendAnimation.time - 0.5 ) * DRILLBOT_ARENA_WIDTH
			local arenaLengthMarginOffset = 6 -- Offset to spawn the ball on the margin area of the arena
			local arenaOffset = sm.vec3.new( 0, -DRILLBOT_ARENA_LENGTH * 0.5 - arenaLengthMarginOffset, DRILLBOT_ARENA_HEIGHT * 0.5 + MagmaBallHeightOffset )
			local xAxis = sm.vec3.new( 1, 0, 0 )
			local cartLandingPosition = fightCenter + arenaOffset + xAxis * cartAimOffset
			local headBonePosition = self.character:getTpBonePos( "head_rot_jnt" )
			self.network:sendToServer( "sv_n_spawnMagmaBall", { spawnPosition = headBonePosition, cartLandingPosition = cartLandingPosition } )
		end
	end
	self.cl.shotsFired = self.cl.shotsFired + 1
end

function DrillbotCharacter.cl_e_scytheAttackEvent( self, animationName )
	local numberString = animationName:match("%d+$")
    if numberString then
		local attackIndex = tonumber( numberString )
		-- Animation to trigger is reversed
		local revScytheIndex = ScytheTriggerIndices - attackIndex + 1
		self:cl_scytheAttack( revScytheIndex )
	end
end

function DrillbotCharacter.client_onUpdate( self, deltaTime )
	if not self.cl.graphicsLoaded then
		return
	end

	local currentTick = sm.game.getServerTick()

	-- Toggle visibility
	if self.cl.visibilityCountdown then
		self.cl.visibilityCountdown = self.cl.visibilityCountdown - deltaTime
		if self.cl.visibilityCountdown <= 0 then
			self.character:setVisible( true )
			self.cl.visibilityCountdown = nil
		end
	end

	-- Check for body animations from the track
	local trackData = DrillbotManager.Cl_GetTrackData()
	local trackAnimationName = trackData and trackData.bodyAnimationName or nil
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

	-- Check if the attack is ending
	local forceBodyOutAnimation = nil
	if self.cl.attackEventAnimation == nil and self.cl.currentAttackState then
		local currentAnimationState = AttackStateAnimations[self.cl.currentAttackState]
		if currentAnimationState then
			if self.cl.currentAttackState == DrillbotAttack.ATTACK_LEFT and self.cl.scytheSwingsLeft >= ScytheSwingsBeforeAbort then
				forceBodyOutAnimation = currentAnimationState.outAnimation
			elseif self.cl.currentAttackState == DrillbotAttack.ATTACK_RIGHT and self.cl.scytheSwingsRight >= ScytheSwingsBeforeAbort then
				forceBodyOutAnimation = currentAnimationState.outAnimation
			elseif self.cl.currentAttackState == DrillbotAttack.COMBO_LEFT01 and self.cl.scytheSwingsComboLeft01 >= ComboSwingsBeforeAbort then
				forceBodyOutAnimation = currentAnimationState.outAnimation
			elseif self.cl.currentAttackState == DrillbotAttack.COMBO_LEFT02 and self.cl.scytheSwingsComboLeft02 >= ComboSwingsBeforeAbort then
				forceBodyOutAnimation = currentAnimationState.outAnimation
			elseif self.cl.currentAttackState == DrillbotAttack.SHOOT and self.cl.shotsFired >= ShotsBeforeAbort then
				forceBodyOutAnimation = currentAnimationState.outAnimation
			end
			if sm.isHost then
				if forceBodyOutAnimation and not self.cl.abortSignalSent then
					self.network:sendToServer( "sv_n_stopAttack" )
					self.cl.abortSignalSent = true
				end
			end
		end
	end

	-- Check for animations from attacks
	local attackStateAnimation = nil
	local bossState = DrillbotManager.Cl_GetBossState()
	local attackStateRevision = bossState and bossState.attackStateRevision or nil
	local retainAttackState = false
	self.cl.desiredAttackState = bossState and bossState.attackState or nil
	self.cl.desiredAttackStartTick = bossState and bossState.attackStartTick or nil
	local attackHasStarted = self.cl.desiredAttackStartTick ~= nil and currentTick >= self.cl.desiredAttackStartTick
	if self.cl.desiredAttackState ~= self.cl.currentAttackState or ( attackStateRevision ~= nil and attackStateRevision ~= self.cl.attackStateRevision ) then
		if self.cl.currentAttackState then
			local currentAnimationState = AttackStateAnimations[self.cl.currentAttackState]
			if self.cl.currentAttackState == DrillbotAttack.DELAY then
				-- Delay uses track animation
				attackStateAnimation = nil
			else
				-- Clear the current attack when the attack state is changed
				self:cl_resetAttack( { attackState = self.cl.currentAttackState } )
				attackStateAnimation = currentAnimationState and currentAnimationState.outAnimation or nil
				retainAttackState = true
			end
		elseif self.cl.desiredAttackState and attackHasStarted then
			if self.cl.desiredAttackState == DrillbotAttack.DELAY then
				-- Delay uses track animation
				attackStateAnimation = nil
			else
				attackStateAnimation = AttackStateAnimations[self.cl.desiredAttackState].inAnimation
			end
		end
	elseif self.cl.currentAttackState then
		if self.cl.currentAttackState == DrillbotAttack.DELAY then
			-- Delay uses track animation
			attackStateAnimation = nil
		else
			if forceBodyOutAnimation then
				attackStateAnimation = forceBodyOutAnimation
			else
				if self.cl.attackEventAnimation then
					attackStateAnimation = self.cl.attackEventAnimation
				else
					attackStateAnimation = AttackStateAnimations[self.cl.currentAttackState].idleAnimation
				end
			end
		end
	end
	if not retainAttackState and attackStateRevision ~= nil then
		self.cl.attackStateRevision = attackStateRevision
	end

	local attackAnimationPlayRate = self:cl_calculateAttackCatchupPlayRate( currentTick, attackStateAnimation )

	-- Update animations
	for name, animation in pairs( self.cl.animations ) do
		if animation.info then
			if attackStateAnimation then
				-- Override track behaviour
				if name == attackStateAnimation then
					animation.time = animation.time + deltaTime * attackAnimationPlayRate
					animation.weight = math.min( animation.weight + ( self.cl.blendSpeed * deltaTime * attackAnimationPlayRate ), 1.0 )
					if animation.time >= animation.info.duration then
						self:cl_attackAnimationEnded( name )
					end
				else
					animation.weight = math.max( animation.weight - ( self.cl.blendSpeed * deltaTime * attackAnimationPlayRate ), 0.0 )
					animation.time = animation.weight > 0 and animation.time + ( deltaTime * attackAnimationPlayRate ) or 0.0
				end
			elseif trackData and bodyAnimationTrackOverride then
				-- Play body animation from track
				if name == bodyAnimationTrackOverride then
					animation.time = trackData.trackProgress * animation.info.duration
					animation.weight = math.min( animation.weight + ( self.cl.blendSpeed * deltaTime ), 1.0 )
				else
					animation.weight = math.max( animation.weight - ( self.cl.blendSpeed * deltaTime ), 0.0 )
					animation.time = animation.weight > 0 and animation.time + deltaTime or 0.0
				end
			else
				-- Play running animation
				if name == CenterRunAnimation then
					animation.time = ( animation.time + deltaTime ) % animation.info.duration
					animation.weight = math.min( animation.weight + ( self.cl.blendSpeed * deltaTime ), 1.0 )
				else
					animation.weight = math.max( animation.weight - ( self.cl.blendSpeed * deltaTime ), 0.0 )
					animation.time = animation.weight > 0 and animation.time + deltaTime or 0.0
				end
			end

			self.character:updateAnimation( animation.info.name, animation.time, animation.weight, animation.additive )
		end
	end

	-- Publicize current animation for use in the legs
	self.character.clientPublicData = self.character.clientPublicData or {}
	self.character.clientPublicData.currentAnimation = attackStateAnimation or bodyAnimationTrackOverride or CenterRunAnimation
	self.character.clientPublicData.playRate = attackAnimationPlayRate
	-- Update face hit
	if bodyAnimationTrackOverride == "stuck_loop" then
		local faceIndex = clamp( DrillbotManager.Cl_GetFaceHits(), 0, DRILLBOT_FACE_HITS )

		local toFraction = faceIndex / DRILLBOT_FACE_HITS
		local fromFraction = math.max( toFraction - ( 1 / DRILLBOT_FACE_HITS ), 0 )
		local toTime = toFraction * self.cl.stuck_hit.info.duration
		local fromTime = fromFraction * self.cl.stuck_hit.info.duration

		-- Weight in
		self.cl.stuck_hit.weight = math.min( self.cl.stuck_hit.weight + ( self.cl.blendSpeed * deltaTime ), 1.0 )
		self.cl.stuck_hit.time = clamp( self.cl.stuck_hit.time + deltaTime, fromTime, toTime )
	else
		-- Weight out
		self.cl.stuck_hit.weight = math.max( self.cl.stuck_hit.weight - ( self.cl.blendSpeed * deltaTime ), 0.0 )
		self.cl.stuck_hit.time = self.cl.stuck_hit.weight > 0 and self.cl.stuck_hit.time or 0.0
		--faceIndex = nil
	end
	self.character:updateAnimation( self.cl.stuck_hit.info.name, self.cl.stuck_hit.time, self.cl.stuck_hit.weight, true )

	-----------------------
	-- Attack animations --
	-----------------------
	-- Check that the current attack is not on its way in or out, (doing the idle animation, but also allow attackEventAnimation to take over)
	local shouldUpdateAttack = self.cl.currentAttackState and self.cl.desiredAttackState == self.cl.currentAttackState
	-- Shoot --
	if self.cl.currentAttackState == DrillbotAttack.SHOOT and shouldUpdateAttack then
		-- Update aim
		self.cl.shootXBendAnimation.weight = 1
		self.cl.shootXBendAnimation.time = clamp( self.cl.shootXBendAnimation.time + self.cl.relativeAimVelocity.x * deltaTime * AimXWidthMultiplier, 0, 1 )

		local desiredWorldDirection = sm.vec3.zero()
		local remainingDistance = 0
		local xAxis = sm.vec3.new( 1, 0, 0 )
		-- Convert animation time to an aim offset based on the cart width
		local cartAimOffset = ( self.cl.shootXBendAnimation.time - 0.5 ) * DRILLBOT_ARENA_WIDTH
		local fightCenter = DrillbotManager.Cl_GetFightCenter()
		local targetCharacter = ResolveDrillbotTarget( bossState )
		if fightCenter and targetCharacter then
			local cartAimPosition = fightCenter + xAxis * cartAimOffset
			local axisToPlayer = xAxis * ( targetCharacter.worldPosition - cartAimPosition ):dot( xAxis )
			desiredWorldDirection = axisToPlayer:safeNormalize( sm.vec3.zero() )
			remainingDistance = axisToPlayer:length()
		end

		-- Calculate dampening based on the remaining distance
		local dampeningMultiplier = AimDampeningFactor * clamp( remainingDistance / AimDampeningDistance, 0, 1 )
		if self.cl.relativeAimVelocity:dot( desiredWorldDirection ) <= 0 then
			-- Allow full acceleration when heading the wrong way
			dampeningMultiplier = 1
		end

		self.cl.relativeAimVelocity = self.cl.relativeAimVelocity + desiredWorldDirection * AimAcceleration * dampeningMultiplier * deltaTime
		self.cl.relativeAimVelocity = ClampVector( self.cl.relativeAimVelocity, AimMaxVelocity )
	else
		-- Disable aim
		self.cl.relativeAimVelocity = sm.vec3.zero()
		self.cl.shootXBendAnimation.weight = math.max( self.cl.shootXBendAnimation.weight - ( self.cl.blendSpeed * deltaTime ), 0.0 )
		self.cl.shootXBendAnimation.time = self.cl.shootXBendAnimation.weight > 0 and self.cl.shootXBendAnimation.time or 0.5
		self.cl.shotsFired = 0
	end
	self.character:updateAnimation( self.cl.shootXBendAnimation.info.name, 1.0 - self.cl.shootXBendAnimation.time, self.cl.shootXBendAnimation.weight, true ) -- Time flipped to match animation

	-- Drill --
	if self.cl.currentAttackState == DrillbotAttack.DRILL and shouldUpdateAttack then
		-- Update drill
		self.cl.drillXBendAnimation.weight = 1
		self.cl.drillZBendAnimation.weight = 1
		self.cl.drillXBendAnimation.time = clamp( self.cl.drillXBendAnimation.time + -self.cl.relativeDrillVelocity.x * deltaTime * DrillXWidthMultiplier, 0, 1 )
		self.cl.drillZBendAnimation.time = clamp( self.cl.drillZBendAnimation.time + self.cl.relativeDrillVelocity.y * deltaTime * DrillZDepthMultiplier, 0, 1 )
		if self.cl.drillBounces < DrillBounces then
			-- Go max speed bouncy
			if self.cl.relativeDrillVelocity == sm.vec3.zero() then
				-- Set initial direction
				local drillPosition = self:cl_getDrillPosition()
				local desiredWorldDirection = sm.vec3.new( 0, 1, 0 )
				local targetCharacter = ResolveDrillbotTarget( bossState )
				if targetCharacter then
					if drillPosition then
						local desiredPositionXY = sm.vec3.new( targetCharacter.worldPosition.x, targetCharacter.worldPosition.y, 0 )
						local drillPositionXY = sm.vec3.new( drillPosition.x, drillPosition.y, 0 )
						local drillToPlayer = desiredPositionXY - drillPositionXY
						desiredWorldDirection = drillToPlayer:safeNormalize( desiredWorldDirection )
					end
				end
				self.cl.relativeDrillVelocity = desiredWorldDirection * DrillMaxBouncyVelocity
			else
				-- Bounce on edges
				local xBounce, zBounce
				xBounce = self.cl.drillXBendAnimation.time <= 0.0 and -1 or xBounce
				xBounce = self.cl.drillXBendAnimation.time >= 1.0 and 1 or xBounce
				zBounce = self.cl.drillZBendAnimation.time <= 0.0 and 1 or zBounce
				zBounce = self.cl.drillZBendAnimation.time >= 1.0 and -1 or zBounce
				if xBounce then
					self.cl.relativeDrillVelocity.x = math.abs( self.cl.relativeDrillVelocity.x ) * xBounce
					self.cl.drillBounces = self.cl.drillBounces + 1
				end
				if zBounce then
					self.cl.relativeDrillVelocity.y = math.abs( self.cl.relativeDrillVelocity.y ) * zBounce
					self.cl.drillBounces = self.cl.drillBounces + 1
				end
			end
		else
			-- Homing drill
			local drillPosition = self:cl_getDrillPosition()
			local desiredWorldDirection = sm.vec3.new( 0, 1, 0 )
			local remainingDistance = 0

			local targetCharacter = ResolveDrillbotTarget( bossState )

			if targetCharacter then
				if drillPosition then
					local desiredPositionXY = sm.vec3.new( targetCharacter.worldPosition.x, targetCharacter.worldPosition.y, 0 )
					local drillPositionXY = sm.vec3.new( drillPosition.x, drillPosition.y, 0 )
					local drillToPlayer = desiredPositionXY - drillPositionXY
					desiredWorldDirection = drillToPlayer:safeNormalize( desiredWorldDirection )
					remainingDistance = drillToPlayer:length()
				end
			end

			-- Add dampening to make the drill aim worse based on the remaining distance, and relative direction
			local dampeningScale = math.max( self.cl.relativeDrillVelocity:safeNormalize( desiredWorldDirection ):dot( desiredWorldDirection ), 0 )
			local dampeningDistance = clamp( remainingDistance / DrillDampeningDistance, 0, 1 )
			local dampeningMultiplier = math.max( dampeningScale, dampeningDistance )

			self.cl.relativeDrillVelocity = self.cl.relativeDrillVelocity + desiredWorldDirection * DrillAcceleration * deltaTime * dampeningMultiplier
			self.cl.relativeDrillVelocity = ClampVector( self.cl.relativeDrillVelocity, DrillMaxVelocity )

			-- Bounce on edges
			local xBounce, zBounce
			xBounce = self.cl.drillXBendAnimation.time <= 0.0 and -1 or xBounce
			xBounce = self.cl.drillXBendAnimation.time >= 1.0 and 1 or xBounce
			zBounce = self.cl.drillZBendAnimation.time <= 0.0 and 1 or zBounce
			zBounce = self.cl.drillZBendAnimation.time >= 1.0 and -1 or zBounce
			if xBounce then
				self.cl.relativeDrillVelocity.x = math.abs( self.cl.relativeDrillVelocity.x ) * xBounce
				self.cl.drillBounces = self.cl.drillBounces + 1
			end
			if zBounce then
				self.cl.relativeDrillVelocity.y = math.abs( self.cl.relativeDrillVelocity.y ) * zBounce
				self.cl.drillBounces = self.cl.drillBounces + 1
			end
		end
	else
		-- Disable drill
		self.cl.drillXBendAnimation.weight = 0
		self.cl.drillZBendAnimation.weight = 0
		self.cl.drillXBendAnimation.time = 0.5
		self.cl.drillZBendAnimation.time = 0.0
		self.cl.relativeDrillVelocity = sm.vec3.zero()
		self.cl.drillBounces = 0
	end
	self.character:updateAnimation( self.cl.drillXBendAnimation.info.name, self.cl.drillXBendAnimation.time, self.cl.drillXBendAnimation.weight, true )
	self.character:updateAnimation( self.cl.drillZBendAnimation.info.name, self.cl.drillZBendAnimation.time, self.cl.drillZBendAnimation.weight, true )

	-- Left Scythe --
	if self.cl.currentAttackState == DrillbotAttack.ATTACK_LEFT and shouldUpdateAttack then
		-- Attack is handled by animation events, cl_e_scytheAttackEvent 
	else
		self.cl.scytheSwingsLeft = 0
	end

	-- Right Scythe --
	if self.cl.currentAttackState == DrillbotAttack.ATTACK_RIGHT and shouldUpdateAttack then
		-- Attack is handled by animation events, cl_e_scytheAttackEvent 
	else
		self.cl.scytheSwingsRight = 0
	end

	-- Left Combo 01 --
	if self.cl.currentAttackState == DrillbotAttack.COMBO_LEFT01 and shouldUpdateAttack then
		-- Activate delayed trigger hits
		for triggerIndex, delayTime in pairs( self.cl.cartTriggerDelaysComboLeft01 ) do
			delayTime = delayTime - deltaTime
			if delayTime <= 0.0 then
				self:cl_scytheAttack( triggerIndex )
				self.cl.cartTriggerDelaysComboLeft01[triggerIndex] = nil
			else
				self.cl.cartTriggerDelaysComboLeft01[triggerIndex] = delayTime
			end
		end
	else
		self.cl.scytheSwingsComboLeft01 = 0
		self.cl.cartTriggerDelaysComboLeft01 = {}
	end

	-- Left Combo 02 --
	if self.cl.currentAttackState == DrillbotAttack.COMBO_LEFT02 and shouldUpdateAttack then
		-- Activate delayed trigger hits
		for triggerIndex, delayTime in pairs( self.cl.cartTriggerDelaysComboLeft02 ) do
			delayTime = delayTime - deltaTime
			if delayTime <= 0.0 then
				self:cl_scytheAttack( triggerIndex )
				self.cl.cartTriggerDelaysComboLeft02[triggerIndex] = nil
			else
				self.cl.cartTriggerDelaysComboLeft02[triggerIndex] = delayTime
			end
		end
	else
		self.cl.scytheSwingsComboLeft02 = 0
		self.cl.cartTriggerDelaysComboLeft02 = {}
	end

end

function DrillbotCharacter.cl_calculateAttackCatchupPlayRate( self, currentTick, attackStateAnimation )

	if attackStateAnimation == nil or self.cl.desiredAttackState == nil or self.cl.desiredAttackStartTick == nil then
		-- Not doing an attack
		return 1.0
	end

	local attackTicksElapsed = currentTick - self.cl.desiredAttackStartTick -- Negative before the desired start of the next attack, positive after
	if attackTicksElapsed < 0 then
		-- Out animation segment, before starting the new attack
		local previousAnimationState = AttackStateAnimations[self.cl.currentAttackState]
		local outAnimation = previousAnimationState and previousAnimationState.outAnimation or nil
		local outAnimationData = outAnimation and self.cl.animations[outAnimation] or nil
		if outAnimationData == nil or outAnimationData.info.duration <= 0 then
			return 1.0
		end

		local outDurationInTicks = outAnimationData.info.duration * GameTickRate
		local outTicksElapsed = outDurationInTicks + attackTicksElapsed
		local expectedOutProgress = clamp( outTicksElapsed / outDurationInTicks, 0, 1 )
		if attackStateAnimation ~= outAnimation then
			-- Not doing the out animation, so either still doing the previous attack (playrate max), or already finished the out animation (playrate 1)
			return expectedOutProgress > 0 and AttackCatchupMaxPlayRate or 1.0
		end

		-- Doing out animation
		local outProgress = clamp( outAnimationData.time / outAnimationData.info.duration, 0, 1 )
		return GetCatchupRate( expectedOutProgress, outProgress )
	end

	if self.cl.currentAttackState == self.cl.desiredAttackState then
		-- Has passed the start of the next attack and has reached the correct attack state
		return 1.0
	end

	local desiredAnimationState = AttackStateAnimations[self.cl.desiredAttackState]
	local inAnimation = desiredAnimationState and desiredAnimationState.inAnimation or nil
	local inAnimationData = inAnimation and self.cl.animations[inAnimation] or nil
	if inAnimationData == nil or inAnimationData.info.duration <= 0 then
		return 1.0
	end

	local inDurationInTicks = inAnimationData.info.duration * GameTickRate
	local expectedInProgress = clamp( attackTicksElapsed / inDurationInTicks, 0, 1 )
	if attackStateAnimation == inAnimation then
		-- Doing in animation
		local inProgress = clamp( inAnimationData.time / inAnimationData.info.duration, 0, 1 )
		return GetCatchupRate( expectedInProgress, inProgress )
	end

	if expectedInProgress > 0 then
		-- Not doing the in animation, but should have started it by now
		return AttackCatchupMaxPlayRate
	end

	return 1.0
end

function DrillbotCharacter.cl_attackAnimationEnded( self, animationName )

	local animation = self.cl.animations[animationName]
	if animation then
		if animation.info and animation.info.looping then
			animation.time = animation.time % animation.info.duration
		end
	end

	if animationName == self.cl.attackEventAnimation then
		-- Reset attack event animation
		self.cl.attackEventAnimation = nil
	end

	-- Switch between attack states
	local desiredAnimationState = AttackStateAnimations[self.cl.desiredAttackState]
	local currentAnimationState = AttackStateAnimations[self.cl.currentAttackState]
	if desiredAnimationState and animationName == desiredAnimationState.inAnimation then
		self.cl.currentAttackState = self.cl.desiredAttackState
	elseif currentAnimationState and animationName == currentAnimationState.outAnimation then
		self.cl.currentAttackState = nil
	end

	-- Trigger sequencing for attacks that use an event animation per swing --
	-- Left Scythe
	if self.cl.currentAttackState == DrillbotAttack.ATTACK_LEFT then
		if animationName == AttackStateAnimations[DrillbotAttack.ATTACK_LEFT].idleAnimation then
			if self.cl.scytheSwingsLeft < ScytheSwingsBeforeAbort then
				-- Choose a trigger to attack
				local triggerIndex = self:cl_getAttackableTriggerIndex()
				-- Trigger to animation index is reversed
				local revScytheIndex = ScytheTriggerIndices - triggerIndex + 1
				self.cl.attackEventAnimation = ScytheLeftAttacks[revScytheIndex]
				self:cl_anticipateScytheAttack( triggerIndex )
				self.cl.scytheSwingsLeft = self.cl.scytheSwingsLeft + 1
			end
		end
	end
	-- Right Scythe
	if self.cl.currentAttackState == DrillbotAttack.ATTACK_RIGHT then
		if animationName == AttackStateAnimations[DrillbotAttack.ATTACK_RIGHT].idleAnimation then
			if self.cl.scytheSwingsRight < ScytheSwingsBeforeAbort then
				-- Choose a trigger to attack
				local triggerIndex = self:cl_getAttackableTriggerIndex()
				-- Trigger to animation index is reversed
				local revScytheIndex = ScytheTriggerIndices - triggerIndex + 1
				self.cl.attackEventAnimation = ScytheRightAttacks[revScytheIndex]
				self:cl_anticipateScytheAttack( triggerIndex )
				self.cl.scytheSwingsRight = self.cl.scytheSwingsRight + 1
			end
		end
	end
	-- Combo Left Scythe 01
	if self.cl.currentAttackState == DrillbotAttack.COMBO_LEFT01 then
		if animationName == AttackStateAnimations[DrillbotAttack.COMBO_LEFT01].idleAnimation then
			if self.cl.scytheSwingsComboLeft01 < ComboSwingsBeforeAbort then
				-- Choose a trigger to attack
				local comboIndex = 1
				local comboDelays = ComboDelays[comboIndex]
				for comboTriggerIndex, delayTime in pairs( comboDelays ) do
					self.cl.cartTriggerDelaysComboLeft01[comboTriggerIndex] = delayTime
				end
				self.cl.attackEventAnimation = ComboLeftAttacks[comboIndex]
				self.cl.scytheSwingsComboLeft01 = self.cl.scytheSwingsComboLeft01 + 1
			end
		end
	end
	-- Combo Left Scythe 02
	if self.cl.currentAttackState == DrillbotAttack.COMBO_LEFT02 then
		if animationName == AttackStateAnimations[DrillbotAttack.COMBO_LEFT02].idleAnimation then
			if self.cl.scytheSwingsComboLeft02 < ComboSwingsBeforeAbort then
				-- Choose a trigger to attack
				local comboIndex = 2
				local comboDelays = ComboDelays[comboIndex]
				for comboTriggerIndex, delayTime in pairs( comboDelays ) do
					self.cl.cartTriggerDelaysComboLeft02[comboTriggerIndex] = delayTime
				end
				self.cl.attackEventAnimation = ComboLeftAttacks[comboIndex]
				self.cl.scytheSwingsComboLeft02 = self.cl.scytheSwingsComboLeft02 + 1
			end
		end
	end
end

function DrillbotCharacter.sv_n_spawnMagmaBall( self, params )
	sm.scriptableObject.createScriptableObject( MagmaBallUuid, params, self.character:getWorld() )
end

function DrillbotCharacter.sv_n_stopAttack( self )
	DrillbotManager.Sv_RequestStopAttack()
end

function DrillbotCharacter.cl_resetAttack( self, params )
	self.cl.attackEventAnimation = nil
	self.cl.abortSignalSent = nil

	local attackStateToReset = params.attackState
	if attackStateToReset == DrillbotAttack.ATTACK_LEFT then
		self.cl.scytheSwingsLeft = 0
	elseif attackStateToReset == DrillbotAttack.ATTACK_RIGHT then
		self.cl.scytheSwingsRight = 0
	elseif attackStateToReset == DrillbotAttack.COMBO_LEFT01 then
		self.cl.scytheSwingsComboLeft01 = 0
		self.cl.cartTriggerDelaysComboLeft01 = {}
	elseif attackStateToReset == DrillbotAttack.COMBO_LEFT02 then
		self.cl.scytheSwingsComboLeft02 = 0
		self.cl.cartTriggerDelaysComboLeft02 = {}
	elseif attackStateToReset == DrillbotAttack.DRILL then
		self.cl.drillBounces = 0
	elseif attackStateToReset == DrillbotAttack.SHOOT then
		self.cl.shotsFired = 0
	end
end

function DrillbotCharacter.client_onEvent( self, event )
	self:cl_handleEvent( event )
end

function DrillbotCharacter.cl_handleEvent( self, event )
	if not self.cl.animationsLoaded then return end

end

function DrillbotCharacter.sv_n_damageCharacter( self, params )
	if not sm.exists( params.character ) then
		return
	end
	if params.character:isPlayer() then
		local player = params.character:getPlayer()
		if sm.exists( player ) then
			sm.event.sendToPlayer( player, "sv_e_receiveDamage", { damage = params.damage, source = "shock" } )
		end
	else
		local unit = params.character:getUnit()
		if sm.exists( unit ) then
			sm.event.sendToUnit( unit, "sv_e_receiveDamage", { damage = params.damage, impact = params.direction, hitPos = params.position } )
		end
	end
end

function DrillbotCharacter.sv_n_destroyLock( self, params )
	if sm.exists( params.lock ) then
		sm.event.sendToHarvestable( params.lock, "sv_e_destroy" )
	end
end

function DrillbotCharacter.sv_n_destroyBox( self, params )
	if sm.exists( params.box ) then
		sm.event.sendToInteractable( params.box, "sv_e_destroy", params.velocity )
	end
end

function DrillbotCharacter.client_onClientDataUpdate( self, clientData, channel )
	self.cl.kinematics = clientData.kinematics
end

function DrillbotCharacter.client_onFixedUpdate( self )
	local currentTick = sm.game.getCurrentTick()
	for characterId, damagedCharacter in pairs( self.cl.damagedCharacters ) do
		if currentTick >= damagedCharacter.damageTick + DamageTickCooldown then
			self.cl.damagedCharacters[characterId] = nil
		end
	end

	if not self.cl.graphicsLoaded then
		return
	end
	self:cl_updateKinematics()
	self:cl_updateDrill()
end

function DrillbotCharacter.cl_updateKinematics( self )
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

function DrillbotCharacter.cl_updateDrill( self )
	local currentTick = sm.game.getCurrentTick()
	if self.cl.drillTrigger then
		-- Check drill collisions
		local drillCharacterCollisions = self.cl.drillTrigger:getCharacters()
		for _, characterCollision in ipairs( drillCharacterCollisions ) do
			-- Filter on player and woc characters
			if sm.exists( characterCollision.character ) then
				local targetCharacter = characterCollision.character
				if self.cl.damagedCharacters[targetCharacter.id] == nil and characterCollision.character ~= self.character then

					local knockbackDirection = ( targetCharacter.worldPosition - self.cl.drillTrigger:getWorldPosition() ):safeNormalize( -targetCharacter.direction )
					local skipKnockback = targetCharacter:isPlayer() and ( targetCharacter:isDowned() or targetCharacter:isTumbling() )
					if not skipKnockback then
						-- Knockback both host and clients
						ApplyKnockback( targetCharacter, knockbackDirection, 4000 )
						self.cl.damagedCharacters[targetCharacter.id] = { damageTick = currentTick }

						-- Both host and clients detects damage on their local player
						if targetCharacter == sm.localPlayer.getPlayer().character then
							local damageParams = { character = targetCharacter, damage = DrillDamage, direction = knockbackDirection, position = self.cl.drillTrigger:getWorldPosition() }
							self.network:sendToServer( "sv_n_damageCharacter", damageParams )
							sm.effect.playEffect( "audio:event:/char/npc/bots/enemies/drillbot/drill_hit", self.cl.drillTrigger:getWorldPosition() )
						end

						if sm.isHost then
							-- Host detects damage on units
							if not targetCharacter:isPlayer() then
								local damageParams = { character = targetCharacter, damage = DrillDamage, direction = knockbackDirection, position = self.cl.drillTrigger:getWorldPosition() }
								self.network:sendToServer( "sv_n_damageCharacter", damageParams )
								sm.effect.playEffect( "audio:event:/char/npc/bots/enemies/drillbot/drill_hit", self.cl.drillTrigger:getWorldPosition() )
							end
						end
					end
				end
			end
		end
		if sm.isHost then
			local drillHarvestableCollisions = self.cl.drillTrigger:getHarvestables()
			for _, harvestableCollision in ipairs( drillHarvestableCollisions ) do
				if sm.exists( harvestableCollision.harvestable ) then
					if harvestableCollision.harvestable.uuid == kin_bosstrain_lock then
						self.network:sendToServer( "sv_n_destroyLock", { lock = harvestableCollision.harvestable} )
					end
				end
			end
			local drillShapeCollisions = self.cl.drillTrigger:getShapes()
			for _, shapeCollision in ipairs( drillShapeCollisions ) do
				if isAnyOf( shapeCollision.shape.uuid, g_drillbot_loot_crates ) then
					local interactable = shapeCollision.shape:getInteractable()
					if interactable then
						self.network:sendToServer( "sv_n_destroyBox", { box = interactable, velocity = self.cl.relativeDrillVelocity } )
					end
				end
			end
		end
	end

	-- Update drill trigger
	local showDrillEffect = false
	local drillAnimation = AttackStateAnimations[DrillbotAttack.DRILL].idleAnimation
	if self.cl.animations[drillAnimation].weight > 0.1 then
		local drillPosition = self:cl_getDrillPosition()
		if drillPosition then
			if self.cl.drillTrigger == nil then
				self.cl.drillTrigger = sm.areaTrigger.createSphere( 1.5, drillPosition, sm.quat.identity(), sm.areaTrigger.filter.character + sm.areaTrigger.filter.harvestable + sm.areaTrigger.filter.dynamicBody )
				self.cl.drillTrigger:setCharacterDetection( true )
				if sm.isHost then
					self.cl.drillTrigger:setHarvestableDetection( true )
					self.cl.drillTrigger:setShapeDetection( true )
				end
			else
				-- raycast to drill ground
				self.cl.drillTrigger:setWorldPosition( drillPosition )
			end

			showDrillEffect = true
			self.cl.drillImpactEffect:setPosition( drillPosition )
		end
	else
		if self.cl.drillTrigger then
			sm.areaTrigger.destroy( self.cl.drillTrigger )
			self.cl.drillTrigger = nil
		end
	end

	if showDrillEffect then
		if not self.cl.drillLoopEffect:isPlaying() then
			self.cl.drillLoopEffect:start()
		end
		if not self.cl.drillImpactEffect:isPlaying() then
			self.cl.drillImpactEffect:start()
		end
	else
		if self.cl.drillLoopEffect:isPlaying() then
			self.cl.drillLoopEffect:stop()
		end
		if self.cl.drillImpactEffect:isPlaying() then
			self.cl.drillImpactEffect:stop()
		end
	end

	local drillStartupAnimation = AttackStateAnimations[DrillbotAttack.DRILL].inAnimation
	if self.cl.animations[drillStartupAnimation].weight > 0.1 then
		if self.cl.drillStartupEffect == nil then
			self.cl.drillStartupEffect = sm.effect.createEffect( "Drillbot - drill_startup01", self.character, "drillguard_jnt" )
			self.cl.drillStartupEffect:start()
		end
	else
		if self.cl.drillStartupEffect then
			self.cl.drillStartupEffect:destroy()
			self.cl.drillStartupEffect = nil
		end
	end
end

function DrillbotCharacter.cl_getDrillPosition( self )
	local drillKinematic = ( self.cl.kinematics["drill_jnt"] and sm.exists( self.cl.kinematics["drill_jnt"].kinematic ) ) and self.cl.kinematics["drill_jnt"].kinematic or nil
	local drillBonePosition = self.character:getTpBonePos( "drill_jnt" )
	local drillBoneRotation = self.character:getTpBoneRot( "drill_jnt" )
	if drillBonePosition and drillBoneRotation then
		-- Spherecast to drill ground
		local drillPosition = drillBonePosition + drillBoneRotation * sm.vec3.new( 0, -14.5, 0 )
		local filter = sm.physics.filter.harvestable -- Only looking for the cart kinematic
		local hit, result = sm.physics.spherecast( drillBonePosition, drillPosition, 0.1, drillKinematic, filter )
		if hit then
			drillPosition = result.pointWorld
		end
		return drillPosition
	end
	return nil
end

function DrillbotCharacter.cl_scytheAttack( self, triggerIndex )
	local function hitCharacters( trigger )
		local characterCollisions = trigger:getCharacters()
		for _, characterCollision in ipairs( characterCollisions ) do
			if sm.exists( characterCollision.character ) then
				local targetCharacter = characterCollision.character
				local knockbackDirection = ( targetCharacter.worldPosition - trigger:getWorldPosition() ):safeNormalize( -targetCharacter.direction )
				local skipHit = targetCharacter:isPlayer() and ( targetCharacter:isDowned() or targetCharacter:isTumbling() )
				if not skipHit then
					-- Knockback both host and clients
					ApplyKnockback( targetCharacter, knockbackDirection, 4000 )

					-- Both host and clients detects damage on their local player
					if targetCharacter == sm.localPlayer.getPlayer().character then
						local damageParams = { character = targetCharacter, damage = ScytheDamage, direction = knockbackDirection, position = trigger:getWorldPosition() }
						self.network:sendToServer( "sv_n_damageCharacter", damageParams )
					end

					if sm.isHost then
						-- Host detects damage on units
						if not targetCharacter:isPlayer() then
							local damageParams = { character = targetCharacter, damage = ScytheDamage, direction = knockbackDirection, position = trigger:getWorldPosition() }
							self.network:sendToServer( "sv_n_damageCharacter", damageParams )
						end
					end
				end
			end
		end
	end

	local cart = DrillbotManager.Cl_GetCurrentCart()
	if cart and cart.scytheTriggers then
		local cartTrigger = cart.scytheTriggers[triggerIndex]
		if sm.exists( cartTrigger ) then
			sm.effect.playEffect( "Drillbot - scythe_impact01", cartTrigger:getWorldPosition() )
			hitCharacters( cartTrigger )
		end
	end
end

function DrillbotCharacter.cl_anticipateScytheAttack( self, triggerIndex )
	local cart = DrillbotManager.Cl_GetCurrentCart()
	if cart and cart.scytheTriggers then
		local cartTrigger = cart.scytheTriggers[triggerIndex]
		if sm.exists( cartTrigger ) then
			sm.effect.playEffect( "Drillbot - Anticipation03", cartTrigger:getWorldPosition() )
		end
	end
end

function DrillbotCharacter.cl_getAttackableTriggerIndex( self )

	local bossState = DrillbotManager.Cl_GetBossState()
	local targetCharacter = ResolveDrillbotTarget( bossState )

	local targetTriggerIndex
	local triggerIndices = {}
	local cart = DrillbotManager.Cl_GetCurrentCart()
	if cart and cart.scytheTriggers then
		for triggerIndex, cartTrigger in pairs( cart.scytheTriggers ) do
			if sm.exists( cartTrigger ) then
				local characterCollisions = cartTrigger:getCharacters()
				for _, characterCollision in ipairs( characterCollisions ) do
					if characterCollision.character:isPlayer() then
						-- This trigger index has a player
						triggerIndices[#triggerIndices+1] = triggerIndex
						if targetCharacter and targetCharacter == characterCollision.character then
							targetTriggerIndex = triggerIndex
						end
					end
				end
			end
		end
	end

	-- Return the trigger index of the targeted player
	if targetTriggerIndex then
		return targetTriggerIndex
	end
	-- Return the first trigger index that has a player in it
	if #triggerIndices > 0 then
		return triggerIndices[1]
	end
	-- No player found, return the middle trigger index
	return math.ceil( ScytheTriggerIndices * 0.5 )
end