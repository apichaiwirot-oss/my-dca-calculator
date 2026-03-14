//+------------------------------------------------------------------+
//|                                              HedgeScalper.mq5    |
//|                   Trend Hedge Scalper EA                         |
//|                   BTCUSD | TP $200-300 | Auto Re-open            |
//|                   Version 1.0                                    |
//+------------------------------------------------------------------+
//
//  STRATEGY
//  ────────
//  1. ตรวจ Trend จาก H4 EMA200
//     Uptrend   → Main = BUY  | Hedge = SELL (lot เล็กกว่า)
//     Downtrend → Main = SELL | Hedge = BUY  (lot เล็กกว่า)
//
//  2. TP ทั้งสองฝั่ง = $200-300 USD (ราคา BTC เคลื่อน)
//
//  3. เมื่อ Order ฝั่งใดปิด TP → เปิดใหม่ทันที
//
//  4. วนซ้ำไม่หยุด (Continuous Cycle)
//
//  RISK NOTE
//  ─────────
//  ฝั่ง Hedge อาจขาดทุนถ้า Trend แรง — ระบบนี้เหมาะกับตลาด
//  ที่มีการแกว่งสองทาง ควร Backtest ก่อนใช้จริง
//+------------------------------------------------------------------+
#property copyright "HedgeScalper v1.0"
#property version   "1.00"
#property description "Trend Hedge Scalper | BTC TP $200-300 | Auto Re-open"

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>

//===================================================================
//  INPUT PARAMETERS
//===================================================================

input group "═══ Identity ═══"
input int      InpMagicMain      = 400100;     // Magic Number — Main orders
input int      InpMagicHedge     = 400200;     // Magic Number — Hedge orders
input string   InpBotName        = "HedgeSclp";// Bot Name

input group "═══ Trend Filter ═══"
input ENUM_TIMEFRAMES InpTrendTF = PERIOD_H4;  // Trend Timeframe
input int      InpTrendEMA       = 200;         // Trend EMA Period
input bool     InpFollowTrend    = true;        // Follow trend (false = always open both)

input group "═══ TP / SL Settings ═══"
input double   InpTPUSD          = 250.0;       // Take Profit in USD price movement ($200-300)
input double   InpSLUSD          = 800.0;       // Stop Loss USD (0 = no SL, rely on hedge)
input bool     InpUseHedgeSL     = true;        // Use hedge as virtual SL (close main if hedge 2×TP)

input group "═══ Lot Settings ═══"
input double   InpMainLot        = 0.01;        // Main order lot size
input double   InpHedgeLot       = 0.01;        // Hedge order lot size
input bool     InpAutoLot        = true;        // Auto lot by risk % (overrides above)
input double   InpRiskPercent    = 1.0;         // Risk % per main trade (if AutoLot=true)

input group "═══ Re-open Settings ═══"
input bool     InpReopenMain     = true;        // Re-open Main after TP
input bool     InpReopenHedge    = true;        // Re-open Hedge after TP
input int      InpReopenDelaySec = 5;           // Delay seconds before re-open
input int      InpMaxMainOrders  = 1;           // Max simultaneous Main orders
input int      InpMaxHedgeOrders = 1;           // Max simultaneous Hedge orders

input group "═══ Protection ═══"
input double   InpMaxDDPercent   = 20.0;        // Stop if drawdown exceeds %
input int      InpMaxSpread      = 200;         // Max spread (points)
input int      InpSlippage       = 50;          // Slippage (points)

input group "═══ Session ═══"
input bool     InpUseSession     = false;       // Session filter
input int      InpSessionStart   = 0;           // Start hour
input int      InpSessionEnd     = 24;          // End hour

//===================================================================
//  GLOBAL VARIABLES
//===================================================================

CTrade        trade;
CPositionInfo posInfo;

int      hTrendEMA = INVALID_HANDLE;
double   bufTrend[];

datetime gLastBar       = 0;
datetime gLastReopenMain  = 0;
datetime gLastReopenHedge = 0;
int      gTrend         = 0;   // 1=UP, -1=DOWN

//===================================================================
//  INIT
//===================================================================

