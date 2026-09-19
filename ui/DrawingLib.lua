--[[
    Hydra Drawing Library (DrawingLib)
    High-performance, object-pooled Drawing API wrapper for Roblox scripts.
    Provides fast, zero-allocation rendering primitives for ESP, FOV, Crosshair, and visual indicators.
--]]

local DrawingLib = {
    Version = "1.1.0",
    DrawingSupported = (type(Drawing) == 'table' and type(Drawing.new) == 'function'),
    Pool = {
        Line = {},
        Square = {},
        Circle = {},
        Text = {},
        Triangle = {},
    },
    ActiveObjects = setmetatable({}, { __mode = 'k' }),
}

-- Fallback dummy object for environments where Drawing is not supported
local function CreateDummyObject(kind)
    local dummy = {
        Visible = false,
        ZIndex = 1,
        Transparency = 1,
        Color = Color3.new(1, 1, 1),
        Destroy = function() end,
        Remove = function() end,
    }
    if kind == 'Line' then
        dummy.From = Vector2.zero
        dummy.To = Vector2.zero
        dummy.Thickness = 1
    elseif kind == 'Square' then
        dummy.Position = Vector2.zero
        dummy.Size = Vector2.zero
        dummy.Thickness = 1
        dummy.Filled = false
    elseif kind == 'Circle' then
        dummy.Position = Vector2.zero
        dummy.Radius = 0
        dummy.Thickness = 1
        dummy.Filled = false
        dummy.NumSides = 64
    elseif kind == 'Text' then
        dummy.Text = ""
        dummy.Size = 14
        dummy.Center = false
        dummy.Outline = false
        dummy.OutlineColor = Color3.new(0, 0, 0)
        dummy.Position = Vector2.zero
        dummy.Font = 2
    elseif kind == 'Triangle' then
        dummy.PointA = Vector2.zero
        dummy.PointB = Vector2.zero
        dummy.PointC = Vector2.zero
        dummy.Thickness = 1
        dummy.Filled = false
    end
    return dummy
end

function DrawingLib.IsSupported()
    return DrawingLib.DrawingSupported
end

-- Acquire a drawing object from the pool or allocate a new one
function DrawingLib.New(kind, properties)
    if not DrawingLib.DrawingSupported then
        return CreateDummyObject(kind)
    end

    local pool = DrawingLib.Pool[kind]
    local obj = nil

    if pool and #pool > 0 then
        obj = table.remove(pool)
    else
        local ok, res = pcall(Drawing.new, kind)
        if ok and res then
            obj = res
        else
            return CreateDummyObject(kind)
        end
    end

    if obj then
        pcall(function()
            obj.Visible = false
            if properties then
                for prop, val in pairs(properties) do
                    obj[prop] = val
                end
            end
        end)
        DrawingLib.ActiveObjects[obj] = kind
    end

    return obj
end

-- Release a drawing object back to the pool for reuse
function DrawingLib.Release(obj, kind)
    if not obj or typeof(obj) == 'Instance' then
        return
    end

    pcall(function()
        obj.Visible = false
    end)

    local targetKind = kind or DrawingLib.ActiveObjects[obj]
    local pool = targetKind and DrawingLib.Pool[targetKind]

    if pool then
        table.insert(pool, obj)
        DrawingLib.ActiveObjects[obj] = nil
    else
        if type(obj.Remove) == 'function' then
            pcall(function() obj:Remove() end)
        end
    end
end

-- Destroy all pooled and active objects
function DrawingLib.ClearAll()
    for _, pool in pairs(DrawingLib.Pool) do
        for _, obj in ipairs(pool) do
            if type(obj.Remove) == 'function' then
                pcall(function() obj:Remove() end)
            end
        end
        table.clear(pool)
    end
    for obj in pairs(DrawingLib.ActiveObjects) do
        if type(obj.Remove) == 'function' then
            pcall(function() obj:Remove() end)
        end
    end
    table.clear(DrawingLib.ActiveObjects)
end

-- ========================================================================
-- HIGH-LEVEL COMPOSITE ESP STRUCTURES (POOLED)
-- ========================================================================

