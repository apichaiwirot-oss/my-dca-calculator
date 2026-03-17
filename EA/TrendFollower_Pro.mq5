//+------------------------------------------------------------------+
//|                                          TrendFollower_Pro.mq5   |
//|                   Multi-Indicator Trend Following EA             |
//|                   BTCUSD, XAUUSD, TFEX, Forex                   |
//|                   Version 2.0 — Scalping Edition                 |
//+------------------------------------------------------------------+
//
//  STRATEGY
//  ────────
//  ซื้อ-ขายแบบ Scalping ตลอดเวลา ปิดกำไรทุก 200-500 จุดตาม ATR
//  เปิด Order ใหม่ทันทีหลัง TP hit (ทั้งฝั่ง Buy / Sell)
//
//  TREND FILTER (Higher TF)
//    EMA Fast > EMA Slow → UPTREND  → Long only
//    EMA Fast < EMA Slow → DOWNTREND → Short only
//
//  ENTRY SIGNALS (Current TF) — ต้องผ่านอย่างน้อย InpMinSignals
//    1. MACD Histogram  : > 0 = bull / < 0 = bear
//    2. Bollinger Band  : ราคาข้ามเส้นกลาง (midline cross)
//    3. Parabolic SAR   : SAR พลิกด้านใต้/บนแท่งเทียน
//
//  EXIT
//    - TP แบบ Dynamic: ATR × ratio, clamp ระหว่าง MinTP–MaxTP (200-500 pts)
//    - SL แบบ Fixed Points หรือ ATR-based
//    - Trailing Stop ตาม live ATR
//
//  RE-ENTRY
//    - หลัง TP/SL hit → เช็คสัญญาณทันทีบน next tick + cooldown
//    - ไม่รอ new bar — เข้าได้เรื่อยๆ ตลอดวัน
//
//+------------------------------------------------------------------+
#property copyright "TrendFollower Pro"
#property version   "2.00"
#property description "Scalping EA | Dynamic TP 200-500pts | EMA+MACD+BB+SAR | Tick-Based"

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>

//===================================================================
//  INPUTS
//===================================================================

input group "═══ Robot Identity ═══"
input int      InpMagicNumber     = 300100;
input string   InpBotName         = "TF_Scalp";

input group "═══ Trend Filter (Higher Timeframe) ═══"
input ENUM_TIMEFRAMES InpTrendTF  = PERIOD_H1;   // H1 สำหรับ XAUUSD
input int      InpTrendEMAFast    = 50;
input int      InpTrendEMASlow    = 200;
input bool     InpStrictTrend     = true;

input group "═══ Entry Signals ═══"
input int      InpMinSignals      = 2;            // ยืนยันอย่างน้อย 2 ใน 3
input int      InpEntryEMAFast    = 20;
input int      InpEntryEMASlow    = 50;
input int      InpMACDFast        = 12;
input int      InpMACDSlow        = 26;
input int      InpMACDSignal      = 9;
input bool     InpUseMACDHist     = true;         // true=Histogram / false=Crossover
input int      InpBBPeriod        = 20;
input double   InpBBDeviation     = 2.0;
input double   InpSARStep         = 0.02;
input double   InpSARMax          = 0.2;

input group "═══ Scalp TP/SL (Dynamic) ═══"
input int      InpTPMin           = 200;          // TP ต่ำสุด (จุด) — ตลาดสงบ
input int      InpTPMax           = 500;          // TP สูงสุด (จุด) — ตลาด volatile
input double   InpTPATRRatio      = 1.2;          // TP = ATR × ratio (clamp ระหว่าง Min-Max)
input int      InpSLPoints        = 150;          // SL คงที่ (จุด)
input int      InpCooldownSecs    = 30;           // วินาที cooldown ระหว่าง entry

input group "═══ Lot Size ═══"
input double   InpRiskPercent     = 1.0;          // Risk % ต่อ trade
input double   InpMaxLotSize      = 1.00;
input double   InpMinLotSize      = 0.01;

input group "═══ Trailing Stop ═══"
input bool     InpUseTrailing     = true;
input double   InpTrailATRMulti   = 1.5;          // Trail distance = ATR × 1.5
input double   InpTrailActivePct  = 0.5;          // เริ่ม trail เมื่อกำไร >= ATR × 0.5

input group "═══ Protection ═══"
input double   InpMaxDDPercent    = 15.0;
input int      InpMaxSpread       = 80;           // XAUUSD ~30-80 pts
input int      InpSlippage        = 30;
input int      InpMaxPositions    = 1;            // 1 position ต่อครั้ง

