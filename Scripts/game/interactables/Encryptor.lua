dofile( "$SURVIVAL_DATA/Scripts/util.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/survival_items.lua" )

Encryptor = class()
Encryptor.maxChildCount = 0
Encryptor.maxParentCount = 1
Encryptor.connectionInput = sm.interactable.connectionType.logic
Encryptor.connectionOutput = sm.interactable.connectionType.none
Encryptor.colorNormal = sm.color.new( 0x808080ff )
Encryptor.colorHighlight = sm.color.new( 0x808080ff )

function Encryptor.server_onCreate( self )
	local startActive = self.interactable.active
	self.sv = {}
	self.sv.body = self.shape:getBody()
	if self.params then
		if self.params.active ~= nil then
			self.interactable.active = self.params.active -- In effect next tick
			startActive = self.params.active
		end
	end
	self.sv.prevActive = startActive
	self:sv_updateRestrictions( startActive )
end

function Encryptor.server_onDestroy( self )
	self:sv_updateRestrictions( false )
end

function Encryptor.server_onFixedUpdate( self, timeStep )
	self.sv.body = self.shape:getBody()
	local active
	local parent = self.interactable:getSingleParent()
	if parent then
		active = parent.active
	else
		active = self.interactable.active
	end
	if active ~= self.sv.prevActive then
		self.sv.prevActive = active
		self:sv_updateRestrictions( active )
	end
end

function Encryptor.client_canInteract( self, character, state )
	if self.interactable:getSingleParent() then
		return false
	end
	return true
end

function Encryptor.client_onInteract( self, character, state )
	if state == true then
		self.network:sendToServer( "sv_n_switchActiveState", not self.interactable.active )
	end
end

function Encryptor.sv_n_switchActiveState( self, requestedState )
	self.interactable.active = requestedState
end

function Encryptor.sv_updateRestrictions( self, encryptionActive )
	if not sm.exists( self.sv.body ) then
		return
	end

	for _, encryption in ipairs( self.data.encryptions ) do
		self.sv.body[encryption] = not encryptionActive
	end

	if encryptionActive then
		if self.data.activationEffect then
			sm.effect.playEffect( self.data.activationEffect, self.shape.worldPosition, nil, self.shape.worldRotation )
		end
	else
		if self.data.deactivationEffect then
			sm.effect.playEffect( self.data.deactivationEffect, self.shape.worldPosition, nil, self.shape.worldRotation )
		end
	end
end