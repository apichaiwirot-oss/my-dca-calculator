//+------------------------------------------------------------------+
//|                                          TrendFollower_Pro.mq5   |
//|                   Multi-Indicator Trend Following EA             |
//|                   BTCUSD, XAUUSD, TFEX, Forex                   |
//|                   Version 1.0                                    |
//+------------------------------------------------------------------+
//
//  STRATEGY OVERVIEW
//  ─────────────────
//  ใช้ Indicator หลายตัวยืนยันสัญญาณก่อนเข้า Order
//
//  TREND FILTER (Higher TF)
//    EMA50 > EMA200  →  UPTREND zone   → Long only
//    EMA50 < EMA200  →  DOWNTREND zone → Short only
//
//  ENTRY SIGNAL (Current TF) — ต้องผ่านอย่างน้อย 2 ใน 3
//    1. MACD  : MACD line ตัดขึ้น/ลง Signal line
//    2. Bollinger Band : ปิดทะลุ Upper (Long) / Lower (Short)
//    3. Parabolic SAR  : SAR เปลี่ยนด้านใต้/บนแท่งเทียน
//
//  EXIT
//    - Stop Loss  : ATR-based หรือ Swing High/Low
//    - Take Profit: ปล่อยวิ่งตาม Trailing Stop (ATR × multiplier)
//    - Force Exit : EMA crossover ตรงข้าม
//
//  RISK MANAGEMENT
//    - Lot = (Balance × Risk%) / (ATR × ATR_Multiplier × TickValue)
//    - จำกัด Risk 2-5% ต่อ trade
//    - Max Drawdown guard
//
//  DOUBLE ROBOT (A/B)
//    - Robot A : Timeframe เร็ว (M15/H1) — เก็บกำไรถี่
//    - Robot B : Timeframe ช้า (H4/D1)  — ตามเทรนด์ใหญ่
//    - ใช้ Magic Number ต่างกัน รันบนกราฟเดียวกันได้
//+------------------------------------------------------------------+
#property copyright "TrendFollower Pro"
#property version   "1.00"
#property description "Multi-Indicator Trend Following EA | EMA+MACD+BB+SAR | ATR Risk"

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>

//===================================================================
//  INPUT PARAMETERS
//===================================================================

input group "═══ Robot Identity ═══"
input int      InpMagicNumber     = 300100;       // Magic Number (A=300100, B=300200)
input string   InpBotName         = "TF_RobotA";  // Bot Name (for logs)

input group "═══ Trend Filter (Higher Timeframe) ═══"
input ENUM_TIMEFRAMES InpTrendTF  = PERIOD_H4;    // Trend Timeframe
input int      InpTrendEMAFast    = 50;            // Fast EMA (trend TF)
input int      InpTrendEMASlow    = 200;           // Slow EMA (trend TF)
input bool     InpStrictTrend     = true;          // Strict: skip trade if trend unclear

input group "═══ Entry Indicators (Current Timeframe) ═══"
input int      InpMinSignals      = 2;             // Min confirmations needed (1-4)

// EMA for entry
input int      InpEntryEMAFast    = 20;            // Entry Fast EMA
input int      InpEntryEMASlow    = 50;            // Entry Slow EMA

// MACD
input int      InpMACDFast        = 12;            // MACD Fast EMA
input int      InpMACDSlow        = 26;            // MACD Slow EMA
input int      InpMACDSignal      = 9;             // MACD Signal
input bool     InpUseMACDHist     = true;          // Use MACD Histogram (histogram > 0 = bullish)
input bool     InpMACDMomentum    = true;          // Require histogram growing (momentum building)

// Bollinger Bands
input int      InpBBPeriod        = 20;            // BB Period
input double   InpBBDeviation     = 2.0;           // BB Deviation
// BB Signal Mode: true=Pullback entry (cross above/below midline), false=Price position vs midline
input bool     InpBBPullback      = true;          // BB Pullback: price crosses back above mid (buy dip)

// Parabolic SAR
input double   InpSARStep         = 0.02;          // SAR Step
input double   InpSARMax          = 0.2;           // SAR Maximum

// RSI (Signal 4 — optional)
input bool     InpUseRSI          = true;          // Enable RSI as 4th signal
input int      InpRSIPeriod       = 14;            // RSI Period
input int      InpRSILevel        = 50;            // RSI threshold (Long: >level, Short: <100-level)

input group "═══ ATR Risk Management ═══"
input int      InpATRPeriod       = 14;            // ATR Period
input double   InpRiskPercent     = 2.0;           // Risk % per trade (2-5%)
input double   InpATRSLMulti      = 2.0;           // SL = ATR × this multiplier
input double   InpATRTPMulti      = 4.0;           // Initial TP = ATR × this multiplier
input bool     InpUseSwingHL      = true;          // Use Swing High/Low for SL (overrides ATR SL)
input int      InpSwingLookback   = 5;             // Bars to look back for Swing H/L
input double   InpMaxLotSize      = 1.00;          // Hard cap lot size
input double   InpMinLotSize      = 0.01;          // Min lot size

input group "═══ Debug ═══"
input bool     InpDebugLog        = true;          // Print debug reason when no trade

input group "═══ Trailing Stop ═══"
input bool     InpUseTrailing     = true;          // Enable ATR Trailing Stop
input double   InpTrailATRMulti   = 2.0;           // Trail distance = ATR × this
input double   InpTrailActivePct  = 0.5;           // Activate trailing when profit >= ATR × 0.5

