//+------------------------------------------------------------------+
//|                                              ScalpBot_Pro.mq5    |
//|                           Pure Scalping EA — XAUUSD / Forex      |
//|                           Version 1.0                            |
//+------------------------------------------------------------------+
//
//  STRATEGY (Simple & Fast)
//  ─────────────────────────
//  Chart   : M5 หรือ M15
//  Entry   : EMA Fast ตัด EMA Slow (crossover) + RSI ยืนยัน
//  Trend   : EMA บน Higher TF กรองทิศทาง (ปิดได้)
//  TP      : Fixed จุด (200 pts default)
//  SL      : Fixed จุด (100 pts default)
//  Re-entry: ทันทีหลัง TP/SL hit + cooldown timer
//
//  XAUUSD 1 point = 0.01 USD
//  200 pts = $2 movement → กำไร $200/lot ต่อ trade
//
//+------------------------------------------------------------------+
#property copyright "ScalpBot Pro"
#property version   "1.00"
#property description "Pure Scalp EA | EMA Cross + RSI | Fixed TP/SL | Auto Re-entry"

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>

//===================================================================
//  INPUTS
//===================================================================

input group "═══ Identity ═══"
input int    InpMagic        = 500100;
input string InpName         = "ScalpBot";

input group "═══ Entry Signal (Current Chart TF) ═══"
input int    InpEMAFast      = 5;       // EMA เร็ว (crossover entry)
input int    InpEMASlow      = 20;      // EMA ช้า
input int    InpRSIPeriod    = 7;       // RSI Period
input int    InpRSIBull      = 52;      // RSI > ค่านี้ = อนุญาต Long
input int    InpRSIBear      = 48;      // RSI < ค่านี้ = อนุญาต Short

input group "═══ Trend Filter (Higher TF) ═══"
input bool            InpUseTrend  = true;         // เปิด/ปิด trend filter
input ENUM_TIMEFRAMES InpTrendTF   = PERIOD_H1;    // H1 สำหรับ XAUUSD
input int             InpTrendEMA  = 50;           // EMA trend (ราคา > EMA = bullish)

input group "═══ TP / SL (Fixed Points) ═══"
input int    InpTP           = 200;     // Take Profit (จุด)
input int    InpSL           = 100;     // Stop Loss (จุด)
input int    InpCooldown     = 60;      // วินาที รอก่อน re-entry

input group "═══ Lot Size ═══"
input bool   InpAutoLot      = true;    // Auto lot ตาม risk%
input double InpRiskPct      = 0.5;    // Risk % ต่อ trade (Auto)
input double InpFixedLot     = 0.01;   // Fixed lot (ถ้า AutoLot=false)
input double InpMaxLot       = 2.00;
input double InpMinLot       = 0.01;

input group "═══ Trailing Stop ═══"
input bool   InpTrail        = true;    // เปิด Trailing
input int    InpTrailStart   = 100;     // เริ่ม trail เมื่อกำไร >= จุดนี้
input int    InpTrailDist    = 80;      // ระยะ trail (จุด)

input group "═══ Protection ═══"
input double InpMaxDD        = 15.0;   // หยุด trade เมื่อ DD >= %
input int    InpMaxSpread    = 80;     // Max spread ที่ยอมรับ (จุด)
input int    InpSlippage     = 20;
input int    InpMaxPos       = 1;      // Max positions พร้อมกัน

input group "═══ Session ═══"
input bool   InpSession      = false;
input int    InpSessStart    = 2;
input int    InpSessEnd      = 22;

//===================================================================
//  GLOBALS
//===================================================================

CTrade        trade;
CPositionInfo pos;

int  hFast = INVALID_HANDLE;   // EMA Fast (entry TF)
int  hSlow = INVALID_HANDLE;   // EMA Slow (entry TF)
int  hRSI  = INVALID_HANDLE;   // RSI
int  hTrnd = INVALID_HANDLE;   // EMA Trend (higher TF)

double bFast[], bSlow[], bRSI[], bTrnd[];

datetime gLastEntry = 0;

//===================================================================
//  INIT
//===================================================================

ENUM_ORDER_TYPE_FILLING GetFilling()
{
   uint f = (uint)SymbolInfoInteger(_Symbol, SYMBOL_FILLING_MODE);
   if((f & SYMBOL_FILLING_FOK) != 0) return ORDER_FILLING_FOK;
   if((f & SYMBOL_FILLING_IOC) != 0) return ORDER_FILLING_IOC;
   return ORDER_FILLING_RETURN;
}

