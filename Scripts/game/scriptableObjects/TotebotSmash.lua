dofile( "$SURVIVAL_DATA/Scripts/game/survival_meleeattacks.lua" )

TotebotSmash = class( nil )

local StompDamage = 10
local TickDuration = 40 * 0.25
local TriggerRadius = 2.0
local TriggerHalfHeight = 0.25

function TotebotSmash.server_onCreate( self )
	self.sv = {}
	self.sv.destroyTick = sm.game.getCurrentTick() + TickDuration
	self.sv.destroyed = false
	self.sv.smasher = self.params.smasher
	self.sv.position = self.params.position
	self.sv.normal = self.params.normal or sm.vec3.new( 0, 0, 1 )
	self.sv.affectedCharacters = {}
	self.sv.affectedShapes = {}

	if self.sv.position and sm.exists( self.sv.smasher ) then
		local triggerPosition = self.sv.position + self.sv.normal * TriggerHalfHeight
		local rotation = sm.vec3.getRotation( sm.vec3.new( 0, 0, 1 ), self.sv.normal )
		local filter = sm.areaTrigger.filter.character + sm.areaTrigger.filter.dynamicBody + sm.areaTrigger.filter.staticBody
		self.sv.trigger = sm.areaTrigger.createCylinder( TriggerRadius, TriggerHalfHeight, triggerPosition, rotation, filter )
		self.sv.trigger:setCharacterDetection( true )
		sm.effect.playEffect( "Yellowtotebot - Jumpimpact", self.sv.smasher.character.worldPosition, nil, rotation )

		sm.melee.meleeAttack( melee_totebotsmash, 0, triggerPosition, -self.sv.normal * TriggerHalfHeight * 2, self.sv.smasher )
	else
		self.sv.destroyed = true
		self.scriptableObject:destroy()
	end
end

function TotebotSmash.server_onFixedUpdate( self )
	if not self.sv.destroyed then
		for _, characterCollision in pairs( self.sv.trigger:getCharacters() ) do
			local character = characterCollision.character
			local collisionPosition = characterCollision.characterWorldPosition
			local isMe = sm.exists( self.sv.smasher ) and self.sv.smasher.character == character
			if sm.exists( character ) then
				if not isMe and self.sv.affectedCharacters[character.id] == nil then
					self.sv.affectedCharacters[character.id] = true
					local player = character:getPlayer()
					local unit = character:getUnit()
					if player and sm.exists( player ) then
						sm.event.sendToPlayer( player, "sv_e_receiveDamage", { damage = StompDamage, source = "impact" } )
						local knockbackDirection = ( character.worldPosition - collisionPosition ):safeNormalize( sm.vec3.new( 0, 0, 1 ) )
						ApplyKnockback( character, knockbackDirection, 5000 )
					elseif unit and sm.exists( unit ) then
						local teamOpponent = false
						if type( self.sv.smasher ) == "Unit" then
							if not SurvivalGame then
								teamOpponent = not InSameTeam( self.sv.smasher, unit )
							end
						end
						if teamOpponent or not isAnyOf( unit.character:getCharacterType(), g_robots ) then
							local knockbackDirection = ( character.worldPosition - collisionPosition ):safeNormalize( sm.vec3.new( 0, 0, 1 ) )
							ApplyKnockback( character, knockbackDirection, 5000 )
							sm.event.sendToUnit( unit, "sv_e_receiveDamage", { damage = StompDamage, source = "impact", hitPos = collisionPosition, impact = knockbackDirection } )
						end
					end
				end
			end
		end
		if sm.game.getCurrentTick() >= self.sv.destroyTick then
			self.sv.destroyed = true
			sm.areaTrigger.destroy( self.sv.trigger )
			self.scriptableObject:destroy()
		end
	end
end