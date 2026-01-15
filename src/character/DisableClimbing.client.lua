local Players = game:GetService("Players")
local player = Players.LocalPlayer

local function setupHumanoid(humanoid)
	-- Отключаем штатно
	pcall(function()
		humanoid:SetStateEnabled(Enum.HumanoidStateType.Climbing, false)
	end)

	-- Жёсткий перехват
	humanoid.StateChanged:Connect(function(_, newState)
		if newState == Enum.HumanoidStateType.Climbing then
			humanoid:ChangeState(Enum.HumanoidStateType.Running)
		end
	end)
end

local function onCharacterAdded(character)
	local humanoid = character:WaitForChild("Humanoid")
	setupHumanoid(humanoid)
end

if player.Character then
	onCharacterAdded(player.Character)
end

player.CharacterAdded:Connect(onCharacterAdded)
