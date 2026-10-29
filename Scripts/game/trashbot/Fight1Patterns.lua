TRASHBOT_HP_THRESHOLDS[1] =
{
	{
		[0.85] = {
			sequence = {
				{ type = TrashbotAttack.BULLET_SPRAY, count = 1, nextAttackWaitTime = 4.0, duration = 3, forceArm = TRASHBOT_ARM.left },
			},
			nextPatternIndex = { 3 },
			eyeOpen = false,
			bulletPatternName = "P1_LOOP_2",
			waitTimeBetweenAttacks = 0.0,
		}
	}
}

TRASHBOT_STATS[1] = {
	healthPerPhase = 30,
	coreHitsToRecover = 5,
	stunTime = 3
}

TRASHBOT_PATTERNS[1] =
{
	{
		{
			sequence = {
				{ type = TrashbotAttack.SPRAY_GROUND,    count = 1, nextAttackWaitTime = 2.0, duration = 10 },
			},
			nextPatternIndex = { 2 },
			eyeOpen = false,
			eyeHitThreshold = 3,
			bulletPatternName = "P1_LOOP_1",
			waitTimeBetweenAttacks = 1.0,
		},
		{
			sequence = {
				{ type = TrashbotAttack.JUNK_WAVE,    count = 1, nextAttackWaitTime = 3.0, color = "green" },
				{ type = TrashbotAttack.JUNK_WAVE,    count = 1, nextAttackWaitTime = 3.0, color = "purple"},
				{ type = TrashbotAttack.JUNK_WAVE,    count = 1, nextAttackWaitTime = 3.0, color = "green" },
				{ type = TrashbotAttack.JUNK_WAVE,    count = 1, nextAttackWaitTime = 3.0, color = "purple"},
				{ type = TrashbotAttack.VOLLEY_BOMB,  count = 1, nextAttackWaitTime = 0.5, forceArm = TRASHBOT_ARM.left },
				{ type = TrashbotAttack.VOLLEY_BOMB,  count = 1, nextAttackWaitTime = 2.0, forceArm = TRASHBOT_ARM.right },
			},
			nextPatternIndex = { 2 },
			eyeOpen = true,
			bulletPatternName = "P1_LOOP_1",
			waitTimeBetweenAttacks = 1.0,
		},
		{
			sequence = {
				{ type = TrashbotAttack.VOLLEY_BOMB,  count = 1, nextAttackWaitTime = 0.5, forceArm = TRASHBOT_ARM.right, multiplayerOnly = true },
				{ type = TrashbotAttack.VOLLEY_BOMB,  count = 1, nextAttackWaitTime = 0.5, forceArm = TRASHBOT_ARM.left },
				{ type = TrashbotAttack.VOLLEY_BOMB,  count = 1, nextAttackWaitTime = 0.5, forceArm = TRASHBOT_ARM.left, multiplayerOnly = true },
				{ type = TrashbotAttack.VOLLEY_BOMB,  count = 1, nextAttackWaitTime = 0.5, forceArm = TRASHBOT_ARM.right },
			},
			nextPatternIndex = { 4 },
			eyeOpen = true,
			bulletPatternName = "P1_LOOP_2",
			waitTimeBetweenAttacks = 2.0
		},
		{
			sequence = {
				{ type = TrashbotAttack.JUNK_WAVE,    count = 1, nextAttackWaitTime = 2.0, color = "purple"},
				{ type = TrashbotAttack.JUNK_WAVE,    count = 1, nextAttackWaitTime = 2.0, color = "green" },
				{ type = TrashbotAttack.JUNK_WAVE,    count = 1, nextAttackWaitTime = 2.0, color = "purple"},
				{ type = TrashbotAttack.JUNK_WAVE,    count = 1, nextAttackWaitTime = 2.0, color = "green" },
				{ type = TrashbotAttack.JUNK_WAVE,    count = 1, nextAttackWaitTime = 2.0, color = "purple"},
				{ type = TrashbotAttack.JUNK_WAVE,    count = 1, nextAttackWaitTime = 2.0, color = "green" },
				{ type = TrashbotAttack.JUNK_WAVE,    count = 1, nextAttackWaitTime = 2.0, color = "purple"},
				{ type = TrashbotAttack.JUNK_WAVE,    count = 1, nextAttackWaitTime = 2.0, color = "green" },
				{ type = TrashbotAttack.JUNK_WAVE,    count = 1, nextAttackWaitTime = 1.0, color = "purple"},
			},
			nextPatternIndex = { 5 },
			eyeOpen = true,
			eyeClosedDuration = 3.0,
			eyeOpenDuration = 4.0,
			bulletPatternName = "P1_LOOP_2",
			waitTimeBetweenAttacks = 2.0
		},
		{

			sequence = {
				{ type = TrashbotAttack.SPRAY_GROUND,    count = 1, nextAttackWaitTime = 4.0, duration = 10 },
			},
			nextPatternIndex = { 6 },
			eyeOpen = true,
			bulletPatternName = "P1_LOOP_2_ROT_LEFT",
			waitTimeBetweenAttacks = 4.0,
		},
		{
			sequence = {
				{ type = TrashbotAttack.BULLET_SPRAY, count = 1, nextAttackWaitTime = 4.0, duration = 3, forceArm = TRASHBOT_ARM.left },
				{ type = TrashbotAttack.BULLET_SPRAY, count = 1, nextAttackWaitTime = 4.0, duration = 3, forceArm = TRASHBOT_ARM.right },
			},
			nextPatternIndex = { 7 },
			eyeOpen = false,
			eyeClosedDuration = 3.0,
			eyeOpenDuration = 4.0,
			bulletPatternName = "P1_LOOP_2",
			waitTimeBetweenAttacks = 0.0,
		},
		{
			sequence = {
				{ type = TrashbotAttack.VOLLEY_BOMB,  count = 1, nextAttackWaitTime = 0.5, forceArm = TRASHBOT_ARM.right, multiplayerOnly = true },
				{ type = TrashbotAttack.VOLLEY_BOMB,  count = 1, nextAttackWaitTime = 0.5, forceArm = TRASHBOT_ARM.left},
				{ type = TrashbotAttack.VOLLEY_BOMB,  count = 1, nextAttackWaitTime = 0.5, forceArm = TRASHBOT_ARM.left, multiplayerOnly = true },
				{ type = TrashbotAttack.VOLLEY_BOMB,  count = 1, nextAttackWaitTime = 0.5, forceArm = TRASHBOT_ARM.right },
			},
			nextPatternIndex = { 8 },
			eyeOpen = true,
			bulletPatternName = "P1_LOOP_2",
			waitTimeBetweenAttacks = 2.0
		},
		{
			sequence = {
				{ type = TrashbotAttack.JUNK_WAVE,    count = 1, nextAttackWaitTime = 2.0, color = "purple"},
				{ type = TrashbotAttack.JUNK_WAVE,    count = 1, nextAttackWaitTime = 2.0, color = "green" },
				{ type = TrashbotAttack.JUNK_WAVE,    count = 1, nextAttackWaitTime = 2.0, color = "purple"},
				{ type = TrashbotAttack.JUNK_WAVE,    count = 1, nextAttackWaitTime = 2.0, color = "green" },
				{ type = TrashbotAttack.JUNK_WAVE,    count = 1, nextAttackWaitTime = 2.0, color = "purple"},
				{ type = TrashbotAttack.JUNK_WAVE,    count = 1, nextAttackWaitTime = 2.0, color = "green" },
				{ type = TrashbotAttack.JUNK_WAVE,    count = 1, nextAttackWaitTime = 2.0, color = "purple"},
				{ type = TrashbotAttack.JUNK_WAVE,    count = 1, nextAttackWaitTime = 2.0, color = "green" },
				{ type = TrashbotAttack.JUNK_WAVE,    count = 1, nextAttackWaitTime = 1.0, color = "purple"},
			},
			nextPatternIndex = { 9 },
			eyeOpen = true,
			eyeClosedDuration = 3.0,
			eyeOpenDuration = 4.0,
			bulletPatternName = "P1_LOOP_2",
			waitTimeBetweenAttacks = 2.0
		},
		{

			sequence = {
				{ type = TrashbotAttack.SPRAY_GROUND,    count = 1, nextAttackWaitTime = 4.0, duration = 10 },
			},
			nextPatternIndex = { 10 },
			eyeOpen = true,
			bulletPatternName = "P1_LOOP_2_ROT_RIGHT",
			waitTimeBetweenAttacks = 4.0,
		},
		{
			sequence = {
				{ type = TrashbotAttack.BULLET_SPRAY, count = 1, nextAttackWaitTime = 4.0, duration = 3, forceArm = TRASHBOT_ARM.left },
				{ type = TrashbotAttack.BULLET_SPRAY, count = 1, nextAttackWaitTime = 4.0, duration = 3, forceArm = TRASHBOT_ARM.right },
			},
			nextPatternIndex = { 4 },
			eyeOpen = false,
			bulletPatternName = "P1_LOOP_2",
			waitTimeBetweenAttacks = 0.0,
		},
		
	},
	{
		{
			sequence = {
				{ type = TrashbotAttack.CONTINUOUS_VOLLEY, 		count = 1, nextAttackWaitTime = 1.0, duration = 6.0 },
			},
			nextPatternIndex = { 2 },
			eyeOpen = false,
			bulletPatternName = "P2_LOOP_NEW",
			waitTimeBetweenAttacks = 4.0
		},
		{
			sequence = {
				{ type = TrashbotAttack.BULLET_SPRAY, 	count = 1, nextAttackWaitTime = 4.0, duration = 2.0, forceArm = TRASHBOT_ARM.right},
				{ type = TrashbotAttack.BULLET_SPRAY, 	count = 1, nextAttackWaitTime = 2.0, duration = 2.0, forceArm = TRASHBOT_ARM.left},
				{ type = TrashbotAttack.BULLET_SPRAY, 	count = 1, nextAttackWaitTime = 4.0, duration = 2.0, forceArm = TRASHBOT_ARM.right},
				{ type = TrashbotAttack.BULLET_SPRAY, 	count = 1, nextAttackWaitTime = 2.0, duration = 2.0, forceArm = TRASHBOT_ARM.left},
			},
			nextPatternIndex = { 3 },
			eyeOpen = true,
			eyeClosedDuration = 3.0,
			eyeOpenDuration = 4.0,
			bulletPatternName = "P2_LOOP_NEW",
			waitTimeBetweenAttacks = 1.0
		},
		{
			sequence = {
				{ type = TrashbotAttack.JUNK_WAVE,    count = 1, nextAttackWaitTime = 2.5, color = "purple"},
				{ type = TrashbotAttack.JUNK_WAVE,    count = 1, nextAttackWaitTime = 2.0, color = "green" },
				{ type = TrashbotAttack.JUNK_WAVE,    count = 1, nextAttackWaitTime = 1.5, color = "purple"},
				{ type = TrashbotAttack.JUNK_WAVE,    count = 1, nextAttackWaitTime = 1.0, color = "green" },
				{ type = TrashbotAttack.JUNK_WAVE,    count = 1, nextAttackWaitTime = 0.5, color = "purple"},
			},
			nextPatternIndex = { 4 },
			eyeOpen = true,
			eyeClosedDuration = 3.0,
			eyeOpenDuration = 4.0,
			bulletPatternName = "P2_LOOP_NEW",
			waitTimeBetweenAttacks = 2.0
		},
		{
			sequence = {
				{ type = TrashbotAttack.CLEAR_PATTERN,    count = 1, nextAttackWaitTime = 1, color = "purple"},
			},
			nextPatternIndex = { 5 },
			eyeOpen = false,
			bulletPatternName = "P2_LOOP_NEW_2",
			waitTimeBetweenAttacks = 2.0
		},
		{
			sequence = {
				{ type = TrashbotAttack.SPRAY_GROUND,    count = 1, nextAttackWaitTime = 2.0, duration = 10 },
			},
			nextPatternIndex = { 1 },
			eyeOpen = true,
			bulletPatternName = "P2_LOOP_NEW_2",
			waitTimeBetweenAttacks = 3.0
		},
	},
	{
		{
			sequence = {
				{ type = TrashbotAttack.CONTINUOUS_VOLLEY, 		count = 1, nextAttackWaitTime = 1.0, duration = 10.0 },
			},
			nextPatternIndex = { 2 },
			eyeOpen = false,
			bulletPatternName = "P3_LOOP_1",
			waitTimeBetweenAttacks = 2.0,
		},
		{
			sequence = {
				{ type = TrashbotAttack.TRASH_BALL, 	count = 1, nextAttackWaitTime = 0.6, preset = "RightRot_Radius_01" },
				{ type = TrashbotAttack.TRASH_BALL, 	count = 1, nextAttackWaitTime = 0.6, preset = "LeftRot_Radius_05" },
				{ type = TrashbotAttack.TRASH_BALL, 	count = 1, nextAttackWaitTime = 0.6, preset = "LeftRot_Radius_02" },
				{ type = TrashbotAttack.TRASH_BALL, 	count = 1, nextAttackWaitTime = 0.6, preset = "RightRot_Radius_04" },
				{ type = TrashbotAttack.TRASH_BALL, 	count = 1, nextAttackWaitTime = 0.6, preset = "RightRot_Radius_03" },
				{ type = TrashbotAttack.TRASH_BALL, 	count = 1, nextAttackWaitTime = 0.6, preset = "LeftRot_Radius_03" },

			},
			nextPatternIndex = { 3 },
			eyeOpen = false,
			bulletPatternName = "P3_LOOP_1",
			waitTimeBetweenAttacks = 1.0
		},
		{
			sequence = {
				{ type = TrashbotAttack.CONTINUOUS_VOLLEY, count = 1, duration = 10.0, nextAttackWaitTime = 1.0 },
			},
			nextPatternIndex = { 4 },
			eyeOpen = true,
			eyeClosedDuration = 3.0,
			eyeOpenDuration = 4.0,
			bulletPatternName = "P3_LOOP_1",
			waitTimeBetweenAttacks = 2.0
		},
		{
			sequence = {
				{ type = TrashbotAttack.TRASH_BALL, 	count = 1, nextAttackWaitTime = 0.6, preset = "RightRot_Radius_01" },
				{ type = TrashbotAttack.TRASH_BALL, 	count = 1, nextAttackWaitTime = 0.6, preset = "LeftRot_Radius_05" },
				{ type = TrashbotAttack.TRASH_BALL, 	count = 1, nextAttackWaitTime = 0.6, preset = "LeftRot_Radius_02" },
				{ type = TrashbotAttack.TRASH_BALL, 	count = 1, nextAttackWaitTime = 0.6, preset = "RightRot_Radius_04" },
				{ type = TrashbotAttack.TRASH_BALL, 	count = 1, nextAttackWaitTime = 0.6, preset = "RightRot_Radius_03" },
				{ type = TrashbotAttack.TRASH_BALL, 	count = 1, nextAttackWaitTime = 0.6, preset = "LeftRot_Radius_03" },

			},
			nextPatternIndex = { 5 },
			eyeOpen = false,
			bulletPatternName = "P3_LOOP_1",
			waitTimeBetweenAttacks = 1.0
		},
		{
			sequence = {
				{ type = TrashbotAttack.SPRAY_GROUND,    count = 1, nextAttackWaitTime = 2.0, duration = 10 },
			},
			nextPatternIndex = { 6 },
			eyeOpen = true,
			bulletPatternName = "P3_LOOP_1",
			waitTimeBetweenAttacks = 3.0
		},
		{
			sequence = {
				{ type = TrashbotAttack.TRASH_BALL, 	count = 1, nextAttackWaitTime = 0.6, preset = "RightRot_Radius_01" },
				{ type = TrashbotAttack.TRASH_BALL, 	count = 1, nextAttackWaitTime = 0.6, preset = "LeftRot_Radius_05" },
				{ type = TrashbotAttack.TRASH_BALL, 	count = 1, nextAttackWaitTime = 0.6, preset = "LeftRot_Radius_02" },
				{ type = TrashbotAttack.TRASH_BALL, 	count = 1, nextAttackWaitTime = 0.6, preset = "RightRot_Radius_04" },
				{ type = TrashbotAttack.TRASH_BALL, 	count = 1, nextAttackWaitTime = 0.6, preset = "RightRot_Radius_03" },
				{ type = TrashbotAttack.TRASH_BALL, 	count = 1, nextAttackWaitTime = 0.6, preset = "LeftRot_Radius_03" },

			},
			nextPatternIndex = { 7 },
			eyeOpen = false,
			bulletPatternName = "P3_LOOP_1",
			waitTimeBetweenAttacks = 1.0
		},
		{
			sequence = {
				{ type = TrashbotAttack.JUNK_WAVE,    count = 1, nextAttackWaitTime = 2.0, color = "purple"},
				{ type = TrashbotAttack.JUNK_WAVE,    count = 1, nextAttackWaitTime = 2.0, color = "green" },
				{ type = TrashbotAttack.JUNK_WAVE,    count = 1, nextAttackWaitTime = 2.0, color = "purple"},
			},
			nextPatternIndex = { 8 },
			eyeOpen = true,
			bulletPatternName = "P3_LOOP_1",
			waitTimeBetweenAttacks = 2.0
		},
		{
			sequence = {
				{ type = TrashbotAttack.SPRAY_GROUND,    count = 1, nextAttackWaitTime = 2.0, duration = 10 },
			},
			nextPatternIndex = { 2 },
			eyeOpen = true,
			bulletPatternName = "P3_LOOP_1",
			waitTimeBetweenAttacks = 3.0
		},
	}
}

