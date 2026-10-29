dofile( "$CONTENT_DATA/Scripts/smserver/core.lua" )

skycontainer_newData = skycontainer_newData or {}
skycontainer_current = skycontainer_current or {}
skycontainer_enderchestSize = 60

skycontainer = class()

local BackendUuid = sm.uuid.new( "1041ace6-6df4-4a85-b2a5-cf4e76308e4d" )

function skycontainer:server_onCreate()
	self.storageData = self.storage:load()
	if not self.storageData then
		self.storageData = table.remove( skycontainer_newData, 1 )
		if not self.storageData then
			-- Shape was placed by hand or the queue was lost. Keep it inert.
			return
		end
		self.storage:save( self.storageData )
	end

	if type( self.storageData.name ) ~= "string" or #self.storageData.name == 0 or #self.storageData.name > 64 then
		return
	end
	self.storageData.size = smserver_clampInteger( self.storageData.size, 1, 600 )

	local body = self.shape.body
	body.destructable = false
	body.erasable = false
	body.liftable = false
	body.paintable = false
	body.usable = false
	body.convertableToDynamic = false
	body.connectable = false
	body.buildable = false

	skycontainer_current[self.storageData.name] = self.interactable:getContainer( 0 ) or self.interactable:addContainer( 0, self.storageData.size )
end

function skycontainer_addContainer( name, size )
	if type( name ) ~= "string" or #name == 0 or #name > 64 then
		return false
	end
	size = smserver_clampInteger( size, 1, 600 )
	if skycontainer_current[name] then
		return false
	end
	if #skycontainer_newData > 4096 then
		return false
	end

	table.insert( skycontainer_newData, { name = name, size = size } )
	sm.shape.createPart( BackendUuid, servicetool.blockposition, sm.quat.fromEuler( sm.vec3.new( 0, 0, 0 ) ), false, true )
	return true
end

function skycontainer_getContainer( name )
	return skycontainer_current[name]
end
