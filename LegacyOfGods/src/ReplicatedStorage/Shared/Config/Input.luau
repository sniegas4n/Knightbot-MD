--[[
	Config.Input (ModuleScript)
	Emplacement : ReplicatedStorage > Shared > Config > Input

	Toutes les touches du jeu. Les contrôleurs clients lisent UNIQUEMENT
	cette table : un futur menu de remappage n'aura qu'à la surcharger.

	⚠ Claviers AZERTY : Z et Q (compétence 1 / esquive) sont aussi des
	touches de déplacement courantes (ZQSD). Le remappage est prévu.

	Touch = configuration du bouton tactile (ContextActionService).
	Position en UDim2, relative au cadre des boutons tactiles de Roblox.
	TouchMode = "Hold" (maintenir) ou "Toggle" (appui = bascule).
]]

return {
	Actions = {
		Sprint = {
			Keyboard = { Enum.KeyCode.LeftShift, Enum.KeyCode.RightShift },
			Gamepad = { Enum.KeyCode.ButtonL3 },
			KeyboardMode = "Hold",
			GamepadMode = "Toggle",
			Touch = { Enabled = true, Title = "Sprint", Position = UDim2.new(1, -170, 1, -70), Mode = "Toggle" },
		},
		Dodge = {
			Keyboard = { Enum.KeyCode.Q },
			Gamepad = { Enum.KeyCode.ButtonB },
			Touch = { Enabled = true, Title = "Esquive", Position = UDim2.new(1, -95, 1, -150) },
		},

		-- Réservées pour la Phase 1-B (combat). Déclarées ici pour que le HUD
		-- affiche déjà les bons raccourcis.
		LightAttack = { Keyboard = { Enum.UserInputType.MouseButton1 }, Gamepad = { Enum.KeyCode.ButtonR2 } },
		HeavyAttack = { Keyboard = { Enum.KeyCode.R }, Gamepad = { Enum.KeyCode.ButtonY } },
		Skill1 = { Keyboard = { Enum.KeyCode.Z }, Gamepad = { Enum.KeyCode.ButtonX }, Label = "Z" },
		Skill2 = { Keyboard = { Enum.KeyCode.X }, Gamepad = { Enum.KeyCode.DPadLeft }, Label = "X" },
		Skill3 = { Keyboard = { Enum.KeyCode.C }, Gamepad = { Enum.KeyCode.DPadRight }, Label = "C" },
		Ultimate = { Keyboard = { Enum.KeyCode.V }, Gamepad = { Enum.KeyCode.DPadUp }, Label = "V" },
		Parry = { Keyboard = { Enum.KeyCode.F }, Gamepad = { Enum.KeyCode.ButtonL2 } },
	},
}
