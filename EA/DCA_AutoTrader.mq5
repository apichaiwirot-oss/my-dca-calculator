//+------------------------------------------------------------------+
//|                                              DCA_AutoTrader.mq5  |
//|                    Trend-Following DCA EA for MT5                |
//|                    BTCUSD & XAUUSD | Cent / Standard Account     |
//|                    Version 2.0                                   |
//+------------------------------------------------------------------+
//  STRATEGY OVERVIEW
//  -----------------
//  1. TREND FILTER (Higher Timeframe - H4)
//     - Price > EMA200 on H4  →  UPTREND   → only BUY
//     - Price < EMA200 on H4  →  DOWNTREND → only SELL
//     - ADX > threshold confirms trend strength
//
//  2. ENTRY (Current Timeframe - H1 default)
//     - Uptrend   : Enter BUY when EMA20 crosses above EMA50 + RSI < overbought
//     - Downtrend : Enter SELL when EMA20 crosses below EMA50 + RSI > oversold
//
//  3. DCA  (only in trend direction)
//     - If price retraces % from last entry → add position
//     - TP recalculates from weighted average price after each DCA
//
//  4. TREND REVERSAL
//     - When H4 trend flips → close all positions → wait for new entry signal
//
//  5. RISK MANAGEMENT (designed for $500 account)
//     - Lot size auto-calculated from account balance × risk %
//     - Hard SL, Max Drawdown guard, Spread filter, Session filter
//+------------------------------------------------------------------+
#property copyright "DCA AutoTrader v2"
#property version   "2.00"
#property description "Trend-Following DCA EA | BTCUSD & XAUUSD | $500 Account"

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>

//===================================================================
//  INPUT PARAMETERS
//===================================================================

input group "=== General ==="
input int      InpMagicNumber     = 202500;          // Magic Number
input string   InpMagicComment    = "DCA_Trend";     // Order Comment

input group "=== Trend Filter (Higher Timeframe) ==="
input ENUM_TIMEFRAMES InpTrendTF  = PERIOD_H4;       // Trend Timeframe (H4 recommended)
input int      InpTrendMA         = 200;             // Trend MA Period (EMA 200)
input bool     InpUseADX          = true;            // Use ADX Trend Strength Filter
input int      InpADXPeriod       = 14;              // ADX Period
input double   InpADXMinLevel     = 20.0;            // ADX Minimum Level (trend valid)

input group "=== Entry Signal (Current Timeframe) ==="
input int      InpFastMA          = 20;              // Fast EMA Period
input int      InpSlowMA          = 50;              // Slow EMA Period
input int      InpRSIPeriod       = 14;              // RSI Period
input double   InpRSIOverbought   = 65.0;            // RSI Overbought (skip buy if above)
input double   InpRSIOversold     = 35.0;            // RSI Oversold (skip sell if below)

input group "=== Risk Management (Lot Calculation) ==="
input double   InpRiskPercent     = 1.0;             // Risk % per trade (1% of balance)
input double   InpSLPercent       = 2.0;             // Stop Loss % from entry price
input double   InpTPPercent       = 3.0;             // Take Profit % from avg entry
input double   InpMaxLotSize      = 0.50;            // Hard cap: Max lot per order
input double   InpMinLotSize      = 0.01;            // Min lot size
input bool     InpUseTrailing     = true;            // Enable Trailing Stop
input double   InpTrailingPercent = 1.0;             // Trailing Stop % from current price

input group "=== DCA Settings ==="
input bool     InpEnableDCA       = true;            // Enable DCA
input int      InpMaxDCALevels    = 4;               // Max DCA Levels (4 levels for $500)
input double   InpDCATriggerPct   = 1.5;             // DCA Trigger: price retraces %
input double   InpDCALotMultiply  = 1.5;             // DCA Lot Multiplier each level

input group "=== Trend Reversal ==="
input bool     InpCloseOnReversal = true;            // Close all positions on trend reversal
input int      InpReversalConfirm = 2;               // Bars to confirm reversal (avoid whipsaw)

