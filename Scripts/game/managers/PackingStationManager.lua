PackingStationManager = class( nil )

-- Server side
function PackingStationManager.sv_onCreate( self )
	g_packingstationServer = self
	self.sv = {}
	self.sv.saved = sm.storage.load( STORAGE_CHANNEL_PACKINGSTATION_MANAGER )
	if self.sv.saved == nil then
		self.sv.saved = {}
		self.sv.saved.createdPacks = 0
		self.sv.saved.currentDeposits = {}
		sm.storage.save( STORAGE_CHANNEL_PACKINGSTATION_MANAGER, self.sv.saved )
	end
end

function PackingStationManager.Sv_PackCreated()
	if g_packingstationServer then
		g_packingstationServer:sv_packCreated()
	end
end

function PackingStationManager.sv_packCreated( self )
	self.sv.saved.createdPacks = self.sv.saved.createdPacks + 1
	sm.storage.save( STORAGE_CHANNEL_PACKINGSTATION_MANAGER, self.sv.saved )
end

function PackingStationManager.Sv_GetPacksCreated()
	if g_packingstationServer then
		return g_packingstationServer:sv_getPacksCreated()
	end
	return 0
end

function PackingStationManager.sv_getPacksCreated( self )
	return self.sv.saved.createdPacks
end

function PackingStationManager.Sv_SetStationLoads( load, cellKey, uidStr )
	if g_packingstationServer then
		g_packingstationServer:sv_setStationLoads( load, cellKey, uidStr )
	end
end

function PackingStationManager.sv_setStationLoads( self, load, cellKey, uidStr )
	if self.sv.saved.currentDeposits[cellKey] == nil then
		self.sv.saved.currentDeposits[cellKey] = {}
	end
	self.sv.saved.currentDeposits[cellKey][uidStr] = load
	sm.storage.save( STORAGE_CHANNEL_PACKINGSTATION_MANAGER, self.sv.saved )
end

function PackingStationManager.Sv_GetHighestLoad( uidStr )
	if g_packingstationServer then
		return g_packingstationServer:sv_getHighestLoad( uidStr )
	end
	return 0
end

function PackingStationManager.sv_getHighestLoad( self, uidStr )
	local highestValue = 0
	for _, uidList in pairs( self.sv.saved.currentDeposits ) do
		for uid,load in pairs( uidList ) do
			if uid == uidStr then
				highestValue = math.max( highestValue, load )
			end
		end
	end
	return highestValue
end

function PackingStationManager.sv_onCellLoaded( self, x, y )
 
	local concat = function(a, b)
		for _, v in pairs(b) do
			a[#a+1] = v;
		end
	end
	local forEach = function(a, fn)
		for i, v in pairs(a) do
			fn(i, v)
		end
	end

	local fronts = sm.cell.getInteractablesByUuid( x, y, obj_packingstation_front )
	if #fronts == 0 then return end
	local mids = sm.cell.getInteractablesByUuid( x, y, obj_packingstation_mid )
	if #mids == 0 then return end
	local screens = {}
	concat( screens, sm.cell.getInteractablesByUuid( x, y, obj_packingstation_screen_fruit ) )
	concat( screens, sm.cell.getInteractablesByUuid( x, y, obj_packingstation_screen_veggie ) )
	if #screens == 0 then return end

	local packingStation = {}
	packingStation.front = fronts[1];
	packingStation.mid = mids[1];
	packingStation.screens = screens;
	packingStation.crateload = sm.cell.getInteractablesByUuid( x, y, obj_packingstation_crateload )[1];

	packingStation.front:setParams({ packingStation = packingStation })
	packingStation.mid:setParams({ packingStation = packingStation })
	forEach(packingStation.screens, function(i, screen)  screen:setParams({ packingStation = packingStation, index = i }) end )

	if packingStation.crateload then
		packingStation.crateload:setParams({ packingStation = packingStation })
	end
	
end