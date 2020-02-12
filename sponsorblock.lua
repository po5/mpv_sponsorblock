-- sponsorblock.lua
--
-- This script skips sponsored segments of YouTube videos
-- using data from https://github.com/ajayyy/SponsorBlock

local ON_WINDOWS = package.config:sub(1,1) ~= '/'

local options = {
    server_address = "https://api.sponsor.ajay.app",

    python_path = ON_WINDOWS and "python" or "python3",

    -- If true, sponsored segments will only be skipped once
    skip_once = true,

    -- Note that sponsored segments may ocasionally be inaccurate if this is turned off
    -- see https://ajay.app/blog.html#voting-and-pseudo-randomness-or-sponsorblock-or-youtube-sponsorship-segment-blocker
    local_database = true,

    -- Update database on first run, does nothing if local_database is false
    auto_update = true,

    -- User ID used to submit sponsored segments, leave blank for random
    user_id = "",

    -- Tell the server when a skip happens
    report_views = true,

    -- Auto upvote skipped sponsors
    auto_upvote = true,

    -- Use sponsor times from server if they're more up to date than our local database
    server_fallback = true,

    -- Minimum duration for sponsors (in seconds), segments under that threshold will be ignored
    min_duration = 1,

    -- Fade audio for smoother transitions
    audio_fade = false,

    -- Audio fade step, applied once every 100ms until cap is reached
    audio_fade_step = 10,

    -- Audio fade cap
    audio_fade_cap = 0,

    -- Fast forward through sponsors instead of skipping
    fast_forward = false,

    -- Playback speed modifier when fast forwarding, applied once every second until cap is reached
    fast_forward_increase = .2,

    -- Playback speed cap
    fast_forward_cap = 2,

    -- Pattern for video id in local files, ignored if blank
    -- Recommended value for base youtube-dl is "-([%a%d%-_]+)%.[mw][kpe][v4b][m]?$"
    local_pattern = ""
}

mp.options = require "mp.options"
mp.options.read_options(options, "sponsorblock")

local legacy = mp.command_native_async == nil
if legacy then
    options.local_database = false
end

local utils = require "mp.utils"
local scripts_dir = mp.find_config_file("scripts")
local sponsorblock = utils.join_path(scripts_dir, "shared/sponsorblock.py")
local uid_path = utils.join_path(scripts_dir, "shared/sponsorblock.txt")
local database_file = options.local_database and utils.join_path(scripts_dir, "shared/sponsorblock.db") or ""
local youtube_id = nil
local ranges = {}
local init = false
local segment = {a = 0, b = 0, progress = 0}
local retrying = false
local last_skip = {uuid = "", dir = nil}
local speed_timer = nil
local fade_timer = nil
local fade_dir = nil
local volume_before = mp.get_property_number("volume")

function file_exists(name)
    local f = io.open(name,"r")
    if f ~= nil then io.close(f) return true else return false end
end

function t_count(t)
    local count = 0
    for _ in pairs(t) do count = count + 1 end
    return count
end

function getranges(_, exists, db, more)
    if type(exists) == "table" and exists["status"] == "1" then
        if options.server_fallback then
            mp.add_timeout(0, function() getranges(true, true, "") end)
        else
            return mp.osd_message("[sponsorblock] database update failed, gave up")
        end
    end
    if db ~= "" and db ~= database_file then db = database_file end
    if exists ~= true and not file_exists(db) then
        if not retrying then
            mp.osd_message("[sponsorblock] database update failed, retrying...")
            retrying = true
        end
        return update()
    end
    if retrying then
        mp.osd_message("[sponsorblock] database update succeeded")
        retrying = false
    end
    local sponsors
    local args = {
        options.python_path,
        sponsorblock,
        "ranges",
        db,
        options.server_address,
        youtube_id
    }
    if not legacy then
        sponsors = mp.command_native({name = "subprocess", capture_stdout = true, playback_only = false, args = args})
    else
        sponsors = utils.subprocess({args = args})
    end
    if not string.match(sponsors.stdout, "^%s*(.*%S)") then return end
    if string.match(sponsors.stdout, "error") then return getranges(true, true) end
    local new_ranges = {}
    local r_count = 0
    if more then r_count = -1 end
    for t in string.gmatch(sponsors.stdout, "[^:%s]+") do
        uuid = string.match(t, '[^,]+$')
        if ranges[uuid] then
            new_ranges[uuid] = ranges[uuid]
        else
            start_time = tonumber(string.match(t, '[^,]+'))
            end_time = tonumber(string.sub(string.match(t, ',[^,]+'), 2))
            if end_time - start_time >= options.min_duration then
                new_ranges[uuid] = {
                    start_time = start_time,
                    end_time = end_time,
                    skipped = false
                }
            end
        end
        r_count = r_count + 1
    end
    local c_count = t_count(ranges)
    if c_count == 0 or r_count >= c_count then
        ranges = new_ranges
    end
