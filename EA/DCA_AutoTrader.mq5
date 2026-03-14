//+------------------------------------------------------------------+
//|                                              DCA_AutoTrader.mq5  |
//|                          DCA Auto Trading EA for Cent Account    |
//|                          Symbols: BTCUSD, XAUUSD                 |
//|                          Timeframe: M15 / H1                     |
//+------------------------------------------------------------------+
#property copyright "DCA Auto Trader"
#property version   "1.00"
#property description "DCA Auto Trading EA for BTCUSD & XAUUSD (Cent Account)"

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Indicators\Trend.mqh>

//--- Input Parameters
input group "=== General Settings ==="
input string   InpMagicComment   = "DCA_EA";          // Magic Comment
input int      InpMagicNumber    = 202400;             // Magic Number
input bool     InpCentAccount    = true;               // Cent Account Mode

input group "=== Entry Signal Settings ==="
input int      InpFastMA         = 20;                 // Fast MA Period
input int      InpSlowMA         = 50;                 // Slow MA Period
input int      InpRSIPeriod      = 14;                 // RSI Period
input double   InpRSIOverbought  = 70.0;               // RSI Overbought Level
input double   InpRSIOversold    = 30.0;               // RSI Oversold Level
input ENUM_MA_METHOD InpMAMethod = MODE_EMA;           // MA Method
input ENUM_APPLIED_PRICE InpMAPrice = PRICE_CLOSE;     // MA Applied Price

input group "=== Trade Settings ==="
input double   InpLotSize        = 0.01;               // Initial Lot Size
input double   InpMaxLotSize     = 0.5;                // Maximum Lot Size
input double   InpTakeProfitPct  = 2.0;                // Take Profit % of entry price
input double   InpStopLossPct    = 5.0;                // Stop Loss % from first entry
input bool     InpUseTrailing    = true;               // Use Trailing Stop
input double   InpTrailingPct    = 1.0;                // Trailing Stop %

input group "=== DCA Settings ==="
input bool     InpEnableDCA      = true;               // Enable DCA
input int      InpMaxDCALevels   = 5;                  // Max DCA Levels
input double   InpDCATriggerPct  = 1.5;                // DCA Trigger % (price drop/rise from last entry)
input double   InpDCAMultiplier  = 1.5;                // DCA Lot Multiplier (next lot = prev * multiplier)
input double   InpDCAMaxLot      = 0.1;                // Max lot per DCA level

input group "=== Risk Management ==="
input double   InpMaxDDPercent   = 20.0;               // Max Drawdown % to stop trading
input int      InpMaxSpread      = 50;                  // Max allowed spread (points)
input int      InpSlippage       = 20;                  // Slippage (points)
input bool     InpAllowBuy       = true;                // Allow Buy Orders
input bool     InpAllowSell      = true;                // Allow Sell Orders

input group "=== Session Filter ==="
input bool     InpUseSession     = false;              // Use Trading Session Filter
input int      InpSessionStart   = 2;                  // Session Start Hour (Server Time)
input int      InpSessionEnd     = 22;                 // Session End Hour (Server Time)

//--- Global Variables
CTrade         trade;
CPositionInfo  posInfo;

int            fastMAHandle, slowMAHandle, rsiHandle;
double         fastMABuffer[], slowMABuffer[], rsiBuffer[];

