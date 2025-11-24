-- MIT License
--
-- Copyright (c) 2025 Ole Asteo
--
-- Permission is hereby granted, free of charge, to any person obtaining a copy
-- of this software and associated documentation files (the "Software"), to deal
-- in the Software without restriction, including without limitation the rights
-- to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
-- copies of the Software, and to permit persons to whom the Software is
-- furnished to do so, subject to the following conditions:
--
-- The above copyright notice and this permission notice shall be included in
-- all copies or substantial portions of the Software.
--
-- THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
-- IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
-- FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
-- AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
-- LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
-- OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
-- SOFTWARE.

local _ = require("gettext")
local BD = require("ui/bidi")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")
local time = require("ui/time")
local http = require("socket.http")
local util = require("util")
local JSON = require("json")
local ltn12 = require("ltn12")
local socket = require("socket")
local ffiUtil = require("ffi/util")
local Device = require("device")
local socketutil = require("socketutil")
local UIManager = require("ui/uimanager")
local NetworkMgr = require("ui/network/manager")
local ConfirmBox = require("ui/widget/confirmbox")
local PluginShare = require("pluginshare")
local InfoMessage = require("ui/widget/infomessage")
local Notification = require("ui/widget/notification")
local EventListener = require("ui/widget/eventlistener")
local T = ffiUtil.template

--[[

Feel free to copy & adapt this updater for your plugin. If you're using
GitHub releases, all you need to do is specify a `name`, `fullname`,
`update_url`, and `version` in your _meta.lua file.

Technically, we just expect the `update_url` API to respond with JSON that
satisfies
  {
    name: string,
    tag_name: string,
    assets?: { content_type: string, browser_download_url: string }[],
    zipball_url: string,
    body: string
  }

The `tag_name` must match the _meta.lua#version field, but may have a leading
"v" as to common git practice.

If any asset has `content_type == "application/zip"` (e.g., custom zip file
attached to the GitHub release), its `browser_download_url` is used as update
file. If no asset matches this content type, we default to `zipball_url`
(source code zip file of GitHub releases).

We expose a public API as `PluginShare.plugin_updater`.
Use it to control (all) instances of the updater from different plugins.

You should not need to change any of the code below.

--]]

-- just a hint for plugin authors to recognize the need to update this file
local UPDATER_VERSION = 1 -- 2025-11

--- if true (uncomment line below), we still propose update if latest version
--- matches the installed version
local DEBUG_FORCE_UPDATE = false
--DEBUG_FORCE_UPDATE = true

local function getPluginDir()
    return debug.getinfo(1, "S").source:match("@(.+%.koplugin)/")
end

local function moveFile(src, dest)
    local mv_bin = Device:isAndroid() and "/system/bin/mv" or "/bin/mv"
    return ffiUtil.execute(mv_bin, src, dest) == 0
end

local meta = dofile(getPluginDir() .. "/_meta.lua")
local settingId = "plugin_updater#" .. meta.name
local publicApi

if not PluginShare.plugin_updater then
    -- Reminder: This public API should stay backward compatible; extend, don't break.
    PluginShare.plugin_updater = EventListener:extend {
        _pause_checks = {},
        modules = {},
        --- Registers a global handler suppress checking for updates in the
        --- background. This is intended for things like lock screens, etc.
        --- @param predicate function Should return `false` to indicate that checks may be run, `true` to indicate to ask again in 60 seconds, or a function that receives a callback to call when to ask again.
        pauseAllWhile = function(predicate)
            table.insert(PluginShare.plugin_updater._pause_checks, predicate)
        end,
    }
end
publicApi = PluginShare.plugin_updater
publicApi.modules[meta.name] = {
    version = meta.version,
    settingId = settingId,
    updater_version = UPDATER_VERSION,
}

local auto_checker

local function dbg(...)
    logger.dbg("[" .. meta.name .. ":updater]", ...)
end
local function warn(...)
    logger.warn("[" .. meta.name .. ":updater]", ...)
end

