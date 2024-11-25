import { Button } from "@/components/ui/button"
import { AsciiArt } from "@/components/ascii-art"

function App() {
  return (
    <main className="min-h-screen bg-black text-green-400 font-mono flex flex-col items-center justify-center p-4">
      <header className="text-4xl mb-8">
        <AsciiArt art="a0" />
      </header>
      
      <div className="text-center">
        <AsciiArt art="bunny" className="mb-8 text-xs sm:text-sm md:text-base" />
        
        <h1 className="text-2xl md:text-4xl mb-4">Welcome to A0 ZK Bridge</h1>
        
        <p className="mb-8 max-w-md">
          Hop into the future of secure, private cross-chain transactions with our zero-knowledge bridge. It's fast, it's fuzzy, it's fantastic!
        </p>
        
        <Button className="bg-green-400 text-black hover:bg-green-300 transition-colors">
          Launch Bridge
        </Button>
      </div>
      
      <footer className="mt-16 text-sm">
        <p>&copy; 2023 A0 ZK Bridge. All rights reserved.</p>
      </footer>
    </main>
  )
}

export default App
