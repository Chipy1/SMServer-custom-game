TRASHBOT_HP_THRESHOLDS[2] =
{
	{
	},
	{
	},
	{
	}
}

TRASHBOT_STATS[2] = {
	healthPerPhase = 30,
	coreHitsToRecover = 5,
	stunTime = 3
}

TRASHBOT_PATTERNS[2] =
{
	{
		{
			sequence = {
				{ type = TrashbotAttack.SPRAY_GROUND,    count = 1, nextAttackWaitTime = 0.0, duration = 10 }
			},
			nextPatternIndex = { 2 },
			eyeOpen = false,
			bulletPatternName = "P1_START",
			waitTimeBetweenAttacks = 1.0
		},
		{
			sequence = {
				{ type = TrashbotAttack.JUNK_WAVE,    		count = 1, nextAttackWaitTime = 2.0, color = "purple", waveAmount = 2 },
				{ type = TrashbotAttack.JUNK_WAVE,    		count = 1, nextAttackWaitTime = 2.0, color = "green", waveAmount = 2 },
				{ type = TrashbotAttack.JUNK_WAVE,    		count = 1, nextAttackWaitTime = 2.0, color = "purple", waveAmount = 1 },
				{ type = TrashbotAttack.JUNK_WAVE,    		count = 1, nextAttackWaitTime = 2.0, color = "green", waveAmount = 1 },
				{ type = TrashbotAttack.JUNK_WAVE,    		count = 1, nextAttackWaitTime = 2.0, color = "purple", waveAmount = 1 },
				{ type = TrashbotAttack.JUNK_WAVE,    		count = 1, nextAttackWaitTime = 2.0, color = "green", waveAmount = 1 },
				{ type = TrashbotAttack.JUNK_WAVE,    		count = 1, nextAttackWaitTime = 2.0, color = "green", waveAmount = 1 },
				{ type = TrashbotAttack.JUNK_WAVE,    		count = 1, nextAttackWaitTime = 2.0, color = "purple", waveAmount = 1 },
				{ type = TrashbotAttack.JUNK_WAVE,    		count = 1, nextAttackWaitTime = 2.0, color = "green", waveAmount = 1 },
				{ type = TrashbotAttack.JUNK_WAVE,    		count = 1, nextAttackWaitTime = 0.0, color = "green", waveAmount = 1 },
			},
			nextPatternIndex = { 3 },
			eyeOpen = true,
			bulletPatternName = "P1_OPENING",
			waitTimeBetweenAttacks = 1.0
		},
		{
			sequence = {
				{ type = TrashbotAttack.CHARGED_BULLET, count = 1, nextAttackWaitTime = 2.0, forceArm = TRASHBOT_ARM.left },
				{ type = TrashbotAttack.CHARGED_BULLET, count = 1, nextAttackWaitTime = 2.0, forceArm = TRASHBOT_ARM.right, multiplayerOnly = true },
				{ type = TrashbotAttack.CHARGED_BULLET, count = 1, nextAttackWaitTime = 2.0, forceArm = TRASHBOT_ARM.left,  multiplayerOnly = true  },
				{ type = TrashbotAttack.CHARGED_BULLET, count = 1, nextAttackWaitTime = 2.0, forceArm = TRASHBOT_ARM.right },
			},
			nextPatternIndex = { 4 },
			eyeOpen = true,
			bulletPatternName = "P1_LOOP_1",
			waitTimeBetweenAttacks = 1.0
		},
		{
			sequence = {
				{ type = TrashbotAttack.JUNK_WAVE,    	count = 1, nextAttackWaitTime = 2.0, color = "green", waveAmount = 2 },
				{ type = TrashbotAttack.CHARGED_BULLET, count = 1, nextAttackWaitTime = 4.0, forceArm = TRASHBOT_ARM.left },
				{ type = TrashbotAttack.CHARGED_BULLET, count = 1, nextAttackWaitTime = 3.0, forceArm = TRASHBOT_ARM.right, multiplayerOnly = true },
				{ type = TrashbotAttack.JUNK_WAVE,    	count = 1, nextAttackWaitTime = 2.0, color = "purple", waveAmount = 2 },
				{ type = TrashbotAttack.CHARGED_BULLET, count = 1, nextAttackWaitTime = 2.0, forceArm = TRASHBOT_ARM.left, multiplayerOnly = true },
				{ type = TrashbotAttack.CHARGED_BULLET, count = 1, nextAttackWaitTime = 2.0, forceArm = TRASHBOT_ARM.right },
			},
			nextPatternIndex = { 3 },
			eyeOpen = true,
			eyeClosedDuration = 2.0,
			eyeOpenDuration = 3.0,
			bulletPatternName = "P1_LOOP_1",
			waitTimeBetweenAttacks = 1.0,
		}
	},
	{
		{
			sequence = {
				{ type = TrashbotAttack.SPRAY_GROUND,    count = 1, nextAttackWaitTime = 5.0, duration = 10 }
			},
			nextPatternIndex = { 2 },
			eyeOpen = false,
			bulletPatternName = "P2_LOOP_1",
			waitTimeBetweenAttacks = 2.0
		},
		{
			sequence = {
				{ type = TrashbotAttack.BULLET_SPRAY, 	count = 1, nextAttackWaitTime = 1.0, 		duration = 1.5, forceArm = TRASHBOT_ARM.right},
				{ type = TrashbotAttack.VOLLEY_BOMB,  	count = 1, nextAttackWaitTime = 1.5, 		forceArm = TRASHBOT_ARM.left },
				{ type = TrashbotAttack.VOLLEY_BOMB,  	count = 1, nextAttackWaitTime = 1.5, 		forceArm = TRASHBOT_ARM.right },
				{ type = TrashbotAttack.BULLET_SPRAY, 	count = 1, nextAttackWaitTime = 1.0, 		duration = 1.5, forceArm = TRASHBOT_ARM.left},
				{ type = TrashbotAttack.VOLLEY_BOMB,  	count = 1, nextAttackWaitTime = 1.5, 		forceArm = TRASHBOT_ARM.right },
				{ type = TrashbotAttack.VOLLEY_BOMB,  	count = 1, nextAttackWaitTime = 1.5, 		forceArm = TRASHBOT_ARM.left },
				{ type = TrashbotAttack.BULLET_SPRAY, 	count = 1, nextAttackWaitTime = 1.0, 		duration = 1.5, forceArm = TRASHBOT_ARM.right},
				{ type = TrashbotAttack.VOLLEY_BOMB,  	count = 1, nextAttackWaitTime = 1.5, 		forceArm = TRASHBOT_ARM.left },
				{ type = TrashbotAttack.VOLLEY_BOMB,  	count = 1, nextAttackWaitTime = 1.5, 		forceArm = TRASHBOT_ARM.right },
				{ type = TrashbotAttack.BULLET_SPRAY, 	count = 1, nextAttackWaitTime = 1.0, 		duration = 1.5, forceArm = TRASHBOT_ARM.left},
				{ type = TrashbotAttack.VOLLEY_BOMB,  	count = 1, nextAttackWaitTime = 1.5, 		forceArm = TRASHBOT_ARM.right },
				{ type = TrashbotAttack.VOLLEY_BOMB,  	count = 1, nextAttackWaitTime = 1.5, 		forceArm = TRASHBOT_ARM.left },
			},
			nextPatternIndex = { 2 },
			eyeOpen = false,
			eyeClosedDuration = 3.0,
			eyeOpenDuration = 4.0,
			bulletPatternName = "P2_LOOP_1",
			waitTimeBetweenAttacks = 2.0
		}
	},
	{
		{
			sequence = {
				{ type = TrashbotAttack.SPRAY_GROUND,    count = 1, nextAttackWaitTime = 2.0, duration = 10 }
			},
			nextPatternIndex = { 2 },
			eyeOpen = false,
			bulletPatternName = "P3_LOOP_01",
			waitTimeBetweenAttacks = 2.0
		},
		{
			sequence = {
				{ type = TrashbotAttack.CHARGED_BULLET, count = 1, nextAttackWaitTime = 2.0, 		forceArm = TRASHBOT_ARM.left },
				{ type = TrashbotAttack.CHARGED_BULLET, count = 1, nextAttackWaitTime = 2.0, 		forceArm = TRASHBOT_ARM.right },
				{ type = TrashbotAttack.CHARGED_BULLET, count = 1, nextAttackWaitTime = 2.0, 		forceArm = TRASHBOT_ARM.left,  multiplayerOnly = true },
				{ type = TrashbotAttack.CHARGED_BULLET, count = 1, nextAttackWaitTime = 2.0, 		forceArm = TRASHBOT_ARM.right, multiplayerOnly = true },
				{ type = TrashbotAttack.CHARGED_BULLET, count = 1, nextAttackWaitTime = 2.0, 		forceArm = TRASHBOT_ARM.left },
				{ type = TrashbotAttack.CHARGED_BULLET, count = 1, nextAttackWaitTime = 2.0, 		forceArm = TRASHBOT_ARM.right },
				{ type = TrashbotAttack.CHARGED_BULLET, count = 1, nextAttackWaitTime = 2.0, 		forceArm = TRASHBOT_ARM.left,  multiplayerOnly = true },
				{ type = TrashbotAttack.CHARGED_BULLET, count = 1, nextAttackWaitTime = 2.0, 		forceArm = TRASHBOT_ARM.right, multiplayerOnly = true },
			},
			nextPatternIndex = { 3 },
			eyeOpen = false,
			eyeClosedDuration = 2.0,
			eyeOpenDuration = 4.0,
			bulletPatternName = "P3_LOOP_01",
			waitTimeBetweenAttacks = 1.0,
		},
		{
			sequence = {
				{ type = TrashbotAttack.SPRAY_GROUND,    count = 1, nextAttackWaitTime = 2.0, duration = 10 }
			},
			nextPatternIndex = { 4 },
			eyeOpen = true,
			bulletPatternName = "P3_CHAOS_01",
			waitTimeBetweenAttacks = 1.0
		},
		{
			sequence = {
				{ type = TrashbotAttack.JUNK_WAVE,    	count = 1, nextAttackWaitTime = 2.0, color = "purple", waveAmount = 2 },
				{ type = TrashbotAttack.JUNK_WAVE,    	count = 1, nextAttackWaitTime = 2.0, color = "green", waveAmount = 2 },
				{ type = TrashbotAttack.JUNK_WAVE,    	count = 1, nextAttackWaitTime = 2.0, color = "purple", waveAmount = 1 },
				{ type = TrashbotAttack.JUNK_WAVE,    	count = 1, nextAttackWaitTime = 2.0, color = "green", waveAmount = 1 },
				{ type = TrashbotAttack.JUNK_WAVE,    	count = 1, nextAttackWaitTime = 3.0, color = "purple", waveAmount = 1 },
				{ type = TrashbotAttack.JUNK_WAVE,    	count = 1, nextAttackWaitTime = 3.0, color = "green", waveAmount = 1 },
				{ type = TrashbotAttack.JUNK_WAVE,    	count = 1, nextAttackWaitTime = 3.0, color = "purple", waveAmount = 1 },
				{ type = TrashbotAttack.JUNK_WAVE,    	count = 1, nextAttackWaitTime = 3.0, color = "green", waveAmount = 1 },
			},
			nextPatternIndex = { 5 },
			eyeOpen = false,
			eyeClosedDuration = 2.0,
			eyeOpenDuration = 4.0,
			bulletPatternName = "P3_LOOP_02",
			waitTimeBetweenAttacks = 1.0,
		},
		{
			sequence = {
				{ type = TrashbotAttack.SPRAY_GROUND,    count = 1, nextAttackWaitTime = 2.0, duration = 10 }
			},
			nextPatternIndex = { 6 },
			eyeOpen = true,
			bulletPatternName = "P3_CHAOS_02",
			waitTimeBetweenAttacks = 1.0
		},
		{
			sequence = {
				{ type = TrashbotAttack.CHARGED_BULLET, count = 1, nextAttackWaitTime = 2.0, 		forceArm = TRASHBOT_ARM.left },
				{ type = TrashbotAttack.CHARGED_BULLET, count = 1, nextAttackWaitTime = 2.0, 		forceArm = TRASHBOT_ARM.right },
				{ type = TrashbotAttack.CHARGED_BULLET, count = 1, nextAttackWaitTime = 2.0, 		forceArm = TRASHBOT_ARM.left,  multiplayerOnly = true },
				{ type = TrashbotAttack.CHARGED_BULLET, count = 1, nextAttackWaitTime = 2.0, 		forceArm = TRASHBOT_ARM.right, multiplayerOnly = true },
				{ type = TrashbotAttack.CHARGED_BULLET, count = 1, nextAttackWaitTime = 2.0, 		forceArm = TRASHBOT_ARM.left },
				{ type = TrashbotAttack.CHARGED_BULLET, count = 1, nextAttackWaitTime = 2.0, 		forceArm = TRASHBOT_ARM.right },
				{ type = TrashbotAttack.CHARGED_BULLET, count = 1, nextAttackWaitTime = 2.0, 		forceArm = TRASHBOT_ARM.left,  multiplayerOnly = true },
				{ type = TrashbotAttack.CHARGED_BULLET, count = 1, nextAttackWaitTime = 2.0, 		forceArm = TRASHBOT_ARM.right, multiplayerOnly = true },
			},
			nextPatternIndex = { 1 },
			eyeOpen = false,
			eyeClosedDuration = 2.0,
			eyeOpenDuration = 4.0,
			bulletPatternName = "P3_LOOP_03",
			waitTimeBetweenAttacks = 1.0,
		},
	},
	{
		{
			sequence = {
					{ type = TrashbotAttack.DESTRUCTION_SWAY },
				},
			nextPatternIndex = { 1 },
			eyeOpen = true,
			eyeHitThreshold = math.huge, -- Final phase core hits count as eye hits
			bulletPatternName = "PHASE_4",
			waitTimeBetweenAttacks = 1.0,
		}
	}
}

