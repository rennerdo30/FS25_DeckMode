-- FS25_DeckMode (Deck Mode)
-- Makes Farming Simulator 25 comfortable on handheld PCs such as the Steam Deck.
--
-- 1) Big menu text: scales the text of all menu / map / dialog / tooltip / button-bar GUI elements.
--    The HUD is not touched (the game's own "UI Scale" setting covers it).
--     * Hooks TextElement.loadProfile / loadFromXML / copyAttributes so every text size is derived
--       from its source value (profile or XML) times the factor; re-applying a profile never
--       scales twice.
--     * Walks every GUI element that already exists when the mod loads (screens, frames, dialogs,
--       unlinked list templates) and scales it once; a flag prevents double scaling.
--     * textMinSize stays unscaled, so the game's shrink-to-fit logic can still fit long texts.
--
-- 2) Graphics preset: target FPS (30 / 60) x style (Power Saver / Balanced / High Quality), applied
--    once (first savegame load) and saved like the settings menu does; later changes in the
--    settings menu stick.
--
-- 3) Controller mode: turns gamepad input on and sets the button help to always show controller
--    buttons, once (first savegame load).
--
-- 4) A "DECK MODE" section at the top of the in-game Settings page (General tab) to change the text
--    size live, (re)apply the graphics preset and switch controller mode.
--
-- Settings: <modSettings>/FS25_DeckMode.xml
--   <deckMode scale="1.5" targetFps="30" graphicsStyle="balanced" graphicsPresetApplied="false"
--             controllerMode="true" controllerModeApplied="false"/>
--   scale: 1.0 - 2.0 | targetFps: off, 30 or 60 | graphicsStyle: powersaver, balanced or quality
--   set graphicsPresetApplied="false" to apply the preset again on the next savegame load

DeckMode = {}
DeckMode.MOD_NAME = g_currentModName
DeckMode.MOD_DIR = g_currentModDirectory
DeckMode.DEFAULT_SCALE = 1.5
DeckMode.MIN_SCALE = 1.0
DeckMode.MAX_SCALE = 2.0
DeckMode.SETTINGS_FILE = "FS25_DeckMode.xml"
DeckMode.FLAG = "deckModeScaled"
DeckMode.DEBUG = false -- true: dump the settings page structure to log.txt on savegame load

DeckMode.scale = DeckMode.DEFAULT_SCALE
DeckMode.graphicsFps = "30"            -- "off", "30" or "60"
DeckMode.graphicsStyle = "balanced"    -- "powersaver", "balanced" or "quality"
DeckMode.graphicsPreset = "balanced30" -- derived: style .. fps, or "off"
DeckMode.graphicsPresetApplied = false
DeckMode.controllerMode = true
DeckMode.controllerModeApplied = false
DeckMode.settingsPath = nil

local function log(fmt, ...)
    print(string.format("[DeckMode] " .. fmt, ...))
end

local function clampScale(value)
    return math.max(DeckMode.MIN_SCALE, math.min(DeckMode.MAX_SCALE, value))
end

---------------------------------------------------------------------------------------------------
-- Settings
---------------------------------------------------------------------------------------------------

function DeckMode.loadSettings()
    local dir = g_modSettingsDirectory
    if dir == nil then
        log("g_modSettingsDirectory not available, using defaults (scale %.2f)", DeckMode.scale)
        return
    end

    createFolder(dir)
    DeckMode.settingsPath = dir .. DeckMode.SETTINGS_FILE

    if fileExists(DeckMode.settingsPath) then
        local xmlFile = loadXMLFile("DeckModeSettings", DeckMode.settingsPath)
        if xmlFile ~= nil and xmlFile ~= 0 then
            local scale = getXMLFloat(xmlFile, "deckMode#scale")
            if scale ~= nil then
                DeckMode.scale = clampScale(scale)
            end
            local fps = getXMLString(xmlFile, "deckMode#targetFps")
            local style = getXMLString(xmlFile, "deckMode#graphicsStyle")
            if fps ~= nil or style ~= nil then
                DeckMode.setGraphicsChoice(fps or DeckMode.graphicsFps, style or DeckMode.graphicsStyle)
            else
                -- 0.2 - 0.4 settings files: a single preset name
                local preset = getXMLString(xmlFile, "deckMode#graphicsPreset")
                if preset ~= nil then
                    DeckMode.migratePreset(preset)
                end
            end
            DeckMode.graphicsPresetApplied = Utils.getNoNil(getXMLBool(xmlFile, "deckMode#graphicsPresetApplied"), false)
            DeckMode.controllerMode = Utils.getNoNil(getXMLBool(xmlFile, "deckMode#controllerMode"), true)
            DeckMode.controllerModeApplied = Utils.getNoNil(getXMLBool(xmlFile, "deckMode#controllerModeApplied"), false)
            delete(xmlFile)
        end
    else
        -- carry over the text scale from the pre-release name (FS25_BigMenuText)
        local legacyPath = dir .. "FS25_BigMenuText.xml"
        if fileExists(legacyPath) then
            local legacyFile = loadXMLFile("DeckModeLegacySettings", legacyPath)
            if legacyFile ~= nil and legacyFile ~= 0 then
                local scale = getXMLFloat(legacyFile, "bigMenuText#scale")
                if scale ~= nil then
                    DeckMode.scale = clampScale(scale)
                end
                delete(legacyFile)
            end
        end
    end

    -- always write back, so new attributes show up in older settings files
    DeckMode.saveSettings()

    log("text scale %.2f, graphics: target FPS %s, style %s (applied: %s), controller mode %s (applied: %s), settings: %s",
        DeckMode.scale, DeckMode.graphicsFps, DeckMode.graphicsStyle, tostring(DeckMode.graphicsPresetApplied),
        tostring(DeckMode.controllerMode), tostring(DeckMode.controllerModeApplied), DeckMode.settingsPath)