input group "═══ Session Filter ═══"
input bool     InpUseSession      = false;
input int      InpSessionStart    = 2;
input int      InpSessionEnd      = 22;

//===================================================================
//  GLOBALS
//===================================================================

CTrade        trade;
CPositionInfo posInfo;

int  hTrendEMAFast = INVALID_HANDLE;
int  hTrendEMASlow = INVALID_HANDLE;
int  hEntryEMAFast = INVALID_HANDLE;
int  hEntryEMASlow = INVALID_HANDLE;
int  hMACD         = INVALID_HANDLE;
int  hBB           = INVALID_HANDLE;
int  hSAR          = INVALID_HANDLE;
int  hATR          = INVALID_HANDLE;

double bTrendFast[], bTrendSlow[];
double bEntryFast[], bEntrySlow[];
double bMACDMain[], bMACDSig[], bMACDHist[];
double bBBUpper[], bBBLower[], bBBMid[];
double bSAR[], bATR[];

double   gATRValue     = 0;
datetime gLastEntry    = 0;   // cooldown timer

//===================================================================
//  INIT / DEINIT
//===================================================================

ENUM_ORDER_TYPE_FILLING GetSymbolFilling()
{
   uint filling = (uint)SymbolInfoInteger(_Symbol, SYMBOL_FILLING_MODE);
   if((filling & SYMBOL_FILLING_FOK) != 0) return ORDER_FILLING_FOK;
   if((filling & SYMBOL_FILLING_IOC) != 0) return ORDER_FILLING_IOC;
   return ORDER_FILLING_RETURN;
}

int OnInit()
{
   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetDeviationInPoints(InpSlippage);
   trade.SetTypeFilling(GetSymbolFilling());
   trade.SetAsyncMode(false);

   hTrendEMAFast = iMA(_Symbol, InpTrendTF,      InpTrendEMAFast, 0, MODE_EMA, PRICE_CLOSE);
   hTrendEMASlow = iMA(_Symbol, InpTrendTF,      InpTrendEMASlow, 0, MODE_EMA, PRICE_CLOSE);
   hEntryEMAFast = iMA(_Symbol, PERIOD_CURRENT,  InpEntryEMAFast, 0, MODE_EMA, PRICE_CLOSE);
   hEntryEMASlow = iMA(_Symbol, PERIOD_CURRENT,  InpEntryEMASlow, 0, MODE_EMA, PRICE_CLOSE);
   hMACD         = iMACD(_Symbol, PERIOD_CURRENT, InpMACDFast, InpMACDSlow, InpMACDSignal, PRICE_CLOSE);
   hBB           = iBands(_Symbol, PERIOD_CURRENT, InpBBPeriod, 0, InpBBDeviation, PRICE_CLOSE);
   hSAR          = iSAR(_Symbol, PERIOD_CURRENT,  InpSARStep, InpSARMax);
   hATR          = iATR(_Symbol, PERIOD_CURRENT,  14);

   if(hTrendEMAFast==INVALID_HANDLE || hTrendEMASlow==INVALID_HANDLE ||
      hEntryEMAFast==INVALID_HANDLE || hEntryEMASlow==INVALID_HANDLE ||
      hMACD==INVALID_HANDLE || hBB==INVALID_HANDLE ||
      hSAR==INVALID_HANDLE  || hATR==INVALID_HANDLE)
   {
      Alert(InpBotName, ": Failed to create indicator handles!");
      return INIT_FAILED;
   }

   ArraySetAsSeries(bTrendFast, true); ArraySetAsSeries(bTrendSlow, true);
   ArraySetAsSeries(bEntryFast, true); ArraySetAsSeries(bEntrySlow, true);
   ArraySetAsSeries(bMACDMain,  true); ArraySetAsSeries(bMACDSig,   true);
   ArraySetAsSeries(bMACDHist,  true);
   ArraySetAsSeries(bBBUpper,   true); ArraySetAsSeries(bBBLower,   true);
   ArraySetAsSeries(bBBMid,     true); ArraySetAsSeries(bSAR,       true);
   ArraySetAsSeries(bATR,       true);

   PrintFormat("══ %s v2.0 SCALP | %s | TrendTF:%s | TP:%d-%dpts | SL:%dpts | Cooldown:%ds ══",
               InpBotName, _Symbol, EnumToString(InpTrendTF),
               InpTPMin, InpTPMax, InpSLPoints, InpCooldownSecs);
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   int h[] = {hTrendEMAFast, hTrendEMASlow, hEntryEMAFast, hEntryEMASlow,
              hMACD, hBB, hSAR, hATR};
   for(int i = 0; i < ArraySize(h); i++)
      if(h[i] != INVALID_HANDLE) IndicatorRelease(h[i]);
}

