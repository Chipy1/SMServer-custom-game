BaseEnemyCharacter = class( nil )

function BaseEnemyCharacter.server_onCreate( self )
	self.character.publicData = {}
end

function BaseEnemyCharacter.sv_e_markEnemy( self, data )
	data.tick = sm.game.getServerTick()
    self.network:setClientData( data )
end

function BaseEnemyCharacter.client_onClientDataUpdate( self, data, channel )
	if channel == 1 then
		self.cl.marked = true
		if not data.raider then
			self.cl.markEffect = sm.effect.createEffect( "EnemyMarker", self.character, nil, sm.effect.axis.all )
			self.cl.markEffect:setOffsetPosition( sm.vec3.new( 0, 0, self.character:getHeight() ) )
			self.cl.markEffect:start()
			if g_compassHud then
				local icon = "icon_farmraid_compass_bot.png"
				if self.character:getCharacterType() == unit_farmbot then
					icon = "icon_farmraid_compass_farmbot.png"
				end
				g_compassHud:compassAddIcon( "enemy"..self.character.id, icon, false, 8, 12  )
				g_compassHud:compassSetIconHost( "enemy"..self.character.id, self.character )
				g_compassHud:setVisible( "enemy"..self.character.id, true )
			end
		elseif data.raider and data.raidKey then
			self.cl.markedRaider = true
			self.cl.raidKey = data.raidKey
			RaidManager.Cl_AddTrackedRaidEnemy( data.raidKey, self.character )
		end
	end
end

function BaseEnemyCharacter.client_onCreate( self )
	self.character.clientPublicData = {}
end

function BaseEnemyCharacter.client_onDestroy( self )
	if self.cl.marked and not self.cl.raider then
		if g_compassHud then
			g_compassHud:compassRemoveIcon( "enemy"..self.character.id )
		end
		if self.cl.markEffect then
			self.cl.markEffect:stop()
			self.cl.markEffect:destroy()
		end
	elseif self.cl.marked and self.cl.raidKey then
		RaidManager.Cl_RemoveTrackedRaidEnemy( self.cl.raidKey, self.character )
	end
end