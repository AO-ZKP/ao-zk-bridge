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



local function validateBlockData(data)

   if data.network ~= ChainId then
      return false, "Invalid network ID"
   end


   if not string.match(data.blockHash, "^0x%x+$") or #data.blockHash ~= 66 then
      return false, "Invalid block hash format"
   end


   if not tonumber(data.blockNumber) or not tonumber(data.timestamp) then
      return false, "Invalid block number or timestamp format"
   end

   return true, ""
end


Handlers.add(
"updateState",
Handlers.utils.hasMatchingTag("Action", "updateState"),
wrapHandler(function(msg)

   if not ((msg.From or msg.Sender) == OracleAddress) then
      ao.send(sendResponse(msg.From, "Error", { message = "Unauthorized" }))
      return
   end

   local data = json.decode(msg.Data)


   local isValid, errMsg = validateBlockData(data)
   if not isValid then
      ao.send(sendResponse(msg.From, "Error", { message = errMsg }))
      return
   end


   local checkStmt = DB:prepare("SELECT block_number, timestamp FROM Blocks WHERE block_number = ? OR block_hash = ?")
   checkStmt:bind_names({ block_number = data.blockNumber, block_hash = data.blockHash })
   local existing = dbUtils.queryOne(checkStmt)

   if existing then
      ao.send(sendResponse(msg.From, "Error", { message = "Block already exists" }))
      return
   end


   local latestStmt = DB:prepare("SELECT block_number, timestamp FROM Blocks ORDER BY CAST(block_number as INTEGER) DESC LIMIT 1")
   local latest = dbUtils.queryOne(latestStmt)

   if latest and (tonumber(data.blockNumber) <= tonumber(latest.block_number) or
      tonumber(data.timestamp) <= tonumber(latest.timestamp)) then
      ao.send(sendResponse(msg.From, "Error", { message = "Invalid block sequence" }))
      return
   end


   local insertStmt = DB:prepare([[
      INSERT INTO Blocks ( block_number, timestamp, block_hash)
      VALUES (:block_number, :timestamp, :block_hash)
    ]])

   insertStmt:bind_names({
      block_number = data.blockNumber,
      timestamp = data.timestamp,
      block_hash = data.blockHash,
   })

   local success, err = dbUtils.execute(insertStmt, "Insert block")
   if not success then
      ao.send(sendResponse(msg.From, "Error", { message = "Failed to insert block: " .. err }))
      return
   end


   print(data)

   ao.send(sendResponse(msg.From, "Success", { message = "Block added successfully" }))
end))



local function getBlock(msg)
   local query = json.decode(msg)
   local stmt
   local whereClause
   local params = {}

   if query.blockNumber then
      whereClause = "block_number = :block_number"
      params.block_number = query.blockNumber
   elseif query.timestamp then
      whereClause = "timestamp = :timestamp"
      params.timestamp = query.timestamp
   elseif query.blockHash then
      whereClause = "block_hash = :block_hash"
      params.block_hash = query.blockHash
   else
      return "No valid search criteria provided"
   end

   stmt = DB:prepare("SELECT * FROM Blocks WHERE " .. whereClause)
   stmt:bind_names(params)

   local block = dbUtils.queryOne(stmt)

   if block then
      local response = {
         blockNumber = tostring(block.block_number),
         timestamp = tostring(block.timestamp),
         blockHash = tostring(block.block_hash),
      }

      return response
   else
      local errorMsg = ""
      if query.blockNumber then
         errorMsg = string.format("block by %s doesnt exist in db", query.blockNumber)
      elseif query.timestamp then
         errorMsg = string.format("block by timestamp %s doesnt exist in db", query.timestamp)
      else
         errorMsg = string.format("block by hash %s doesnt exist in db", query.blockHash)
      end

      local response = {
         blockNumber = query.blockNumber and errorMsg or "",
         timestamp = query.timestamp and errorMsg or "",
         blockHash = query.blockHash and errorMsg or "",
      }
      return response
   end

end

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
   local block = {
      blockNumber = verifierResult.blocknumber,
   }

   print("Block number: " .. block.blockNumber)
   local getBlockJson = getBlock(json.encode(block))

   print("Block json: ") 
   print(getBlockJson)
   local block = json.encode(getBlockJson) 
   
   print("Block Table: " .. block)
   if (getBlockJson.blockNumber ~= verifierResult.blocknumber) or (getBlockJson.blockHash ~= verifierResult.blockhash) then
      ao.send(sendResponse(msg.From, "Error", { message = "Block not found" }))
      print("Block not found" .. block.blockNumber .. " verifier" .. verifierResult.blocknumber)
      return
   end
    
   

   local final = {
      nullifier = nullifier,
      block_number = verifierResult.blocknumber,
      amount = verifierResult.amount,
      timestamp = verifierResult.timestamp,
      withdraw_address = input.withdraw,
      block_hash = verifierResult.blockhash,
      }

   
   local insertStmt = DB:prepare([[
      INSERT INTO Transactions (nullifier, block_number, amount, timestamp, withdraw_address, block_hash)
      VALUES (:nullifier, :block_number, :amount, :timestamp, :withdraw_address, :block_hash)
    ]])

   insertStmt:bind_names(final)

   local success, err = dbUtils.execute(insertStmt, "Insert block")
   if not success then
      ao.send(sendResponse(msg.From, "Error", { message = "Failed to Add Transaction: " .. err }))
      print("Failed to add transaction")
      return
   end

   print("Block added successfully")
   print(final)

   Send({ Target = Token, Action = "Mint", Recipient = input.withdraw, Quantity = tostring(verifierResult.amount)} )
   return
end))


print("ao-bridge process initialized")