input group "=== Protection ==="
input double   InpMaxDDPercent    = 20.0;            // Stop trading if drawdown exceeds %
input int      InpMaxSpread       = 80;              // Max spread (points) to allow trade
input int      InpSlippage        = 30;              // Max slippage (points)

input group "=== Session Filter ==="
input bool     InpUseSession      = false;           // Enable session filter
input int      InpSessionStart    = 2;               // Start hour (server time)
input int      InpSessionEnd      = 22;              // End hour (server time)

//===================================================================
//  GLOBAL VARIABLES
//===================================================================

CTrade        trade;
CPositionInfo posInfo;

// Indicator handles - Trend TF
int  hTrendMA  = INVALID_HANDLE;
int  hADX      = INVALID_HANDLE;

// Indicator handles - Entry TF
int  hFastMA   = INVALID_HANDLE;
int  hSlowMA   = INVALID_HANDLE;
int  hRSI      = INVALID_HANDLE;

// Buffers
double bufTrendMA[], bufADXMain[], bufFastMA[], bufSlowMA[], bufRSI[];

// State tracking
datetime gLastBarTime     = 0;
int      gTrendDirection  = 0;   //  1=UP, -1=DOWN, 0=NONE
int      gPrevTrend       = 0;
int      gReversalBars    = 0;

// DCA state
double   gFirstEntryPrice = 0;
double   gLastDCAPrice    = 0;
int      gDCALevel        = 0;

//===================================================================
//  INIT
//===================================================================

int OnInit()
{
   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetDeviationInPoints(InpSlippage);
   trade.SetTypeFilling(ORDER_FILLING_IOC);
   trade.SetAsyncMode(false);

   // Trend timeframe indicators
   hTrendMA = iMA(_Symbol, InpTrendTF, InpTrendMA, 0, MODE_EMA, PRICE_CLOSE);
   hADX     = iADX(_Symbol, InpTrendTF, InpADXPeriod);

   // Entry timeframe indicators
   hFastMA  = iMA(_Symbol, PERIOD_CURRENT, InpFastMA, 0, MODE_EMA, PRICE_CLOSE);
   hSlowMA  = iMA(_Symbol, PERIOD_CURRENT, InpSlowMA, 0, MODE_EMA, PRICE_CLOSE);
   hRSI     = iRSI(_Symbol, PERIOD_CURRENT, InpRSIPeriod, PRICE_CLOSE);

   if(hTrendMA == INVALID_HANDLE || hADX == INVALID_HANDLE ||
      hFastMA  == INVALID_HANDLE || hSlowMA == INVALID_HANDLE || hRSI == INVALID_HANDLE)
   {
      Alert("DCA_AutoTrader: Failed to create indicator handles!");
      return INIT_FAILED;
   }

   ArraySetAsSeries(bufTrendMA, true);
   ArraySetAsSeries(bufADXMain, true);
   ArraySetAsSeries(bufFastMA,  true);
   ArraySetAsSeries(bufSlowMA,  true);
   ArraySetAsSeries(bufRSI,     true);

   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   PrintFormat("=== DCA AutoTrader v2.0 | %s | Balance: %.2f ===", _Symbol, balance);
   PrintFormat("Risk: %.1f%% | SL: %.1f%% | TP: %.1f%% | DCA Levels: %d",
               InpRiskPercent, InpSLPercent, InpTPPercent, InpMaxDCALevels);
   PrintFormat("Trend TF: %s | EMA%d | ADX%d min=%.0f",
               EnumToString(InpTrendTF), InpTrendMA, InpADXPeriod, InpADXMinLevel);

   return INIT_SUCCEEDED;
}

//===================================================================
//  DEINIT
//===================================================================

void OnDeinit(const int reason)
{
   IndicatorRelease(hTrendMA);
   IndicatorRelease(hADX);
   IndicatorRelease(hFastMA);
   IndicatorRelease(hSlowMA);
   IndicatorRelease(hRSI);
}

//===================================================================
//  MAIN TICK
//===================================================================