int OnInit()
{
   trade.SetDeviationInPoints(InpSlippage);
   trade.SetTypeFilling(ORDER_FILLING_IOC);
   trade.SetAsyncMode(false);

   hTrendEMA = iMA(_Symbol, InpTrendTF, InpTrendEMA, 0, MODE_EMA, PRICE_CLOSE);
   if(hTrendEMA == INVALID_HANDLE)
   {
      Alert(InpBotName, ": Cannot create EMA handle!");
      return INIT_FAILED;
   }
   ArraySetAsSeries(bufTrend, true);

   PrintFormat("══ %s Ready | %s | TP:$%.0f | Main:%.2f lot | Hedge:%.2f lot ══",
               InpBotName, _Symbol, InpTPUSD, InpMainLot, InpHedgeLot);
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   if(hTrendEMA != INVALID_HANDLE) IndicatorRelease(hTrendEMA);
}

//===================================================================
//  MAIN TICK
//===================================================================

void OnTick()
{
   if(!CheckSpread())                    return;
   if(InpUseSession && !IsInSession())   return;
   if(IsMaxDrawdown())                   return;

   // Update trend on new bar
   datetime barTime = iTime(_Symbol, PERIOD_CURRENT, 0);
   if(barTime != gLastBar)
   {
      gLastBar = barTime;
      UpdateTrend();
   }

   int mainBuy   = CountOrders(InpMagicMain,  POSITION_TYPE_BUY);
   int mainSell  = CountOrders(InpMagicMain,  POSITION_TYPE_SELL);
   int hedgeBuy  = CountOrders(InpMagicHedge, POSITION_TYPE_BUY);
   int hedgeSell = CountOrders(InpMagicHedge, POSITION_TYPE_SELL);

   int totalMain  = mainBuy  + mainSell;
   int totalHedge = hedgeBuy + hedgeSell;

   // ── Initial open: no orders at all ──────────────────────────────
   if(totalMain == 0 && totalHedge == 0)
   {
      OpenInitial();
      return;
   }

   // ── Re-open Main after TP ────────────────────────────────────────
   if(InpReopenMain && totalMain < InpMaxMainOrders)
   {
      if(TimeCurrent() - gLastReopenMain >= InpReopenDelaySec)
         ReopenMain();
   }

   // ── Re-open Hedge after TP ───────────────────────────────────────
   if(InpReopenHedge && totalHedge < InpMaxHedgeOrders)
   {
      if(TimeCurrent() - gLastReopenHedge >= InpReopenDelaySec)
         ReopenHedge();
   }
}

//===================================================================
//  INITIAL OPEN — Main (trend) + Hedge (opposite)
//===================================================================

void OpenInitial()
{
   if(gTrend == 0 && InpFollowTrend) return; // Wait for trend

   ENUM_ORDER_TYPE mainType, hedgeType;

   if(InpFollowTrend)
   {
      mainType  = (gTrend == 1) ? ORDER_TYPE_BUY  : ORDER_TYPE_SELL;
      hedgeType = (gTrend == 1) ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
   }
   else
   {
      // Always start with BUY as main (no trend filter)
      mainType  = ORDER_TYPE_BUY;
      hedgeType = ORDER_TYPE_SELL;
   }

   double mainLot  = InpAutoLot ? CalcLot(InpRiskPercent) : InpMainLot;
   double hedgeLot = InpHedgeLot;

   // Open Main
   trade.SetExpertMagicNumber(InpMagicMain);
   if(OpenOrder(mainType, mainLot, InpTPUSD, InpSLUSD))
      PrintFormat("[%s] MAIN %s opened | Lot: %.2f | TP: $%.0f",
                  InpBotName, (mainType==ORDER_TYPE_BUY)?"BUY":"SELL", mainLot, InpTPUSD);

   // Open Hedge
   trade.SetExpertMagicNumber(InpMagicHedge);
   if(OpenOrder(hedgeType, hedgeLot, InpTPUSD, InpSLUSD))
      PrintFormat("[%s] HEDGE %s opened | Lot: %.2f | TP: $%.0f",
                  InpBotName, (hedgeType==ORDER_TYPE_BUY)?"BUY":"SELL", hedgeLot, InpTPUSD);
}

//===================================================================
//  RE-OPEN MAIN (same direction as current trend)
//===================================================================

