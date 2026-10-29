TutorialBed = class( Bed )

function TutorialBed.server_onCreate( self )
	Bed.server_onCreate( self )
	self.sv = {}
	self.sv.saved = self.storage:load()
	if self.sv.saved == nil then
		QuestPinManager.Sv_AddPin( self.shape, self.shape.body:getWorld(), "SleepPin", sm.vec3.new( 0, 0, 1 ) )
	end	
end


function TutorialBed.sv_activateBed( self, character )
	g_respawnManager:sv_registerBed( self.shape, character )
	if self.sv.saved == nil then
		self.sv.saved = {}
		self.storage:save( self.sv.saved )
		QuestPinManager.Sv_RemovePin( self.shape.id, type( self.shape ) )
	end
end