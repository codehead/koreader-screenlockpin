local _ = require("gettext")
local BD = require("ui/bidi")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")
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
local InfoMessage = require("ui/widget/infomessage")
local Notification = require("ui/widget/notification")
local T = ffiUtil.template

local DEBUG_FORCE_UPDATE = false
DEBUG_FORCE_UPDATE = true

local function getPluginDir()
    return debug.getinfo(1, "S").source:match("@(.+%.koplugin)/")
end

local function moveFile(src, dest)
    local mv_bin = Device:isAndroid() and "/system/bin/mv" or "/bin/mv"
    return ffiUtil.execute(mv_bin, src, dest) == 0
end

local meta = dofile(getPluginDir() .. "/_meta.lua")

local function fetchRemoteMeta()
    local sink = {}
    socketutil:set_timeout()
    local request = {
        url     = meta.update_url,
        method  = "GET",
        sink    = ltn12.sink.table(sink),
    }
    logger.dbg("ScreenLockPin: Calling", request.url)
    local code, headers, status = socket.skip(1, http.request(request))
    socketutil:reset_timeout()
    -- check network error
    if headers == nil then
        logger.warn("ScreenLockPin: Network unreachable", status or code or "unknown")
        return false
    end
    -- check HTTP error
    if code ~= 200 then
        logger.warn("ScreenLockPin: HTTP status unexpected:", status or code or "unknown")
        logger.dbg("ScreenLockPin: Response headers:", headers)
        return false
    end
    -- quick check content JSON format
    local content = table.concat(sink)
    if content == "" or content:sub(1, 1) ~= "{" then
        logger.warn("ScreenLockPin: Expected JSON response, got", content)
        return false
    end
    -- parse JSON
    local ok, data = pcall(JSON.decode, content, JSON.decode.simple)
    if not ok or not data then
        logger.warn("ScreenLockPin: Failed to parse JSON", data)
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
    local remote_zip_url = remote_zip_asset and remote_zip_asset.browser_download_url
    logger.dbg("ScreenLockPin: Latest upstream version:", data.name, remote_version, remote_zip_url, data.body)
    return true, {
        name = data.name,
        version = remote_version,
        description = data.body,
        zip_url = remote_zip_url,
    }
end

local function downloadFile(local_path, remote_url)
    logger.dbg("ScreenLockPin: Downloading file", local_path, "from", remote_url)
    socketutil:set_timeout(socketutil.FILE_BLOCK_TIMEOUT, socketutil.FILE_TOTAL_TIMEOUT)
    local code, headers, status = socket.skip(1, http.request {
        url      = remote_url,
        sink     = ltn12.sink.file(io.open(local_path, "w")),
    })
    socketutil:reset_timeout()
    if code ~= 200 then
        util.removeFile(local_path)
        logger.dbg("ScreenLockPin: Request failed:", status or code)
        logger.dbg("ScreenLockPin: Response headers:", headers)
        UIManager:show(InfoMessage:new {
            text = T(_("Could not save file to:\n%1\n%2"),
                    BD.filepath(local_path),
                    status or code or "network unreachable"),
        })
        return false
    end
    logger.dbg("ScreenLockPin: File downloaded to", local_path)
    return true
end

local function downloadUpdate(plugin_dir, remote)
    logger.dbg("ScreenLockPin: Downloading plugin update…")
    local local_target = plugin_dir .. "_" .. remote.version .. ".zip"
    if lfs.attributes(local_target) ~= nil then
        logger.warn("ScreenLockPin: Found update archive, re-using it…")
        Notification:notify(_("Update file present; skipping download."))
        return local_target
    end
    if downloadFile(local_target, remote.zip_url) then
        return local_target
    else
        return nil
    end
end

local function _async_update_step(msg, ...)
    local status_widget = InfoMessage:new { text = _(msg), dismissable = false }
    UIManager:show(status_widget, "ui")
    local step_concluded = function() UIManager:close(status_widget, "ui") end
    local run_fns = table.pack(...)
    UIManager:nextTick(function()
        for _, run in ipairs(run_fns) do run(step_concluded) end
    end)
end

