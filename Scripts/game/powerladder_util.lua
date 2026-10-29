function GetRailTag( tags )
	if tags then
		for index, value in ipairs( tags ) do
			if string.sub( value, 1, 7 ) == "ts:rail" then
				return value
			end
		end
	end
	return nil
end

function GetRailStorage( tileKey, tag )
	local rail = TileStorageManager.Sv_GetValueInSubTable( tileKey, POWERLADDER_RAIL_TABLE, tag )
	if rail == nil then
		rail = { powered = false, collection = {} }
		TileStorageManager.Sv_SetValueInSubTable( tileKey, POWERLADDER_RAIL_TABLE, tag, rail )
	end
	return rail
end

function SetRailPower( powerEnabled, tag, tileKey )
	local rail = GetRailStorage( tileKey, tag )
	rail.powered = powerEnabled
	TileStorageManager.Sv_SetValueInSubTable( tileKey, POWERLADDER_RAIL_TABLE, tag, rail )
	-- update power on existing rail parts
	for _, railPart in pairs( rail.collection ) do
		if sm.exists( railPart ) then
			sm.event.sendToHarvestable( railPart, "sv_e_updatePower", powerEnabled )
		end
	end
end