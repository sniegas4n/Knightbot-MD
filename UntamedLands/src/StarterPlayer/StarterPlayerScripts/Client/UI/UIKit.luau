--!nonstrict
--[[
	UIKit
	Location : StarterPlayer/StarterPlayerScripts/Client/UI/UIKit (ModuleScript)
	Purpose  : Tiny helpers for building UI from code, plus the game's visual
	           identity (palette + fonts): dark weathered leather panels, bone
	           text, rust accents.
	           UI is built in code (not hand-placed in StarterGui) so it lives
	           in version control and can be reviewed and diffed like any script.
	Depends  : nothing
]]

local UIKit = {}

UIKit.Colors = {
	Backdrop = Color3.fromRGB(14, 12, 10),
	Panel = Color3.fromRGB(30, 26, 22),
	PanelLight = Color3.fromRGB(48, 41, 34),
	Border = Color3.fromRGB(92, 76, 58),
	Text = Color3.fromRGB(226, 214, 190),
	TextDim = Color3.fromRGB(158, 146, 126),
	Accent = Color3.fromRGB(176, 88, 46),
	AccentBright = Color3.fromRGB(214, 120, 64),
	Health = Color3.fromRGB(160, 46, 38),
	Stamina = Color3.fromRGB(204, 158, 62),
	Good = Color3.fromRGB(132, 168, 92),
	Bad = Color3.fromRGB(200, 70, 56),
}

UIKit.Fonts = {
	Title = Enum.Font.Oswald,
	Body = Enum.Font.GothamMedium,
	Bold = Enum.Font.GothamBold,
}

function UIKit.create(className, props, children)
	local instance = Instance.new(className)
	local parent = nil
	for key, value in pairs(props or {}) do
		if key == "Parent" then
			parent = value
		else
			instance[key] = value
		end
	end
	for _, child in ipairs(children or {}) do
		child.Parent = instance
	end
	if parent then
		instance.Parent = parent
	end
	return instance
end

function UIKit.corner(radius)
	return UIKit.create("UICorner", { CornerRadius = UDim.new(0, radius or 6) })
end

function UIKit.stroke(color, thickness, transparency)
	return UIKit.create("UIStroke", {
		Color = color or UIKit.Colors.Border,
		Thickness = thickness or 1,
		Transparency = transparency or 0,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	})
end

function UIKit.padding(pixels)
	local p = UDim.new(0, pixels)
	return UIKit.create("UIPadding", { PaddingTop = p, PaddingBottom = p, PaddingLeft = p, PaddingRight = p })
end

function UIKit.label(props)
	local defaults = {
		BackgroundTransparency = 1,
		Font = UIKit.Fonts.Body,
		TextColor3 = UIKit.Colors.Text,
		TextSize = 16,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextWrapped = true,
	}
	for key, value in pairs(props or {}) do
		defaults[key] = value
	end
	return UIKit.create("TextLabel", defaults)
end

function UIKit.button(text, props)
	local defaults = {
		Text = text,
		AutoButtonColor = true,
		BackgroundColor3 = UIKit.Colors.PanelLight,
		Font = UIKit.Fonts.Bold,
		TextColor3 = UIKit.Colors.Text,
		TextSize = 16,
	}
	for key, value in pairs(props or {}) do
		defaults[key] = value
	end
	return UIKit.create("TextButton", defaults, { UIKit.corner(4), UIKit.stroke() })
end

-- Returns frame, fill. Set fill.Size = UDim2.fromScale(fraction, 1) to update.
function UIKit.bar(props, fillColor)
	local frame = UIKit.create("Frame", {
		BackgroundColor3 = UIKit.Colors.Backdrop,
		BackgroundTransparency = 0.2,
		BorderSizePixel = 0,
	}, { UIKit.corner(3), UIKit.stroke(UIKit.Colors.Border, 1, 0.3) })
	for key, value in pairs(props or {}) do
		frame[key] = value
	end
	local fill = UIKit.create("Frame", {
		Name = "Fill",
		BackgroundColor3 = fillColor,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		Parent = frame,
	}, { UIKit.corner(3) })
	return frame, fill
end

return UIKit
