dofile "$SURVIVAL_DATA/Scripts/util.lua"
dofile "$SURVIVAL_DATA/Scripts/game/trashbot/TrashbotStageValues.lua"

TrashbotCharacter = class( nil )

local LookMaxRadiansPerSecond = math.rad( 75 )
local AimedRadiansPerSecond = math.rad( 20 )

local QuadDirection = {
	FORWARD = 1,
	LEFT = 2,
	RIGHT = 3,
	BACK = 4,
}

local StunTicks = math.floor( 40 * 3.0 ) -- Same as trashbot unit stun time

local TrashbotKinematicPieces = {
	["l_arm04_jnt"] = sm.uuid.new( "f80d42b7-b294-4dd0-890e-66d037a6cd11" ),
	["r_arm04_jnt"] = sm.uuid.new( "f80d42b7-b294-4dd0-890e-66d037a6cd11" ),
	["center_jnt"] = sm.uuid.new( "77279545-9e45-4cb9-946a-0f585cb0f514" ),
	["head_jnt"] = sm.uuid.new( "339ea9ef-b610-488f-9ed7-dbc894b30f13" ),
	["leg01_02_jnt"] = sm.uuid.new( "1090c8a2-5e28-480a-bef0-582087e83a1a" ),
	["leg02_02_jnt"] = sm.uuid.new( "1090c8a2-5e28-480a-bef0-582087e83a1a" ),
	["leg03_02_jnt"] = sm.uuid.new( "1090c8a2-5e28-480a-bef0-582087e83a1a" ),
	["leg04_02_jnt"] = sm.uuid.new( "1090c8a2-5e28-480a-bef0-582087e83a1a" ),
	["leg01_03_jnt"] = sm.uuid.new( "66ba7f43-e6ed-4b75-8845-8312450631ea" ),
	["leg02_03_jnt"] = sm.uuid.new( "66ba7f43-e6ed-4b75-8845-8312450631ea" ),
	["leg03_03_jnt"] = sm.uuid.new( "66ba7f43-e6ed-4b75-8845-8312450631ea" ),
	["leg04_03_jnt"] = sm.uuid.new( "66ba7f43-e6ed-4b75-8845-8312450631ea" ),
	["trun_jnt"] = sm.uuid.new( "35886aef-079c-4317-a469-df6759c1849c" ),
	["hinge02_jnt"] = sm.uuid.new( "25d24db2-5ce5-4b34-b896-ac5ce7023c61" )
}

local EyeEffectDelayTime = math.floor( 0.6 * 40 )

-- Horizontal radius (meters) around the trashbot within which the boss music plays.
local BossMusicRadius = 80

local NonBroomAnims = {
		"koDmg",
		"koFinal",
		"koOut",
		"escape",
		"cinematic",
		"underground_cinematic",
		"destroy",
		"koIn"
	}

function TrashbotCharacter.server_onCreate( self )
	self.sv = {}
	self.sv.kinematicPieces = {}
	for joint,uuid in pairs( TrashbotKinematicPieces ) do
		self.sv.kinematicPieces[joint] = sm.harvestable.createHarvestable( uuid, self.character.worldPosition, sm.quat.identity() )
	end

	self.network:setClientData( self.sv.kinematicPieces )
end

function TrashbotCharacter.server_onDestroy( self )
	for _,kinematic in pairs( self.sv.kinematicPieces ) do
		sm.harvestable.destroy( kinematic )
	end
end

function TrashbotCharacter.client_onClientDataUpdate( self, data, channel )
	if channel == 1 then
		self.cl.kinematicPieces = data
	elseif channel == 2 then
		self:cl_n_toggleLookAtTarget( data )
	elseif channel == 3 then
		if data.fightType == 1 then
			DialogManager.Cl_RegisterSpeaker( self.character, DialogSpeakerName.Lorenzo )
		end
	elseif channel == 4 then
		self:cl_setBossMusicControl( data.control )
	end
end

function TrashbotCharacter.client_onCreate( self )

	self.cl = {}
	self.cl.animations = {}
	self.cl.target = nil
	self.cl.lookDirection = self.character.direction:safeNormalize( sm.vec3.new( 0, 1, 0 ) )
	self.cl.spawnDirection = self.cl.lookDirection
	self.cl.lookingAtTarget = false
	self.cl.headUpDownFraction = 0.5
	self.cl.headLeftRightFraction = 0.5
	self.cl.turretFraction = 0.0
	self.cl.currentAnimation = ""
	self.cl.eyeOpen = false
	self.cl.isAlerted = false
	self.cl.latestMissedEvent = nil

	self.cl.hasBossMusicControl = false
	self.cl.bossMusicEffect = nil

	self.cl.kinematicPieces = {}

	print( "-- TrashbotCharacter created --" )
	self:client_onRefresh()
end

function TrashbotCharacter.client_onDestroy( self )
	if self.cl and self.cl.bossMusicEffect then
		self.cl.bossMusicEffect:stopImmediate()
		self.cl.bossMusicEffect:destroy()
		self.cl.bossMusicEffect = nil
	end
	print( "-- TrashbotCharacter destroyed --" )
end

function TrashbotCharacter.client_onRefresh( self )
	print( "-- TrashbotCharacter refreshed --" )
end

