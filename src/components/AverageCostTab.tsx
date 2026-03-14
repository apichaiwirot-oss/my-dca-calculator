import { useState, useCallback } from 'react'
import { Plus, Trash2, TrendingUp, TrendingDown, Target, AlertCircle } from 'lucide-react'
import { BuyRound, calcPortfolio, sharesNeededToReachTarget, fmt, fmtCurrency } from '../lib/calculations'

interface Props {
  currency: string
}

let roundId = 0
function newRound(shares = 0, price = 0): BuyRound {
  return { id: `r${++roundId}`, shares, pricePerShare: price }
}

export default function AverageCostTab({ currency }: Props) {
  const [symbol, setSymbol] = useState('')
  const [rounds, setRounds] = useState<BuyRound[]>([newRound(100, 150)])
  const [currentPrice, setCurrentPrice] = useState<number>(170)
  const [addShares, setAddShares] = useState<number>(0)
  const [addPrice, setAddPrice] = useState<number>(0)
  const [targetAvg, setTargetAvg] = useState<number>(0)

  const updateRound = useCallback((id: string, field: 'shares' | 'pricePerShare', val: number) => {
    setRounds(prev => prev.map(r => r.id === id ? { ...r, [field]: val } : r))
  }, [])

  const removeRound = useCallback((id: string) => {
    setRounds(prev => prev.length > 1 ? prev.filter(r => r.id !== id) : prev)
  }, [])

  const addRound = () => setRounds(prev => [...prev, newRound()])

  // Current portfolio stats
  const stats = calcPortfolio(rounds, currentPrice)
  const isProfit = stats.profitLoss >= 0

  // Preview: what if we add more shares?
  const newRounds = addShares > 0 && addPrice > 0
    ? [...rounds, newRound(addShares, addPrice)]
    : rounds
  const previewStats = calcPortfolio(newRounds, currentPrice)
  const hasPreview = addShares > 0 && addPrice > 0

  // Shares needed to reach target average
  const sharesNeeded = targetAvg > 0 && addPrice > 0
    ? sharesNeededToReachTarget(stats.totalShares, stats.averageCost, addPrice, targetAvg)
    : null

  return (
    <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
      {/* LEFT: Input */}
      <div className="space-y-5">
        {/* Stock Info */}
        <div className="bg-[#161b22] border border-[#30363d] rounded-xl p-5">
          <h2 className="text-sm font-semibold text-[#7d8590] uppercase tracking-wider mb-4 flex items-center gap-2">
            <span className="w-2 h-2 rounded-full bg-teal-400 inline-block" />
            ข้อมูลหุ้น
          </h2>

          <div className="mb-4">
            <label className="block text-xs text-[#7d8590] mb-1.5">ชื่อหุ้น / SYMBOL (ไม่บังคับ)</label>
            <input
              type="text"
              value={symbol}
              onChange={e => setSymbol(e.target.value.toUpperCase())}
              placeholder="AAPL, NVDA, BTC, PTT.BK ..."
              className="w-full bg-[#0d1117] border border-[#30363d] rounded-lg px-3 py-2.5 text-sm focus:border-teal-500 focus:outline-none transition-colors placeholder-[#484f58]"
            />
          </div>

          {/* Buy Rounds Table */}
          <div>
            <div className="flex items-center justify-between mb-2">
              <label className="text-xs text-[#7d8590]">รอบการซื้อ</label>
              <span className="text-xs text-[#484f58]">{rounds.length} รอบ</span>
            </div>

            <div className="space-y-2">
              <div className="grid grid-cols-12 gap-2 text-xs text-[#484f58] px-1">
                <span className="col-span-1">#</span>
                <span className="col-span-5">จำนวนหุ้น</span>
                <span className="col-span-5">ราคาต่อหุ้น ({currency})</span>
                <span className="col-span-1" />
              </div>

              {rounds.map((r, i) => (
                <div key={r.id} className="grid grid-cols-12 gap-2 items-center">
                  <span className="col-span-1 text-xs text-[#484f58] text-center">{i + 1}</span>
                  <input
                    type="number"
                    min="0"
                    value={r.shares || ''}
                    onChange={e => updateRound(r.id, 'shares', parseFloat(e.target.value) || 0)}
                    placeholder="100"
                    className="col-span-5 bg-[#0d1117] border border-[#30363d] rounded-lg px-3 py-2 text-sm focus:border-teal-500 focus:outline-none transition-colors"
                  />
                  <input
                    type="number"
                    min="0"
                    step="0.01"
                    value={r.pricePerShare || ''}
                    onChange={e => updateRound(r.id, 'pricePerShare', parseFloat(e.target.value) || 0)}
                    placeholder="150.00"
                    className="col-span-5 bg-[#0d1117] border border-[#30363d] rounded-lg px-3 py-2 text-sm focus:border-teal-500 focus:outline-none transition-colors"
                  />
                  <button
                    onClick={() => removeRound(r.id)}
                    disabled={rounds.length === 1}
                    className="col-span-1 p-1.5 rounded-lg text-[#484f58] hover:text-red-400 hover:bg-red-950/30 disabled:opacity-30 disabled:cursor-not-allowed transition-colors"
                  >
                    <Trash2 size={13} />
                  </button>
                </div>
              ))}
            </div>

            <button
              onClick={addRound}
              className="mt-3 w-full flex items-center justify-center gap-2 py-2 rounded-lg border border-dashed border-[#30363d] text-xs text-[#7d8590] hover:border-teal-500 hover:text-teal-400 transition-colors"
            >
              <Plus size={13} /> เพิ่มรอบการซื้อ
            </button>
          </div>

          {/* Current Price */}
          <div className="mt-4">
            <label className="block text-xs text-[#7d8590] mb-1.5">ราคาตลาดปัจจุบัน ({currency})</label>
            <div className="relative">
              <span className="absolute left-3 top-1/2 -translate-y-1/2 text-sm text-[#7d8590]">{currency}</span>
              <input
                type="number"
                min="0"
                step="0.01"
                value={currentPrice || ''}
                onChange={e => setCurrentPrice(parseFloat(e.target.value) || 0)}
                className="w-full bg-[#0d1117] border border-[#30363d] rounded-lg pl-8 pr-3 py-2.5 text-sm focus:border-teal-500 focus:outline-none transition-colors"
                placeholder="170.00"
              />
            </div>
          </div>
        </div>

        {/* Add More Shares Section */}
        <div className="bg-[#161b22] border border-[#30363d] rounded-xl p-5">
          <h2 className="text-sm font-semibold text-[#7d8590] uppercase tracking-wider mb-4 flex items-center gap-2">
            <span className="w-2 h-2 rounded-full bg-cyan-400 inline-block" />
            จำลองการซื้อเพิ่ม
          </h2>

          <div className="grid grid-cols-2 gap-3 mb-3">
            <div>
              <label className="block text-xs text-[#7d8590] mb-1.5">จำนวนหุ้นที่จะซื้อเพิ่ม</label>
              <input
                type="number"
                min="0"
                value={addShares || ''}
                onChange={e => setAddShares(parseFloat(e.target.value) || 0)}
                placeholder="50"
                className="w-full bg-[#0d1117] border border-[#30363d] rounded-lg px-3 py-2.5 text-sm focus:border-cyan-500 focus:outline-none transition-colors"
              />
            </div>
            <div>
              <label className="block text-xs text-[#7d8590] mb-1.5">ราคาที่จะซื้อ ({currency})</label>
              <div className="relative">
                <span className="absolute left-3 top-1/2 -translate-y-1/2 text-sm text-[#7d8590]">{currency}</span>
                <input
                  type="number"
                  min="0"
                  step="0.01"
                  value={addPrice || ''}
                  onChange={e => setAddPrice(parseFloat(e.target.value) || 0)}
                  placeholder="130.00"
                  className="w-full bg-[#0d1117] border border-[#30363d] rounded-lg pl-8 pr-3 py-2.5 text-sm focus:border-cyan-500 focus:outline-none transition-colors"
                />
              </div>
            </div>
          </div>

          {hasPreview && (
            <div className="p-3 rounded-lg bg-cyan-950/20 border border-cyan-900/40 text-sm">
              <div className="flex items-center gap-2 text-cyan-400 text-xs mb-2 font-medium">
                <AlertCircle size={12} /> ผลหลังซื้อเพิ่ม
              </div>
              <div className="grid grid-cols-2 gap-2 text-xs">
                <div>
                  <div className="text-[#7d8590]">ต้นทุนเฉลี่ยใหม่</div>
                  <div className="font-semibold text-cyan-300">{fmtCurrency(previewStats.averageCost, currency)}</div>
                </div>
                <div>
                  <div className="text-[#7d8590]">ลดลงจากเดิม</div>
                  <div className={`font-semibold ${previewStats.averageCost < stats.averageCost ? 'text-green-400' : 'text-red-400'}`}>
                    {previewStats.averageCost < stats.averageCost ? '▼' : '▲'} {fmtCurrency(Math.abs(previewStats.averageCost - stats.averageCost), currency)}
                  </div>
                </div>
                <div>
                  <div className="text-[#7d8590]">หุ้นรวม</div>
                  <div className="font-semibold">{fmt(previewStats.totalShares)} หุ้น</div>
                </div>
                <div>
                  <div className="text-[#7d8590]">ลงทุนรวม</div>
                  <div className="font-semibold">{fmtCurrency(previewStats.totalInvested, currency)}</div>
                </div>
              </div>
            </div>
          )}

          {/* Target Average Calculator */}
          <div className="mt-4 pt-4 border-t border-[#21262d]">
            <div className="flex items-center gap-2 text-xs text-[#7d8590] mb-2">
              <Target size={12} className="text-yellow-400" />
              <span>ต้องการลด average ลงเหลือ</span>
            </div>
            <div className="flex gap-2 items-end">
              <div className="flex-1">
                <div className="relative">
                  <span className="absolute left-3 top-1/2 -translate-y-1/2 text-sm text-[#7d8590]">{currency}</span>
                  <input
                    type="number"
                    min="0"
                    step="0.01"
                    value={targetAvg || ''}
                    onChange={e => setTargetAvg(parseFloat(e.target.value) || 0)}
                    placeholder="target avg..."
                    className="w-full bg-[#0d1117] border border-[#30363d] rounded-lg pl-8 pr-3 py-2.5 text-sm focus:border-yellow-500 focus:outline-none transition-colors"
                  />
                </div>
              </div>
            </div>
            {sharesNeeded !== null && addPrice > 0 && targetAvg > 0 && (
              <div className="mt-2 p-3 rounded-lg bg-yellow-950/20 border border-yellow-900/40">
                {sharesNeeded > 0 ? (
                  <p className="text-xs text-yellow-300">
                    ต้องซื้อเพิ่ม{' '}
                    <span className="font-bold text-yellow-200">{fmt(sharesNeeded)} หุ้น</span>{' '}
                    ที่ราคา {fmtCurrency(addPrice, currency)} เพื่อให้ avg = {fmtCurrency(targetAvg, currency)}
                    <br />
                    <span className="text-yellow-500">ใช้เงินเพิ่ม: {fmtCurrency(sharesNeeded * addPrice, currency)}</span>
                  </p>
                ) : (
                  <p className="text-xs text-[#7d8590]">ราคาซื้อต้องต่ำกว่า target average และ average ปัจจุบัน</p>
                )}
              </div>
            )}
          </div>
        </div>
      </div>

      {/* RIGHT: Results */}
      <div className="space-y-4">
        {/* Hero: Current Portfolio Value */}
        <div className="bg-gradient-to-br from-[#0d1f1f] to-[#0d1117] border border-teal-900/40 rounded-xl p-6 text-center">
          <p className="text-xs text-[#7d8590] mb-1">มูลค่าพอร์ตปัจจุบัน{symbol ? ` · ${symbol}` : ''}</p>
          <div className={`text-4xl font-bold tracking-tight mb-1 ${isProfit ? 'text-teal-300' : 'text-red-300'}`}>
            {fmtCurrency(stats.currentValue, currency)}
          </div>
          <div className={`flex items-center justify-center gap-2 text-sm font-medium ${isProfit ? 'text-green-400' : 'text-red-400'}`}>
            {isProfit ? <TrendingUp size={16} /> : <TrendingDown size={16} />}
            <span>
              {isProfit ? '+' : ''}{fmtCurrency(stats.profitLoss, currency)} ({isProfit ? '+' : ''}{fmt(stats.profitLossPercent)}%)
            </span>
          </div>
        </div>

        {/* Stats Grid */}
        <div className="grid grid-cols-2 gap-3">
          <StatCard
            label="ต้นทุนเฉลี่ย"
            value={fmtCurrency(stats.averageCost, currency)}
            sub="ต่อหุ้น"
            color="text-white"
          />
          <StatCard
            label="จำนวนหุ้นทั้งหมด"
            value={fmt(stats.totalShares)}
            sub="หุ้น"
            color="text-white"
          />
          <StatCard
            label="เงินลงทุนรวม"
            value={fmtCurrency(stats.totalInvested, currency)}
            sub="ต้นทุนทั้งหมด"
            color="text-white"
          />
          <StatCard
            label="กำไร / ขาดทุน"
            value={(isProfit ? '+' : '') + fmtCurrency(stats.profitLoss, currency)}
            sub={`${isProfit ? '+' : ''}${fmt(stats.profitLossPercent)}% ROI`}
            color={isProfit ? 'text-green-400' : 'text-red-400'}
          />
        </div>

        {/* Break-even Info */}
        {stats.totalShares > 0 && (
          <div className="bg-[#161b22] border border-[#30363d] rounded-xl p-4">
            <h3 className="text-xs font-semibold text-[#7d8590] uppercase tracking-wider mb-3">วิเคราะห์</h3>
            <div className="space-y-2.5 text-sm">
              <InfoRow
                label="ราคา break-even"
                value={fmtCurrency(stats.averageCost, currency)}
                hint="ราคาที่ต้องขายเพื่อคืนทุน"
              />
              <InfoRow
                label="% จากราคาปัจจุบัน"
                value={`${fmt(((currentPrice - stats.averageCost) / stats.averageCost) * 100)}%`}
                hint={currentPrice > stats.averageCost ? 'ราคาสูงกว่าต้นทุน' : 'ราคาต่ำกว่าต้นทุน'}
                valueColor={currentPrice >= stats.averageCost ? 'text-green-400' : 'text-red-400'}
              />
              <InfoRow
                label="มูลค่าถ้าราคา +10%"
                value={fmtCurrency(stats.totalShares * currentPrice * 1.1, currency)}
                hint={`กำไร: +${fmtCurrency(stats.totalShares * currentPrice * 0.1, currency)}`}
              />
              <InfoRow
                label="มูลค่าถ้าราคา -10%"
                value={fmtCurrency(stats.totalShares * currentPrice * 0.9, currency)}
                hint={`ขาดทุน: -${fmtCurrency(stats.totalShares * currentPrice * 0.1, currency)}`}
                valueColor="text-[#7d8590]"
              />
            </div>
          </div>
        )}

        {/* Round Summary */}
        {rounds.length > 1 && (
          <div className="bg-[#161b22] border border-[#30363d] rounded-xl p-4">
            <h3 className="text-xs font-semibold text-[#7d8590] uppercase tracking-wider mb-3">สรุปรอบการซื้อ</h3>
            <div className="space-y-1.5">
              {rounds.map((r, i) => {
                if (!r.shares || !r.pricePerShare) return null
                const cost = r.shares * r.pricePerShare
                const val = r.shares * currentPrice
                const pnl = val - cost
                return (
                  <div key={r.id} className="flex items-center justify-between text-xs">
                    <span className="text-[#7d8590]">รอบ {i + 1}</span>
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

function StatCard({ label, value, sub, color = 'text-white' }: {
  label: string; value: string; sub: string; color?: string
}) {
  return (
    <div className="bg-[#161b22] border border-[#30363d] rounded-xl p-4">
      <p className="text-xs text-[#7d8590] mb-1">{label}</p>
      <p className={`text-lg font-bold ${color}`}>{value}</p>
      <p className="text-xs text-[#484f58]">{sub}</p>
    </div>
  )
}

function InfoRow({ label, value, hint, valueColor = 'text-white' }: {
  label: string; value: string; hint: string; valueColor?: string
}) {
  return (
    <div className="flex items-center justify-between">
      <div>
        <span className="text-[#7d8590]">{label}</span>
        <span className="text-xs text-[#484f58] ml-2">{hint}</span>
      </div>
      <span className={`font-semibold ${valueColor}`}>{value}</span>
    </div>
  )
}