double         gFirstEntryPrice = 0;
int            gDCALevel        = 0;
double         gLastDCAPrice    = 0;
datetime       gLastBarTime     = 0;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   // Setup trade object
   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetDeviationInPoints(InpSlippage);
   trade.SetTypeFilling(ORDER_FILLING_IOC);

   // Validate symbol
   string sym = Symbol();
   if(sym != "BTCUSD" && sym != "XAUUSD" &&
      sym != "BTCUSDc" && sym != "XAUUSDc" &&
      StringFind(sym, "BTC") < 0 && StringFind(sym, "XAU") < 0)
   {
      Alert("WARNING: This EA is optimized for BTCUSD and XAUUSD. Current symbol: ", sym);
   }

   // Create indicator handles
   fastMAHandle = iMA(_Symbol, PERIOD_CURRENT, InpFastMA, 0, InpMAMethod, InpMAPrice);
   slowMAHandle = iMA(_Symbol, PERIOD_CURRENT, InpSlowMA, 0, InpMAMethod, InpMAPrice);
   rsiHandle    = iRSI(_Symbol, PERIOD_CURRENT, InpRSIPeriod, InpMAPrice);

   if(fastMAHandle == INVALID_HANDLE || slowMAHandle == INVALID_HANDLE || rsiHandle == INVALID_HANDLE)
   {
      Alert("Failed to create indicator handles!");
      return(INIT_FAILED);
   }

   ArraySetAsSeries(fastMABuffer, true);
   ArraySetAsSeries(slowMABuffer, true);
   ArraySetAsSeries(rsiBuffer,    true);

   Print("DCA AutoTrader EA initialized on ", _Symbol);
   PrintFormat("Lot: %.2f | DCA Levels: %d | DCA Trigger: %.1f%%", InpLotSize, InpMaxDCALevels, InpDCATriggerPct);

   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(fastMAHandle != INVALID_HANDLE) IndicatorRelease(fastMAHandle);
   if(slowMAHandle != INVALID_HANDLE) IndicatorRelease(slowMAHandle);
   if(rsiHandle    != INVALID_HANDLE) IndicatorRelease(rsiHandle);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   // Check for new bar only
   datetime currentBar = iTime(_Symbol, PERIOD_CURRENT, 0);
   if(currentBar == gLastBarTime)
   {
      // Still manage trailing stop on every tick
      if(InpUseTrailing) ManageTrailingStop();
      return;
   }
   gLastBarTime = currentBar;

   // Spread check
   if(!CheckSpread()) return;

   // Session check
   if(InpUseSession && !IsInSession()) return;

   // Drawdown protection
   if(IsMaxDrawdown()) return;

   // Refresh indicator data
   if(!RefreshIndicators()) return;

   // Count open positions for this EA
   int buyCount  = CountPositions(POSITION_TYPE_BUY);
   int sellCount = CountPositions(POSITION_TYPE_SELL);

   // --- DCA Logic ---
   if(InpEnableDCA && (buyCount > 0 || sellCount > 0))
   {
      CheckDCA(buyCount, sellCount);
      return; // Don't open new opposite positions while DCA is active
   }

   // --- New Entry Logic ---
   if(buyCount == 0 && sellCount == 0)
   {
      gFirstEntryPrice = 0;
      gDCALevel = 0;
      gLastDCAPrice = 0;

      ENUM_ORDER_TYPE signal = GetEntrySignal();

      if(signal == ORDER_TYPE_BUY && InpAllowBuy)
      {
         double lot = NormalizeLot(InpLotSize);
         if(OpenTrade(ORDER_TYPE_BUY, lot))
         {
            gFirstEntryPrice = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
            gLastDCAPrice    = gFirstEntryPrice;
            gDCALevel        = 0;
            PrintFormat("[BUY] Entry at %.5f | Lot: %.2f", gFirstEntryPrice, lot);
         }
      }
      else if(signal == ORDER_TYPE_SELL && InpAllowSell)
      {
         double lot = NormalizeLot(InpLotSize);
         if(OpenTrade(ORDER_TYPE_SELL, lot))
         {
            gFirstEntryPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
            gLastDCAPrice    = gFirstEntryPrice;
            gDCALevel        = 0;
            PrintFormat("[SELL] Entry at %.5f | Lot: %.2f", gFirstEntryPrice, lot);
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Get entry signal from MA crossover + RSI filter                  |
//+------------------------------------------------------------------+
ENUM_ORDER_TYPE GetEntrySignal()
{
   // Need at least 3 bars
   double fastCur  = fastMABuffer[0];
   double fastPrev = fastMABuffer[1];
   double slowCur  = slowMABuffer[0];
   double slowPrev = slowMABuffer[1];
   double rsiCur   = rsiBuffer[0];

   // Bullish crossover + RSI not overbought
   bool buySignal  = (fastPrev <= slowPrev) && (fastCur > slowCur) && (rsiCur < InpRSIOverbought);
   // Bearish crossover + RSI not oversold
   bool sellSignal = (fastPrev >= slowPrev) && (fastCur < slowCur) && (rsiCur > InpRSIOversold);

   if(buySignal)  return ORDER_TYPE_BUY;
   if(sellSignal) return ORDER_TYPE_SELL;

   return (ENUM_ORDER_TYPE)-1; // No signal
}

//+------------------------------------------------------------------+
//| DCA logic - add to losing position                               |
//+------------------------------------------------------------------+
void CheckDCA(int buyCount, int sellCount)
{
   if(gDCALevel >= InpMaxDCALevels) return;
   if(gFirstEntryPrice == 0) return;

   double currentAsk = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double currentBid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double triggerDist = gLastDCAPrice * InpDCATriggerPct / 100.0;

   // BUY DCA: price dropped below last DCA price by trigger %
   if(buyCount > 0 && (gLastDCAPrice - currentAsk) >= triggerDist)
   {
      double dcaLot = NormalizeLot(InpLotSize * MathPow(InpDCAMultiplier, gDCALevel + 1));
      dcaLot = MathMin(dcaLot, InpDCAMaxLot);

      if(OpenTrade(ORDER_TYPE_BUY, dcaLot))
      {
         gDCALevel++;
         gLastDCAPrice = currentAsk;
         PrintFormat("[DCA BUY #%d] Price: %.5f | Lot: %.2f", gDCALevel, currentAsk, dcaLot);
         UpdateDCATakeProfit(POSITION_TYPE_BUY);
      }
   }

   // SELL DCA: price rose above last DCA price by trigger %
   if(sellCount > 0 && (currentBid - gLastDCAPrice) >= triggerDist)
   {
      double dcaLot = NormalizeLot(InpLotSize * MathPow(InpDCAMultiplier, gDCALevel + 1));
      dcaLot = MathMin(dcaLot, InpDCAMaxLot);

      if(OpenTrade(ORDER_TYPE_SELL, dcaLot))
      {
         gDCALevel++;
         gLastDCAPrice = currentBid;
         PrintFormat("[DCA SELL #%d] Price: %.5f | Lot: %.2f", gDCALevel, currentBid, dcaLot);
         UpdateDCATakeProfit(POSITION_TYPE_SELL);
      }
   }
}

//+------------------------------------------------------------------+
//| Update TP for all positions of same type after DCA               |
//+------------------------------------------------------------------+
void UpdateDCATakeProfit(ENUM_POSITION_TYPE posType)
{
   double totalLots  = 0;
   double weightedPrice = 0;

   // Calculate weighted average entry price
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(!posInfo.SelectByIndex(i)) continue;
      if(posInfo.Symbol() != _Symbol) continue;
      if(posInfo.Magic() != InpMagicNumber) continue;
      if(posInfo.PositionType() != posType) continue;

      totalLots      += posInfo.Volume();
      weightedPrice  += posInfo.PriceOpen() * posInfo.Volume();
   }

   if(totalLots <= 0) return;

   double avgPrice = weightedPrice / totalLots;
   double newTP    = 0;
   double newSL    = 0;
   double point    = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   int    digits   = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);

   if(posType == POSITION_TYPE_BUY)
   {
      newTP = NormalizeDouble(avgPrice * (1 + InpTakeProfitPct / 100.0), digits);
      newSL = (InpStopLossPct > 0) ? NormalizeDouble(gFirstEntryPrice * (1 - InpStopLossPct / 100.0), digits) : 0;
   }
   else
   {
      newTP = NormalizeDouble(avgPrice * (1 - InpTakeProfitPct / 100.0), digits);
      newSL = (InpStopLossPct > 0) ? NormalizeDouble(gFirstEntryPrice * (1 + InpStopLossPct / 100.0), digits) : 0;
   }

   // Modify all positions with new TP/SL
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(!posInfo.SelectByIndex(i)) continue;
      if(posInfo.Symbol() != _Symbol) continue;
      if(posInfo.Magic() != InpMagicNumber) continue;
      if(posInfo.PositionType() != posType) continue;

      trade.PositionModify(posInfo.Ticket(), newSL, newTP);
   }

   PrintFormat("[UPDATE TP] Avg: %.5f | TP: %.5f | SL: %.5f", avgPrice, newTP, newSL);
}

