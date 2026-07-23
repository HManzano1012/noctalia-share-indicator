--!nonstrict
-- Headless service: poll pw-dump, detect portal / PipeWire screen-capture
-- sessions, publish { sharing, apps, count } on the plugin state channel.
-- Optional auto_dnd enables notification DND while sharing (ShareDND ownership).

noctalia.setUpdateInterval(1000)

local STOP_DEBOUNCE = 1.0

local dumping = false
local missingLogged = false
local lastKey = ""

local rawSharing = false
local sharingActive = false
local stopDeadline = nil
local dndSetByUs = false

local function cfgPollMs()
	local value = noctalia.getConfig("poll_ms")
	if type(value) ~= "number" then
		return 1000
	end
	if value < 250 then
		return 250
	end
	if value > 10000 then
		return 10000
	end
	return math.floor(value)
end

local function cfgAutoDnd()
	return noctalia.getConfig("auto_dnd") == true
end

local function propsOf(obj)
	local info = obj.info
	if type(info) ~= "table" then
		return nil
	end
	local props = info.props
	if type(props) ~= "table" then
		return nil
	end
	return props
end

local function prop(props, key)
	local value = props[key]
	if value == nil then
		return ""
	end
	return tostring(value)
end

local function isPortalApp(name)
	return string.find(string.lower(name), "xdg-desktop-portal", 1, true) ~= nil
end

local function isCameraNode(props)
	local role = string.lower(prop(props, "media.role"))
	if role == "camera" then
		return true
	end
	local name = string.lower(prop(props, "node.name"))
	if string.sub(name, 1, 5) == "v4l2_" then
		return true
	end
	local api = string.lower(prop(props, "device.api"))
	if api == "v4l2" then
		return true
	end
	return false
end

local function truthy(value)
	return value == true or value == 1 or value == "true" or value == "1"
end

local function isPortalSource(props)
	if isCameraNode(props) then
		return false
	end
	local app = prop(props, "application.name")
	local binary = prop(props, "application.process.binary")
	if isPortalApp(app) or isPortalApp(binary) then
		return true
	end
	if truthy(props["pipewire.access.portal.is_portal"]) then
		return true
	end
	return false
end

local function consumerLabel(props)
	local portalId = prop(props, "pipewire.access.portal.app_id")
	if portalId ~= "" then
		return portalId
	end
	local app = prop(props, "application.name")
	if app ~= "" and not isPortalApp(app) then
		return app
	end
	local binary = prop(props, "application.process.binary")
	if binary ~= "" and not isPortalApp(binary) then
		return binary
	end
	local nick = prop(props, "node.nick")
	if nick ~= "" then
		return nick
	end
	local desc = prop(props, "node.description")
	if desc ~= "" then
		return desc
	end
	local name = prop(props, "node.name")
	if name ~= "" then
		return name
	end
	return ""
end

local function addApp(apps, seen, label)
	if label == "" or seen[label] then
		return
	end
	seen[label] = true
	table.insert(apps, label)
end

local function detect(nodes)
	local apps = {}
	local seen = {}
	local sharing = false

	for _, obj in ipairs(nodes) do
		if obj.type == "PipeWire:Interface:Node" then
			local props = propsOf(obj)
			if props ~= nil then
				local mediaClass = prop(props, "media.class")

				if mediaClass == "Stream/Input/Video" and not isCameraNode(props) then
					sharing = true
					addApp(apps, seen, consumerLabel(props))
				elseif mediaClass == "Video/Source" and isPortalSource(props) then
					sharing = true
				end
			end
		end
	end

	return sharing, apps
end

local function publish(sharing, apps)
	local count = #apps
	local appsKey = table.concat(apps, ",")
	local key = `{if sharing then "1" else "0"}|{count}|{appsKey}`
	if key == lastKey then
		return
	end
	lastKey = key
	noctalia.state.set("status", {
		sharing = sharing,
		apps = apps,
		count = count,
	})
end

