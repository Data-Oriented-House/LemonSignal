--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local LemonSignal = require(ReplicatedStorage.LemonSignal)

local sig = LemonSignal.new()
-- local sig: LemonSignal.Signal<string, boolean> = LemonSignal.new()

-- sig:Connect(function(num: number, str: string, bool: boolean)
-- 	print(num)
-- 	print(str)
-- 	print(bool)
-- end)

sig:Connect(function(a0: string, a1: boolean) end)

sig:Fire("hello", false)
