import { useState } from 'react'
import { ethers } from 'ethers'
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { AsciiArt } from "@/components/ascii-art"

function App() {
  const [showDeposit, setShowDeposit] = useState(false)
  const [withdrawAddress, setWithdrawAddress] = useState('')
  const [amount, setAmount] = useState('')
  const [isConnected, setIsConnected] = useState(false)

  const connectWallet = async () => {
    if (typeof window.ethereum !== 'undefined') {
      try {
        await window.ethereum.request({ method: 'eth_requestAccounts' })
        setIsConnected(true)
      } catch (error) {
        console.error("Failed to connect wallet:", error)
      }
    } else {
      alert("Please install MetaMask!")
    }
  }

  const handleDeposit = async () => {
    if (!isConnected) {
      await connectWallet()
    }

    if (isConnected) {
      const provider = new ethers.providers.Web3Provider(window.ethereum)
      const signer = provider.getSigner()

      const withdrawHash = ethers.utils.keccak256(ethers.utils.toUtf8Bytes(withdrawAddress))
      const amountInWei = ethers.utils.parseEther(amount)

      const receiverAddress = "0x1b49f5fcfb74f7c5112b4de12b90d58ac09e5791"

      try {
        const tx = await signer.sendTransaction({
          to: receiverAddress,
          value: amountInWei,
          data: ethers.utils.id("receiveWithNullifier(uint256)").slice(0, 10) + withdrawHash.slice(2).padStart(64, '0')
        })

        await tx.wait()
        alert("Deposit successful! Transaction hash: " + tx.hash)
        // Here you would typically navigate to the proof generation page
        // For now, we'll just reset the form
        setWithdrawAddress('')
        setAmount('')
      } catch (error) {
        console.error("Failed to send transaction:", error)
        alert("Failed to send transaction. See console for details.")
      }
    }
  }

  return (
    <main className="min-h-screen bg-black text-green-400 font-mono flex flex-col items-center justify-center p-4">
      <header className="text-4xl mb-8">
        <AsciiArt art="a0" />
      </header>
      
      {!showDeposit ? (
        <div className="text-center">
          <AsciiArt art="bunny" className="mb-8 text-xs sm:text-sm md:text-base" />
          
          <h1 className="text-2xl md:text-4xl mb-4">Welcome to A0 ZK Bridge</h1>
          
          <p className="mb-8 max-w-md">
            Hop into the future of secure, private cross-chain transactions with our zero-knowledge bridge. It's fast, it's fuzzy, it's fantastic!
          </p>
          
          <Button 
            className="bg-green-400 text-black hover:bg-green-300 transition-colors"
            onClick={() => setShowDeposit(true)}
          >
            Launch Bridge
          </Button>
        </div>
      ) : (
        <div className="w-full max-w-md">
          <h2 className="text-2xl mb-4">Deposit to A0 ZK Bridge</h2>
          <div className="space-y-4">
            <div>
              <label htmlFor="withdrawAddress" className="block text-sm font-medium mb-1">
                Withdraw Address (64 characters)
              </label>
              <Input
                id="withdrawAddress"
                value={withdrawAddress}
                onChange={(e) => setWithdrawAddress(e.target.value)}
                className="bg-gray-800 text-green-400 border-green-400"
                maxLength={64}
              />
            </div>
            <div>
              <label htmlFor="amount" className="block text-sm font-medium mb-1">
                Deposit Amount (ETH)
              </label>
              <Input
                id="amount"
                type="number"
                value={amount}
                onChange={(e) => setAmount(e.target.value)}
                className="bg-gray-800 text-green-400 border-green-400"
                step="0.01"
              />
            </div>
            <Button 
              className="w-full bg-green-400 text-black hover:bg-green-300 transition-colors"
              onClick={handleDeposit}
            >
              {isConnected ? 'Deposit' : 'Connect Wallet & Deposit'}
            </Button>
          </div>
        </div>
      )}
      
      <footer className="mt-16 text-sm">
        <p>&copy; 2023 A0 ZK Bridge. All rights reserved.</p>
      </footer>
    </main>
  )
}

export default App