local function setDnd(on, cb)
	noctalia.runAsync("noctalia msg notification-dnd-set " .. (on and "on" or "off"), function(res)
		local ok = res ~= nil and res.exitCode == 0
		if not ok then
			noctalia.log("share-indicator: notification-dnd-set failed")
		end
		if cb then
			cb(ok)
		end
	end)
end

local function onSharingStarted()
	if not cfgAutoDnd() then
		return
	end
	noctalia.runAsync("noctalia msg notification-dnd-status", function(res)
		if not sharingActive or not cfgAutoDnd() then
			return
		end
		if res == nil or res.exitCode ~= 0 then
			noctalia.log("share-indicator: notification-dnd-status failed")
			return
		end
		if (res.stdout or ""):match("^%s*on") then
			dndSetByUs = false
			noctalia.log("share-indicator: sharing started, DND already on")
		else
			setDnd(true, function(ok)
				dndSetByUs = ok
				if ok then
					noctalia.log("share-indicator: sharing started, DND enabled")
					if not sharingActive or not cfgAutoDnd() then
						setDnd(false)
						dndSetByUs = false
					end
				end
			end)
		end
	end)
end

local function onSharingStopped()
	if dndSetByUs then
		setDnd(false)
		noctalia.log("share-indicator: sharing stopped, DND disabled")
	else
		noctalia.log("share-indicator: sharing stopped, DND left as-is")
	end
	dndSetByUs = false
end

local function applyDetected(sharing, apps)
	rawSharing = sharing

	if rawSharing then
		stopDeadline = nil
		if not sharingActive then
			sharingActive = true
			publish(true, apps)
			onSharingStarted()
		else
			publish(true, apps)
		end
	elseif sharingActive then
		if stopDeadline == nil then
			stopDeadline = os.clock() + STOP_DEBOUNCE
		end
	else
		publish(false, {})
	end
end

local function commitPendingStop()
	if stopDeadline == nil or os.clock() < stopDeadline then
		return
	end
	stopDeadline = nil
	if sharingActive and not rawSharing then
		sharingActive = false
		publish(false, {})
		onSharingStopped()
	end
end

local function parseDump(stdout)
	local data, err = noctalia.json.decode(stdout)
	if type(data) ~= "table" then
		noctalia.log(`share-indicator: pw-dump json decode failed: {err}`)
		return
	end

	local sharing, apps = detect(data)
	applyDetected(sharing, apps)
end

local function poll()
	if dumping then
		return
	end

	if not noctalia.commandExists("pw-dump") then
		if not missingLogged then
			missingLogged = true
			noctalia.log("share-indicator: pw-dump not found on PATH")
		end
		applyDetected(false, {})
		return
	end

	dumping = true
	local ok = noctalia.runAsync("pw-dump -i 0", function(result)
		dumping = false
		if result.timedOut then
			noctalia.log("share-indicator: pw-dump timed out")
			return
		end
		if result.exitCode ~= 0 then
			noctalia.log(`share-indicator: pw-dump exit {result.exitCode}`)
			return
		end
		if result.stdoutTruncated then
			noctalia.log("share-indicator: pw-dump stdout truncated; detection may be incomplete")
		end
		parseDump(result.stdout or "")
	end)

	if not ok then
		dumping = false
		noctalia.log("share-indicator: failed to launch pw-dump")
	end
end

function update()
	noctalia.setUpdateInterval(cfgPollMs())
	commitPendingStop()
	poll()
end

function onConfigChanged()
	noctalia.setUpdateInterval(cfgPollMs())
	if not cfgAutoDnd() then
		if dndSetByUs then
			setDnd(false)
			dndSetByUs = false
			noctalia.log("share-indicator: auto_dnd off, DND released")
		end
		return
	end
	if sharingActive and not dndSetByUs then
		onSharingStarted()
	end
end

function onIpc(event, _payload)
	if event == "refresh" then
		poll()
	else
		noctalia.log(`share-indicator: unknown ipc '{event}'`)
	end
end

function onExit(_signal)
	if dndSetByUs then
		noctalia.runAsync("noctalia msg notification-dnd-set off")
	end
end

publish(false, {})