//===================================================================
//  MAIN TICK
//===================================================================

void OnTick()
{
   // ── Trailing stop ทำงานทุก tick (ใช้ live ATR) ───────────────────
   if(InpUseTrailing) ManageTrailingStop();

   // ── Guard checks ─────────────────────────────────────────────────
   if(!CheckSpread())                  return;
   if(InpUseSession && !IsInSession()) return;
   if(IsMaxDrawdown())                 return;

   // ── Cooldown: ป้องกัน entry ถี่เกิน ──────────────────────────────
   if((int)(TimeCurrent() - gLastEntry) < InpCooldownSecs) return;

   // ── Refresh indicators ────────────────────────────────────────────
   if(!RefreshAllIndicators()) return;

   // ── Live ATR (ใช้ค่าปัจจุบัน ไม่รอ bar ใหม่) ─────────────────────
   double atrBuf[1];
   if(CopyBuffer(hATR, 0, 0, 1, atrBuf) >= 1 && atrBuf[0] > 0)
      gATRValue = atrBuf[0];
   if(gATRValue <= 0) return;

   // ── ตรวจ position ─────────────────────────────────────────────────
   int buyCount  = CountPositions(POSITION_TYPE_BUY);
   int sellCount = CountPositions(POSITION_TYPE_SELL);
   int totalPos  = buyCount + sellCount;

   if(totalPos >= InpMaxPositions) return;   // รอปิดก่อนค่อยเปิดใหม่

   // ── Trend direction ───────────────────────────────────────────────
   int trend = GetTrendDirection();
   if(trend == 0 && InpStrictTrend) return;

   // ── Entry signals ─────────────────────────────────────────────────
   int longSig = 0, shortSig = 0;
   GetEntrySignals(longSig, shortSig);

   if(trend >= 0 && longSig >= InpMinSignals && buyCount == 0)
   {
      PrintFormat("[%s] LONG signal | Trend:%s | Sig:%d | ATR:%.2f | TP~%.0fpts",
                  InpBotName, TrendName(trend), longSig, gATRValue,
                  CalcDynamicTP() / SymbolInfoDouble(_Symbol, SYMBOL_POINT));
      ExecuteScalpEntry(ORDER_TYPE_BUY);
      gLastEntry = TimeCurrent();
   }
   else if(trend <= 0 && shortSig >= InpMinSignals && sellCount == 0)
   {
      PrintFormat("[%s] SHORT signal | Trend:%s | Sig:%d | ATR:%.2f | TP~%.0fpts",
                  InpBotName, TrendName(trend), shortSig, gATRValue,
                  CalcDynamicTP() / SymbolInfoDouble(_Symbol, SYMBOL_POINT));
      ExecuteScalpEntry(ORDER_TYPE_SELL);
      gLastEntry = TimeCurrent();
   }
}

//===================================================================
//  DYNAMIC TP CALCULATION
//===================================================================

double CalcDynamicTP()
{
   double point   = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double atrPts  = (gATRValue > 0) ? gATRValue / point : InpTPMin;
   double tpPts   = atrPts * InpTPATRRatio;

   // Clamp: ไม่น้อยกว่า InpTPMin, ไม่มากกว่า InpTPMax
   tpPts = MathMax(InpTPMin, MathMin(InpTPMax, tpPts));
   return tpPts * point;
}

//===================================================================
//  EXECUTE SCALP ENTRY
//===================================================================

void ExecuteScalpEntry(ENUM_ORDER_TYPE type)
{
   double point  = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   int    digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   double ask    = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid    = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double price  = (type == ORDER_TYPE_BUY) ? ask : bid;

   double tpDist = CalcDynamicTP();
   double slDist = InpSLPoints * point;

   double sl = (type == ORDER_TYPE_BUY)
               ? NormalizeDouble(price - slDist, digits)
               : NormalizeDouble(price + slDist, digits);
   double tp = (type == ORDER_TYPE_BUY)
               ? NormalizeDouble(price + tpDist, digits)
               : NormalizeDouble(price - tpDist, digits);

   double lot = CalcLot(slDist);
   if(lot <= 0) return;

   bool ok = (type == ORDER_TYPE_BUY)
             ? trade.Buy(lot,  _Symbol, ask, sl, tp, InpBotName)
             : trade.Sell(lot, _Symbol, bid, sl, tp, InpBotName);

   if(ok)
      PrintFormat("[%s OPEN] %s | Price:%.2f | Lot:%.2f | SL:%.2f | TP:%.2f | TP:%.0fpts | SL:%dpts",
                  InpBotName, (type==ORDER_TYPE_BUY)?"BUY":"SELL",
                  price, lot, sl, tp, tpDist/point, InpSLPoints);
   else
      PrintFormat("[%s ERROR] Open failed: %d", InpBotName, GetLastError());
}

