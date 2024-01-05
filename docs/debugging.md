---
sidebar_position: 4
---

# Debugging
On Roblox, when your connection errors you can press the error in your output window and get directly sent to the exact line the error originated from, but when using `coroutine.resume` we lose that convenience and will have to manually get there, I've made a bug report to Roblox to hopefully fix this issue, but for now let's go on how to go about.

Let's take this code in a script called `Script` that's parented to `ServerScriptService`:

```lua
local signal = require(game.ReplicatedStorage.LemonSignal).new()

local function foo() 
    error("error")
end

signal:Connect(function()
	foo()
end)

signal:Fire()
```

Which shows this on your console:

```
Script <-- Press to select the script.  -  Server
ServerScriptService.Script:4: error  -  Server - LemonSignal:131
Stack Begin  -  Studio
Script 'ReplicatedStorage.LemonSignal', Line 131 - function contextualError  -  Studio - LemonSignal:131
Script 'ReplicatedStorage.LemonSignal', Line 406 - function Fire  -  Studio - LemonSignal:406
Script 'ServerScriptService.Script', Line 11  -  Studio - Script:11
Stack End  -  Studio
```

Ideally, pressing the 2nd line should open the `ServerScriptService.Script` at line 4, but all it does is it takes you to LemonSignal's source, that's why the 1st line exists, if you press `Script` while your game is still running, it will select the script for you in the explorer and then you can just double click it and go to line 4:

![debug](/debug.gif)

*Please note that pressing the `Script` in the output will select your script in the explorer only when the game is still running.*