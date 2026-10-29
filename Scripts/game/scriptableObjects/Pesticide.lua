Pesticide = class( nil )
Pesticide.isSaveObject = true

function Pesticide.server_onCreate( self )
	self.sv = {}
	self.sv.saved = self.storage:load()
	if self.sv.saved == nil then
		self.sv.saved = {}
		self.sv.saved.lifeTicks = 0
		self.sv.saved.position = self.params.position
		self.sv.saved.rotation = self.params.rotation
		self.sv.saved.sizeModifier = self.params.sizeModifier or 0.5
		self.sv.saved.pesticideLifeDuration = self.params.pesticideLifeDuration and ( self.params.pesticideLifeDuration * 40 ) or (40 * 12.0)
	end
	self.sv.destroyed = false

	self.sv.areaTrigger = sm.areaTrigger.createBox( PESTICIDE_SIZE * self.sv.saved.sizeModifier, self.sv.saved.position, self.sv.saved.rotation, sm.areaTrigger.filter.character )
	self.sv.areaTrigger:bindOnStay( "trigger_onStayPesticide", self )

	self.network:setClientData( { position = self.sv.saved.position, rotation = self.sv.saved.rotation, size = self.sv.saved.sizeModifier } )
	self.storage:save( self.sv.saved )
end

function Pesticide.server_onFixedUpdate( self )
	self.sv.saved.lifeTicks = self.sv.saved.lifeTicks + 1
	if self.sv.saved.lifeTicks % 20 == 0 then
		self.storage:save( self.sv.saved )
	end
	if self.sv.saved.lifeTicks >= self.sv.saved.pesticideLifeDuration and not self.sv.destroyed then
		self.sv.destroyed = true
		sm.areaTrigger.destroy( self.sv.areaTrigger )
		self.scriptableObject:destroy()
	end
end

function Pesticide.trigger_onStayPesticide( self, trigger, results )
	for _, result in ipairs( results ) do
		if sm.exists( result ) then
			if type( result ) == "Character" then
				if result:isPlayer() then
					sm.event.sendToPlayer( result:getPlayer(), "sv_e_onStayPesticide" )
				end
			end
		end
	end
end


function Pesticide.client_onCreate( self )
	self.cl = {}
end

function Pesticide.client_onDestroy( self )
	if self.cl.effect then
		self.cl.effect:stop()
		self.cl.effect:destroy()
	end
end

function Pesticide.client_onClientDataUpdate( self, data )
	if ( data.size >= 0.5 ) then
		self.effect = "Pesticide - Cloud"
	else
		self.effect = "Fire - Chemicalfire" -- TODO use smaller effect.
	end

	self.cl.effect = sm.effect.createEffect( self.effect )

	self.cl.effect:setPosition( data.position )
	self.cl.effect:setRotation( data.rotation )
	self.cl.effect:start()
end