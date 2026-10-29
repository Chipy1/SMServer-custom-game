dofile( "$SURVIVAL_DATA/Scripts/game/survival_collections.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/survival_constants.lua" )
dofile( "$SURVIVAL_DATA/Scripts/util.lua" )

RayProjectileManager = class()

local ProjectileRadius = 0.05

function RayProjectileManager.server_onCreate( self )
	local worldId = self.scriptableObject:getWorld().id
	g_rayProjectileManagerServerWorld = g_rayProjectileManagerServerWorld or {}
	g_rayProjectileManagerServerWorld[worldId] = self
	self.sv = {}
	self.sv.rayProjectiles = {}
end

function RayProjectileManager.server_onFixedUpdate( self )
	for _, rayProjectile in ipairs( self.sv.rayProjectiles ) do
		local effectStartPosition = rayProjectile.startPosition
		local effectEndPosition = rayProjectile.endPosition

		local filter = bit.bor( sm.physics.filter.default, sm.physics.filter.waterArea )
		local sourceObject = sm.exists( rayProjectile.sourceObject ) and rayProjectile.sourceObject or nil
		local hit, result = sm.physics.spherecast( rayProjectile.startPosition, rayProjectile.endPosition, ProjectileRadius, sourceObject, filter )
		if hit then
			effectEndPosition = result.pointWorld

			-- Deal damage
			if result.type == "character" then
				local hitCharacter = result:getCharacter()

				if hitCharacter:isPlayer() then
					local player = hitCharacter:getPlayer()
					if sm.exists( player ) then
						sm.event.sendToPlayer( player, "sv_e_receiveDamage", { damage = rayProjectile.damage, source = rayProjectile.source } )
					end
				else
					local unit = hitCharacter:getUnit()
					if sm.exists( unit ) then
						local teamOpponent = false
						if type( sourceObject ) == "Character" then
							if not SurvivalGame then
								teamOpponent = not InSameTeam( sourceObject, unit )
							end
						end
						if teamOpponent or not isAnyOf( unit.character:getCharacterType(), g_robots ) then
							sm.event.sendToUnit( unit, "sv_e_receiveDamage", { damage = rayProjectile.damage, impact = -result.normalWorld, hitPos = result.pointWorld, source = rayProjectile.source } )
						end
					end
				end
			elseif result.type == "body" then
				-- Destroy shape
				local hitShape = result:getShape()
				if sm.exists( hitShape ) then
					local interactable = hitShape:getInteractable()
					if hitShape.isBlock then
						-- Destroy hit block
						local hitPos = result.pointWorld
						local blockPosition = hitShape:getClosestBlockLocalPosition( hitPos )
						hitShape:destroyBlock( blockPosition, nil, rayProjectile.destructionLevel )
					elseif isAnyOf( hitShape.uuid, g_capsules ) then
						-- Hit a capsule, so open it
						sm.event.sendToInteractable( hitShape.interactable, "sv_e_open" )
					elseif isAnyOf( hitShape.uuid, g_explosives ) then
						-- Hit an explosive
						sm.event.sendToInteractable( hitShape.interactable, "server_startCountdown" )
					elseif interactable and interactable:hasSeat() then
						local targetCharacter = interactable:getSeatCharacter()
						local targetPlayer = targetCharacter and targetCharacter:getPlayer() or nil
						if targetPlayer then
							sm.event.sendToPlayer( targetPlayer, "sv_e_receiveDamage", { damage = rayProjectile.damage, source = rayProjectile.source } )
						end
					elseif interactable == nil then
						-- Destroy non-interactable parts
						hitShape:destroyShape( rayProjectile.destructionLevel )
					end
				end
			end

			local effectRotation = sm.vec3.getRotation( sm.vec3.new( 0, 0, 1 ), result.normalWorld )
			if result.type == "terrainSurface" then
				sm.effect.playEffect( "Ray - Projectileimpact_ground", effectEndPosition, nil, effectRotation )
			else
				sm.effect.playEffect( "Ray - Projectileimpact", effectEndPosition, nil, effectRotation )
			end
		end

		local rayFromTo = effectEndPosition - effectStartPosition
		local rayDirection = rayFromTo:safeNormalize( sm.vec3.new( 0, 1, 0 ) )
		local rayRotation = sm.vec3.getRotation( sm.vec3.new( 0, 0, 1 ), rayDirection )
		sm.effect.playEffect( "Ray - Projectile_start", effectStartPosition, nil, rayRotation )
		sm.effect.playEffect( "Ray - Projectile_end", effectEndPosition, nil, rayRotation )
	end
	self.sv.rayProjectiles = {}
end

--[[ Manager ]]
function RayProjectileManager.Sv_FireRayProjectile( startPosition, endPosition, sourceObject, damage, destructionLevel, source )
	local world = sm.world.getCurrentWorld()
	if sm.exists( world ) then
		if g_rayProjectileManagerServerWorld[world.id] then
			g_rayProjectileManagerServerWorld[world.id]:sv_fireRayProjectile( startPosition, endPosition, sourceObject, damage, destructionLevel, source )
		end
	end
end

function RayProjectileManager.sv_fireRayProjectile( self, startPosition, endPosition, sourceObject, damage, destructionLevel, source )
	self.sv.rayProjectiles[#self.sv.rayProjectiles+1] = { startPosition = startPosition, endPosition = endPosition, sourceObject = sourceObject, damage = damage, destructionLevel = destructionLevel, source = source }
end
