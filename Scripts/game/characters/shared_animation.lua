dofile( "$SURVIVAL_DATA/Scripts/util.lua" )

-- Shared animation initialization. Make a table for some .rend of animations, and then call INIT_ANIMATION_REND to initialize them all at once. Used for animation shared between characters.

--char_male_tp_npc_emote.rend
local char_male_tp_npc_emote = {
	emote_hello = true,
	emote_wave = true,
	emote_wave_loop = true,
	emote_l_comehere = true,
	emote_r_comehere = true,
	emote_cheer = true,
	emote_cheer_loop = true,
	emote_clap = true,
	emote_wohoo = true,
	emote_wohoo_loop = true,
	emote_tired = true,
	emote_confused = true,
	emote_use = true,
	emote_cower = true,
	emote_surprised = true,
	emote_give_in = { nextAnimation = "emote_give_loop", instantNext = true },
	emote_give_loop = { nextAnimation = "emote_give_out", inAnimation = "emote_give_in" },
	emote_give_out = true,
	emote_lookaround = true,
	emote_l_point_in = true,
	emote_l_point_loop = { nextAnimation = "emote_l_point_out", inAnimation = "emote_l_point_in" },
	emote_l_point_out = true,
	emote_r_point_in = true,
	emote_r_point_loop = { nextAnimation = "emote_r_point_out", inAnimation = "emote_r_point_in" },
	emote_r_point_out = true,
	emote_scratchbutt = true,
	explain_loop = true,
	emote_l_gesture_in = true,
	emote_l_gesture_loop = true,
	emote_l_gesture_out = true,
	emote_r_gesture_in = true,
	emote_r_gesture_loop = true,
	emote_r_gesture_out = true,
	emote_casual_explain = true,
	emote_casual_explain_out = true,
	emote_thumbup = true,
	emote_doublethumbup = true,
	ko_idle = true,
	revive = true,
	emote_countdown_loop = true,
	emote_cower_loop = true
}

-- Animations for NPCs in endgame cinematic
local engine_blast_reactions = {
	emote_engineblast01 = { nextAnimation = "emote_engineblast_loop", instantNext = true },
	emote_engineblast02 = { nextAnimation = "emote_engineblast_loop", instantNext = true },
	emote_engineblast03 = { nextAnimation = "emote_engineblast_loop", instantNext = true },
	emote_engineblast_loop = true
}

local local_tables = {
	char_male_tp_npc_emote = char_male_tp_npc_emote,
	engine_blast_reactions = engine_blast_reactions,
}


function INIT_ANIMATION( animTable, animatedObject, name, args )

	local getAnimationInfo = (type(animatedObject) == "Character" and animatedObject.getAnimationInfo) or
	function(animatedObject,name)
		local animInfo = {}
		animInfo.name = name
		animInfo.duration = animatedObject:getAnimDuration( animInfo.name  )
		animInfo.looping = animatedObject:isAnimLooping( animInfo.name )
		return animInfo 
	end

	animTable[name] = {
		info = getAnimationInfo( animatedObject,name ),
		time = 0,
		weight = 0
	}
	if type( args ) == "table" then
		for key, value in pairs( args ) do
			animTable[name][key] = value
		end
		if args.controlled then
			animTable[name].current = 0.5
			animTable[name].target = 0.5
		end
	end
end

function INIT_ANIMATION_REND( animTable, character, rendName )
	if local_tables[rendName] then
		for name, v in pairs( local_tables[rendName] ) do
			if v == true then
				INIT_ANIMATION( animTable, character, name )
			else
				INIT_ANIMATION( animTable, character, name, v )
			end
		end
	end
end



CharacterAnimationStrategy = class( nil )
function CharacterAnimationStrategy.update(animatedObject, animations, currentAnimation, blendSpeed, dt)
	for name, animation in pairs(animations) do
		if animation.info and not animation.controlled then
			if name == currentAnimation then
				animation.weight = math.min(animation.weight + (blendSpeed * dt), 1.0)
			else
				animation.weight = math.max(animation.weight - (blendSpeed * dt), 0.0)
			end
			animatedObject:updateAnimation(animation.info.name, animation.time, animation.weight)
		end
	end
