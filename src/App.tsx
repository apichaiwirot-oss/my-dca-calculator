import { useState } from 'react'
import { AuthProvider, useAuth } from './contexts/AuthContext'
import LoginPage from './components/LoginPage'
import AverageCostTab from './components/AverageCostTab'
import DCASimulatorTab from './components/DCASimulatorTab'
import CompareTab from './components/CompareTab'
import MarketTicker from './components/MarketTicker'
import NewsTicker from './components/NewsTicker'

type TabId = 'average' | 'simulator' | 'compare'

const TABS: { id: TabId; label: string; icon: string }[] = [
  { id: 'average',   label: 'ลดค่าเฉลี่ย / เพิ่มหุ้น', icon: '📊' },
  { id: 'simulator', label: 'จำลอง DCA',               icon: '📈' },
  { id: 'compare',   label: 'เปรียบเทียบหุ้น',          icon: '⚖️' },
]

function AppContent() {
  const { user, loading, logout } = useAuth()
  const [activeTab, setActiveTab] = useState<TabId>('average')
  const [currency, setCurrency] = useState<'$' | '฿'>('$')

  if (loading) {
    return (
      <div className="min-h-screen bg-[#141414] flex items-center justify-center">
        <div className="flex flex-col items-center gap-4">
          <div className="w-12 h-12 rounded-xl bg-[#E50914] flex items-center justify-center text-white font-black text-xl shadow-lg">
            N
          </div>
          <div className="w-6 h-6 border-2 border-[#E50914] border-t-transparent rounded-full animate-spin" />
        </div>
      </div>
    )
  }

  if (!user) return <LoginPage />

  return (
    <div className="min-h-screen bg-[#141414] text-white">

      {/* ── Netflix-style Header ───────────────────────────── */}
      <header className="bg-[#141414] border-b border-[#1e1e1e] sticky top-0 z-50 netflix-header-gradient">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 py-3 flex items-center justify-between">

          {/* Left: Logo + Title */}
          <div className="flex items-center gap-3">
            <div className="w-9 h-9 rounded-lg bg-[#E50914] flex items-center justify-center font-black text-lg text-white shadow-lg netflix-red-glow">
              N
            </div>
            <div>
              <h1 className="text-base font-bold tracking-tight leading-none">
                DCA<span className="text-[#E50914]"> Calculator</span> Pro
              </h1>
              <p className="text-[10px] text-[#666] mt-0.5 hidden sm:block">
                คำนวณ DCA · ลดค่าเฉลี่ย · เพิ่มทุนกำไร · เปรียบเทียบ
              </p>
            </div>
          </div>

          {/* Right: Currency + User */}
          <div className="flex items-center gap-2">
            <button
              onClick={() => setCurrency(c => (c === '$' ? '฿' : '$'))}
              className="px-3 py-1.5 rounded-lg bg-[#1a1a1a] border border-[#2a2a2a] text-xs font-medium text-[#b3b3b3] hover:border-[#E50914] hover:text-white transition-all"
            >
              {currency === '$' ? '🇺🇸 USD' : '🇹🇭 THB'}
            </button>

            <div className="flex items-center gap-2 pl-2 border-l border-[#2a2a2a]">
              {user.photoURL ? (
                <img src={user.photoURL} alt="avatar" className="w-8 h-8 rounded-full ring-2 ring-[#E50914]/40" />
              ) : (
                <div className="w-8 h-8 rounded-full bg-[#E50914] flex items-center justify-center text-xs font-bold">
                  {(user.displayName || user.email || 'U')[0].toUpperCase()}
                </div>
              )}
              <span className="text-xs text-[#808080] hidden sm:block max-w-[120px] truncate">
                {user.displayName || user.email}
              </span>
              <button
                onClick={logout}
                className="text-xs text-[#555] hover:text-[#E50914] transition-colors px-2 py-1"
              >
                ออก
              </button>
            </div>
          </div>
        </div>
      </header>

      {/* ── Market Indices Ticker ──────────────────────────── */}
      <MarketTicker />

      {/* ── News Ticker ───────────────────────────────────── */}
      <NewsTicker />

      {/* ── Tab Navigation ────────────────────────────────── */}
      <div className="bg-[#141414] border-b border-[#1e1e1e]">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 flex gap-0 pt-1 overflow-x-auto">
          {TABS.map(tab => (
            <button
              key={tab.id}
              onClick={() => setActiveTab(tab.id)}
              className={`px-5 py-3 text-sm font-medium transition-all flex items-center gap-2 border-b-2 -mb-px whitespace-nowrap ${
                activeTab === tab.id
                  ? 'border-[#E50914] text-white bg-[#E50914]/5'
                  : 'border-transparent text-[#808080] hover:text-[#b3b3b3] hover:border-[#444]'
              }`}
            >
              <span>{tab.icon}</span>
              <span>{tab.label}</span>
            </button>
          ))}
        </div>
      </div>

      {/* ── Content ───────────────────────────────────────── */}
      <main className="max-w-7xl mx-auto px-4 sm:px-6 py-6">
        {activeTab === 'average'   && <AverageCostTab currency={currency} userId={user.uid} />}
        {activeTab === 'simulator' && <DCASimulatorTab currency={currency} />}
        {activeTab === 'compare'   && <CompareTab currency={currency} />}
      </main>

      {/* ── Footer ────────────────────────────────────────── */}
      <footer className="text-center text-xs text-[#444] py-6 mt-4 border-t border-[#1e1e1e]">
        <span className="text-[#E50914] font-bold">DCA Calculator Pro</span>
        {' '}— ข้อมูลเพื่อการศึกษาเท่านั้น ไม่ใช่คำแนะนำการลงทุน
      </footer>
    </div>
  )
}

export default function App() {
  return (
    <AuthProvider>
      <AppContent />
    </AuthProvider>
  )
}
