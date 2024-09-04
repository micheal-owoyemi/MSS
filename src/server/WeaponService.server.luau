-- spawn weapon
    -- send back equipped weapons in remote function

--[[ everytime a lerp is completer from one of the move functions, send an unreliable remote event:
    -- send back weapon data in a remote function
    {
        Orientation: 
        Position:
        Pivot??
    }

    take that data and update the weapons in the Weapons table sorted by player and catalouged by UUID

    fire all clients and find the player, then weapon model, then update the model's primary part with the data sent over --
    -- Use lerp or tween for other clients
]]