input group "═══ Force Exit Conditions ═══"
input bool     InpExitOnEMACross  = true;          // Exit when EMA crossover reverses
input bool     InpExitOnSARFlip   = false;         // Exit when Parabolic SAR flips
input bool     InpExitOnMACDCross = false;         // Exit when MACD crosses back

input group "═══ Protection ═══"
input double   InpMaxDDPercent    = 15.0;          // Max Drawdown % — stop trading
input int      InpMaxSpread       = 1000;          // Max spread (points) — BTC:1000, Forex:30
input int      InpSlippage        = 30;            // Slippage (points)
input int      InpMaxPositions    = 1;             // Max open positions (this bot)

input group "═══ Session Filter ═══"
input bool     InpUseSession      = false;         // Enable session filter
input int      InpSessionStart    = 2;             // Start hour (server time)
input int      InpSessionEnd      = 22;            // End hour

input group "═══ Scalp Mode ═══"
// เปิด Scalp Mode → EA จะเปิด-ปิด Order เร็วบน TF เล็ก (ข้าม Trend Following logic)
input bool            InpScalpMode      = false;      // Enable Scalp Mode (fast open/close on small TF)
input ENUM_TIMEFRAMES InpScalpTF        = PERIOD_M5;  // Scalp Timeframe (M1 / M5)
input int             InpScalpEMAFast   = 5;          // Scalp Fast EMA (entry TF)
input int             InpScalpEMASlow   = 10;         // Scalp Slow EMA (entry TF)
input int             InpScalpRSIPeriod = 7;          // Scalp RSI Period
input double          InpScalpTPPoints  = 150.0;      // Scalp TP in points (XAUUSD 150pts≈$1.50)
input double          InpScalpSLPoints  = 80.0;       // Scalp SL in points
input bool            InpScalpAutoLot   = true;       // Auto lot by risk % (true) / fixed lot (false)
input double          InpScalpRiskPct   = 0.5;        // Scalp risk % per trade
input double          InpScalpFixedLot  = 0.01;       // Fixed lot (used when AutoLot=false)
input bool            InpScalpUseTrend  = true;       // Filter by higher TF trend
input ENUM_TIMEFRAMES InpScalpTrendTF   = PERIOD_M15; // Scalp Trend Timeframe (M15 recommended)
input int             InpScalpTrendEMA  = 50;         // Trend EMA period on ScalpTrendTF
input bool            InpScalpEveryBar  = true;       // Trade every bar when EMA aligned (true=รัวๆ / false=crossover only)
input bool            InpScalpQuickExit = true;       // Quick exit when EMA reverses
input bool            InpScalpRSIExit   = true;       // Quick exit when RSI crosses back 50 (ออกเร็ว)
input int             InpScalpMaxBars   = 8;          // Force exit after N scalp bars (0=off)
input int             InpScalpMaxPos    = 1;          // Max simultaneous scalp positions

//===================================================================
//  GLOBAL VARIABLES
//===================================================================

CTrade        trade;
CPositionInfo posInfo;

// Indicator handles — Trend TF
int  hTrendEMAFast = INVALID_HANDLE;
int  hTrendEMASlow = INVALID_HANDLE;

// Indicator handles — Entry TF
int  hEntryEMAFast = INVALID_HANDLE;
int  hEntryEMASlow = INVALID_HANDLE;
int  hMACD         = INVALID_HANDLE;
int  hBB           = INVALID_HANDLE;
int  hSAR          = INVALID_HANDLE;
int  hATR          = INVALID_HANDLE;
int  hRSI          = INVALID_HANDLE;

// Indicator handles — Scalp TF
int  hScalpEMAFast  = INVALID_HANDLE;
int  hScalpEMASlow  = INVALID_HANDLE;
int  hScalpRSI      = INVALID_HANDLE;
int  hScalpATR      = INVALID_HANDLE;
int  hScalpTrendEMA = INVALID_HANDLE;   // Trend EMA on M15 (for scalp bias)

// Buffers
double bTrendFast[], bTrendSlow[];
double bEntryFast[], bEntrySlow[];
double bMACDMain[], bMACDSignal[], bMACDHist[];
double bBBUpper[], bBBLower[], bBBMid[];
double bSAR[], bATR[], bRSI[];
double bScalpFast[], bScalpSlow[], bScalpRSI[], bScalpATR[], bScalpTrend[];

datetime gLastBar      = 0;
datetime gLastScalpBar = 0;
double   gATRValue     = 0;
int      gScalpOpenBar = 0;             // bar index when last scalp position opened

//===================================================================
//  INIT / DEINIT
//===================================================================

