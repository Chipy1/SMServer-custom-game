BridgeManager = class ( nil )
BridgeManager.isSaveObject = true

local BridgeStartDelayTicks = 0.75 * 40
local BridgeRaiseEventTickDuration = 23 * 40
local BridgeKinematicLingerTicks = 2 * 40

local BridgeRaisedQuestEventDelayTicks = 12 * 40

function BridgeManager.server_onCreate( self )
    assert( g_BridgeManager == nil )
    g_BridgeManager = self

    self.sv = {}
    self.sv.saved = self.storage:load()
    if self.sv.saved == nil and self.params then
        self.sv.saved = {
            position = self.params.position,
            creationTick = sm.game.getServerTick(),
            activationTick = nil,
            bridgeRaisedQuestEventSent = false,
            tileStorageKey = TileStorageManager.Sv_GetTileStorageKeyFromPosition( self.scriptableObject:getWorld(), self.params.position )
        }
        self.storage:save( self.sv.saved )
    end

end

function BridgeManager.server_onDestroy( self )
    g_BridgeManager = nil
end

function BridgeManager.server_onFixedUpdate( self, timeStep )
    -- Delay before starting bridge raise
    if not self.sv.saved.activationTick then
        if sm.game.getCurrentTick() >= self.sv.saved.creationTick + BridgeStartDelayTicks then
            self.sv.saved.activationTick = sm.game.getCurrentTick()
            self.storage:save( self.sv.saved )
            EffectManager.Sv_PlayNamedCinematic( { name = "cinematic.kinematicbridge01", callbackData = { world = self.scriptableObject:getWorld() }, interruptible = false } )
            KinematicManager.Sv_Activate( self.sv.saved.tileStorageKey, "RaiseBridge", { tick = self.sv.saved.activationTick, persistent = true } )
        end
        return
    end

    if not self.sv.saved.bridgeRaisedQuestEventSent and sm.game.getCurrentTick() > self.sv.saved.activationTick + BridgeRaisedQuestEventDelayTicks then
        self.sv.saved.bridgeRaisedQuestEventSent = true
        self.storage:save( self.sv.saved )
        QuestManager.Sv_SendEvent( QuestEvent.BridgeRaised )
    end

    if sm.game.getCurrentTick() > self.sv.saved.activationTick + BridgeRaiseEventTickDuration + BridgeKinematicLingerTicks then
        self.scriptableObject:destroy()
        return
    end

    if sm.game.getCurrentTick() > self.sv.saved.activationTick + BridgeRaiseEventTickDuration then

        if TileStorageManager.Sv_SyncedGetValueInSubTable( self.sv.saved.tileStorageKey, TILESTORAGE_FLAGS_TABLE, "raised" ) then
            return
        end
        
        SetTileStorageFlag( self.sv.saved.tileStorageKey, "raised" )

        local reloadCellsArgs = { world = self.scriptableObject:getWorld(), cells = {} }
        local registered = KinematicManager.Sv_GetRegistered( self.sv.saved.tileStorageKey, "RaiseBridge" )
        if registered  then
            for _, kinematic in ipairs( registered ) do
                local cell = ( kinematic:getPosition() / 64 ):floor()
                table.insert( reloadCellsArgs.cells, { x=cell.x, y=cell.y } )
            end
        end
        self.network:sendToClients( "cl_n_reloadBridgeCells", reloadCellsArgs )
    end
end

function BridgeManager.cl_n_reloadBridgeCells( self, params )
    self.cl.bridgeCellReload = 0
	self.cl.bridgeCellReloadCount = 0
    for _, cell in ipairs( params.cells ) do
        params.world:reloadCell( cell.x, cell.y, "cl_reloadBridgeCellsCallback" )
        self.cl.bridgeCellReload = self.cl.bridgeCellReload + 1
	end
end

function BridgeManager.cl_reloadBridgeCellsCallback( self, world, x, y, result )
	self.cl.bridgeCellReloadCount = self.cl.bridgeCellReloadCount + 1
	if self.cl.bridgeCellReloadCount >= self.cl.bridgeCellReload then
		self:cl_setBridgeRaised( sm.game.getCurrentTick() )
	end
end

function BridgeManager.client_onCreate( self )
    self.cl = {}
    g_BridgeManagerClient = self
end

function BridgeManager.client_onDestroy( self )
    g_BridgeManagerClient = nil
end

function BridgeManager.cl_setBridgeRaised( self, tick )
    self.cl.bridgeRaised = tick
end

function BridgeManager.cl_isBridgeRaised( self )
    if self.cl.bridgeRaised == nil then
        return false
    end
    return sm.game.getCurrentTick() >= self.cl.bridgeRaised
end