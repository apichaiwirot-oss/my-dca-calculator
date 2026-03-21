import { useState, useCallback, useEffect, useRef } from 'react'
import { Plus, Trash2, TrendingUp, TrendingDown, Target, AlertCircle, Save, Upload, CheckCircle } from 'lucide-react'
import { doc, setDoc, getDoc } from 'firebase/firestore'
import { db } from '../lib/firebase'
import { BuyRound, calcPortfolio, sharesNeededToReachTarget, fmt, fmtCurrency } from '../lib/calculations'

interface Props {
  currency: string
  userId: string
}

let roundId = 0
function newRound(shares = 0, price = 0): BuyRound {
  return { id: `r${++roundId}`, shares, pricePerShare: price }
}

function parseCSV(text: string): BuyRound[] {
  const lines = text.split('\n').filter(l => l.trim())
  const rounds: BuyRound[] = []
  for (const line of lines) {
    // Skip header lines
    if (/shares|หุ้น|price|ราคา|qty|quantity/i.test(line)) continue
    const cols = line.split(/[,\t;]/).map(c => c.trim().replace(/[^0-9.]/g, ''))
    const a = parseFloat(cols[0])
    const b = parseFloat(cols[1])
    if (!isNaN(a) && !isNaN(b) && a > 0 && b > 0) {
      rounds.push(newRound(a, b))
    }
  }
  return rounds
}

