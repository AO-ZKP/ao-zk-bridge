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
      INSERT INTO Blocks (network, block_number, timestamp, block_hash)
      VALUES (:network, :block_number, :timestamp, :block_hash)
    ]])

   insertStmt:bind_names({
      network = data.network,
      block_number = data.blockNumber,
      timestamp = data.timestamp,
      block_hash = data.blockHash,
   })

   local success, err = dbUtils.execute(insertStmt, "Insert block")
   if not success then
      ao.send(sendResponse(msg.From, "Error", { message = "Failed to insert block: " .. err }))
      return
   end

   ao.send(sendResponse(msg.From, "Success", { message = "Block added successfully" }))
end))


print("ao-bridge process initialized")
