dofile( "$SURVIVAL_DATA/Scripts/util.lua" )

LogEntryManager = class()

local Logs = dofile ( "$SURVIVAL_DATA/Logs/log_entries.json" ).logList

local LogsMap = {}
for _, value in ipairs( Logs ) do
    LogsMap[value.uuid] = value
end

function LogEntryManager.server_onCreate( self )
    g_logEntryManager = self

    self.sv = {}
    self.sv.highlightedLogs = {}
    self.sv.saved = { logs = {}, locations = {} }
    self.sv.logRevision = 0

    self.sv.saved.logs = sm.storage.load( STORAGE_CHANNEL_LOGS ) or {}

    -- always start with crashed ship log entry
    if not isAnyOf( LOGS.log_crashedship, self.sv.saved.logs ) then
		self.sv.saved.logs[#self.sv.saved.logs + 1] = LOGS.log_crashedship
	end

    -- if you have an old survial save with completed quest you will not have received the log entry in STORAGE_CHANNEL_LOGS, 
    -- retroactively add it if the quest is completed
	if QuestManager.Sv_IsQuestComplete( "quest_tutorial" ) and not isAnyOf( LOGS.log_mechanicstation, self.sv.saved.logs ) then
		self.sv.saved.logs[#self.sv.saved.logs + 1] = LOGS.log_mechanicstation
	end

    self.sv.saved.locations = sm.storage.load( STORAGE_CHANNEL_LOCATIONS ) or {}

    self.network:setClientData( self.sv.saved.logs, 1 )
    self.network:setClientData( self.sv.saved.locations, 2 )
end

function LogEntryManager.Sv_RefreshLocations()
    if g_logEntryManager then
        sm.event.sendToScriptableObject( g_logEntryManager.scriptableObject, "sv_e_refreshLocations", nil, sm.event.types.instant )
    end
end

function LogEntryManager.sv_e_refreshLocations( self )
    self.sv.saved.locations = sm.storage.load( STORAGE_CHANNEL_LOCATIONS ) or {}
    self.network:setClientData( self.sv.saved.locations, 2 )
end


function LogEntryManager.Sv_SetLogHighlight( uuid, active )
    sm.event.sendToScriptableObject( g_logEntryManager.scriptableObject, "sv_e_setLogHighlight", { uuid = uuid, active = active } )
end

function LogEntryManager.sv_e_setLogHighlight( self, data )
    self.sv.highlightedLogs[data.uuid] = data.active
    self.sv.logRevision = self.sv.logRevision + 1
    self.network:setClientData( self.sv.highlightedLogs, 3 )
end

function LogEntryManager.client_onCreate( self )
    g_logEntryManagerClient = self

    self.cl = {}

    self.cl.logRevision = 0
    self.cl.locationRevision = 0
    self.cl.highlightedLogs = {}
    self.cl.logs = { LOGS.log_crashedship }
end

function LogEntryManager.client_onClientDataUpdate( self, data, channel )

    if channel == 1 then
        if self.cl.logs == nil or #self.cl.logs < #data then
            if g_survivalHud then
                g_survivalHud:setVisible( "LogbookNotification", true )
            end
        end
        self.cl.logs = data
        self.cl.logRevision = self.cl.logRevision + 1
    elseif channel == 2 then
        self.cl.locations = data
        self.cl.locationRevision = self.cl.locationRevision + 1
    elseif channel == 3 then
        self.cl.highlightedLogs = data
        self.cl.logRevision = self.cl.logRevision + 1
    end

end

function LogEntryManager.Sv_AddLog( uuid, skipNotification )
    if g_logEntryManager then
        if type( uuid ) == "Uuid" then
            uuid = tostring( uuid )
        end
        assert( type( uuid ) == "string" )
        sm.event.sendToScriptableObject( g_logEntryManager.scriptableObject, "sv_e_addLog", { uuid = uuid, skipNotification = skipNotification } )
    end
end

function LogEntryManager.sv_e_addLog( self, data )
	if not isAnyOf( data.uuid, self.sv.saved.logs ) then
		self.sv.saved.logs[#self.sv.saved.logs+1] = data.uuid
        
        local referenceMap = {}
        for index,value in ipairs( Logs ) do
            referenceMap[value.uuid] = index
        end

        table.sort( self.sv.saved.logs, function( a, b )
            return ( referenceMap[a] or math.huge ) < ( referenceMap[b] or math.huge )
        end )

		sm.storage.save( STORAGE_CHANNEL_LOGS, self.sv.saved.logs )
        self.sv.logRevision = self.sv.logRevision + 1
		self.network:setClientData( self.sv.saved.logs, 1 )
        QuestManager.Sv_SendEvent( QuestEvent.LogUnlocked, { uuid = data.uuid } )
        if not data.skipNotification then
			NotificationManager.Sv_LogUnlock( data.uuid )
		end
	end
end

function LogEntryManager.Sv_RemoveLog( uuid )
    if g_logEntryManager then
        sm.event.sendToScriptableObject( g_logEntryManager.scriptableObject, "sv_e_removeLog", { uuid = uuid } )
    end
end

function LogEntryManager.sv_e_removeLog( self, data )
    if isAnyOf( data.uuid, self.sv.saved.logs ) then
        for index, logUid in ipairs( self.sv.saved.logs ) do
            if logUid == data.uuid then
                table.remove( self.sv.saved.logs, index )
                break
            end
        end
        sm.storage.save( STORAGE_CHANNEL_LOGS, self.sv.saved.logs )
        self.sv.logRevision = self.sv.logRevision + 1
        self.network:setClientData( self.sv.saved.logs, 1 )
    end
end

function LogEntryManager.Cl_GetLogRevision()
    return g_logEntryManagerClient.cl.logRevision
end

function LogEntryManager.Cl_GetLogItems()
	return g_logEntryManagerClient.cl.logs
end

function LogEntryManager.Cl_GetLocations()
    return g_logEntryManagerClient.cl.locations
end

function LogEntryManager.Cl_HasLog( uuid )
    local existingLogs = g_logEntryManagerClient.cl.logs
    if existingLogs then
        return isAnyOf( uuid, existingLogs )
    end
    return false
end

function LogEntryManager.Sv_HasLog( uuid )
	if uuid == nil then
		sm.log.warning( "LogEntryManager.Sv_HasLog: uuid is nil" )
		return false
	end
    local existingLogs = g_logEntryManager.sv.saved.logs
	if existingLogs then
		return isAnyOf( uuid, existingLogs )
	end
	return false
end

function LogEntryManager.Cl_GetIsLogHighlighted( uuid )
    return g_logEntryManagerClient:cl_getIsLogHighlighted( uuid )
end

function LogEntryManager.cl_getIsLogHighlighted( self, uuid )
    return self.cl.highlightedLogs[uuid] or false
end

function LogEntryManager.Sv_GetLogRevision()
    if g_logEntryManager then
        return g_logEntryManager.sv.logRevision
    end
    return 0
end

function LogEntryManager.Cl_IsLogUuid( uuid )
    return LogsMap[uuid] ~= nil
end

function LogEntryManager.Cl_GetLogData( uuid )
    return LogsMap[uuid]
end

function LogEntryManager.Cl_GetLogFromItemUuid( uuid )
    for _, logData in pairs( LogsMap ) do
        if logData.item and ITEMS[logData.item] == sm.uuid.new( uuid ) then
            return logData.uuid
        end
    end
    return nil
end