function TrashbotCharacter.client_onGraphicsLoaded( self )
	self.character:setMovementEffects( "$SURVIVAL_DATA/Character/Char_Trashbot/movement_effects.json" )
	self:cl_initGraphics()
	self.character:setGlowMultiplier( 1 )
	self.graphicsLoaded = true

	self.cl.cinematicEffect = sm.effect.createEffect( "Cinematiceffects - Trashbot", self.character )
	self.cl.cinematicUndergroundEffect = sm.effect.createEffect( "Cinematiceffects - Trashbot_underground", self.character )
	self.cl.cinematicRoarEffect = sm.effect.createEffect( "Cinematiceffects - Trashbot_roar", self.character, "head_jnt" )
	self.cl.cinematicRoarUndergroundEffect = sm.effect.createEffect( "Cinematiceffects - Trashbot_roar_underground", self.character, "head_jnt" )

	self.cl.floorSwirlEffect = sm.effect.createEffect( "Trashbot - GroundSpray_Twister")
	self.cl.floorSwirlEffect:setPosition( self.character:getTpBonePos( "root_jnt" ) )

	self.cl.groundSwirlIntense = sm.effect.createEffect( "Trashbot - Twister_Center" )
	self.cl.groundSwirlIntense:setPosition( self.character:getTpBonePos( "root_jnt" ) )

	self.cl.groundSprayLeftArmEffect = sm.effect.createEffect( "Trashbot - Flowspray_purple", self.character, "l_arm04_jnt" )
	self.cl.groundSprayLeftArmEffect:setOffsetRotation( sm.quat.fromEuler( sm.vec3.new( 0.0, 180.0, 0.0 ) ) )
	self.cl.groundSprayRightArmEffect = sm.effect.createEffect( "Trashbot - Flowspray_green", self.character, "r_arm04_jnt" )

	self.cl.eyeGlowEffect = sm.effect.createEffect( "Trashbot - Eyeglow_loop", self.character, "mouth02_jnt" )
	self.cl.eyeGlowEffect:setOffsetPosition( sm.vec3.new( 0.0, 0.0, 0.9 ) )
	self.cl.eyeOpenEffect = sm.effect.createEffect( "Trashbot - Eyeglow_open", self.character, "mouth02_jnt" )
	self.cl.eyeOpenEffect:setOffsetPosition( sm.vec3.new( 0.0, 0.0, 0.9 ) )
	self.cl.eyeCloseEffect = sm.effect.createEffect( "audio:event:/char/npc/bots/enemies/trashbot/eye_close", self.character, "mouth02_jnt" )
	self.cl.eyeCloseEffect:setOffsetPosition( sm.vec3.new( 0.0, 0.0, 0.9 ) )
	self.cl.eyeEffectTimer = Timer()

	self.cl.batteryLoopEffect = sm.effect.createEffect( "Trashbot - Battery Lightning Loop", self.character, "powercore_05_jnt" )
	self.cl.chargingEffectRight = sm.effect.createEffect( "Trashbot - Chargedshot Buildup Green", self.character, "r_arm04_jnt" )
	self.cl.chargingEffectRight:setOffsetRotation( sm.quat.fromEuler( sm.vec3.new( -90, 0, 0 ) ) )
	self.cl.chargingEffectLeft = sm.effect.createEffect( "Trashbot - Chargedshot Buildup Purple", self.character, "l_arm04_jnt" )
	self.cl.chargingEffectLeft:setOffsetRotation( sm.quat.fromEuler( sm.vec3.new( 90, 0, 0 ) ) )
	self.cl.pushbackEffect = sm.effect.createEffect( "Trashbot - Wind_Push", self.character, "root_jnt" )
	self.cl.pushbackEffect:setOffsetRotation( sm.quat.fromEuler( sm.vec3.new( -90, 0, 0 ) ) )

	self.cl.bleedEffectsData = {
		{ effect = sm.effect.createEffect( "Trashbot - Phase03", self.character, "pejnt_trash" ), phase = 3 },
		{ effect = sm.effect.createEffect( "Trashbot - Phase04", self.character, "pejnt_trash" ), phase = 4 },
		{ effect = sm.effect.createEffect( "Trashbot - Phase04_head", self.character, "head_jnt" ), phase = 4 },	
	}

	self.cl.eyeAreaTrigger = sm.areaTrigger.createBox( sm.vec3.new( 1.75, 1.75, 1 ), self.character:getTpBonePos( "head_jnt" ), self.character:getTpBoneRot( "head_jnt" ) )
	self.cl.eyeAreaTrigger:bindOnProjectile( "cl_t_onProjectile", self )
end

function TrashbotCharacter.client_onGraphicsUnloaded( self )
	self.graphicsLoaded = false

	if self.cl.cinematicEffect then
		self.cl.cinematicEffect:destroy()
		self.cl.cinematicEffect = nil
	end
	if self.cl.cinematicUndergroundEffect then
		self.cl.cinematicUndergroundEffect:destroy()
		self.cl.cinematicUndergroundEffect = nil
	end
	if self.cl.cinematicRoarUndergroundEffect then
		self.cl.cinematicRoarUndergroundEffect:destroy()
		self.cl.cinematicRoarUndergroundEffect = nil
	end
	if self.cl.cinematicRoarEffect then
		self.cl.cinematicRoarEffect:destroy()
		self.cl.cinematicRoarEffect = nil
	end
	if self.cl.batteryLoopEffect then
		self.cl.batteryLoopEffect:destroy()
		self.cl.batteryLoopEffect = nil
	end
	if self.cl.chargingEffectRight then
		self.cl.chargingEffectRight:destroy()
		self.cl.chargingEffectRight = nil
	end
	if self.cl.chargingEffectLeft then
		self.cl.chargingEffectLeft:destroy()
		self.cl.chargingEffectLeft = nil
	end
	if self.cl.pushbackEffect then
		self.cl.pushbackEffect:destroy()
		self.cl.pushbackEffect = nil
	end
	if self.cl.floorSwirlEffect then
		self.cl.floorSwirlEffect:stopImmediate()
		self.cl.floorSwirlEffect:destroy()
		self.cl.floorSwirlEffect = nil
	end
	if self.cl.groundSwirlIntense then
		self.cl.groundSwirlIntense:stopImmediate()
		self.cl.groundSwirlIntense:destroy()
		self.cl.groundSwirlIntense = nil
	end
	if self.cl.eyeGlowEffect then
		self.cl.eyeGlowEffect:stopImmediate()
		self.cl.eyeGlowEffect = nil
	end

	if sm.exists( self.cl.eyeAreaTrigger ) then
		sm.areaTrigger.destroy( self.cl.eyeAreaTrigger )
		self.cl.eyeAreaTrigger = nil
	end
end

