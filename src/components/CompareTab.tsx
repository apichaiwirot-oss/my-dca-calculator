import { useState, useMemo } from 'react'
import {
  LineChart, Line, XAxis, YAxis, CartesianGrid, Tooltip, Legend, ResponsiveContainer,
} from 'recharts'
import { RefreshCw } from 'lucide-react'
import { simulateDCA, generateSimulatedPrices, fmt, fmtCurrency } from '../lib/calculations'

interface Props {
  currency: string
}

interface Asset {
  name: string
  startPrice: number
  endPrice: number
  volatility: number
  color: string
}

const COLORS = ['#E50914', '#f59e0b', '#8b5cf6', '#3b82f6']

const DEFAULT_ASSETS: Asset[] = [
  { name: 'หุ้น A', startPrice: 100, endPrice: 180, volatility: 0.2, color: COLORS[0] },
  { name: 'หุ้น B', startPrice: 100, endPrice: 130, volatility: 0.4, color: COLORS[1] },
]

export default function CompareTab({ currency }: Props) {
  const [assets, setAssets] = useState<Asset[]>(DEFAULT_ASSETS)
  const [investment, setInvestment] = useState(5000)
  const [periods, setPeriods] = useState(24)
  const [seed, setSeed] = useState(0)

  // eslint-disable-next-line react-hooks/exhaustive-deps
  const pricesPerAsset = useMemo(() =>
    assets.map(a => generateSimulatedPrices(a.startPrice, a.endPrice, periods, a.volatility)),
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [assets, periods, seed]
  )

  const dataPerAsset = useMemo(() =>
    pricesPerAsset.map(prices =>
      simulateDCA(investment, prices, i => `งวด ${i + 1}`)
    ),
    [pricesPerAsset, investment]
  )

  // Combine into chart data
  const chartData = useMemo(() => {
    const maxLen = Math.max(...dataPerAsset.map(d => d.length))
    return Array.from({ length: maxLen }, (_, i) => {
      const row: Record<string, number | string> = { name: `งวด ${i + 1}` }
      dataPerAsset.forEach((data, ai) => {
        const d = data[i]
        if (d) {
          row[`${assets[ai].name} - มูลค่า`] = parseFloat(d.portfolioValue.toFixed(2))
          row[`${assets[ai].name} - ลงทุน`] = parseFloat(d.totalInvested.toFixed(2))
        }
      })
      return row
    })
  }, [dataPerAsset, assets])

  const updateAsset = (index: number, field: keyof Asset, value: string | number) => {
    setAssets(prev => prev.map((a, i) => i === index ? { ...a, [field]: value } : a))
  }

  const addAsset = () => {
    if (assets.length >= 4) return
    setAssets(prev => [...prev, {
      name: `หุ้น ${String.fromCharCode(65 + prev.length)}`,
      startPrice: 100,
      endPrice: 150,
      volatility: 0.3,
      color: COLORS[prev.length],
    }])
  }

  const removeAsset = (index: number) => {
    if (assets.length <= 2) return
    setAssets(prev => prev.filter((_, i) => i !== index))
  }

  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const CustomTooltip = ({ active, payload, label }: any) => {
    if (!active || !payload?.length) return null
    return (
      <div className="bg-[#1a1a1a] border border-[#2a2a2a] rounded-lg p-3 text-xs shadow-xl max-w-xs">
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
      {/* Global Config */}
      <div className="bg-[#1a1a1a] border border-[#2a2a2a] rounded-xl p-5">
        <div className="flex items-center justify-between mb-4">
          <h2 className="text-sm font-semibold text-[#808080] uppercase tracking-wider flex items-center gap-2">
            <span className="w-2 h-2 rounded-full bg-[#E50914] inline-block" />
            ตั้งค่าการเปรียบเทียบ
          </h2>
          <button
            onClick={() => setSeed(s => s + 1)}
            className="flex items-center gap-1.5 px-3 py-1.5 rounded-lg bg-[#141414] border border-[#2a2a2a] text-xs text-[#808080] hover:text-white hover:border-[#E50914] transition-colors"
          >
            <RefreshCw size={12} /> สุ่มใหม่
          </button>
        </div>
        <div className="grid grid-cols-2 gap-4">
          <div>
            <label className="block text-xs text-[#808080] mb-1.5">เงินลงทุนต่องวด ({currency})</label>
            <div className="relative">
              <span className="absolute left-3 top-1/2 -translate-y-1/2 text-sm text-[#808080]">{currency}</span>
              <input
                type="number" min="1" value={investment}
                onChange={e => setInvestment(Math.max(1, parseFloat(e.target.value) || 1))}
                className="w-full bg-[#141414] border border-[#2a2a2a] rounded-lg pl-8 pr-3 py-2.5 text-sm focus:border-[#E50914] focus:outline-none transition-colors"
              />
            </div>
          </div>
          <div>
            <label className="block text-xs text-[#808080] mb-1.5">จำนวนงวด (เหมือนกันทุกหุ้น)</label>
            <input
              type="number" min="2" max="120" value={periods}
              onChange={e => setPeriods(Math.min(120, Math.max(2, parseInt(e.target.value) || 2)))}
              className="w-full bg-[#141414] border border-[#2a2a2a] rounded-lg px-3 py-2.5 text-sm focus:border-[#E50914] focus:outline-none transition-colors"
            />
          </div>
        </div>
      </div>

      {/* Asset Configs */}
      <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
        {assets.map((asset, ai) => (
          <div
            key={ai}
            className="bg-[#1a1a1a] border rounded-xl p-4 transition-colors"
            style={{ borderColor: asset.color + '40' }}
          >
            <div className="flex items-center justify-between mb-3">
              <div className="flex items-center gap-2">
                <span className="w-3 h-3 rounded-full" style={{ backgroundColor: asset.color }} />
                <input
                  type="text"
                  value={asset.name}
                  onChange={e => updateAsset(ai, 'name', e.target.value)}
                  className="bg-transparent text-sm font-semibold focus:outline-none border-b border-transparent focus:border-[#2a2a2a] transition-colors w-24"
                />
              </div>
              {assets.length > 2 && (
                <button
                  onClick={() => removeAsset(ai)}
                  className="text-xs text-[#555] hover:text-red-400 transition-colors px-2"
                >
                  ลบ
                </button>
              )}
            </div>

            <div className="space-y-3">
              <div className="grid grid-cols-2 gap-2">
                <div>
                  <label className="block text-xs text-[#555] mb-1">ราคาเริ่มต้น</label>
                  <div className="relative">
                    <span className="absolute left-2 top-1/2 -translate-y-1/2 text-xs text-[#555]">{currency}</span>
                    <input
                      type="number" min="0.01" step="0.01" value={asset.startPrice}
                      onChange={e => updateAsset(ai, 'startPrice', parseFloat(e.target.value) || 0.01)}
                      className="w-full bg-[#141414] border border-[#2a2a2a] rounded-lg pl-6 pr-2 py-2 text-sm focus:outline-none focus:border-[#E50914]"
                    />
                  </div>
                </div>
                <div>
                  <label className="block text-xs text-[#555] mb-1">ราคาสิ้นสุด</label>
                  <div className="relative">
                    <span className="absolute left-2 top-1/2 -translate-y-1/2 text-xs text-[#555]">{currency}</span>
                    <input
                      type="number" min="0.01" step="0.01" value={asset.endPrice}
                      onChange={e => updateAsset(ai, 'endPrice', parseFloat(e.target.value) || 0.01)}
                      className="w-full bg-[#141414] border border-[#2a2a2a] rounded-lg pl-6 pr-2 py-2 text-sm focus:outline-none focus:border-[#E50914]"
                    />
                  </div>
                </div>
              </div>

              <div>
                <label className="block text-xs text-[#555] mb-1">
                  ความผันผวน: <span className="text-white">{Math.round(asset.volatility * 100)}%</span>
                </label>
                <input
                  type="range" min="0" max="1" step="0.05" value={asset.volatility}
                  onChange={e => updateAsset(ai, 'volatility', parseFloat(e.target.value))}
                  className="w-full"
                  style={{ accentColor: asset.color }}
                />
              </div>

              {/* Mini stats for this asset */}
              {dataPerAsset[ai].length > 0 && (() => {
                const last = dataPerAsset[ai][dataPerAsset[ai].length - 1]
                const isP = last.profitLoss >= 0
                return (
                  <div className="grid grid-cols-3 gap-1.5 pt-2 border-t border-[#1e1e1e]">
                    <MiniStat label="ลงทุนรวม" value={fmtCurrency(last.totalInvested, currency)} />
                    <MiniStat label="มูลค่า" value={fmtCurrency(last.portfolioValue, currency)} valueColor={isP ? 'text-green-400' : 'text-red-400'} />
                    <MiniStat label="ROI" value={`${isP ? '+' : ''}${fmt(last.profitLossPercent)}%`} valueColor={isP ? 'text-green-400' : 'text-red-400'} />
                  </div>
                )
              })()}
            </div>
          </div>
        ))}

        {assets.length < 4 && (
          <button
            onClick={addAsset}
            className="bg-[#1a1a1a] border border-dashed border-[#2a2a2a] rounded-xl p-4 text-sm text-[#808080] hover:border-[#E50914] hover:text-[#E50914] transition-colors flex items-center justify-center gap-2 min-h-[120px]"
          >
            + เพิ่มหุ้นเปรียบเทียบ
          </button>
        )}
      </div>

      {/* Comparison Chart */}
      {chartData.length > 0 && (
        <div className="bg-[#1a1a1a] border border-[#2a2a2a] rounded-xl p-5">
          <h3 className="text-sm font-semibold text-white mb-4">⚖️ กราฟเปรียบเทียบมูลค่าพอร์ต</h3>
          <ResponsiveContainer width="100%" height={340}>
            <LineChart data={chartData} margin={{ top: 10, right: 10, left: 0, bottom: 0 }}>
              <CartesianGrid strokeDasharray="3 3" stroke="#1e1e1e" />
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
              <Legend wrapperStyle={{ fontSize: '11px', color: '#808080', paddingTop: '12px' }} />
              {assets.map((asset) => (
                <Line
                  key={`${asset.name}-มูลค่า`}
                  type="monotone"
                  dataKey={`${asset.name} - มูลค่า`}
                  stroke={asset.color}
                  strokeWidth={2.5}
                  dot={false}
                  activeDot={{ r: 4 }}
                />
              ))}
              {/* Invested line (same for all) */}
              <Line
                type="monotone"
                dataKey={`${assets[0].name} - ลงทุน`}
                stroke="#374151"
                strokeWidth={1.5}
                strokeDasharray="5 5"
                dot={false}
                name="เงินลงทุน (เท่ากันทุกหุ้น)"
              />
            </LineChart>
          </ResponsiveContainer>
        </div>
      )}

      {/* Ranking Table */}
      {dataPerAsset.every(d => d.length > 0) && (
        <div className="bg-[#1a1a1a] border border-[#2a2a2a] rounded-xl overflow-hidden">
          <div className="p-4 border-b border-[#1e1e1e]">
            <h3 className="text-sm font-semibold text-white">🏆 ผลสรุปและจัดอันดับ</h3>
          </div>
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead>
                <tr className="bg-[#141414]">
                  {['อันดับ', 'หุ้น', 'ลงทุนรวม', 'มูลค่าสุดท้าย', 'กำไร/ขาดทุน', 'ROI', 'avg cost'].map(h => (
                    <th key={h} className="px-4 py-3 text-left text-xs text-[#808080] font-medium">{h}</th>
                  ))}
                </tr>
              </thead>
              <tbody>
                {dataPerAsset
                  .map((data, ai) => ({ ai, last: data[data.length - 1], asset: assets[ai] }))
                  .sort((a, b) => b.last.profitLossPercent - a.last.profitLossPercent)
                  .map(({ ai, last, asset }, rank) => (
                    <tr key={ai} className="border-t border-[#1e1e1e] hover:bg-[#1a1a1a] transition-colors">
                      <td className="px-4 py-3">
                        <span className="text-lg">{['🥇', '🥈', '🥉', '4️⃣'][rank]}</span>
                      </td>
                      <td className="px-4 py-3">
                        <div className="flex items-center gap-2">
                          <span className="w-2.5 h-2.5 rounded-full" style={{ backgroundColor: asset.color }} />
                          <span className="font-medium">{asset.name}</span>
                        </div>
                      </td>
                      <td className="px-4 py-3 text-[#808080]">{fmtCurrency(last.totalInvested, currency)}</td>
                      <td className="px-4 py-3 font-semibold">{fmtCurrency(last.portfolioValue, currency)}</td>
                      <td className={`px-4 py-3 font-semibold ${last.profitLoss >= 0 ? 'text-green-400' : 'text-red-400'}`}>
                        {last.profitLoss >= 0 ? '+' : ''}{fmtCurrency(last.profitLoss, currency)}
                      </td>
                      <td className={`px-4 py-3 font-bold text-base ${last.profitLossPercent >= 0 ? 'text-green-400' : 'text-red-400'}`}>
                        {last.profitLossPercent >= 0 ? '+' : ''}{fmt(last.profitLossPercent)}%
                      </td>
                      <td className="px-4 py-3 text-[#808080]">{fmtCurrency(last.averageCost, currency)}</td>
                    </tr>
                  ))}
              </tbody>
            </table>
          </div>
        </div>
      )}
    </div>
  )
}

function MiniStat({ label, value, valueColor = 'text-white' }: { label: string; value: string; valueColor?: string }) {
  return (
    <div>
      <p className="text-xs text-[#555] mb-0.5">{label}</p>
      <p className={`text-xs font-semibold ${valueColor}`}>{value}</p>
    </div>
  )
}