-- 2D Box with Outer, Main, and Inner layers
function DrawingLib.CreateBox2D()
    local box = {
        Outline = DrawingLib.New('Square', { Thickness = 3, Filled = false, Color = Color3.new(0, 0, 0), Visible = false }),
        Main = DrawingLib.New('Square', { Thickness = 1, Filled = false, Color = Color3.fromRGB(0, 255, 100), Visible = false }),
        Inline = DrawingLib.New('Square', { Thickness = 1, Filled = false, Color = Color3.new(0, 0, 0), Visible = false }),
        Fill = DrawingLib.New('Square', { Thickness = 0, Filled = true, Color = Color3.fromRGB(0, 255, 100), Transparency = 0.2, Visible = false }),
    }

    function box:Update(pos, size, color, fillTransparency, showFill)
        self.Outline.Position = pos - Vector2.new(1, 1)
        self.Outline.Size = size + Vector2.new(2, 2)
        self.Outline.Visible = true

        self.Main.Position = pos
        self.Main.Size = size
        self.Main.Color = color
        self.Main.Visible = true

        self.Inline.Position = pos + Vector2.new(1, 1)
        self.Inline.Size = size - Vector2.new(2, 2)
        self.Inline.Visible = true

        if showFill then
            self.Fill.Position = pos
            self.Fill.Size = size
            self.Fill.Color = color
            self.Fill.Transparency = fillTransparency or 0.2
            self.Fill.Visible = true
        else
            self.Fill.Visible = false
        end
    end

    function box:SetVisible(vis)
        self.Outline.Visible = vis
        self.Main.Visible = vis
        self.Inline.Visible = vis
        self.Fill.Visible = vis and self.Fill.Visible
    end

    function box:Release()
        DrawingLib.Release(self.Outline, 'Square')
        DrawingLib.Release(self.Main, 'Square')
        DrawingLib.Release(self.Inline, 'Square')
        DrawingLib.Release(self.Fill, 'Square')
    end

    return box
end

-- 8-Segment Corner Box (Fast, Modern ESP Box)
function DrawingLib.CreateCornerBox()
    local lines = table.create(8)
    for i = 1, 8 do
        lines[i] = DrawingLib.New('Line', { Thickness = 1, Color = Color3.fromRGB(0, 255, 100), Visible = false })
    end

    local cornerBox = {
        Lines = lines,
    }

    function cornerBox:Update(x, y, w, h, cornerLen, color, thickness)
        local cLen = cornerLen or math.min(w, h) * 0.25
        local th = thickness or 1

        -- Top-Left
        lines[1].From = Vector2.new(x, y); lines[1].To = Vector2.new(x + cLen, y)
        lines[2].From = Vector2.new(x, y); lines[2].To = Vector2.new(x, y + cLen)
        -- Top-Right
        lines[3].From = Vector2.new(x + w, y); lines[3].To = Vector2.new(x + w - cLen, y)
        lines[4].From = Vector2.new(x + w, y); lines[4].To = Vector2.new(x + w, y + cLen)
        -- Bottom-Left
        lines[5].From = Vector2.new(x, y + h); lines[5].To = Vector2.new(x + cLen, y + h)
        lines[6].From = Vector2.new(x, y + h); lines[6].To = Vector2.new(x, y + h - cLen)
        -- Bottom-Right
        lines[7].From = Vector2.new(x + w, y + h); lines[7].To = Vector2.new(x + w - cLen, y + h)
        lines[8].From = Vector2.new(x + w, y + h); lines[8].To = Vector2.new(x + w, y + h - cLen)

        for i = 1, 8 do
            lines[i].Color = color
            lines[i].Thickness = th
            lines[i].Visible = true
        end
    end

    function cornerBox:SetVisible(vis)
        for i = 1, 8 do
            lines[i].Visible = vis
        end
    end

    function cornerBox:Release()
        for i = 1, 8 do
            DrawingLib.Release(lines[i], 'Line')
        end
    end

    return cornerBox
end

-- Health Bar with background and value text
function DrawingLib.CreateHealthBar()
    local bar = {
        Bg = DrawingLib.New('Square', { Thickness = 1, Filled = true, Color = Color3.fromRGB(20, 20, 20), Visible = false }),
        Fill = DrawingLib.New('Square', { Thickness = 1, Filled = true, Color = Color3.fromRGB(0, 255, 0), Visible = false }),
        Text = DrawingLib.New('Text', { Size = 12, Outline = true, Color = Color3.new(1, 1, 1), Visible = false }),
    }

    function bar:Update(x, y, w, h, hpFraction, showText, hpTextValue)
        hpFraction = math.clamp(hpFraction, 0, 1)

        self.Bg.Position = Vector2.new(x, y)
        self.Bg.Size = Vector2.new(w, h)
        self.Bg.Visible = true

        local fillH = math.floor(h * hpFraction)
        self.Fill.Position = Vector2.new(x, y + h - fillH)
        self.Fill.Size = Vector2.new(w, fillH)

        -- Health gradient from Green -> Yellow -> Red
        local r = hpFraction < 0.5 and 1 or (1 - hpFraction) * 2
        local g = hpFraction > 0.5 and 1 or hpFraction * 2
        self.Fill.Color = Color3.new(r, g, 0)
        self.Fill.Visible = true

        if showText and hpFraction < 0.99 then
            self.Text.Position = Vector2.new(x - 2, y + h - fillH - 6)
            self.Text.Text = hpTextValue or tostring(math.floor(hpFraction * 100))
            self.Text.Visible = true
        else
            self.Text.Visible = false
        end
    end

    function bar:SetVisible(vis)
        self.Bg.Visible = vis
        self.Fill.Visible = vis
        self.Text.Visible = vis and self.Text.Visible
    end

    function bar:Release()
        DrawingLib.Release(self.Bg, 'Square')
        DrawingLib.Release(self.Fill, 'Square')
        DrawingLib.Release(self.Text, 'Text')
    end

    return bar
