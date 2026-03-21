import { useState, useEffect } from 'react'

interface IndexData {
  name: string
  price: number
  change: number
  changePct: number
  flag: string
  decimals: number
}

const INITIAL_DATA: IndexData[] = [
  { name: 'S&P 500',     price: 5463.54,  change:  28.01,   changePct:  0.52,  flag: '🇺🇸', decimals: 2 },
  { name: 'NASDAQ',      price: 17732.60, change: -45.20,   changePct: -0.25,  flag: '🇺🇸', decimals: 2 },
  { name: 'Dow Jones',   price: 42214.50, change:  156.30,  changePct:  0.37,  flag: '🇺🇸', decimals: 2 },
  { name: 'Nikkei 225',  price: 38142.00, change: -234.50,  changePct: -0.61,  flag: '🇯🇵', decimals: 2 },
  { name: 'SET Index',   price: 1321.45,  change:   5.67,   changePct:  0.43,  flag: '🇹🇭', decimals: 2 },
  { name: 'Hang Seng',   price: 18234.00, change:  89.20,   changePct:  0.49,  flag: '🇭🇰', decimals: 2 },
  { name: 'FTSE 100',    price: 8231.00,  change: -12.50,   changePct: -0.15,  flag: '🇬🇧', decimals: 2 },
  { name: 'DAX',         price: 22401.00, change:  89.50,   changePct:  0.40,  flag: '🇩🇪', decimals: 2 },
  { name: 'Gold/oz',     price: 3053.20,  change:  12.80,   changePct:  0.42,  flag: '🥇', decimals: 2 },
  { name: 'Bitcoin',     price: 84250.00, change: -1250.00, changePct: -1.46,  flag: '₿',  decimals: 0 },
  { name: 'Ethereum',    price: 1842.50,  change: -28.30,   changePct: -1.51,  flag: '⟠',  decimals: 2 },
  { name: 'USD/THB',     price: 34.15,    change:   0.08,   changePct:  0.23,  flag: '💱', decimals: 2 },
]

export default function MarketTicker() {
  const [data, setData] = useState<IndexData[]>(INITIAL_DATA)
  const [time, setTime] = useState(new Date())

  useEffect(() => {
    const interval = setInterval(() => {
      setData(prev =>
        prev.map(item => {
          const delta = (Math.random() - 0.48) * item.price * 0.0008
          const newPrice = Math.max(0.01, item.price + delta)
          const newChange = item.change + delta
          const base = newPrice - newChange
          const newChangePct = base !== 0 ? (newChange / base) * 100 : 0
          return { ...item, price: newPrice, change: newChange, changePct: newChangePct }
        })
      )
      setTime(new Date())
    }, 4000)
    return () => clearInterval(interval)
  }, [])

  // Duplicate items for seamless infinite loop
  const items = [...data, ...data]

  return (
    <div className="bg-[#0a0a0a] border-b border-[#1e1e1e] overflow-hidden" style={{ height: '34px' }}>
      <div className="flex items-stretch h-full">
        {/* LIVE badge */}
        <div className="flex-shrink-0 flex items-center gap-1.5 px-4 bg-[#E50914] z-10">
          <span className="w-1.5 h-1.5 bg-white rounded-full animate-pulse" />
          <span className="text-white text-[10px] font-black tracking-widest">LIVE</span>
        </div>

        {/* Scrolling track */}
        <div className="flex-1 overflow-hidden relative">
          <div className="ticker-track h-full items-center">
            {items.map((item, i) => (
              <div
                key={i}
                className="flex items-center gap-2 px-5 h-full flex-shrink-0 border-r border-[#1e1e1e]"
              >
                <span className="text-sm leading-none">{item.flag}</span>
                <span className="text-[#666] text-[11px] font-medium uppercase tracking-wide whitespace-nowrap">
                  {item.name}
                </span>
                <span className="text-white text-[12px] font-semibold font-mono whitespace-nowrap">
                  {item.price.toLocaleString('en-US', {
                    minimumFractionDigits: item.decimals,
                    maximumFractionDigits: item.decimals,
                  })}
                </span>
                <span
                  className={`text-[11px] font-mono font-medium whitespace-nowrap ${
                    item.changePct >= 0 ? 'text-[#46d369]' : 'text-[#E50914]'
                  }`}
                >
                  {item.changePct >= 0 ? '▲' : '▼'} {Math.abs(item.changePct).toFixed(2)}%
                </span>
              </div>
            ))}
          </div>
        </div>

        {/* Clock */}
        <div className="flex-shrink-0 flex items-center px-3 border-l border-[#1e1e1e] bg-[#0a0a0a]">
          <span className="text-[#444] text-[10px] font-mono">
            {time.toLocaleTimeString('th-TH', { hour: '2-digit', minute: '2-digit', second: '2-digit' })}
          </span>
        </div>
      </div>
    </div>
  )
}