end
function CharacterAnimationStrategy.applyControlProgress(animatedObject, animName, progress)
	animatedObject:updateAnimation(animName, 0, progress)
end
function CharacterAnimationStrategy.debugDisplay(animatedObject, animations)
	sm.gui.setCharacterDebugText( animatedObject, "" )
	for name, animation in pairs( animations ) do
		if animation.info and animation.weight > 0 then
			local truncatedWeight = math.floor( animation.weight * 10 + 0.5 ) / 10
			sm.gui.setCharacterDebugText( animatedObject, tostring( name .. " : " .. truncatedWeight ), false )
		end
	end
end


InteractableAnimationStrategy = class( nil )
function InteractableAnimationStrategy.update(animatedObject, animations, currentAnimation, blendSpeed, dt)
	for name, animation in pairs(animations) do
		if animation.info and not animation.controlled then
			if name == currentAnimation then
				animatedObject:setAnimEnabled(animation.info.name, true)
				local progress = animation.info.duration > 0 and animation.time / animation.info.duration or 0
				animatedObject:setAnimProgress(animation.info.name, progress)
			else
				animatedObject:setAnimEnabled(animation.info.name, false)
			end
		end
	end
end
function InteractableAnimationStrategy.applyControlProgress(animatedObject, animName, progress)
	animatedObject:setAnimEnabled(animName, true)
	animatedObject:setAnimProgress(animName, progress)
end
function InteractableAnimationStrategy.debugDisplay(animatedObject, animations)
	local debugLines = {}
	for name, animation in pairs( animations ) do
		if animation.info and animation.weight > 0 then
			local truncatedWeight = math.floor( animation.weight * 10 + 0.5 ) / 10
			table.insert( debugLines, name .. " : " .. truncatedWeight )
		end
	end
	local text = table.concat( debugLines, "\n" )
	sm.debugDraw.addText( "interactable_anim_debug", text, animatedObject:getShape().worldPosition )
end


local Animator = class( nil )

-- Creates a new AnimationController for the given animated object.
-- stateTable is the shared table (e.g. self.cl) where animations, currentAnimation, etc. are stored.
-- Automatically selects the correct strategy based on userdata type (Character or Interactable).
function CREATE_ANIMATOR( animatedObject,animations, blendSpeed, blendTime )
	local strategy 
	if type(animatedObject) == "Character" then
		strategy = CharacterAnimationStrategy()
	elseif type(animatedObject) == "Interactable" then
		strategy = InteractableAnimationStrategy()
	else
		error( "Animated object of type " .. type(animatedObject) .. " is not supported." )
	end

	local controller = Animator()
	controller.strategy = strategy
	controller.animatedObject = animatedObject
	controller.animations = animations or {}
	controller.blendSpeed = blendSpeed or 5.0
	controller.blendTime = blendTime or 0.2
	controller.currentAnimation = nil

	return controller
end

-- Advances all animation timers, handles expiration/transitions, renders via strategy, and interpolates controlled animations.
-- Call once per frame with the delta time.
function Animator.update( self, dt )







	
	-- Third person animations
	for name, animation in pairs(self.animations) do
		if animation.info and not animation.controlled then
			animation.time = animation.time + dt
			local isAnimationFinished = animation.time >= animation.info.duration
			if isAnimationFinished and animation.info.looping then
				animation.time = animation.time - animation.info.duration
			elseif isAnimationFinished and animation.clampWhenFinished then
				animation.time = animation.info.duration
			elseif isAnimationFinished and name == self.currentAnimation then
				self:_animationExpired( self.currentAnimation )
			end
		end
	end

	self.strategy.update( self.animatedObject, self.animations, self.currentAnimation, self.blendSpeed, dt )

	-- Head tracking (computes control targets before interpolation)
	self:_updateHeadTracking()

	-- Interpolated animations
	for name, animation in pairs(self.animations) do
		if animation.controlled and animation.target then
			animation.current = magicInterpolation( animation.current, animation.target, dt, animation.lerpSpeed or 0.1 )
			self.strategy.applyControlProgress( self.animatedObject, animation.info.name, animation.current )
		end
	end
