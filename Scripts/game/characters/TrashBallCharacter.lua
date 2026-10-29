TrashBallCharacter = class( nil )

local Rot180Z = sm.quat.fromEuler( sm.vec3.new( 0, 0, 180 ) )
local Rot90X = sm.quat.fromEuler( sm.vec3.new( 90, 0, 0 ) )

function TrashBallCharacter.client_onCreate( self )
	self.cl = {}
	self.cl.animations = {}
	self.cl.effects = {}
end

function TrashBallCharacter.client_onDestroy( self )
end

function TrashBallCharacter.client_onRefresh( self )
end

function TrashBallCharacter.client_onGraphicsLoaded( self )
	self.character:setMovementEffects( "$SURVIVAL_DATA/Character/Char_Trashball/movement_effects.json" )
	self.character:setGlowMultiplier( 1 )
	self.graphicsLoaded = true

	self.cl.angularFraction = 0.0
	self.cl.effects = {}
	self.cl.effects.ball = sm.effect.createEffect( "ShapeRenderable", self.character )
	if self.data.color and self.data.color == "purple" then
		self.cl.effects.ball:setParameter( "uuid", sm.uuid.new( "af5afd6c-6fd5-43ab-818a-803c5674c006" ) )
		self.cl.effects.trail = sm.effect.createEffect( "Trashball - TrailPurple" )
	else			
		self.cl.effects.ball:setParameter( "uuid", sm.uuid.new( "d76d0639-4b04-4fb2-8338-ff4f7bde5ea0" ) )
		self.cl.effects.trail = sm.effect.createEffect( "Trashball - TrailGreen" )
	end

	self.cl.effects.ball:setScale( sm.vec3.new( 0.25, 0.25, 0.25 ) )
	self.cl.effects.ball:setOffsetPosition( sm.vec3.new( 0, self.character:getRadius(), 0 ) )
	self.cl.effects.ball:start()

end

function TrashBallCharacter.client_onGraphicsUnloaded( self )
	self.graphicsLoaded = false
	if self.cl.effects.ball then
		self.cl.effects.ball:destroy()
		self.cl.effects.ball = nil
	end
	if self.cl.effects.trail then
		self.cl.effects.trail:destroy()
		self.cl.effects.trail = nil
	end
end

function TrashBallCharacter.client_onUpdate( self, deltaTime )
	if not self.graphicsLoaded then
		return
	end

	if sm.exists( self.character ) then
		local hasTrail = false
		if self.character:isOnGround() then

			-- Get the current angular rotation
			local flatVelocity = sm.vec3.new( self.character.velocity.x, self.character.velocity.y, 0 )
			local velocity = flatVelocity:length()
			hasTrail = velocity > 1.0
			local angularVelocity =  velocity / self.character:getRadius()
			local angularFractionDelta = ( -angularVelocity * deltaTime ) / ( math.pi * 2 )
			self.cl.angularFraction = ( self.cl.angularFraction + angularFractionDelta ) % 1.0

			-- Get the current rotation axis
			local rollDirection = sm.vec3.new( flatVelocity.x, flatVelocity.y, 0 ):safeNormalize( sm.vec3.new( 0, 1, 0 ) )
			local right = rollDirection:cross( sm.vec3.new( 0, 0, 1 ) )

			-- Transform the rotation axis into the attached character's mesh space
			local relRight = Rot180Z * Rot90X * right
			local offsetRotation = sm.quat.angleAxis( math.pi * 2.0 * self.cl.angularFraction, relRight )

			self.cl.effects.ball:setOffsetRotation( offsetRotation )

			-- Update trail effect
			local forward = sm.vec3.new( 0, 1, 0 )
			local trailRad = math.acos( clamp( forward:dot( rollDirection ), -1, 1 ) )
			local determinant = ( forward.x * rollDirection.y - forward.y * rollDirection.x )
			if determinant > 0 then
				trailRad = -trailRad
			end

			local hit, result = sm.physics.raycast( self.character.worldPosition, self.character.worldPosition - sm.vec3.new( 0, 0, 4 ), self.character )
			local groundNormal = sm.vec3.new( 0, 0, 1 )
			if hit then
				groundNormal = result.normalWorld
			end
			local groundRotQuat = sm.vec3.getRotation( sm.vec3.new( 0, 0, 1 ), groundNormal )
			self.cl.effects.trail:setPosition( self.character.worldPosition + sm.vec3.new( 0, 0, -self.character:getHeight() * 0.5 ) )
			self.cl.effects.trail:setRotation( groundRotQuat * sm.quat.fromEuler( sm.vec3.new( 0, 0, -math.deg( trailRad ) ) ) )
		end

		if hasTrail then
			if not self.cl.effects.trail:isPlaying() then
				self.cl.effects.trail:start()
			end
		else
			if self.cl.effects.trail:isPlaying() then
				self.cl.effects.trail:stop()
			end
		end
















	end
end
