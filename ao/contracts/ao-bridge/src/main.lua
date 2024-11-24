local _tl_compat; if (tonumber((_VERSION or ''):match('[%d.]*$')) or 0) < 5.3 then local p, m = pcall(require, 'compat53.module'); if p then _tl_compat = m end end; local debug = _tl_compat and _tl_compat.debug or debug; local string = _tl_compat and _tl_compat.string or string; local xpcall = _tl_compat and _tl_compat.xpcall or xpcall
require("globals")
local json = require("json")
local database = require("database")
local dbUtils = require("dbUtils")

BlockData = {}






BlockError = {}







ResponseData = {}






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



Handlers.add(
"getBlock",
Handlers.utils.hasMatchingTag("Action", "getBlock"),
wrapHandler(function(msg)
   local query = json.decode(msg.Data)
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
      ao.send(sendResponse(msg.From, "Error", { message = "No valid search criteria provided" }))
      return
   end

   stmt = DB:prepare("SELECT * FROM Blocks WHERE " .. whereClause)
   stmt:bind_names(params)

   local block = dbUtils.queryOne(stmt)

   if block then
      local response = {
         network = tostring(block.network),
         blockNumber = tostring(block.block_number),
         timestamp = tostring(block.timestamp),
         blockHash = tostring(block.block_hash),
      }
      ao.send(sendResponse(msg.From, "Success", response))
      return
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
         network = ChainId,
         blockNumber = query.blockNumber and errorMsg or "",
         timestamp = query.timestamp and errorMsg or "",
         blockHash = query.blockHash and errorMsg or "",
      }
      ao.send(sendResponse(msg.From, "Error", response))
      return
   end
end))


print("ao-bridge process initialized")
