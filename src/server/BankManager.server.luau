local ServerScriptService = game:GetService('ServerScriptService')
local Bank = require(ServerScriptService.Server.Bank)

local bank1 = Bank.new('Will', 100) -- Add 1000
local bank2 = Bank.new('Gvisitc', 100) -- Set to 0

bank1:addBalance(900)
print(bank1:getBalance())

bank2:setBalance(0)
print(bank2:getBalance())
