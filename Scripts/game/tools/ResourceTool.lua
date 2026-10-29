
dofile "$SURVIVAL_DATA/Scripts/game/survival_shapes.lua"

ResourceTool = class()

function ResourceTool.client_onEquippedUpdate( self, primaryState, secondaryState )
	local success, result = sm.localPlayer.getLatestRaycast()
	if success and result.type == "body" then
		local targetShape = result:getShape()
		if isAnyOf( targetShape:getShapeUuid(), { ITEMS.obj_interactive_prospector } ) then
			if primaryState == sm.tool.interactState.start then
				local params = { targetShape = targetShape, itemId = sm.localPlayer.getActiveItem() }
				self.network:sendToServer( "sv_n_use", params )
			end
			return true, false
		end
	end
	return false, false
end

function ResourceTool.client_onEquip( self ) end

function ResourceTool.client_onUnequip( self ) end

function ResourceTool.sv_n_use( self, params, player )
	if params.targetShape.interactable then
		params.player = player
		sm.event.sendToInteractable( params.targetShape.interactable, "sv_e_collectResource", params )
	end
end