end

function fast_forward()
    local last_speed = mp.get_property_number("speed")
    local new_speed = math.min(last_speed + options.fast_forward_increase, options.fast_forward_cap)
    if new_speed <= last_speed then return end
    mp.set_property("speed", new_speed)
end

function fade_audio(step)
    local last_volume = mp.get_property_number("volume")
    local new_volume = math.max(options.audio_fade_cap, math.min(last_volume + step, volume_before))
    if new_volume == last_volume then
        if step >= 0 then fade_dir = nil end
        if fade_timer ~= nil then fade_timer:kill() end
        fade_timer = nil
        return
    end
    mp.set_property("volume", new_volume)
end

function skip_ads(name, pos)
    if pos == nil then return end
    local sponsor_ahead = false
    for uuid, t in pairs(ranges) do
        if (options.fast_forward == uuid or not options.skip_once or not t.skipped) and t.start_time <= pos and t.end_time > pos then
            if options.fast_forward == uuid then return end
            if options.fast_forward == false then
                mp.osd_message("[sponsorblock] sponsor skipped")
                mp.set_property("time-pos", t.end_time)
            else
                mp.osd_message("[sponsorblock] skipping sponsor")
            end
            t.skipped = true
            last_skip = {uuid = uuid, dir = nil}
            if options.report_views or options.auto_upvote then
                local args = {
                    options.python_path,
                    sponsorblock,
                    "stats",
                    database_file,
                    options.server_address,
                    youtube_id,
                    uuid,
                    options.report_views and "1" or "",
                    uid_path,
                    options.user_id,
                    options.auto_upvote and "1" or ""
                }
                if not legacy then
                    mp.command_native_async({name = "subprocess", playback_only = false, args = args}, function () end)
                else
                    utils.subprocess_detached({args = args})
                end
            end
            if options.fast_forward ~= false then
                options.fast_forward = uuid
                speed_timer = mp.add_periodic_timer(1, fast_forward)
            end
            return
        elseif (not options.skip_once or not t.skipped) and t.start_time <= pos + 1 and t.end_time > pos + 1 then
            sponsor_ahead = true
        end
    end
    if options.audio_fade then
        if sponsor_ahead then
            if fade_dir ~= false then
                if fade_dir == nil then volume_before = mp.get_property_number("volume") end
                if fade_timer ~= nil then fade_timer:kill() end
                fade_dir = false
                fade_timer = mp.add_periodic_timer(.1, function() fade_audio(-options.audio_fade_step) end)
            end
        elseif fade_dir == false then
            fade_dir = true
            if fade_timer ~= nil then fade_timer:kill() end
            fade_timer = mp.add_periodic_timer(.1, function() fade_audio(options.audio_fade_step) end)
        end
    end
    if options.fast_forward and options.fast_forward ~= true then
        options.fast_forward = true
        speed_timer:kill()
        mp.set_property("speed", 1)
    end
end

function vote(dir)
    if last_skip.uuid == "" then return mp.osd_message("[sponsorblock] no sponsors skipped, can't submit vote") end
    local updown = dir == "1" and "up" or "down"
    if last_skip.dir == dir then return mp.osd_message("[sponsorblock] " .. updown .. "vote already submitted") end
    last_skip.dir = dir
    local args = {
        options.python_path,
        sponsorblock,
        "stats",
        database_file,
        options.server_address,
        youtube_id,
        last_skip.uuid,
        "",
        uid_path,
        options.user_id,
        dir
    }
    if not legacy then
        mp.command_native_async({name = "subprocess", playback_only = false, args = args}, function () end)
    else
        utils.subprocess({args = args})
    end
    mp.osd_message("[sponsorblock] " .. updown .. "vote submitted")
end

function update()
    mp.command_native_async({name = "subprocess", playback_only = false, args = {
        options.python_path,
        sponsorblock,
        "update",
        database_file,
        options.server_address
    }}, getranges)
end

