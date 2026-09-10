//+------------------------------------------------------------------+
//|                     Multi-Stage Trailing Stop EA                  |
//|                  Dynamic Trailing based on Profit Gain            |
//|                        For XAUUSD Only                            |
//+------------------------------------------------------------------+
#property copyright "2026"
#property link      "https://github.com/010vermakrish"
#property version   "1.00"
#property strict

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\OrderInfo.mqh>

// ============== INPUT PARAMETERS ==============
input double   InpLotSize = 0.01;              // Lot Size
input int      InpEMA1Period = 1;              // EMA 1 Period (Fast)
input int      InpEMA7Period = 7;              // EMA 7 Period (Slow)
input int      InpMaxSpread = 30;              // Max Spread in points
input int      InpMagicNumber = 010201;        // Magic Number
input string   InpSymbol = "XAUUSD";           // Symbol (Fixed)

// ============== TRAIL STEP PARAMETERS ==============
input int      InpTrailAGain = 600;            // Trail A: Gain trigger in points (60 pips)
input int      InpTrailAGap = 400;             // Trail A: Price gap SL to Current (40 pips)

input int      InpTrailBGain = 1400;           // Trail B: Gain trigger in points (140 pips)
input int      InpTrailBGap = 500;             // Trail B: Price gap SL to Current (50 pips)

input int      InpTrailCGain = 2250;           // Trail C: Gain trigger in points (225 pips)
input int      InpTrailCGap = 700;             // Trail C: Price gap SL to Current (70 pips)

input int      InpTrailDGain = 3250;           // Trail D: Gain trigger in points
input int      InpTrailDGap = 900;             // Trail D: Price gap SL to Current

input int      InpTrailEGain = 4500;           // Trail E: Gain trigger in points
input int      InpTrailEGap = 1200;            // Trail E: Price gap SL to Current

// ============== GLOBAL VARIABLES ==============
CTrade trade;
CPositionInfo positionInfo;
int handleEMA1, handleEMA7;
double ema1Buffer[], ema7Buffer[];
bool tradeOpen = false;
double entryPrice = 0.0;
double initialSL = 0.0;
double currentSL = 0.0;
int currentTrailStage = 0;                    // 0=None, 1=TrailA, 2=TrailB, 3=TrailC, etc.

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   // Set symbol
   if(Symbol() != InpSymbol)
   {
      Print("This EA works only on " + InpSymbol);
      return INIT_FAILED;
   }

   // Initialize EMAs
   handleEMA1 = iMA(InpSymbol, PERIOD_CURRENT, InpEMA1Period, 0, MODE_EMA, PRICE_CLOSE);
   handleEMA7 = iMA(InpSymbol, PERIOD_CURRENT, InpEMA7Period, 0, MODE_EMA, PRICE_CLOSE);

   if(handleEMA1 == INVALID_HANDLE || handleEMA7 == INVALID_HANDLE)
   {
      Print("Failed to create EMA handles");
      return INIT_FAILED;
   }

   // Set up arrays
   ArraySetAsSeries(ema1Buffer, true);
   ArraySetAsSeries(ema7Buffer, true);

   Print("EA Initialized successfully on ", InpSymbol);
   return INIT_SUCCEED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(handleEMA1 != INVALID_HANDLE) IndicatorRelease(handleEMA1);
   if(handleEMA7 != INVALID_HANDLE) IndicatorRelease(handleEMA7);
   Print("EA Deinitialized");
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   // Check spread
   if(SymbolInfoInteger(InpSymbol, SYMBOL_SPREAD) > InpMaxSpread)
   {
      return; // Skip if spread too high
   }

   // Get current price
   double bid = SymbolInfoDouble(InpSymbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(InpSymbol, SYMBOL_ASK);

   // Check if trade is open
   if(positionInfo.SelectByMagic(InpSymbol, InpMagicNumber))
   {
      tradeOpen = true;
      entryPrice = positionInfo.PriceOpen();
      
      // Update trailing stop
      UpdateTrailingStop();
      
      return;
   }
   else
   {
      tradeOpen = false;
      currentTrailStage = 0;
      currentSL = 0.0;
   }

   // Entry logic: EMA crossover
   CheckEntrySignal();
}

