{
    ["actions"] = {
        ["finish"] = {
        },
        ["init"] = {
            ["custom"] = "\\n\\n",
            ["do_custom"] = false,
        },
        ["start"] = {
        },
    },
    ["adjustedMax"] = "",
    ["adjustedMin"] = "",
    ["alpha"] = 1,
    ["anchorFrameType"] = "SCREEN",
    ["anchorPoint"] = "CENTER",
    ["animation"] = {
        ["finish"] = {
            ["duration_type"] = "seconds",
            ["easeStrength"] = 3,
            ["easeType"] = "none",
            ["type"] = "none",
        },
        ["main"] = {
            ["duration_type"] = "seconds",
            ["easeStrength"] = 3,
            ["easeType"] = "none",
            ["type"] = "none",
        },
        ["start"] = {
            ["duration_type"] = "seconds",
            ["easeStrength"] = 3,
            ["easeType"] = "none",
            ["type"] = "none",
        },
    },
    ["authorOptions"] = {
    },
    ["color"] = {
        [1] = 1,
        [2] = 1,
        [3] = 1,
        [4] = 1,
    },
    ["conditions"] = {
        [1] = {
            ["changes"] = {
                [1] = {
                    ["property"] = "desaturate",
                    ["value"] = true,
                },
            },
            ["check"] = {
                ["trigger"] = 1,
                ["value"] = 0,
                ["variable"] = "buffed",
            },
        },
    },
    ["config"] = {
    },
    ["cooldown"] = false,
    ["cooldownEdge"] = false,
    ["customText"] = "function()\\n  local x1,x2,x3 = aura_env.GetPercent()\\n  print(x1, x2, x3)\\n  return tostring(x1 - x2)\\nend",
    ["customTextUpdate"] = "update",
    ["customTextUpdateThrottle"] = 0.1,
    ["desaturate"] = false,
    ["displayIcon"] = "Interface\\\\Icons\\\\Spell_Shadow_AbominationExplosion",
    ["frameStrata"] = 1,
    ["height"] = 48,
    ["icon"] = true,
    ["iconSource"] = -1,
    ["id"] = "{Edgy] Warlock - Corruption",
    ["information"] = {
    },
    ["internalVersion"] = 89,
    ["inverse"] = false,
    ["keepAspectRatio"] = false,
    ["load"] = {
        ["class"] = {
            ["multi"] = {
                ["PALADIN"] = true,
                ["PRIEST"] = true,
                ["SHAMAN"] = true,
            },
            ["single"] = "WARLOCK",
        },
        ["class_and_spec"] = {
            ["multi"] = {
            },
            ["single"] = 263,
        },
        ["size"] = {
            ["multi"] = {
            },
        },
        ["spec"] = {
            ["multi"] = {
            },
        },
        ["talent"] = {
            ["multi"] = {
            },
        },
        ["use_class"] = true,
    },
    ["parent"] = "[Edgy] Warlock - Core",
    ["progressSource"] = {
        [1] = -1,
        [2] = "",
    },
    ["regionType"] = "icon",
    ["selfPoint"] = "CENTER",
    ["subRegions"] = {
        [1] = {
            ["type"] = "subbackground",
        },
        [2] = {
            ["anchorXOffset"] = 0,
            ["anchorYOffset"] = 0,
            ["anchor_point"] = "CENTER",
            ["text_automaticWidth"] = "Auto",
            ["text_color"] = {
                [1] = 0.94901960784314,
                [2] = 1,
                [3] = 0,
                [4] = 1,
            },
            ["text_fixedWidth"] = 64,
            ["text_font"] = "Accidental Presidency",
            ["text_fontSize"] = 24,
            ["text_fontType"] = "OUTLINE",
            ["text_justify"] = "CENTER",
            ["text_selfPoint"] = "CENTER",
            ["text_shadowColor"] = {
                [1] = 0,
                [2] = 0,
                [3] = 0,
                [4] = 1,
            },
            ["text_shadowXOffset"] = 0,
            ["text_shadowYOffset"] = 0,
            ["text_text"] = "%p",
            ["text_text_format_p_format"] = "timed",
            ["text_text_format_p_time_dynamic_threshold"] = 3,
            ["text_text_format_p_time_format"] = 0,
            ["text_text_format_p_time_legacy_floor"] = false,
            ["text_text_format_p_time_precision"] = 1,
            ["text_text_format_s_format"] = "none",
            ["text_visible"] = true,
            ["text_wordWrap"] = "WordWrap",
            ["type"] = "subtext",
        },
        [3] = {
            ["border_color"] = {
                [1] = 0,
                [2] = 0,
                [3] = 0,
                [4] = 1,
            },
            ["border_edge"] = "Square Full White",
            ["border_offset"] = 0,
            ["border_size"] = 3,
            ["border_visible"] = true,
            ["type"] = "subborder",
        },
    },
    ["triggers"] = {
        [1] = {
            ["trigger"] = {
                ["auraspellids"] = {
                    [1] = "47813",
                },
                ["debuffType"] = "HARMFUL",
                ["event"] = "Cooldown Progress (Spell)",
                ["genericShowOn"] = "showAlways",
                ["matchesShowOn"] = "showAlways",
                ["names"] = {
                },
                ["ownOnly"] = true,
                ["spellIds"] = {
                },
                ["spellName"] = 17364,
                ["subeventPrefix"] = "SPELL",
                ["subeventSuffix"] = "_CAST_START",
                ["type"] = "aura2",
                ["unit"] = "target",
                ["useExactSpellId"] = true,
                ["use_exact_spellName"] = true,
                ["use_genericShowOn"] = true,
                ["use_spellName"] = true,
                ["use_track"] = true,
            },
            ["untrigger"] = {
            },
        },
        [2] = {
            ["trigger"] = {
                ["debuffType"] = "HELPFUL",
                ["event"] = "Conditions",
                ["type"] = "unit",
                ["unit"] = "player",
                ["use_alwaystrue"] = true,
                ["use_unit"] = true,
            },
            ["untrigger"] = {
            },
        },
        ["activeTriggerMode"] = -10,
        ["disjunctive"] = "any",
    },
    ["uid"] = "8qAEUe0mNg0",
    ["useAdjustededMax"] = false,
    ["useAdjustededMin"] = false,
    ["width"] = 48,
    ["xOffset"] = 0,
    ["yOffset"] = 0,
    ["zoom"] = 0.3,
}