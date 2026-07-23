--!nonstrict
-- Bar widget: thin client over the service status channel.
-- Hidden while idle; primary color + white glyph while sharing (visible
-- even without host capsule); click notifies apps.

local status = noctalia.state.get("status")
if type(status) ~= "table" then
	status = { sharing = false, apps = {}, count = 0 }
end

local hasTooltip = false

local function appsText(apps)
	if type(apps) ~= "table" or #apps == 0 then
		return noctalia.tr("notify.unknown-app")
	end
	return table.concat(apps, ", ")
end

local function clearTooltipSafe()
	if hasTooltip then
		barWidget.clearTooltip()
		hasTooltip = false
	end
end

local function render()
	local sharing = status.sharing == true
	local apps = appsText(status.apps)
	local glyph = noctalia.getConfig("glyph")
	if type(glyph) ~= "string" or glyph == "" then
		glyph = "screen-share"
	end

	barWidget.setVisible(sharing)
	if not sharing then
		clearTooltipSafe()
		return
	end

	barWidget.setGlyph(glyph)
	-- White glyph stays readable without capsule; "script" beats host icon_color.
	barWidget.setGlyphColor("#ffffff", "script")
	barWidget.setColor("primary", "script")
	barWidget.setText("")
	barWidget.setTooltip(noctalia.tr("tooltip.sharing", { apps = apps }))
	hasTooltip = true
end

noctalia.state.watch("status", function(value)
	if type(value) == "table" then
		status = value
	else
		status = { sharing = false, apps = {}, count = 0 }
	end
	render()
end)

function update()
	noctalia.setUpdateInterval(5000)
	render()
end

function onClick()
	if status.sharing ~= true then
		return
	end
	noctalia.notify(
		noctalia.tr("notify.sharing"),
		noctalia.tr("notify.apps", { apps = appsText(status.apps) })
	)
end

render()
