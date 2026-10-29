
TutorialManager = class( nil )

TutorialEvent = {
	HungerAndThirst = "event.tutorial.hunger_and_thirst",
	FoodPerks = "event.tutorial.food_perks",
	CreationNeedsGas = "event.tutorial.creation_needs_gas",
	KnockedOut = "event.tutorial.knocked_out",
	HowToBuildACar = "event.tutorial.how_to_build_a_car",
	PackingStation = "event.tutorial.packing_station",
	PickUpBucket = "event.tutorial.pick_up_bucket",
	RefineByHand = "event.tutorial.refine_by_hand",
	SmashACrate = "event.tutorial.smash_a_crate",
	TreeTooLarge = "event.tutorial.tree_too_large",
	ShipCraftbot = "event.tutorial.ship_craftbot",
	GasEngine = "event.tutorial.gas_engine",
	Refinerybot = "event.tutorial.refinerybot",
	MenuBuilding = "event.tutorial.menu_building",
	GarmentBox = "event.tutorial.garment_box",
	FlippedCreation = "event.tutorial.flipped_creation",
	Schematicbot = "event.tutorial.schematicbot",
	Connection = "event.tutorial.connection",
	Weld = "event.tutorial.weld",
	Piston = "event.tutorial.piston",
	Bearing = "event.tutorial.bearing",
	Garage = "event.tutorial.garage",
	Interactive = "event.tutorial.interactive",
	PlasmaDrill = "event.tutorial.plasma_drill",
	PlasmaDrillAdvanced = "event.tutorial.plasma_drill_advanced",
	Prospector = "event.tutorial.prospector"
}

