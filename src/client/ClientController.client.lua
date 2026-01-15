print("[CLIENT] ClientController started")


local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GetProfile = ReplicatedStorage.Remotes.Functions.GetProfile

local profile
repeat
	profile = GetProfile:InvokeServer()
	task.wait(0.2)
until profile ~= nil

print("[CLIENT] My profile:", profile)


local ReplicatedStorage = game:GetService("ReplicatedStorage")
