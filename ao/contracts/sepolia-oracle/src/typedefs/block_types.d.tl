-- block_types.tl
local record BlockData
    network: string
    blockNumber: string
    timestamp: string
    blockHash: string
  end
  
  local record BlockError
    network: string
    blockNumber: string
    timestamp: string
    blockHash: string
  end
  
  return {
    BlockData = BlockData,
    BlockError = BlockError
  }