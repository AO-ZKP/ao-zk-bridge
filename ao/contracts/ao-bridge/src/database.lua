require("globals")

local sqlite3 = require("lsqlite3")

Variant = "0.0.1"
Counter = 0
DB = DB or sqlite3.open_memory()
Configured = Configured or false

local database = {}

local function initializeDatabaseConnection()
   if not DB then
      local ok, err = pcall(function()
         return sqlite3.open_memory()
      end)
      if not ok then
         print("Failed to initialize database connection: " .. tostring(err))
         return false
      end
      DB = err
   end
   return true
end

local function executeSQL(sql)
   local ok, err = pcall(function()
      DB:exec(sql)
   end)
   if not ok then
      return false, "Failed to execute SQL: " .. tostring(err)
   end
   return true, ""
end

function database.initializeDatabase()
   print("Initializing database")
   if not initializeDatabaseConnection() then
      return false
   end

   if not Configured then
      print("Setting up database schema")
      local tables = {



         [[
        CREATE TABLE IF NOT EXISTS Transactions (
          nullifier TEXT PRIMARY KEY,
          block_number TEXT NOT NULL,
          amount TEXT NOT NULL,
          timestamp TEXT NOT NULL,
          withdraw_address TEXT NOT NULL,
          block_hash TEXT NOT NULL,
          created_at INTEGER DEFAULT (strftime('%s', 'now'))
        );
      ]],
      }

      for _, sql in ipairs(tables) do
         local ok, err = executeSQL(sql)
         if not ok then
            print("Database initialization failed: " .. err)
            return false
         end
      end

      Configured = true
   end

   print("Database initialization complete")
   return true
end

return database