//+------------------------------------------------------------------+
//| Manage trailing stop on all open positions                       |
//+------------------------------------------------------------------+
void ManageTrailingStop()
{
   if(!InpUseTrailing) return;

   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(!posInfo.SelectByIndex(i)) continue;
      if(posInfo.Symbol() != _Symbol) continue;
      if(posInfo.Magic() != InpMagicNumber) continue;

      double currentSL = posInfo.StopLoss();
      double openPrice = posInfo.PriceOpen();
      double trailDist = openPrice * InpTrailingPct / 100.0;

      if(posInfo.PositionType() == POSITION_TYPE_BUY)
      {
         double bid     = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         double newSL   = NormalizeDouble(bid - trailDist, digits);
         if(newSL > currentSL + SymbolInfoDouble(_Symbol, SYMBOL_POINT))
            trade.PositionModify(posInfo.Ticket(), newSL, posInfo.TakeProfit());
      }
      else if(posInfo.PositionType() == POSITION_TYPE_SELL)
      {
         double ask     = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         double newSL   = NormalizeDouble(ask + trailDist, digits);
         if(newSL < currentSL - SymbolInfoDouble(_Symbol, SYMBOL_POINT) || currentSL == 0)
            trade.PositionModify(posInfo.Ticket(), newSL, posInfo.TakeProfit());
      }
   }
}