local function fetchRemoteMeta()
    local sink = {}
    socketutil:set_timeout()
    local request = {
        url     = meta.update_url,
        method  = "GET",
        sink    = ltn12.sink.table(sink),
    }
    dbg("Fetching meta information on latest update", request.url)
    local code, headers, status = socket.skip(1, http.request(request))
    socketutil:reset_timeout()
    -- check network error
    if headers == nil then
        warn("Network unreachable", status or code or "unknown")
        return false
    end
    -- check HTTP error
    if code ~= 200 then
        warn("HTTP status unexpected:", status or code or "unknown")
        dbg("HTTP response headers:", headers)
        return false
    end
    -- quick check content JSON format
    local content = table.concat(sink)
    if content == "" or content:sub(1, 1) ~= "{" then
        warn("Expected plugin meta JSON response, got", content)
        return false
    end
    -- parse JSON
    local ok, data = pcall(JSON.decode, content, JSON.decode.simple)
    if not ok or not data then
        warn("Failed to parse plugin meta JSON", data)
        return false
    end
    -- parse version
    local remote_version = data.tag_name
    if remote_version:sub(1, 1) == "v" then remote_version = remote_version:sub(2) end
    -- find zip asset
    local remote_zip_asset
    for _, asset in ipairs(data.assets or {}) do
        if asset.content_type == "application/zip" then
            remote_zip_asset = asset
            break
        end
    end
    local remote_zip_url = remote_zip_asset and remote_zip_asset.browser_download_url or data.zipball_url
    local remote_description = data.body or ""
    dbg("Parsed plugin meta successfully:", string.format("name = %s | version = %s | zip_url = %s", data.name, remote_version, remote_zip_url))
    return true, {
        name = data.name,
        version = remote_version,
        description = remote_description,
        zip_url = remote_zip_url,
    }
end

local function downloadFile(local_path, remote_url)
    dbg("Downloading update file from", remote_url, "; saving as", local_path)
    socketutil:set_timeout(socketutil.FILE_BLOCK_TIMEOUT, socketutil.FILE_TOTAL_TIMEOUT)
    local code, headers, status = socket.skip(1, http.request {
        url      = remote_url,
        sink     = ltn12.sink.file(io.open(local_path, "w")),
    })
    socketutil:reset_timeout()
    if code ~= 200 then
        util.removeFile(local_path)
        dbg("Download failed:", status or code)
        dbg("HTTP response headers:", headers)
        UIManager:show(InfoMessage:new {
            text = T(_("Could not save file to:\n%1\n%2"),
                    BD.filepath(local_path),
                    status or code or "network unreachable"),
        })
        return false
    end
    dbg("Plugin update file download succeeded:", local_path)
    return true
end

local function downloadUpdate(plugin_dir, remote)
    local local_target = plugin_dir .. "_" .. remote.version .. ".zip"
    if lfs.attributes(local_target) ~= nil then
        warn("Update file already present in file system. Re-using it to avoid re-download.")
        Notification:notify(_("Update file found. Skipping download."), Notification.SOURCE_DISPATCHER)
        return local_target
    end
    if downloadFile(local_target, remote.zip_url) then
        return local_target
    else
        return nil
    end
end

local function _async_update_step(text, ...)
    local run_fns = table.pack(...)
    local step_concluded = function() end
    if text ~= nil then
        local status_widget = InfoMessage:new { text = _(text), dismissable = false }
        UIManager:show(status_widget, "ui")
        step_concluded = function() UIManager:close(status_widget, "ui") end
    end
    UIManager:nextTick(function()
        for _, run in ipairs(run_fns) do run(step_concluded) end
    end)
end