int OnInit()
{
   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetDeviationInPoints(InpSlippage);
   trade.SetTypeFilling(GetSymbolFilling());
   trade.SetAsyncMode(false);

   // Trend TF handles
   hTrendEMAFast = iMA(_Symbol, InpTrendTF, InpTrendEMAFast, 0, MODE_EMA, PRICE_CLOSE);
   hTrendEMASlow = iMA(_Symbol, InpTrendTF, InpTrendEMASlow, 0, MODE_EMA, PRICE_CLOSE);

   // Entry TF handles
   hEntryEMAFast = iMA(_Symbol, PERIOD_CURRENT, InpEntryEMAFast, 0, MODE_EMA, PRICE_CLOSE);
   hEntryEMASlow = iMA(_Symbol, PERIOD_CURRENT, InpEntryEMASlow, 0, MODE_EMA, PRICE_CLOSE);
   hMACD         = iMACD(_Symbol, PERIOD_CURRENT, InpMACDFast, InpMACDSlow, InpMACDSignal, PRICE_CLOSE);
   hBB           = iBands(_Symbol, PERIOD_CURRENT, InpBBPeriod, 0, InpBBDeviation, PRICE_CLOSE);
   hSAR          = iSAR(_Symbol, PERIOD_CURRENT, InpSARStep, InpSARMax);
   hATR          = iATR(_Symbol, PERIOD_CURRENT, InpATRPeriod);
   if(InpUseRSI)
      hRSI       = iRSI(_Symbol, PERIOD_CURRENT, InpRSIPeriod, PRICE_CLOSE);

   if(hTrendEMAFast == INVALID_HANDLE || hTrendEMASlow == INVALID_HANDLE ||
      hEntryEMAFast == INVALID_HANDLE || hEntryEMASlow == INVALID_HANDLE ||
      hMACD         == INVALID_HANDLE || hBB           == INVALID_HANDLE ||
      hSAR          == INVALID_HANDLE || hATR          == INVALID_HANDLE ||
      (InpUseRSI && hRSI == INVALID_HANDLE))
   {
      Alert(InpBotName, ": Failed to create indicator handles!");
      return INIT_FAILED;
   }

   // Scalp Mode handles
   if(InpScalpMode)
   {
      hScalpEMAFast  = iMA(_Symbol, InpScalpTF,      InpScalpEMAFast,  0, MODE_EMA, PRICE_CLOSE);
      hScalpEMASlow  = iMA(_Symbol, InpScalpTF,      InpScalpEMASlow,  0, MODE_EMA, PRICE_CLOSE);
      hScalpRSI      = iRSI(_Symbol, InpScalpTF,     InpScalpRSIPeriod, PRICE_CLOSE);
      hScalpATR      = iATR(_Symbol, InpScalpTF,     InpATRPeriod);
      hScalpTrendEMA = iMA(_Symbol, InpScalpTrendTF, InpScalpTrendEMA, 0, MODE_EMA, PRICE_CLOSE);
      if(hScalpEMAFast  == INVALID_HANDLE || hScalpEMASlow  == INVALID_HANDLE ||
         hScalpRSI      == INVALID_HANDLE || hScalpATR      == INVALID_HANDLE ||
         hScalpTrendEMA == INVALID_HANDLE)
      {
         Alert(InpBotName, ": Failed to create Scalp indicator handles!");
         return INIT_FAILED;
      }
      ArraySetAsSeries(bScalpFast,  true);
      ArraySetAsSeries(bScalpSlow,  true);
      ArraySetAsSeries(bScalpRSI,   true);
      ArraySetAsSeries(bScalpATR,   true);
      ArraySetAsSeries(bScalpTrend, true);
   }

   ArraySetAsSeries(bTrendFast,  true);
   ArraySetAsSeries(bTrendSlow,  true);
   ArraySetAsSeries(bEntryFast,  true);
   ArraySetAsSeries(bEntrySlow,  true);
   ArraySetAsSeries(bMACDMain,   true);
   ArraySetAsSeries(bMACDSignal, true);
   ArraySetAsSeries(bMACDHist,   true);
   ArraySetAsSeries(bBBUpper,    true);
   ArraySetAsSeries(bBBLower,    true);
   ArraySetAsSeries(bBBMid,      true);
   ArraySetAsSeries(bSAR,        true);
   ArraySetAsSeries(bATR,        true);
   ArraySetAsSeries(bRSI,        true);

   if(InpScalpMode)
      PrintFormat("══ %s [SCALP MODE] | %s | ScalpTF:%s TrendTF:%s EMA%d | Entry EMA%d/%d | TP:%.0fpts SL:%.0fpts | EveryBar:%s RSIExit:%s MaxBars:%d ══",
                  InpBotName, _Symbol,
                  EnumToString(InpScalpTF), EnumToString(InpScalpTrendTF), InpScalpTrendEMA,
                  InpScalpEMAFast, InpScalpEMASlow,
                  InpScalpTPPoints, InpScalpSLPoints,
                  InpScalpEveryBar?"ON":"OFF", InpScalpRSIExit?"ON":"OFF", InpScalpMaxBars);
   else
      PrintFormat("══ %s Initialized | %s | TrendTF: %s | Risk: %.1f%% | MinSignals: %d/4 | RSI:%s ══",
                  InpBotName, _Symbol, EnumToString(InpTrendTF),
                  InpRiskPercent, InpMinSignals, InpUseRSI?"ON":"OFF");
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   int handles[] = {hTrendEMAFast, hTrendEMASlow, hEntryEMAFast, hEntryEMASlow,
                    hMACD, hBB, hSAR, hATR, hRSI,
                    hScalpEMAFast, hScalpEMASlow, hScalpRSI, hScalpATR, hScalpTrendEMA};
   for(int i = 0; i < ArraySize(handles); i++)
      if(handles[i] != INVALID_HANDLE) IndicatorRelease(handles[i]);
}

//===================================================================
//  MAIN TICK
//===================================================================

