print("[CLIENT] ClientController started")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Net = require(ReplicatedStorage.Shared.Net)

local GetProfile = Net.GetRemoteFunction("GetProfile")

local profile
for _ = 1, 10 do
	profile = GetProfile:InvokeServer()
	if profile ~= nil then
		break
	end
	task.wait(0.4)
end

print("[CLIENT] My profile:", profile)
