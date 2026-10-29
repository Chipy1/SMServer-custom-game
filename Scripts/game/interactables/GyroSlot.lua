-- GyroSlot.lua --
dofile("$SURVIVAL_DATA/Scripts/game/survival_shapes.lua")
dofile( "$SURVIVAL_DATA/Scripts/game/managers/TutorialManager.lua" )

GyroSlot = class( nil )

function GyroSlot.server_onCreate( self )
	self.sv = {}
	self.sv.saved = self.storage:load()
	if self.sv.saved == nil then
		self.sv.saved = { inserted = false }
	end
	self.storage:save( self.sv.saved )
	self.network:setClientData( self.sv.saved )
end

function GyroSlot.client_onClientDataUpdate( self, clientData )
	if self.cl == nil then
		self.cl = {}
	end

	if not self.cl.inserting and clientData.inserted then
		self.interactable:setSubMeshVisible( "m_gyrocore", true )
		self.cl.animationTime = 0
		self.interactable:setAnimEnabled( "idle", true )
		self.interactable:setAnimProgress( "idle", 0.0 )
		self.interactable:setAnimEnabled( "insert", false )
	else
		self.interactable:setSubMeshVisible( "m_gyrocore", false )
	end
end

function GyroSlot.client_onCreate( self )
	if self.cl == nil then
		self.cl = {}
	end

	self.cl.insertDuration = self.interactable:getAnimDuration( "insert" )
	self.cl.idleDuration = self.interactable:getAnimDuration( "idle" )
	self.cl.animationProgress = 0.0
end

function GyroSlot.sv_e_receiveItem( self, params )
	sm.container.beginTransaction()
	sm.container.spendFromSlot( params.containerA, 0, params.itemA, params.quantityA, true )
	if sm.container.endTransaction() then
		self.sv.saved.inserted = true
		self.storage:save( self.sv.saved )
		self.network:setClientData( self.sv.saved )
		self.network:sendToClients( "cl_n_insert" )
		QuestManager.Sv_SendEvent( "event.quest_bosstrain.insert_core" )
	else
		sm.log.error( "Transaction failed" )
	end
end

-- Client

function GyroSlot.cl_n_insert( self )
	self.cl.animationProgress = 0.0
	self.cl.inserting = true
	self.interactable:setSubMeshVisible( "m_gyrocore", true )
	self.interactable:setAnimEnabled( "insert", true )
	self.interactable:setAnimProgress( "insert", 0.0 )
	self.interactable:setAnimEnabled( "idle", false )
end

function GyroSlot.client_onUpdate( self, deltaTime )
	if self.cl.inserting then
		self.cl.animationProgress = math.min( self.cl.animationProgress + (deltaTime / self.cl.insertDuration), 1.0 )
		self.interactable:setAnimProgress( "insert", self.cl.animationProgress )
		if self.cl.animationProgress >= 1.0 then
			self.cl.inserting = false
			
			self.interactable:setAnimEnabled( "insert", false )
			self.interactable:setAnimEnabled( "idle", true )
			self.interactable:setAnimProgress( "idle", 0.0 )
		end
	else
		self.cl.animationProgress = self.cl.animationProgress + deltaTime / self.cl.idleDuration
		if self.cl.animationProgress > 1.0 then
			self.cl.animationProgress = self.cl.animationProgress - 1.0
		end
		self.interactable:setAnimProgress( "idle", self.cl.animationProgress )
	end
end