void OnTick()
{
   // ── Scalp Mode: takes full control (bypass trend following) ──────
   if(InpScalpMode)
   {
      ManageScalpMode();
      return;
   }

   // Trailing stop — every tick
   if(InpUseTrailing) ManageTrailingStop();

   // New bar check
   datetime barTime = iTime(_Symbol, PERIOD_CURRENT, 0);
   if(barTime == gLastBar) return;
   gLastBar = barTime;

   // Pre-checks
   if(!CheckSpread())                      return;
   if(InpUseSession && !IsInSession())     return;
   if(IsMaxDrawdown())                     return;
   if(!RefreshAllIndicators())             return;

   gATRValue = bATR[1]; // Use last completed bar ATR

   int buyCount  = CountPositions(POSITION_TYPE_BUY);
   int sellCount = CountPositions(POSITION_TYPE_SELL);
   int totalPos  = buyCount + sellCount;

   // --- Force Exit Check ---
   if(totalPos > 0)
   {
      CheckForceExit(buyCount, sellCount);
      return;
   }

   // --- New Entry ---
   if(totalPos < InpMaxPositions)
   {
      // Get trend direction from higher TF
      int trend = GetTrendDirection();
      if(trend == 0 && InpStrictTrend)
      {
         if(InpDebugLog)
            PrintFormat("[%s DEBUG] Skipped: trend=SIDE & StrictTrend=true | TrendEMA fast=%.5f slow=%.5f",
                        InpBotName, bTrendFast[1], bTrendSlow[1]);
         return;
      }

      // Count entry signals
      int longSignals  = 0;
      int shortSignals = 0;
      GetEntrySignals(longSignals, shortSignals);

      string sigLog = StringFormat("Trend:%s | Signals L%d/S%d | ATR=%.5f",
                                   TrendName(trend), longSignals, shortSignals, gATRValue);

      if(InpDebugLog && longSignals < InpMinSignals && shortSignals < InpMinSignals)
         PrintFormat("[%s DEBUG] Not enough signals — %s | MACDHist=%.5f(prev=%.5f) | Close=%.5f BBMid=%.5f | SAR=%.5f | RSI=%.1f",
                     InpBotName, sigLog,
                     bMACDHist[1], bMACDHist[2],
                     iClose(_Symbol, PERIOD_CURRENT, 1),
                     bBBMid[1], bSAR[1],
                     (InpUseRSI && ArraySize(bRSI) >= 2) ? bRSI[1] : -1.0);

      // LONG: trend up + enough signals
      if(trend >= 0 && longSignals >= InpMinSignals)
      {
         Print(InpBotName, " [ENTRY LONG] ", sigLog);
         ExecuteEntry(ORDER_TYPE_BUY);
      }
      // SHORT: trend down + enough signals
      else if(trend <= 0 && shortSignals >= InpMinSignals)
      {
         Print(InpBotName, " [ENTRY SHORT] ", sigLog);
         ExecuteEntry(ORDER_TYPE_SELL);
      }
   }
}

//===================================================================
//  TREND DIRECTION (Higher TF EMA50 vs EMA200)
//===================================================================

int GetTrendDirection()
{
   // Use bar[1] = last completed bar on trend TF
   double fastEMA = bTrendFast[1];
   double slowEMA = bTrendSlow[1];
   double diff    = fastEMA - slowEMA;
   double atr     = gATRValue > 0 ? gATRValue : 1;

   // Require meaningful separation (> 10% of ATR) to avoid flat crossover noise
   if(MathAbs(diff) < atr * 0.1)
      return 0; // Too close — sideways

   if(fastEMA > slowEMA) return  1; // Uptrend
   if(fastEMA < slowEMA) return -1; // Downtrend
   return 0;
}

//===================================================================
//  SCALP MODE — เปิด-ปิดเร็วบน TF เล็ก (M1/M5)
//===================================================================

bool RefreshScalpIndicators()
{
   if(CopyBuffer(hScalpEMAFast,  0, 0, 4, bScalpFast)  < 4) return false;
   if(CopyBuffer(hScalpEMASlow,  0, 0, 4, bScalpSlow)  < 4) return false;
   if(CopyBuffer(hScalpRSI,      0, 0, 4, bScalpRSI)   < 4) return false;
   if(CopyBuffer(hScalpATR,      0, 0, 4, bScalpATR)   < 4) return false;
   if(CopyBuffer(hScalpTrendEMA, 0, 0, 4, bScalpTrend) < 4) return false;
   return true;
}

void ExecuteScalpEntry(ENUM_ORDER_TYPE type, double atrVal)
{
   double ask    = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid    = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   int    digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   double point  = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double price  = (type == ORDER_TYPE_BUY) ? ask : bid;

   double tpDist = InpScalpTPPoints * point;
   double slDist = InpScalpSLPoints * point;

   double tp = (type == ORDER_TYPE_BUY) ? NormalizeDouble(price + tpDist, digits)
                                        : NormalizeDouble(price - tpDist, digits);
   double sl = (type == ORDER_TYPE_BUY) ? NormalizeDouble(price - slDist, digits)
                                        : NormalizeDouble(price + slDist, digits);

   double lot;
   if(InpScalpAutoLot && slDist > 0)
   {
      double balance  = AccountInfoDouble(ACCOUNT_BALANCE);
      double riskAmt  = balance * InpScalpRiskPct / 100.0;
      double tickSz   = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
      double tickVal  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
      double valPerPt = (tickSz > 0 && tickVal > 0) ? (tickVal / tickSz) * point : 0;
      lot = (valPerPt > 0) ? riskAmt / (InpScalpSLPoints * valPerPt) : InpScalpFixedLot;
   }
   else
      lot = InpScalpFixedLot;

   lot = NormalizeLot(lot);

   bool ok = (type == ORDER_TYPE_BUY)
             ? trade.Buy(lot,  _Symbol, ask, sl, tp, InpBotName + "_S")
             : trade.Sell(lot, _Symbol, bid, sl, tp, InpBotName + "_S");

   if(ok)
      PrintFormat("[%s SCALP OPEN] %s | Price:%.5f | Lot:%.2f | SL:%.5f | TP:%.5f | ATR:%.5f",
                  InpBotName, (type==ORDER_TYPE_BUY)?"LONG":"SHORT",
                  price, lot, sl, tp, atrVal);
   else
      PrintFormat("[%s SCALP ERROR] Open failed: %d", InpBotName, GetLastError());
}

