-- main.tl
require "globals"
local json = require "json"
local database = require "database"
local dbUtils = require "dbUtils"
local blockTypes = require "block_types"

-- Type definitions
global record ResponseData
  Target: string
  Action: string
  Data: string
end

-- Initialize the database
database.initializeDatabase()

-- Helper function to send a response
local function sendResponse(target: string, action: string, data: any): ResponseData
  return {
    Target = target,
    Action = action,
    Data = json.encode(data)
  }
end

local function errorHandler(err: any): nil
  print("Critical error occurred: " .. tostring(err))
  print(debug.traceback())
end

local function wrapHandler(handlerFn: function(msg: Message)): function(msg: Message)
  return function(msg: Message): nil
    local success = xpcall(function(): any return handlerFn(msg) end, errorHandler)
    if not success then
      if msg.Sender == nil then
        ao.send(sendResponse(msg.From, "Error", {message = "An unexpected error occurred. Please try again later."}))
      else
        ao.send(sendResponse(msg.Sender, "Error", {message = "An unexpected error occurred. Please try again later."}))
      end
    end
  end
end

-- Validate block data
local function validateBlockData(data: blockTypes.BlockData): boolean, string
  -- Check network ID
  if data.network ~= ChainId then
    return false, "Invalid network ID"
  end

  -- Check block hash format
  if not string.match(data.blockHash, "^0x%x+$") or #data.blockHash ~= 66 then
    return false, "Invalid block hash format"
  end

  -- Check if block number and timestamp are valid numbers
  if not tonumber(data.blockNumber) or not tonumber(data.timestamp) then
    return false, "Invalid block number or timestamp format"
  end

  return true, ""
end

-- Add updateState handler
Handlers.add(
  "updateState",
  Handlers.utils.hasMatchingTag("Action", "updateState"),
  wrapHandler(function(msg: Message): nil
    
    if msg.From ~= OracleAddress then
        ao.send(sendResponse(msg.From, "Error", {message = "Unauthorized"}))
        return
    end

    local data = json.decode(msg.Data) as blockTypes.BlockData
    
    -- Validate input data
    local isValid, errMsg = validateBlockData(data)
    if not isValid then
      ao.send(sendResponse(msg.From, "Error", {message = errMsg}))
      return
    end

    -- Check for existing block
    local checkStmt = DB:prepare("SELECT block_number, timestamp FROM Blocks WHERE block_number = ? OR block_hash = ?")
    checkStmt:bind_names({block_number = data.blockNumber, block_hash = data.blockHash})
    local existing = dbUtils.queryOne(checkStmt)

    if existing then
      ao.send(sendResponse(msg.From, "Error", {message = "Block already exists"}))
      return
    end

    -- Check for latest block
    local latestStmt = DB:prepare("SELECT block_number, timestamp FROM Blocks ORDER BY CAST(block_number as INTEGER) DESC LIMIT 1")
    local latest = dbUtils.queryOne(latestStmt)

    if latest and (tonumber(data.blockNumber) <= tonumber(latest.block_number) or 
                  tonumber(data.timestamp) <= tonumber(latest.timestamp)) then
      ao.send(sendResponse(msg.From, "Error", {message = "Invalid block sequence"}))
      return
    end

    -- Insert new block
    local insertStmt = DB:prepare([[
      INSERT INTO Blocks (network, block_number, timestamp, block_hash)
      VALUES (:network, :block_number, :timestamp, :block_hash)
    ]])

    insertStmt:bind_names({
      network = data.network,
      block_number = data.blockNumber,
      timestamp = data.timestamp,
      block_hash = data.blockHash
    })

    local success, err = dbUtils.execute(insertStmt, "Insert block")
    if not success then
      ao.send(sendResponse(msg.From, "Error", {message = "Failed to insert block: " .. err}))
      return
    end

    ao.send(sendResponse(msg.From, "Success", {message = "Block added successfully"}))
  end)
)

-- Add getBlock handler
Handlers.add(
  "getBlock",
  Handlers.utils.hasMatchingTag("Action", "getBlock"),
  wrapHandler(function(msg: Message): nil
    local query = json.decode(msg.Data) as {string: string}
    local stmt: statement
    local whereClause: string
    local params: {string: string} = {}

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
      ao.send(sendResponse(msg.From, "Error", {message = "No valid search criteria provided"}))
      return
    end

    stmt = DB:prepare("SELECT * FROM Blocks WHERE " .. whereClause)
    stmt:bind_names(params)
    
    local block = dbUtils.queryOne(stmt)
    
    if block then
      local response: blockTypes.BlockData = {
        network = tostring(block.network) as string,
        blockNumber = tostring(block.block_number) as string,
        timestamp = tostring(block.timestamp) as string,
        blockHash = tostring(block.block_hash) as string
      }
      ao.send(sendResponse(msg.From, "Success", response))
    else
      local errorMsg = ""
      if query.blockNumber then
        errorMsg = string.format("block by %s doesnt exist in db", query.blockNumber)
      elseif query.timestamp then
        errorMsg = string.format("block by timestamp %s doesnt exist in db", query.timestamp)
      else
        errorMsg = string.format("block by hash %s doesnt exist in db", query.blockHash)
      end

      local response: blockTypes.BlockError = {
        network = "",
        blockNumber = query.blockNumber and errorMsg or "",
        timestamp = query.timestamp and errorMsg or "",
        blockHash = query.blockHash and errorMsg or ""
      }
      ao.send(sendResponse(msg.From, "Error", response))
    end
  end)
)

print("sepolia-oracle process initialized")