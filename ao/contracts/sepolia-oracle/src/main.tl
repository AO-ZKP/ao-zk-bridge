-- main.tl

require "globals"
local json = require "json"
local database = require "database"


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

local function safeGetTag(message: Message, tag:string): string | nil
  if not message or type(message) ~= "table" or not message.Tags or type(message.Tags) ~= "table" then
      return nil
  end
  
  local success, result = pcall(function():string
      return message.Tags[tag]
  end)
  
  if success and result ~= nil then
      return result
  else
      return nil
  end
end


-- Add an info handler to return the process version
Handlers.add(
  "getInfo",
  Handlers.utils.hasMatchingTag("Action", "Info"),
  wrapHandler(function(msg: Message)
    ao.send(sendResponse(msg.From, "Info", {version = Variant}))
  end)
)



print("sepolia-oracle process initialized")