end

function Animator._animationExpired( self, expiredAnimationName )
	local expiredAnimation = self.animations[expiredAnimationName]
	if expiredAnimation.info.looping and expiredAnimation.variation == nil then
		-- looping animations will select from variations if any, but not automatically go to next animation.
		return
	end
	
	-- determine next animation
	local nextAnimationName
	if expiredAnimation.variation then
		nextAnimationName = self:_selectAnimationVariation( expiredAnimation.variation )
	else
		nextAnimationName = expiredAnimation.nextAnimation
	end


	self:_setNextAnimation( expiredAnimationName, nextAnimationName )
end

-- Explicitly ends the named animation or the currentAnimation if nothing is passed and transitions to its configured nextAnimation.
function Animator.endAnimation( self, endedAnimationName, requestedNext )
	endedAnimationName = endedAnimationName or self.currentAnimation
	if not endedAnimationName then
		return
	end
	
	local nextAnimationName = requestedNext or self.animations[endedAnimationName].nextAnimation
	self:_setNextAnimation( endedAnimationName, nextAnimationName )
end

function Animator._setNextAnimation( self, endedAnimationName, nextAnimationName )
	local endedAnimation = self.animations[endedAnimationName]
	if nextAnimationName and self.animations[nextAnimationName] then
		if endedAnimation.instantNext then
			-- set next animation and carry over surplus time, transfer weight
			self.currentAnimation = nextAnimationName

			local surplusTime
			if endedAnimation.time > endedAnimation.info.duration then
				surplusTime = endedAnimation.time - endedAnimation.info.duration
			else
				surplusTime = endedAnimation.time
			end
			self.animations[nextAnimationName].time = surplusTime
			self.animations[nextAnimationName].weight = endedAnimation.weight
			
			if endedAnimationName ~= nextAnimationName then
				self.animations[endedAnimationName].time = 0.0
				self.animations[endedAnimationName].weight = 0.0
			end
		else
			self.currentAnimation = nextAnimationName
			self.animations[nextAnimationName].time = 0.0
			self.animations[nextAnimationName].weight = 0.0
		end
	else
		self.currentAnimation = nil
	end
end

function Animator._selectAnimationVariation( self, variationTable )
	local nextAnimationName = nil
	local total = 0
	for _, weight in pairs( variationTable ) do
		total = total + weight
	end
	local rand = math.random() * total
	local cumulative = 0
	for name, weight in pairs( variationTable ) do
		cumulative = cumulative + weight
		if rand <= cumulative then
			nextAnimationName = name
			break
		end
	end
	return nextAnimationName
end

-- Sets the current animation by name, resetting its time and weight.
-- Optional startTime (in seconds) to begin partway through (e.g. for starting at the end of a non-looping animation).
-- Returns true on success, false if the animation doesn't exist.
function Animator.setCurrentAnimation( self, name, startTime )
	if not self.animations[name] then
		sm.log.error( "Animation " .. name .. " does not exist on animated object "  )
		return false
	end

	if self.currentAnimation == name and self.animations[name].info.looping then
		return true
	end

	-- when setting animation, set it's inAnimation first unless it's already playing.
	if self.animations[name].inAnimation then
		-- if there is an inAnimation, play that first if it would lead to the desired animation
		local inAnimation = self.animations[name].inAnimation
		if self.animations[inAnimation] and inAnimation ~= self.currentAnimation then
			if self.animations[inAnimation].nextAnimation == name then
				name = self.animations[name].inAnimation
			end
		end
	end

	self.currentAnimation = name
	self.animations[name].time = startTime or 0.0
	self.animations[name].weight = 0.0
	return true
