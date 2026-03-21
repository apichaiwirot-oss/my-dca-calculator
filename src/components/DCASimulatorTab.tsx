import { useState, useMemo } from 'react'
import {
  AreaChart, Area, XAxis, YAxis, CartesianGrid, Tooltip, Legend, ResponsiveContainer,
} from 'recharts'
import { RefreshCw, ChevronDown, ChevronUp } from 'lucide-react'
import { simulateDCA, generateSimulatedPrices, fmt, fmtCurrency } from '../lib/calculations'

interface Props {
  currency: string
}

type PriceMode = 'simulate' | 'manual'

const PERIOD_LABELS = (i: number, mode: 'monthly' | 'weekly') =>
  mode === 'monthly' ? `เดือน ${i + 1}` : `สัปดาห์ ${i + 1}`

export default function DCASimulatorTab({ currency }: Props) {
  const [investment, setInvestment] = useState(5000)
  const [periods, setPeriods] = useState(24)
  const [periodMode, setPeriodMode] = useState<'monthly' | 'weekly'>('monthly')
  const [priceMode, setPriceMode] = useState<PriceMode>('simulate')

  // Simulate mode
  const [startPrice, setStartPrice] = useState(100)
  const [endPrice, setEndPrice] = useState(180)
  const [volatility, setVolatility] = useState(0.3)
  const [seed, setSeed] = useState(0)

  // Manual mode
  const [manualPrices, setManualPrices] = useState<string>(
    Array.from({ length: 12 }, (_, i) => (100 + i * 5 + Math.random() * 20 - 10).toFixed(2)).join('\n')
  )
  const [showTable, setShowTable] = useState(false)

  // Generate prices
  const prices = useMemo(() => {
    if (priceMode === 'manual') {
      return manualPrices
        .split(/[\n,;]+/)
        .map(s => parseFloat(s.trim()))
        .filter(n => !isNaN(n) && n > 0)
    }
    return generateSimulatedPrices(startPrice, endPrice, periods, volatility)
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [priceMode, manualPrices, startPrice, endPrice, periods, volatility, seed])

  const data = useMemo(
    () => simulateDCA(investment, prices, i => PERIOD_LABELS(i, periodMode)),
    [investment, prices, periodMode]
  )

  const last = data[data.length - 1]
  const isProfit = last ? last.profitLoss >= 0 : false

  const chartData = data.map(d => ({
    name: d.label,
    'เงินที่ลงทุน': parseFloat(d.totalInvested.toFixed(2)),
    'มูลค่าพอร์ต': parseFloat(d.portfolioValue.toFixed(2)),
    'ราคาหุ้น': parseFloat(d.price.toFixed(2)),
    'ต้นทุนเฉลี่ย': parseFloat(d.averageCost.toFixed(2)),
  }))

  // Recharts tooltip
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const CustomTooltip = ({ active, payload, label }: any) => {
    if (!active || !payload?.length) return null
    return (
      <div className="bg-[#1a1a1a] border border-[#2a2a2a] rounded-lg p-3 text-xs shadow-xl">
        <p className="font-semibold text-white mb-2">{label}</p>
        {payload.map((p: { name: string; value: number; color: string }) => (
          <div key={p.name} className="flex justify-between gap-4 mb-0.5">
            <span style={{ color: p.color }}>{p.name}</span>
            <span className="text-white font-medium">{fmtCurrency(p.value, currency)}</span>
          </div>
        ))}
      </div>
    )
  }

  return (
    <div className="space-y-5">
      {/* Config */}
      <div className="grid grid-cols-1 md:grid-cols-2 gap-5">
        {/* Investment Settings */}
        <div className="bg-[#1a1a1a] border border-[#2a2a2a] rounded-xl p-5">
          <h2 className="text-sm font-semibold text-[#808080] uppercase tracking-wider mb-4 flex items-center gap-2">
            <span className="w-2 h-2 rounded-full bg-[#E50914] inline-block" />
            การลงทุน
          </h2>

          <div className="space-y-4">
            <div>
              <label className="block text-xs text-[#808080] mb-1.5">เงินลงทุนต่องวด ({currency})</label>
              <div className="relative">
                <span className="absolute left-3 top-1/2 -translate-y-1/2 text-sm text-[#808080]">{currency}</span>
                <input
                  type="number"
                  min="1"
                  value={investment}
                  onChange={e => setInvestment(Math.max(1, parseFloat(e.target.value) || 1))}
                  className="w-full bg-[#141414] border border-[#2a2a2a] rounded-lg pl-8 pr-3 py-2.5 text-sm focus:border-[#E50914] focus:outline-none transition-colors"
                />
              </div>
            </div>

            <div className="grid grid-cols-2 gap-3">
              <div>
                <label className="block text-xs text-[#808080] mb-1.5">จำนวนงวด</label>
                <input
                  type="number"
                  min="2"
                  max="120"
                  value={periods}
                  onChange={e => {
                    const v = Math.min(120, Math.max(2, parseInt(e.target.value) || 2))
                    setPeriods(v)
                  }}
                  className="w-full bg-[#141414] border border-[#2a2a2a] rounded-lg px-3 py-2.5 text-sm focus:border-[#E50914] focus:outline-none transition-colors"
                />
              </div>
              <div>
                <label className="block text-xs text-[#808080] mb-1.5">รูปแบบงวด</label>
                <select
                  value={periodMode}
                  onChange={e => setPeriodMode(e.target.value as 'monthly' | 'weekly')}
                  className="w-full bg-[#141414] border border-[#2a2a2a] rounded-lg px-3 py-2.5 text-sm focus:border-[#E50914] focus:outline-none transition-colors"
                >
                  <option value="monthly">รายเดือน</option>
                  <option value="weekly">รายสัปดาห์</option>
                </select>
              </div>
            </div>
          </div>
        </div>

        {/* Price Settings */}
        <div className="bg-[#1a1a1a] border border-[#2a2a2a] rounded-xl p-5">
          <div className="flex items-center justify-between mb-4">
            <h2 className="text-sm font-semibold text-[#808080] uppercase tracking-wider flex items-center gap-2">
              <span className="w-2 h-2 rounded-full bg-white inline-block" />
              ราคาหุ้น
            </h2>
            <div className="flex rounded-lg overflow-hidden border border-[#2a2a2a]">
              {(['simulate', 'manual'] as PriceMode[]).map(m => (
                <button
                  key={m}
                  onClick={() => setPriceMode(m)}
                  className={`px-3 py-1 text-xs font-medium transition-colors ${
                    priceMode === m
                      ? 'bg-[#E50914] text-white'
                      : 'text-[#808080] hover:text-white'
                  }`}
                >
                  {m === 'simulate' ? 'จำลอง' : 'กรอกเอง'}
                </button>
              ))}
            </div>
          </div>

          {priceMode === 'simulate' ? (
            <div className="space-y-3">
              <div className="grid grid-cols-2 gap-3">
                <div>
                  <label className="block text-xs text-[#808080] mb-1.5">ราคาเริ่มต้น ({currency})</label>
                  <div className="relative">
                    <span className="absolute left-3 top-1/2 -translate-y-1/2 text-xs text-[#808080]">{currency}</span>
                    <input
                      type="number" min="0.01" step="0.01" value={startPrice}
                      onChange={e => setStartPrice(parseFloat(e.target.value) || 0.01)}
                      className="w-full bg-[#141414] border border-[#2a2a2a] rounded-lg pl-7 pr-2 py-2.5 text-sm focus:border-[#E50914] focus:outline-none"
                    />
                  </div>
                </div>
                <div>
                  <label className="block text-xs text-[#808080] mb-1.5">ราคาสิ้นสุด ({currency})</label>
                  <div className="relative">
                    <span className="absolute left-3 top-1/2 -translate-y-1/2 text-xs text-[#808080]">{currency}</span>
                    <input
                      type="number" min="0.01" step="0.01" value={endPrice}
                      onChange={e => setEndPrice(parseFloat(e.target.value) || 0.01)}
                      className="w-full bg-[#141414] border border-[#2a2a2a] rounded-lg pl-7 pr-2 py-2.5 text-sm focus:border-[#E50914] focus:outline-none"
                    />
                  </div>
                </div>
              </div>
              <div>
                <label className="block text-xs text-[#808080] mb-1.5">
                  ความผันผวน: <span className="text-white">{Math.round(volatility * 100)}%</span>
                </label>
                <input
                  type="range" min="0" max="1" step="0.05" value={volatility}
                  onChange={e => setVolatility(parseFloat(e.target.value))}
                  className="w-full accent-[#E50914]"
                />
                <div className="flex justify-between text-xs text-[#555] mt-0.5">
                  <span>ต่ำ</span><span>กลาง</span><span>สูง</span>
                </div>
              </div>
              <button
                onClick={() => setSeed(s => s + 1)}
                className="w-full flex items-center justify-center gap-2 py-2 rounded-lg bg-[#141414] border border-[#2a2a2a] text-xs text-[#808080] hover:text-white hover:border-[#E50914] transition-colors"
              >
                <RefreshCw size={12} /> สุ่มราคาใหม่
              </button>
            </div>
          ) : (
            <div>
              <label className="block text-xs text-[#808080] mb-1.5">
                กรอกราคาแต่ละงวด (แยกด้วยบรรทัดใหม่หรือ comma)
              </label>
              <textarea
                rows={6}
                value={manualPrices}
                onChange={e => setManualPrices(e.target.value)}
                placeholder={"100\n105\n98\n112\n..."}
                className="w-full bg-[#141414] border border-[#2a2a2a] rounded-lg px-3 py-2.5 text-sm focus:border-[#E50914] focus:outline-none transition-colors font-mono resize-none"
              />
              <p className="text-xs text-[#555] mt-1">จำนวนงวดที่ใช้: {prices.length}</p>
            </div>
          )}
        </div>
      </div>

      {/* Summary Cards */}
      {last && (
        <div className="grid grid-cols-2 sm:grid-cols-4 gap-3">
          <SummaryCard label="ลงทุนรวม" value={fmtCurrency(last.totalInvested, currency)} />
          <SummaryCard label="มูลค่าพอร์ต" value={fmtCurrency(last.portfolioValue, currency)}
            valueColor={isProfit ? 'text-[#ff6b6b]' : 'text-red-300'} />
          <SummaryCard
            label="กำไร / ขาดทุน"
            value={(isProfit ? '+' : '') + fmtCurrency(last.profitLoss, currency)}
            valueColor={isProfit ? 'text-green-400' : 'text-red-400'}
          />
          <SummaryCard
            label="ROI"
            value={`${isProfit ? '+' : ''}${fmt(last.profitLossPercent)}%`}
            valueColor={isProfit ? 'text-green-400' : 'text-red-400'}
            sub={`avg cost: ${fmtCurrency(last.averageCost, currency)}`}
          />
        </div>
      )}

      {/* Chart */}
      {data.length > 0 && (
        <div className="bg-[#1a1a1a] border border-[#2a2a2a] rounded-xl p-5">
          <h3 className="text-sm font-semibold text-white mb-4">📈 กราฟการเติบโตของพอร์ต</h3>
          <ResponsiveContainer width="100%" height={320}>
            <AreaChart data={chartData} margin={{ top: 10, right: 10, left: 0, bottom: 0 }}>
              <defs>
                <linearGradient id="portfolioGrad" x1="0" y1="0" x2="0" y2="1">
                  <stop offset="5%" stopColor="#E50914" stopOpacity={0.3} />
                  <stop offset="95%" stopColor="#E50914" stopOpacity={0} />
                </linearGradient>
                <linearGradient id="investedGrad" x1="0" y1="0" x2="0" y2="1">
                  <stop offset="5%" stopColor="#6b7280" stopOpacity={0.2} />
                  <stop offset="95%" stopColor="#6b7280" stopOpacity={0} />
                </linearGradient>
              </defs>
              <CartesianGrid strokeDasharray="3 3" stroke="#2a2a2a" />
              <XAxis
                dataKey="name"
                tick={{ fontSize: 10, fill: '#555' }}
                tickLine={false}
                interval={Math.floor(chartData.length / 6)}
              />
              <YAxis
                tick={{ fontSize: 10, fill: '#555' }}
                tickLine={false}
                axisLine={false}
                tickFormatter={v => `${currency}${(v / 1000).toFixed(0)}k`}
                width={55}
              />
              <Tooltip content={<CustomTooltip />} />
              <Legend
                wrapperStyle={{ fontSize: '12px', color: '#808080', paddingTop: '12px' }}
              />
              <Area
                type="monotone"
                dataKey="เงินที่ลงทุน"
                stroke="#6b7280"
                fill="url(#investedGrad)"
                strokeDasharray="5 5"
                strokeWidth={1.5}
              />
              <Area
                type="monotone"
                dataKey="มูลค่าพอร์ต"
                stroke="#E50914"
                fill="url(#portfolioGrad)"
                strokeWidth={2.5}
              />
            </AreaChart>
          </ResponsiveContainer>
        </div>
      )}

      {/* Data Table (collapsible) */}
      {data.length > 0 && (
        <div className="bg-[#1a1a1a] border border-[#2a2a2a] rounded-xl overflow-hidden">
          <button
            onClick={() => setShowTable(v => !v)}
            className="w-full flex items-center justify-between p-4 text-sm font-medium hover:bg-[#1a1a1a] transition-colors"
          >
            <span>📋 ตารางข้อมูลรายงวด ({data.length} งวด)</span>
            {showTable ? <ChevronUp size={16} /> : <ChevronDown size={16} />}
          </button>

          {showTable && (
            <div className="overflow-x-auto">
              <table className="w-full text-xs">
                <thead>
                  <tr className="border-t border-[#2a2a2a] bg-[#141414]">
                    {['งวด', 'ราคา', 'ซื้อได้', 'หุ้นสะสม', 'ลงทุนสะสม', 'มูลค่าพอร์ต', 'กำไร/ขาดทุน', 'ROI', 'avg cost'].map(h => (
                      <th key={h} className="px-3 py-2.5 text-left text-[#808080] font-medium whitespace-nowrap">{h}</th>
                    ))}
                  </tr>
                </thead>
                <tbody>
                  {data.map((d, i) => (
                    <tr key={i} className={`border-t border-[#1e1e1e] hover:bg-[#1a1a1a] transition-colors ${d.profitLoss >= 0 ? '' : 'opacity-80'}`}>
                      <td className="px-3 py-2 text-[#808080]">{d.label}</td>
                      <td className="px-3 py-2">{fmtCurrency(d.price, currency)}</td>
                      <td className="px-3 py-2">{fmt(d.sharesBought, 4)}</td>
                      <td className="px-3 py-2">{fmt(d.totalShares, 4)}</td>
                      <td className="px-3 py-2">{fmtCurrency(d.totalInvested, currency)}</td>
                      <td className="px-3 py-2 font-medium">{fmtCurrency(d.portfolioValue, currency)}</td>
                      <td className={`px-3 py-2 font-medium ${d.profitLoss >= 0 ? 'text-green-400' : 'text-red-400'}`}>
                        {d.profitLoss >= 0 ? '+' : ''}{fmtCurrency(d.profitLoss, currency)}
                      </td>
                      <td className={`px-3 py-2 ${d.profitLossPercent >= 0 ? 'text-green-400' : 'text-red-400'}`}>
                        {d.profitLossPercent >= 0 ? '+' : ''}{fmt(d.profitLossPercent)}%
                      </td>
                      <td className="px-3 py-2 text-[#808080]">{fmtCurrency(d.averageCost, currency)}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
        </div>
      )}
    </div>
  )
}

function SummaryCard({ label, value, valueColor = 'text-white', sub }: {
  label: string; value: string; valueColor?: string; sub?: string
}) {
  return (
    <div className="bg-[#1a1a1a] border border-[#2a2a2a] rounded-xl p-4">
      <p className="text-xs text-[#808080] mb-1">{label}</p>
      <p className={`text-base font-bold ${valueColor}`}>{value}</p>
      {sub && <p className="text-xs text-[#555] mt-0.5">{sub}</p>}
    </div>
  )
}