end

function DeckMode.saveSettings()
    if DeckMode.settingsPath == nil then
        return
    end

    local xmlFile = createXMLFile("DeckModeSettings", DeckMode.settingsPath, "deckMode")
    if xmlFile ~= nil and xmlFile ~= 0 then
        setXMLFloat(xmlFile, "deckMode#scale", DeckMode.scale)
        setXMLString(xmlFile, "deckMode#targetFps", DeckMode.graphicsFps)
        setXMLString(xmlFile, "deckMode#graphicsStyle", DeckMode.graphicsStyle)
        setXMLBool(xmlFile, "deckMode#graphicsPresetApplied", DeckMode.graphicsPresetApplied)
        setXMLBool(xmlFile, "deckMode#controllerMode", DeckMode.controllerMode)
        setXMLBool(xmlFile, "deckMode#controllerModeApplied", DeckMode.controllerModeApplied)
        saveXMLFile(xmlFile)
        delete(xmlFile)
    end
end

---------------------------------------------------------------------------------------------------
-- Graphics preset
---------------------------------------------------------------------------------------------------

-- Presets for the Steam Deck (1280x800 APU), based on public FS25 tests:
--  * SteamDeckHQ review: Medium preset + FSR 3 Quality, 30 FPS cap, mirrors 0, terrain low,
--    PPAA off -> steady 30 FPS at 12-16 W.
--  * pcoptimizedsettings.com (per-setting cost): mirrors up to 12%+, shadow quality ~10%,
--    object / foliage / LOD distance ~10% each, foliage shadows ~7%, screen-space shadows 4-5%,
--    light quality ~5%; SSAO, SSR, clouds, atmosphere, shader quality: little or no cost.
-- Each value is a table of "knobs"; every knob maps to an engine setter or a game setting.
-- Knobs whose function or enum does not exist in this game version are skipped and logged.

-- Two menu fields: target FPS (off / 30 / 60) and style (power saver / balanced / high quality).
-- "Off" means Deck Mode does not touch graphics at all.
DeckMode.FPS_ORDER = {"off", "30", "60"}
DeckMode.FPS_NAMES = {off = "Off", ["30"] = "30 FPS", ["60"] = "60 FPS"}
DeckMode.STYLE_ORDER = {"powersaver", "balanced", "quality"}
DeckMode.STYLE_NAMES = {powersaver = "Power Saver", balanced = "Balanced", quality = "High Quality"}