void OnTick()
{
   // Trailing stop runs on every tick
   if(InpUseTrailing)
      ManageTrailingStop();

   // Rest of logic only on new bar
   datetime barTime = iTime(_Symbol, PERIOD_CURRENT, 0);
   if(barTime == gLastBarTime) return;
   gLastBarTime = barTime;

   // Safety checks
   if(!CheckSpread())   return;
   if(InpUseSession && !IsInSession()) return;
   if(IsMaxDrawdown())  return;

   // Refresh all indicators
   if(!RefreshIndicators()) return;

   // Determine trend direction from higher timeframe
   int newTrend = GetTrendDirection();

   // --- Handle trend reversal ---
   if(newTrend != 0 && newTrend != gTrendDirection)
   {
      gReversalBars++;
      if(gReversalBars >= InpReversalConfirm)
      {
         if(gTrendDirection != 0)
         {
            PrintFormat("[TREND CHANGE] %s → %s",
                        TrendName(gTrendDirection), TrendName(newTrend));
            if(InpCloseOnReversal)
               CloseAllPositions();
         }
         gTrendDirection   = newTrend;
         gReversalBars     = 0;
         gFirstEntryPrice  = 0;
         gLastDCAPrice     = 0;
         gDCALevel         = 0;
      }
      return; // Wait for reversal confirmation
   }
   else
   {
      gReversalBars = 0;
   }

   if(gTrendDirection == 0) return; // No clear trend

   // Count positions
   int buyCount  = CountPositions(POSITION_TYPE_BUY);
   int sellCount = CountPositions(POSITION_TYPE_SELL);
   int totalPos  = buyCount + sellCount;

   // --- DCA: add to existing position if trend holds ---
   if(InpEnableDCA && totalPos > 0)
   {
      CheckDCA(buyCount, sellCount);
      return;
   }

   // --- New entry when no position ---
   if(totalPos == 0)
   {
      ResetDCAState();
      ENUM_ORDER_TYPE signal = GetEntrySignal();

      if(signal == ORDER_TYPE_BUY && gTrendDirection == 1)
         ExecuteEntry(ORDER_TYPE_BUY);
      else if(signal == ORDER_TYPE_SELL && gTrendDirection == -1)
         ExecuteEntry(ORDER_TYPE_SELL);
   }
}

//===================================================================
//  TREND DIRECTION - EMA200 + ADX on Higher TF
//===================================================================

int GetTrendDirection()
{
   double price = iClose(_Symbol, InpTrendTF, 1); // Last closed bar
   double ma    = bufTrendMA[1];
   double adx   = bufADXMain[1];

   if(InpUseADX && adx < InpADXMinLevel)
      return 0; // Trend not strong enough

   if(price > ma) return  1; // Uptrend
   if(price < ma) return -1; // Downtrend
   return 0;
}

//===================================================================
//  ENTRY SIGNAL - EMA20/50 crossover + RSI filter on current TF
//===================================================================

ENUM_ORDER_TYPE GetEntrySignal()
{
   double fastCur  = bufFastMA[0];
   double fastPrev = bufFastMA[1];
   double slowCur  = bufSlowMA[0];
   double slowPrev = bufSlowMA[1];
   double rsi      = bufRSI[0];

   // BUY: fast crosses above slow + RSI not overbought
   if(fastPrev <= slowPrev && fastCur > slowCur && rsi < InpRSIOverbought)
      return ORDER_TYPE_BUY;

   // SELL: fast crosses below slow + RSI not oversold
   if(fastPrev >= slowPrev && fastCur < slowCur && rsi > InpRSIOversold)
      return ORDER_TYPE_SELL;

   return (ENUM_ORDER_TYPE)-1;
}

//===================================================================
//  EXECUTE ENTRY - Calculate lot from risk, open trade
//===================================================================