TutorialGuiData = {
	[TutorialEvent.HungerAndThirst] = {
		title = "#{TUTORIAL_HUNGER_AND_THIRST_TITLE}",
		message = "#{TUTORIAL_HUNGER_AND_THIRST_MESSAGE}",
		image = "gui_tutorial_image_hunger.png",
	},
	[TutorialEvent.FoodPerks] = {
		title = "#{TUTORIAL_FOOD_PERKS_KEY_TITLE}",
		message = "#{TUTORIAL_FOOD_PERKS_KEY_MESSAGE}",
		image = "gui_tutorial_image_food_perks.png",
	},
	[TutorialEvent.CreationNeedsGas] = {
		title = "#{TUTORIAL_CREATION_NEEDS_GAS_TITLE}",
		message = "#{TUTORIAL_CREATION_NEEDS_GAS_MESSAGE}",
		image = "gui_tutorial_image_refill_engine.png",
	},
	[TutorialEvent.KnockedOut] = {
		title = "#{TUTORIAL_KNOCKED_OUT_TITLE}",
		message = "#{TUTORIAL_KNOCKED_OUT_MESSAGE}",
		image = "gui_tutorial_image_kobag.png",
	},
	[TutorialEvent.HowToBuildACar] = {
		title = "#{TUTORIAL_HOW_TO_BUILD_A_CAR_TITLE}",
		message = "#{TUTORIAL_HOW_TO_BUILD_A_CAR_MESSAGE}",
		image = "gui_tutorial_image_build_car.png",
	},
	[TutorialEvent.PackingStation] = {
		title = "#{TUTORIAL_PACKING_STATION_TITLE}",
		message = "#{TUTORIAL_PACKING_STATION_MESSAGE}",
		image = "gui_tutorial_image_packing_station.png",
	},
	[TutorialEvent.PickUpBucket] = {
		title = "#{TUTORIAL_PICKUP_ITEM_TITLE}",
		message = "#{TUTORIAL_PICKUP_ITEM_MESSAGE}",
		image = "gui_tutorial_image_pickup_items.png",
	},
	[TutorialEvent.RefineByHand] = {
		title = "#{TUTORIAL_REFINE_BY_HAND_TITLE}",
		message = "#{TUTORIAL_REFINE_BY_HAND_MESSAGE}",
		image = "gui_tutorial_image_refine.png",
	},
	[TutorialEvent.SmashACrate] = {
		title = "#{TUTORIAL_SMASH_A_CRATE_TITLE}",
		message = "#{TUTORIAL_SMASH_A_CRATE_MESSAGE}",
		image = "gui_tutorial_image_smask_crate.png",
	},
	[TutorialEvent.TreeTooLarge] = {
		title = "#{TUTORIAL_TREE_TOO_LARGE_TITLE}",
		message = "#{TUTORIAL_TREE_TOO_LARGE_MESSAGE}",
		image = "gui_tutorial_image_saw_blade.png",
	},
	[TutorialEvent.ShipCraftbot] = {
		title = "#{TUTORIAL_SHIP_CRAFTBOT_TITLE}",
		message = "#{TUTORIAL_SHIP_CRAFTBOT_MESSAGE}",
		image = "gui_tutorial_image_mini_craftbot_step1.png",
	},
	[TutorialEvent.GasEngine] = {
		title = "#{TUTORIAL_GAS_ENGINE_TITLE}",
		message = "#{TUTORIAL_GAS_ENGINE_MESSAGE}",
		image = "gui_tutorial_image_gas_engine.png",
	},
	[TutorialEvent.Refinerybot] = {
		title = "#{TUTORIAL_REFINERYBOT_TITLE}",
		message = "#{TUTORIAL_REFINERYBOT_MESSAGE}",
		image = "gui_tutorial_image_refinarybot.png",
	},
	[TutorialEvent.MenuBuilding] = {
		title = "#{TUTORIAL_MENU_BUILDING_TITLE}",
		message = "#{TUTORIAL_MENU_BUILDING_MESSAGE}",
		image = "gui_tutorial_image_menu_building.png",
	},
	[TutorialEvent.GarmentBox] = {
		title = "#{TUTORIAL_GARMENT_BOX_TITLE}",
		message = "#{TUTORIAL_GARMENT_BOX_MESSAGE}",
		image = "gui_tutorial_image_garment_box.png",
	},
	[TutorialEvent.FlippedCreation] = {
		title = "#{TUTORIAL_FLIPPED_CREATION_TITLE}",
		message = "#{TUTORIAL_FLIPPED_CREATION_MESSAGE}",
		image = "gui_tutorial_image_flipped_creation.png"
	},
	[TutorialEvent.Schematicbot] = {
		title = "#{TUTORAIL_SCHEMATICBOT_TITLE}",
		message = "#{TUTORAIL_SCHEMATICBOT_MESSAGE}",
		image = "gui_tutorial_image_schematic_station.png"
	},
	[TutorialEvent.Connection] = {
		title = "#{TUTORIAL_CONNECTION_TITLE}",
		message = "#{TUTORIAL_CONNECTION_MESSAGE}",
		image = "gui_tutorial_image_connect_tool.png"
	},
	[TutorialEvent.Weld] = {
		title = "#{TUTORIAL_WELD_TITLE}",
		message = "#{TUTORIAL_WELD_MESSAGE}",
		image = "gui_tutorial_image_weld.png"
	},
	[TutorialEvent.Piston] = {
		title = "#{TUTORIAL_PISTON_TITLE}",
		message = "#{TUTORIAL_PISTON_MESSAGE}",
		image = "gui_tutorial_image_piston.png"
	},
	[TutorialEvent.Bearing] = {
		title = "#{TUTORIAL_BEARINGS_KEY_TITLE}",
		message = "#{TUTORIAL_BEARINGS_KEY_MESSAGE}",
		image = "gui_tutorial_image_bearing.png"
	},
	[TutorialEvent.Garage] = {
		title = "#{TUTORIAL_GARAGE_TITLE}",
		message = "#{TUTORIAL_GARAGE_MESSAGE}",
		image = "gui_tutorial_image_garage.png"
	},
	[TutorialEvent.Interactive] = {
		title = "#{TUTORIAL_INTERACTIVE_KEY_TITLE}",
		message = "#{TUTORIAL_INTERACTIVE_KEY_MESSAGE}",
		image = "gui_tutorial_image_parts_surface.png"
	},
	[TutorialEvent.PlasmaDrill] = {
		title = "#{TUTORIAL_PLASMA_DRILL_TITLE}",
		message = "#{TUTORIAL_PLASMA_DRILL_MESSAGE}",
		image = "gui_tutorial_image_plasma_drill.png"
	},
	[TutorialEvent.PlasmaDrillAdvanced] = {
		title = "#{TUTORIAL_PLASMA_DRILL_ADVANCED_TITLE}",
		message = "#{TUTORIAL_PLASMA_DRILL_ADVANCED_MESSAGE}",
		image = "gui_tutorial_image_plasma_drill_advanced.png"
	},
	[TutorialEvent.Prospector] = {
		title = "#{TUTORIAL_PROSPECTOR_TITLE}",
		message = "#{TUTORIAL_PROSPECTOR_MESSAGE}",
		image = "gui_tutorial_image_prospector.png"
	}
}

