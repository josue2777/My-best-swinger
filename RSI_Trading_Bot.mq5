//+------------------------------------------------------------------+
//| ProjectName RSI Scalping Bot                                     |
//| Copyright 2026, CompanyName                                      |
//| http://www.companyname.net                                       |
//+------------------------------------------------------------------+
#include <Trade/Trade.mqh>

CTrade trade;

// RSI Parameters
input group "=== RSI Settings ==="
input int RSI_Period = 6;
input ENUM_APPLIED_PRICE RSI_AppliedPrice = PRICE_WEIGHTED;
input double RSI_Level_High = 85.0; // Sell Zone
input double RSI_Level_Low  = 16.0; // Buy Zone

input group "=== Trade Management ==="
input int SL_Pips = 150;
input int TP_Pips = 150;
input int MinTradesPerSignal = 1;
input int MaxTradesPerSignal = 1;
input int MaxTotalTrades = 5;
input bool UseRiskManagement = false; // Yes = Use %, No = Fixed Lot
input double RiskPercent = 1.0; // Risk % per Signal (if enabled)
input double FixedLotSize = 0.1; // Fixed Lot size (if enabled)
input int MagicNumber = 987654;

enum ENUM_YES_NO
  {
   Yes = 1,
   No = 0
  };

input group "=== Signal Toggles ==="
input ENUM_YES_NO Enable_Signal_1 = Yes; // Long Wick (100 pips) in Zone
input ENUM_YES_NO Enable_Signal_2 = Yes; // RSI 91/8 + Doji
input ENUM_YES_NO Enable_Signal_3 = Yes; // Doji + Adjacent FVG (50 pips)
input ENUM_YES_NO Enable_Signal_4 = Yes; // Doji + 2 Adjacent FVGs (20 pips)
input ENUM_YES_NO Enable_Signal_5 = Yes; // Doji + FVG in last 4 bars (54 pips)
input ENUM_YES_NO Enable_Signal_6 = Yes; // RSI 91/8 + Wick (41 pips)
input ENUM_YES_NO Enable_Signal_7 = Yes; // Doji + Wick (55 pips)
input ENUM_YES_NO Enable_Signal_8 = Yes; // RSI 95/5

int rsiHandle = INVALID_HANDLE;
double m_pip;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
   trade.SetExpertMagicNumber(MagicNumber);
   MathSrand(GetTickCount());

   rsiHandle = iRSI(_Symbol, _Period, RSI_Period, RSI_AppliedPrice);
   if(rsiHandle == INVALID_HANDLE)
     {
      Print("Failed to create RSI handle");
      return(INIT_FAILED);
     }

   // Define Pip size
   m_pip = _Point;
   if(_Digits == 3 || _Digits == 5) m_pip = _Point * 10;

   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   if(rsiHandle != INVALID_HANDLE)
      IndicatorRelease(rsiHandle);
  }

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
  {
   if(!IsNewBar()) return;

   // Check if we already have trades in progress
   // "si un signal est détecté alors que des trades sont deja en cours ce signal est juste ignoré"
   if(PositionsTotalByMagic() > 0) return;

   int signal = CheckSignals(); // 1 for Buy signal, -1 for Sell signal, 0 for None

   if(signal != 0)
     {
      // Invert logic: Buy signal triggers Sell (-1), Sell signal triggers Buy (1)
      ExecuteTrades(signal * -1);
     }
  }

//+------------------------------------------------------------------+
//| Check for New Bar                                                |
//+------------------------------------------------------------------+
bool IsNewBar()
  {
   static datetime last_time = 0;
   datetime lastbar_time = iTime(_Symbol, _Period, 0);
   if(last_time != lastbar_time)
     {
      last_time = lastbar_time;
      return true;
     }
   return false;
  }

//+------------------------------------------------------------------+
//| Count positions by Magic Number                                  |
//+------------------------------------------------------------------+
int PositionsTotalByMagic()
  {
   int count = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(PositionSelectByTicket(PositionGetTicket(i)))
        {
         if(PositionGetInteger(POSITION_MAGIC) == MagicNumber && PositionGetString(POSITION_SYMBOL) == _Symbol)
            count++;
        }
     }
   return count;
  }

