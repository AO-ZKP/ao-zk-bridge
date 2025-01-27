interface AsciiArtProps {
    art: 'a0' | 'bunny';
    className?: string;
  }
  
  export function AsciiArt({ art, className = '' }: AsciiArtProps) {
    const asciiArt = {
      a0: `

      __        ____  ____    
     /""\\      /   ")(  " \\   
    /    \\    /. __/  \\__. \\  
   /' /\\  \\  // /  \\\\    ) :) 
  //  __'  \\(: (___ \\\\__/ //  
 /   /  \\\\  \\\\     ) /"   /   
(___/    \\___)\\"__/ (____/    
                          
  `,
      bunny: `
      
{\\__/}
( • . •)
/ >♥️
    ZK Bridge
  `
    };
  
    return (
      <pre className={className}>
        {asciiArt[art]}
      </pre>
    )
  }
  
  