function TrashbotCharacter.cl_initGraphics( self )

	self.cl.leftArmAnimations = { "sprayLeft", "volleyLeft", "chargeLeft", "sprinklerLeft_loop", "sprinklerLeft_in", "sprinklerLeft_out", "sprayLeft_loop", "sprayLeft_in", "sprayLeft_out" }
	self.cl.rightArmAnimations = { "sprayRight", "volleyRight", "chargeRight", "sprinklerRight_loop", "sprinklerRight_in", "sprinklerRight_out", "sprayRight_loop", "sprayRight_in", "sprayRight_out" }

	if not self.cl.animations.idleLeftAnimation then
		self.cl.animations.idleLeftAnimation = {
			info = self.character:getAnimationInfo( "idle_l" ),
			time = 0,
			weight = 0,
			additive = true,
			looping = true
		}
	end
	if not self.cl.animations.idleRightAnimation then
		self.cl.animations.idleRightAnimation = {
			info = self.character:getAnimationInfo( "idle_r" ),
			time = 0,
			weight = 0,
			additive = true,
			looping = true
		}
	end

	if not self.cl.animations.volleyLeft then
		self.cl.animations.volleyLeft = {
			info = self.character:getAnimationInfo( "volley_l" ),
			time = 0,
			weight = 0,
			additive = true
		}
	end
	if not self.cl.animations.volleyRight then
		self.cl.animations.volleyRight = {
			info = self.character:getAnimationInfo( "volley_r" ),
			time = 0,
			weight = 0,
			additive = true
		}
	end
	if not self.cl.animations.chargeLeft then
		self.cl.animations.chargeLeft = {
			info = self.character:getAnimationInfo( "charge_l" ),
			time = 0,
			weight = 0,
			additive = true
		}
	end
	if not self.cl.animations.chargeRight then
		self.cl.animations.chargeRight = {
			info = self.character:getAnimationInfo( "charge_r" ),
			time = 0,
			weight = 0,
			additive = true
		}
	end
	if not self.cl.animations.pushback then
		self.cl.animations.pushback = {
			info = self.character:getAnimationInfo( "pushback" ),
			time = 0,
			weight = 0,
			additive = false
		}
	end

	if not self.cl.animations.broom then
		self.cl.animations.broom = {
			info = self.character:getAnimationInfo( "broom01" ),
			time = 0,
			weight = 0,
			active = false,
			additive = true
		}
	end
	if not self.cl.animations.stomp then
		self.cl.animations.stomp = {
			info = self.character:getAnimationInfo( "stomp" ),
			time = 0,
			weight = 0,
			active = false,
			additive = true
		}
	end
	if not self.cl.animations.barf01 then
		self.cl.animations.barf01 = {
			info = self.character:getAnimationInfo( "barf01" ),
			time = 0,
			weight = 0,
			active = false,
			additive = true
		}
	end
	if not self.cl.animations.hurt then
		self.cl.animations.hurt = {
			info = self.character:getAnimationInfo( "add_hurt" ),
			time = 0,
			weight = 0,
			active = false,
			additive = true
		}
	end
	if not self.cl.animations.ko then
		self.cl.animations.ko = {
			info = self.character:getAnimationInfo( "ko" ),
			time = 0,
			weight = 0,
			additive = true
		}
	end
	if not self.cl.animations.koDmg then
		self.cl.animations.koDmg = {
			info = self.character:getAnimationInfo( "ko_dmg" ),
			time = 0,
			weight = 0,
			active = false,
			additive = true
		}
	end
	-- Lower body forward
	if not self.cl.animations.koInForward then
		self.cl.animations.koInForward = {
			info = self.character:getAnimationInfo( "ko_in_legs_f" ),
			time = 0,
			weight = 0,
			active = false,
			additive = true
		}
	end
	-- Lower body left
	if not self.cl.animations.koInLeft then
		self.cl.animations.koInLeft = {
			info = self.character:getAnimationInfo( "ko_in_legs_l" ),
			time = 0,
			weight = 0,
			active = false,
			additive = true
		}
	end
	-- Lower body right
	if not self.cl.animations.koInRight then
		self.cl.animations.koInRight = {
			info = self.character:getAnimationInfo( "ko_in_legs_r" ),
			time = 0,
			weight = 0,
			active = false,
			additive = true
		}
	end
	-- Lower body back
	if not self.cl.animations.koInBack then
		self.cl.animations.koInBack = {
			info = self.character:getAnimationInfo( "ko_in_legs_b" ),
			time = 0,
			weight = 0,
			active = false,
			additive = true
		}
	end
	-- Upper body
	if not self.cl.animations.koIn then
		self.cl.animations.koIn = {
			info = self.character:getAnimationInfo( "ko_in" ),
			time = 0,
			weight = 0,
			active = false,
			additive = false
		}
	end
	-- Whole body loop
	if not self.cl.animations.koLoop then
		self.cl.animations.koLoop = {
			info = self.character:getAnimationInfo( "ko_loop" ),
			time = 0,
			weight = 0,
			active = false,
			looping = true,
			additive = false
		}
	end
	-- Lower body forward
	if not self.cl.animations.koOutForward then
		self.cl.animations.koOutForward = {
			info = self.character:getAnimationInfo( "ko_out_legs_f" ),
			time = 0,
			weight = 0,
			active = false,
			additive = true
		}
	end
	-- Lower body left
	if not self.cl.animations.koOutLeft then
		self.cl.animations.koOutLeft = {
			info = self.character:getAnimationInfo( "ko_out_legs_l" ),
			time = 0,
			weight = 0,
			active = false,
			additive = true
		}
	end
	-- Lower body right
	if not self.cl.animations.koOutRight then
		self.cl.animations.koOutRight = {
			info = self.character:getAnimationInfo( "ko_out_legs_r" ),
			time = 0,
			weight = 0,
			active = false,
			additive = true
		}
	end
	-- Lower body back
	if not self.cl.animations.koOutBack then
		self.cl.animations.koOutBack = {
			info = self.character:getAnimationInfo( "ko_out_legs_b" ),
			time = 0,
			weight = 0,
			active = false,
			additive = true
		}
	end
	-- Upper body
	if not self.cl.animations.koOut then
		self.cl.animations.koOut = {
			info = self.character:getAnimationInfo( "ko_out" ),
			time = 0,
			weight = 0,
			active = false,
			additive = false
		}
	end
	if not self.cl.animations.laugh then
		self.cl.animations.laugh = {
			info = self.character:getAnimationInfo( "laugh" ),
			time = 0,
			weight = 0,
			active = false,
			additive = true
		}
	end
	if not self.cl.animations.cinematic then
		self.cl.animations.cinematic = {
			info = self.character:getAnimationInfo( "cinematic_spawn_01" ),
			time = 0,
			weight = 0,
			active = false,
			additive = false
		}
	end

	if not self.cl.animations.underground_cinematic then
		self.cl.animations.underground_cinematic = {
			info = self.character:getAnimationInfo( "cinematic_spawn_02" ),
			time = 0,
			weight = 0,
			active = false,
			additive = false
		}
	end

	if not self.cl.animations.defeat_cinematic then
		self.cl.animations.defeat_cinematic = {
			info = self.character:getAnimationInfo( "cinematic_despawn_01" ),
			time = 0,
			weight = 0,
			active = false,
			additive = false
		}
	end

	if not self.cl.animations.bpose_openeye then
		self.cl.animations.bpose_openeye = {
			info = self.character:getAnimationInfo( "bpose_openeye" ),
			time = 0,
			weight = 0,
			active = false,
			additive = true,
			looping = false
		}
	end

	if not self.cl.animations.alerted then
		self.cl.animations.alerted = {
			info = self.character:getAnimationInfo( "alerted" ),
			time = 0,
			weight = 0,
			active = false,
			additive = false
		}
	end

	if not self.cl.animations.sprayground_in then
		self.cl.animations.sprayground_in = {
			info = self.character:getAnimationInfo( "sprayground_in" ),
			time = 0,
			weight = 0,
			active = false,
			additive = false
		}
	end

	if not self.cl.animations.sprayground_out then
		self.cl.animations.sprayground_out = {
			info = self.character:getAnimationInfo( "sprayground_out" ),
			time = 0,
			weight = 0,
			active = false,
			additive = false
		}
	end

	if not self.cl.animations.sprayground_loop then
		self.cl.animations.sprayground_loop = {
			info = self.character:getAnimationInfo( "sprayground_loop" ),
			time = 0,
			weight = 0,
			active = false,
			additive = false,
			looping = true
		}
	end

	if not self.cl.animations.volley_in then
		self.cl.animations.volley_in = {
			info = self.character:getAnimationInfo( "volley_in" ),
			time = 0,
			weight = 0,
			active = false,
			additive = false
		}
	end

	if not self.cl.animations.volley_out then
		self.cl.animations.volley_out = {
			info = self.character:getAnimationInfo( "volley_out" ),
			time = 0,
			weight = 0,
			active = false,
			additive = false
		}
	end

	if not self.cl.animations.volley_loop then
		self.cl.animations.volley_loop = {
			info = self.character:getAnimationInfo( "volley_loop" ),
			time = 0,
			weight = 0,
			active = false,
			additive = false,
			looping = true
		}
	end

	if not self.cl.animations.sprinklerLeft_in then
		self.cl.animations.sprinklerLeft_in = {
			info = self.character:getAnimationInfo( "sprinkler_l_in" ),
			time = 0,
			weight = 0,
			active = false,
			additive = true,
			looping = false
		}
	end

	if not self.cl.animations.sprinklerLeft_loop then
		self.cl.animations.sprinklerLeft_loop = {
			info = self.character:getAnimationInfo( "sprinkler_l_loop" ),
			time = 0,
			weight = 0,
			active = false,
			additive = true,
			looping = true
		}
	end

	if not self.cl.animations.sprinklerLeft_out then
		self.cl.animations.sprinklerLeft_out = {
			info = self.character:getAnimationInfo( "sprinkler_l_out" ),
			time = 0,
			weight = 0,
			active = false,
			additive = true,
			looping = false
		}
	end

	if not self.cl.animations.sprinklerRight_in then
		self.cl.animations.sprinklerRight_in = {
			info = self.character:getAnimationInfo( "sprinkler_r_in" ),
			time = 0,
			weight = 0,
			active = false,
			additive = true,
			looping = false
		}
	end

	if not self.cl.animations.sprinklerRight_loop then
		self.cl.animations.sprinklerRight_loop = {
			info = self.character:getAnimationInfo( "sprinkler_r_loop" ),
			time = 0,
			weight = 0,
			active = false,
			additive = true,
			looping = true
		}
	end

	if not self.cl.animations.sprinklerRight_out then
		self.cl.animations.sprinklerRight_out = {
			info = self.character:getAnimationInfo( "sprinkler_r_out" ),
			time = 0,
			weight = 0,
			active = false,
			additive = true,
			looping = false
		}
	end

	if not self.cl.animations.sprayLeft_in then
		self.cl.animations.sprayLeft_in = {
			info = self.character:getAnimationInfo( "spray_l_in" ),
			time = 0,
			weight = 0,
			active = false,
			additive = true,
			looping = false
		}
	end

	if not self.cl.animations.sprayLeft_loop then
		self.cl.animations.sprayLeft_loop = {
			info = self.character:getAnimationInfo( "spray_l_loop" ),
			time = 0,
			weight = 0,
			active = false,
			additive = true,
			looping = true
		}
	end

	if not self.cl.animations.sprayLeft_out then
		self.cl.animations.sprayLeft_out = {
			info = self.character:getAnimationInfo( "spray_l_out" ),
			time = 0,
			weight = 0,
			active = false,
			additive = true,
			looping = false
		}
	end

	if not self.cl.animations.sprayRight_in then
		self.cl.animations.sprayRight_in = {
			info = self.character:getAnimationInfo( "spray_r_in" ),
			time = 0,
			weight = 0,
			active = false,
			additive = true,
			looping = false
		}
	end

	if not self.cl.animations.sprayRight_loop then
		self.cl.animations.sprayRight_loop = {
			info = self.character:getAnimationInfo( "spray_r_loop" ),
			time = 0,
			weight = 0,
			active = false,
			additive = true,
			looping = true
		}
	end

	if not self.cl.animations.sprayRight_out then
		self.cl.animations.sprayRight_out = {
			info = self.character:getAnimationInfo( "spray_r_out" ),
			time = 0,
			weight = 0,
			active = false,
			additive = true,
			looping = false
		}
	end

	if not self.cl.animations.death_in then
		self.cl.animations.death_in = {
			info = self.character:getAnimationInfo( "death_in" ),
			time = 0,
			weight = 0,
			active = false,
			additive = false,
			nextAnimation = "death_loop"
		}
	end

	if not self.cl.animations.death_loop then
		self.cl.animations.death_loop = {
			info = self.character:getAnimationInfo( "death_loop" ),
			time = 0,
			weight = 0,
			active = false,
			additive = false,
			looping = true
		}
	end
	if not self.cl.animations.neardeath_in then
		self.cl.animations.neardeath_in = {
			info = self.character:getAnimationInfo( "neardeath_in" ),
			time = 0,
			weight = 0,
			active = false,
			additive = false
		}
	end

	if not self.cl.animations.neardeath_loop then
		self.cl.animations.neardeath_loop = {
			info = self.character:getAnimationInfo( "neardeath_loop" ),
			time = 0,
			weight = 0,
			active = false,
			additive = false,
			looping = true
		}
	end

	if not self.cl.animations.death_loop_pulse then
		self.cl.animations.death_loop_pulse = {
			info = self.character:getAnimationInfo( "death_loop_pulse" ),
			time = 0,
			weight = 0,
			active = false,
			additive = true
		}
	end

	if not self.cl.animations.broom_loop then
		self.cl.animations.broom_loop = {
			info = self.character:getAnimationInfo( "broom_loop" ),
			time = 0,
			weight = 0,
			active = false,
			additive = true,
			looping = true
		}
	end

	self.animationsLoaded = true

	self.cl.blendSpeed = 5.0
