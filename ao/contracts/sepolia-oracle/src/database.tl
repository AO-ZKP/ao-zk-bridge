-- database.tl

require "globals"

local sqlite3 = require("lsqlite3")

Variant = "0.0.1"
Counter = 0
DB = DB or sqlite3.open_memory()
Configured = Configured or false

local database = {}

local function initializeDatabaseConnection(): boolean
  if not DB then
    local ok, err = pcall(function(): db
      return sqlite3.open_memory()
    end)
    if not ok then
      print("Failed to initialize database connection: " .. tostring(err))
      return false
    end
    DB = err as db  -- In this case, 'err' is actually the successful result
  end
  return true
end

local function executeSQL(sql: string): boolean, string
  local ok, err = pcall(function(): nil
    DB:exec(sql)
  end)
  if not ok then
    return false, "Failed to execute SQL: " .. tostring(err)
  end
  return true, ""
end

function database.initializeDatabase(): boolean
  print("Initializing database")
  if not initializeDatabaseConnection() then
    return false
  end

  if not Configured then
    print("Setting up database schema")
    local tables: {string} = {
      -- Users Table
      [[
        CREATE TABLE IF NOT EXISTS Users (
          user_id TEXT PRIMARY KEY,
          total_games_played INTEGER DEFAULT 0,
          created_at INTEGER
        );
      ]],

      -- Games Table
      [[
        CREATE TABLE IF NOT EXISTS Games (
          game_id TEXT PRIMARY KEY,
          user_id TEXT,
          initial_bet REAL,
          current_multiplier REAL DEFAULT 1,
          current_credits REAL DEFAULT 0,
          current_level INTEGER DEFAULT 1,
          game_status TEXT CHECK(game_status IN ('active', 'won', 'lost')),
          created_at INTEGER,
          updated_at INTEGER,
          multipliers TEXT DEFAULT '',
          FOREIGN KEY(user_id) REFERENCES Users(user_id)
        );
      ]],

      -- GameMoves Table
      [[
        CREATE TABLE IF NOT EXISTS GameMoves (
          move_id TEXT PRIMARY KEY,
          game_id TEXT,
          level INTEGER,
          row_config TEXT,
          selected_column INTEGER CHECK(selected_column IN (1, 2, 3)),
          outcome TEXT CHECK(outcome IN ('reward', 'magma')),
          row_multiplier REAL,
          created_at INTEGER,
          FOREIGN KEY(game_id) REFERENCES Games(game_id)
        );
      ]],

      -- Probabilities Table
      [[
        CREATE TABLE IF NOT EXISTS Probabilities (
          level INTEGER PRIMARY KEY CHECK(level BETWEEN 1 AND 7),
          magma_probability REAL,
          magma_blocks INTEGER,
          base_reward INTEGER
        );
      ]],

      -- Initialize Probabilities
      [[
        INSERT OR IGNORE INTO Probabilities (level, magma_probability, magma_blocks, base_reward)
        VALUES
          (1, 0.33, 1, 1),
          (2, 0.33, 1, 1),
          (3, 0.33, 1, 1),
          (4, 0.33, 1, 1),
          (5, 0.66, 2, 1),
          (6, 0.66, 2, 1),
          (7, 0.66, 2, 1);
      ]],
      
      -- GameStatistics Table
      [[
        CREATE TABLE IF NOT EXISTS GameStatistics (
          stat_id TEXT PRIMARY KEY,
          total_games_played INTEGER DEFAULT 0,
          total_bets INTEGER DEFAULT 0,
          total_payouts INTEGER DEFAULT 0,
          highest_multiplier REAL DEFAULT 0,
          average_multiplier REAL DEFAULT 0,
          updated_at INTEGER
        );
      ]],

      -- Initialize GameStatistics
      [[
        INSERT OR IGNORE INTO GameStatistics (stat_id, updated_at)
        VALUES ('global', strftime('%s', 'now'));
      ]]
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