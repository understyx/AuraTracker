
SimpleAuraTrackerDB = {
	["profileKeys"] = {
		["Divinelight - Icecrown"] = "Default",
		["Stygianblade - Icecrown"] = "Default",
		["Storsvartkuk - Icecrown"] = "Default",
		["Cloudsky - Icecrown"] = "Default",
		["Stabbydude - Icecrown"] = "Default",
		["Puredecay - Icecrown"] = "Default",
		["Flexonscrub - Icecrown"] = "Default",
		["Vivification - Icecrown"] = "Default",
		["Pestering - Icecrown"] = "Default",
		["Ratform - Icecrown"] = "Default",
	},
	["profiles"] = {
		["Default"] = {
			["bars"] = {
				["Fury Warrior"] = {
					["direction"] = "HORIZONTAL",
					["point"] = "CENTER",
					["scale"] = 1.4,
					["classRestriction"] = "WARRIOR",
					["spacing"] = 2,
					["iconSize"] = 40,
					["textSize"] = 12,
					["showCooldownText"] = true,
					["enabled"] = true,
					["talentRequirements"] = {
						[67] = true,
					},
					["ignoreGCD"] = true,
					["x"] = 0,
					["name"] = "Fury Warrior",
					["showOnlyKnown"] = false,
					["trackedItems"] = {
						[58567] = {
							["onShowActions"] = {
							},
							["trackType"] = "aura",
							["exclusiveSpells"] = {
								[47467] = true,
								[55749] = true,
								[8647] = true,
							},
							["order"] = 5,
							["conditionals"] = {
							},
							["unit"] = "target",
							["displayMode"] = "always",
							["onlyMine"] = false,
							["onClickActions"] = {
							},
							["filter"] = "HARMFUL",
							["loadConditions"] = {
							},
							["onHideActions"] = {
							},
							["type"] = "target_debuff",
							["auraId"] = 58567,
						},
						[1719] = {
							["order"] = 7,
							["trackType"] = "cooldown",
							["displayMode"] = "always",
						},
						[46916] = {
							["onShowActions"] = {
							},
							["trackType"] = "aura",
							["order"] = 4,
							["conditionals"] = {
							},
							["unit"] = "player",
							["displayMode"] = "always",
							["onlyMine"] = true,
							["onClickActions"] = {
							},
							["filter"] = "HELPFUL",
							["loadConditions"] = {
							},
							["onHideActions"] = {
							},
							["type"] = "player_buff",
							["auraId"] = 46916,
						},
						[47471] = {
							["onShowActions"] = {
							},
							["displayMode"] = "always",
							["trackType"] = "cooldown",
							["loadConditions"] = {
								{
									["value"] = 20,
									["op"] = "<=",
									["check"] = "unit_hp",
									["unit"] = "target",
								}, -- [1]
							},
							["order"] = 3,
							["onHideActions"] = {
							},
							["onClickActions"] = {
							},
							["conditionals"] = {
							},
						},
						[23881] = {
							["onShowActions"] = {
							},
							["displayMode"] = "always",
							["trackType"] = "cooldown",
							["loadConditions"] = {
							},
							["order"] = 1,
							["onHideActions"] = {
							},
							["onClickActions"] = {
							},
							["conditionals"] = {
							},
						},
						[12292] = {
							["order"] = 6,
							["trackType"] = "cooldown",
							["displayMode"] = "always",
						},
						[1680] = {
							["order"] = 2,
							["trackType"] = "cooldown",
							["displayMode"] = "always",
						},
					},
					["y"] = -128,
					["loadConditions"] = {
					},
					["textColor"] = {
						["a"] = 1,
						["b"] = 1,
						["g"] = 1,
						["r"] = 1,
					},
				},
				["Holy Paladin Main Bar"] = {
					["direction"] = "HORIZONTAL",
					["point"] = "CENTER",
					["scale"] = 1.5,
					["classRestriction"] = "PALADIN",
					["spacing"] = 2,
					["iconSize"] = 40,
					["textSize"] = 20,
					["showCooldownText"] = true,
					["enabled"] = true,
					["talentRequirements"] = {
						[26] = true,
					},
					["ignoreGCD"] = true,
					["x"] = 0,
					["name"] = "[Paladin] Holy Bar",
					["loadConditions"] = {
					},
					["trackedItems"] = {
						[31884] = {
							["order"] = 4,
							["trackType"] = "cooldown",
							["displayMode"] = "always",
						},
						[53601] = {
							["onShowActions"] = {
							},
							["trackType"] = "aura",
							["order"] = 2,
							["conditionals"] = {
							},
							["unit"] = "smart_group",
							["displayMode"] = "always",
							["onlyMine"] = true,
							["onClickActions"] = {
							},
							["filter"] = "HELPFUL",
							["loadConditions"] = {
							},
							["onHideActions"] = {
							},
							["type"] = "smart_group_buff",
							["auraId"] = 53601,
						},
						[53563] = {
							["onShowActions"] = {
							},
							["trackType"] = "aura",
							["order"] = 1,
							["conditionals"] = {
							},
							["unit"] = "smart_group",
							["displayMode"] = "always",
							["onlyMine"] = true,
							["onClickActions"] = {
							},
							["filter"] = "HELPFUL",
							["loadConditions"] = {
							},
							["onHideActions"] = {
							},
							["type"] = "smart_group_buff",
							["auraId"] = 53563,
						},
						[54428] = {
							["order"] = 5,
							["trackType"] = "cooldown",
							["displayMode"] = "always",
						},
						[31842] = {
							["order"] = 3,
							["trackType"] = "cooldown",
							["displayMode"] = "always",
						},
					},
					["y"] = -128,
					["textColor"] = {
						["a"] = 1,
						["b"] = 0,
						["g"] = 1,
						["r"] = 0.9921568627450981,
					},
				},
				["[Death Knight] Buffs, Procs, Reminders"] = {
					["enabled"] = true,
					["direction"] = "HORIZONTAL",
					["point"] = "CENTER",
					["textColor"] = {
						["a"] = 1,
						["r"] = 1,
						["g"] = 1,
						["b"] = 1,
					},
					["scale"] = 1,
					["textSize"] = 12,
					["y"] = -32,
					["spacing"] = 2,
					["ignoreGCD"] = true,
					["x"] = 0,
					["name"] = "[Death Knight] Buffs, Procs, Reminders",
					["loadConditions"] = {
						{
							["check"] = "has_vehicle_ui",
							["value"] = "no",
						}, -- [1]
					},
					["iconSize"] = 40,
					["classRestriction"] = "DEATHKNIGHT",
					["trackedItems"] = {
						[59052] = {
							["auraId"] = 59052,
							["onlyMine"] = true,
							["trackType"] = "aura",
							["filter"] = "HELPFUL",
							["order"] = 3,
							["type"] = "player_buff",
							["displayMode"] = "active_only",
							["unit"] = "player",
						},
						[57623] = {
							["onShowActions"] = {
							},
							["trackType"] = "aura",
							["exclusiveSpells"] = {
								[58643] = true,
							},
							["order"] = 1,
							["auraId"] = 57623,
							["unit"] = "player",
							["type"] = "player_buff",
							["displayMode"] = "missing_only",
							["onClickActions"] = {
							},
							["filter"] = "HELPFUL",
							["loadConditions"] = {
							},
							["onHideActions"] = {
							},
							["onlyMine"] = false,
							["conditionals"] = {
							},
						},
						[45529] = {
							["auraId"] = 45529,
							["onlyMine"] = true,
							["trackType"] = "aura",
							["filter"] = "HELPFUL",
							["order"] = 4,
							["type"] = "player_buff",
							["displayMode"] = "active_only",
							["unit"] = "player",
						},
						[51124] = {
							["auraId"] = 51124,
							["onlyMine"] = true,
							["trackType"] = "aura",
							["filter"] = "HELPFUL",
							["order"] = 2,
							["type"] = "player_buff",
							["displayMode"] = "active_only",
							["unit"] = "player",
						},
						[51271] = {
							["auraId"] = 51271,
							["onlyMine"] = true,
							["trackType"] = "aura",
							["filter"] = "HELPFUL",
							["order"] = 5,
							["type"] = "player_buff",
							["displayMode"] = "active_only",
							["unit"] = "player",
						},
					},
					["showCooldownText"] = true,
				},
				["auratracker"] = {
					["direction"] = "HORIZONTAL",
					["point"] = "CENTER",
					["scale"] = 1.5,
					["classRestriction"] = "WARLOCK",
					["loadConditions"] = {
						{
							["check"] = "has_vehicle_ui",
							["value"] = "no",
						}, -- [1]
					},
					["iconSize"] = 40,
					["textSize"] = 20,
					["showCooldownText"] = true,
					["enabled"] = true,
					["talentRequirements"] = {
						[28] = true,
					},
					["showSnapshotBG"] = true,
					["showOnlyKnown"] = false,
					["snapshotTextSize"] = 18,
					["ignoreGCD"] = true,
					["x"] = 0,
					["name"] = "[Warlock] Affliction Bar",
					["font"] = "ABF",
					["y"] = -128,
					["spacing"] = 2,
					["trackedItems"] = {
						[47864] = {
							["onShowActions"] = {
							},
							["trackType"] = "aura",
							["exclusiveSpells"] = {
								[47865] = true,
								[50511] = true,
								[47867] = true,
								[11719] = true,
							},
							["order"] = 2,
							["conditionals"] = {
							},
							["unit"] = "target",
							["displayMode"] = "always",
							["onlyMine"] = true,
							["loadConditions"] = {
							},
							["filter"] = "HARMFUL",
							["type"] = "target_debuff",
							["onHideActions"] = {
							},
							["onClickActions"] = {
							},
							["auraId"] = 47864,
						},
						[59164] = {
							["onShowActions"] = {
							},
							["displayMode"] = "always",
							["onClickActions"] = {
							},
							["loadConditions"] = {
							},
							["order"] = 3,
							["onHideActions"] = {
							},
							["trackType"] = "cooldown",
							["conditionals"] = {
							},
						},
						[32391] = {
							["onShowActions"] = {
							},
							["trackType"] = "aura",
							["order"] = 5,
							["conditionals"] = {
							},
							["unit"] = "target",
							["displayMode"] = "always",
							["onlyMine"] = true,
							["loadConditions"] = {
							},
							["filter"] = "HARMFUL",
							["type"] = "target_debuff",
							["onHideActions"] = {
							},
							["onClickActions"] = {
							},
							["auraId"] = 32391,
						},
						[47813] = {
							["onShowActions"] = {
							},
							["trackType"] = "aura",
							["exclusiveSpells"] = {
								[47836] = true,
							},
							["order"] = 1,
							["showSnapshotText"] = true,
							["unit"] = "target",
							["displayMode"] = "always",
							["onlyMine"] = true,
							["filter"] = "HARMFUL",
							["loadConditions"] = {
							},
							["type"] = "target_debuff",
							["onHideActions"] = {
							},
							["onClickActions"] = {
							},
							["conditionals"] = {
							},
						},
						[47843] = {
							["onShowActions"] = {
							},
							["trackType"] = "aura",
							["order"] = 4,
							["conditionals"] = {
							},
							["unit"] = "target",
							["onlyMine"] = true,
							["displayMode"] = "always",
							["onClickActions"] = {
							},
							["filter"] = "HARMFUL",
							["loadConditions"] = {
							},
							["onHideActions"] = {
							},
							["type"] = "target_debuff",
							["auraId"] = 47843,
						},
					},
					["textColor"] = {
						["a"] = 1,
						["r"] = 0.8980392156862745,
						["g"] = 1,
						["b"] = 0,
					},
				},
				["[Warlock] Utility"] = {
					["direction"] = "HORIZONTAL",
					["point"] = "CENTER",
					["scale"] = 1,
					["classRestriction"] = "WARLOCK",
					["spacing"] = 2,
					["iconSize"] = 40,
					["textSize"] = 18,
					["showCooldownText"] = true,
					["enabled"] = true,
					["ignoreGCD"] = true,
					["x"] = 0,
					["name"] = "[Warlock] Utility",
					["showOnlyKnown"] = true,
					["y"] = -191.9999956232167,
					["trackedItems"] = {
						[36895] = {
							["onShowActions"] = {
							},
							["displayMode"] = "always",
							["trackType"] = "item",
							["loadConditions"] = {
							},
							["order"] = 3,
							["onHideActions"] = {
							},
							["onClickActions"] = {
							},
							["conditionals"] = {
							},
						},
						[48020] = {
							["onShowActions"] = {
							},
							["displayMode"] = "always",
							["trackType"] = "cooldown",
							["loadConditions"] = {
							},
							["order"] = 8,
							["onHideActions"] = {
							},
							["onClickActions"] = {
							},
							["conditionals"] = {
							},
						},
						[61290] = {
							["order"] = 6,
							["trackType"] = "cooldown",
							["displayMode"] = "always",
						},
						[1122] = {
							["order"] = 5,
							["trackType"] = "cooldown",
							["displayMode"] = "always",
						},
						[29858] = {
							["onShowActions"] = {
							},
							["displayMode"] = "always",
							["trackType"] = "cooldown",
							["loadConditions"] = {
							},
							["order"] = 4,
							["onHideActions"] = {
							},
							["onClickActions"] = {
							},
							["conditionals"] = {
							},
						},
						[47860] = {
							["order"] = 2,
							["trackType"] = "cooldown",
							["displayMode"] = "always",
						},
						[19647] = {
							["order"] = 1,
							["trackType"] = "cooldown",
							["displayMode"] = "always",
						},
						[48018] = {
							["onShowActions"] = {
							},
							["trackType"] = "aura",
							["order"] = 7,
							["auraId"] = 48018,
							["unit"] = "player",
							["type"] = "player_buff",
							["onlyMine"] = true,
							["onClickActions"] = {
							},
							["filter"] = "HELPFUL",
							["loadConditions"] = {
							},
							["onHideActions"] = {
							},
							["displayMode"] = "always",
							["conditionals"] = {
							},
						},
					},
					["loadConditions"] = {
						{
							["check"] = "has_vehicle_ui",
							["value"] = "no",
						}, -- [1]
					},
					["textColor"] = {
						["a"] = 1,
						["r"] = 0,
						["g"] = 0.9176470588235294,
						["b"] = 1,
					},
				},
				["Protection Paladin - Buffs, Reminders"] = {
					["direction"] = "HORIZONTAL",
					["point"] = "CENTER",
					["scale"] = 1,
					["classRestriction"] = "PALADIN",
					["spacing"] = 2,
					["iconSize"] = 40,
					["textSize"] = 15,
					["showCooldownText"] = true,
					["enabled"] = true,
					["talentRequirements"] = {
						[66] = true,
					},
					["ignoreGCD"] = true,
					["x"] = 0,
					["name"] = "[Paladin] Protection Reminders",
					["loadConditions"] = {
						{
							["check"] = "has_vehicle_ui",
							["value"] = "no",
						}, -- [1]
					},
					["y"] = -95.99999781160834,
					["trackedItems"] = {
						[25780] = {
							["onShowActions"] = {
								{
									["message"] = "",
									["type"] = "glow",
									["channel"] = "SAY",
									["glow"] = true,
									["glowColor"] = {
										["r"] = 1,
										["g"] = 0.07058823529411765,
										["b"] = 0,
									},
								}, -- [1]
							},
							["trackType"] = "aura",
							["order"] = 11,
							["auraId"] = 25780,
							["unit"] = "player",
							["type"] = "player_buff",
							["displayMode"] = "missing_only",
							["onClickActions"] = {
							},
							["filter"] = "HELPFUL",
							["loadConditions"] = {
							},
							["onHideActions"] = {
							},
							["onlyMine"] = true,
							["conditionals"] = {
							},
						},
						[53601] = {
							["onShowActions"] = {
							},
							["trackType"] = "aura",
							["order"] = 2,
							["auraId"] = 53601,
							["unit"] = "player",
							["type"] = "player_buff",
							["displayMode"] = "missing_only",
							["onClickActions"] = {
							},
							["filter"] = "HELPFUL",
							["loadConditions"] = {
							},
							["onHideActions"] = {
							},
							["onlyMine"] = true,
							["conditionals"] = {
							},
						},
						[71638] = {
							["onShowActions"] = {
							},
							["trackType"] = "aura",
							["order"] = 7,
							["auraId"] = 71638,
							["unit"] = "player",
							["type"] = "player_buff",
							["displayMode"] = "active_only",
							["onClickActions"] = {
							},
							["filter"] = "HELPFUL",
							["loadConditions"] = {
							},
							["onHideActions"] = {
							},
							["onlyMine"] = true,
							["conditionals"] = {
							},
						},
						[48952] = {
							["unit"] = "player",
							["onlyMine"] = true,
							["displayMode"] = "active_only",
							["filter"] = "HELPFUL",
							["order"] = 12,
							["type"] = "player_buff",
							["trackType"] = "aura",
							["auraId"] = 48952,
						},
						[54428] = {
							["onShowActions"] = {
							},
							["trackType"] = "aura",
							["order"] = 3,
							["auraId"] = 54428,
							["unit"] = "player",
							["type"] = "player_buff",
							["displayMode"] = "missing_only",
							["onClickActions"] = {
							},
							["filter"] = "HELPFUL",
							["loadConditions"] = {
							},
							["onHideActions"] = {
							},
							["onlyMine"] = true,
							["conditionals"] = {
							},
						},
						[20165] = {
							["onShowActions"] = {
							},
							["trackType"] = "aura",
							["order"] = 4,
							["auraId"] = 20165,
							["unit"] = "player",
							["type"] = "player_buff",
							["displayMode"] = "active_only",
							["onClickActions"] = {
							},
							["filter"] = "HELPFUL",
							["loadConditions"] = {
							},
							["onHideActions"] = {
							},
							["onlyMine"] = true,
							["conditionals"] = {
							},
						},
						[53762] = {
							["auraId"] = 53762,
							["onlyMine"] = true,
							["trackType"] = "aura",
							["filter"] = "HELPFUL",
							["order"] = 1,
							["type"] = "player_buff",
							["displayMode"] = "active_only",
							["unit"] = "player",
						},
						[20911] = {
							["onShowActions"] = {
								{
									["message"] = "",
									["type"] = "glow",
									["channel"] = "SAY",
									["glow"] = true,
									["glowColor"] = {
										["r"] = 1,
										["g"] = 0.1568627450980392,
										["b"] = 0,
									},
								}, -- [1]
							},
							["trackType"] = "aura",
							["exclusiveSpells"] = {
								[25899] = true,
								[63944] = true,
							},
							["order"] = 13,
							["auraId"] = 20911,
							["unit"] = "player",
							["type"] = "player_buff",
							["displayMode"] = "missing_only",
							["onClickActions"] = {
							},
							["filter"] = "HELPFUL",
							["loadConditions"] = {
							},
							["onHideActions"] = {
							},
							["onlyMine"] = true,
							["conditionals"] = {
							},
						},
						[20375] = {
							["onShowActions"] = {
							},
							["trackType"] = "aura",
							["order"] = 6,
							["auraId"] = 20375,
							["unit"] = "player",
							["type"] = "player_buff",
							["displayMode"] = "active_only",
							["onClickActions"] = {
							},
							["filter"] = "HELPFUL",
							["loadConditions"] = {
							},
							["onHideActions"] = {
							},
							["onlyMine"] = true,
							["conditionals"] = {
							},
						},
						[498] = {
							["onShowActions"] = {
							},
							["trackType"] = "aura",
							["order"] = 8,
							["auraId"] = 498,
							["unit"] = "player",
							["type"] = "player_buff",
							["onlyMine"] = true,
							["onClickActions"] = {
							},
							["filter"] = "HELPFUL",
							["loadConditions"] = {
							},
							["onHideActions"] = {
							},
							["displayMode"] = "active_only",
							["conditionals"] = {
							},
						},
						[53736] = {
							["auraId"] = 53736,
							["onlyMine"] = true,
							["trackType"] = "aura",
							["filter"] = "HELPFUL",
							["order"] = 5,
							["type"] = "player_buff",
							["displayMode"] = "active_only",
							["unit"] = "player",
						},
						[1038] = {
							["onShowActions"] = {
							},
							["trackType"] = "aura",
							["order"] = 9,
							["auraId"] = 1038,
							["unit"] = "player",
							["type"] = "player_buff",
							["onlyMine"] = true,
							["onClickActions"] = {
							},
							["filter"] = "HELPFUL",
							["loadConditions"] = {
							},
							["onHideActions"] = {
							},
							["displayMode"] = "active_only",
							["conditionals"] = {
							},
						},
						[20166] = {
							["onShowActions"] = {
							},
							["trackType"] = "aura",
							["order"] = 10,
							["auraId"] = 20166,
							["unit"] = "player",
							["type"] = "player_buff",
							["displayMode"] = "active_only",
							["onClickActions"] = {
							},
							["filter"] = "HELPFUL",
							["loadConditions"] = {
							},
							["onHideActions"] = {
							},
							["onlyMine"] = true,
							["conditionals"] = {
							},
						},
						[70940] = {
							["auraId"] = 70940,
							["onlyMine"] = true,
							["trackType"] = "aura",
							["filter"] = "HELPFUL",
							["order"] = 14,
							["type"] = "player_buff",
							["displayMode"] = "active_only",
							["unit"] = "player",
						},
					},
					["textColor"] = {
						["a"] = 1,
						["r"] = 0,
						["g"] = 1,
						["b"] = 0.9803921568627451,
					},
				},
				["Missing Buffs"] = {
					["enabled"] = true,
					["direction"] = "HORIZONTAL",
					["point"] = "TOP",
					["scale"] = 1,
					["showCooldownText"] = true,
					["trackedItems"] = {
						[2895] = {
							["onShowActions"] = {
							},
							["trackType"] = "aura",
							["order"] = 11,
							["conditionals"] = {
							},
							["unit"] = "player",
							["onlyMine"] = false,
							["displayMode"] = "missing_only",
							["onClickActions"] = {
								{
									["message"] = "I'm missing %spelllink",
									["type"] = "chat",
									["glow"] = false,
									["channel"] = "SMART",
								}, -- [1]
							},
							["filter"] = "HELPFUL",
							["loadConditions"] = {
							},
							["onHideActions"] = {
							},
							["type"] = "player_buff",
							["auraId"] = 2895,
						},
						[48074] = {
							["onShowActions"] = {
							},
							["trackType"] = "aura",
							["exclusiveSpells"] = {
								[57567] = true,
								[14752] = true,
							},
							["order"] = 8,
							["conditionals"] = {
							},
							["unit"] = "player",
							["displayMode"] = "missing_only",
							["onlyMine"] = false,
							["onClickActions"] = {
								{
									["message"] = "I'm missing %spelllink",
									["type"] = "chat",
									["glow"] = false,
									["channel"] = "SMART",
								}, -- [1]
							},
							["filter"] = "HELPFUL",
							["loadConditions"] = {
							},
							["onHideActions"] = {
							},
							["type"] = "player_buff",
							["auraId"] = 48074,
						},
						[58754] = {
							["onShowActions"] = {
							},
							["trackType"] = "aura",
							["order"] = 10,
							["conditionals"] = {
							},
							["unit"] = "player",
							["onlyMine"] = false,
							["displayMode"] = "missing_only",
							["onClickActions"] = {
								{
									["message"] = "I'm missing %spelllink",
									["type"] = "chat",
									["glow"] = false,
									["channel"] = "SMART",
								}, -- [1]
							},
							["filter"] = "HELPFUL",
							["loadConditions"] = {
							},
							["onHideActions"] = {
							},
							["type"] = "player_buff",
							["auraId"] = 58754,
						},
						[48938] = {
							["onShowActions"] = {
							},
							["trackType"] = "aura",
							["exclusiveSpells"] = {
								[58774] = true,
								[48936] = true,
							},
							["order"] = 3,
							["conditionals"] = {
							},
							["unit"] = "player",
							["onlyMine"] = false,
							["displayMode"] = "missing_only",
							["onClickActions"] = {
								{
									["message"] = "I'm missing %spelllink",
									["type"] = "chat",
									["glow"] = false,
									["channel"] = "SMART",
								}, -- [1]
							},
							["filter"] = "HELPFUL",
							["loadConditions"] = {
							},
							["onHideActions"] = {
							},
							["type"] = "player_buff",
							["auraId"] = 48938,
						},
						[48170] = {
							["onShowActions"] = {
							},
							["trackType"] = "aura",
							["order"] = 6,
							["conditionals"] = {
							},
							["unit"] = "player",
							["displayMode"] = "missing_only",
							["onlyMine"] = false,
							["onClickActions"] = {
								{
									["message"] = "I'm missing %spelllink",
									["type"] = "chat",
									["glow"] = false,
									["channel"] = "SMART",
								}, -- [1]
							},
							["filter"] = "HELPFUL",
							["loadConditions"] = {
							},
							["onHideActions"] = {
							},
							["type"] = "player_buff",
							["auraId"] = 48170,
						},
						[25898] = {
							["onShowActions"] = {
							},
							["type"] = "player_buff",
							["exclusiveSpells"] = {
								[25898] = true,
								[20217] = true,
								[69378] = true,
							},
							["order"] = 1,
							["conditionals"] = {
							},
							["unit"] = "player",
							["trackType"] = "aura",
							["onlyMine"] = false,
							["onClickActions"] = {
								{
									["message"] = "I'm missing %spelllink",
									["type"] = "chat",
									["glow"] = false,
									["channel"] = "SMART",
								}, -- [1]
							},
							["filter"] = "HELPFUL",
							["loadConditions"] = {
							},
							["onHideActions"] = {
							},
							["displayMode"] = "missing_only",
							["auraId"] = 25898,
						},
						[43002] = {
							["onShowActions"] = {
							},
							["trackType"] = "aura",
							["exclusiveSpells"] = {
								[27127] = true,
								[57567] = true,
								[42995] = true,
								[61316] = true,
							},
							["order"] = 14,
							["conditionals"] = {
							},
							["unit"] = "player",
							["displayMode"] = "missing_only",
							["onlyMine"] = false,
							["onClickActions"] = {
								{
									["message"] = "I'm missing %spelllink",
									["type"] = "chat",
									["glow"] = false,
									["channel"] = "SMART",
								}, -- [1]
							},
							["filter"] = "HELPFUL",
							["loadConditions"] = {
							},
							["onHideActions"] = {
							},
							["type"] = "player_buff",
							["auraId"] = 43002,
						},
						[47440] = {
							["onShowActions"] = {
							},
							["trackType"] = "aura",
							["exclusiveSpells"] = {
								[47982] = true,
								[47440] = true,
							},
							["order"] = 5,
							["auraId"] = 47440,
							["unit"] = "player",
							["type"] = "player_buff",
							["displayMode"] = "missing_only",
							["onClickActions"] = {
								{
									["message"] = "I'm missing %spelllink",
									["type"] = "chat",
									["glow"] = false,
									["channel"] = "SMART",
								}, -- [1]
							},
							["filter"] = "HELPFUL",
							["loadConditions"] = {
							},
							["onHideActions"] = {
							},
							["onlyMine"] = false,
							["conditionals"] = {
							},
						},
						[48470] = {
							["onShowActions"] = {
							},
							["trackType"] = "aura",
							["exclusiveSpells"] = {
								[48469] = true,
								[69381] = true,
							},
							["order"] = 12,
							["auraId"] = 48470,
							["unit"] = "player",
							["type"] = "player_buff",
							["displayMode"] = "missing_only",
							["onClickActions"] = {
								{
									["message"] = "I'm missing %spelllink",
									["type"] = "chat",
									["glow"] = false,
									["channel"] = "SMART",
								}, -- [1]
							},
							["filter"] = "HELPFUL",
							["loadConditions"] = {
							},
							["onHideActions"] = {
							},
							["onlyMine"] = false,
							["conditionals"] = {
							},
						},
						[25899] = {
							["onShowActions"] = {
							},
							["trackType"] = "aura",
							["exclusiveSpells"] = {
							},
							["order"] = 2,
							["auraId"] = 25899,
							["unit"] = "player",
							["type"] = "player_buff",
							["onlyMine"] = false,
							["onClickActions"] = {
								{
									["message"] = "I'm missing %spelllink",
									["type"] = "chat",
									["glow"] = false,
									["channel"] = "SMART",
								}, -- [1]
							},
							["filter"] = "HELPFUL",
							["loadConditions"] = {
							},
							["onHideActions"] = {
							},
							["displayMode"] = "missing_only",
							["conditionals"] = {
							},
						},
						[48934] = {
							["onShowActions"] = {
							},
							["trackType"] = "aura",
							["exclusiveSpells"] = {
								[48934] = true,
								[47436] = true,
							},
							["order"] = 4,
							["conditionals"] = {
							},
							["unit"] = "player",
							["onlyMine"] = false,
							["displayMode"] = "missing_only",
							["onClickActions"] = {
								{
									["message"] = "I'm missing %spelllink",
									["type"] = "chat",
									["glow"] = false,
									["channel"] = "SMART",
								}, -- [1]
							},
							["filter"] = "HELPFUL",
							["loadConditions"] = {
							},
							["onHideActions"] = {
							},
							["type"] = "player_buff",
							["auraId"] = 48934,
						},
						[48162] = {
							["onShowActions"] = {
							},
							["trackType"] = "aura",
							["exclusiveSpells"] = {
								[69377] = true,
								[48161] = true,
							},
							["order"] = 7,
							["conditionals"] = {
							},
							["unit"] = "player",
							["displayMode"] = "missing_only",
							["onlyMine"] = false,
							["onClickActions"] = {
								{
									["message"] = "I'm missing %spelllink",
									["type"] = "chat",
									["glow"] = false,
									["channel"] = "SMART",
								}, -- [1]
							},
							["filter"] = "HELPFUL",
							["loadConditions"] = {
							},
							["onHideActions"] = {
							},
							["type"] = "player_buff",
							["auraId"] = 48162,
						},
						[55610] = {
							["onShowActions"] = {
							},
							["trackType"] = "aura",
							["exclusiveSpells"] = {
								[8512] = true,
							},
							["order"] = 13,
							["auraId"] = 55610,
							["unit"] = "player",
							["type"] = "player_buff",
							["onlyMine"] = false,
							["onClickActions"] = {
								{
									["message"] = "I'm missing %spelllink",
									["type"] = "chat",
									["glow"] = false,
									["channel"] = "SMART",
								}, -- [1]
							},
							["filter"] = "HELPFUL",
							["loadConditions"] = {
							},
							["onHideActions"] = {
							},
							["displayMode"] = "missing_only",
							["conditionals"] = {
							},
						},
						[57623] = {
							["onShowActions"] = {
							},
							["trackType"] = "aura",
							["exclusiveSpells"] = {
								[58643] = true,
							},
							["order"] = 9,
							["auraId"] = 57623,
							["unit"] = "player",
							["type"] = "player_buff",
							["onlyMine"] = false,
							["onClickActions"] = {
								{
									["message"] = "I'm missing %spelllink",
									["type"] = "chat",
									["glow"] = false,
									["channel"] = "SMART",
								}, -- [1]
							},
							["filter"] = "HELPFUL",
							["loadConditions"] = {
							},
							["onHideActions"] = {
							},
							["displayMode"] = "missing_only",
							["conditionals"] = {
							},
						},
					},
					["loadConditions"] = {
					},
					["y"] = -32,
					["x"] = 32,
					["name"] = "[General] Clickable missing buffs",
					["spacing"] = 2,
					["iconSize"] = 40,
					["ignoreGCD"] = true,
					["textSize"] = 12,
					["textColor"] = {
						["a"] = 1,
						["b"] = 1,
						["g"] = 1,
						["r"] = 1,
					},
				},
				["[Warlock] Procs & Reminders"] = {
					["direction"] = "HORIZONTAL",
					["point"] = "CENTER",
					["scale"] = 1,
					["classRestriction"] = "WARLOCK",
					["loadConditions"] = {
						{
							["check"] = "has_vehicle_ui",
							["value"] = "no",
						}, -- [1]
					},
					["iconSize"] = 40,
					["trackedItems"] = {
						[47893] = {
							["onShowActions"] = {
							},
							["trackType"] = "aura",
							["exclusiveSpells"] = {
								[48074] = true,
							},
							["order"] = 1,
							["conditionals"] = {
							},
							["unit"] = "player",
							["onlyMine"] = true,
							["displayMode"] = "missing_only",
							["onClickActions"] = {
							},
							["filter"] = "HELPFUL",
							["loadConditions"] = {
							},
							["onHideActions"] = {
							},
							["type"] = "player_buff",
							["auraId"] = 47893,
						},
						[64371] = {
							["onShowActions"] = {
							},
							["type"] = "player_buff",
							["order"] = 6,
							["auraId"] = 64371,
							["unit"] = "player",
							["onlyMine"] = true,
							["displayMode"] = "active_only",
							["onClickActions"] = {
							},
							["filter"] = "HELPFUL",
							["loadConditions"] = {
							},
							["onHideActions"] = {
							},
							["trackType"] = "aura",
							["conditionals"] = {
							},
						},
						[50589] = {
							["onShowActions"] = {
								{
									["message"] = "",
									["glow"] = true,
									["channel"] = "SAY",
									["glowColor"] = {
										["b"] = 1,
										["g"] = 0,
										["r"] = 0.7490196078431373,
									},
									["type"] = "glow",
								}, -- [1]
							},
							["displayMode"] = "active_only",
							["trackType"] = "cooldown",
							["loadConditions"] = {
								{
									["value"] = "have_aura",
									["check"] = "aura",
									["spellId"] = 47241,
									["unit"] = "player",
								}, -- [1]
							},
							["order"] = 10,
							["onHideActions"] = {
							},
							["onClickActions"] = {
							},
							["conditionals"] = {
							},
						},
						[63167] = {
							["onShowActions"] = {
							},
							["type"] = "player_buff",
							["order"] = 8,
							["auraId"] = 63167,
							["unit"] = "player",
							["onlyMine"] = true,
							["displayMode"] = "active_only",
							["onClickActions"] = {
							},
							["filter"] = "HELPFUL",
							["loadConditions"] = {
							},
							["onHideActions"] = {
							},
							["trackType"] = "aura",
							["conditionals"] = {
							},
						},
						[71165] = {
							["onShowActions"] = {
							},
							["type"] = "player_buff",
							["order"] = 7,
							["auraId"] = 71165,
							["unit"] = "player",
							["onlyMine"] = true,
							["displayMode"] = "active_only",
							["onClickActions"] = {
							},
							["filter"] = "HELPFUL",
							["loadConditions"] = {
							},
							["onHideActions"] = {
							},
							["trackType"] = "aura",
							["conditionals"] = {
							},
						},
						[-1] = {
							["onShowActions"] = {
							},
							["trackType"] = "weapon_enchant",
							["slot"] = "mainhand",
							["order"] = 3,
							["onClickActions"] = {
							},
							["loadConditions"] = {
							},
							["displayMode"] = "missing_only",
							["onHideActions"] = {
							},
							["expectedEnchant"] = "spellstone",
							["conditionals"] = {
							},
						},
						[25228] = {
							["onShowActions"] = {
							},
							["trackType"] = "aura",
							["order"] = 9,
							["conditionals"] = {
							},
							["unit"] = "player",
							["onlyMine"] = true,
							["displayMode"] = "missing_only",
							["onClickActions"] = {
							},
							["filter"] = "HELPFUL",
							["loadConditions"] = {
								{
									["value"] = "yes",
									["talentState"] = true,
									["check"] = "talent",
									["talentKey"] = 49,
								}, -- [1]
								{
									["check"] = "mounted",
									["value"] = "no",
								}, -- [2]
							},
							["onHideActions"] = {
							},
							["type"] = "player_buff",
							["auraId"] = 25228,
						},
						[17941] = {
							["onShowActions"] = {
							},
							["type"] = "player_buff",
							["order"] = 5,
							["auraId"] = 17941,
							["unit"] = "player",
							["onlyMine"] = true,
							["displayMode"] = "active_only",
							["onClickActions"] = {
							},
							["filter"] = "HELPFUL",
							["loadConditions"] = {
							},
							["onHideActions"] = {
							},
							["trackType"] = "aura",
							["conditionals"] = {
							},
						},
						[70840] = {
							["onShowActions"] = {
							},
							["type"] = "player_buff",
							["order"] = 4,
							["auraId"] = 70840,
							["unit"] = "player",
							["onlyMine"] = true,
							["displayMode"] = "active_only",
							["onClickActions"] = {
							},
							["filter"] = "HELPFUL",
							["loadConditions"] = {
							},
							["onHideActions"] = {
							},
							["trackType"] = "aura",
							["conditionals"] = {
							},
						},
						[63321] = {
							["onShowActions"] = {
							},
							["type"] = "player_buff",
							["order"] = 2,
							["auraId"] = 63321,
							["unit"] = "player",
							["displayMode"] = "missing_only",
							["onlyMine"] = true,
							["onClickActions"] = {
							},
							["filter"] = "HELPFUL",
							["loadConditions"] = {
							},
							["onHideActions"] = {
							},
							["trackType"] = "aura",
							["conditionals"] = {
							},
						},
					},
					["showCooldownText"] = true,
					["enabled"] = true,
					["ignoreGCD"] = true,
					["x"] = 0,
					["name"] = "[Warlock] Procs & Reminders",
					["showOnlyKnown"] = false,
					["spacing"] = 2,
					["textSize"] = 18,
					["y"] = -64,
					["textColor"] = {
						["a"] = 1,
						["r"] = 0,
						["g"] = 0.9137254901960784,
						["b"] = 1,
					},
				},
				["Protection Paladin"] = {
					["direction"] = "HORIZONTAL",
					["point"] = "CENTER",
					["scale"] = 1.3,
					["classRestriction"] = "PALADIN",
					["spacing"] = 2,
					["iconSize"] = 40,
					["textSize"] = 31,
					["showCooldownText"] = true,
					["enabled"] = true,
					["talentRequirements"] = {
						[66] = true,
					},
					["ignoreGCD"] = true,
					["x"] = 1.422139452386445,
					["name"] = "[Paladin] Protection Bar",
					["fontOutline"] = "THICKOUTLINE",
					["y"] = -144.3554703055426,
					["trackedItems"] = {
						[20271] = {
							["onShowActions"] = {
							},
							["displayMode"] = "always",
							["trackType"] = "cooldown",
							["loadConditions"] = {
							},
							["order"] = 4,
							["onHideActions"] = {
							},
							["onClickActions"] = {
							},
							["conditionals"] = {
							},
						},
						[61411] = {
							["order"] = 3,
							["trackType"] = "cooldown",
							["displayMode"] = "always",
						},
						[48819] = {
							["onShowActions"] = {
							},
							["displayMode"] = "always",
							["trackType"] = "cooldown",
							["loadConditions"] = {
							},
							["order"] = 5,
							["onHideActions"] = {
							},
							["onClickActions"] = {
							},
							["conditionals"] = {
							},
						},
						[53595] = {
							["order"] = 1,
							["trackType"] = "cooldown",
							["displayMode"] = "always",
						},
						[48952] = {
							["order"] = 2,
							["trackType"] = "cooldown",
							["displayMode"] = "always",
						},
					},
					["loadConditions"] = {
						{
							["check"] = "has_vehicle_ui",
							["value"] = "no",
						}, -- [1]
					},
					["textColor"] = {
						["a"] = 1,
						["r"] = 0.7372549019607844,
						["g"] = 1,
						["b"] = 0.2117647058823529,
					},
				},
				["WarlockAfflictionBar"] = {
					["direction"] = "HORIZONTAL",
					["point"] = "CENTER",
					["scale"] = 1.5,
					["classRestriction"] = "WARLOCK",
					["spacing"] = 2,
					["iconSize"] = 40,
					["textSize"] = 20,
					["showCooldownText"] = true,
					["enabled"] = true,
					["talentRequirements"] = {
						[67] = true,
					},
					["ignoreGCD"] = true,
					["x"] = 0,
					["name"] = "[Warlock] Demonology Bar",
					["loadConditions"] = {
						{
							["check"] = "has_vehicle_ui",
							["value"] = "no",
						}, -- [1]
					},
					["trackedItems"] = {
						[47241] = {
							["onShowActions"] = {
							},
							["displayMode"] = "always",
							["trackType"] = "cooldown",
							["loadConditions"] = {
							},
							["order"] = 1,
							["onHideActions"] = {
							},
							["onClickActions"] = {
							},
							["conditionals"] = {
							},
						},
						[63321] = {
							["onShowActions"] = {
							},
							["trackType"] = "aura",
							["order"] = 5,
							["auraId"] = 63321,
							["unit"] = "player",
							["type"] = "player_buff",
							["displayMode"] = "active_only",
							["onClickActions"] = {
							},
							["filter"] = "HELPFUL",
							["loadConditions"] = {
							},
							["onHideActions"] = {
							},
							["onlyMine"] = true,
							["conditionals"] = {
							},
						},
						[47811] = {
							["onShowActions"] = {
							},
							["type"] = "target_debuff",
							["order"] = 3,
							["auraId"] = 47811,
							["unit"] = "target",
							["onlyMine"] = true,
							["displayMode"] = "always",
							["onClickActions"] = {
							},
							["filter"] = "HARMFUL",
							["loadConditions"] = {
							},
							["onHideActions"] = {
							},
							["trackType"] = "aura",
							["conditionals"] = {
							},
						},
						[47813] = {
							["onShowActions"] = {
							},
							["trackType"] = "aura",
							["exclusiveSpells"] = {
								[47836] = true,
							},
							["order"] = 2,
							["showSnapshotText"] = false,
							["unit"] = "target",
							["onlyMine"] = true,
							["displayMode"] = "always",
							["onClickActions"] = {
							},
							["filter"] = "HARMFUL",
							["type"] = "target_debuff",
							["onHideActions"] = {
							},
							["loadConditions"] = {
							},
							["conditionals"] = {
							},
						},
						[47867] = {
							["onShowActions"] = {
							},
							["trackType"] = "aura",
							["exclusiveSpells"] = {
								[47865] = true,
								[50511] = true,
								[47864] = true,
								[11719] = true,
							},
							["order"] = 4,
							["auraId"] = 47867,
							["unit"] = "target",
							["type"] = "target_debuff",
							["onlyMine"] = true,
							["onClickActions"] = {
							},
							["filter"] = "HARMFUL",
							["loadConditions"] = {
							},
							["onHideActions"] = {
							},
							["displayMode"] = "always",
							["conditionals"] = {
							},
						},
					},
					["y"] = -127.9999737393001,
					["textColor"] = {
						["a"] = 1,
						["b"] = 0,
						["g"] = 1,
						["r"] = 0.9450980392156863,
					},
				},
				["[Death Knight] Frost DPS"] = {
					["direction"] = "HORIZONTAL",
					["point"] = "CENTER",
					["scale"] = 1.5,
					["classRestriction"] = "DEATHKNIGHT",
					["spacing"] = 2,
					["iconSize"] = 40,
					["textSize"] = 12,
					["showCooldownText"] = true,
					["enabled"] = true,
					["talentRequirements"] = {
						[69] = true,
					},
					["ignoreGCD"] = true,
					["x"] = 0,
					["name"] = "[Death Knight] Frost DPS Bar",
					["loadConditions"] = {
						{
							["check"] = "has_vehicle_ui",
							["value"] = "no",
						}, -- [1]
					},
					["y"] = -127.9999737393001,
					["trackedItems"] = {
						[59921] = {
							["auraId"] = 59921,
							["onlyMine"] = true,
							["trackType"] = "aura",
							["filter"] = "HARMFUL",
							["order"] = 1,
							["type"] = "target_debuff",
							["displayMode"] = "always",
							["unit"] = "target",
						},
						[51271] = {
							["order"] = 4,
							["trackType"] = "cooldown",
							["displayMode"] = "always",
						},
						[59879] = {
							["auraId"] = 59879,
							["onlyMine"] = true,
							["trackType"] = "aura",
							["filter"] = "HARMFUL",
							["order"] = 2,
							["type"] = "target_debuff",
							["displayMode"] = "always",
							["unit"] = "target",
						},
						[47568] = {
							["order"] = 5,
							["trackType"] = "cooldown",
							["displayMode"] = "always",
						},
						[51411] = {
							["onShowActions"] = {
							},
							["displayMode"] = "always",
							["trackType"] = "cooldown",
							["loadConditions"] = {
							},
							["order"] = 3,
							["onHideActions"] = {
							},
							["onClickActions"] = {
							},
							["conditionals"] = {
							},
						},
					},
					["textColor"] = {
						["a"] = 1,
						["r"] = 1,
						["g"] = 1,
						["b"] = 1,
					},
				},
			},
		},
	},
}
