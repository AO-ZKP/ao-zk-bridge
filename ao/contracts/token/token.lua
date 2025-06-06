local bint = require('.bint')(256)
--[[
  This module implements the ao Standard Token Specification.

  Terms:
    Sender: the wallet or Process that sent the Message

  It will first initialize the internal state, and then attach handlers,
    according to the ao Standard Token Spec API:

    - Info(): return the token parameters, like Name, Ticker, Logo, and Denomination

    - Balance(Target?: string): return the token balance of the Target. If Target is not provided, the Sender
        is assumed to be the Target

    - Balances(): return the token balance of all participants

    - Transfer(Target: string, Quantity: number): if the Sender has a sufficient balance, send the specified Quantity
        to the Target. It will also issue a Credit-Notice to the Target and a Debit-Notice to the Sender

    - Mint(Quantity: number): if the Sender matches the Process Owner, then mint the desired Quantity of tokens, adding
        them the Processes' balance
]]
--
local json = require('json')

--[[
  utils helper functions to remove the bint complexity.
]]
--


local utils = {
  add = function(a, b)
    return tostring(bint(a) + bint(b))
  end,
  subtract = function(a, b)
    return tostring(bint(a) - bint(b))
  end,
  toBalanceValue = function(a)
    return tostring(bint(a))
  end,
  toNumber = function(a)
    return bint.tonumber(a)
  end
}


--[[
     Initialize State

     ao.id is equal to the Process.Id
   ]]
--
Variant = "0.0.3"

-- token should be idempotent and not change previous state updates
Denomination = Denomination or 12
Balances = Balances or { [ao.id] = utils.toBalanceValue(10000 * 10 ^ Denomination) }
TotalSupply = TotalSupply or utils.toBalanceValue(10000 * 10 ^ Denomination)
Name = Name or 'Wrapped ETH Sepolia'
Ticker = Ticker or 'wETHS'
Logo = Logo or 'tV92WZxgU2GoLj8YeDeWEH6vCogz7ARdR05UoOmbntQ'
ChainId = "11155111"
OracleContract = "SX5bFl_MIcu9CjIe7Rd6jbpLXWiS_eXuMvTgjYh1H3Q"

--[[
     Add handlers for each incoming Action defined by the ao Standard Token Specification
   ]]
--

--[[
     Info
   ]]
--
Handlers.add('info', Handlers.utils.hasMatchingTag("Action", "Info"), function(msg)
  if msg.reply then
    msg.reply({
      Name = Name,
      Ticker = Ticker,
      Logo = Logo,
      Denomination = tostring(Denomination)
    })
  else
    Send({Target = msg.From, 
    Name = Name,
    Ticker = Ticker,
    Logo = Logo,
    Denomination = tostring(Denomination)
   })
  end
end)

--[[
     Balance
   ]]
--
Handlers.add('balance', Handlers.utils.hasMatchingTag("Action", "Balance"), function(msg)
  local bal = '0'

  -- If not Recipient is provided, then return the Senders balance
  if (msg.Tags.Recipient) then
    if (Balances[msg.Tags.Recipient]) then
      bal = Balances[msg.Tags.Recipient]
    end
  elseif msg.Tags.Target and Balances[msg.Tags.Target] then
    bal = Balances[msg.Tags.Target]
  elseif Balances[msg.From] then
    bal = Balances[msg.From]
  end
  if msg.reply then
    msg.reply({
      Balance = bal,
      Ticker = Ticker,
      Account = msg.Tags.Recipient or msg.From,
      Data = bal
    })
  else
    Send({
      Target = msg.From,
      Balance = bal,
      Ticker = Ticker,
      Account = msg.Tags.Recipient or msg.From,
      Data = bal
    })
  end
end)

--[[
     Balances
   ]]
--
Handlers.add('balances', Handlers.utils.hasMatchingTag("Action", "Balances"),
  function(msg) 
    if msg.reply then
      msg.reply({ Data = json.encode(Balances) })
    else 
      Send({Target = msg.From, Data = json.encode(Balances) }) 
    end
  end)

--[[
     Transfer
   ]]