//===================================================================
//  TREND DIRECTION
//===================================================================

int GetTrendDirection()
{
   double diff = bTrendFast[1] - bTrendSlow[1];
   double atr  = gATRValue > 0 ? gATRValue : 1;
   if(MathAbs(diff) < atr * 0.1) return 0;
   return (diff > 0) ? 1 : -1;
}

//===================================================================
//  ENTRY SIGNALS (3 ตัว)
//===================================================================

void GetEntrySignals(int &longSig, int &shortSig)
{
   longSig = shortSig = 0;

   // Signal 1: MACD
   if(InpUseMACDHist)
   {
      if(bMACDHist[1] > 0) longSig++;
      if(bMACDHist[1] < 0) shortSig++;
   }
   else
   {
      if(bMACDMain[2] <= bMACDSig[2] && bMACDMain[1] > bMACDSig[1]) longSig++;
      if(bMACDMain[2] >= bMACDSig[2] && bMACDMain[1] < bMACDSig[1]) shortSig++;
   }

   // Signal 2: BB Midline Cross (บ่อยกว่าการปิดนอก Band)
   double c1 = iClose(_Symbol, PERIOD_CURRENT, 1);
   double c2 = iClose(_Symbol, PERIOD_CURRENT, 2);
   if(c2 <= bBBMid[2] && c1 > bBBMid[1]) longSig++;    // ข้ามขึ้นเหนือ mid → bull
   if(c2 >= bBBMid[2] && c1 < bBBMid[1]) shortSig++;   // ข้ามลงใต้ mid → bear

   // Signal 3: Parabolic SAR flip
   double h1 = iHigh(_Symbol, PERIOD_CURRENT, 1);
   double l1 = iLow (_Symbol, PERIOD_CURRENT, 1);
   double h2 = iHigh(_Symbol, PERIOD_CURRENT, 2);
   double l2 = iLow (_Symbol, PERIOD_CURRENT, 2);
   if(bSAR[2] > h2 && bSAR[1] < l1) longSig++;
   if(bSAR[2] < l2 && bSAR[1] > h1) shortSig++;
}

//===================================================================
//  TRAILING STOP (live ATR ทุก tick)
//===================================================================

void ManageTrailingStop()
{
   // อ่าน ATR live (ไม่รอ bar ใหม่)
   double atrBuf[1];
   if(CopyBuffer(hATR, 0, 0, 1, atrBuf) < 1) return;
   double atr = atrBuf[0];
   if(atr <= 0) return;

   int    digits     = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   double point      = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double trailDist  = atr * InpTrailATRMulti;
   double activeDist = atr * InpTrailActivePct;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(!posInfo.SelectByIndex(i)) continue;
      if(posInfo.Symbol()  != _Symbol)        continue;
      if(posInfo.Magic()   != InpMagicNumber) continue;

      double openPx = posInfo.PriceOpen();
      double curSL  = posInfo.StopLoss();
      double curTP  = posInfo.TakeProfit();

      if(posInfo.PositionType() == POSITION_TYPE_BUY)
      {
         double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         if(bid - openPx < activeDist) continue;
         double newSL = NormalizeDouble(bid - trailDist, digits);
         if(newSL > curSL + point) trade.PositionModify(posInfo.Ticket(), newSL, curTP);
      }
      else if(posInfo.PositionType() == POSITION_TYPE_SELL)
      {
         double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         if(openPx - ask < activeDist) continue;
         double newSL = NormalizeDouble(ask + trailDist, digits);
         if(curSL == 0 || newSL < curSL - point) trade.PositionModify(posInfo.Ticket(), newSL, curTP);
      }
   }
}

//===================================================================
//  LOT CALCULATION
//===================================================================