end

-- Smooth Multi-Ring FOV Circle (64-sided polygon)
function DrawingLib.CreateFovCircle()
    local fov = {
        Fill = DrawingLib.New('Circle', { Filled = true, NumSides = 64, Visible = false }),
        Outline = DrawingLib.New('Circle', { Filled = false, Thickness = 1, NumSides = 64, Visible = false }),
        Glow1 = DrawingLib.New('Circle', { Filled = false, Thickness = 2, NumSides = 64, Visible = false }),
        Glow2 = DrawingLib.New('Circle', { Filled = false, Thickness = 3, NumSides = 64, Visible = false }),
    }

    function fov:Update(center, radius, color, transparency, filled, showGlow)
        self.Outline.Position = center
        self.Outline.Radius = radius
        self.Outline.Color = color
        self.Outline.Transparency = transparency or 1
        self.Outline.Visible = true

        if filled then
            self.Fill.Position = center
            self.Fill.Radius = radius
            self.Fill.Color = color
            self.Fill.Transparency = (transparency or 1) * 0.15
            self.Fill.Visible = true
        else
            self.Fill.Visible = false
        end

        if showGlow then
            self.Glow1.Position = center
            self.Glow1.Radius = radius + 1
            self.Glow1.Color = color
            self.Glow1.Transparency = (transparency or 1) * 0.4
            self.Glow1.Visible = true

            self.Glow2.Position = center
            self.Glow2.Radius = radius + 2
            self.Glow2.Color = color
            self.Glow2.Transparency = (transparency or 1) * 0.2
            self.Glow2.Visible = true
        else
            self.Glow1.Visible = false
            self.Glow2.Visible = false
        end
    end

    function fov:SetVisible(vis)
        self.Outline.Visible = vis
        self.Fill.Visible = vis and self.Fill.Visible
        self.Glow1.Visible = vis and self.Glow1.Visible
        self.Glow2.Visible = vis and self.Glow2.Visible
    end

    function fov:Release()
        DrawingLib.Release(self.Fill, 'Circle')
        DrawingLib.Release(self.Outline, 'Circle')
        DrawingLib.Release(self.Glow1, 'Circle')
        DrawingLib.Release(self.Glow2, 'Circle')
    end

    return fov
end

-- Offscreen Indicator Arrow (3-line triangle)
function DrawingLib.CreateArrow()
    local arrow = {
        Left = DrawingLib.New('Line', { Thickness = 2, Visible = false }),
        Right = DrawingLib.New('Line', { Thickness = 2, Visible = false }),
        Base = DrawingLib.New('Line', { Thickness = 2, Visible = false }),
    }

    function arrow:Update(screenPos, dirVector, size, color, thickness)
        local normal = Vector2.new(-dirVector.Y, dirVector.X)
        local tip = screenPos + dirVector * (size * 1.4)
        local leftPt = screenPos - dirVector * (size * 0.6) + normal * (size * 0.8)
        local rightPt = screenPos - dirVector * (size * 0.6) - normal * (size * 0.8)

        local th = thickness or 2
        for _, seg in pairs({ self.Left, self.Right, self.Base }) do
            seg.Color = color
            seg.Thickness = th
            seg.Visible = true
        end

        self.Left.From = leftPt; self.Left.To = tip
        self.Right.From = rightPt; self.Right.To = tip
        self.Base.From = leftPt; self.Base.To = rightPt
    end

    function arrow:SetVisible(vis)
        self.Left.Visible = vis
        self.Right.Visible = vis
        self.Base.Visible = vis
    end

    function arrow:Release()
        DrawingLib.Release(self.Left, 'Line')
        DrawingLib.Release(self.Right, 'Line')
        DrawingLib.Release(self.Base, 'Line')
    end

    return arrow
end

return DrawingLib