void ManageScalpMode()
{
   // ── ทำงานทุก bar ใหม่บน Scalp TF ────────────────────────────────
   datetime scalpBar = iTime(_Symbol, InpScalpTF, 0);
   if(scalpBar == gLastScalpBar) return;
   gLastScalpBar = scalpBar;

   if(!CheckSpread())                   return;
   if(InpUseSession && !IsInSession())  return;
   if(IsMaxDrawdown())                  return;
   if(!RefreshScalpIndicators())        return;

   double scalpATR = bScalpATR[1];
   if(scalpATR > 0) gATRValue = scalpATR;

   int buyCount  = CountPositions(POSITION_TYPE_BUY);
   int sellCount = CountPositions(POSITION_TYPE_SELL);
   int totalPos  = buyCount + sellCount;

   double rsi        = bScalpRSI[1];
   bool   emaIsBull  = (bScalpFast[1] > bScalpSlow[1]);
   bool   emaIsBear  = (bScalpFast[1] < bScalpSlow[1]);
   int    currentBar = iBars(_Symbol, InpScalpTF);

   // ── EXIT LOGIC ───────────────────────────────────────────────────
   if(totalPos > 0)
   {
      bool exitLong  = false;
      bool exitShort = false;
      string exitReason = "";

      // 1. EMA กลับทิศ
      if(InpScalpQuickExit)
      {
         if(buyCount  > 0 && emaIsBear) { exitLong  = true; exitReason = "EMA reversed bearish"; }
         if(sellCount > 0 && emaIsBull) { exitShort = true; exitReason = "EMA reversed bullish"; }
      }

      // 2. RSI ข้าม 50 กลับ (ออกเร็ว ก่อน EMA)
      if(InpScalpRSIExit)
      {
         if(buyCount  > 0 && rsi < 50.0) { exitLong  = true; exitReason = StringFormat("RSI=%.1f<50", rsi); }
         if(sellCount > 0 && rsi > 50.0) { exitShort = true; exitReason = StringFormat("RSI=%.1f>50", rsi); }
      }

      // 3. Max bars — บังคับออกหลัง N bars
      if(InpScalpMaxBars > 0 && gScalpOpenBar > 0)
      {
         int barsHeld = currentBar - gScalpOpenBar;
         if(barsHeld >= InpScalpMaxBars)
         {
            exitLong = exitShort = true;
            exitReason = StringFormat("MaxBars(%d/%d)", barsHeld, InpScalpMaxBars);
         }
      }

      if((exitLong && buyCount > 0) || (exitShort && sellCount > 0))
      {
         PrintFormat("[%s SCALP EXIT] %s | RSI=%.1f | EMA fast=%.5f slow=%.5f | Reason: %s",
                     InpBotName, (buyCount>0)?"LONG":"SHORT",
                     rsi, bScalpFast[1], bScalpSlow[1], exitReason);
         CloseAllPositions();
         buyCount = sellCount = totalPos = 0;
         gScalpOpenBar = 0;
      }
   }

   if(totalPos >= InpScalpMaxPos) return;

   // ── TREND FILTER (M15 EMA) ───────────────────────────────────────
   int trend = 0;
   if(InpScalpUseTrend && ArraySize(bScalpTrend) >= 2)
   {
      double trendClose = iClose(_Symbol, InpScalpTrendTF, 1);
      trend = (trendClose > bScalpTrend[1]) ? 1 : -1;
   }

   // ── ENTRY SIGNALS ────────────────────────────────────────────────
   bool longOK, shortOK;

   if(InpScalpEveryBar)
   {
      // รัวๆ: เข้าทุก bar ที่ EMA aligned + RSI ยืนยัน
      longOK  = emaIsBull && (rsi > 50.0);
      shortOK = emaIsBear && (rsi < 50.0);
   }
   else
   {
      // Crossover only (เข้าแค่ตอน EMA ตัด)
      bool emaBullCross = (bScalpFast[2] <= bScalpSlow[2]) && emaIsBull;
      bool emaBearCross = (bScalpFast[2] >= bScalpSlow[2]) && emaIsBear;
      longOK  = emaBullCross && (rsi > 50.0);
      shortOK = emaBearCross && (rsi < 50.0);
   }

   bool goLong  = longOK  && (!InpScalpUseTrend || trend >= 0);
   bool goShort = shortOK && (!InpScalpUseTrend || trend <= 0);

   if(goLong)
   {
      PrintFormat("[%s SCALP ENTRY] LONG | EMA fast=%.5f>slow=%.5f | RSI=%.1f | Trend=%s | Mode:%s",
                  InpBotName, bScalpFast[1], bScalpSlow[1], rsi,
                  TrendName(trend), InpScalpEveryBar?"EveryBar":"Crossover");
      ExecuteScalpEntry(ORDER_TYPE_BUY, scalpATR);
      gScalpOpenBar = iBars(_Symbol, InpScalpTF);
   }
   else if(goShort)
   {
      PrintFormat("[%s SCALP ENTRY] SHORT | EMA fast=%.5f<slow=%.5f | RSI=%.1f | Trend=%s | Mode:%s",
                  InpBotName, bScalpFast[1], bScalpSlow[1], rsi,
                  TrendName(trend), InpScalpEveryBar?"EveryBar":"Crossover");
      ExecuteScalpEntry(ORDER_TYPE_SELL, scalpATR);
      gScalpOpenBar = iBars(_Symbol, InpScalpTF);
   }
   else if(InpDebugLog)
   {
      PrintFormat("[%s SCALP DEBUG] No entry | EMA fast=%.5f slow=%.5f | RSI=%.1f | Trend=%s",
                  InpBotName, bScalpFast[1], bScalpSlow[1], rsi, TrendName(trend));
   }
}