local function perform_update(remote)
    _async_update_step("Preparing for update…", function(step_concluded)
        local plugin_dir = getPluginDir()
        if not plugin_dir then
            step_concluded()
            logger.warn("ScreenLockPin: Failed to detect plugin root")
            UIManager:show(InfoMessage:new {
                text = _("Failed to detect plugin root.\nCannot perform update automatically."),
            })
            return
        end
        local bak_dir = plugin_dir .. ".old"
        logger.dbg("ScreenLockPin: Detected plugin dir", plugin_dir)
        if lfs.attributes(bak_dir) ~= nil then
            step_concluded()
            logger.warn("ScreenLockPin: Path already exists: " .. bak_dir)
            UIManager:show(InfoMessage:new {
                text = _("Path already exists: " .. bak_dir .. "\nMaybe an incomplete update beforehand?\nPlease resolve situation by hand."),
            })
            return
        end

        _async_update_step("Downloading…", step_concluded, function(step_concluded)
            local update_file = downloadUpdate(plugin_dir, remote)
            if not update_file then
                step_concluded()
                logger.warn("ScreenLockPin: Failed to download update file")
                UIManager:show(InfoMessage:new {
                    text = _("Failed to download update file.\nPlease check connection and try again."),
                })
                return
            end

            _async_update_step("Applying update…", step_concluded, function(step_concluded)
                logger.dbg("ScreenLockPin: Moving " .. plugin_dir .. " to " .. bak_dir)
                local ok = moveFile(plugin_dir, bak_dir)
                if not ok then
                    step_concluded()
                    logger.warn("ScreenLockPin: Failed to move old plugin directory")
                    UIManager:show(InfoMessage:new {
                        text = _("Failed to move the old plugin directory.\nCannot perform update automatically."),
                    })
                    return
                end
                lfs.mkdir(plugin_dir)
                logger.dbg("ScreenLockPin: Unpacking plugin archive " .. update_file .. " to " .. plugin_dir)
                local ok, err = Device:unpackArchive(update_file, plugin_dir, true)
                if not ok then
                    logger.warn("ScreenLockPin: Failed to extract update file", err)

                    _async_update_step("Something went wrong. Rolling back…", step_concluded, function(step_concluded)
                        local restoring = true
                        if lfs.attributes(plugin_dir) ~= nil then
                            logger.dbg("ScreenLockPin: [recovery] Purging", plugin_dir)
                            if not ffiUtil.purgeDir(plugin_dir) then restoring = false end
                        end
                        if restoring then
                            logger.dbg("ScreenLockPin: [recovery] Moving " .. bak_dir .. " to " .. plugin_dir)
                            restoring = moveFile(bak_dir, plugin_dir)
                        end
                        step_concluded()
                        local restored = restoring
                        local text = _("Failed to extract update file.\nCannot perform update automatically.")
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
                        logger.warn("ScreenLockPin: Plugin validation failed (no _meta.lua file found).")
                        UIManager:show(InfoMessage:new {
                            text = T(_("Failed to verify the patched update.\n\nPlease check plugins/ directory and resolve situation by hand."),
                                    err or "reason unknown"),
                        })
                        return
                    end
                    local new_meta = dofile(plugin_dir .. "/_meta.lua")
                    if new_meta.version ~= remote.version then
                        step_concluded()
                        logger.warn("ScreenLockPin: Updated plugin version mismatch. Got " .. new_meta.version .. ", expected " .. remote.version)
                        UIManager:show(InfoMessage:new {
                            text = T(_("Failed to verify the patched update (wrong version in _meta.lua).\n\nPlease check plugins/ directory and resolve situation by hand."),
                                    err or "reason unknown"),
                        })
                        return
                    end
                    meta = new_meta

                    _async_update_step("Post-update cleanup…", step_concluded, function(step_concluded)
                        logger.dbg("ScreenLockPin: [cleanup] Update extracted, purging old version", bak_dir)
                        local ok, err = ffiUtil.purgeDir(bak_dir)
                        if not ok then
                            step_concluded()
                            logger.warn("ScreenLockPin: Failed to remove old plugin dir", err)
                            UIManager:show(InfoMessage:new {
                                text = T(_("Failed to perform cleanup operation after patching the update:\n%1\n\nPlease check plugins/ directory and remove the '.old' directory and zip file by hand."),
                                        err or "reason unknown"),
                            })
                            return
                        end
                        logger.dbg("ScreenLockPin: [cleanup] Removing plugin update archive", update_file)
                        local ok, err = os.remove(update_file)
                        if not ok then
                            step_concluded()
                            logger.warn("ScreenLockPin: Failed to remove plugin update file", err)
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

local function checkNow()
    if not NetworkMgr:isWifiOn() then
        Notification:notify(_("Turn on Wi-Fi first."))
        return
    end
    if not NetworkMgr:isOnline() then
        Notification:notify(_("No internet connection."))
        return
    end

    _async_update_step("Checking for update…", function(step_concluded)
        local ok, remote = fetchRemoteMeta()
        if not ok then
            step_concluded()
            Notification:notify(_("Failed to fetch plugin details."))
            return
        end
        if not DEBUG_FORCE_UPDATE and remote.version == meta.version then
            step_concluded()
            Notification:notify(_("You're already up to date."), Notification.SOURCE_DISPATCHER)
            return
        end
        step_concluded()
        UIManager:show(InfoMessage:new {
            show_icon = false,
            text = _("Plugin update available: ") .. remote.version .. "\n" .. remote.name .. "\n\n" .. remote.description,
            dismiss_callback = function()
                UIManager:show(ConfirmBox:new{
                    text = T(_("Update to ScreenLockPin v%1 now?"), remote.version),
                    ok_text = _("Update"),
                    ok_callback = function() perform_update(remote) end,
                })
            end
        })
    end)
end

return { checkNow = checkNow }
