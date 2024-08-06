local Bank = {}
Bank.__index = Bank

function Bank.new(name, initBalance)
    local self = setmetatable({}, Bank)
    self.name = name
    self.initialBalance = initBalance
    return self
end

-- Setter Function
function Bank:setBalance(amount)
    self.initialBalance = amount
end

-- Getter Function
function Bank:getBalance()
    return self.initialBalance
end

-- Add Function
function Bank:addBalance(amount)
    self.initialBalance += amount
end
return Bank