local function perform_update(remote)
    _async_update_step("Preparing for update…", function(step_concluded)
        local plugin_dir = getPluginDir()
        if not plugin_dir then
            step_concluded()
            warn("Failed to detect plugin root")
            UIManager:show(InfoMessage:new {
                text = _("Failed to detect plugin root.\nCannot perform update automatically."),
            })
            return
        end
        local backup_dir = plugin_dir .. ".backup"
        dbg("Detected plugin dir", plugin_dir)
        if lfs.attributes(backup_dir) ~= nil then
            step_concluded()
            warn("Path already exists: " .. backup_dir)
            UIManager:show(InfoMessage:new {
                text = _("Path already exists: " .. backup_dir .. "\nMaybe an incomplete update beforehand?\nPlease resolve situation by hand."),
            })
            return
        end

        _async_update_step("Downloading…", step_concluded, function(step_concluded)
            local update_file = downloadUpdate(plugin_dir, remote)
            if not update_file then
                step_concluded()
                warn("Failed to download update file")
                UIManager:show(InfoMessage:new {
                    text = _("Failed to download update file.\nPlease check connection and try again."),
                })
                return
            end

            _async_update_step("Applying update…", step_concluded, function(step_concluded)
                dbg("Moving " .. plugin_dir .. " to " .. backup_dir)
                local ok = moveFile(plugin_dir, backup_dir)
                if not ok then
                    step_concluded()
                    warn("Failed to move old plugin directory")
                    UIManager:show(InfoMessage:new {
                        text = _("Failed to move the old plugin directory.\nCannot perform update automatically."),
                    })
                    return
                end
                lfs.mkdir(plugin_dir)
                dbg("Unpacking plugin archive " .. update_file .. " to " .. plugin_dir)
                local ok, err = Device:unpackArchive(update_file, plugin_dir, true)
                if not ok then
                    warn("Failed to extract update file", err)

                    _async_update_step("Something went wrong. Rolling back…", step_concluded, function(step_concluded)
                        local restoring = true
                        if lfs.attributes(plugin_dir) ~= nil then
                            dbg("[recovery] Purging", plugin_dir)
                            if not ffiUtil.purgeDir(plugin_dir) then restoring = false end
                        end
                        if restoring then
                            dbg("[recovery] Moving " .. backup_dir .. " to " .. plugin_dir)
                            restoring = moveFile(backup_dir, plugin_dir)
                        end
                        step_concluded()
                        local restored = restoring
                        local text = _("Failed to extract update file.\nCannot perform update automatically.\nCheck the update zip file inside plugins/ directory.")
                        if not restored then
                            text = text .. "\n\n" .. _("Failed to clean up intermediate plugins/ directories.\nPlease resolve situation by hand.")
                        end
                        UIManager:show(InfoMessage:new { text = text })
                    end)
                    return
                end

                _async_update_step("Verifying update integrity…", step_concluded, function(step_concluded)
                    local meta_file = plugin_dir .. "/_meta.lua"
                    if not lfs.attributes(meta_file) then
                        step_concluded()
                        warn("Plugin validation failed (no _meta.lua file found).")
                        UIManager:show(InfoMessage:new {
                            text = T(_("Failed to verify the patched update.\n\nPlease check plugins/ directory and resolve situation by hand."),
                                    err or "reason unknown"),
                        })
                        return
                    end
                    local new_meta = dofile(plugin_dir .. "/_meta.lua")
                    if new_meta.version ~= remote.version then
                        step_concluded()
                        warn("Updated plugin version mismatch. Got " .. new_meta.version .. ", expected " .. remote.version)
                        UIManager:show(InfoMessage:new {
                            text = T(_("Failed to verify the patched update (wrong version in _meta.lua).\n\nPlease check plugins/ directory and resolve situation by hand."),
                                    err or "reason unknown"),
                        })
                        return
                    end
                    meta = new_meta

                    _async_update_step("Post-update cleanup…", step_concluded, function(step_concluded)
                        dbg("[cleanup] Update extracted, purging old version", backup_dir)
                        local ok, err = ffiUtil.purgeDir(backup_dir)
                        if not ok then
                            step_concluded()
                            warn("Failed to remove old plugin dir", err)
                            UIManager:show(InfoMessage:new {
                                text = T(_("Failed to perform cleanup operation after patching the update:\n%1\n\nPlease check plugins/ directory and remove the '.backup' directory and zip file by hand."),
                                        err or "reason unknown"),
                            })
                            return
                        end
                        dbg("[cleanup] Removing plugin update archive", update_file)
                        local ok, err = os.remove(update_file)
                        if not ok then
                            step_concluded()
                            warn("Failed to remove plugin update file", err)
                            UIManager:show(InfoMessage:new {
                                text = T(_("Failed to perform cleanup operation after patching the update:\n%1\n\nPlease check plugins/ directory and remove the zip file by hand."),
                                        err or "reason unknown"),
                            })
                            return
                        end

                        step_concluded()
                        UIManager:askForRestart("Plugin updated successfully. To use the new version, the device must be restarted.")
                    end)
                end)
            end)
        end)
    end)
end

local function markCheckedAt(timestamp)
    dbg("AutoChecker: store latest checked at", timestamp)
    G_reader_settings:saveSetting(settingId .. ":checked_at", timestamp or time.now())
end