for eventName, eventId in pairs( TutorialEvent ) do
	assert( TutorialGuiData[eventId] ~= nil, "Missing TutorialGuiData for TutorialEvent." .. eventName )
end

for eventId, _ in pairs( TutorialGuiData ) do
	assert( isAnyOf( eventId, TutorialEvent ), "TutorialGuiData contains unknown event key: " .. tostring( eventId ) )
end

function TutorialManager.server_onCreate( self )
	assert( g_tutorialManager == nil )
	g_tutorialManager = self
	self.sv = {}
end

function TutorialManager.Sv_TutorialEvent( event, client )
	if g_tutorialManager then
		sm.event.sendToScriptableObject( g_tutorialManager.scriptableObject, "sv_e_tutorialEvent", { event = event, client = client } )
	end
end

function TutorialManager.sv_e_tutorialEvent( self, params )
	if params.client then
		self.network:sendToClient( params.client, "cl_tutorialEvent", params.event )
	else
		self.network:sendToClients( "cl_tutorialEvent", params.event )
	end
end

function TutorialManager.client_onCreate( self )
	assert( g_tutorialManagerClient == nil )
	g_tutorialManagerClient = self

	self.cl = {}
	self.cl.watchedTutorials = sm.game.loadWatchedTutorials() or {}
	self.cl.incomingTutorials = {}
	self.cl.activeTutorial = nil
end

function TutorialManager.client_onFixedUpdate( self, timestep )
	if not self.cl.activeTutorial and self.cl.loadingScreenLifted then
		local nextTutorialName, _ = next( self.cl.incomingTutorials )
		if nextTutorialName then
			local tutorialGuiData = TutorialGuiData[nextTutorialName]
			local tutorialData = sm.json.open( "$GAME_DATA/Gui/JsonGuis/Tutorial.gui" )
			FindWidget( tutorialData, "TextTitle" ).Caption = tutorialGuiData.title
			FindWidget( tutorialData, "TextMessage" ).Caption = tutorialGuiData.message
			FindWidget( tutorialData, "ImageTutorial" ).ImageTexture = tutorialGuiData.image
			FindWidget( tutorialData, "TextDismiss" ).Caption = "#{TUTORIAL_DISMISS}"
			self.cl.jsonGui = sm.jsonGui.createGui( { layer = "LuaNotification", isInteractive = false, bNeedsCursor = false, isHud = true, handleKeySetup = "Tutorial" } )
			self.cl.jsonGui:render( tutorialData )
			self.cl.activeTutorial = nextTutorialName

			self.cl.incomingTutorials[nextTutorialName] = nil
			self.cl.watchedTutorials[nextTutorialName] = true
			sm.game.saveWatchedTutorials( self.cl.watchedTutorials )
		end
	end
end

function TutorialManager.cl_onGuiClosed( self )
	self.cl.activeTutorial = nil
	self.cl.jsonGui = nil
end

function TutorialManager.Cl_TutorialEvent( event )
	if g_tutorialManagerClient then
		g_tutorialManagerClient:cl_tutorialEvent( event )
	end
end

function TutorialManager.cl_tutorialEvent( self, event )
	if not self.cl.watchedTutorials[event] then
		self.cl.incomingTutorials[event] = true
	end
end

function TutorialManager.Cl_OnLoadingScreenLifted()
	if g_tutorialManagerClient then
		g_tutorialManagerClient.cl.loadingScreenLifted = true
	end
end

function TutorialManager.Cl_HasWatched( event )
	return g_tutorialManagerClient and g_tutorialManagerClient.cl.watchedTutorials[event] or false
end