double CalcLot(double slDist)
{
   double balance  = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskAmt  = balance * InpRiskPercent / 100.0;
   double tickSz   = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double tickVal  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double point    = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   if(tickSz <= 0 || tickVal <= 0 || point <= 0 || slDist <= 0) return InpMinLotSize;
   double valPerPt = (tickVal / tickSz) * point;
   if(valPerPt <= 0) return InpMinLotSize;
   return NormalizeLot(riskAmt / (slDist / point * valPerPt));
}

double NormalizeLot(double lot)
{
   double minL = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxL = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   lot = MathMax(lot, MathMax(minL, InpMinLotSize));
   lot = MathMin(lot, MathMin(maxL, InpMaxLotSize));
   return NormalizeDouble(MathFloor(lot / step) * step, 2);
}

//===================================================================
//  INDICATOR REFRESH
//===================================================================

bool RefreshAllIndicators()
{
   if(CopyBuffer(hTrendEMAFast, 0, 0, 4, bTrendFast) < 4) return false;
   if(CopyBuffer(hTrendEMASlow, 0, 0, 4, bTrendSlow) < 4) return false;
   if(CopyBuffer(hEntryEMAFast, 0, 0, 4, bEntryFast) < 4) return false;
   if(CopyBuffer(hEntryEMASlow, 0, 0, 4, bEntrySlow) < 4) return false;
   if(CopyBuffer(hMACD, 0, 0, 4, bMACDMain) < 4)          return false;
   if(CopyBuffer(hMACD, 1, 0, 4, bMACDSig)  < 4)          return false;
   ArrayResize(bMACDHist, 4);
   for(int i = 0; i < 4; i++) bMACDHist[i] = bMACDMain[i] - bMACDSig[i];
   if(CopyBuffer(hBB, 0, 0, 4, bBBMid)   < 4) return false;
   if(CopyBuffer(hBB, 1, 0, 4, bBBUpper) < 4) return false;
   if(CopyBuffer(hBB, 2, 0, 4, bBBLower) < 4) return false;
   if(CopyBuffer(hSAR, 0, 0, 4, bSAR)    < 4) return false;
   if(CopyBuffer(hATR, 0, 0, 4, bATR)    < 4) return false;
   return true;
}

//===================================================================
//  HELPERS
//===================================================================

int CountPositions(ENUM_POSITION_TYPE posType)
{
   int n = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(!posInfo.SelectByIndex(i)) continue;
      if(posInfo.Symbol() != _Symbol)        continue;
      if(posInfo.Magic()  != InpMagicNumber) continue;
      if(posInfo.PositionType() == posType)  n++;
   }
   return n;
}

bool CheckSpread()   { return (int)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD) <= InpMaxSpread; }
string TrendName(int t) { return t == 1 ? "UP" : t == -1 ? "DOWN" : "SIDE"; }

bool IsInSession()
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   return (dt.hour >= InpSessionStart && dt.hour < InpSessionEnd);
}

bool IsMaxDrawdown()
{
   double bal = AccountInfoDouble(ACCOUNT_BALANCE);
   double eq  = AccountInfoDouble(ACCOUNT_EQUITY);
   if(bal <= 0) return false;
   double dd  = (bal - eq) / bal * 100.0;
   if(dd >= InpMaxDDPercent)
   {
      static datetime lw = 0;
      if(TimeCurrent() - lw > 300)
      {
         PrintFormat("[%s RISK] DD=%.2f%% >= %.2f%% — paused", InpBotName, dd, InpMaxDDPercent);
         lw = TimeCurrent();
      }
      return true;
   }
   return false;
}

//===================================================================
//  TRADE CLOSED LOG
//===================================================================

void OnTradeTransaction(const MqlTradeTransaction& trans,
                        const MqlTradeRequest&     request,
                        const MqlTradeResult&      result)
{
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD) return;
   if(!HistoryDealSelect(trans.deal)) return;
   long entry = HistoryDealGetInteger(trans.deal, DEAL_ENTRY);
   if(entry == DEAL_ENTRY_OUT || entry == DEAL_ENTRY_OUT_BY)
      PrintFormat("[%s CLOSED] Vol:%.2f Price:%.2f Profit:%+.2f | Bal:%.2f — รอ entry ใหม่...",
                  InpBotName,
                  HistoryDealGetDouble(trans.deal, DEAL_VOLUME),
                  HistoryDealGetDouble(trans.deal, DEAL_PRICE),
                  HistoryDealGetDouble(trans.deal, DEAL_PROFIT),
                  AccountInfoDouble(ACCOUNT_BALANCE));
}
//+------------------------------------------------------------------+