local function getAutoCheckThrottleDelayFts(throttle_duration_s)
    local last_check = G_reader_settings:readSetting(settingId .. ":checked_at")
    if not last_check then
        dbg("AutoChecker: no stored latest checked at found")
        return 0
    end
    local now = time.now()
    local elapsed_fts = now - last_check
    local interval_fts = time.s(throttle_duration_s)
    local diff_fts = interval_fts - elapsed_fts
    dbg("AutoChecker: found latest checked at; diff =", time.to_s(diff_fts), "seconds")
    return math.max(0, diff_fts)
end

--- Checks for updates.
---
--- @param args.silent boolean If true, don't show any notifications during the check for updates. E.g., use this for background checks.
--- @param args.failed_callback function Called with error string after an unsuccessful check (e.g., connection failed).
--- @param args.checked_callback function Called after a successful check. The passed boolean indicates if an update is available.
local function checkNow(args)
    if not args then args = {} end
    local silent = args.silent or false
    local failed_callback = args.failed_callback or function() end
    local checked_callback = args.checked_callback or function() end

    if not NetworkMgr:isWifiOn() then
        dbg("No wi-fi")
        if not silent then
            Notification:notify(_("Turn on Wi-Fi first."), Notification.SOURCE_DISPATCHER)
        end
        failed_callback("No Wi-Fi")
        return
    end
    if not NetworkMgr:isOnline() then
        dbg("Not online")
        if not silent then
            Notification:notify(_("No internet connection."), Notification.SOURCE_DISPATCHER)
        end
        failed_callback("Not online")
        return
    end

    _async_update_step((silent and {} or { "Checking for update…" })[1], function(step_concluded)
        local ok, remote = fetchRemoteMeta()
        if not ok then
            step_concluded()
            if not silent then
                Notification:notify(_("Failed to fetch plugin details."), Notification.SOURCE_DISPATCHER)
            end
            failed_callback("Fetch failed")
            return
        end
        if DEBUG_FORCE_UPDATE then
            dbg("Skipping version check due to debug flag.")
        else
            if remote.version == meta.version then
                dbg("Already on latest version. Remote:", remote.version, "Local:", meta.version)
                step_concluded()
                if not silent then
                    Notification:notify(T(_("You're already up to date (v%1)"), meta.version), Notification.SOURCE_DISPATCHER)
                end
                markCheckedAt()
                if auto_checker then auto_checker:reschedule() end
                checked_callback(false)
                return
            end
            dbg("Version mismatch; assuming update available. Remote:", remote.version, "Local:", meta.version)
        end
        step_concluded()
        markCheckedAt()
        checked_callback(true)
        UIManager:show(InfoMessage:new {
            show_icon = false,
            text = _("Plugin update available: ") .. remote.version .. "\n" .. remote.name .. "\n\n" .. remote.description,
            dismiss_callback = function()
                UIManager:show(ConfirmBox:new{
                    text = T(_("Update to %1 v%2 now?"), meta.fullname, remote.version),
                    ok_text = _("Update"),
                    ok_callback = function() perform_update(remote) end,
                })
            end
        })
    end)
end

local DURATION_SECOND = 1
local DURATION_MINUTE = DURATION_SECOND * 60
local DURATION_HOUR = DURATION_MINUTE * 60
local DURATION_DAY = DURATION_HOUR * 24
local DURATION_WEEK = DURATION_DAY * 7
local DURATION_4WEEKS = DURATION_WEEK * 4

local BACKOFF = {
    DURATION_SECOND * 20,
    DURATION_MINUTE,
    DURATION_MINUTE * 20,
    DURATION_HOUR * 2,
    DURATION_DAY,
}

local AutoChecker = EventListener:extend {
    min_seconds_between_checks = DURATION_WEEK,
    pause_while = nil,
    stopped = false,
    backoff_idx = 0,
    _scheduleId = 0,
}

function AutoChecker:free()
    self.stopped = true
    self.pause_while = nil
end

local function scheduleInOneMinute(cb)
    UIManager:scheduleIn(DURATION_MINUTE, cb)
end

local function parsePauseSchedulerFactory(fn)
    if not fn then return false end
    local result = fn()
    if not result then return false end
    if result == true then return scheduleInOneMinute end
    return result
end