void ExecuteEntry(ENUM_ORDER_TYPE type)
{
   double lot = CalcLotByRisk(InpRiskPercent, InpSLPercent);
   if(lot <= 0) return;

   if(!OpenTrade(type, lot, InpSLPercent, InpTPPercent)) return;

   double price         = (type == ORDER_TYPE_BUY)
                          ? SymbolInfoDouble(_Symbol, SYMBOL_ASK)
                          : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   gFirstEntryPrice     = price;
   gLastDCAPrice        = price;
   gDCALevel            = 0;

   PrintFormat("[ENTRY %s] Price: %.5f | Lot: %.2f | Balance: %.2f | Risk: %.1f%%",
               (type == ORDER_TYPE_BUY) ? "BUY" : "SELL",
               price, lot, AccountInfoDouble(ACCOUNT_BALANCE), InpRiskPercent);
}

//===================================================================
//  DCA CHECK - Only add in trend direction
//===================================================================

void CheckDCA(int buyCount, int sellCount)
{
   if(gDCALevel >= InpMaxDCALevels) return;
   if(gFirstEntryPrice <= 0)        return;

   double ask        = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid        = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double trigger    = gLastDCAPrice * InpDCATriggerPct / 100.0;

   // BUY DCA: price pulled back below last entry by trigger %
   if(buyCount > 0 && gTrendDirection == 1 && (gLastDCAPrice - ask) >= trigger)
   {
      double dcaLot = CalcDCALot(gDCALevel + 1);
      if(OpenTrade(ORDER_TYPE_BUY, dcaLot, 0, 0)) // SL/TP updated by UpdateAllTP
      {
         gDCALevel++;
         gLastDCAPrice = ask;
         PrintFormat("[DCA BUY #%d] Price: %.5f | Lot: %.2f", gDCALevel, ask, dcaLot);
         UpdateAllTP(POSITION_TYPE_BUY);
      }
   }

   // SELL DCA: price rallied above last entry by trigger %
   if(sellCount > 0 && gTrendDirection == -1 && (bid - gLastDCAPrice) >= trigger)
   {
      double dcaLot = CalcDCALot(gDCALevel + 1);
      if(OpenTrade(ORDER_TYPE_SELL, dcaLot, 0, 0))
      {
         gDCALevel++;
         gLastDCAPrice = bid;
         PrintFormat("[DCA SELL #%d] Price: %.5f | Lot: %.2f", gDCALevel, bid, dcaLot);
         UpdateAllTP(POSITION_TYPE_SELL);
      }
   }
}

//===================================================================
//  UPDATE ALL TP/SL after DCA (weighted average method)
//===================================================================

void UpdateAllTP(ENUM_POSITION_TYPE posType)
{
   double totalLot  = 0;
   double wgtPrice  = 0;
   int    digits    = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(!posInfo.SelectByIndex(i)) continue;
      if(posInfo.Symbol()           != _Symbol)        continue;
      if(posInfo.Magic()            != InpMagicNumber) continue;
      if(posInfo.PositionType()     != posType)        continue;
      totalLot += posInfo.Volume();
      wgtPrice += posInfo.PriceOpen() * posInfo.Volume();
   }

   if(totalLot <= 0) return;

   double avgPrice = wgtPrice / totalLot;
   double newTP, newSL;

   if(posType == POSITION_TYPE_BUY)
   {
      newTP = NormalizeDouble(avgPrice * (1.0 + InpTPPercent / 100.0), digits);
      newSL = NormalizeDouble(gFirstEntryPrice * (1.0 - InpSLPercent / 100.0), digits);
   }
   else
   {
      newTP = NormalizeDouble(avgPrice * (1.0 - InpTPPercent / 100.0), digits);
      newSL = NormalizeDouble(gFirstEntryPrice * (1.0 + InpSLPercent / 100.0), digits);
   }

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(!posInfo.SelectByIndex(i)) continue;
      if(posInfo.Symbol()       != _Symbol)        continue;
      if(posInfo.Magic()        != InpMagicNumber) continue;
      if(posInfo.PositionType() != posType)        continue;
      trade.PositionModify(posInfo.Ticket(), newSL, newTP);
   }

   PrintFormat("[UPDATE TP/SL] Avg: %.5f | TP: %.5f | SL: %.5f | Lots: %.2f",
               avgPrice, newTP, newSL, totalLot);
}

//===================================================================
//  TRAILING STOP (runs every tick)
//===================================================================

