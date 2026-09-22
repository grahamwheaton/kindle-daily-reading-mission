--[[--
The reading profile for a seven-year-old learning to read.

KOReader's defaults are set for adults: smaller type, justified text and
hyphenation on, which breaks words across lines. A new reader meets a word
like "mountain-\nbike" and stops. So: larger type, generous even margins,
looser lines, no hyphenation, and ragged-right text with the publisher's own
page margins ignored, which is what makes the indents look uneven.

These are applied as KOReader's global defaults, once per profile version, so
they reach every mission without being reapplied over the top of a change made
deliberately from KOReader's own menus. Bump PROFILE_VERSION to re-apply.
--]]

local logger = require("logger")

local PROFILE_VERSION = 1

local Reading = {}

-- KOReader stores document defaults under copt_* keys; new books inherit them.
local SETTINGS = {
    copt_font_size = 26,          -- KOReader's own default is 22
    copt_h_page_margins = { 20, 20 },
    copt_t_page_margin = 15,
    copt_b_page_margin = 15,
    copt_line_spacing = 120,
    hyphenation = false,
}

-- Ragged right, and ignore whatever margins the HTML asked for.
local STYLE_TWEAKS = {
    text_align_most_left = true,
    margin_body_0 = true,
}

function Reading.apply()
    if G_reader_settings:readSetting("rupert_profile_version") == PROFILE_VERSION then
        return false
    end
    for key, value in pairs(SETTINGS) do
        G_reader_settings:saveSetting(key, value)
    end

    local tweaks = G_reader_settings:readSetting("style_tweaks") or {}
    for id, enabled in pairs(STYLE_TWEAKS) do
        tweaks[id] = enabled
    end
    G_reader_settings:saveSetting("style_tweaks", tweaks)

    G_reader_settings:saveSetting("rupert_profile_version", PROFILE_VERSION)
    G_reader_settings:flush()
    logger.info("rupertdash: applied reading profile", PROFILE_VERSION)
    return true
end

return Reading
