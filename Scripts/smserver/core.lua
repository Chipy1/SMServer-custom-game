-- Shared class system ported from atstd lib (scripts/shared/api/Class2.lua).
-- Loaded before the smserver helpers so custom scripts can use std.class,
-- std.event (token-checked events) and std.broadcast.
if not std or not std.class then
	dofile( "$CONTENT_DATA/Scripts/shared/api/WeakTable.lua" )
	dofile( "$CONTENT_DATA/Scripts/shared/api/Class2.lua" )
end

-- Minimal smserver runtime shared by the ported custom blocks and the network
-- hardening helpers used by the custom game scripts.
-- Replaces the old $CONTENT_DATA/Scripts/smserver/servicetool.lua login/admin
-- suite with only the state the block scripts need.

if not servicetool then
	servicetool = {}
end

servicetool.blockposition = servicetool.blockposition or sm.vec3.new( -10, -10, 2000 )
servicetool.loginError = servicetool.loginError or "#ff0000you need to be logged in to use this"

-- Player id (Steam id) -> true. Mirrored from the game script's saved state.
servicetool.admins = servicetool.admins or {}

-- Kept for compatibility with the old block scripts. The port has no
-- nickname/password gate, so this table is never consulted for access.
servicetool.loginedNicknames = servicetool.loginedNicknames or {}

function servicetool.getPlayerByName( name )
	for _, player in ipairs( sm.player.getAllPlayers() ) do
		if player.name == name then
			return player
		end
	end
	return nil
end

-- Network hardening ---------------------------------------------------------
-- The engine appends the sending Player as the final argument of every
-- network-invoked method. Handlers must take the caller from that position and
-- never trust a player object supplied in the payload, otherwise a modified
-- client can impersonate another player (including the host).

function smserver_getNetworkCaller( ... )
	local args = { ... }
	local count = 0
	for key in pairs( args ) do
		if type( key ) == "number" and key > count then
			count = key
		end
	end
	if count < 1 then
		return nil
	end
	local last = args[count]
	if last == nil then
		return nil
	end
	local okId, id = pcall( function() return last.id end )
	if not okId or id == nil then
		return nil
	end
	local okName, name = pcall( function() return last.name end )
	if not okName or name == nil then
		return nil
	end
	return last
end

function smserver_isHost( player )
	if player == nil then
		return false
	end
	local ok, host = pcall( sm.player.getHostPlayer )
	return ok and host ~= nil and host.id == player.id
end

function smserver_isAdmin( player )
	if player == nil then
		return false
	end
	if smserver_isHost( player ) then
		return true
	end
	return servicetool.admins[player.id] == true
end

function smserver_isSelf( player, caller )
	return caller == nil or ( player ~= nil and caller.id == player.id )
end

function smserver_inRange( player, position, maxDistance )
	if player == nil or position == nil then
		return false
	end
	local character = player.character
	if character == nil or not sm.exists( character ) then
		return false
	end
	return ( character.worldPosition - position ):length() <= maxDistance
end

function smserver_isFinite( value )
	return type( value ) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

function smserver_clampInteger( value, minimum, maximum )
	if type( value ) ~= "number" or not smserver_isFinite( value ) then
		return minimum
	end
	local result = math.floor( value )
	if result < minimum then
		return minimum
	end
	if result > maximum then
		return maximum
	end
	return result
end