//+------------------------------------------------------------------+
//| Execute the trades                                               |
//+------------------------------------------------------------------+
void ExecuteTrades(int type)
  {
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   // Random trades count between Min and Max
   int numTrades = MinTradesPerSignal;
   if(MaxTradesPerSignal > MinTradesPerSignal)
      numTrades = MinTradesPerSignal + MathRand() % (MaxTradesPerSignal - MinTradesPerSignal + 1);

   double lots = 0;
   if(UseRiskManagement)
      lots = calcLots(SL_Pips, numTrades);
   else
      lots = FixedLotSize;

   if(lots <= 0) return;

   for(int i = 0; i < numTrades; i++)
     {
      if(PositionsTotalByMagic() >= MaxTotalTrades) break;

      if(type == 1) // Buy
        {
         double sl = ask - SL_Pips * m_pip;
         double tp = ask + TP_Pips * m_pip;
         trade.Buy(lots, _Symbol, ask, sl, tp, "RSI Scalp Buy");
        }
      else if(type == -1) // Sell
        {
         double sl = bid + SL_Pips * m_pip;
         double tp = bid - TP_Pips * m_pip;
         trade.Sell(lots, _Symbol, bid, sl, tp, "RSI Scalp Sell");
        }
     }
  }

//+------------------------------------------------------------------+
//| Signal Detection Logic                                           |
//+------------------------------------------------------------------+
int CheckSignals()
  {
   double rsi[];
   ArraySetAsSeries(rsi, true);
   // We check RSI of the latest COMPLETED bar (index 1)
   if(CopyBuffer(rsiHandle, 0, 1, 1, rsi) < 1) return 0;

   double lastRSI = rsi[0];
   bool inBuyZone = lastRSI <= RSI_Level_Low;
   bool inSellZone = lastRSI >= RSI_Level_High;

   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   // Copy rates for completed bars (starting from index 1)
   if(CopyRates(_Symbol, _Period, 1, 10, rates) < 10) return 0;

   // Signal 8: RSI reaches level 95 or 5
   if(Enable_Signal_8)
     {
      if(lastRSI >= 95) return -1;
      if(lastRSI <= 5) return 1;
     }

   // ALL other signals require being in the buy or sell zone
   if(inBuyZone)
     {
      // Signal 1: Lower wick >= 100 pips
      if(Enable_Signal_1 && GetLowerWickPips(rates[0]) >= 100) return 1;

      // Signal 2: RSI <= 8 + Doji
      if(Enable_Signal_2 && lastRSI <= 8 && IsDoji(rates[0])) return 1;

      // Signal 3: Doji + Adjacent FVG (50 pips)
      // "cote a cote" -> FVG is at index 1 (between 0 and 2)
      if(Enable_Signal_3 && IsDoji(rates[0]) && GetFVGPips(rates, 1, true) >= 50) return 1;

      // Signal 4: Doji + 2 FVGs (20 pips minimum each)
      if(Enable_Signal_4 && IsDoji(rates[0]) && GetFVGPips(rates, 1, true) >= 20 && GetFVGPips(rates, 2, true) >= 20) return 1;

      // Signal 5: Doji OR FVG in last 4 bars preceding it (54 pips)
      // "doji ou dans les 4 dernière bougie le précédant il y a un fvg d'au moins 54 pips"
      if(Enable_Signal_5 && IsDoji(rates[0]))
        {
         for(int i=1; i<=4; i++) if(GetFVGPips(rates, i, true) >= 54) return 1;
        }

      // Signal 6: RSI <= 8 + Lower Wick of 41 pips
      if(Enable_Signal_6 && lastRSI <= 8 && GetLowerWickPips(rates[0]) >= 41) return 1;

      // Signal 7: Doji + Lower Wick of 55 pips
      if(Enable_Signal_7 && IsDoji(rates[0]) && GetLowerWickPips(rates[0]) >= 55) return 1;
     }

   if(inSellZone)
     {
      // Signal 1: Upper wick >= 100 pips
      if(Enable_Signal_1 && GetUpperWickPips(rates[0]) >= 100) return -1;

      // Signal 2: RSI >= 91 + Doji
      if(Enable_Signal_2 && lastRSI >= 91 && IsDoji(rates[0])) return -1;

      // Signal 3: Doji + Adjacent FVG (50 pips)
      if(Enable_Signal_3 && IsDoji(rates[0]) && GetFVGPips(rates, 1, false) >= 50) return -1;

      // Signal 4: Doji + 2 FVGs (20 pips minimum each)
      if(Enable_Signal_4 && IsDoji(rates[0]) && GetFVGPips(rates, 1, false) >= 20 && GetFVGPips(rates, 2, false) >= 20) return -1;

      // Signal 5: Doji + FVG in last 4 bars (54 pips)
      if(Enable_Signal_5 && IsDoji(rates[0]))
        {
         for(int i=1; i<=4; i++) if(GetFVGPips(rates, i, false) >= 54) return -1;
        }

      // Signal 6: RSI >= 91 + Upper Wick of 41 pips
      if(Enable_Signal_6 && lastRSI >= 91 && GetUpperWickPips(rates[0]) >= 41) return -1;

      // Signal 7: Doji + Upper Wick of 55 pips
      if(Enable_Signal_7 && IsDoji(rates[0]) && GetUpperWickPips(rates[0]) >= 55) return -1;
     }

   return 0;
  }

