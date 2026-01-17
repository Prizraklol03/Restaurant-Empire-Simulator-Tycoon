-- PlotService.lua
-- Manages plot acquisition for player businesses

local Workspace = game:GetService("Workspace")

local PlotService = {}

local function getPlotsFolder()
	return Workspace:WaitForChild("BusinessPlots")
end

function PlotService.AcquirePlot(player)
	local plotsFolder = getPlotsFolder()

	for index = 1, 6 do
		local plot = plotsFolder:FindFirstChild("Plot_" .. index)
		if plot then
			local occupiedBy = plot:GetAttribute("OccupiedByUserId")
			if not occupiedBy or occupiedBy == 0 then
				plot:SetAttribute("OccupiedByUserId", player.UserId)
				print(string.format("[PlotService] player=%s acquired Plot_%d", player.UserId, index))
				return plot
			end
		end
	end

	return nil
end

function PlotService.ReleasePlot(player)
	local plotsFolder = getPlotsFolder()

	for index = 1, 6 do
		local plot = plotsFolder:FindFirstChild("Plot_" .. index)
		if plot and plot:GetAttribute("OccupiedByUserId") == player.UserId then
			plot:SetAttribute("OccupiedByUserId", 0)
			print(string.format("[PlotService] player=%s released Plot_%d", player.UserId, index))
			return
		end
	end
end

return PlotService
