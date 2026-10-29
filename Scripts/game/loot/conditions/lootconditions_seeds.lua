LOOT_CONDITIONS.seeds = {
    [tostring( ITEMS.obj_seed_carrot )] = { minSeedTier = 2 },
    [tostring( ITEMS.obj_seed_redbeet )] = { minSeedTier = 3 },
    [tostring( ITEMS.obj_seed_banana )] = { minSeedTier = 4 },
    [tostring( ITEMS.obj_seed_blueberry )] = { minSeedTier = 5 },
    [tostring( ITEMS.obj_seed_orange )] = { minSeedTier = 6 },
    [tostring( ITEMS.obj_seed_chili )] = { minSeedTier = 6, completedQuest = "quest_find_excavation" },
    [tostring( ITEMS.obj_seed_broccoli )] = { minSeedTier = 7 },
    [tostring( ITEMS.obj_seed_pineapple )] = { minSeedTier = 8 },
}

-- Evaluated in ProgressionManager.Sv_ConditionsFulfilled