void ReopenMain()
{
   ENUM_ORDER_TYPE type;

   if(InpFollowTrend && gTrend != 0)
      type = (gTrend == 1) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   else
   {
      // Reopen same direction as last closed main
      type = GetLastClosedType(InpMagicMain);
      if((int)type < 0) return;
   }

   double lot = InpAutoLot ? CalcLot(InpRiskPercent) : InpMainLot;
   trade.SetExpertMagicNumber(InpMagicMain);

   if(OpenOrder(type, lot, InpTPUSD, InpSLUSD))
   {
      gLastReopenMain = TimeCurrent();
      PrintFormat("[%s] MAIN RE-OPEN %s | Lot: %.2f | Trend: %s",
                  InpBotName, (type==ORDER_TYPE_BUY)?"BUY":"SELL",
                  lot, TrendName(gTrend));
   }
}

//===================================================================
//  RE-OPEN HEDGE (opposite of main / opposite of trend)
//===================================================================

void ReopenHedge()
{
   ENUM_ORDER_TYPE type;

   if(InpFollowTrend && gTrend != 0)
      type = (gTrend == 1) ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
   else
   {
      type = GetLastClosedType(InpMagicHedge);
      if((int)type < 0) return;
   }

   trade.SetExpertMagicNumber(InpMagicHedge);

   if(OpenOrder(type, InpHedgeLot, InpTPUSD, InpSLUSD))
   {
      gLastReopenHedge = TimeCurrent();
      PrintFormat("[%s] HEDGE RE-OPEN %s | Lot: %.2f",
                  InpBotName, (type==ORDER_TYPE_BUY)?"BUY":"SELL", InpHedgeLot);
   }
}

//===================================================================
//  OPEN ORDER — Convert USD TP/SL to price levels
//===================================================================

bool OpenOrder(ENUM_ORDER_TYPE type, double lot, double tpUSD, double slUSD)
{
   double ask    = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid    = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   int    digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);

   double price  = (type == ORDER_TYPE_BUY) ? ask : bid;

   // Convert USD movement to price distance
   // For BTCUSD: $1 move in price = $1 × lot profit
   // TP distance in price = tpUSD (since 1 lot BTC = 1 BTC)
   // For 0.01 lot: actual $ profit = price_move × 0.01
   // So price_move needed = tpUSD / lot... but we want fixed price distance
   // Use fixed price distance = tpUSD (e.g., $250 price move)
   double tpDist = tpUSD;
   double slDist = (slUSD > 0) ? slUSD : 0;

   double tp = 0, sl = 0;

   if(type == ORDER_TYPE_BUY)
   {
      tp = NormalizeDouble(price + tpDist, digits);
      sl = (slDist > 0) ? NormalizeDouble(price - slDist, digits) : 0;
   }
   else
   {
      tp = NormalizeDouble(price - tpDist, digits);
      sl = (slDist > 0) ? NormalizeDouble(price + slDist, digits) : 0;
   }

   lot = NormalizeLot(lot);

   bool ok = (type == ORDER_TYPE_BUY)
             ? trade.Buy(lot,  _Symbol, ask, sl, tp, InpBotName)
             : trade.Sell(lot, _Symbol, bid, sl, tp, InpBotName);

   if(!ok)
      PrintFormat("[%s ERROR] Open %s failed: %d | Lot: %.2f",
                  InpBotName, (type==ORDER_TYPE_BUY)?"BUY":"SELL", GetLastError(), lot);
   return ok;
}

//===================================================================
//  UPDATE TREND
//===================================================================

void UpdateTrend()
{
   if(CopyBuffer(hTrendEMA, 0, 0, 3, bufTrend) < 3) return;

   double price = iClose(_Symbol, InpTrendTF, 1);
   double ema   = bufTrend[1];

   int newTrend = (price > ema) ? 1 : -1;

   if(newTrend != gTrend)
   {
      PrintFormat("[%s] Trend: %s → %s | Price: %.2f | EMA%d: %.2f",
                  InpBotName, TrendName(gTrend), TrendName(newTrend),
                  price, InpTrendEMA, ema);
      gTrend = newTrend;
   }
}

//===================================================================
//  LOT CALCULATION
//===================================================================