//+------------------------------------------------------------------+
//| Calculate Lot Size based on Risk %                               |
//+------------------------------------------------------------------+
double calcLots(double slPips, int tradesCount)
  {
   if(slPips <= 0) return 0.01;

   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskMoney = balance * RiskPercent / 100.0;

   // Adjust for multiple trades per signal if needed (sharing the risk)
   if(tradesCount > 1) riskMoney = riskMoney / tradesCount;

   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double volumeStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

   // Value of 1 lot for the SL distance
   // points = pips * (m_pip / _Point)
   double slPoints = slPips * (m_pip / _Point);
   double moneyPerLot = (slPoints / tickSize) * tickValue;

   if(moneyPerLot == 0) return 0.01;

   double lots = MathFloor(riskMoney / (moneyPerLot * volumeStep)) * volumeStep;

   // Constraints
   double minVol = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxVol = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);

   lots = MathMax(lots, minVol);
   lots = MathMin(lots, maxVol);

   return NormalizeDouble(lots, 2);
  }

//+------------------------------------------------------------------+
//| Helper functions for candle analysis                             |
//+------------------------------------------------------------------+
double GetLowerWickPips(const MqlRates &rate)
  {
   double bodyLow = MathMin(rate.open, rate.close);
   return (bodyLow - rate.low) / m_pip;
  }

double GetUpperWickPips(const MqlRates &rate)
  {
   double bodyHigh = MathMax(rate.open, rate.close);
   return (rate.high - bodyHigh) / m_pip;
  }

bool IsDoji(const MqlRates &rate)
  {
   double bodySize = MathAbs(rate.open - rate.close);
   double candleSize = rate.high - rate.low;
   if(candleSize == 0) return true;
   // User likely means any Doji-like candle.
   // Usually body < 10% of total size.
   return (bodySize / candleSize) < 0.1;
  }

// Fair Value Gap (FVG)
// index i is the 'middle' candle of a 3-candle sequence
// rates[i-1] is the newer candle, rates[i+1] is the older candle
double GetFVGPips(const MqlRates &rates[], int i, bool bullish)
  {
   if(i <= 0 || i >= ArraySize(rates)-1) return 0;

   if(bullish)
     {
      // Bullish FVG: Low of (i-1) is higher than High of (i+1)
      if(rates[i-1].low > rates[i+1].high)
         return (rates[i-1].low - rates[i+1].high) / m_pip;
     }
   else
     {
      // Bearish FVG: High of (i-1) is lower than Low of (i+1)
      if(rates[i-1].high < rates[i+1].low)
         return (rates[i+1].low - rates[i-1].high) / m_pip;
     }
   return 0;
  }
//+------------------------------------------------------------------+