//===================================================================
//  ENTRY SIGNALS — 3 independent confirmations
//===================================================================

void GetEntrySignals(int &longSig, int &shortSig)
{
   longSig  = 0;
   shortSig = 0;

   // ── Signal 1: MACD ──────────────────────────────────────────────
   if(InpUseMACDHist)
   {
      if(InpMACDMomentum)
      {
         // Histogram positive AND growing (momentum building = higher quality entry)
         if(bMACDHist[1] > 0 && bMACDHist[1] > bMACDHist[2]) longSig++;
         if(bMACDHist[1] < 0 && bMACDHist[1] < bMACDHist[2]) shortSig++;
      }
      else
      {
         // Histogram direction only
         if(bMACDHist[1] > 0) longSig++;
         if(bMACDHist[1] < 0) shortSig++;
      }
   }
   else
   {
      // Line crossover
      if(bMACDMain[2] <= bMACDSignal[2] && bMACDMain[1] > bMACDSignal[1]) longSig++;
      if(bMACDMain[2] >= bMACDSignal[2] && bMACDMain[1] < bMACDSignal[1]) shortSig++;
   }

   // ── Signal 2: Bollinger Band ────────────────────────────────────
   double closeBar1 = iClose(_Symbol, PERIOD_CURRENT, 1);
   double closeBar2 = iClose(_Symbol, PERIOD_CURRENT, 2);

   if(InpBBPullback)
   {
      // Pullback entry: price crosses back above/below BB midline
      // Long  = price dipped near mid then crosses back above (buy the dip in uptrend)
      // Short = price rallied near mid then crosses back below (sell the bounce in downtrend)
      if(closeBar2 <= bBBMid[2] && closeBar1 > bBBMid[1]) longSig++;
      if(closeBar2 >= bBBMid[2] && closeBar1 < bBBMid[1]) shortSig++;
   }
   else
   {
      // Simple position: price above midline = bullish, below = bearish
      if(closeBar1 > bBBMid[1]) longSig++;
      if(closeBar1 < bBBMid[1]) shortSig++;
   }

   // ── Signal 3: Parabolic SAR flip ───────────────────────────────
   // SAR flips when it crosses from above to below candle (or reverse)
   double highBar1 = iHigh(_Symbol, PERIOD_CURRENT, 1);
   double lowBar1  = iLow(_Symbol,  PERIOD_CURRENT, 1);
   double highBar2 = iHigh(_Symbol, PERIOD_CURRENT, 2);
   double lowBar2  = iLow(_Symbol,  PERIOD_CURRENT, 2);

   bool sarWasAbove = (bSAR[2] > highBar2); // SAR was above candle (bearish)
   bool sarNowBelow = (bSAR[1] < lowBar1);  // SAR now below candle (bullish flip)
   bool sarWasBelow = (bSAR[2] < lowBar2);
   bool sarNowAbove = (bSAR[1] > highBar1);

   if(sarWasAbove && sarNowBelow) longSig++;   // SAR flipped bullish
   if(sarWasBelow && sarNowAbove) shortSig++;  // SAR flipped bearish

   // ── Signal 4: RSI (optional) ────────────────────────────────────
   if(InpUseRSI && ArraySize(bRSI) >= 3)
   {
      // RSI above threshold = bullish momentum, below = bearish
      if(bRSI[1] > InpRSILevel)            longSig++;
      if(bRSI[1] < (100 - InpRSILevel))    shortSig++;
   }
}

//===================================================================
//  EXECUTE ENTRY — ATR-based SL/TP + lot sizing
//===================================================================

void ExecuteEntry(ENUM_ORDER_TYPE type)
{
   if(gATRValue <= 0) return;

   double ask    = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid    = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   int    digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   double price  = (type == ORDER_TYPE_BUY) ? ask : bid;

   // ── Calculate Stop Loss ─────────────────────────────────────────
   double slDist = gATRValue * InpATRSLMulti;

   if(InpUseSwingHL)
   {
      // Use recent swing low (buy) or swing high (sell) as SL
      double swingLevel = GetSwingLevel(type, InpSwingLookback);
      if(swingLevel > 0)
      {
         double swingDist = MathAbs(price - swingLevel);
         // Take the wider of ATR-SL vs Swing-SL for safety
         slDist = MathMax(slDist, swingDist);
      }
   }

   double sl = (type == ORDER_TYPE_BUY)
               ? NormalizeDouble(price - slDist, digits)
               : NormalizeDouble(price + slDist, digits);

   // ── Calculate Initial TP (ATR-based, trailing will override later)
   double tpDist = gATRValue * InpATRTPMulti;
   double tp = (type == ORDER_TYPE_BUY)
               ? NormalizeDouble(price + tpDist, digits)
               : NormalizeDouble(price - tpDist, digits);

   // ── Calculate Lot (Risk-based) ──────────────────────────────────
   double lot = CalcLotByATR(slDist);
   if(lot <= 0) return;

   // ── Open Trade ──────────────────────────────────────────────────
   bool ok = (type == ORDER_TYPE_BUY)
             ? trade.Buy(lot,  _Symbol, ask, sl, tp, InpBotName)
             : trade.Sell(lot, _Symbol, bid, sl, tp, InpBotName);

   if(ok)
   {
      double rr = tpDist / slDist;
      PrintFormat("[%s OPEN] %s | Price: %.5f | Lot: %.2f | SL: %.5f | TP: %.5f | R:R=1:%.1f | ATR=%.5f",
                  InpBotName, (type==ORDER_TYPE_BUY)?"LONG":"SHORT",
                  price, lot, sl, tp, rr, gATRValue);
   }
   else
      PrintFormat("[%s ERROR] Open failed: %d", InpBotName, GetLastError());
}

