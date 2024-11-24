require("globals")
local json = require("json")
local database = require("database")
local dbUtils = require("dbUtils")


database.initializeDatabase()


local function sendResponse(target, action, data)
   return {
      Target = target,
      Action = action,
      Data = json.encode(data),
   }
end

local function errorHandler(err)
   print("Critical error occurred: " .. tostring(err))
   print(debug.traceback())
end

local function wrapHandler(handlerFn)
   return function(msg)
      local success = xpcall(function() return handlerFn(msg) end, errorHandler)
      if not success then
         if msg.Sender == nil then
            ao.send(sendResponse(msg.From, "Error", { message = "An unexpected error occurred. Please try again later." }))
         else
            ao.send(sendResponse(msg.Sender, "Error", { message = "An unexpected error occurred. Please try again later." }))
         end
      end
   end
end

print ("ImageId: " .. ImageId)


Handlers.add(
"bridge",
Handlers.utils.hasMatchingTag("Action", "Bridge"),
wrapHandler(function(msg)

   local data = json.decode(msg.Data)
   if not (data.receipt or data.withdraw) then
      ao.send(sendResponse(msg.From, "Error", { message = "Invalid request" }))
      return
   end

   -- input is a json which equals = {receipt, withdraw, ImageId}
   local input ={receipt = data.receipt, withdraw = data.withdraw, imageid = ImageId}

   --turn input table to json string
   local inputJson = json.encode(input)

   print(inputJson)
   local keccakResult = require("_groth16").keccak(inputJson)
   print ("Keccak result: " .. keccakResult)
   if keccakResult.error then
      ao.send(sendResponse(msg.From, "Error", { message = keccakResult.error }))
      return
   end

   local nullifier = json.decode(keccakResult).hash

   print("Nullifier: " .. tostring(nullifier))
   print("Checking if transaction exists")
   -- check if an entry with the nullifier EXISTS
   local checkStmt = DB:prepare("SELECT * FROM Transactions WHERE nullifier = :nullifier")
   checkStmt:bind_names({ nullifier = nullifier })
   local existing = dbUtils.queryOne(checkStmt)

   if existing then
      ao.send(sendResponse(msg.From, "Error", { message = "Transaction already Bridged" }))
      return
   end

   print("Transaction does not exist")
   print(existing)
   -- verify the proof

   local verifierResult = require("_groth16").verify(inputJson)
   print("Verifier result: " .. verifierResult) 
   if verifierResult.error then
      ao.send(sendResponse(msg.From, "Error", { message = verifierResult.error }))
      return
   end

   print("Proof verified successfully")

   local verifierResult = json.decode(verifierResult)


   local final = {
      nullifier = nullifier,
      block_number = verifierResult.blocknumber,
      amount = verifierResult.amount,
      timestamp = verifierResult.timestamp,
      withdraw_address = input.withdraw,
      block_hash = verifierResult.blockhash,
      }

   print(final)
   
   local insertStmt = DB:prepare([[
      INSERT INTO Transactions (nullifier, block_number, amount, timestamp, withdraw_address, block_hash)
      VALUES (:nullifier, :block_number, :amount, :timestamp, :withdraw_address, :block_hash)
    ]])

   insertStmt:bind_names({

      nullifier = nullifier,
      block_number = verifierResult.blocknumber,
      amount = verifierResult.amount,
      timestamp = verifierResult.timestamp,
      withdraw_address = input.withdraw,
      block_hash = verifierResult.blockhash,
   
   })

   local success, err = dbUtils.execute(insertStmt, "Insert block")
   if not success then
      ao.send(sendResponse(msg.From, "Error", { message = "Failed to Add Transaction: " .. err }))
      return
   end

   print("Block added successfully")
   print(final)

   ao.send(sendResponse(msg.From, "Success", { message = "Transaction added successfully" }))
end))


print("ao-bridge process initialized")
