import { useState } from 'react'
import AverageCostTab from './components/AverageCostTab'
import DCASimulatorTab from './components/DCASimulatorTab'
import CompareTab from './components/CompareTab'

type TabId = 'average' | 'simulator' | 'compare'

const TABS: { id: TabId; label: string; icon: string }[] = [
  { id: 'average', label: 'ลดค่าเฉลี่ย / เพิ่มหุ้น', icon: '📊' },
  { id: 'simulator', label: 'จำลอง DCA', icon: '📈' },
  { id: 'compare', label: 'เปรียบเทียบหุ้น', icon: '⚖️' },
]

export default function App() {
  const [activeTab, setActiveTab] = useState<TabId>('average')
  const [currency, setCurrency] = useState<'$' | '฿'>('$')

  return (
    <div className="min-h-screen bg-[#0d1117] text-[#e6edf3]">
      {/* Header */}
      <header className="border-b border-[#21262d]">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 py-4 flex items-center justify-between">
          <div>
            <div className="flex items-center gap-3">
              <div className="w-8 h-8 rounded-lg bg-gradient-to-br from-teal-400 to-cyan-600 flex items-center justify-center font-bold text-sm text-white shadow-lg shadow-teal-900/40">
                D
              </div>
              <h1 className="text-lg font-bold tracking-tight">DCA Calculator Pro</h1>
            </div>
            <p className="text-xs text-[#7d8590] mt-0.5 ml-11">
              คำนวณ DCA · ลดค่าเฉลี่ย · เพิ่มทุนกำไร · เปรียบเทียบ — USD / THB
            </p>
          </div>
          {/* Currency Toggle */}
          <button
            onClick={() => setCurrency(c => (c === '$' ? '฿' : '$'))}
            className="px-3 py-1.5 rounded-lg bg-[#161b22] border border-[#30363d] text-sm font-medium hover:border-teal-500 transition-colors"
          >
            {currency === '$' ? '🇺🇸 USD' : '🇹🇭 THB'}
          </button>
        </div>
      </header>

      {/* Tab Bar */}
      <div className="border-b border-[#21262d]">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 flex gap-1 pt-2">
          {TABS.map(tab => (
            <button
              key={tab.id}
              onClick={() => setActiveTab(tab.id)}
              className={`px-4 py-2.5 rounded-t-lg text-sm font-medium transition-all flex items-center gap-2 border-b-2 -mb-px ${
                activeTab === tab.id
                  ? 'border-teal-400 text-teal-400 bg-teal-950/20'
                  : 'border-transparent text-[#7d8590] hover:text-[#e6edf3] hover:border-[#30363d]'
              }`}
            >
              <span>{tab.icon}</span>
              <span>{tab.label}</span>
            </button>
          ))}
        </div>
      </div>

      {/* Content */}
      <main className="max-w-7xl mx-auto px-4 sm:px-6 py-6">
        {activeTab === 'average' && <AverageCostTab currency={currency} />}
        {activeTab === 'simulator' && <DCASimulatorTab currency={currency} />}
        {activeTab === 'compare' && <CompareTab currency={currency} />}
      </main>

      {/* Footer */}
      <footer className="text-center text-xs text-[#484f58] py-6 mt-4 border-t border-[#21262d]">
        DCA Calculator Pro — ข้อมูลเพื่อการศึกษาเท่านั้น ไม่ใช่คำแนะนำการลงทุน
      </footer>
    </div>
  )
}