void ManageTrailingStop()
{
   int    digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   double point  = SymbolInfoDouble(_Symbol, SYMBOL_POINT);

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(!posInfo.SelectByIndex(i)) continue;
      if(posInfo.Symbol() != _Symbol)        continue;
      if(posInfo.Magic()  != InpMagicNumber) continue;

      double curSL    = posInfo.StopLoss();
      double curTP    = posInfo.TakeProfit();
      double openPx   = posInfo.PriceOpen();
      double trailDst = openPx * InpTrailingPercent / 100.0;

      if(posInfo.PositionType() == POSITION_TYPE_BUY)
      {
         double bid   = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         double newSL = NormalizeDouble(bid - trailDst, digits);
         if(newSL > curSL + point)
            trade.PositionModify(posInfo.Ticket(), newSL, curTP);
      }
      else
      {
         double ask   = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         double newSL = NormalizeDouble(ask + trailDst, digits);
         if(curSL == 0 || newSL < curSL - point)
            trade.PositionModify(posInfo.Ticket(), newSL, curTP);
      }
   }
}

//===================================================================
//  LOT SIZE CALCULATION (Risk-based)
//  Formula: Lot = (Balance × RiskPct%) / (SL_distance × TickValue)
//===================================================================

double CalcLotByRisk(double riskPct, double slPct)
{
   double balance  = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskAmt  = balance * riskPct / 100.0;  // e.g. $500 × 1% = $5

   double price    = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double slDist   = price * slPct / 100.0;       // SL distance in price

   // Convert SL distance to points
   double pointSz  = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   if(pointSz <= 0) return InpMinLotSize;

   double slPoints = slDist / pointSz;

   // Tick value: how much 1 point move = $X for 1.0 lot
   double tickVal  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSz   = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tickSz <= 0 || tickVal <= 0) return InpMinLotSize;

   double valPerPoint = tickVal / tickSz * pointSz; // $ per point per lot

   if(valPerPoint <= 0 || slPoints <= 0) return InpMinLotSize;

   double lot = riskAmt / (slPoints * valPerPoint);

   return NormalizeLot(lot);
}

//===================================================================
//  DCA LOT: multiply each level
//===================================================================

double CalcDCALot(int level)
{
   double baseLot = CalcLotByRisk(InpRiskPercent, InpSLPercent);
   double dcaLot  = baseLot * MathPow(InpDCALotMultiply, level);
   return NormalizeLot(dcaLot);
}

//===================================================================
//  OPEN TRADE
//===================================================================

bool OpenTrade(ENUM_ORDER_TYPE type, double lot, double slPct, double tpPct)
{
   double ask    = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid    = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   int    digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   double price  = (type == ORDER_TYPE_BUY) ? ask : bid;

   double sl = 0, tp = 0;

   if(slPct > 0)
   {
      sl = (type == ORDER_TYPE_BUY)
           ? NormalizeDouble(price * (1.0 - slPct / 100.0), digits)
           : NormalizeDouble(price * (1.0 + slPct / 100.0), digits);
   }

   if(tpPct > 0)
   {
      tp = (type == ORDER_TYPE_BUY)
           ? NormalizeDouble(price * (1.0 + tpPct / 100.0), digits)
           : NormalizeDouble(price * (1.0 - tpPct / 100.0), digits);
   }

   bool ok = (type == ORDER_TYPE_BUY)
             ? trade.Buy(lot,  _Symbol, ask, sl, tp, InpMagicComment)
             : trade.Sell(lot, _Symbol, bid, sl, tp, InpMagicComment);

   if(!ok)
      PrintFormat("[ERROR] Open %s failed: %d | Lot: %.2f",
                  (type == ORDER_TYPE_BUY) ? "BUY" : "SELL", GetLastError(), lot);
   return ok;
}

//===================================================================
//  CLOSE ALL POSITIONS (on trend reversal)
//===================================================================