int OnInit()
{
   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints(InpSlippage);
   trade.SetTypeFilling(GetFilling());
   trade.SetAsyncMode(false);

   hFast = iMA(_Symbol, PERIOD_CURRENT, InpEMAFast, 0, MODE_EMA, PRICE_CLOSE);
   hSlow = iMA(_Symbol, PERIOD_CURRENT, InpEMASlow, 0, MODE_EMA, PRICE_CLOSE);
   hRSI  = iRSI(_Symbol, PERIOD_CURRENT, InpRSIPeriod, PRICE_CLOSE);
   hTrnd = iMA(_Symbol, InpTrendTF,     InpTrendEMA, 0, MODE_EMA, PRICE_CLOSE);

   if(hFast==INVALID_HANDLE || hSlow==INVALID_HANDLE ||
      hRSI ==INVALID_HANDLE || hTrnd==INVALID_HANDLE)
      { Alert(InpName,": Indicator init failed!"); return INIT_FAILED; }

   ArraySetAsSeries(bFast, true);
   ArraySetAsSeries(bSlow, true);
   ArraySetAsSeries(bRSI,  true);
   ArraySetAsSeries(bTrnd, true);

   PrintFormat("══ %s v1.0 | %s %s | EMA%d/%d | RSI%d | TP:%dpts SL:%dpts | Risk:%.1f%% ══",
               InpName, _Symbol, EnumToString(PERIOD_CURRENT),
               InpEMAFast, InpEMASlow, InpRSIPeriod,
               InpTP, InpSL, InpRiskPct);
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   IndicatorRelease(hFast);
   IndicatorRelease(hSlow);
   IndicatorRelease(hRSI);
   IndicatorRelease(hTrnd);
}

//===================================================================
//  MAIN TICK
//===================================================================

void OnTick()
{
   // ── Trailing ทุก tick ──────────────────────────────────────────
   if(InpTrail) DoTrailing();

   // ── Guards ────────────────────────────────────────────────────
   if(Spread() > InpMaxSpread)                return;
   if(InpSession && !InSession())             return;
   if(IsMaxDD())                              return;
   if((int)(TimeCurrent()-gLastEntry) < InpCooldown) return;

   // ── Refresh indicators ─────────────────────────────────────────
   if(CopyBuffer(hFast,0,0,3,bFast) < 3) return;
   if(CopyBuffer(hSlow,0,0,3,bSlow) < 3) return;
   if(CopyBuffer(hRSI, 0,0,3,bRSI)  < 3) return;
   if(CopyBuffer(hTrnd,0,0,2,bTrnd) < 2) return;

   // ── ตรวจ position ──────────────────────────────────────────────
   if(CountPos() >= InpMaxPos) return;

   // ── Trend filter ───────────────────────────────────────────────
   double closeH  = iClose(_Symbol, InpTrendTF, 1);
   bool   trendUp   = !InpUseTrend || (closeH > bTrnd[1]);
   bool   trendDown = !InpUseTrend || (closeH < bTrnd[1]);

   // ── EMA Crossover (bar[2]→bar[1]) ─────────────────────────────
   bool crossUp   = (bFast[2] <= bSlow[2]) && (bFast[1] > bSlow[1]);
   bool crossDown = (bFast[2] >= bSlow[2]) && (bFast[1] < bSlow[1]);

   // ── RSI confirm ────────────────────────────────────────────────
   bool rsiBull = (bRSI[1] > InpRSIBull);
   bool rsiBear = (bRSI[1] < InpRSIBear);

   // ── Fire entry ────────────────────────────────────────────────
   if(crossUp && rsiBull && trendUp)
   {
      PrintFormat("[%s] BUY | EMA cross UP | RSI=%.1f | Trend=%s",
                  InpName, bRSI[1], trendUp?"UP":"—");
      if(OpenOrder(ORDER_TYPE_BUY))
         gLastEntry = TimeCurrent();
   }
   else if(crossDown && rsiBear && trendDown)
   {
      PrintFormat("[%s] SELL | EMA cross DOWN | RSI=%.1f | Trend=%s",
                  InpName, bRSI[1], trendDown?"DOWN":"—");
      if(OpenOrder(ORDER_TYPE_SELL))
         gLastEntry = TimeCurrent();
   }
}

//===================================================================
//  OPEN ORDER
//===================================================================

bool OpenOrder(ENUM_ORDER_TYPE type)
{
   double pt  = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   int    dg  = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   double price = (type==ORDER_TYPE_BUY) ? ask : bid;
   double tpD   = InpTP * pt;
   double slD   = InpSL * pt;

   double sl = NormalizeDouble((type==ORDER_TYPE_BUY) ? price-slD : price+slD, dg);
   double tp = NormalizeDouble((type==ORDER_TYPE_BUY) ? price+tpD : price-tpD, dg);
   double lot = GetLot(slD);

   bool ok = (type==ORDER_TYPE_BUY)
             ? trade.Buy(lot,  _Symbol, ask, sl, tp, InpName)
             : trade.Sell(lot, _Symbol, bid, sl, tp, InpName);

   if(ok)
      PrintFormat("[%s OPEN] %s | Price:%.2f | Lot:%.2f | SL:%.2f(-%dpts) | TP:%.2f(+%dpts)",
                  InpName, (type==ORDER_TYPE_BUY)?"BUY":"SELL",
                  price, lot, sl, InpSL, tp, InpTP);
   else
      PrintFormat("[%s FAIL] Error:%d | Ask:%.2f Bid:%.2f", InpName, GetLastError(), ask, bid);

   return ok;
}