end

-- Picks a random animation from a weighted variation table and sets it as current.
-- variationTable: { ["AnimName"] = weight, ... }
function Animator.setCurrentAnimationVariation( self, variationTable )
    local name = self:_selectAnimationVariation( variationTable )
    if name then
        self:setCurrentAnimation( name )
    end
end

-- Sets the target value (0-1) for a controlled animation. The controller will interpolate towards it each frame.
function Animator.setControlTarget( self, name, target )
	if self.animations[name] and self.animations[name].controlled then
		self.animations[name].target = target
	end
end

-- Overrides the interpolation speed for a controlled animation.
function Animator.setControlLerpSpeed( self, name, lerpSpeed )
	if self.animations[name] and self.animations[name].controlled then
		self.animations[name].lerpSpeed = lerpSpeed
	end
end

-- Handles an animation event string. If the event matches an animation name, it is played.
-- If "end.animation", the current animation is ended. Events received before graphics load are queued.
function Animator.handleEvent( self, event )
	if self.animations[event] then
		self:setCurrentAnimation( event )
		return true
	end

	if event == "end.animation" then
		self:endAnimation()
		return true
	end

	return false
end


-- Enables automatic head tracking on this animator.
-- settings:
--   upDownAnim       - name of the controlled animation for up/down (required)
--   leftRightAnim    - name of the controlled animation for left/right (required)
--   lookAtRange      - max distance to detect players (default 10)
--   lookFromOffset     - offset for look origin (default 0)
--   getLookAtPosition -  function() returning a vec3 target to look at
--   isEnabled        - optional function(animator) returning false to disable tracking
function Animator.enableHeadTracking( self, settings )
	self.headTracking = {
		upDownAnim = settings.upDownAnim,
		leftRightAnim = settings.leftRightAnim,
		lookAtRange = settings.lookAtRange or 10.0,
		lookFromOffset = settings.lookFromOffset or sm.vec3.zero(),
		getLookAtPosition = settings.getLookAtPosition,
		isEnabled = settings.isEnabled,
	}
end

function Animator._updateHeadTracking( self )
	if not self.headTracking then return end

	local ht = self.headTracking
	local shape = self.animatedObject.shape

	if ht.isEnabled and not ht.isEnabled( self ) then
		self:setControlTarget( ht.upDownAnim, 0.5 )
		self:setControlTarget( ht.leftRightAnim, 0.5 )
		return
	end

	local stationUp = shape:getAt()
	local stationRight = -shape:getRight()
	local upDownControl = 0.5
	local leftRightControl = 0.5

	local lookAtPosition = ht.getLookAtPosition()
	if lookAtPosition then
		local lookFromPosition = shape.worldPosition
			+ shape:getAt() * ht.lookFromOffset.y
			+ shape:getUp() * ht.lookFromOffset.z
			+ shape:getRight() * ht.lookFromOffset.x
		local lookDirection = ( lookAtPosition - lookFromPosition ):safeNormalize( shape:getUp() )
		local upProjection = lookDirection:dot( stationUp )
		local rightProjection = lookDirection:dot( stationRight )

		local range = 0.35
		upDownControl = clamp( 0.5 + ( -upProjection * range ), 0, 1 )
		leftRightControl = clamp( 0.5 + ( rightProjection * range ), 0, 1 )
		self:setControlTarget( ht.upDownAnim, upDownControl )
		self:setControlTarget( ht.leftRightAnim, leftRightControl )
	end
end

function Animator.getElapsedTime(self,name)
	if name == nil then
		name = self.currentAnimation
	end
	if self.animations[name] then
		return self.animations[name].time
	end
	return nil
end

function Animator.getDuration(self, name)
	if name == nil then
		name = self.currentAnimation
	end
	if self.animations[name] and self.animations[name].info then
		return self.animations[name].info.duration
	end
	return nil
end