void CloseAllPositions()
{
   int closed = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(!posInfo.SelectByIndex(i)) continue;
      if(posInfo.Symbol() != _Symbol)        continue;
      if(posInfo.Magic()  != InpMagicNumber) continue;

      if(trade.PositionClose(posInfo.Ticket()))
         closed++;
      else
         PrintFormat("[CLOSE ERROR] Ticket: %d | Code: %d",
                     (int)posInfo.Ticket(), GetLastError());
   }
   if(closed > 0)
      PrintFormat("[CLOSE ALL] Closed %d position(s) due to trend reversal", closed);
}

//===================================================================
//  HELPERS
//===================================================================

bool RefreshIndicators()
{
   if(CopyBuffer(hTrendMA, 0, 0, 3, bufTrendMA) < 3) return false;
   if(CopyBuffer(hADX,     0, 0, 3, bufADXMain) < 3) return false;
   if(CopyBuffer(hFastMA,  0, 0, 3, bufFastMA)  < 3) return false;
   if(CopyBuffer(hSlowMA,  0, 0, 3, bufSlowMA)  < 3) return false;
   if(CopyBuffer(hRSI,     0, 0, 3, bufRSI)     < 3) return false;
   return true;
}

int CountPositions(ENUM_POSITION_TYPE posType)
{
   int count = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(!posInfo.SelectByIndex(i)) continue;
      if(posInfo.Symbol()       != _Symbol)        continue;
      if(posInfo.Magic()        != InpMagicNumber) continue;
      if(posInfo.PositionType() == posType)        count++;
   }
   return count;
}

double NormalizeLot(double lot)
{
   double minLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

   lot = MathMax(lot, MathMax(minLot, InpMinLotSize));
   lot = MathMin(lot, MathMin(maxLot, InpMaxLotSize));
   lot = NormalizeDouble(MathFloor(lot / lotStep) * lotStep, 2);
   return lot;
}

bool CheckSpread()
{
   return (SymbolInfoInteger(_Symbol, SYMBOL_SPREAD) <= InpMaxSpread);
}

bool IsInSession()
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   return (dt.hour >= InpSessionStart && dt.hour < InpSessionEnd);
}

bool IsMaxDrawdown()
{
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double equity  = AccountInfoDouble(ACCOUNT_EQUITY);
   if(balance <= 0) return false;

   double dd = (balance - equity) / balance * 100.0;
   if(dd >= InpMaxDDPercent)
   {
      static datetime lastWarn = 0;
      if(TimeCurrent() - lastWarn > 300)
      {
         PrintFormat("[RISK GUARD] Drawdown %.2f%% exceeds limit %.2f%% | Trading paused",
                     dd, InpMaxDDPercent);
         lastWarn = TimeCurrent();
      }
      return true;
   }
   return false;
}

void ResetDCAState()
{
   gFirstEntryPrice = 0;
   gLastDCAPrice    = 0;
   gDCALevel        = 0;
}

string TrendName(int trend)
{
   if(trend ==  1) return "UPTREND";
   if(trend == -1) return "DOWNTREND";
   return "SIDEWAYS";
}

//===================================================================
//  ON TRADE (log closed deals)
//===================================================================

void OnTradeTransaction(const MqlTradeTransaction& trans,
                        const MqlTradeRequest&     request,
                        const MqlTradeResult&      result)
{
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD) return;

   ulong deal = trans.deal;
   if(!HistoryDealSelect(deal)) return;

   long entryType = HistoryDealGetInteger(deal, DEAL_ENTRY);
   if(entryType == DEAL_ENTRY_OUT || entryType == DEAL_ENTRY_OUT_BY)
   {
      double profit = HistoryDealGetDouble(deal, DEAL_PROFIT);
      double volume = HistoryDealGetDouble(deal, DEAL_VOLUME);
      double price  = HistoryDealGetDouble(deal, DEAL_PRICE);
      PrintFormat("[CLOSED] Vol: %.2f | Price: %.5f | Profit: %+.2f | Balance: %.2f",
                  volume, price, profit, AccountInfoDouble(ACCOUNT_BALANCE));

      // Reset DCA state after close
      if(CountPositions(POSITION_TYPE_BUY) + CountPositions(POSITION_TYPE_SELL) == 0)
         ResetDCAState();
   }
}
//+------------------------------------------------------------------+
