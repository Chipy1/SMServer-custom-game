
dofile( "$SURVIVAL_DATA/Scripts/util.lua" )

LOOT_TABLES = LOOT_TABLES or {}
LOOT_SOURCES = LOOT_SOURCES or {}
LOOT_CONDITIONS = LOOT_CONDITIONS or {}

dofile( "$SURVIVAL_DATA/Scripts/game/loot/loottables.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/loot/lootsources.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/loot/lootconditions.lua" )

local function SolveValue( value, default )
	if value then
		if type( value ) == "table" then
			if #value == 1 then
				return value[1]
			elseif #value == 2 then
				return randomStackAmount( value[1], ( value[1] + value[2] ) / 2, value[2] )
			else
				return randomStackAmount( value[1], value[2], value[3] )
			end
		else
			return value
		end
	end
	return default
end

local function SelectOne( lootTable, tier, usedUniqueTags, budget, costOverride, epicOverride, recursionDepth, ignoreTag, parentConditions )
	if lootTable == nil or ( recursionDepth or 0 ) > 10 then
		return nil
	end

	local tierTable
	if tier then
		local t = tier
		while tierTable == nil and t >= 1 do
			tierTable = lootTable["tier"..t]
			t = t - 1
		end
	end
	lootTable = tierTable or lootTable

	assert( lootTable.list )
	local list = {}
	for _,item in ipairs( lootTable.list ) do
		local itemCost = costOverride or item.cost or 0
		if ( not item.uniqueTag or ( not usedUniqueTags[item.uniqueTag] and ignoreTag ~= item.uniqueTag ) ) and budget >= itemCost then
			list[#list + 1] = DeepCopy( item )
		end
	end

	for index,item in reverse_ipairs( list ) do
		local itemConditions = item.conditions or parentConditions
		if itemConditions and item.uuid then
			local conditionList = LOOT_CONDITIONS[itemConditions]
			local conditions = conditionList and conditionList[tostring( item.uuid )]
			if conditions then
				if not ProgressionManager.Sv_ConditionsFulfilled( conditions ) then
					table.remove( list, index )
				end
			end
		end
	end

	local sum = 0
	for _,item in ipairs( list ) do
		sum = sum + ( item.weight or 1 )
	end
	local rand = math.random() * sum
	sum = 0
	for _,item in ipairs( list ) do
		sum = sum + ( item.weight or 1 )
		if rand <= sum then
			if item.uniqueTag then
				usedUniqueTags[item.uniqueTag] = true
			end
			if item.table then
				local childTable = LOOT_TABLES[item.table]
				if childTable == nil then
					sm.log.error( "Loot table not found: " .. item.table )
				end
				return SelectOne( childTable, tier, usedUniqueTags, budget, costOverride or item.cost, epicOverride or item.epic, ( recursionDepth or 0 ) + 1, ignoreTag, item.conditions )
			end
			if item.uuid then
				return {
					uuid = item.uuid,
					quantity = SolveValue( item.quantity, 1 ),
					cost = costOverride or item.cost,
					epic = epicOverride or item.epic
				}
			end
			return nil
		end
	end
	return nil
end

function SelectLoot( lootSourceName, slotLimit, lootType, ignoreTag )
	local lootSource = nil
	if lootType then
		lootSource = LOOT_SOURCES[lootSourceName.."_"..lootType]
		if lootSource == nil then
			print( "Loot source not found: '" .. lootSourceName.."_"..lootType, "'. Defaulting to "..lootSourceName )
		end
	end
	if not lootSource then
		lootSource = LOOT_SOURCES[lootSourceName]
		if lootSource == nil then
			sm.log.error( "Loot source not found: " .. lootSourceName )
			return {}
		end
	end

	local lootList = {}
	local tier = g_lootTier
	local budget = SolveValue( lootSource.budget, 0 )
	local usedUniqueItems = {}

	for _,lootItem in ipairs( lootSource.loot ) do
		for i = 1, ( lootItem.count or 1 ) do
			if slotLimit and #lootList >= slotLimit then
				break
			end
			local item = SelectOne( lootItem, tier, usedUniqueItems, budget, lootItem.cost, lootItem.epic, nil, ignoreTag, nil )
			if item then
				assert( item.uuid )
				assert( item.quantity )
				lootList[#lootList + 1] = item
				budget = budget - ( item.cost or 0 )
			end
		end
	end
	return lootList
end

function SpawnLoot( origin, lootList, worldPosition, ringAngle, velocity, direction )
	if type( origin ) == "Unit" then
		local world = GetWorld( origin )
		if world and world.publicData and world.publicData.type == "DrillbotWorld" then
			return
		end
	end

	if worldPosition == nil then
		if type( origin ) == "Shape" then
			worldPosition = origin.worldPosition
		elseif type( origin ) == "Player" or type( origin ) == "Unit" then
			local character = origin:getCharacter()
			if character then
				worldPosition = character.worldPosition
			end
		elseif type( origin ) == "Harvestable" then
			worldPosition = origin.worldPosition
		end
	end

	local up = direction
	local perp
	if up == nil then
		if type( origin ) == "Shape" then
			up = sm.vec3.new( 0, 1, 0 )
		else
			up = sm.vec3.new( 0, 0, 1 )
		end
		perp = sm.vec3.new( 1, 0, 0 )
	else
		local closestAxis = sm.vec3.closestAxis( up )
		if closestAxis.x == 0 then
			perp = sm.vec3.new( 1, 0, 0 )
		else
			perp = sm.vec3.new( 0, 1, 0 )
		end
	end


	ringAngle = ringAngle or math.pi / 18

	local startAngle = math.random() * 2 * math.pi

	if worldPosition then
		local firstCircle = 6
		local secondCircle = 13
		local thirdCircle = 26

		local divisions, dir

		for i = 1, #lootList do
			if i < firstCircle then
				divisions = ( firstCircle - ( firstCircle - math.min( #lootList, firstCircle - 1 ) ) )
				dir = up:rotate( ringAngle, perp )
				dir = dir:rotate( i * 2 * math.pi / divisions + startAngle, up )
			elseif i < secondCircle then
				divisions = ( secondCircle - ( secondCircle - math.min( #lootList - firstCircle + 1, secondCircle - firstCircle ) ) )
				dir = up:rotate( ringAngle * 2, perp )
				dir = dir:rotate( i * 2 * math.pi / divisions + startAngle, up )
			elseif i < thirdCircle then
				divisions = ( thirdCircle - ( thirdCircle - math.min( #lootList - secondCircle + 1, thirdCircle - secondCircle ) ) )
				dir = up:rotate( ringAngle * 3, perp )
				dir = dir:rotate( i * 2 * math.pi / divisions + startAngle, up )
			else
				-- Out of predetermined room, place randomly
				dir = up:rotate( ringAngle * ( 1 + math.random() * 2 ), perp )
				dir = dir:rotate( math.random() * 2 * math.pi, up )
			end

			local loot = lootList[i]
			local params = { lootUid = loot.uuid, lootQuantity = loot.quantity or 1, epic = loot.epic, limitedLoot = loot.limitedLoot, questItem = loot.questItem }
			velocity = velocity or 5
			local vel = dir * ( velocity - 1 + math.random() * 2 )
			local projectileUuid = loot.epic and projectile_epicloot or projectile_loot
			sm.debugDraw.flashArrow( worldPosition, worldPosition + dir, nil, 2 )
			if type( origin ) == "Shape" then
				sm.projectile.shapeCustomProjectileAttack( params, projectileUuid, 0, sm.vec3.new( 0, 0, 0 ), vel, origin, 0 )
			elseif type( origin ) == "Player" or type( origin ) == "Unit" or type( origin ) == "World" then
				sm.projectile.customProjectileAttack( params, projectileUuid, 0, worldPosition, vel, origin, worldPosition, worldPosition, 0 )
			elseif type( origin ) == "Harvestable" then
				sm.projectile.harvestableCustomProjectileAttack( params, projectileUuid, 0, worldPosition, vel, origin, 0 )
			elseif type( origin ) == "World" then
				sm.projectile.customProjectileAttack( params, projectileUuid, 0, worldPosition, vel, origin )
			end
		end
	end
end

function SpawnLogLoot( origin, worldPosition, params )
	if worldPosition == nil then
		if type( origin ) == "Shape" then
			worldPosition = origin.worldPosition
		elseif type( origin ) == "Player" or type( origin ) == "Unit" then
			local character = origin:getCharacter()
			if character then
				worldPosition = character.worldPosition
			end
		elseif type( origin ) == "Harvestable" then
			worldPosition = origin.worldPosition
		end
	end
	if worldPosition then
		local vel = sm.vec3.new( 0, 0, 5 )
		if type( origin ) == "Shape" then
			sm.projectile.shapeCustomProjectileAttack( params, projectile_log, 0, sm.vec3.new( 0, 0, 0 ), vel, origin, 0 )
		elseif type( origin ) == "Player" or type( origin ) == "Unit" then
			sm.projectile.customProjectileAttack( params, projectile_log, 0, worldPosition, vel, origin, worldPosition, worldPosition, 0 )
		elseif type( origin ) == "Harvestable" then
			sm.projectile.harvestableCustomProjectileAttack( params, projectile_log, 0, worldPosition, vel, origin, 0 )
		end
	end
end











































































































































