--
Handlers.add('transfer', Handlers.utils.hasMatchingTag("Action", "Transfer"), function(msg)
  assert(type(msg.Recipient) == 'string', 'Recipient is required!')
  assert(type(msg.Quantity) == 'string', 'Quantity is required!')
  assert(bint.__lt(0, bint(msg.Quantity)), 'Quantity must be greater than 0')

  if not Balances[msg.From] then Balances[msg.From] = "0" end
  if not Balances[msg.Recipient] then Balances[msg.Recipient] = "0" end

  if bint(msg.Quantity) <= bint(Balances[msg.From]) then
    Balances[msg.From] = utils.subtract(Balances[msg.From], msg.Quantity)
    Balances[msg.Recipient] = utils.add(Balances[msg.Recipient], msg.Quantity)

    --[[
         Only send the notifications to the Sender and Recipient
         if the Cast tag is not set on the Transfer message
       ]]
    --
    if not msg.Cast then
      -- Debit-Notice message template, that is sent to the Sender of the transfer
      local debitNotice = {
        Action = 'Debit-Notice',
        Recipient = msg.Recipient,
        Quantity = msg.Quantity,
        Data = Colors.gray ..
            "You transferred " ..
            Colors.blue .. msg.Quantity .. Colors.gray .. " to " .. Colors.green .. msg.Recipient .. Colors.reset
      }
      -- Credit-Notice message template, that is sent to the Recipient of the transfer
      local creditNotice = {
        Target = msg.Recipient,
        Action = 'Credit-Notice',
        Sender = msg.From,
        Quantity = msg.Quantity,
        Data = Colors.gray ..
            "You received " ..
            Colors.blue .. msg.Quantity .. Colors.gray .. " from " .. Colors.green .. msg.From .. Colors.reset
      }

      -- Add forwarded tags to the credit and debit notice messages
      for tagName, tagValue in pairs(msg) do
        -- Tags beginning with "X-" are forwarded
        if string.sub(tagName, 1, 2) == "X-" then
          debitNotice[tagName] = tagValue
          creditNotice[tagName] = tagValue
        end
      end

      -- Send Debit-Notice and Credit-Notice
      if msg.reply then
        msg.reply(debitNotice)
      else
        debitNotice.Target = msg.From
        Send(debitNotice)
      end
      Send(creditNotice)
    end
  else
    if msg.reply then
      msg.reply({
        Action = 'Transfer-Error',
        ['Message-Id'] = msg.Id,
        Error = 'Insufficient Balance!'
      })
    else
      Send({
        Target = msg.From,
        Action = 'Transfer-Error',
        ['Message-Id'] = msg.Id,
        Error = 'Insufficient Balance!'
      })
    end
  end
end)

--[[
    Mint
   ]]
--
Handlers.add('mint', Handlers.utils.hasMatchingTag("Action","Mint"), function(msg)
  print('Minting ' .. tostring(msg.Quantity) .. ' tokens')
  assert(type(msg.Quantity) == 'string', 'Quantity is required!')
  
  if type(msg.Recipient) ~= 'string' then
    return
  end
  msg.Quantity = tostring(bint.floor(bint(msg.Quantity)/1000000))
  print('Minting ' .. tostring(msg.Quantity) .. ' tokens')

  assert(bint(0) < bint(msg.Quantity), 'Quantity must be greater than zero!')

  if not Balances[msg.From] then Balances[msg.From] = "0" end
  if not Balances[ao.id] then Balances[ao.id] = "0" end
  if not Balances[msg.Quantity] then Balances[msg.Quantity] = "0" end
  if not Balances[msg.Recipient] then Balances[msg.Recipient] = "0" end

  if msg.From == ao.id or msg.From ==  OracleContract then
    -- Add tokens to the token pool, according to Quantity
    Balances[ao.id] = utils.add(Balances[ao.id], msg.Quantity)
    
    TotalSupply = utils.add(TotalSupply, msg.Quantity)

  if bint(msg.Quantity) <= bint(Balances[ao.id]) then
    Balances[ao.id] = utils.subtract(Balances[ao.id], msg.Quantity)
    Balances[msg.Recipient] = utils.add(Balances[msg.Recipient], msg.Quantity)
  end
    if msg.reply then
      msg.reply({
        Data = Colors.gray .. "Successfully minted " .. Colors.blue .. msg.Quantity .. Colors.reset
      })
    else
      Send({
        Target = msg.From,
        Data = Colors.gray .. "Successfully minted " .. Colors.blue .. msg.Quantity .. Colors.reset
      })
    end
  else
    if msg.reply then
      msg.reply({
        Action = 'Mint-Error',
        ['Message-Id'] = msg.Id,
        Error = 'Only the Process Id can mint new ' .. Ticker .. ' tokens!'
      })
    else
      Send({
        Target = msg.From,
        Action = 'Mint-Error',
        ['Message-Id'] = msg.Id,
        Error = 'Only the Process Id can mint new ' .. Ticker .. ' tokens!'
      })
    end
  end
end)

--[[
     Total Supply
   ]]
--
Handlers.add('totalSupply', Handlers.utils.hasMatchingTag("Action","Total-Supply"), function(msg)
  assert(msg.From ~= ao.id, 'Cannot call Total-Supply from the same process!')
  if msg.reply then
    msg.reply({
      Action = 'Total-Supply',
      Data = TotalSupply,
      Ticker = Ticker
    })
  else
    Send({
      Target = msg.From,
      Action = 'Total-Supply',
      Data = TotalSupply,
      Ticker = Ticker
    })
  end
end)

--[[
 Burn
]] --
Handlers.add('burn', Handlers.utils.hasMatchingTag("Action",'Burn'), function(msg)
  print("burning is disabled")
return
end)
