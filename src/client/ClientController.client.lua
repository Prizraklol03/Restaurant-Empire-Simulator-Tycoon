print("[CLIENT] ClientController started")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Net = require(ReplicatedStorage.Shared.Net)

local GetProfile = Net.GetRemoteFunction("GetProfile")

local profile
for attempt = 1, 3 do
	profile = GetProfile:InvokeServer()
	if profile ~= nil then
		break
	end
	warn(("[CLIENT] GetProfile returned nil, retry %d/3"):format(attempt))
	task.wait(0.5)
end

print("[CLIENT] My profile:", profile)