function file_loaded()
    local initialized = init
    ranges = {}
    segment = {a = 0, b = 0, progress = 0}
    last_skip = {uuid = "", dir = nil}
    local video_path = mp.get_property("path")
    local youtube_id1 = string.match(video_path, "https?://youtu%.be/([%a%d%-_]+).*")
    local youtube_id2 = string.match(video_path, "https?://w?w?w?%.?youtube%.com/v/([%a%d%-_]+).*")
    local youtube_id3 = string.match(video_path, "/watch%?v=([%a%d%-_]+).*")
    local youtube_id4 = string.match(video_path, "/embed/([%a%d%-_]+).*")
    local local_pattern = nil
    if options.local_pattern ~= "" then
        local_pattern = string.match(video_path, options.local_pattern)
    end
    youtube_id = youtube_id1 or youtube_id2 or youtube_id3 or youtube_id4 or local_pattern
    if not youtube_id then return end
    init = true
    if not options.local_database then
        getranges(true, true)
    else
        local exists = file_exists(database_file)
        if exists and options.server_fallback then
            getranges(true, true)
            mp.add_timeout(0, function() getranges(true, true, "", true) end)
        elseif exists then
            getranges(true, true)
        elseif options.server_fallback then
            mp.add_timeout(0, function() getranges(true, true, "") end)
        end
    end
    if initialized then return end
    mp.observe_property("time-pos", "native", skip_ads)
    if not options.local_database or (not options.auto_update and file_exists(database_file)) then return end
    update()
end

function set_segment()
    if not youtube_id then return end
    local pos = mp.get_property_number("time-pos")
    if pos == nil then return end
    if segment.progress > 1 then
        segment.progress = segment.progress - 2
    end
    if segment.progress == 1 then
        segment.progress = 0
        segment.b = pos
        mp.osd_message("[sponsorblock] segment boundary B set, press again for boundary A", 3)
    else
        segment.progress = 1
        segment.a = pos
        mp.osd_message("[sponsorblock] segment boundary A set, press again for boundary B", 3)
    end
end

function submit_segment()
    if not youtube_id then return end
    local start_time = math.min(segment.a, segment.b)
    local end_time = math.max(segment.a, segment.b)
    if end_time - start_time == 0 or end_time == 0 then
        mp.osd_message("[sponsorblock] empty segment, not submitting")
    elseif segment.progress <= 1 then
        mp.osd_message(string.format("[sponsorblock] press Shift+G again to confirm: %.2d:%.2d:%.2d to %.2d:%.2d:%.2d", start_time/(60*60), start_time/60%60, start_time%60, end_time/(60*60), end_time/60%60, end_time%60), 5)
        segment.progress = segment.progress + 2
    else
        mp.osd_message("[sponsorblock] submitting segment...", 30)
        local submit
        local args = {
            options.python_path,
            sponsorblock,
            "submit",
            database_file,
            options.server_address,
            youtube_id,
            tostring(start_time),
            tostring(end_time),
            uid_path,
            options.user_id
        }
        if not legacy then
            submit = mp.command_native({name = "subprocess", capture_stdout = true, playback_only = false, args = args})
        else
            submit = utils.subprocess({args = args})
        end
        if string.match(submit.stdout, "success") then
            segment = {a = 0, b = 0, progress = 0}
            mp.osd_message("[sponsorblock] segment submitted")
        elseif string.match(submit.stdout, "error") then
            mp.osd_message("[sponsorblock] segment submission failed, server may be down. try again", 5)
        elseif string.match(submit.stdout, "502") then
            mp.osd_message("[sponsorblock] segment submission failed, server is down. try again", 5)
        elseif string.match(submit.stdout, "400") then
            mp.osd_message("[sponsorblock] segment submission failed, impossible inputs", 5)
            segment = {a = 0, b = 0, progress = 0}
        elseif string.match(submit.stdout, "429") then
            mp.osd_message("[sponsorblock] segment submission failed, rate limited. try again", 5)
        elseif string.match(submit.stdout, "409") then
            mp.osd_message("[sponsorblock] segment already submitted", 3)
            segment = {a = 0, b = 0, progress = 0}
        else
            mp.osd_message("[sponsorblock] segment submission failed", 5)
        end
    end
end

mp.register_event("file-loaded", file_loaded)
mp.add_key_binding("g", "sponsorblock_set_segment", set_segment)
mp.add_key_binding("G", "sponsorblock_submit_segment", submit_segment)
mp.add_key_binding("h", "sponsorblock_upvote", function() return vote("1") end)
mp.add_key_binding("H", "sponsorblock_downvote", function() return vote("0") end)