-- settings shared by every preset (expensive for little visual gain on a 7" screen)
local COMMON = {
    softShadows = 0, foliageShadows = false, ssr = "OFF", ssShadows = "OFF", lensFlares = "OFF", mirrors = 0,
}

-- "distance" sets object, foliage, LOD, terrain LOD and foliage LOD distance to the same value
local function preset(values)
    for key, value in pairs(COMMON) do
        if values[key] == nil then
            values[key] = value
        end
    end
    local d = values.distance
    values.distance = nil
    values.objectDistance, values.foliageDistance, values.lodDistance = d, d, d
    values.terrainLod, values.foliageLod = d, d
    return values
end

DeckMode.PRESETS = {
    -- 30 FPS
    powersaver30 = preset({frameLimit = 30, upscaler = "PERFORMANCE", shadowDistance = 0, maxShadowLights = 1,
        ssao = 0, cloudShadows = false, distance = 0.6, tireTracks = 0.5}),
    balanced30 = preset({frameLimit = 30, upscaler = "BALANCED", shadowDistance = 0, maxShadowLights = 2,
        ssao = 1, cloudShadows = false, distance = 0.8, tireTracks = 1.0}),
    -- close to the SteamDeckHQ recommendation (Medium + FSR 3 Quality, 30 FPS, 12-16 W)
    quality30 = preset({frameLimit = 30, upscaler = "QUALITY", shadowDistance = 1, maxShadowLights = 3,
        ssao = 2, cloudShadows = true, distance = 1.0, tireTracks = 1.0}),

    -- 60 FPS: twice the frames, so one step lower than the matching 30 FPS style
    powersaver60 = preset({frameLimit = 60, upscaler = "PERFORMANCE", shadowDistance = 0, maxShadowLights = 1,
        ssao = 0, cloudShadows = false, distance = 0.5, tireTracks = 0.5}),
    balanced60 = preset({frameLimit = 60, upscaler = "PERFORMANCE", shadowDistance = 0, maxShadowLights = 1,
        ssao = 1, cloudShadows = false, distance = 0.7, tireTracks = 1.0}),
    quality60 = preset({frameLimit = 60, upscaler = "BALANCED", shadowDistance = 0, maxShadowLights = 2,
        ssao = 1, cloudShadows = true, distance = 0.8, tireTracks = 1.0}),
}

local function indexOf(list, value)
    for i, v in ipairs(list) do
        if v == value then
            return i
        end
    end
    return nil
end

function DeckMode.setGraphicsChoice(fps, style)
    fps = string.lower(tostring(fps))
    style = string.lower(tostring(style))
    if indexOf(DeckMode.FPS_ORDER, fps) == nil then
        fps = "30"
    end
    if indexOf(DeckMode.STYLE_ORDER, style) == nil then
        style = "balanced"
    end
    DeckMode.graphicsFps = fps
    DeckMode.graphicsStyle = style
    DeckMode.graphicsPreset = fps == "off" and "off" or (style .. fps)
end

-- single preset names used by 0.2 - 0.4
function DeckMode.migratePreset(name)
    local legacy = {
        off = {"off", "balanced"},
        balanced = {"60", "quality"},
        battery30 = {"30", "powersaver"}, quality30 = {"30", "quality"},
        battery60 = {"60", "powersaver"}, quality60 = {"60", "quality"},
    }
    local choice = legacy[string.lower(tostring(name))] or {"30", "balanced"}
    DeckMode.setGraphicsChoice(choice[1], choice[2])
end

local function enumValue(enumName, key)
    local enum = _G[enumName]
    if type(enum) == "table" then
        return enum[key]
    end
    return nil
end

-- knob -> {label, apply(value) -> true | false, reason}
local function engine(funcName, convert)
    return function(value)
        local setter = _G[funcName]
        if type(setter) ~= "function" then
            return false, funcName .. " missing"
        end
        if convert ~= nil then
            value = convert(value)
        end
        if value == nil then
            return false, "value not available"
        end
        local ok, err = pcall(setter, value)
        return ok, err
    end
end

local function gameSetting(key, convert)
    return function(value)
        if g_gameSettings == nil or GameSettings == nil or GameSettings.SETTING == nil or GameSettings.SETTING[key] == nil then
            return false, "GameSettings." .. key .. " missing"
        end
        if convert ~= nil then
            value = convert(value)
        end
        if value == nil then
            return false, "value not available"
        end
        local ok, err = pcall(g_gameSettings.setValue, g_gameSettings, GameSettings.SETTING[key], value)
        return ok, err
    end
end

DeckMode.KNOBS = {
    {key = "shadowDistance",  label = "shadow distance",          apply = engine("setShadowDistanceQuality")},
    {key = "softShadows",     label = "soft shadows",             apply = engine("setShadowFilterQuality")},
    {key = "foliageShadows",  label = "foliage shadows",          apply = engine("setAllowFoliageShadows")},
    {key = "maxShadowLights", label = "max shadow lights",        apply = engine("setMaxNumShadowLights")},
    {key = "ssao",            label = "ambient occlusion",        apply = engine("setSSAOQuality")},
    {key = "cloudShadows",    label = "cloud shadows",            apply = engine("setCloudShadowsQuality", function(v) return v and 1 or 0 end)},
    {key = "ssr",             label = "screen-space reflections", apply = engine("setScreenSpaceReflectionsQuality", function(v) return enumValue("ScreenSpaceReflectionsQuality", v) end)},
    {key = "ssShadows",       label = "screen-space shadows",     apply = engine("setScreenSpaceShadowsQuality", function(v) return enumValue("ScreenSpaceShadowsQuality", v) end)},
    {key = "lensFlares",      label = "lens flares",              apply = engine("setLensFlareQuality", function(v) return enumValue("LensFlareQuality", v) end)},
    {key = "objectDistance",  label = "object draw distance",     apply = engine("setViewDistanceCoeff")},
    {key = "foliageDistance", label = "foliage draw distance",    apply = engine("setFoliageViewDistanceCoeff")},
    {key = "lodDistance",     label = "LOD distance",             apply = engine("setLODDistanceCoeff")},
    {key = "terrainLod",      label = "terrain LOD distance",     apply = engine("setTerrainLODDistanceCoeff")},
    {key = "foliageLod",      label = "foliage LOD distance",     apply = engine("setFoliageLODDistanceCoeff")},
    {key = "tireTracks",      label = "tire tracks",              apply = engine("setTyreTracksSegmentsCoeff")},
    {key = "mirrors",         label = "max mirrors",              apply = gameSetting("MAX_NUM_MIRRORS")},
    {key = "frameLimit",      label = "frame limit",              apply = gameSetting("FRAME_LIMIT")},
    -- FSR 3 upscaling; post-process AA off as the settings menu does when FSR 3 is selected
    {key = "upscaler",        label = "FSR 3 upscaling",          apply = function(mode)
        local quality = enumValue("FidelityFxSR30Quality", mode)
        if quality == nil or type(setFidelityFxSR30Quality) ~= "function" then
            return false, "FSR 3 not available"
        end
        if type(getSupportsFidelityFxSR30Quality) == "function" and not getSupportsFidelityFxSR30Quality(quality) then
            return false, "FSR 3 " .. mode .. " not supported on this GPU"
        end
        local ok, err = pcall(setFidelityFxSR30Quality, quality)
        if ok and type(setPostProcessAntiAliasing) == "function" and enumValue("PostProcessAntiAliasing", "OFF") ~= nil then
            pcall(setPostProcessAntiAliasing, PostProcessAntiAliasing.OFF)
        end
        return ok, err
    end},
}

function DeckMode.applyGraphicsPreset()
    local presetName = DeckMode.graphicsPreset
    local preset = DeckMode.PRESETS[presetName]
    if preset == nil then
        log("graphics preset '%s': nothing to apply", presetName)
        return
    end

    local numApplied, numSkipped = 0, 0
    for _, knob in ipairs(DeckMode.KNOBS) do
        local value = preset[knob.key]
        if value ~= nil then
            local ok, err = knob.apply(value)
            if ok then
                numApplied = numApplied + 1
            else
                numSkipped = numSkipped + 1
                log("  skipped %s = %s (%s)", knob.label, tostring(value), tostring(err))
            end
        end
    end

    -- persist like the settings menu does, then let the menu re-read the engine state
    if type(saveHardwareScalability) == "function" then
        pcall(saveHardwareScalability)
    end
    if g_gameSettings ~= nil and g_gameSettings.save ~= nil then
        pcall(g_gameSettings.save, g_gameSettings)
    end
    if g_settingsModel ~= nil and g_settingsModel.refresh ~= nil then
        pcall(g_settingsModel.refresh, g_settingsModel)
    end

    DeckMode.graphicsPresetApplied = true
    DeckMode.saveSettings()

    log("graphics preset '%s' applied (%d settings, %d skipped)", presetName, numApplied, numSkipped)

    if DeckMode.DEBUG then
        local function enumKeys(name)
            local enum = _G[name]
            if type(enum) ~= "table" then
                return "n/a"
            end
            local parts = {}
            for k, v in pairs(enum) do
                table.insert(parts, tostring(k) .. "=" .. tostring(v))
            end
            table.sort(parts)
            return table.concat(parts, " ")
        end
        local function call(name)
            local f = _G[name]
            if type(f) ~= "function" then
                return "n/a"
            end
            local ok, a, b = pcall(f)
            return ok and (tostring(a) .. (b ~= nil and (", " .. tostring(b)) or "")) or "error"
        end
        log("  FidelityFxSR30Quality: %s", enumKeys("FidelityFxSR30Quality"))
        log("  PostProcessAntiAliasing: %s", enumKeys("PostProcessAntiAliasing"))
        log("  now: fsr3=%s ppaa=%s viewDist=%s shadowLights=%s tyreTracks=%s shadowQuality=%s",
            call("getFidelityFxSR30Quality"), call("getPostProcessAntiAliasing"), call("getViewDistanceCoeff"),
            call("getMaxNumShadowLights"), call("getTyreTracksSegmentsCoeff"), call("getShadowQuality"))
        if g_gameSettings ~= nil and GameSettings ~= nil and GameSettings.SETTING ~= nil then
            local values = g_gameSettings.frameLimitValues
            log("  frameLimit=%s (values: %s) maxMirrors=%s",
                tostring(g_gameSettings:getValue(GameSettings.SETTING.FRAME_LIMIT)),
                type(values) == "table" and table.concat(values, ",") or "n/a",
                tostring(g_gameSettings:getValue(GameSettings.SETTING.MAX_NUM_MIRRORS)))
        end
        local names = {}
        for k, v in pairs(_G) do
            if type(v) == "function" then
                local lk = string.lower(tostring(k))
                if lk:find("framerate") or lk:find("framelimit") or lk:find("fps") or lk:find("upscal") then
                    table.insert(names, tostring(k))
                end
            end
        end
        table.sort(names)
        log("  frame functions: %s", table.concat(names, ", "))
    end
end

---------------------------------------------------------------------------------------------------
-- Controller mode: gamepad input on, button hints always show gamepad buttons
---------------------------------------------------------------------------------------------------

local function setGameSetting(key, value)
    if g_gameSettings == nil or GameSettings == nil or GameSettings.SETTING == nil then
        return false
    end
    local name = GameSettings.SETTING[key]
    if name == nil or value == nil then
        return false
    end
    return pcall(g_gameSettings.setValue, g_gameSettings, name, value)
end

function DeckMode.applyControllerMode(enabled)
    local helpModeValue = enabled and GS_INPUT_HELP_MODE_GAMEPAD or GS_INPUT_HELP_MODE_AUTO

    -- preferred: go through the settings model like the Settings menu does, so the input system
    -- picks up the new mode right away
    local viaModel = false
    local model = g_settingsModel
    local keys = SettingsModel ~= nil and SettingsModel.SETTING or nil
    if model ~= nil and keys ~= nil and keys.INPUT_HELP_MODE ~= nil and model.settings ~= nil
        and model.settings[keys.INPUT_HELP_MODE] ~= nil then
        viaModel = pcall(function()
            if enabled and keys.GAMEPAD_ENABLED ~= nil and model.settings[keys.GAMEPAD_ENABLED] ~= nil then
                model:setValue(keys.GAMEPAD_ENABLED, true)
            end
            model:setValue(keys.INPUT_HELP_MODE, helpModeValue)
            model:applyChanges(SettingsModel.SETTING_CLASS.SAVE_GAMEPLAY_SETTINGS)
        end)
    end

    if not viaModel then
        if enabled then
            setGameSetting("IS_GAMEPAD_ENABLED", true)
        end
        setGameSetting("INPUT_HELP_MODE", helpModeValue)
        if g_gameSettings ~= nil and g_gameSettings.save ~= nil then
            pcall(g_gameSettings.save, g_gameSettings)
        end
        if model ~= nil and model.refresh ~= nil then
            pcall(model.refresh, model)
        end
    end

    DeckMode.controllerMode = enabled
    DeckMode.controllerModeApplied = true
    DeckMode.saveSettings()

    local helpMode = nil
    if g_inputBinding ~= nil and g_inputBinding.getInputHelpMode ~= nil then
        helpMode = g_inputBinding:getInputHelpMode()
    end
    local savedMode = nil
    if g_gameSettings ~= nil and GameSettings ~= nil and GameSettings.SETTING ~= nil then
        savedMode = g_gameSettings:getValue(GameSettings.SETTING.INPUT_HELP_MODE)
    end
    log("controller mode %s (via settings model: %s, setting %s, active help mode %s)",
        enabled and "on" or "off", tostring(viaModel), tostring(savedMode), tostring(helpMode))

    if DeckMode.DEBUG and g_inputBinding ~= nil then
        local names = {}
        local mt = getmetatable(g_inputBinding)
        local class = mt ~= nil and mt.__index or nil
        if type(class) == "table" then
            for k, v in pairs(class) do
                if type(v) == "function" and string.find(string.lower(tostring(k)), "mode") then
                    table.insert(names, tostring(k))
                end
            end
        end
        table.sort(names)
        log("g_inputBinding mode functions: %s", table.concat(names, ", "))
    end
end

---------------------------------------------------------------------------------------------------
-- "Deck Mode" section in the in-game Settings page (General settings tab)
---------------------------------------------------------------------------------------------------

DeckMode.SCALE_STEPS = {1.0, 1.1, 1.2, 1.3, 1.4, 1.5, 1.6, 1.7, 1.8, 1.9, 2.0}

local function scaleIndex()
    local best, bestDiff = 1, math.huge
    for i, value in ipairs(DeckMode.SCALE_STEPS) do
        local diff = math.abs(value - DeckMode.scale)
        if diff < bestDiff then
            best, bestDiff = i, diff
        end
    end
    return best
end

local function fpsIndex()
    return indexOf(DeckMode.FPS_ORDER, DeckMode.graphicsFps) or 1
end

local function styleIndex()
    return indexOf(DeckMode.STYLE_ORDER, DeckMode.graphicsStyle) or 2
end

local function namesFor(order, names)
    local texts = {}
    for _, key in ipairs(order) do
        table.insert(texts, names[key])
    end
    return texts
end

local function findChild(element, predicate)
    for _, child in ipairs(element.elements) do
        if predicate(child) then
            return child
        end
    end
    return nil
end

local function byProfile(name)
    return function(element)
        return element.profile == name
    end
end

-- Clones an existing settings row (container > option + title) and rewires it.
local function createRow(page, layout, templateRow, title, tooltip, texts, state, onChange)
    local row = templateRow:clone(layout)
    local option = findChild(row, function(e) return e.setTexts ~= nil and e.setState ~= nil end)
    local titleElement = findChild(row, byProfile("fs25_settingsMultiTextOptionTitle"))
    if option == nil then
        row:unlinkElement()
        return nil
    end

    option.id = nil
    option.onClickCallback = function()
        onChange(option:getState())
    end
    option:setTexts(texts)
    option:setState(state)

    if titleElement ~= nil then
        titleElement:setText(title)
    end
    local tooltipElement = findChild(option, byProfile("fs25_multiTextOptionTooltip"))
    if tooltipElement ~= nil then
        tooltipElement:setText(tooltip)
    end

    if FocusManager ~= nil and FocusManager.loadElementFromCustomValues ~= nil then
        pcall(FocusManager.loadElementFromCustomValues, FocusManager, option)
    end

    return row, option
end

function DeckMode.buildSettingsSection()
    local menu = g_inGameMenu
    local page = menu ~= nil and menu.pageSettings or nil
    if page == nil or page.deckModeSection ~= nil then
        return
    end

    local layout = page.generalSettingsLayout
    local templateRow = page.multiInputHelpMode ~= nil and page.multiInputHelpMode.parent or nil
    if layout == nil or templateRow == nil then
        log("settings page layout not found, no Deck Mode section in the menu")
        return
    end
    local headerTemplate = findChild(layout, byProfile("fs25_settingsSectionHeader"))

    local numBefore = #layout.elements
    local section = {}

    if headerTemplate ~= nil then
        local header = headerTemplate:clone(layout)
        header:setText("DECK MODE")
        section.header = header
    end

    local scaleTexts = {}
    for _, value in ipairs(DeckMode.SCALE_STEPS) do
        table.insert(scaleTexts, string.format("%d%%", math.floor(value * 100 + 0.5)))
    end

    local _, scaleOption = createRow(page, layout, templateRow, "Menu Text Size",
        "Size of the text in menus, dialogs and the button help bar. Some menus update after reopening them.",
        scaleTexts, scaleIndex(),
        function(state)
            DeckMode.setScale(DeckMode.SCALE_STEPS[state] or DeckMode.DEFAULT_SCALE)
        end)
    section.scaleOption = scaleOption

    local function onGraphicsChoice(fps, style)
        DeckMode.setGraphicsChoice(fps, style)
        if DeckMode.graphicsPreset == "off" then
            DeckMode.saveSettings()
        else
            DeckMode.applyGraphicsPreset()
        end
    end

    local _, fpsOption = createRow(page, layout, templateRow, "Target FPS",
        "Frame limit for the graphics preset; applies right away. Off: Deck Mode does not touch graphics settings.",
        namesFor(DeckMode.FPS_ORDER, DeckMode.FPS_NAMES), fpsIndex(),
        function(state)
            onGraphicsChoice(DeckMode.FPS_ORDER[state] or "off", DeckMode.graphicsStyle)
        end)
    section.fpsOption = fpsOption

    local _, styleOption = createRow(page, layout, templateRow, "Graphics Style",
        "Power Saver: lower settings, longer battery life. Balanced: good mix. High Quality: better shadows and "
            .. "view distance, more power. Uses FSR 3 upscaling; applies right away.",
        namesFor(DeckMode.STYLE_ORDER, DeckMode.STYLE_NAMES), styleIndex(),
        function(state)
            onGraphicsChoice(DeckMode.graphicsFps, DeckMode.STYLE_ORDER[state] or "balanced")
        end)
    section.styleOption = styleOption

    local _, controllerOption = createRow(page, layout, templateRow, "Controller Mode",
        "On: gamepad input on, and the button help always shows controller buttons.",
        {"Off", "On"}, DeckMode.controllerMode and 2 or 1,
        function(state)
            DeckMode.applyControllerMode(state == 2)
        end)
    section.controllerOption = controllerOption

    -- move the new elements to the top of the General tab
    local added = {}
    for i = numBefore + 1, #layout.elements do
        table.insert(added, layout.elements[i])
    end
    for i = #layout.elements, numBefore + 1, -1 do
        table.remove(layout.elements, i)
    end
    for i, element in ipairs(added) do
        table.insert(layout.elements, i, element)
    end
    pcall(layout.invalidateLayout, layout)

    page.deckModeSection = section
    log("added Deck Mode section to the settings page (%d elements)", #added)
end

-- keep the options in sync when the settings page opens
function DeckMode.refreshSettingsSection()
    local menu = g_inGameMenu
    local section = menu ~= nil and menu.pageSettings ~= nil and menu.pageSettings.deckModeSection or nil
    if section == nil then
        return
    end
    if section.scaleOption ~= nil then
        section.scaleOption:setState(scaleIndex())
    end
    if section.fpsOption ~= nil then
        section.fpsOption:setState(fpsIndex())
    end
    if section.styleOption ~= nil then
        section.styleOption:setState(styleIndex())
    end
    if section.controllerOption ~= nil then
        local helpMode = g_gameSettings ~= nil and GameSettings ~= nil and GameSettings.SETTING ~= nil
            and g_gameSettings:getValue(GameSettings.SETTING.INPUT_HELP_MODE) or nil
        section.controllerOption:setState(helpMode == GS_INPUT_HELP_MODE_GAMEPAD and 2 or 1)
    end
end
---------------------------------------------------------------------------------------------------
-- Hooks (affect every text element loaded after the mod)
---------------------------------------------------------------------------------------------------

local function scaledY(value, current)
    return GuiUtils.getNormalizedYValue(value, current) * DeckMode.scale
end

function DeckMode.installHooks()
    local origLoadProfile = TextElement.loadProfile
    TextElement.loadProfile = function(self, profile, applyProfile)
        origLoadProfile(self, profile, applyProfile)

        local changed = false
        local textSize = profile:getValue("textSize")
        if textSize ~= nil then
            self.textSize = scaledY(textSize, self.textSize)
            self.defaultTextSize = self.textSize
            self[DeckMode.FLAG] = true
            changed = true
        end

        local text2Size = profile:getValue("text2Size")
        if text2Size ~= nil then
            self.text2Size = scaledY(text2Size, self.text2Size)
            self.defaultText2Size = self.text2Size
            changed = true
        end

        if changed and applyProfile then
            self:updateSize()
        end
    end

    local origLoadFromXML = TextElement.loadFromXML
    TextElement.loadFromXML = function(self, xmlFile, key)
        origLoadFromXML(self, xmlFile, key)

        local xmlTextSize = getXMLString(xmlFile, key .. "#textSize")
        local xmlText2Size = getXMLString(xmlFile, key .. "#text2Size")
        local wasScaled = self[DeckMode.FLAG] == true

        if xmlTextSize ~= nil then
            self.textSize = scaledY(xmlTextSize, self.textSize)
        elseif not wasScaled then
            -- no profile/XML size: the class default is in use
            self.textSize = self.textSize * DeckMode.scale
        end

        if xmlText2Size ~= nil then
            self.text2Size = scaledY(xmlText2Size, self.text2Size)
        elseif not wasScaled and self.text2Size ~= nil then
            self.text2Size = self.text2Size * DeckMode.scale
        end

        self.defaultTextSize = self.textSize
        self.defaultText2Size = self.text2Size
        self[DeckMode.FLAG] = true

        self:updateSize()
    end

    -- Buttons that size themselves to their text (e.g. the settings tabs) grow with the bigger text,
    -- but child backgrounds sized to the old button width (the selected-tab highlight) do not.
    -- Let children that matched the button's width follow it.
    if ButtonElement ~= nil and ButtonElement.updateSize ~= nil then
        local origButtonUpdateSize = ButtonElement.updateSize
        ButtonElement.updateSize = function(self, forceTextSize)
            local oldWidth = self.absSize ~= nil and self.absSize[1] or nil
            origButtonUpdateSize(self, forceTextSize)

            if oldWidth == nil or not (self.fitToContent or self.textAutoWidth) then
                return
            end
            local newWidth = self.absSize[1]
            if math.abs(newWidth - oldWidth) < 0.0001 or oldWidth <= 0 then
                return
            end
            for _, child in ipairs(self.elements) do
                if child.absSize ~= nil and math.abs(child.absSize[1] - oldWidth) < 0.0005 then
                    child:setSize(child.size[1] * newWidth / oldWidth, nil)
                end
            end
        end
    end

    local origCopyAttributes = TextElement.copyAttributes
    TextElement.copyAttributes = function(self, src)
        origCopyAttributes(self, src)
        self[DeckMode.FLAG] = src[DeckMode.FLAG]
    end
end

---------------------------------------------------------------------------------------------------
-- Walk existing GUI elements (built before the mod loaded)
---------------------------------------------------------------------------------------------------

local function isGuiElement(value)
    return type(value) == "table" and type(value.elements) == "table" and value.absSize ~= nil
end

local function isTextElement(element)
    return element.defaultTextSize ~= nil and element.textSize ~= nil and element.textMinSize ~= nil
end

function DeckMode.scaleExistingElement(element)
    if element[DeckMode.FLAG] then
        return false
    end

    local k = DeckMode.scale
    element.defaultTextSize = element.defaultTextSize * k
    element.textSize = element.defaultTextSize
    if element.defaultText2Size ~= nil then
        element.defaultText2Size = element.defaultText2Size * k
        element.text2Size = element.defaultText2Size
    end
    element[DeckMode.FLAG] = true

    -- re-run the element's own layout (wrapping / shrink-to-fit) with the new size
    if element.sourceText ~= nil and element.setTextInternal ~= nil then
        pcall(element.setTextInternal, element, element.sourceText, nil, true)
    else
        pcall(element.updateSize, element)
    end

    return true
end

-- Calls fn(element) for every GUI element reachable from the GUI system, then re-runs layouts.
function DeckMode.forEachGuiElement(fn)
    local visited = {}
    local layouts = {}

    local visit -- forward declaration

    -- follow plain (non-element) tables a little, to reach e.g. SmoothList cellDatabase / cellCache
    local function scanTable(tbl, depth)
        if depth > 2 or visited[tbl] then
            return
        end
        visited[tbl] = true
        for _, value in pairs(tbl) do
            if isGuiElement(value) then
                visit(value)
            elseif type(value) == "table" and getmetatable(value) == nil then
                scanTable(value, depth + 1)
            end
        end
    end

    visit = function(element)
        if visited[element] then
            return
        end
        visited[element] = true

        fn(element)
        if element.invalidateLayout ~= nil then
            table.insert(layouts, element)
        end

        for _, child in ipairs(element.elements) do
            visit(child)
        end

        -- element fields: unlinked templates, list caches, controller references
        for field, value in pairs(element) do
            if field ~= "parent" then
                if isGuiElement(value) then
                    visit(value)
                elseif type(value) == "table" and getmetatable(value) == nil then
                    scanTable(value, 1)
                end
            end
        end
    end

    local gui = g_gui
    if gui == nil then
        return false
    end

    for _, collection in ipairs({gui.guis, gui.frames, gui.screens, gui.screenControllers, gui.dialogs}) do
        if type(collection) == "table" then
            for _, value in pairs(collection) do
                if isGuiElement(value) then
                    visit(value)
                end
            end
        end
    end

    -- children are laid out before parents would be ideal, but invalidateLayout is idempotent
    for i = #layouts, 1, -1 do
        pcall(layouts[i].invalidateLayout, layouts[i])
    end

    return true
end

function DeckMode.scaleExisting()
    local numScaled = 0
    local ok = DeckMode.forEachGuiElement(function(element)
        if isTextElement(element) and DeckMode.scaleExistingElement(element) then
            numScaled = numScaled + 1
        end
    end)
    if ok then
        log("scaled %d existing text elements", numScaled)
    else
        log("g_gui not available yet")
    end
end

-- Changes the text scale live: already scaled elements are rescaled by new/old, the rest scaled once.
function DeckMode.setScale(newScale)
    newScale = clampScale(newScale)
    local ratio = newScale / DeckMode.scale
    if math.abs(ratio - 1) < 0.001 then
        return
    end
    DeckMode.scale = newScale
    DeckMode.saveSettings()

    DeckMode.forEachGuiElement(function(element)
        if not isTextElement(element) then
            return
        end
        if element[DeckMode.FLAG] then
            element.defaultTextSize = element.defaultTextSize * ratio
            element.textSize = element.defaultTextSize
            if element.defaultText2Size ~= nil then
                element.defaultText2Size = element.defaultText2Size * ratio
                element.text2Size = element.defaultText2Size
            end
            if element.sourceText ~= nil and element.setTextInternal ~= nil then
                pcall(element.setTextInternal, element, element.sourceText, nil, true)
            else
                pcall(element.updateSize, element)
            end
        else
            DeckMode.scaleExistingElement(element)
        end
    end)
    log("text scale changed to %.2f", newScale)
end

---------------------------------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Debug dump (development only): writes the in-game settings page structure to log.txt
---------------------------------------------------------------------------------------------------

local function sortedKeys(tbl)
    local keys = {}
    for k in pairs(tbl) do
        table.insert(keys, tostring(k))
    end
    table.sort(keys)
    return keys
end

function DeckMode.debugDump()
    log("=== DUMP BEGIN ===")

    for _, name in ipairs({"GameSettings", "SettingsModel"}) do
        local class = _G[name]
        if class ~= nil and type(class.SETTING) == "table" then
            log("%s.SETTING: %s", name, table.concat(sortedKeys(class.SETTING), ", "))
        else
            log("%s.SETTING: n/a", name)
        end
    end
    for _, name in ipairs({"GS_INPUT_HELP_MODE_AUTO", "GS_INPUT_HELP_MODE_KEYBOARD", "GS_INPUT_HELP_MODE_GAMEPAD"}) do
        log("%s = %s", name, tostring(_G[name]))
    end
    if g_gameSettings ~= nil and GameSettings ~= nil and type(GameSettings.SETTING) == "table" then
        for key, value in pairs(GameSettings.SETTING) do
            local lk = string.lower(tostring(key))
            if lk:find("gamepad") or lk:find("input") or lk:find("help") or lk:find("camera") or lk:find("invert") then
                local ok, v = pcall(g_gameSettings.getValue, g_gameSettings, value)
                log("  g_gameSettings %s (%s) = %s", tostring(key), tostring(value), ok and tostring(v) or "error")
            end
        end
    end

    local menu = g_inGameMenu or (g_gui ~= nil and g_gui.screenControllers ~= nil and g_gui.screenControllers[InGameMenu])
    local page = menu ~= nil and menu.pageSettings or nil
    if page == nil then
        log("pageSettings not found (menu: %s)", tostring(menu))
        log("=== DUMP END ===")
        return
    end

    -- fields of the frame object that reference GUI elements (named controls)
    local named = {}
    for field, value in pairs(page) do
        if isGuiElement(value) then
            table.insert(named, string.format("%s=%s/%s", tostring(field), tostring(value.typeName), tostring(value.profile)))
        end
    end
    table.sort(named)
    log("pageSettings named elements: %s", table.concat(named, " | "))

    -- class methods
    local methods = {}
    local mt = getmetatable(page)
    local class = mt ~= nil and mt.__index or nil
    if type(class) == "table" then
        for k, v in pairs(class) do
            if type(v) == "function" then
                table.insert(methods, tostring(k))
            end
        end
    end
    table.sort(methods)
    log("pageSettings methods: %s", table.concat(methods, ", "))

    local count = 0
    local function walk(element, depth)
        if count > 600 or depth > 12 then
            return
        end
        count = count + 1
        local text = element.text or element.sourceText
        if type(text) == "string" and #text > 40 then
            text = text:sub(1, 40)
        end
        log("%s%s id=%s profile=%s text=%s", string.rep("  ", depth), tostring(element.typeName),
            tostring(element.id), tostring(element.profile), tostring(text))
        for _, child in ipairs(element.elements) do
            walk(child, depth + 1)
        end
    end
    walk(page, 0)

    log("=== DUMP END ===")
end

function DeckMode:loadMap(filename)
    -- in-game menus may be (re)built during mission load; catch anything not yet scaled
    DeckMode.scaleExisting()

    local ok, err = pcall(DeckMode.buildSettingsSection)
    if not ok then
        log("could not add the settings section: %s", tostring(err))
    end

    if InGameMenuSettingsFrame ~= nil and InGameMenuSettingsFrame.onFrameOpen ~= nil and not DeckMode.frameOpenHooked then
        DeckMode.frameOpenHooked = true
        InGameMenuSettingsFrame.onFrameOpen = Utils.appendedFunction(InGameMenuSettingsFrame.onFrameOpen, function()
            pcall(DeckMode.refreshSettingsSection)
        end)
    end

    if DeckMode.DEBUG then
        local dumpOk, dumpErr = pcall(DeckMode.debugDump)
        if not dumpOk then
            log("debug dump failed: %s", tostring(dumpErr))
        end
    end
end

function DeckMode:update(dt)
    -- apply the graphics preset once, on the first frame after the savegame finished loading
    if DeckMode.graphicsPresetChecked then
        return
    end
    DeckMode.graphicsPresetChecked = true

    if DeckMode.graphicsPreset ~= "off" and not DeckMode.graphicsPresetApplied then
        DeckMode.applyGraphicsPreset()
    end
    if DeckMode.controllerMode and not DeckMode.controllerModeApplied then
        DeckMode.applyControllerMode(true)
    end
end

DeckMode.loadSettings()
DeckMode.installHooks()
DeckMode.scaleExisting()
addModEventListener(DeckMode)
