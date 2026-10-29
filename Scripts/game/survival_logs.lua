-- Should match Survival/Logs/log_entries.json names
LOGS = {
	log_babywoc = "be3b153c-d71c-4d3a-9570-013ebf128a12",
	log_mechanicstation = "29d72e47-8eac-4fb9-95b1-ecccc06ff84f",
	log_crashedship = "ee4ab0d3-027a-4969-9436-5b23c26e5eeb",
	log_hideout = "2e3dbf78-f4e3-4d37-bff6-c11b5031c1b9",
	log_audioBunkRecording = "6d7cf454-4c01-4e3b-8f6d-a9dbf6234522",
	log_audioBunkRecording2 = "1be51b09-65a1-4241-bcaf-1e64f3152e02",
	log_warehouseRecording = "fe721e78-eff6-4dd8-a323-deb65a17648f",
	log_warehousemasterkey = "cabd1534-6d08-406c-a15c-f598a9594ba6",
	log_warehouse_key = "e877b877-0387-4a8b-a7e4-a66663c8e7fe",
	log_garage = "40a7cbfb-3e9c-47cb-b054-ed6758007cdb",
	log_mininghub = "dd5082ff-066a-4e98-be26-d8e9ef1df20d",
	log_packingstation_vegetable = "71fa62f6-c121-4e60-b1c1-5a4fbfd41522",
	log_packingstation_fruit = "d16f9ffd-f18a-4428-8a6f-72d1afe8aed6",

	log_growlab_01 = "67c579bf-d0f8-4e66-8504-50b6eddd7c56",
	log_growlab_02 = "ceb02530-80f8-4bf5-a57e-7d05946b2f21",
	log_growlab_03 = "74ccefaf-8984-4e4b-ba04-f07a33e48ba8",
	log_growlab_04 = "eea67672-c5b1-4c28-8783-ecd05e7b5310",
	log_growlab_05 = "e5ff8eed-dd5b-4533-9152-a6c393164798",
	log_growlab_06 = "db5bcb14-7138-49fd-acd7-b831c182e3df",
	log_growlab_07 = "b2c71b5f-163f-48d8-b470-5c08ac3c128b",

	log_accesscard_01 = "7cd0faee-77bb-4afc-a2e2-d198a5c16200",
	log_accesscard_02 = "ae6773eb-c842-4dd8-8421-d83ed7069ace",
	log_accesscard_03 = "d8239bc7-7232-4d66-9d7f-893cd3b45dcd",
	log_accesscard_04 = "63ad737c-e03e-4c64-a8de-86cac9e5e6b7",

	log_underground_elevator_key_01 = "6eb805a0-e19f-4619-a1fe-aa1a2167352b",
	log_underground_minerboss_key = "38d9393a-1abb-427f-aaa6-6a58f62085c6",
	log_lorenzo_photo = "364d2f17-de2b-4c55-ab02-07d7b8fe3bc9",
}
log_mechanicstation = "29d72e47-8eac-4fb9-95b1-ecccc06ff84f" -- Legacy support
log_crashedship = "ee4ab0d3-027a-4969-9436-5b23c26e5eeb" -- Legacy support

-- To find log_.. usage without LOGS.
-- Regex: "(?<!\.)\blog_"

g_growlabLogs = {
	{ uuid = LOGS.log_growlab_01, color = "ffd100ff", lootConditions = { impossible = true } },
	{ uuid = LOGS.log_growlab_02, color = "ff7d00ff", lootConditions = { minSeedTier = 2 } },
	{ uuid = LOGS.log_growlab_03, color = "00f3ffff", lootConditions = { minSeedTier = 3 } },
	{ uuid = LOGS.log_growlab_04, color = "38c455ff", lootConditions = { minSeedTier = 4 } },
	{ uuid = LOGS.log_growlab_05, color = "d850ffff", lootConditions = { minSeedTier = 5 } },
	{ uuid = LOGS.log_growlab_06, color = "3265ffff", lootConditions = { minSeedTier = 6 } },
	{ uuid = LOGS.log_growlab_07, color = "ff1d1dff", lootConditions = { minSeedTier = 7 } },
}
