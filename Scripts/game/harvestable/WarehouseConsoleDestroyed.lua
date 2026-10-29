WarehouseConsoleDestroyed = class()

function WarehouseConsoleDestroyed.client_onCreate( self )
	self.cl = {}
	self.cl.effect = sm.effect.createEffect( "Controlconsole - Destroyed Smokeloop", self.harvestable )
	self.cl.effect:start()
	DialogManager.Cl_RegisterSpeaker( self.harvestable, DialogSpeakerName.Mainframe )
end

function WarehouseConsoleDestroyed.client_onDestroy( self )
	if self.cl.effect then
		self.cl.effect:destroy()
		self.cl.effect = nil
	end
end