-- AkiraUI bridge (AkiraUilib/Library.lua)
-- Loads the local AkiraUI.lua library and re-exposes the linoria-style API the
-- main script already uses (Window:AddTab, groupboxes, Toggles/Options, ...).
-- Replaces the previously embedded UE-LIB copy with zero changes to the script.

local HSRC_CANDIDATES = {
	'ui/AkiraUI.lua',
	'AkiraUI.lua',
	'AkiraUilib/AkiraUI.lua',
	'../ui/AkiraUI.lua',
}
local AkiraSource = nil
local libErr = 'no filesystem'
if readfile and isfile then
	for _, path in ipairs(HSRC_CANDIDATES) do
		local ok, exists = pcall(isfile, path)
		if ok and exists then
			local okRead, src = pcall(readfile, path)
			if okRead and type(src) == 'string' and #src > 100 then
				AkiraSource = src
				break
			end
		end
	end
	if not AkiraSource then
		libErr = 'ui/AkiraUI.lua not found in executor workspace'
	end
else
	libErr = 'readfile/isfile unavailable'
end
if not AkiraSource then
	error('[Akira Bridge] ' .. libErr)
end
local compile = loadstring or load
local chunk = assert(compile(AkiraSource, '@ui/AkiraUI.lua'), '[Akira Bridge] AkiraUI.lua failed to compile')
local H = chunk()
if type(H) ~= 'table' then
	error('[Akira Bridge] AkiraUI.lua did not return a Library table')
end

local UserInputService = game:GetService('UserInputService')
local Players = game:GetService('Players')
local Teams = game:GetService('Teams')

local Library = {}
setmetatable(Library, { __index = H })

Library.Toggles = {}
Library.Options = {}
Library.Flags = Library.Options
Library.Registry = {}
Library.HudRegistry = {}
Library.Signals = {}
Library.UnloadSignals = {}
Library.DependencyBoxes = {}
Library.Unloaded = false
Library.Toggled = false
Library.LayoutSuspended = false
Library.ConfigLoading = false
Library.NotifyOnError = false
Library.ShowCustomCursor = false
Library.ViewModels = {}
Library.MobileGui = nil
Library.KeybindFrame = nil
Library.ScreenGui = H._Instance
Library.Directory = 'akira'
Library.NotifyToggles = false
Library.FindWatermark = nil
Library.AccentColor = (H.Theme and H.Theme.Accent) or Color3.fromRGB(56, 130, 255)
Library.Font = (H.Font) and (H.Theme and H.Theme.TextColor) and Enum.Font.Code or (H.Font)
Library.FontSize = 14

if not Library.Watermark then
	Library.Watermark = { Text = 'Akira', Enabled = false }
end

Library.ToggleKeybind = {
	Value = H.MenuKey,
	Mode = 'Toggle',
	Changed = {},
}
do
	local function apply(code)
		Library.ToggleKeybind.Value = code
		H.MenuKey = code
		for _, cb in Library.ToggleKeybind.Changed do
			pcall(cb, code)
		end
	end
	Library.ToggleKeybind.SetKeybind = apply
	Library.ToggleKeybind.SetValue = function(_, code) apply(code) end
end

Library.Flags.MenuKeybind = { Value = H.MenuKey, Set = Library.ToggleKeybind.SetKeybind }

local Defaults = {}
local function TrackDefault(id, value)
	Defaults[id] = value
end

local function RegisterControl(tableRef, id, control)
	if not id then return control end
	tableRef[id] = control
	if not control.Get then
		control.Get = function() return control.Value end
	end
	return control
end