export default function AverageCostTab({ currency, userId }: Props) {
  const [symbol, setSymbol] = useState('')
  const [rounds, setRounds] = useState<BuyRound[]>([newRound(100, 150)])
  const [currentPrice, setCurrentPrice] = useState<number>(170)
  const [addShares, setAddShares] = useState<number>(0)
  const [addPrice, setAddPrice] = useState<number>(0)
  const [targetAvg, setTargetAvg] = useState<number>(0)
  const [saving, setSaving] = useState(false)
  const [saved, setSaved] = useState(false)
  const [loadingData, setLoadingData] = useState(true)
  const fileRef = useRef<HTMLInputElement>(null)

  // Load from Firestore on mount
  useEffect(() => {
    const load = async () => {
      try {
        const snap = await getDoc(doc(db, 'portfolios', userId))
        if (snap.exists()) {
          const data = snap.data()
          if (data.symbol) setSymbol(data.symbol)
          if (data.currentPrice) setCurrentPrice(data.currentPrice)
          if (data.rounds?.length) setRounds(data.rounds)
        }
      } catch (e) {
        console.error('Load error:', e)
      } finally {
        setLoadingData(false)
      }
    }
    load()
  }, [userId])

  const saveToFirestore = async () => {
    setSaving(true)
    try {
      await setDoc(doc(db, 'portfolios', userId), {
        symbol,
        currentPrice,
        rounds,
        updatedAt: new Date().toISOString(),
      })
      setSaved(true)
      setTimeout(() => setSaved(false), 2000)
    } catch (e) {
      console.error('Save error:', e)
    } finally {
      setSaving(false)
    }
  }

  const handleCSVUpload = (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0]
    if (!file) return
    const reader = new FileReader()
    reader.onload = ev => {
      const text = ev.target?.result as string
      const parsed = parseCSV(text)
      if (parsed.length > 0) {
        setRounds(parsed)
        // Try to get symbol from filename
        const name = file.name.replace(/\.[^.]+$/, '').toUpperCase()
        if (name && !name.includes('EXPORT') && !name.includes('DATA')) {
          setSymbol(name)
        }
      } else {
        alert('ไม่พบข้อมูลที่ถูกต้องในไฟล์ กรุณาตรวจสอบรูปแบบ CSV\n\nรูปแบบที่รองรับ: จำนวนหุ้น, ราคาต่อหุ้น (แต่ละรอบ 1 บรรทัด)')
      }
    }
    reader.readAsText(file)
    e.target.value = ''
  }

  const updateRound = useCallback((id: string, field: 'shares' | 'pricePerShare', val: number) => {
    setRounds(prev => prev.map(r => r.id === id ? { ...r, [field]: val } : r))
  }, [])

  const removeRound = useCallback((id: string) => {
    setRounds(prev => prev.length > 1 ? prev.filter(r => r.id !== id) : prev)
  }, [])

  const addRound = () => setRounds(prev => [...prev, newRound()])

  const stats = calcPortfolio(rounds, currentPrice)
  const isProfit = stats.profitLoss >= 0

  const newRounds = addShares > 0 && addPrice > 0
    ? [...rounds, newRound(addShares, addPrice)]
    : rounds
  const previewStats = calcPortfolio(newRounds, currentPrice)
  const hasPreview = addShares > 0 && addPrice > 0

  const sharesNeeded = targetAvg > 0 && addPrice > 0
    ? sharesNeededToReachTarget(stats.totalShares, stats.averageCost, addPrice, targetAvg)
    : null

  if (loadingData) {
    return (
      <div className="flex items-center justify-center py-20">
        <div className="w-6 h-6 border-2 border-[#E50914] border-t-transparent rounded-full animate-spin" />
        <span className="ml-3 text-[#808080] text-sm">กำลังโหลดข้อมูลพอร์ต...</span>
      </div>
    )
  }

  return (
    <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
      {/* LEFT: Input */}
      <div className="space-y-5">
        {/* Stock Info */}
        <div className="bg-[#1a1a1a] border border-[#2a2a2a] rounded-xl p-5">
          <div className="flex items-center justify-between mb-4">
            <h2 className="text-sm font-semibold text-[#808080] uppercase tracking-wider flex items-center gap-2">
              <span className="w-2 h-2 rounded-full bg-[#E50914] inline-block" />
              ข้อมูลหุ้น
            </h2>
            <div className="flex gap-2">
              {/* CSV Import */}
              <input ref={fileRef} type="file" accept=".csv,.txt" className="hidden" onChange={handleCSVUpload} />
              <button
                onClick={() => fileRef.current?.click()}
                className="flex items-center gap-1.5 px-3 py-1.5 rounded-lg bg-[#141414] border border-[#2a2a2a] text-xs text-[#808080] hover:text-white hover:border-[#555] transition-colors"
              >
                <Upload size={12} /> Import CSV
              </button>
              {/* Save */}
              <button
                onClick={saveToFirestore}
                disabled={saving}
                className={`flex items-center gap-1.5 px-3 py-1.5 rounded-lg text-xs font-medium transition-colors ${
                  saved
                    ? 'bg-green-900/30 border border-green-700 text-green-400'
                    : 'bg-red-900/20 border border-[#b91c1c] text-[#E50914] hover:bg-red-900/30'
                } disabled:opacity-60`}
              >
                {saved ? <CheckCircle size={12} /> : <Save size={12} />}
                {saving ? 'กำลังบันทึก...' : saved ? 'บันทึกแล้ว!' : 'บันทึก'}
              </button>
            </div>
          </div>

          <div className="mb-4">
            <label className="block text-xs text-[#808080] mb-1.5">ชื่อหุ้น / SYMBOL</label>
            <input
              type="text"
              value={symbol}
              onChange={e => setSymbol(e.target.value.toUpperCase())}
              placeholder="AAPL, NVDA, BTC, PTT.BK ..."
              className="w-full bg-[#141414] border border-[#2a2a2a] rounded-lg px-3 py-2.5 text-sm focus:border-[#E50914] focus:outline-none transition-colors placeholder-[#555]"
            />
          </div>

          {/* CSV Format hint */}
          <div className="mb-4 p-3 rounded-lg bg-[#141414] border border-[#1e1e1e] text-xs text-[#555]">
            📋 รูปแบบ CSV: <code className="text-[#E50914]">จำนวนหุ้น, ราคา</code> (แต่ละรอบ 1 บรรทัด)
            <br/>ตัวอย่าง: <code className="text-[#808080]">100, 150.50</code>
          </div>

          {/* Buy Rounds */}
          <div>
            <div className="flex items-center justify-between mb-2">
              <label className="text-xs text-[#808080]">รอบการซื้อ</label>
              <span className="text-xs text-[#555]">{rounds.length} รอบ</span>
            </div>
            <div className="space-y-2">
              <div className="grid grid-cols-12 gap-2 text-xs text-[#555] px-1">
                <span className="col-span-1">#</span>
                <span className="col-span-5">จำนวนหุ้น</span>
                <span className="col-span-5">ราคา ({currency})</span>
                <span className="col-span-1" />
              </div>
              {rounds.map((r, i) => (
                <div key={r.id} className="grid grid-cols-12 gap-2 items-center">
                  <span className="col-span-1 text-xs text-[#555] text-center">{i + 1}</span>
                  <input
                    type="number" min="0" value={r.shares || ''}
                    onChange={e => updateRound(r.id, 'shares', parseFloat(e.target.value) || 0)}
                    placeholder="100"
                    className="col-span-5 bg-[#141414] border border-[#2a2a2a] rounded-lg px-3 py-2 text-sm focus:border-[#E50914] focus:outline-none transition-colors"
                  />
                  <input
                    type="number" min="0" step="0.01" value={r.pricePerShare || ''}
                    onChange={e => updateRound(r.id, 'pricePerShare', parseFloat(e.target.value) || 0)}
                    placeholder="150.00"
                    className="col-span-5 bg-[#141414] border border-[#2a2a2a] rounded-lg px-3 py-2 text-sm focus:border-[#E50914] focus:outline-none transition-colors"
                  />
                  <button
                    onClick={() => removeRound(r.id)}
                    disabled={rounds.length === 1}
                    className="col-span-1 p-1.5 rounded-lg text-[#555] hover:text-red-400 hover:bg-red-950/30 disabled:opacity-30 disabled:cursor-not-allowed transition-colors"
                  >
                    <Trash2 size={13} />
                  </button>
                </div>
              ))}
            </div>
            <button
              onClick={addRound}
              className="mt-3 w-full flex items-center justify-center gap-2 py-2 rounded-lg border border-dashed border-[#2a2a2a] text-xs text-[#808080] hover:border-[#E50914] hover:text-[#E50914] transition-colors"
            >
              <Plus size={13} /> เพิ่มรอบการซื้อ
            </button>
          </div>

          {/* Current Price */}
          <div className="mt-4">
            <label className="block text-xs text-[#808080] mb-1.5">ราคาตลาดปัจจุบัน ({currency})</label>
            <div className="relative">
              <span className="absolute left-3 top-1/2 -translate-y-1/2 text-sm text-[#808080]">{currency}</span>
              <input
                type="number" min="0" step="0.01" value={currentPrice || ''}
                onChange={e => setCurrentPrice(parseFloat(e.target.value) || 0)}
                className="w-full bg-[#141414] border border-[#2a2a2a] rounded-lg pl-8 pr-3 py-2.5 text-sm focus:border-[#E50914] focus:outline-none transition-colors"
                placeholder="170.00"
              />
            </div>
          </div>
        </div>

        {/* Add More Shares */}
        <div className="bg-[#1a1a1a] border border-[#2a2a2a] rounded-xl p-5">
          <h2 className="text-sm font-semibold text-[#808080] uppercase tracking-wider mb-4 flex items-center gap-2">
            <span className="w-2 h-2 rounded-full bg-white inline-block" />
            จำลองการซื้อเพิ่ม
          </h2>
          <div className="grid grid-cols-2 gap-3 mb-3">
            <div>
              <label className="block text-xs text-[#808080] mb-1.5">จำนวนหุ้น</label>
              <input
                type="number" min="0" value={addShares || ''}
                onChange={e => setAddShares(parseFloat(e.target.value) || 0)}
                placeholder="50"
                className="w-full bg-[#141414] border border-[#2a2a2a] rounded-lg px-3 py-2.5 text-sm focus:border-[#E50914] focus:outline-none transition-colors"
              />
            </div>
            <div>
              <label className="block text-xs text-[#808080] mb-1.5">ราคาที่จะซื้อ ({currency})</label>
              <div className="relative">
                <span className="absolute left-3 top-1/2 -translate-y-1/2 text-sm text-[#808080]">{currency}</span>
                <input
                  type="number" min="0" step="0.01" value={addPrice || ''}
                  onChange={e => setAddPrice(parseFloat(e.target.value) || 0)}
                  placeholder="130.00"
                  className="w-full bg-[#141414] border border-[#2a2a2a] rounded-lg pl-8 pr-3 py-2.5 text-sm focus:border-[#E50914] focus:outline-none transition-colors"
                />
              </div>
            </div>
          </div>
          {hasPreview && (
            <div className="p-3 rounded-lg bg-[#1a1a1a] border border-[#2a2a2a] text-sm">
              <div className="flex items-center gap-2 text-[#b3b3b3] text-xs mb-2 font-medium">
                <AlertCircle size={12} /> ผลหลังซื้อเพิ่ม
              </div>
              <div className="grid grid-cols-2 gap-2 text-xs">
                <div>
                  <div className="text-[#808080]">ต้นทุนเฉลี่ยใหม่</div>
                  <div className="font-semibold text-[#e0e0e0]">{fmtCurrency(previewStats.averageCost, currency)}</div>
                </div>
                <div>
                  <div className="text-[#808080]">เปลี่ยนจากเดิม</div>
                  <div className={`font-semibold ${previewStats.averageCost < stats.averageCost ? 'text-green-400' : 'text-red-400'}`}>
                    {previewStats.averageCost < stats.averageCost ? '▼' : '▲'} {fmtCurrency(Math.abs(previewStats.averageCost - stats.averageCost), currency)}
                  </div>
                </div>
                <div>
                  <div className="text-[#808080]">หุ้นรวม</div>
                  <div className="font-semibold">{fmt(previewStats.totalShares)} หุ้น</div>
                </div>
                <div>
                  <div className="text-[#808080]">ลงทุนรวม</div>
                  <div className="font-semibold">{fmtCurrency(previewStats.totalInvested, currency)}</div>
                </div>
              </div>
            </div>
          )}

          {/* Target Avg */}
          <div className="mt-4 pt-4 border-t border-[#1e1e1e]">
            <div className="flex items-center gap-2 text-xs text-[#808080] mb-2">
              <Target size={12} className="text-yellow-400" />
              ต้องการลด average ลงเหลือ ({currency})
            </div>
            <div className="relative">
              <span className="absolute left-3 top-1/2 -translate-y-1/2 text-sm text-[#808080]">{currency}</span>
              <input
                type="number" min="0" step="0.01" value={targetAvg || ''}
                onChange={e => setTargetAvg(parseFloat(e.target.value) || 0)}
                placeholder="target avg..."
                className="w-full bg-[#141414] border border-[#2a2a2a] rounded-lg pl-8 pr-3 py-2.5 text-sm focus:border-yellow-500 focus:outline-none transition-colors"
              />
            </div>
            {sharesNeeded !== null && addPrice > 0 && targetAvg > 0 && (
              <div className="mt-2 p-3 rounded-lg bg-yellow-950/20 border border-yellow-900/40">
                {sharesNeeded > 0 ? (
                  <p className="text-xs text-yellow-300">
                    ต้องซื้อเพิ่ม <span className="font-bold text-yellow-200">{fmt(sharesNeeded)} หุ้น</span> ที่ราคา {fmtCurrency(addPrice, currency)}
                    <br /><span className="text-yellow-500">ใช้เงินเพิ่ม: {fmtCurrency(sharesNeeded * addPrice, currency)}</span>
                  </p>
                ) : (
                  <p className="text-xs text-[#808080]">ราคาซื้อต้องต่ำกว่า target และ avg ปัจจุบัน</p>
                )}
              </div>
            )}
          </div>
        </div>
      </div>

      {/* RIGHT: Results */}
      <div className="space-y-4">
        <div className="bg-gradient-to-br from-[#1a0000] to-[#141414] border border-red-900/30 rounded-xl p-6 text-center">
          <p className="text-xs text-[#808080] mb-1">มูลค่าพอร์ตปัจจุบัน{symbol ? ` · ${symbol}` : ''}</p>
          <div className={`text-4xl font-bold tracking-tight mb-1 ${isProfit ? 'text-[#ff6b6b]' : 'text-red-300'}`}>
            {fmtCurrency(stats.currentValue, currency)}
          </div>
          <div className={`flex items-center justify-center gap-2 text-sm font-medium ${isProfit ? 'text-green-400' : 'text-red-400'}`}>
            {isProfit ? <TrendingUp size={16} /> : <TrendingDown size={16} />}
            <span>{isProfit ? '+' : ''}{fmtCurrency(stats.profitLoss, currency)} ({isProfit ? '+' : ''}{fmt(stats.profitLossPercent)}%)</span>
          </div>
        </div>

        <div className="grid grid-cols-2 gap-3">
          <StatCard label="ต้นทุนเฉลี่ย" value={fmtCurrency(stats.averageCost, currency)} sub="ต่อหุ้น" />
          <StatCard label="จำนวนหุ้นทั้งหมด" value={fmt(stats.totalShares)} sub="หุ้น" />
          <StatCard label="เงินลงทุนรวม" value={fmtCurrency(stats.totalInvested, currency)} sub="ต้นทุนทั้งหมด" />
          <StatCard
            label="กำไร / ขาดทุน"
            value={(isProfit ? '+' : '') + fmtCurrency(stats.profitLoss, currency)}
            sub={`${isProfit ? '+' : ''}${fmt(stats.profitLossPercent)}% ROI`}
            color={isProfit ? 'text-green-400' : 'text-red-400'}
          />
        </div>

        {stats.totalShares > 0 && (
          <div className="bg-[#1a1a1a] border border-[#2a2a2a] rounded-xl p-4">
            <h3 className="text-xs font-semibold text-[#808080] uppercase tracking-wider mb-3">วิเคราะห์</h3>
            <div className="space-y-2.5 text-sm">
              <InfoRow label="ราคา break-even" value={fmtCurrency(stats.averageCost, currency)} hint="คืนทุนที่ราคานี้" />
              <InfoRow
                label="% จากราคาปัจจุบัน"
                value={`${fmt(((currentPrice - stats.averageCost) / stats.averageCost) * 100)}%`}
                hint={currentPrice > stats.averageCost ? 'สูงกว่าต้นทุน' : 'ต่ำกว่าต้นทุน'}
                valueColor={currentPrice >= stats.averageCost ? 'text-green-400' : 'text-red-400'}
              />
              <InfoRow label="ถ้าราคา +10%" value={fmtCurrency(stats.totalShares * currentPrice * 1.1, currency)} hint={`+${fmtCurrency(stats.totalShares * currentPrice * 0.1, currency)}`} />
              <InfoRow label="ถ้าราคา -10%" value={fmtCurrency(stats.totalShares * currentPrice * 0.9, currency)} hint={`-${fmtCurrency(stats.totalShares * currentPrice * 0.1, currency)}`} valueColor="text-[#808080]" />
            </div>
          </div>
        )}

        {rounds.length > 1 && (
          <div className="bg-[#1a1a1a] border border-[#2a2a2a] rounded-xl p-4">
            <h3 className="text-xs font-semibold text-[#808080] uppercase tracking-wider mb-3">สรุปรอบการซื้อ</h3>
            <div className="space-y-1.5">
              {rounds.map((r, i) => {
                if (!r.shares || !r.pricePerShare) return null
                const pnl = r.shares * currentPrice - r.shares * r.pricePerShare
                return (
                  <div key={r.id} className="flex items-center justify-between text-xs">
                    <span className="text-[#808080]">รอบ {i + 1}</span>
                    <span>{fmt(r.shares)} × {fmtCurrency(r.pricePerShare, currency)}</span>
                    <span className={pnl >= 0 ? 'text-green-400' : 'text-red-400'}>
                      {pnl >= 0 ? '+' : ''}{fmtCurrency(pnl, currency)}
                    </span>
                  </div>
                )
              })}
            </div>
          </div>
        )}
      </div>
    </div>
  )
}

function StatCard({ label, value, sub, color = 'text-white' }: { label: string; value: string; sub: string; color?: string }) {
  return (
    <div className="bg-[#1a1a1a] border border-[#2a2a2a] rounded-xl p-4">
      <p className="text-xs text-[#808080] mb-1">{label}</p>
      <p className={`text-lg font-bold ${color}`}>{value}</p>
      <p className="text-xs text-[#555]">{sub}</p>
    </div>
  )
}

function InfoRow({ label, value, hint, valueColor = 'text-white' }: { label: string; value: string; hint: string; valueColor?: string }) {
  return (
    <div className="flex items-center justify-between">
      <div>
        <span className="text-[#808080]">{label}</span>
        <span className="text-xs text-[#555] ml-2">{hint}</span>
      </div>
      <span className={`font-semibold ${valueColor}`}>{value}</span>
    </div>
  )
}