//===================================================================
//  FORCE EXIT — EMA cross / SAR flip / MACD cross (opposite)
//===================================================================

void CheckForceExit(int buyCount, int sellCount)
{
   bool exitLong  = false;
   bool exitShort = false;

   // Exit on EMA crossover reversal
   if(InpExitOnEMACross)
   {
      bool emaBearCross = (bEntryFast[2] >= bEntrySlow[2]) && (bEntryFast[1] < bEntrySlow[1]);
      bool emaBullCross = (bEntryFast[2] <= bEntrySlow[2]) && (bEntryFast[1] > bEntrySlow[1]);
      if(buyCount  > 0 && emaBearCross) exitLong  = true;
      if(sellCount > 0 && emaBullCross) exitShort = true;
   }

   // Exit on SAR flip reversal
   if(InpExitOnSARFlip)
   {
      double high1 = iHigh(_Symbol, PERIOD_CURRENT, 1);
      double low1  = iLow(_Symbol,  PERIOD_CURRENT, 1);
      double high2 = iHigh(_Symbol, PERIOD_CURRENT, 2);
      double low2  = iLow(_Symbol,  PERIOD_CURRENT, 2);

      if(buyCount  > 0 && bSAR[2] < low2  && bSAR[1] > high1) exitLong  = true;
      if(sellCount > 0 && bSAR[2] > high2 && bSAR[1] < low1)  exitShort = true;
   }

   // Exit on MACD reverse cross
   if(InpExitOnMACDCross)
   {
      bool macdBearCross = (bMACDMain[2] >= bMACDSignal[2]) && (bMACDMain[1] < bMACDSignal[1]);
      bool macdBullCross = (bMACDMain[2] <= bMACDSignal[2]) && (bMACDMain[1] > bMACDSignal[1]);
      if(buyCount  > 0 && macdBearCross) exitLong  = true;
      if(sellCount > 0 && macdBullCross) exitShort = true;
   }

   if(exitLong || exitShort)
   {
      string reason = InpExitOnEMACross ? "EMA Cross" : InpExitOnSARFlip ? "SAR Flip" : "MACD Cross";
      PrintFormat("[%s FORCE EXIT] Reason: %s", InpBotName, reason);
      CloseAllPositions();
   }
}

//===================================================================
//  ATR TRAILING STOP (every tick)
//===================================================================

void ManageTrailingStop()
{
   int    digits  = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   double point   = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double atr     = gATRValue > 0 ? gATRValue : 0;
   if(atr <= 0) return;

   double trailDist = atr * InpTrailATRMulti;
   double activeDist = atr * InpTrailActivePct;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(!posInfo.SelectByIndex(i))          continue;
      if(posInfo.Symbol() != _Symbol)        continue;
      if(posInfo.Magic()  != InpMagicNumber) continue;

      double openPx   = posInfo.PriceOpen();
      double curSL    = posInfo.StopLoss();
      double curTP    = posInfo.TakeProfit();

      if(posInfo.PositionType() == POSITION_TYPE_BUY)
      {
         double bid    = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         double profit = bid - openPx;

         // Activate trailing only after minimum profit
         if(profit < activeDist) continue;

         double newSL = NormalizeDouble(bid - trailDist, digits);
         if(newSL > curSL + point)
            trade.PositionModify(posInfo.Ticket(), newSL, curTP);
      }
      else if(posInfo.PositionType() == POSITION_TYPE_SELL)
      {
         double ask    = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         double profit = openPx - ask;

         if(profit < activeDist) continue;

         double newSL = NormalizeDouble(ask + trailDist, digits);
         if(curSL == 0 || newSL < curSL - point)
            trade.PositionModify(posInfo.Ticket(), newSL, curTP);
      }
   }
}

//===================================================================
//  LOT SIZE — Risk / (ATR_SL_distance × TickValue)
//===================================================================

double CalcLotByATR(double slDist)
{
   double balance   = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskAmt   = balance * InpRiskPercent / 100.0;

   double tickSz    = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double tickVal   = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double point     = SymbolInfoDouble(_Symbol, SYMBOL_POINT);

   if(tickSz <= 0 || tickVal <= 0 || point <= 0 || slDist <= 0)
      return InpMinLotSize;

   double slPoints   = slDist / point;
   double valPerPt   = (tickVal / tickSz) * point;
   if(valPerPt <= 0) return InpMinLotSize;

   double lot = riskAmt / (slPoints * valPerPt);
   return NormalizeLot(lot);
}

//===================================================================
//  SWING HIGH / LOW for SL
//===================================================================

