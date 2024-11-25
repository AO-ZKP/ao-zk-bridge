import { useState, useEffect, useCallback } from 'react'
import { ethers } from 'ethers'
import { message, createDataItemSigner } from "@permaweb/aoconnect"
import { useConnection } from "arweave-wallet-kit"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Textarea } from "@/components/ui/textarea"
import { AsciiArt } from "@/components/ascii-art"

function App() {
  const [currentPage, setCurrentPage] = useState('landing')
  const [withdrawAddress, setWithdrawAddress] = useState('')
  const [amount, setAmount] = useState('')
  const [isEthereumConnected, setIsEthereumConnected] = useState(false)
  const [ethereumAddress, setEthereumAddress] = useState('')
  const [isGeneratingProof, setIsGeneratingProof] = useState(false)
  const [proof, setProof] = useState<{ receipt: any; withdraw: string } | null>(null)
  const [isSubmittingProof, setIsSubmittingProof] = useState(false)
  const [submissionResponse, setSubmissionResponse] = useState(null)
  const [manualProof, setManualProof] = useState('')

  const { connected: isArweaveConnected, connect: connectArweave } = useConnection()

  useEffect(() => {
    checkEthereumConnection()
  }, [])

  const checkEthereumConnection = async () => {
    if (typeof window.ethereum !== 'undefined') {
      try {
        const provider = new ethers.providers.Web3Provider(window.ethereum)
        const accounts = await provider.listAccounts()
        if (accounts.length > 0) {
          setIsEthereumConnected(true)
          setEthereumAddress(accounts[0])
        }
      } catch (error) {
        console.error("Failed to check Ethereum connection:", error)
      }
    }
  }

  const connectEthereum = async () => {
    if (typeof window.ethereum !== 'undefined') {
      try {
        const provider = new ethers.providers.Web3Provider(window.ethereum)
        await provider.send("eth_requestAccounts", [])
        const signer = provider.getSigner()
        const address = await signer.getAddress()
        setIsEthereumConnected(true)
        setEthereumAddress(address)
      } catch (error) {
        console.error("Failed to connect Ethereum wallet:", error)
        alert("Failed to connect Ethereum wallet. Please try again.")
      }
    } else {
      alert("Please install MetaMask!")
    }
  }

  const handleDeposit = async () => {
    if (!isEthereumConnected) {
      await connectEthereum()
    }

    if (isEthereumConnected) {
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
        setCurrentPage('generateProof')
      } catch (error) {
        console.error("Failed to send transaction:", error)
        alert("Failed to send transaction. See console for details.")
      }
    }
  }

  const generateProof = async () => {
    setIsGeneratingProof(true)
    try {
      const response = await fetch(`https://vmi2291107.contaboserver.net/generate/${ethereumAddress}`)
      if (!response.ok) {
        throw new Error(`HTTP error! status: ${response.status}`)
      }
      const proofData = await response.json()
      const submissionData = {
        receipt: proofData.Ok.receipt,
        withdraw: withdrawAddress
      }
      setProof(submissionData)
      
      // Create a Blob from the JSON data
      const blob = new Blob([JSON.stringify(submissionData)], { type: 'application/json' })
      const url = URL.createObjectURL(blob)
      
      // Create a link element and trigger the download
      const a = document.createElement('a')
      a.href = url
      a.download = 'proof.json'
      document.body.appendChild(a)
      a.click()
      document.body.removeChild(a)
      URL.revokeObjectURL(url)

      setCurrentPage('submitProof')
    } catch (error) {
      console.error("Failed to generate proof:", error)
      alert("Failed to generate proof. See console for details.")
    } finally {
      setIsGeneratingProof(false)
    }
  }

  const submitProof = async (proofToSubmit) => {
    setIsSubmittingProof(true)
    try {
      if (!isArweaveConnected) {
        await connectArweave()
      }

      let submissionData
      if (typeof proofToSubmit === 'string') {
        // If it's a string, parse it as JSON
        const parsedProof = JSON.parse(proofToSubmit)
        if (!parsedProof.withdraw || !parsedProof.receipt) {
          throw new Error("Invalid proof data")
        }
        const receiptJson = JSON.parse(parsedProof.receipt);

        // Create new object with parsed receipt
        const fixedJson = {
            ...parsedProof,
            receipt: receiptJson
        };
        submissionData = fixedJson
        console.log("Proof data:", fixedJson)
        console.log("Parsed proof data:", JSON.stringify(fixedJson))
      } else if (proofToSubmit && proofToSubmit.Ok && proofToSubmit.Ok.receipt) {
        // If it's an object with the expected structure
        submissionData = {
          receipt: proofToSubmit.Ok.receipt,
          withdraw: withdrawAddress
        }
      } else {
        throw new Error("Invalid proof data")
      }

      const response = await message({
        process: "SX5bFl_MIcu9CjIe7Rd6jbpLXWiS_eXuMvTgjYh1H3Q", // Replace with actual process ID
        tags: [
          { name: "Action", value: "Bridge" },
        ],
        signer: createDataItemSigner(globalThis.arweaveWallet),
        data: JSON.stringify(submissionData),
      })

      setSubmissionResponse(response)
      setCurrentPage('thankYou')
    } catch (error) {
      console.error("Failed to submit proof:", error)
      alert("Failed to submit proof. See console for details.")
    } finally {
      setIsSubmittingProof(false)
    }
  }

  const handleDragOver = (e) => {
    e.preventDefault()
  }

  const handleDrop = useCallback((e) => {
    e.preventDefault()
    const file = e.dataTransfer.files[0]
    if (file) {
      const reader = new FileReader()
      reader.onload = (event) => {
        try {
          const proofData = JSON.parse(event.target.result)
          setProof(proofData)
          setManualProof(JSON.stringify(proofData, null, 2))
        } catch (error) {
          console.error("Failed to parse dropped file:", error)
          alert("Invalid proof file. Please ensure it's a valid JSON file.")
        }
      }
      reader.readAsText(file)
    }
  }, [])

  const renderContent = () => {
    switch (currentPage) {
      case 'landing':
        return (
          <div className="text-center">
            <AsciiArt art="bunny" className="mb-8 text-xs sm:text-sm md:text-base" />
            
            <h1 className="text-2xl md:text-4xl mb-4">Welcome to A0 ZK Bridge</h1>
            
            <p className="mb-8 max-w-md">
              Hop into the future of secure, private cross-chain transactions with our zero-knowledge bridge. It's fast, it's fuzzy, it's fantastic!
            </p>
            
            <div className="space-y-4">
              <Button 
                className="w-full bg-green-400 text-black hover:bg-green-300 transition-colors"
                onClick={() => setCurrentPage('deposit')}
              >
                Make a Deposit
              </Button>
              <Button 
                className="w-full bg-green-400 text-black hover:bg-green-300 transition-colors"
                onClick={() => setCurrentPage('submitProof')}
              >
                Submit Existing Proof
              </Button>
            </div>
          </div>
        )
      case 'deposit':
        return (
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
                {isEthereumConnected ? 'Deposit' : 'Connect Ethereum & Deposit'}
              </Button>
            </div>
          </div>
        )
      case 'generateProof':
        return (
          <div className="w-full max-w-md text-center">
            <h2 className="text-2xl mb-4">Generate Proof</h2>
            <p className="mb-4">
              Connected Ethereum Wallet: {ethereumAddress}
            </p>
            <Button 
              className="w-full bg-green-400 text-black hover:bg-green-300 transition-colors"
              onClick={generateProof}
              disabled={isGeneratingProof}
            >
              {isGeneratingProof ? 'Generating Proof...' : 'Generate Proof'}
            </Button>
            {isGeneratingProof && (
              <p className="mt-4">This process may take about a minute. Please wait...</p>
            )}
          </div>
        )
      case 'submitProof':
        return (
          <div className="w-full max-w-md text-center">
            <h2 className="text-2xl mb-4">Submit Proof</h2>
            <div 
              className="border-2 border-dashed border-green-400 p-4 mb-4 cursor-pointer"
              onDragOver={handleDragOver}
              onDrop={handleDrop}
            >
              <p>Drag and drop your proof file here</p>
            </div>
            <p className="mb-2">Or paste your proof here:</p>
            <Textarea
              value={manualProof}
              onChange={(e) => setManualProof(e.target.value)}
              className="bg-gray-800 text-green-400 border-green-400 mb-4"
              rows={10}
            />
            <Button 
              className="w-full bg-green-400 text-black hover:bg-green-300 transition-colors"
              onClick={() => submitProof(manualProof || proof)}
              disabled={isSubmittingProof || (!manualProof && !proof)}
            >
              {isSubmittingProof ? 'Submitting Proof...' : 'Submit Proof'}
            </Button>
          </div>
        )
      case 'thankYou':
        return (
          <div className="w-full max-w-md text-center">
            <h2 className="text-2xl mb-4">Thank You!</h2>
            <p className="mb-4">
              Thank you for using our A0 ZK Bridge service!
            </p>
            <p className="mb-4">
              Join our <a href="https://discord.gg/zaGHZgtyyw" target="_blank" rel="noopener noreferrer" className="text-blue-400 hover:underline">[Discord server]</a> and follow us on <a href="https://x.com/a0labs" target="_blank" rel="noopener noreferrer" className="text-blue-400 hover:underline">Twitter @a0labs</a>.
            </p>
            <p className="mb-4">
              Feel free to reach out to me on <a href="https://x.com/quantaindew" target="_blank" rel="noopener noreferrer" className="text-blue-400 hover:underline"> @quantaindew on Twitter</a> or Discord (@quantaindew).
            </p>
            <div className="space-y-4">
              <Button 
                className="w-full bg-green-400 text-black hover:bg-green-300 transition-colors"
                onClick={() => setCurrentPage('landing')}
              >
                Return to Home
              </Button>
              <Button 
                className="w-full bg-green-400 text-black hover:bg-green-300 transition-colors"
                onClick={() => setCurrentPage('deposit')}
              >
                Make Another Transaction
              </Button>
            </div>
          </div>
        )
      default:
        return null
    }
  }

  return (
    <main className="min-h-screen bg-black text-green-400 font-mono flex flex-col items-center justify-center p-4">
      <header className="text-4xl mb-8">
        <AsciiArt art="a0" />
      </header>
      
      {renderContent()}
      
      <footer className="mt-16 text-sm">
        <p>&copy;
2023 A0 ZK Bridge. All rights reserved.</p>
      </footer>
    </main>
  )
}

export default App