//+------------------------------------------------------------------+
//| Check Entry Signal - EMA Crossover Logic                         |
//+------------------------------------------------------------------+
void CheckEntrySignal()
{
   // Copy EMA values
   if(CopyBuffer(handleEMA1, 0, 0, 3, ema1Buffer) < 0 || 
      CopyBuffer(handleEMA7, 0, 0, 3, ema7Buffer) < 0)
   {
      return;
   }

   double ema1Current = ema1Buffer[0];
   double ema1Previous = ema1Buffer[1];
   double ema7Current = ema7Buffer[0];
   double ema7Previous = ema7Buffer[1];

   double bid = SymbolInfoDouble(InpSymbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(InpSymbol, SYMBOL_ASK);

   // BUY Signal: EMA1 crosses above EMA7
   if(ema1Previous <= ema7Previous && ema1Current > ema7Current)
   {
      OpenBuyTrade(ask);
      return;
   }

   // SELL Signal: EMA1 crosses below EMA7
   if(ema1Previous >= ema7Previous && ema1Current < ema7Current)
   {
      OpenSellTrade(bid);
      return;
   }
}

//+------------------------------------------------------------------+
//| Open Buy Trade                                                   |
//+------------------------------------------------------------------+
void OpenBuyTrade(double entryPrice)
{
   double ask = SymbolInfoDouble(InpSymbol, SYMBOL_ASK);
   double sl = ask - (InpTrailAGap * SymbolInfoDouble(InpSymbol, SYMBOL_POINT));

   MqlTradeRequest request = {};
   MqlTradeResult result = {};

   request.action = TRADE_ACTION_DEAL;
   request.symbol = InpSymbol;
   request.volume = InpLotSize;
   request.type = ORDER_TYPE_BUY;
   request.price = ask;
   request.sl = sl;
   request.tp = 0;
   request.magic = InpMagicNumber;
   request.comment = "Buy Trail EA";

   if(!OrderSend(request, result))
   {
      Print("Buy order failed: ", GetLastError());
      return;
   }

   Print("Buy order opened at ", ask, " SL: ", sl);
   initialSL = sl;
   currentSL = sl;
   currentTrailStage = 1; // Start with Trail A
}

//+------------------------------------------------------------------+
//| Open Sell Trade                                                  |
//+------------------------------------------------------------------+
void OpenSellTrade(double entryPrice)
{
   double bid = SymbolInfoDouble(InpSymbol, SYMBOL_BID);
   double sl = bid + (InpTrailAGap * SymbolInfoDouble(InpSymbol, SYMBOL_POINT));

   MqlTradeRequest request = {};
   MqlTradeResult result = {};

   request.action = TRADE_ACTION_DEAL;
   request.symbol = InpSymbol;
   request.volume = InpLotSize;
   request.type = ORDER_TYPE_SELL;
   request.price = bid;
   request.sl = sl;
   request.tp = 0;
   request.magic = InpMagicNumber;
   request.comment = "Sell Trail EA";

   if(!OrderSend(request, result))
   {
      Print("Sell order failed: ", GetLastError());
      return;
   }

   Print("Sell order opened at ", bid, " SL: ", sl);
   initialSL = sl;
   currentSL = sl;
   currentTrailStage = 1; // Start with Trail A
}

//+------------------------------------------------------------------+
//| Update Trailing Stop Based on Profit Gain                        |
//+------------------------------------------------------------------+
void UpdateTrailingStop()
{
   if(!positionInfo.SelectByMagic(InpSymbol, InpMagicNumber))
      return;

   double bid = SymbolInfoDouble(InpSymbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(InpSymbol, SYMBOL_ASK);
   double currentPrice = (positionInfo.PositionType() == POSITION_TYPE_BUY) ? bid : ask;
   double pointValue = SymbolInfoDouble(InpSymbol, SYMBOL_POINT);

   // Calculate gain from entry in points
   int gainPoints = 0;
   if(positionInfo.PositionType() == POSITION_TYPE_BUY)
   {
      gainPoints = (int)((currentPrice - entryPrice) / pointValue);
   }
   else
   {
      gainPoints = (int)((entryPrice - currentPrice) / pointValue);
   }

   // Check for Trail A (600 points)
   if(gainPoints >= InpTrailAGain && currentTrailStage < 1)
   {
      ApplyTrailA(currentPrice, positionInfo.PositionType());
      currentTrailStage = 1;
      Print("Trail A activated at gain: ", gainPoints, " points");
      return;
   }

   // Check for Trail B (1400 points from entry)
   if(gainPoints >= InpTrailBGain && currentTrailStage < 2)
   {
      ApplyTrailB(currentPrice, positionInfo.PositionType());
      currentTrailStage = 2;
      Print("Trail B activated at gain: ", gainPoints, " points");
      return;
   }

   // Check for Trail C (2250 points from entry)
   if(gainPoints >= InpTrailCGain && currentTrailStage < 3)
   {
      ApplyTrailC(currentPrice, positionInfo.PositionType());
      currentTrailStage = 3;
      Print("Trail C activated at gain: ", gainPoints, " points");
      return;
   }

   // Check for Trail D (3250 points from entry)
   if(gainPoints >= InpTrailDGain && currentTrailStage < 4)
   {
      ApplyTrailD(currentPrice, positionInfo.PositionType());
      currentTrailStage = 4;
      Print("Trail D activated at gain: ", gainPoints, " points");
      return;
   }

   // Check for Trail E (4500 points from entry)
   if(gainPoints >= InpTrailEGain && currentTrailStage < 5)
   {
      ApplyTrailE(currentPrice, positionInfo.PositionType());
      currentTrailStage = 5;
      Print("Trail E activated at gain: ", gainPoints, " points");
      return;
   }
}

//+------------------------------------------------------------------+
//| Apply Trail A - BUY                                              |
//+------------------------------------------------------------------+
void ApplyTrailA(double currentPrice, ENUM_POSITION_TYPE posType)
{
   double pointValue = SymbolInfoDouble(InpSymbol, SYMBOL_POINT);
   double newSL = 0.0;

   if(posType == POSITION_TYPE_BUY)
   {
      newSL = currentPrice - (InpTrailAGap * pointValue);
      if(newSL > currentSL)
      {
         ModifyStopLoss(newSL);
         currentSL = newSL;
      }
   }
   else // SELL
   {
      newSL = currentPrice + (InpTrailAGap * pointValue);
      if(newSL < currentSL)
      {
         ModifyStopLoss(newSL);
         currentSL = newSL;
      }
   }
}

//+------------------------------------------------------------------+
//| Apply Trail B                                                    |
//+------------------------------------------------------------------+
void ApplyTrailB(double currentPrice, ENUM_POSITION_TYPE posType)
{
   double pointValue = SymbolInfoDouble(InpSymbol, SYMBOL_POINT);
   double newSL = 0.0;

   if(posType == POSITION_TYPE_BUY)
   {
      newSL = currentPrice - (InpTrailBGap * pointValue);
      if(newSL > currentSL)
      {
         ModifyStopLoss(newSL);
         currentSL = newSL;
      }
   }
   else // SELL
   {
      newSL = currentPrice + (InpTrailBGap * pointValue);
      if(newSL < currentSL)
      {
         ModifyStopLoss(newSL);
         currentSL = newSL;
      }
   }
}

//+------------------------------------------------------------------+
//| Apply Trail C                                                    |
//+------------------------------------------------------------------+
void ApplyTrailC(double currentPrice, ENUM_POSITION_TYPE posType)
{
   double pointValue = SymbolInfoDouble(InpSymbol, SYMBOL_POINT);
   double newSL = 0.0;

   if(posType == POSITION_TYPE_BUY)
   {
      newSL = currentPrice - (InpTrailCGap * pointValue);
      if(newSL > currentSL)
      {
         ModifyStopLoss(newSL);
         currentSL = newSL;
      }
   }
   else // SELL
   {
      newSL = currentPrice + (InpTrailCGap * pointValue);
      if(newSL < currentSL)
      {
         ModifyStopLoss(newSL);
         currentSL = newSL;
      }
   }
}

//+------------------------------------------------------------------+
//| Apply Trail D                                                    |
//+------------------------------------------------------------------+
void ApplyTrailD(double currentPrice, ENUM_POSITION_TYPE posType)
{
   double pointValue = SymbolInfoDouble(InpSymbol, SYMBOL_POINT);
   double newSL = 0.0;

   if(posType == POSITION_TYPE_BUY)
   {
      newSL = currentPrice - (InpTrailDGap * pointValue);
      if(newSL > currentSL)
      {
         ModifyStopLoss(newSL);
         currentSL = newSL;
      }
   }
   else // SELL
   {
      newSL = currentPrice + (InpTrailDGap * pointValue);
      if(newSL < currentSL)
      {
         ModifyStopLoss(newSL);
         currentSL = newSL;
      }
   }
}

//+------------------------------------------------------------------+
//| Apply Trail E                                                    |
//+------------------------------------------------------------------+
void ApplyTrailE(double currentPrice, ENUM_POSITION_TYPE posType)
{
   double pointValue = SymbolInfoDouble(InpSymbol, SYMBOL_POINT);
   double newSL = 0.0;

   if(posType == POSITION_TYPE_BUY)
   {
      newSL = currentPrice - (InpTrailEGap * pointValue);
      if(newSL > currentSL)
      {
         ModifyStopLoss(newSL);
         currentSL = newSL;
      }
   }
   else // SELL
   {
      newSL = currentPrice + (InpTrailEGap * pointValue);
      if(newSL < currentSL)
      {
         ModifyStopLoss(newSL);
         currentSL = newSL;
      }
   }
}

//+------------------------------------------------------------------+
//| Modify Stop Loss                                                 |
//+------------------------------------------------------------------+
void ModifyStopLoss(double newSL)
{
   if(!positionInfo.SelectByMagic(InpSymbol, InpMagicNumber))
      return;

   MqlTradeRequest request = {};
   MqlTradeResult result = {};

   request.action = TRADE_ACTION_SLTP;
   request.position = positionInfo.Ticket();
   request.sl = newSL;
   request.tp = positionInfo.TakeProfit();

   if(!OrderSend(request, result))
   {
      Print("Failed to modify SL: ", GetLastError());
      return;
   }

   Print("SL modified to: ", newSL);
}

//+------------------------------------------------------------------+
//| END OF EA                                                        |
//+------------------------------------------------------------------+