end

function TrashbotCharacter.cl_getQuadDirection( self )
	local directionDots = {}
	directionDots[#directionDots+1] = { direction = QuadDirection.FORWARD, dot = self.cl.lookDirection:dot( self.cl.spawnDirection ) }
	directionDots[#directionDots+1] = { direction = QuadDirection.LEFT, dot = self.cl.lookDirection:dot( self.cl.spawnDirection:rotateZ( -90.0 * math.pi / 180 ) ) }
	directionDots[#directionDots+1] = { direction = QuadDirection.RIGHT, dot = self.cl.lookDirection:dot( self.cl.spawnDirection:rotateZ( 90.0 * math.pi / 180 ) ) }
	directionDots[#directionDots+1] = { direction = QuadDirection.BACK, dot = self.cl.lookDirection:dot( -self.cl.spawnDirection ) }
	table.sort( directionDots, function( a, b ) return a.dot > b.dot end )
	return directionDots[1].direction
end

function TrashbotCharacter.client_onFixedUpdate( self )
	if not self.graphicsLoaded then
		return
	end
	if self.cl.eyeEffectTimer and self.cl.eyeEffectTimer:isActive() then
		self.cl.eyeEffectTimer:tick()
		if self.cl.eyeEffectTimer:done() then
			self.cl.eyeEffectTimer:stop()
			self.cl.eyeGlowEffect:start()
			self.cl.eyeOpen = true
		end
	end

	for joint,kinematic in pairs( self.cl.kinematicPieces ) do
		if kinematic and sm.exists( kinematic ) then
			local bonePos = self.character:getTpBonePos( joint )
			local boneRot = self.character:getTpBoneRot( joint )
			if bonePos then
				kinematic:setPosition( bonePos )
			end
			if boneRot then
				kinematic:setRotation( boneRot )
			end
		end
	end

	if self.cl.hasBossMusicControl then
		if self:cl_isLocalPlayerInBossRadius() then
			self:cl_startBossMusic()
		else
			self:cl_stopBossMusic()
		end
	end
end

function TrashbotCharacter.cl_isAiming( self )
	if self.cl.animations then
		return ( self.cl.animations.sprayLeft_loop.active or self.cl.animations.sprayRight_loop.active or self.cl.animations.chargeRight.active or self.cl.animations.chargeLeft.active or
			self.cl.animations.sprayLeft_in.active or self.cl.animations.sprayLeft_out.active or self.cl.animations.sprayRight_in.active or self.cl.animations.sprayRight_out.active )
	else
		return false
	end
end

function TrashbotCharacter.client_onUpdate( self, deltaTime )
	if not self.graphicsLoaded then
		return
	end

	if self.cl.latestMissedEvent ~= nil then
		self:cl_handleEvent( self.cl.latestMissedEvent )
		self.cl.latestMissedEvent = nil
	end

	-- Move the eye trigger to character's eye
	self.cl.eyeAreaTrigger:setWorldPosition( self.character:getTpBonePos( "head_jnt" ) )
	self.cl.eyeAreaTrigger:setWorldRotation( self.character:getTpBoneRot( "head_jnt" ) )

	-- Toggle battery effect
	if self.cl.animations.koLoop.active then
		if not self.cl.batteryLoopEffect:isPlaying() then
			self.cl.batteryLoopEffect:start()
		end
	else
		if self.cl.batteryLoopEffect:isPlaying() then
			self.cl.batteryLoopEffect:stop()
		end
	end

	-- Update look direction and spine bending animations
	local headPosition = self.character.worldPosition + sm.vec3.new( 0, 0, 2 )
	if self.cl.target and sm.exists( self.cl.target ) and self.cl.lookingAtTarget and not self.cl.rotate then
		local fromToTarget = self.cl.target.worldPosition - headPosition
		local flatFromToTarget = sm.vec3.new( fromToTarget.x, fromToTarget.y, 0 )
		local wantedFlatLookDirection = flatFromToTarget:safeNormalize( self.cl.lookDirection )

		-- Radians to rotate this step
		local radiansToRotate = math.acos( clamp( self.cl.lookDirection:dot( wantedFlatLookDirection ), -1, 1 ) )
		local rotationStep = math.min( ( self:cl_isAiming() and AimedRadiansPerSecond or LookMaxRadiansPerSecond ) * deltaTime, radiansToRotate )

		-- Find which direction to rotate
		local rotationZ = 0.0
		local determinant = wantedFlatLookDirection.x * self.cl.lookDirection.y - wantedFlatLookDirection.y * self.cl.lookDirection.x
		if determinant <= -FLT_EPSILON then
			rotationZ = rotationStep
		elseif determinant >= FLT_EPSILON then
			rotationZ = -rotationStep
		end
		-- Update look direction
		self.cl.lookDirection = ( self.cl.lookDirection:rotateZ( rotationZ ) ):safeNormalize( self.cl.lookDirection )

		-- Update spine bend up/down
		local targetLookDirection = ( fromToTarget ):safeNormalize( self.cl.lookDirection )
		local upDownAngleFraction = math.asin( targetLookDirection:dot( sm.vec3.new( 0, 0, 1 ) ) ) / ( math.pi / 2 )
		local desiredUpDownAnimationFraction = ( 0.5 + upDownAngleFraction * 0.5 )
		self.cl.headUpDownFraction = magicInterpolation( self.cl.headUpDownFraction, desiredUpDownAnimationFraction, deltaTime, 1.0 / 8.0 )

		-- Update spine bend right/left
		local rightLeftAngle = math.acos( clamp( self.cl.lookDirection:dot( wantedFlatLookDirection ), -1, 1 ) )
		local spineDeterminant = wantedFlatLookDirection.x * self.cl.lookDirection.y - wantedFlatLookDirection.y * self.cl.lookDirection.x
		if spineDeterminant >= FLT_EPSILON then
			rightLeftAngle = -rightLeftAngle
		end
		local rightLeftAngleFraction = clamp( rightLeftAngle / ( math.pi / 2 ), -1, 1 )
		local desiredRightLeftAnimationFraction = ( 0.5 + rightLeftAngleFraction * 0.5 )
		self.cl.headLeftRightFraction = magicInterpolation( self.cl.headLeftRightFraction, desiredRightLeftAnimationFraction, deltaTime, 1.0 / 15.0 )
	elseif self.cl.rotate then
		self.cl.lookDirection = self.cl.lookDirection:rotateZ( LookMaxRadiansPerSecond * deltaTime ):safeNormalize( self.cl.lookDirection )
		self.cl.headUpDownFraction = magicInterpolation( self.cl.headUpDownFraction, 0.5, deltaTime, 1.0 / 8.0 )
		self.cl.headLeftRightFraction = magicInterpolation( self.cl.headLeftRightFraction, 0.5, deltaTime, 1.0 / 15.0 )
	else
		self.cl.headUpDownFraction = magicInterpolation( self.cl.headUpDownFraction, 0.5, deltaTime, 1.0 / 8.0 )
		self.cl.headLeftRightFraction = magicInterpolation( self.cl.headLeftRightFraction, 0.5, deltaTime, 1.0 / 15.0 )

		-- Look towards closest axis
		self.cl.lookDirection = sm.vec3.closestAxis( self.cl.lookDirection )
	end

	-- Update turret rotation
	local baseForward = self.character.direction
	local turretAngle = math.acos( clamp( baseForward:dot( self.cl.lookDirection ), -1, 1 ) )
	local desiredTurretAngleFraction = turretAngle / ( math.pi * 2 )
	local turretDeterminant = self.cl.lookDirection.x * baseForward.y - self.cl.lookDirection.y * baseForward.x
	if turretDeterminant >= FLT_EPSILON then
		desiredTurretAngleFraction = 1.0 - desiredTurretAngleFraction
	end
	local shortestFractionDiff = ( ( ( ( desiredTurretAngleFraction - self.cl.turretFraction ) % 1.0 ) + 1.5 ) % 1.0 ) - 0.5
	local wraparoundFraction = magicInterpolation( self.cl.turretFraction, self.cl.turretFraction + shortestFractionDiff, deltaTime, 1.0 / 15.0 )
	self.cl.turretFraction = wraparoundFraction % 1.0

	self.character:updateAnimation( "aimbend_updown", 1.0 - self.cl.headUpDownFraction, 1.0, true )
	self.character:updateAnimation( "aimbend_rightleft", self.cl.headLeftRightFraction, 1.0, true )
	self.character:updateAnimation( "turretbend", self.cl.turretFraction, 1.0, true )

















	-- Update animations
	local totalNonAdditiveWeight = 0.0
	local loopedNames = {}
	for name, animation in pairs(self.cl.animations) do
		loopedNames[name] = true
		if animation.info then
			if name == "bpose_openeye" then
				if self.cl.eyeOpen then
					animation.time = math.min( animation.time + deltaTime, animation.info.duration )
				else
					animation.time = math.max( animation.time - deltaTime, 0.0 )
				end
			else
				animation.time = animation.time + deltaTime
			end

			if name == self.cl.currentAnimation then
				if animation.disableMovementAnimations then
					animation.weight = 1.0
					self.character:setMovementWeights( 0, 0 )
				else
					animation.weight = math.min(animation.weight+(self.cl.blendSpeed * deltaTime), 1.0)
					self.character:setMovementWeights( 1, 1 )
				end
				if animation.time >= animation.info.duration then
					if animation.looping then
						animation.time = animation.time % animation.info.duration
					else
						self.cl.currentAnimation = animation.nextAnimation or ""
						if self.cl.currentAnimation ~= "" then
							if loopedNames[self.cl.currentAnimation] == nil then
								self.cl.animations[self.cl.currentAnimation].time = 0
							else
								self.cl.animations[self.cl.currentAnimation].time = deltaTime
								self.character:updateAnimation( self.cl.animations[self.cl.currentAnimation].info.name, self.cl.animations[self.cl.currentAnimation].time, self.cl.animations[self.cl.currentAnimation].weight, self.cl.animations[self.cl.currentAnimation].additive )
							end
						end
						if animation.disableMovementAnimations then
							self.character:setMovementWeights( 1, 1 )
						end
					end
				end
			elseif animation.active then
				if animation.disableMovementAnimations then
					animation.weight = 1.0
					self.character:setMovementWeights( 0, 0 )
				else
					animation.weight = math.min(animation.weight+(self.cl.blendSpeed * deltaTime), 1.0)
					if name == "koLoop" then
						animation.weight = 1.0
					end
					self.character:setMovementWeights( 1, 1 )
				end
				if ( animation.time >= animation.info.duration or animation.time < 0 ) and name ~= "bpose_openeye" then
					if animation.looping then
						animation.time = animation.time % animation.info.duration
					else
						self.cl.animations[name].active = false
						if animation.disableMovementAnimations then
							self.character:setMovementWeights( 1, 1 )
						end
					end

					-- Special case, immediately go to koLoop after completing koIn
					if name == "koIn" then
						animation.weight = 0.0
						self.cl.animations.koLoop.active = true
						self.cl.animations.koLoop.time = 0
						self.character:updateAnimation( self.cl.animations.koLoop.info.name, 0, 1, self.cl.animations.koLoop.additive )
						self.cl.currentInAnimation.weight = 0.0
						self.cl.currentInAnimation.time = 0.0
						self.cl.currentInAnimation.active = false
						self.character:updateAnimation( self.cl.currentInAnimation.info.name, 0, 0, self.cl.currentInAnimation.additive )
					end
				end
			else
				if animation.disableMovementAnimations then
					animation.weight = 0.0
				else
					animation.weight = math.max(animation.weight-( self.cl.blendSpeed * deltaTime ), 0.0)
				end
			end

			if not animation.additive then
				totalNonAdditiveWeight = totalNonAdditiveWeight + animation.weight
			end
			self.character:updateAnimation( animation.info.name, animation.time, animation.weight, animation.additive )
		end
	end
	
	-- Default to playing idle arms
	self.cl.animations.idleLeftAnimation.active = true
	self.cl.animations.idleRightAnimation.active = true
	-- Turn off arm idles when playing center animations
	if totalNonAdditiveWeight >= 1.0 then
		self.cl.animations.idleLeftAnimation.active = false
		self.cl.animations.idleRightAnimation.active = false
	end
	-- Turn off left idle when playing left animations
	if self.cl.animations.idleLeftAnimation.active then
		for _, animationName in ipairs( self.cl.leftArmAnimations ) do
			local animation = self.cl.animations[animationName]
			if animation and animation.active then
				self.cl.animations.idleLeftAnimation.active = false
				break
			end
		end
	end
	-- Turn off right idle when playing right animations
	if self.cl.animations.idleRightAnimation.active then
		for _, animationName in ipairs( self.cl.rightArmAnimations ) do
			local animation = self.cl.animations[animationName]
			if animation and animation.active then
				self.cl.animations.idleRightAnimation.active = false
				break
			end
		end
	end
end

function TrashbotCharacter.client_onEvent( self, event )
	self:cl_handleEvent( event )
end

function TrashbotCharacter.cl_handleEvent( self, event )
	if not self.animationsLoaded then
		self.cl.latestMissedEvent = event
		return
	end

	if event == "stomp" then
		self.cl.animations.stomp.active = true
		self.cl.animations.stomp.time = 0
	elseif event == "rotate" then
		self.cl.rotate = true
	elseif event == "stopRotate" then
		self.cl.rotate = false
	elseif event == "shoot01" then
		self.cl.currentAnimation = "shoot01"
		self.cl.animations.shoot01.time = 0
	elseif event == "shoot02" then
		self.cl.currentAnimation = "shoot02"
		self.cl.animations.shoot02.time = 0
	elseif event == "volleyLeft" then
		self.cl.animations.volleyLeft.active = true
		self.cl.animations.volleyLeft.time = 0
	elseif event == "volleyRight" then
		self.cl.animations.volleyRight.active = true
		self.cl.animations.volleyRight.time = 0
		
	elseif event == "chargeBulletRight" then
		self.cl.animations.chargeRight.active = true
		self.cl.animations.chargeRight.time = 0
		if self.graphicsLoaded then
			self.cl.chargingEffectRight:start()
		end
	elseif event == "chargeBulletLeft" then
		self.cl.animations.chargeLeft.active = true
		self.cl.animations.chargeLeft.time = 0
		if self.graphicsLoaded then
			self.cl.chargingEffectLeft:start()
		end
	elseif event == "shootChargedBulletRight" then
		if self.graphicsLoaded then
			self.cl.chargingEffectRight:stop()
		end
	elseif event == "shootChargedBulletLeft" then
		if self.graphicsLoaded then
			self.cl.chargingEffectLeft:stop()
		end
	elseif event == "startPushback" then
		self.cl.currentAnimation = "pushback"
		self.cl.animations.pushback.time = 0
		if self.graphicsLoaded then
			self.cl.pushbackEffect:start()
		end
	elseif event == "endPushback" then
		if self.graphicsLoaded then
			self.cl.pushbackEffect:stop()
		end
	elseif event == "barf01" then
		self.cl.animations.barf01.active = true
		self.cl.animations.barf01.time = 0
	elseif event == "laugh" then
		self.cl.animations.laugh.active = true
		self.cl.animations.laugh.time = 0
	elseif event == "cinematic" then
		self.cl.animations.cinematic.active = true
		self.cl.animations.cinematic.time = 0
		if self.graphicsLoaded then
			self.cl.cinematicEffect:start()
			self.cl.cinematicRoarEffect:start()
		end
	elseif event == "underground_cinematic" then
		self.cl.animations.underground_cinematic.active = true
		self.cl.animations.underground_cinematic.time = 0
		if self.graphicsLoaded then
			self.cl.cinematicUndergroundEffect:start()
			self.cl.cinematicRoarUndergroundEffect:start()
		end
	elseif event == "think" then
		self.cl.currentAnimation = ""
	elseif event == "koDmg" then
		self.cl.animations.koDmg.active = true
		self.cl.animations.koDmg.time = 0
		if self.graphicsLoaded then
			sm.effect.playHostedEffect( "Trashbot - Battery Lightning Damage", self.character, "powercore_05_jnt" )
		end
	elseif event == "koFinal" then
		self.cl.animations.koDmg.active = true
		self.cl.animations.koDmg.time = 0
		if self.graphicsLoaded then
			sm.effect.playHostedEffect( "Trashbot - Battery Destruct", self.character, "powercore_05_jnt" )
		end
	elseif event == "koIn" then
		self.cl.animations.koIn.active = true
		self.cl.animations.koIn.time = 0
		self.cl.animations.bpose_openeye.active = true
		self.cl.eyeOpen = false
		-- Select correct depending on direction
		if self:cl_getQuadDirection() == QuadDirection.FORWARD then
			self.cl.animations.koInForward.active = true
			self.cl.animations.koInForward.time = 0
			self.cl.currentInAnimation = self.cl.animations.koInForward
		elseif self:cl_getQuadDirection() == QuadDirection.LEFT then
			self.cl.animations.koInLeft.active = true
			self.cl.animations.koInLeft.time = 0
			self.cl.currentInAnimation = self.cl.animations.koInLeft
		elseif self:cl_getQuadDirection() == QuadDirection.RIGHT then
			self.cl.animations.koInRight.active = true
			self.cl.animations.koInRight.time = 0
			self.cl.currentInAnimation = self.cl.animations.koInRight
		elseif self:cl_getQuadDirection() == QuadDirection.BACK then
			self.cl.animations.koInBack.active = true
			self.cl.animations.koInBack.time = 0
			self.cl.currentInAnimation = self.cl.animations.koInBack
		end
	elseif event == "koOut" then
		self.cl.animations.koOut.active = true
		self.cl.animations.koOut.time = 0

		-- Select correct depending on direction
		if self:cl_getQuadDirection() == QuadDirection.FORWARD then
			self.cl.animations.koOutForward.active = true
			self.cl.animations.koOutForward.time = 0
		elseif self:cl_getQuadDirection() == QuadDirection.LEFT then
			self.cl.animations.koOutLeft.active = true
			self.cl.animations.koOutLeft.time = 0
		elseif self:cl_getQuadDirection() == QuadDirection.RIGHT then
			self.cl.animations.koOutRight.active = true
			self.cl.animations.koOutRight.time = 0
		elseif self:cl_getQuadDirection() == QuadDirection.BACK then
			self.cl.animations.koOutBack.active = true
			self.cl.animations.koOutBack.time = 0
		end

		-- Turn off idle
		self.cl.animations.koIn.active = false
		self.cl.animations.koIn.time = 0
		self.cl.animations.koLoop.active = false
		self.cl.animations.koLoop.time = 0

		-- Safe to turn off all directional variants
		self.cl.animations.koInForward.active = false
		self.cl.animations.koInForward.time = 0

		self.cl.animations.koInLeft.active = false
		self.cl.animations.koInLeft.time = 0

		self.cl.animations.koInRight.active = false
		self.cl.animations.koInRight.time = 0

		self.cl.animations.koInBack.active = false
		self.cl.animations.koInBack.time = 0
	elseif event == "hurteye" then
		self.cl.animations.hurt.active = true
		self.cl.animations.hurt.time = 0
	elseif event == "eyeOpen" then
		self.cl.animations.bpose_openeye.active = true
		self.cl.animations.bpose_openeye.time = 0
		if self.cl.eyeOpen == false then
			self.cl.eyeOpenEffect:start()
			self.cl.eyeEffectTimer:start( EyeEffectDelayTime )
		end
	elseif event == "eyeClose" then
		self.cl.animations.bpose_openeye.active = true
		self.cl.animations.bpose_openeye.time = self.cl.animations.bpose_openeye.info.duration
		if self.cl.eyeOpen == true then
			self.cl.eyeCloseEffect:start()
		end
		self.cl.eyeOpen = false
		self.cl.eyeGlowEffect:stopImmediate()
	elseif event == "removeProjectiles" then
		sm.projectile.removeProjectilesWithSource( self.character, StunTicks, self.character:getWorld() )
	elseif event == "escape" then
		self.cl.currentAnimation = "cinematic_despawn_01"
		self.cl.animations.defeat_cinematic.active = true
		self.cl.animations.defeat_cinematic.time = 0
		self.cl.lookDirection = self.cl.spawnDirection
		self:cl_n_toggleLookAtTarget( { lookAtTarget = nil } )
	elseif event == "alerted" then
		self.cl.currentAnimation = "alerted"
		self.cl.animations.alerted.active = true
		self.cl.animations.alerted.time = 0
		self.cl.isAlerted = true
	elseif event == "sprayground_in" then
		self.cl.currentAnimation = "sprayground_in"
		self.cl.animations.sprayground_in.active = true
		self.cl.animations.sprayground_in.time = 0
	elseif event == "sprayground_out" then
		self.cl.currentAnimation = "sprayground_out"
		self.cl.animations.sprayground_loop.active = false
		self.cl.animations.sprayground_out.active = true
		self.cl.animations.sprayground_out.time = 0
		self.cl.groundSwirlIntense:stop()
		self.cl.groundSprayLeftArmEffect:stop()
		self.cl.groundSprayRightArmEffect:stop()
	elseif event == "sprayground_loop" then
		self.cl.currentAnimation = "sprayground_loop"
		self.cl.animations.sprayground_in.active = false
		self.cl.animations.sprayground_loop.active = true
		self.cl.animations.sprayground_loop.time = 0
		self.cl.groundSwirlIntense:start()
		self.cl.groundSprayLeftArmEffect:start()
		self.cl.groundSprayRightArmEffect:start()
	elseif event == "volley_in" then
		self.cl.currentAnimation = "volley_in"
		self.cl.animations.volley_in.active = true
		self.cl.animations.volley_in.time = 0
	elseif event == "volley_out" then
		self.cl.currentAnimation = "volley_out"
		self.cl.animations.volley_loop.active = false
		self.cl.animations.volley_out.active = true
		self.cl.animations.volley_out.time = 0
	elseif event == "volley_loop" then
		self.cl.currentAnimation = "volley_loop"
		self.cl.animations.volley_loop.active = true
		self.cl.animations.volley_in.active = false
		self.cl.animations.volley_loop.time = 0
	elseif event == "sprinkler_left_in" then
		self.cl.animations.sprinklerLeft_in.active = true
		self.cl.animations.sprinklerLeft_in.time = 0
	elseif event == "sprinkler_left_loop" then
		self.cl.animations.sprinklerLeft_loop.active = true
		self.cl.animations.sprinklerLeft_loop.time = 0
		self.cl.animations.sprinklerLeft_in.active = false
	elseif event == "sprinkler_left_out" then
		self.cl.animations.sprinklerLeft_out.active = true
		self.cl.animations.sprinklerLeft_out.time = 0
		self.cl.animations.sprinklerLeft_loop.active = false
	elseif event == "sprinkler_right_in" then
		self.cl.animations.sprinklerRight_in.active = true
		self.cl.animations.sprinklerRight_in.time = 0
	elseif event == "sprinkler_right_loop" then
		self.cl.animations.sprinklerRight_loop.active = true
		self.cl.animations.sprinklerRight_loop.time = 0
		self.cl.animations.sprinklerRight_in.active = false
	elseif event == "sprinkler_right_out" then
		self.cl.animations.sprinklerRight_out.active = true
		self.cl.animations.sprinklerRight_out.time = 0
		self.cl.animations.sprinklerRight_loop.active = false
	elseif event == "spray_left_in" then
		self.cl.animations.sprayLeft_in.active = true
		self.cl.animations.sprayLeft_in.time = 0
	elseif event == "spray_left_loop" then
		self.cl.animations.sprayLeft_loop.active = true
		self.cl.animations.sprayLeft_loop.time = 0
		self.cl.animations.sprayLeft_in.active = false
	elseif event == "spray_left_out" then
		self.cl.animations.sprayLeft_out.active = true
		self.cl.animations.sprayLeft_out.time = 0
		self.cl.animations.sprayLeft_loop.active = false
	elseif event == "spray_right_in" then
		self.cl.animations.sprayRight_in.active = true
		self.cl.animations.sprayRight_in.time = 0
	elseif event == "spray_right_loop" then
		self.cl.animations.sprayRight_loop.active = true
		self.cl.animations.sprayRight_loop.time = 0
		self.cl.animations.sprayRight_in.active = false
	elseif event == "spray_right_out" then
		self.cl.animations.sprayRight_out.active = true
		self.cl.animations.sprayRight_out.time = 0
		self.cl.animations.sprayRight_loop.active = false
	elseif event == "neardeath_in" then
		self.cl.animations.neardeath_in.active = true
		self.cl.animations.neardeath_in.time = 0
		self.cl.animations.bpose_openeye.active = false
		self.cl.eyeGlowEffect:stopImmediate()
	elseif event == "neardeath_loop" then
		self.cl.animations.neardeath_loop.active = true
		self.cl.animations.neardeath_loop.time = 0
		self.cl.animations.neardeath_loop.weight = 1
		self.cl.animations.neardeath_in.weight = 0
		self.cl.animations.neardeath_in.time = 0
		self.cl.animations.neardeath_in.active = false
		self.cl.eyeOpen = false
		self.cl.eyeGlowEffect:stopImmediate()
	elseif event == "destroy" then
		self.cl.currentAnimation = "death_in"
		self.cl.animations.death_in.active = true
		self.cl.animations.death_in.time = 0
		self.cl.animations.death_in.weight = 1
		self.cl.animations.neardeath_loop.weight = 0
		self.cl.animations.neardeath_loop.active = false
		self.cl.animations.bpose_openeye.active = true
		self.cl.eyeOpen = false
		self.cl.eyeGlowEffect:stopImmediate()
		self.cl.animations.death_loop_pulse.active = true
		self.cl.animations.death_loop_pulse.time = 0
		self.cl.animations.death_loop_pulse.weight = 1
	elseif event == "phase3" then
		for _,effectData in ipairs( self.cl.bleedEffectsData ) do
			if effectData.phase <= 3 then
				if not effectData.effect:isPlaying() then
					effectData.effect:start()
				end
			end
		end
	elseif event == "phase4" then
		for _,effectData in ipairs( self.cl.bleedEffectsData ) do
			if effectData.phase <= 4 then
				if not effectData.effect:isPlaying() then
					effectData.effect:start()
				end
			end
		end
	end
	if event ~= "stop" then
		if not isAnyOf( event, NonBroomAnims ) then
			self.cl.animations.broom_loop.active = true
			if self.cl.floorSwirlEffect ~= nil and not self.cl.floorSwirlEffect:isPlaying() then
				self.cl.floorSwirlEffect:start()
			end
		else
			self.cl.animations.broom_loop.active = false
			if self.cl.floorSwirlEffect ~= nil and self.cl.floorSwirlEffect:isPlaying() then
				self.cl.floorSwirlEffect:stop()
				self.cl.eyeGlowEffect:stopImmediate()
			end
		end
	end
end

function TrashbotCharacter.sv_e_setFightType( self, params )
	self.network:setClientData( params, 3 )
end

function TrashbotCharacter.sv_e_setBossMusicControl( self, control )
	self.network:setClientData( { control = control }, 4 )
end

function TrashbotCharacter.cl_setBossMusicControl( self, control )
	self.cl.hasBossMusicControl = control == true
end

function TrashbotCharacter.cl_isLocalPlayerInBossRadius( self )
	local player = sm.localPlayer.getPlayer()
	if not player then
		return false
	end
	local playerCharacter = player:getCharacter()
	if not playerCharacter or not sm.exists( playerCharacter ) or not sm.exists( self.character ) then
		return false
	end
	if playerCharacter:getWorld() ~= self.character:getWorld() then
		return false
	end
	local delta = playerCharacter.worldPosition - self.character.worldPosition
	-- Truncated sphere: full radius horizontally, half the radius vertically.
	if math.abs( delta.z ) > BossMusicRadius * 0.5 then
		return false
	end
	return ( delta.x * delta.x + delta.y * delta.y ) <= ( BossMusicRadius * BossMusicRadius )
end

function TrashbotCharacter.cl_startBossMusic( self )
	if not self.cl.bossMusicEffect then
		self.cl.bossMusicEffect = sm.effect.createEffect( "Trashbot - Music" )
	end
	if not self.cl.bossMusicEffect:isPlaying() then
		self.cl.bossMusicEffect:start()
	end
end

function TrashbotCharacter.cl_stopBossMusic( self )
	if self.cl.bossMusicEffect and self.cl.bossMusicEffect:isPlaying() then
		self.cl.bossMusicEffect:stop()
		sm.effect.playEffect( "audio:event:/music/stop_bossmusic" )
	end
end

function TrashbotCharacter.sv_e_updateTarget( self, params )
	self.network:sendToClients( "cl_n_updateTarget", params )
end

function TrashbotCharacter.cl_n_updateTarget( self, params )
	self.cl.target = params.target
end

function TrashbotCharacter.sv_e_toggleLookAtTarget( self, params )
	self.network:setClientData( params, 2 )
end

function TrashbotCharacter.cl_n_toggleLookAtTarget( self, params )
	self.cl.lookingAtTarget = params.lookAtTarget
end

function TrashbotCharacter.sv_e_characterEffect( self, params )
	self.network:sendToClients( "cl_n_characterEffect", params )
end

function TrashbotCharacter.cl_n_characterEffect( self, params )
	sm.effect.playHostedEffect( params.effectName, self.character, params.jointName, params.effectParams )
end

function TrashbotCharacter.sv_e_partEffect( self, params )
	self.network:sendToClients( "cl_n_partEffect", params )
end

function TrashbotCharacter.cl_n_partEffect( self, params )
	sm.effect.playHostedEffect( "Trashbot - PartGoopTrail", params.SpawnedPart )
end

function TrashbotCharacter.sv_n_eyeHit( self, params )
	local unit = self.character:getUnit()
	if sm.exists( unit ) then
		sm.event.sendToUnit( unit, "sv_e_eyeDamaged", params, sm.event.types.instant )
	end
end

function TrashbotCharacter.cl_t_onProjectile( self, trigger, hitPos, hitTime, hitVelocity, _, attacker, damage, userData, hitNormal, projectileUuid )
	if type( attacker ) == "Player" or type( attacker ) == "Shape" then
		if damage > 0 then
			local up = sm.vec3.new( 0, 0, 1 )
			if sm.isHost then
				self.network:sendToServer( "sv_n_eyeHit", { hitPos = hitPos, direction = sm.vec3.getRotation( up, self.cl.lookDirection ), hitVelocity = hitVelocity, projectileType = projectileUuid } )
			end
		end
	end

	-- Destroy projectile
	return true
end