//+------------------------------------------------------------------+
//| Open a trade with TP/SL                                         |
//+------------------------------------------------------------------+
bool OpenTrade(ENUM_ORDER_TYPE type, double lot)
{
   double ask    = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid    = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   int    digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);

   double price  = (type == ORDER_TYPE_BUY) ? ask : bid;
   double tp     = 0, sl = 0;

   if(type == ORDER_TYPE_BUY)
   {
      tp = NormalizeDouble(price * (1 + InpTakeProfitPct / 100.0), digits);
      sl = (InpStopLossPct > 0) ? NormalizeDouble(price * (1 - InpStopLossPct / 100.0), digits) : 0;
   }
   else
   {
      tp = NormalizeDouble(price * (1 - InpTakeProfitPct / 100.0), digits);
      sl = (InpStopLossPct > 0) ? NormalizeDouble(price * (1 + InpStopLossPct / 100.0), digits) : 0;
   }

   bool result = false;
   if(type == ORDER_TYPE_BUY)
      result = trade.Buy(lot, _Symbol, ask, sl, tp, InpMagicComment);
   else
      result = trade.Sell(lot, _Symbol, bid, sl, tp, InpMagicComment);

   if(!result)
      PrintFormat("[ERROR] Order failed: %s | Code: %d", EnumToString(type), GetLastError());

   return result;
}

//+------------------------------------------------------------------+
//| Count open positions for this EA                                 |
//+------------------------------------------------------------------+
int CountPositions(ENUM_POSITION_TYPE posType)
{
   int count = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(!posInfo.SelectByIndex(i)) continue;
      if(posInfo.Symbol() != _Symbol) continue;
      if(posInfo.Magic() != InpMagicNumber) continue;
      if(posInfo.PositionType() == posType) count++;
   }
   return count;
}

//+------------------------------------------------------------------+
//| Refresh all indicator buffers                                    |
//+------------------------------------------------------------------+
bool RefreshIndicators()
{
   if(CopyBuffer(fastMAHandle, 0, 0, 3, fastMABuffer) < 3) return false;
   if(CopyBuffer(slowMAHandle, 0, 0, 3, slowMABuffer) < 3) return false;
   if(CopyBuffer(rsiHandle,    0, 0, 3, rsiBuffer)    < 3) return false;
   return true;
}

//+------------------------------------------------------------------+
//| Normalize lot size to broker specifications                      |
//+------------------------------------------------------------------+
double NormalizeLot(double lot)
{
   double minLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

   lot = MathMax(lot, minLot);
   lot = MathMin(lot, MathMin(maxLot, InpMaxLotSize));
   lot = NormalizeDouble(MathRound(lot / lotStep) * lotStep, 2);
   return lot;
}

//+------------------------------------------------------------------+
//| Check if spread is within acceptable range                       |
//+------------------------------------------------------------------+
bool CheckSpread()
{
   long spread = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   if(spread > InpMaxSpread)
   {
      // Silent skip - don't flood logs
      return false;
   }
   return true;
}

//+------------------------------------------------------------------+
//| Check if current time is within trading session                  |
//+------------------------------------------------------------------+
bool IsInSession()
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   return (dt.hour >= InpSessionStart && dt.hour < InpSessionEnd);
}

//+------------------------------------------------------------------+
//| Check max drawdown protection                                    |
//+------------------------------------------------------------------+
bool IsMaxDrawdown()
{
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double equity  = AccountInfoDouble(ACCOUNT_EQUITY);
   if(balance <= 0) return false;

   double ddPct = (balance - equity) / balance * 100.0;
   if(ddPct >= InpMaxDDPercent)
   {
      static datetime lastAlert = 0;
      if(TimeCurrent() - lastAlert > 300)
      {
         PrintFormat("[RISK] Max drawdown reached: %.2f%% | Equity: %.2f | Balance: %.2f",
                     ddPct, equity, balance);
         lastAlert = TimeCurrent();
      }
      return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| Trade transaction handler                                        |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction& trans,
                        const MqlTradeRequest& request,
                        const MqlTradeResult& result)
{
   if(trans.type == TRADE_TRANSACTION_DEAL_ADD)
   {
      if(trans.deal_type == DEAL_TYPE_BUY || trans.deal_type == DEAL_TYPE_SELL)
      {
         // Log filled orders
         PrintFormat("[DEAL] %s | Vol: %.2f | Price: %.5f | Profit: %.2f",
                     EnumToString(trans.deal_type), trans.volume, trans.price,
                     HistoryDealGetDouble(trans.deal, DEAL_PROFIT));
      }
   }
}
//+------------------------------------------------------------------+