//===================================================================
//  TRAILING STOP
//===================================================================

void DoTrailing()
{
   double pt  = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   int    dg  = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   double startD = InpTrailStart * pt;
   double trailD = InpTrailDist  * pt;

   for(int i = PositionsTotal()-1; i >= 0; i--)
   {
      if(!pos.SelectByIndex(i))                   continue;
      if(pos.Symbol() != _Symbol)                 continue;
      if(pos.Magic()  != InpMagic)                continue;

      double op  = pos.PriceOpen();
      double csl = pos.StopLoss();
      double ctp = pos.TakeProfit();

      if(pos.PositionType() == POSITION_TYPE_BUY)
      {
         double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         if(bid - op < startD) continue;                    // ยังไม่ถึงระยะ activate
         double nsl = NormalizeDouble(bid - trailD, dg);
         if(nsl > csl + pt)
            trade.PositionModify(pos.Ticket(), nsl, ctp);
      }
      else if(pos.PositionType() == POSITION_TYPE_SELL)
      {
         double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         if(op - ask < startD) continue;
         double nsl = NormalizeDouble(ask + trailD, dg);
         if(csl == 0 || nsl < csl - pt)
            trade.PositionModify(pos.Ticket(), nsl, ctp);
      }
   }
}

//===================================================================
//  LOT CALCULATION
//===================================================================

double GetLot(double slDist)
{
   if(!InpAutoLot) return NormLot(InpFixedLot);

   double bal    = AccountInfoDouble(ACCOUNT_BALANCE);
   double risk   = bal * InpRiskPct / 100.0;
   double tSz    = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double tVal   = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double pt     = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   if(tSz<=0 || tVal<=0 || pt<=0 || slDist<=0) return NormLot(InpFixedLot);
   double vpp    = (tVal/tSz)*pt;
   if(vpp <= 0) return NormLot(InpFixedLot);
   return NormLot(risk / (slDist/pt * vpp));
}

double NormLot(double lot)
{
   double mn = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double mx = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double st = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   lot = MathMax(lot, MathMax(mn, InpMinLot));
   lot = MathMin(lot, MathMin(mx, InpMaxLot));
   return NormalizeDouble(MathFloor(lot/st)*st, 2);
}

//===================================================================
//  HELPERS
//===================================================================

int CountPos()
{
   int n = 0;
   for(int i = PositionsTotal()-1; i >= 0; i--)
   {
      if(!pos.SelectByIndex(i))    continue;
      if(pos.Symbol() != _Symbol)  continue;
      if(pos.Magic()  != InpMagic) continue;
      n++;
   }
   return n;
}

int    Spread()   { return (int)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD); }

bool   InSession()
{
   MqlDateTime dt; TimeToStruct(TimeCurrent(), dt);
   return (dt.hour >= InpSessStart && dt.hour < InpSessEnd);
}

bool IsMaxDD()
{
   double bal = AccountInfoDouble(ACCOUNT_BALANCE);
   double eq  = AccountInfoDouble(ACCOUNT_EQUITY);
   if(bal <= 0) return false;
   double dd  = (bal-eq)/bal*100.0;
   if(dd >= InpMaxDD)
   {
      static datetime lw = 0;
      if(TimeCurrent()-lw > 300)
         { PrintFormat("[%s] DD %.1f%% — หยุด trade", InpName, dd); lw = TimeCurrent(); }
      return true;
   }
   return false;
}

//===================================================================
//  CLOSED TRADE LOG
//===================================================================

void OnTradeTransaction(const MqlTradeTransaction& trans,
                        const MqlTradeRequest& req,
                        const MqlTradeResult& res)
{
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD) return;
   if(!HistoryDealSelect(trans.deal)) return;
   long entry = HistoryDealGetInteger(trans.deal, DEAL_ENTRY);
   if(entry != DEAL_ENTRY_OUT && entry != DEAL_ENTRY_OUT_BY) return;

   double profit = HistoryDealGetDouble(trans.deal, DEAL_PROFIT);
   double bal    = AccountInfoDouble(ACCOUNT_BALANCE);
   string result = profit > 0 ? "✔ WIN" : "✘ LOSS";

   PrintFormat("[%s %s] Profit:%+.2f | Balance:%.2f | รอ entry ใหม่ใน %ds...",
               InpName, result, profit, bal, InpCooldown);
}
//+------------------------------------------------------------------+
