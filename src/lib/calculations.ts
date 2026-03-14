export interface BuyRound {
  id: string
  shares: number
  pricePerShare: number
}

export interface PortfolioStats {
  totalShares: number
  totalInvested: number
  averageCost: number
  currentValue: number
  profitLoss: number
  profitLossPercent: number
}

export function calcPortfolio(rounds: BuyRound[], currentPrice: number): PortfolioStats {
  const totalShares = rounds.reduce((s, r) => s + (r.shares || 0), 0)
  const totalInvested = rounds.reduce((s, r) => s + (r.shares || 0) * (r.pricePerShare || 0), 0)
  const averageCost = totalShares > 0 ? totalInvested / totalShares : 0
  const currentValue = totalShares * (currentPrice || 0)
  const profitLoss = currentValue - totalInvested
  const profitLossPercent = totalInvested > 0 ? (profitLoss / totalInvested) * 100 : 0
  return { totalShares, totalInvested, averageCost, currentValue, profitLoss, profitLossPercent }
}

/** How many shares to buy at buyPrice to bring average down to targetAvg */
export function sharesNeededToReachTarget(
  currentShares: number,
  currentAvg: number,
  buyPrice: number,
  targetAvg: number
): number {
  if (buyPrice >= targetAvg || buyPrice >= currentAvg) return 0
  return (currentShares * (currentAvg - targetAvg)) / (targetAvg - buyPrice)
}

export interface DCADataPoint {
  period: number
  label: string
  price: number
  sharesBought: number
  totalShares: number
  totalInvested: number
  portfolioValue: number
  profitLoss: number
  profitLossPercent: number
  averageCost: number
}

export function simulateDCA(
  investmentPerPeriod: number,
  prices: number[],
  labelFn: (i: number) => string
): DCADataPoint[] {
  let totalShares = 0
  let totalInvested = 0
  const result: DCADataPoint[] = []

  for (let i = 0; i < prices.length; i++) {
    const price = prices[i]
    if (!price || price <= 0) continue
    const sharesBought = investmentPerPeriod / price
    totalShares += sharesBought
    totalInvested += investmentPerPeriod
    const portfolioValue = totalShares * price
    const profitLoss = portfolioValue - totalInvested
    const profitLossPercent = totalInvested > 0 ? (profitLoss / totalInvested) * 100 : 0
    const averageCost = totalShares > 0 ? totalInvested / totalShares : 0
    result.push({
      period: i + 1,
      label: labelFn(i),
      price,
      sharesBought,
      totalShares,
      totalInvested,
      portfolioValue,
      profitLoss,
      profitLossPercent,
      averageCost,
    })
  }
  return result
}

export function generateSimulatedPrices(
  startPrice: number,
  endPrice: number,
  periods: number,
  volatility: number // 0..1
): number[] {
  const prices: number[] = [startPrice]
  const logReturn = periods > 1 ? Math.log(endPrice / startPrice) / (periods - 1) : 0

  for (let i = 1; i < periods; i++) {
    const noise = (Math.random() - 0.5) * 2 * volatility * startPrice * 0.3
    const trend = startPrice * Math.exp(logReturn * i)
    prices.push(Math.max(trend + noise, startPrice * 0.05))
  }
  return prices
}

export function fmt(n: number, decimals = 2): string {
  return n.toLocaleString('en-US', {
    minimumFractionDigits: decimals,
    maximumFractionDigits: decimals,
  })
}

export function fmtCurrency(n: number, symbol = '$'): string {
  return `${symbol}${fmt(n)}`
}