function AutoChecker:_getPauseScheduler()
    if self.stopped then return nil end
    local res = parsePauseSchedulerFactory(self.pause_while)
    if res then return res, "local pause" end
    for idx, fn in ipairs(publicApi._pause_checks) do
        local res = parsePauseSchedulerFactory(fn)
        if res then return res, "global pause #" .. idx end
    end
    if Device.screen_saver_mode then return scheduleInOneMinute, "screensaver mode" end
    if Device.screen_saver_lock then return scheduleInOneMinute, "screensaver lock" end
    return nil
end

function AutoChecker:checkNow()
    if self.stopped then return end
    local rescheduleFn, reason = self:_getPauseScheduler()
    if rescheduleFn ~= nil then
        dbg("AutoChecker: paused due to " .. reason)
        rescheduleFn(function() self:scheduleWithNextWiFi() end)
        return
    end
    dbg("AutoChecker: check now")
    local _id = self._scheduleId
    checkNow({
        silent = true,
        failed_callback = function()
            if _id ~= self._scheduleId then return end
            self.backoff_idx = self.backoff_idx + 1
            local backoff = math.min(BACKOFF[self.backoff_idx] or DURATION_DAY, self.min_seconds_between_checks)
            dbg("AutoChecker: backoff retry due to failed fetch attempt [", backoff, "seconds]")
            self:scheduleIn(time.s(backoff))
        end,
    })
end

function AutoChecker:reschedule()
    self._scheduleId = self._scheduleId + 1
    self:schedule()
end

function AutoChecker:scheduleWithNextWiFi()
    if self.stopped then return end
    dbg("AutoChecker: schedule with next WiFi")
    if not NetworkMgr:isConnected() then self.backoff_idx = 0 end
    local _id = self._scheduleId
    NetworkMgr:runWhenConnected(function()
        if _id ~= self._scheduleId then return end
        self:checkNow()
    end)
end

function AutoChecker:scheduleIn(delay_fts)
    if self.stopped then return end
    local delay_s = time.to_s(delay_fts)
    dbg("AutoChecker: schedule in", delay_s, "seconds")
    local _id = self._scheduleId
    UIManager:scheduleIn(delay_s, function()
        if _id ~= self._scheduleId then return end
        self:scheduleWithNextWiFi()
    end)
end

function AutoChecker:schedule()
    self.backoff_idx = 0
    local delay_fts = getAutoCheckThrottleDelayFts(self.min_seconds_between_checks)
    if delay_fts > 0 then self:scheduleIn(delay_fts) else self:scheduleWithNextWiFi() end
end

--- Stops the background job started by `enableAutoChecks`.
local function disableAutoChecks()
    if not auto_checker then
        warn("Called disableAutoChecks() but none is running")
        return false
    end
    dbg("AutoChecker: Disable background check")
    auto_checker:free()
    auto_checker = nil
    return true
end

--- Starts a background job that silently checks for updates whenever connected
--- to Wi-Fi.
---
--- @param args.min_seconds_between_checks number The minimal duration to wait after a successful check before checking again.
--- @param args.pause_while function Optional function to suspend the background checker. If specified, the function may return `false` to indicate that checks may be run, `true` to indicate to ask again in 60 seconds, or a function that receives a callback to call when to ask again.
--- @param args.silent_override boolean Don't warn-log if already enabled.
local function enableAutoChecks(args)
    if not args then args = {} end
    local min_seconds_between_checks = args.min_seconds_between_checks or DURATION_WEEK
    local pause_while = args.pause_while or nil

    if auto_checker ~= nil then
        if not args.silent_override then
            warn("Called enableAutoChecks() while another background check is still enabled. Stopping old instance.")
        end
        disableAutoChecks()
    end
    dbg("AutoChecker: Enable background check each " .. min_seconds_between_checks .. " seconds.")
    auto_checker = AutoChecker:new {
        min_seconds_between_checks = min_seconds_between_checks,
        pause_while = pause_while,
    }
    auto_checker:schedule()
end

return {
    _settingId = settingId,

    DURATION_SECOND = DURATION_SECOND,
    DURATION_MINUTE = DURATION_MINUTE,
    DURATION_HOUR = DURATION_HOUR,
    DURATION_DAY = DURATION_DAY,
    DURATION_WEEK = DURATION_WEEK,
    DURATION_4WEEKS = DURATION_4WEEKS,

    checkNow = checkNow,
    enableAutoChecks = enableAutoChecks,
    disableAutoChecks = disableAutoChecks,
}