TRASHBOT_BULLET_HELL_SETTINGS[1] = {
	{
		["P1_LOOP_1"] = {
			{
				sequenceName = "P1_LOOP_2_PART_1",
				activationDelay = 0,
				nextPatternIndex = 2,
				useUnitRotation = false,
				systemList =
				{
					"V2_Fight1_Phase1_Start",
				}
			},
			{
				sequenceName = "P1_LOOP_2_PART_1",
				activationDelay = 0,
				nextPatternIndex = 2,
				useUnitRotation = false,
				systemList =
				{
					"V2_Fight1_Phase1_Loop1",
				}
			},
		},
		["P1_LOOP_2"] = {
			{
				sequenceName = "P1_LOOP_2_PART_1",
				activationDelay = 1,
				nextPatternIndex = 1,
				useUnitRotation = false,
				systemList =
				{
					"V2_Fight1_Phase1_loop2_04",
				}
			}
		},
		["P1_LOOP_3"] = {
			{
				sequenceName = "P1_LOOP_2_PART_1",
				activationDelay = 6,
				nextPatternIndex = 1,
				useUnitRotation = false,
				systemList =
				{
					"V2_Fight1_Phase1_loop2_04",
				}
			}
		},
		["P1_LOOP_2_ROT_LEFT"] = {
			{
				sequenceName = "P1_LOOP_2_PART_1",
				activationDelay = 1,
				nextPatternIndex = 1,
				useUnitRotation = false,
				systemList =
				{
					"V2_Fight1_Phase1_loop2_rot_left",
				}
			}
		},
		["P1_LOOP_2_ROT_RIGHT"] = {
			{
				sequenceName = "P1_LOOP_2_PART_1",
				activationDelay = 1,
				nextPatternIndex = 1,
				useUnitRotation = false,
				systemList =
				{
					"V2_Fight1_Phase1_loop2_rot_right",
				}
			}
		}
	},

	{
		["P2_LOOP_1"] = {
			{
				sequenceName = "P2_LOOP_1_START",
				activationDelay = 0.0,
				nextPatternIndex = 2,
				duration = 30.0,
				systemList =
				{
					"Fight1_Phase2_Maze1",
				}
			},
			{
				sequenceName = "P2_LOOP_1_PART_2",
				activationDelay = 9.0,
				nextPatternIndex = 3,
				duration = 30.0,
				systemList =
				{
					"Fight1_Phase2_AlternatingCircle",
				}
			},
			{
				sequenceName = "P2_LOOP_1_PART_3",
				activationDelay = 0.0,
				nextPatternIndex = 1,
				duration = 30.0,
				systemList =
				{
					"Fight1_Phase2_StaticCombined",
				}
			}
		},
		["P2_LOOP_NEW"] = {
			{
				sequenceName = "P2_LOOP_1_START",
				activationDelay = 0.0,
				nextPatternIndex = 2,
				useUnitRotation = true,
				systemList =
				{
					"fight1_wall_01",
				}
			},
			{
				sequenceName = "P2_LOOP_1_START",
				activationDelay = 0.0,
				nextPatternIndex = 1,
				useUnitRotation = true,
				systemList =
				{
					"fight1_wall_02",
				}
			}
		},
		["P2_LOOP_NEW_2"] = {
			{
				sequenceName = "P2_LOOP_1_START",
				activationDelay = 6.0,
				nextPatternIndex = 1,
				systemList =
				{
					"fight1_alternating",
				}
			}
		}
	},
	{
		["P3_LOOP_1"] = {
			{
				sequenceName = "P2_LOOP_1_START",
				activationDelay = 0.0,
				nextPatternIndex = 2,
				duration = 30.0,
				systemList =
				{
					"V2_Fight1_Phase3_Curved_loop1",
				}
			},
			{
				sequenceName = "P2_LOOP_1_PART_1",
				activationDelay = 0.0,
				nextPatternIndex = 1,
				duration = 30.0,
				systemList =
				{
					"V2_Fight1_Phase3_Curved_loop2",
				}
			},
			{
				sequenceName = "P2_LOOP_1_PART_1",
				activationDelay = 0.0,
				nextPatternIndex = 1,
				duration = 30.0,
				systemList =
				{
					"V2_Fight1_Phase3_Curved_loop3",
				}
			}
		}
	}
}