require("globals")
local json = require("json")

local verify = require("_groth16").verify
local keccak = require("_groth16").keccak

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
"verify",
Handlers.utils.hasMatchingTag("Action", "Verify"),
wrapHandler(function(msg)
   local data = json.decode(msg.Data)
   -- input is a json which equals = {receipt, withdraw, ImageId}
   local input ={receipt = data.receipt, withdraw = data.withdraw, imageid = ImageId}
   --turn input table to json string
   local inputJson = json.encode(input)
local result = verify(inputJson)

ao.send(sendResponse(msg.From, "Result", result))
end))

Handlers.add(
"keccak",
Handlers.utils.hasMatchingTag("Action", "Keccak"),
wrapHandler(function(msg)
   local data = json.decode(msg.Data)
   -- input is a json which equals = {receipt, withdraw, ImageId}
   local input ={receipt = data.receipt, withdraw = data.withdraw, imageid = ImageId}
   --turn input table to json string
   local inputJson = json.encode(input)
local result = keccak(inputJson)

   
   ao.send(sendResponse(msg.From, "Result", result))
   
end))

print(" verifier process initialized")