local function MakeOnChanged()
	local cbs = {}
	local changed = function(cb)
		cbs[#cbs + 1] = cb
		return cb
	end
	return changed, cbs
end

Library.ResetToFactoryDefaults = function()
	for id, def in Defaults do
		local c = Library.Toggles[id] or Library.Options[id]
		if c and type(c.SetValue) == 'function' then
			pcall(c.SetValue, c, def, true)
		end
	end
end

Library.ApplyConfig = function(config)
	if type(config) ~= 'table' then return end
	for id, val in pairs(config) do
		if type(id) == 'string' and id ~= '' and id:sub(1, 1) ~= '$' and id ~= 'MenuKeybind' then
			local c = Library.Toggles[id] or Library.Options[id]
			if c and type(c.SetValue) == 'function' then
				pcall(c.SetValue, c, val, true)
			end
		end
	end
end

local NotifyCbs = {}
Library.OnAccent = function(cb)
	NotifyCbs[#NotifyCbs + 1] = cb
end
Library.RegisterAccent = function(obj)
	return obj
end

Library.GiveSignal = function(self, conn)
	if type(conn) ~= 'table' or type(conn.Disconnect) ~= 'function' then
		return conn
	end
	Library.Signals[#Library.Signals + 1] = conn
	return conn
end

local origNotify = H.Notify
Library.Notify = function(self, a, b)
	if type(a) == 'table' then
		local text = a.Text or a.text or a.Description or a.desc or a.Content or a.content
		local title = a.Title or a.title
		local typ = a.Type or a.type
		local dur = a.Duration or a.duration or a.Time
		pcall(origNotify, H, {
			Title = tostring(title or 'Akira'),
			Text = tostring(text or ''),
			Type = tostring(typ or 'Info'),
			Duration = dur or 3,
		})
	else
		pcall(origNotify, H, {
			Title = 'Akira',
			Text = tostring(a or ''),
			Duration = b or 3,
		})
	end
end

Library.IsLayoutSuspended = function()
	return Library.LayoutSuspended == true
end
Library.SuspendLayout = function()
	Library.LayoutSuspended = true
end
Library.ResumeLayout = function()
	Library.LayoutSuspended = false
end

Library.GetTextBounds = function(self, Text, Font, Size, Resolution)
	local useFont = (((typeof(Font) == 'Font') and Enum.Font.Code) or Font or Enum.Font.Code)
	local bounds = game:GetService('TextService'):GetTextSize(
		tostring(Text or ''), Size or 14, useFont, Resolution or Vector2.new(1920, 1080))
	return bounds.X, bounds.Y
end

Library.Create = function(Class, Properties)
	local inst = Class
	if type(Class) == 'string' then inst = Instance.new(Class) end
	local parent = Properties and Properties.Parent
	for prop, val in pairs(Properties or {}) do
		if prop ~= 'Parent' then
			if prop == 'Font' and typeof(val) == 'Font' then
				inst.FontFace = val
			else
				pcall(function()
					inst[prop] = val
				end)
			end
		end
	end
	if parent ~= nil then inst.Parent = parent end
	return inst
end

Library.ClampGuiToViewport = function(self, element)
	if typeof(element) ~= 'Instance' then return end
	local vp = (workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize)
		or game:GetService('GuiService'):GetScreenResolution()
	local pos = element.AbsolutePosition
	local size = element.AbsoluteSize
	if size.X == 0 or size.Y == 0 then return end
	local clamped = Vector2.new(
		math.clamp(pos.X, 4, math.max(4, vp.X - size.X - 4)),
		math.clamp(pos.Y, 4, math.max(4, vp.Y - size.Y - 4)))
	element.Position = UDim2.fromOffset(math.round(clamped.X), math.round(clamped.Y))
end

Library.SetUIScale = function(scale)
	pcall(H.SetScale, H, tonumber(scale) or 1)
end

-- ------- window / page / groupbox facades -------

local WindowList = {}
local function MakeSectionFrom(entry, sectionArgs)
	local Sec = entry.Section(sectionArgs)
	return Sec
end

local function NormalizeKey(key)
	if key == nil then return nil end
	if key == 'None' then return nil end
	if typeof(key) == 'EnumItem' then return key end
	if typeof(key) == 'string' and Enum.KeyCode[key] then return Enum.KeyCode[key] end
	if type(key) == 'number' and Enum.KeyCode[key] then return Enum.KeyCode[key] end
	return key
end

local function BuildColorPickerOnLabel(label, id, opts)
	opts = opts or {}
	local userCb = opts.Callback
	local cbs = {}
	local suppressCb = false

	local fireCallback = function(...)
		if suppressCb then return end
		if type(userCb) == 'function' then pcall(userCb, ...) end
		for i = 1, #cbs do pcall(cbs[i], ...) end
	end

	local el = label:Colorpicker({
		Title = opts.Title or opts.Text or tostring(id),
		Color = opts.Default or opts.DefaultValue or Color3.fromRGB(255, 255, 255),
		Transparency = opts.Transparency or 0,
	})
	TrackDefault(id, el.Color)
	local ctrl = {
		Type = 'ColorPicker',
		Value = el.Color,
		Transparency = el.Transparency or 0,
		HasTransparency = true,
		OnChanged = function(cb) cbs[#cbs + 1] = cb end,
		AddColorPicker = function(self, pid, popts)
			return BuildColorPickerOnLabel(label, pid, popts)
		end,
		AddColorpicker = function(self, pid, popts)
			return BuildColorPickerOnLabel(label, pid, popts)
		end,
		SetValue = function(self, v, silent)
			if type(v) == 'number' then v = Color3.fromRGB(v, v, v) end
			if typeof(v) == 'Color3' then
				self.Value = v
				suppressCb = silent == true
				pcall(el.Set, v, self.Transparency or 0)
				suppressCb = false
				self.Value = el.Color or self.Value
				self.Transparency = el.Transparency or 0
			end
		end,
		SetValueRGB = function(self, v, transparent, silent)
			if type(v) == 'number' then v = Color3.fromRGB(v, v, v) end
			if typeof(v) == 'Color3' then
				self.Value = v
				self.Transparency = transparent or self.Transparency or 0
				suppressCb = silent == true
				pcall(el.Set, v, self.Transparency)
				suppressCb = false
				self.Value = el.Color or self.Value
				self.Transparency = el.Transparency or self.Transparency
			end
		end,
		Apply = function(self, c3) ctrl:SetValue(c3) end,
	}
	el.Callback = function(color, transp)
		ctrl.Value = el.Color or color
		ctrl.Transparency = el.Transparency or transp or 0
		fireCallback(ctrl.Value, ctrl.Transparency)
	end
	return RegisterControl(Library.Options, id, ctrl)
end

local function BuildControl(section, kind, id, opts)
	opts = opts or {}
	local userCb = opts.Callback
	local cbs = {}
	local suppressCb = false

	local function fireCallback(...)
		if suppressCb then return end
		if type(userCb) == 'function' then pcall(userCb, ...) end
		for i = 1, #cbs do pcall(cbs[i], ...) end
	end

	if kind == 'ColorPicker' or kind == 'Colorpicker' then
		local last = section.LastLabel
		if not last then error('[Akira Bridge] AddColorPicker requires a preceding AddLabel') end
		return BuildColorPickerOnLabel(last, id, opts)
	elseif kind == 'Toggle' then
		local L = section:Label({ Text = opts.Text or opts.Name or tostring(id) })
		local el = L:Toggle({ State = opts.Default == true })
		TrackDefault(id, opts.Default == true)
		local ctrl = {
			Type = 'Toggle',
			Value = el.State == true,
			Keybind = nil,
			Text = opts.Text or tostring(id),
			OnChanged = function(cb)
				cbs[#cbs + 1] = cb
			end,
			AddKeyPicker = function(self, pid, popts)
				ctrl.Keybind = BuildKeyPicker(L, pid, popts)
				return ctrl.Keybind
			end,
			AddColorPicker = function(self, pid, popts)
				return BuildColorPickerOnLabel(L, pid, popts)
			end,
			AddColorpicker = function(self, pid, popts)
				return BuildColorPickerOnLabel(L, pid, popts)
			end,
			SetValue = function(self, v, silent)
				self.Value = v == true
				suppressCb = silent == true
				pcall(el.Set, v == true, true)
				suppressCb = false
			end,
		}
		el.Callback = function(v)
			ctrl.Value = el.State == true
			fireCallback(ctrl.Value)
		end
		return RegisterControl(Library.Toggles, id, ctrl)
	elseif kind == 'Slider' then
		local el = section:Slider({
			Name = opts.Text or tostring(id),
			Suffix = opts.Suffix or opts.Unit or '',
			Value = opts.Default or 0,
			Increment = opts.Increment or ((opts.Max and opts.Min) and ((opts.Max - opts.Min) > 0 and (opts.Max - opts.Min) / 100 or 1) or 0.1),
			Max = opts.Max or 100,
			Min = opts.Min or 0,
		})
		TrackDefault(id, opts.Default or 0)
		local ctrl = {
			Type = 'Slider',
			Value = el.Value,
			OnChanged = function(cb) cbs[#cbs + 1] = cb end,
			GetValue = function() return el.Value end,
			SetValue = function(self, v, silent)
				if type(v) == 'string' then v = tonumber(v) or v end
				self.Value = v
				suppressCb = silent == true
				pcall(el.Set, v)
				suppressCb = false
				self.Value = el.Value
			end,
		}
		el.Callback = function(v)
			ctrl.Value = el.Value
			fireCallback(ctrl.Value)
		end
		return RegisterControl(Library.Options, id, ctrl)
	elseif kind == 'Dropdown' then
		local specialValues = opts.Values or {}
		if opts.SpecialType == 'Player' then
			specialValues = {}
			for _, plr in Players:GetPlayers() do
				specialValues[#specialValues + 1] = plr.Name
			end
			table.sort(specialValues, function(a, b) return a < b end)
		elseif opts.SpecialType == 'Team' then
			specialValues = {}
			for _, team in Teams:GetTeams() do
				specialValues[#specialValues + 1] = team.Name
			end
			table.sort(specialValues, function(a, b) return a < b end)
		end
		opts.Values = specialValues
		local initDefault = opts.Default
		if type(initDefault) == 'number' and type(specialValues[initDefault]) == 'string' then
			initDefault = specialValues[initDefault]
		end
		local el = section:Dropdown({
			Name = opts.Text or tostring(id),
			Options = specialValues,
			Value = initDefault,
			Multi = opts.Multi == true,
			Search = opts.Search == true,
		})
		TrackDefault(id, opts.Default)
		local ctrl = {
			Type = 'Dropdown',
			Value = el.Value,
			Multi = opts.Multi == true,
			Values = specialValues,
			SpecialType = opts.SpecialType,
			OnChanged = function(cb) cbs[#cbs + 1] = cb end,
			SetValues = function(self, list)
				ctrl.Values = list or {}
				pcall(el.UpdateOptions, ctrl.Values)
			end,
			UpdateOptions = function(self, list) ctrl:SetValues(list) end,
			SetValue = function(self, v, silent)
				if not opts.Multi and type(v) == 'number' and type(ctrl.Values[v]) == 'string' then
					v = ctrl.Values[v]
				end
				if opts.Multi then v = (type(v) == 'table') and v or { v } end
				if opts.Multi then
					for i = #v, 1, -1 do
						if type(v[i]) == 'number' and type(ctrl.Values[v[i]]) == 'string' then
							v[i] = ctrl.Values[v[i]]
						end
					end
				end
				self.Value = v
				suppressCb = silent == true
				pcall(el.Set, v)
				suppressCb = false
				self.Value = el.Value
			end,
		}
		el.Callback = function(v)
			ctrl.Value = el.Value
			fireCallback(ctrl.Value)
		end
		return RegisterControl(Library.Options, id, ctrl)
	elseif kind == 'Input' then
		local el = section:Input({
			Name = opts.Text or tostring(id),
			Value = opts.Default or '',
			Placeholder = opts.Placeholder or opts.Text or '',
		})
		TrackDefault(id, opts.Default or '')
		local ctrl = {
			Type = 'Input',
			Value = el.Value,
			OnChanged = function(cb) cbs[#cbs + 1] = cb end,
			SetValue = function(self, v, silent)
				self.Value = tostring(v or '')
				suppressCb = silent == true
				pcall(el.Set, self.Value)
				suppressCb = false
				self.Value = el.Value
			end,
		}
		el.Callback = function(v)
			ctrl.Value = el.Value
			fireCallback(ctrl.Value)
		end
		return RegisterControl(Library.Options, id, ctrl)
	else
		error('[Akira Bridge] Unknown control kind: ' .. tostring(kind))
	end
end

local function BuildKeyPicker(label, id, opts)
	opts = opts or {}
	local mode = opts.Mode or 'Toggle'
	if opts.SyncToggleState then mode = 'Toggle' end
	local kp = {
		Type = 'KeyPicker',
		Mode = mode,
		Toggled = false,
		Value = 'None',
		Key = nil,
		KeyCode = nil,
		Keybind = nil,
		SyncToggleState = opts.SyncToggleState == true,
		_onclick = {},
		Changed = {},
	}
	local constIsMenuKey = (id == 'MenuKeybind')
	local el = label:Keybind({
		Title = opts.Text or opts.Name or tostring(id),
		Type = (mode == 'Hold') and 'Hold' or 'Toggle',
		Callback = function(state)
			kp.Toggled = state == true
			for i = 1, #kp._onclick do pcall(kp._onclick[i], kp.Toggled) end
		end,
	})
	kp.Keybind = el

	local function syncFromEl()
		local key = el.Key
		kp.Key = key
		kp.KeyCode = key
		kp.Value = (key and (typeof(key) == 'EnumItem' and key.Name or tostring(key))) or 'None'
		kp.Mode = (el.Type == 'Hold') and 'Hold' or 'Toggle'
		if constIsMenuKey then
			H.MenuKey = key
		end
	end

	local origSet = el.Set
	el.Set = function(key, ...)
		origSet(key, ...)
		syncFromEl()
		if constIsMenuKey then
			Library.ToggleKeybind.Value = kp.Value
		end
		for _, cb in kp.Changed do pcall(cb, kp.Value) end
	end

	local origSetType = el.SetType
	el.SetType = function(selfOrType, maybeType)
		local newType = (type(selfOrType) == 'string') and selfOrType or maybeType
		origSetType(newType)
		kp.Mode = (el.Type == 'Hold') and 'Hold' or 'Toggle'
	end

	function kp.Update() syncFromEl() end

	function kp.OnClick(cb)
		kp._onclick[#kp._onclick + 1] = cb
		return function()
			for i = #kp._onclick, 1, -1 do
				if kp._onclick[i] == cb then table.remove(kp._onclick, i) end
			end
		end
	end

	function kp.SetKeybind(code)
		local key = NormalizeKey(code)
		pcall(el.Set, key)
		syncFromEl()
	end

	function kp.SetMode(newMode)
		if newMode == 'Always' then kp.Mode = 'Always' return end
		kp.Mode = (newMode == 'Hold') and 'Hold' or 'Toggle'
		pcall(el.SetType, kp.Mode)
		syncFromEl()
	end

	function kp.SetValue(a, silent)
		if type(a) == 'table' then
			local key, newMode = a[1], a[2]
			if key ~= nil then
				kp:SetKeybind(key)
			end
			if newMode ~= nil then
				kp:SetMode(newMode)
			end
			kp.Update()
			return
		end
		if silent ~= true then
			kp.Toggled = a == true
		end
	end

	function kp.GetState()
		if kp.Mode == 'Always' then return true end
		if kp.Mode == 'Hold' then
			local key = kp.Key
			if key == nil then return false end
			if typeof(key) == 'EnumItem' then
				if key.EnumType == Enum.KeyCode then
					return UserInputService:IsKeyDown(key)
				end
				return UserInputService:IsMouseDown(key)
			end
			return UserInputService:IsKeyDown(Enum.KeyCode[key]) or false
		end
		return kp.Toggled == true
	end

	function kp.Get() return kp.Value == 'None' and nil or kp.Value end
	function kp.GetKeybindName() return kp.Value end
	function kp.SetKeybindHolder() end

	if opts.Default ~= nil then
		kp:SetKeybind(opts.Default)
	end
	kp.Update()
	RegisterControl(Library.Options, id, kp)
	return kp
end

local ControlBuilders = {}
ControlBuilders.AddToggle = function(self, id, opts) return BuildControl(self.Section, 'Toggle', id, opts) end
ControlBuilders.AddSlider = function(self, id, opts) return BuildControl(self.Section, 'Slider', id, opts) end
ControlBuilders.AddDropdown = function(self, id, opts) return BuildControl(self.Section, 'Dropdown', id, opts) end
ControlBuilders.AddInput = function(self, id, opts) return BuildControl(self.Section, 'Input', id, opts) end
ControlBuilders.AddColorPicker = function(self, id, opts) return BuildControl(self.Section, 'ColorPicker', id, opts) end
ControlBuilders.AddKeyPicker = function(self, id, opts)
	if not self.Section.LastLabel then error('[Akira Bridge] AddKeyPicker requires a preceding AddLabel/AddToggle') end
	return BuildKeyPicker(self.Section.LastLabel, id, opts, nil)
end
ControlBuilders.AddLabel = function(self, text, opts)
	local txt = type(text) == 'string' and text or ((type(opts) == 'table' and (opts.Text or opts.Name)) or tostring(text or ''))
	local L = self.Section:Label({ Text = txt })
	self.Section.LastLabel = L
	if type(L.SetText) ~= 'function' then
		L.SetText = function(_, newText)
			L.Text = newText
			local container = L.LeftContent or L.Frame or L.LabelFrame
			if typeof(container) == 'Instance' then
				local tlabel = container:FindFirstChild('Label')
				if tlabel then
					tlabel.Text = newText
					tlabel.AutomaticSize = Enum.AutomaticSize.XY
				end
			end
		end
	end
	if type(L.AddColorPicker) ~= 'function' then
		L.AddColorPicker = function(_, pid, popts) return BuildColorPickerOnLabel(L, pid, popts) end
		L.AddColorpicker = L.AddColorPicker
		L.AddKeyPicker = function(_, pid, popts) return BuildKeyPicker(L, pid, popts) end
	end
	return L
end
ControlBuilders.AddParagraph = function(self, data)
	local title, body = '', ''
	if type(data) == 'string' then
		body = data
	elseif type(data) == 'table' then
		title = data.Title or ''
		body = data.Body or data.Text or ''
	end
	return self.Section:Paragraph({ Title = title, Body = body })
end
ControlBuilders.AddDivider = function(self)
	local L = self.Section:Label({ Text = '' })
	self.Section.LastLabel = L
	return L
end
ControlBuilders.AddButton = function(self, opts, secondCallback)
	local info = opts
	if type(info) ~= 'table' then
		info = { Text = opts }
		if type(secondCallback) == 'function' then info.Callback = secondCallback end
	end
	info = info or {}
	local el = self.Section:Button({
		Name = info.Text or info.Name or info.Title or 'Button',
		Callback = info.Callback or info.Func or function() end,
		DoubleClick = info.DoubleClick == true,
	})
	if type(el.AddButton) ~= 'function' then
		el.AddButton = function(_, opts2, cb2)
			return ControlBuilders.AddButton(self, opts2, cb2)
		end
	end
	return el
end

local function newDependencyBox(section)
	local frame = Instance.new('Frame')
	frame.Name = 'DependencyBox'
	frame.BackgroundTransparency = 1
	frame.BorderSizePixel = 0
	frame.Size = UDim2.fromScale(1, 0)
	frame.AutomaticSize = Enum.AutomaticSize.Y
	frame.LayoutOrder = 100
	frame.Parent = section.Content
	local deps = {}
	local fake = setmetatable({ Content = frame }, { __index = H.Elements })
	local box = setmetatable({}, { __index = ControlBuilders })
	box.Type = 'DependencyBox'
	box.Section = fake
	box.Content = frame
	box.Frame = frame
	box.SetupDependencies = function(self, list)
		deps = list or {}
		Library.DependencyBoxes[#Library.DependencyBoxes + 1] = box
		local function refresh()
			local show = true
			for _, dep in deps do
				local ctrl = dep[1]
				local want = dep[2]
				if ctrl and ctrl.Value ~= want then
					show = false
					break
				end
			end
			frame.Visible = show
		end
		for _, dep in deps do
			local ctrl = dep[1]
			if ctrl and type(ctrl.OnChanged) == 'function' then
				ctrl:OnChanged(refresh)
			end
		end
		refresh()
		return box
	end
	box.AddDependencyBox = function() return newDependencyBox(fake) end
	return box
end
ControlBuilders.AddDependencyBox = function(self)
	return newDependencyBox(self.Section)
end

local function MakePage(window, hwin, name, icon)
	local hp = hwin:Page({ Name = name, Icon = icon or 'folder' })
	local page = {
		Name = name,
		Icon = icon or 'folder',
		Section = nil,
		HP = hp,
		Window = window,
		IsOpen = false,
	}
	function page.MakeSide(side, groupName)
		local Sec = MakeSectionFrom(hp, { Name = groupName or '', Icon = 'player', Side = side })
		return setmetatable({ Section = Sec }, { __index = ControlBuilders })
	end
	function page.AddLeftGroupbox(self, groupName)
		return self.MakeSide('Left', groupName)
	end
	function page.AddRightGroupbox(self, groupName)
		return self.MakeSide('Right', groupName)
	end
	function page.AddGroupbox(self, groupName)
		return self.MakeSide('Left', groupName)
	end
	function page.MakeTabbox(side, boxName)
		local tb = {
			Name = boxName or '',
			Side = side,
			ParentPage = page,
			Tabs = {},
		}
		function tb.AddTab(self, tabName)
			local Sec = MakeSectionFrom(hp, { Name = tabName or '', Icon = 'folder', Side = side })
			local g = setmetatable({ Section = Sec, TabName = tabName }, { __index = ControlBuilders })
			tb.Tabs[#tb.Tabs + 1] = g
			return g
		end
		return tb
	end
	function page.AddLeftTabbox(self, boxName)
		return self.MakeTabbox('Left', boxName)
	end
	function page.AddRightTabbox(self, boxName)
		return self.MakeTabbox('Right', boxName)
	end
	function page.AddTab(self, tabName)
		return self.MakeTabbox('Left', tabName)
	end
	function page.Select(self)
		pcall(hp.Open, hp)
		page.IsOpen = true
	end
	window.Tabs[#window.Tabs + 1] = page
	window.Tabs[page.Name] = page
	window.Tabs[tostring(page.Name):lower()] = page
	return page
end

local function NewBridgeWindow(hwin, config)
	local canvas = hwin.Canvas or H._Instance:FindFirstChild('Canvas')
	local window = {
		Name = config.Title or 'Akira',
		Holder = canvas,
		Canvas = canvas,
		Pages = {},
		Tabs = {},
		PageButtons = (function()
			if canvas then
				local sidebar = canvas:FindFirstChild('Sidebar')
				return sidebar and sidebar:FindFirstChild('PageButtons')
			end
			return nil
		end)(),
		TabEditMode = false,
		hwin = hwin,
	}
	function window.AddTab(self, name, icon)
		return MakePage(window, hwin, name, icon)
	end
	function window.SelectTab(self, name)
		for _, p in window.Tabs do
			if p.Name == name then
				pcall(p.Select, p)
				return
			end
		end
	end
	function window.Toggle(self)
		local state = not Library.Toggled
		Library.Toggled = state
		H.MenuOpen = state
		if canvas then canvas.Visible = state end
		return state
	end
	function window.SetVisible(self, state)
		state = state == true
		Library.Toggled = state
		H.MenuOpen = state
		if canvas then canvas.Visible = state end
	end
	function window.IsMenuVisible(self)
		return canvas ~= nil and canvas.Visible == true
	end
	Library.Window = window
	WindowList[#WindowList + 1] = window
	if not H.MenuOpen then
		H.MenuOpen = config.AutoShow ~= false
	end
	if config.AutoShow ~= false then
		Library.Toggled = true
		if canvas then canvas.Visible = true end
	else
		Library.Toggled = false
		if canvas then canvas.Visible = false end
	end
	return setmetatable(window, { __index = hwin })
end

Library.CreateWindow = function(self, config)
	config = config or {}
	local title = config.Title or 'Akira'
	local hwin = H:Window({
		Title = title,
		Footer = config.Footer or '',
		Logo = config.Icon or config.Logo or nil,
	})
	if hwin and hwin.Canvas and typeof(config.Size) == 'UDim2' then
		pcall(function()
			hwin.Canvas.Size = config.Size
			if config.Center then
				hwin.Canvas.AnchorPoint = Vector2.new(0.5, 0.5)
				hwin.Canvas.Position = UDim2.fromScale(0.5, 0.5)
			end
		end)
	end
	local window = NewBridgeWindow(hwin, config)
	return window
end

Library.Toggle = function(self)
	if Library.Window then
		return Library.Window:Toggle()
	end
	pcall(H.ToggleMenu, H)
end

Library.SetVisible = function(self, state)
	if Library.Window then
		return Library.Window:SetVisible(state)
	end
	H.MenuOpen = state == true
	H.ToggleMenu(state == true)
end

Library.IsMenuVisible = function(self)
	if Library.Window then
		return Library.Window:IsMenuVisible()
	end
	return H.MenuOpen == true
end

function Library.ToggleMenu(self, state)
	if state == nil then
		state = not Library.Toggled
	end
	Library:SetVisible(state == true)
end

Library.SetMobileButtonEnabled = function(self, enabled)
	if enabled == true and type(self.EnsureMobileToggleButton) == 'function' then
		pcall(self.EnsureMobileToggleButton, self)
	end
	local gui = Library.MobileGui
	if typeof(gui) == 'Instance' then
		gui.Enabled = enabled == true
	end
end

Library.Unload = function(self)
	Library.Unloaded = true
	for i = #Library.Signals, 1, -1 do
		local conn = table.remove(Library.Signals, i)
		pcall(function()
			if conn and conn.Disconnect then conn:Disconnect() end
		end)
	end
	for i = #Library.UnloadSignals, 1, -1 do
		local conn = table.remove(Library.UnloadSignals, i)
		pcall(function()
			if conn and conn.Disconnect then conn:Disconnect() end
		end)
	end
	if type(H.Unload) == 'function' then
		pcall(H.Unload, H)
	end
end

Library.SafeCallback = function(callback, ...)
	local args = { ... }
	return function(...)
		pcall(callback, ...)
	end
end

Library.UpdateColorsUsingRegistry = function(self)
	for _, Object in next, Library.Registry do
		if typeof(Object) == 'Instance' then
			pcall(H.UpdateTheme, H, Library.CurrentRainbowColor)
		elseif type(Object) == 'table' and Object.Instance and Object.Properties then
			for Property, ColorIdx in next, Object.Properties do
				if type(ColorIdx) == 'string' then
					pcall(function() Object.Instance[Property] = Library[ColorIdx] end)
				elseif type(ColorIdx) == 'function' then
					pcall(function() Object.Instance[Property] = ColorIdx() end)
				end
			end
		end
	end
end

Library.OnUnload = function(self, cb)
	Library.OnUnload = cb
end

Library.CreateAccentPicker = function(section)
	return section:AddColorPicker('AccentColor', {
		Text = 'Accent',
		Default = (H.Theme and H.Theme.Accent) or Color3.fromRGB(56, 130, 255),
		Callback = function(color)
			if H.Theme then
				H.ApplyTheme({ Accent = color })
				for i = 1, #NotifyCbs do
					pcall(NotifyCbs[i], color)
				end
			end
		end,
	})
end

do
	local function wireInputFrame()
		if not Library.Toggled then return end
	end
end

return Library