-- AssetDiagnostics.server.luau
-- Scans template assets in Studio for debugging slow loads

local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

if not RunService:IsStudio() then
	return
end

local function collectAssets(root, buckets)
	for _, descendant in ipairs(root:GetDescendants()) do
		if descendant:IsA("Animation") then
			local id = descendant.AnimationId
			if id and id ~= "" and not id:match("^rbxasset://") then
				buckets.animations[id] = true
			end
		elseif descendant:IsA("Sound") then
			local id = descendant.SoundId
			if id and id ~= "" and not id:match("^rbxasset://") then
				buckets.sounds[id] = true
			end
		elseif descendant:IsA("MeshPart") then
			local meshId = descendant.MeshId
			local texId = descendant.TextureID
			if meshId and meshId ~= "" and not meshId:match("^rbxasset://") then
				buckets.meshes[meshId] = true
			end
			if texId and texId ~= "" and not texId:match("^rbxasset://") then
				buckets.meshes[texId] = true
			end
		elseif descendant:IsA("SpecialMesh") then
			local meshId = descendant.MeshId
			local texId = descendant.TextureId
			if meshId and meshId ~= "" and not meshId:match("^rbxasset://") then
				buckets.meshes[meshId] = true
			end
			if texId and texId ~= "" and not texId:match("^rbxasset://") then
				buckets.meshes[texId] = true
			end
		elseif descendant:IsA("Decal") then
			local tex = descendant.Texture
			if tex and tex ~= "" and not tex:match("^rbxasset://") then
				buckets.textures[tex] = true
			end
		end
	end
end

local function toList(map)
	local list = {}
	for id in pairs(map) do
		table.insert(list, id)
	end
	return list
end

local function logBucket(name, list)
	print(string.format("[AssetDiagnostics] %s: %d unique", name, #list))
	table.sort(list)
	for index, id in ipairs(list) do
		if index > 20 then
			break
		end
		print(string.format("[AssetDiagnostics] %s[%d]=%s", name, index, id))
	end
end

local buckets = {
	animations = {},
	sounds = {},
	meshes = {},
	textures = {},
}

local kiosk = ServerStorage:FindFirstChild("KioskTemplate")
if kiosk then
	collectAssets(kiosk, buckets)
else
	warn("[AssetDiagnostics] KioskTemplate missing")
end

local client = ServerStorage:FindFirstChild("ClientTemplate")
if client then
	collectAssets(client, buckets)
else
	warn("[AssetDiagnostics] ClientTemplate missing")
end

local hud = ServerStorage:FindFirstChild("HUD")
if hud then
	collectAssets(hud, buckets)
end

logBucket("animations", toList(buckets.animations))
logBucket("sounds", toList(buckets.sounds))
logBucket("meshes", toList(buckets.meshes))
logBucket("textures", toList(buckets.textures))