double CalcLot(double riskPct)
{
   double balance  = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskAmt  = balance * riskPct / 100.0;

   // For BTC: TP distance = InpTPUSD price move
   // Profit = lot × price_move
   // To risk riskAmt on SL: lot = riskAmt / SL_distance
   double slDist = (InpSLUSD > 0) ? InpSLUSD : InpTPUSD * 2;

   double tickVal = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSz  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double point   = SymbolInfoDouble(_Symbol, SYMBOL_POINT);

   if(tickSz <= 0 || tickVal <= 0) return InpMainLot;

   double valPerPrice = tickVal / tickSz; // $ per 1 price unit per lot
   if(valPerPrice <= 0) return InpMainLot;

   double lot = riskAmt / (slDist * valPerPrice);
   return NormalizeLot(lot);
}

//===================================================================
//  GET LAST CLOSED ORDER TYPE (for re-open direction)
//===================================================================

ENUM_ORDER_TYPE GetLastClosedType(int magic)
{
   datetime latestTime = 0;
   ENUM_ORDER_TYPE lastType = (ENUM_ORDER_TYPE)-1;

   if(!HistorySelect(TimeCurrent() - 86400, TimeCurrent())) // Last 24h
      return lastType;

   for(int i = HistoryDealsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = HistoryDealGetTicket(i);
      if(HistoryDealGetInteger(ticket, DEAL_MAGIC) != magic)    continue;
      if(HistoryDealGetString(ticket, DEAL_SYMBOL) != _Symbol)  continue;
      if(HistoryDealGetInteger(ticket, DEAL_ENTRY) != DEAL_ENTRY_OUT) continue;

      datetime t = (datetime)HistoryDealGetInteger(ticket, DEAL_TIME);
      if(t > latestTime)
      {
         latestTime = t;
         long dealType = HistoryDealGetInteger(ticket, DEAL_TYPE);
         // DEAL_TYPE_SELL = closed a BUY position → reopen BUY
         lastType = (dealType == DEAL_TYPE_SELL) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
      }
   }
   return lastType;
}

//===================================================================
//  TRADE TRANSACTION (log TP hits + profit tracking)
//===================================================================

void OnTradeTransaction(const MqlTradeTransaction& trans,
                        const MqlTradeRequest&     request,
                        const MqlTradeResult&      result)
{
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD) return;
   if(!HistoryDealSelect(trans.deal))           return;

   long magic  = HistoryDealGetInteger(trans.deal, DEAL_MAGIC);
   if(magic != InpMagicMain && magic != InpMagicHedge) return;

   long entry  = HistoryDealGetInteger(trans.deal, DEAL_ENTRY);
   if(entry != DEAL_ENTRY_OUT && entry != DEAL_ENTRY_OUT_BY) return;

   double profit = HistoryDealGetDouble(trans.deal, DEAL_PROFIT);
   double vol    = HistoryDealGetDouble(trans.deal, DEAL_VOLUME);
   double px     = HistoryDealGetDouble(trans.deal, DEAL_PRICE);
   string side   = (magic == InpMagicMain) ? "MAIN" : "HEDGE";
   string result_str = (profit >= 0) ? "TP ✅" : "SL ❌";

   PrintFormat("[%s %s] %s | Vol:%.2f | Price:%.2f | Profit:%+.2f | Balance:%.2f",
               InpBotName, side, result_str, vol, px, profit,
               AccountInfoDouble(ACCOUNT_BALANCE));

   // Mark reopen time
   if(magic == InpMagicMain)  gLastReopenMain  = TimeCurrent();
   if(magic == InpMagicHedge) gLastReopenHedge = TimeCurrent();
}

//===================================================================
//  HELPERS
//===================================================================

int CountOrders(int magic, ENUM_POSITION_TYPE posType)
{
   int n = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(!posInfo.SelectByIndex(i))          continue;
      if(posInfo.Symbol() != _Symbol)        continue;
      if(posInfo.Magic()  != magic)          continue;
      if(posInfo.PositionType() == posType)  n++;
   }
   return n;
}

double NormalizeLot(double lot)
{
   double minLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   lot = MathMax(lot, minLot);
   lot = MathMin(lot, MathMin(maxLot, 0.5));
   lot = NormalizeDouble(MathFloor(lot / lotStep) * lotStep, 2);
   return lot;
}

bool CheckSpread()
{
   return ((int)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD) <= InpMaxSpread);
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
         PrintFormat("[%s RISK] DD=%.2f%% — Trading paused", InpBotName, dd);
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
   return "NONE";
}
//+------------------------------------------------------------------+