double GetSwingLevel(ENUM_ORDER_TYPE type, int bars)
{
   double level = 0;
   if(type == ORDER_TYPE_BUY)
   {
      // Find lowest low in last N bars (use as SL for long)
      level = iLow(_Symbol, PERIOD_CURRENT, 1);
      for(int i = 2; i <= bars; i++)
      {
         double lo = iLow(_Symbol, PERIOD_CURRENT, i);
         if(lo < level) level = lo;
      }
      level -= gATRValue * 0.2; // Small buffer below swing low
   }
   else
   {
      // Find highest high in last N bars (SL for short)
      level = iHigh(_Symbol, PERIOD_CURRENT, 1);
      for(int i = 2; i <= bars; i++)
      {
         double hi = iHigh(_Symbol, PERIOD_CURRENT, i);
         if(hi > level) level = hi;
      }
      level += gATRValue * 0.2; // Small buffer above swing high
   }
   return NormalizeDouble(level, (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS));
}

//===================================================================
//  HELPERS
//===================================================================

bool RefreshAllIndicators()
{
   if(CopyBuffer(hTrendEMAFast, 0, 0, 4, bTrendFast)  < 4) return false;
   if(CopyBuffer(hTrendEMASlow, 0, 0, 4, bTrendSlow)  < 4) return false;
   if(CopyBuffer(hEntryEMAFast, 0, 0, 4, bEntryFast)  < 4) return false;
   if(CopyBuffer(hEntryEMASlow, 0, 0, 4, bEntrySlow)  < 4) return false;
   if(CopyBuffer(hMACD, 0, 0, 4, bMACDMain)           < 4) return false;
   if(CopyBuffer(hMACD, 1, 0, 4, bMACDSignal)         < 4) return false;
   // MT5 iMACD has only 2 buffers (0=MACD, 1=Signal) — no buffer 2
   // Calculate histogram manually: MACD line - Signal line
   ArrayResize(bMACDHist, 4);
   for(int i = 0; i < 4; i++)
      bMACDHist[i] = bMACDMain[i] - bMACDSignal[i];
   if(CopyBuffer(hBB,   1, 0, 4, bBBUpper)            < 4) return false;
   if(CopyBuffer(hBB,   2, 0, 4, bBBLower)            < 4) return false;
   if(CopyBuffer(hBB,   0, 0, 4, bBBMid)              < 4) return false;
   if(CopyBuffer(hSAR,  0, 0, 4, bSAR)                < 4) return false;
   if(CopyBuffer(hATR,  0, 0, 4, bATR)                < 4) return false;
   if(InpUseRSI && hRSI != INVALID_HANDLE)
   {
      if(CopyBuffer(hRSI, 0, 0, 4, bRSI)             < 4) return false;
   }
   return true;
}

void CloseAllPositions()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(!posInfo.SelectByIndex(i))          continue;
      if(posInfo.Symbol() != _Symbol)        continue;
      if(posInfo.Magic()  != InpMagicNumber) continue;
      trade.PositionClose(posInfo.Ticket());
   }
}

int CountPositions(ENUM_POSITION_TYPE posType)
{
   int n = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(!posInfo.SelectByIndex(i))          continue;
      if(posInfo.Symbol() != _Symbol)        continue;
      if(posInfo.Magic()  != InpMagicNumber) continue;
      if(posInfo.PositionType() == posType)  n++;
   }
   return n;
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

ENUM_ORDER_TYPE_FILLING GetSymbolFilling()
{
   uint filling = (uint)SymbolInfoInteger(_Symbol, SYMBOL_FILLING_FLAGS);
   if((filling & SYMBOL_FILLING_FOK)    != 0) return ORDER_FILLING_FOK;
   if((filling & SYMBOL_FILLING_IOC)    != 0) return ORDER_FILLING_IOC;
   return ORDER_FILLING_RETURN;
}

bool CheckSpread()
{
   int spread = (int)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   if(spread > InpMaxSpread)
   {
      if(InpDebugLog)
         PrintFormat("[%s DEBUG] Spread blocked: current=%d > max=%d", InpBotName, spread, InpMaxSpread);
      return false;
   }
   return true;
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
         PrintFormat("[%s RISK] DD=%.2f%% > limit=%.2f%% — Trading paused",
                     InpBotName, dd, InpMaxDDPercent);
         lastWarn = TimeCurrent();
      }
      return true;
   }
   return false;
}

string TrendName(int t)
{
   if(t ==  1) return "UP";
   if(t == -1) return "DOWN";
   return "SIDE";
}

//===================================================================
//  ON TRADE — Log deals
//===================================================================

void OnTradeTransaction(const MqlTradeTransaction& trans,
                        const MqlTradeRequest&     request,
                        const MqlTradeResult&      result)
{
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD) return;
   if(!HistoryDealSelect(trans.deal))           return;

   long entry = HistoryDealGetInteger(trans.deal, DEAL_ENTRY);
   if(entry == DEAL_ENTRY_OUT || entry == DEAL_ENTRY_OUT_BY)
   {
      double profit = HistoryDealGetDouble(trans.deal, DEAL_PROFIT);
      double vol    = HistoryDealGetDouble(trans.deal, DEAL_VOLUME);
      double px     = HistoryDealGetDouble(trans.deal, DEAL_PRICE);
      PrintFormat("[%s CLOSED] Vol:%.2f | Price:%.5f | Profit:%+.2f | Balance:%.2f",
                  InpBotName, vol, px, profit, AccountInfoDouble(ACCOUNT_BALANCE));
   }
}
//+------------------------------------------------------------------+