TRASHBOT_BULLET_HELL_SETTINGS[2] = {
	{
		["P1_OPENING"] = {
			{
				sequenceName = "Start",
				activationDelay = 1.1,
				nextPatternIndex = 1,
				systemList =
				{
					"fight2_curved_alternating",
				}
			},
		},
		["P1_START"] = {
			{
				sequenceName = "Start",
				activationDelay = 1.1,
				nextPatternIndex = 1,
				systemList =
				{
					"V2_fight2_Phase1_opener",
				}
			},
		},
		["P1_LOOP_1"] = {
			{
				sequenceName = "1",
				activationDelay = 5.0,
				nextPatternIndex = 2,
				useUnitRotation = true,
				systemList =
				{
					"F1_02_Maze_01",
				}
			},
			{
				sequenceName = "2",
				activationDelay = 0.0,
				nextPatternIndex = 3,
				useUnitRotation = true,
				systemList =
				{
					"F1_02_Maze_02",
				}
			},
			{
				sequenceName = "3",
				activationDelay = 0.0,
				nextPatternIndex = 4,
				useUnitRotation = true,
				systemList =
				{
					"F1_02_Maze_03",
				}
			},
			{
				sequenceName = "4",
				activationDelay = 0.0,
				nextPatternIndex = 5,
				useUnitRotation = true,
				systemList =
				{
					"F1_02_Maze_04",
				}
			},
			{
				sequenceName = "5",
				activationDelay = 0.0,
				nextPatternIndex = 6,
				useUnitRotation = true,
				systemList =
				{
					"F1_02_Maze_01",
				}
			},
			{
				sequenceName = "6",
				activationDelay = 0.0,
				nextPatternIndex = 7,
				useUnitRotation = true,
				systemList =
				{
					"F1_02_Maze_02",
				}
			},
			{
				sequenceName = "7",
				activationDelay = 0.0,
				nextPatternIndex = 1,
				useUnitRotation = false,
				systemList =
				{
					"F1_02_Maze_05",
				}
			},
		},
	},
	{
		["P2_LOOP_1"] = {
			{
				sequenceName = "1",
				activationDelay = 0.0,
				nextPatternIndex = 1,
				systemList =
				{
					"V2_fight2_Phase2_loop1",
				}
			}
		},
	},
	{
		["P3_START"] = {
			{
				sequenceName = "P2_LOOP_1_PART_1",
				activationDelay = 0.0,
				nextPatternIndex = 4,
				systemList =
				{
					"F1_P3_Start",
				}
			},
		},
		["P3_LOOP_01"] = {
			{
				sequenceName = "P2_LOOP_1_PART_1",
				activationDelay = 1.0,
				nextPatternIndex = 2,
				systemList =
				{
					"fight2_curved_hypnoiticrings",
				}
			},

		},
		["P3_CHAOS_01"] = {
			{
				sequenceName = "Start",
				activationDelay = 4.1,
				nextPatternIndex = 1,
				systemList =
				{
					"V2_fight2_Phase1_opener",
				}
			},
		},
		["P3_LOOP_02"] = {
			{
				sequenceName = "P2_LOOP_1_PART_1",
				activationDelay = 0.0,
				nextPatternIndex = 4,
				systemList =
				{
					"F1_SpiralCurved_01",
				}
			}
		},
		["P3_CHAOS_02"] = {
			{
				sequenceName = "Start",
				activationDelay = 1.1,
				nextPatternIndex = 1,
				systemList =
				{
					"Fight1_Phase2_AlternatingCircle",
				}
			},
		},
		["P3_LOOP_03"] = {
			{
				sequenceName = "P2_LOOP_1_PART_1",
				activationDelay = 0.0,
				nextPatternIndex = 4,
				systemList =
				{
					"Fight1_Phase2_WavyChaos",
				}
			}
		},
		
	},
	{
		["PHASE_4"] = {
			{
				sequenceName = "P2_LOOP_1_PART_1",
				activationDelay = 0.0,
				nextPatternIndex = 1,
				useUnitRotation = true,
				systemList =
				{
					"F1_P3_Start",
				}
			},
		},
		["P3_LOOP_02"] = {
			{
				sequenceName = "P2_LOOP_1_PART_1",
				activationDelay = 0.0,
				nextPatternIndex = 2,
				systemList =
				{
					"F1_SpiralCurved_01",
				}
			}
		}
	}
}