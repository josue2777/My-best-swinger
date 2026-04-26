//+------------------------------------------------------------------+
//| ProjectName: SD HA Bot                                           |
//| Copyright 2026, CompanyName                                      |
//| http://www.companyname.net                                       |
//+------------------------------------------------------------------+
#include <Trade/Trade.mqh>

CTrade trade;

// Indicator Parameters
input group "=== Supertrend HA Settings ==="
input int InpATRPeriod = 5;
input double InpMultiplier = 1.5;

input group "=== Risk Management ==="
input double RiskPercent = 1.0; // 1% of capital
input int Default_SL_Pips = 150; // Default SL for lot calculation

input group "=== Bot Settings ==="
input int MagicNumber = 554433;
input string TradeComment = "SD HA Bot";

// Global Variables
int atrHandle = INVALID_HANDLE;
double m_pip;

struct HA_Candle
  {
   double open;
   double high;
   double low;
   double close;
  };

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
   trade.SetExpertMagicNumber(MagicNumber);

   atrHandle = iATR(_Symbol, _Period, InpATRPeriod);
   if(atrHandle == INVALID_HANDLE)
     {
      Print("Failed to create ATR handle");
      return(INIT_FAILED);
     }

   m_pip = _Point;
   if(_Digits == 3 || _Digits == 5) m_pip = _Point * 10;

   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   if(atrHandle != INVALID_HANDLE)
      IndicatorRelease(atrHandle);
  }

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
  {
   if(!IsNewBar()) return;

   HA_Candle ha[];
   if(!CalculateHA(20, ha)) return;

   double upBand[], dnBand[];
   int trend[];
   if(!CalculateSupertrend(ha, upBand, dnBand, trend)) return;

   int currentTrend = trend[0];
   int prevTrend = trend[1];

   // Signal Logic
   if(currentTrend == 1 && prevTrend == -1) // Buy Signal
     {
      ClosePositions(POSITION_TYPE_SELL);
      ExecuteTrade(POSITION_TYPE_BUY);
     }
   else if(currentTrend == -1 && prevTrend == 1) // Sell Signal
     {
      ClosePositions(POSITION_TYPE_BUY);
      ExecuteTrade(POSITION_TYPE_SELL);
     }
  }

//+------------------------------------------------------------------+
//| Calculate Heikin Ashi Candles                                    |
//+------------------------------------------------------------------+
bool CalculateHA(int count, HA_Candle &ha[])
  {
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   if(CopyRates(_Symbol, _Period, 0, count + 1, rates) < count + 1) return false;

   ArrayResize(ha, count);
   ArraySetAsSeries(ha, true);

   // First candle initialization (approximate)
   double prevOpen = (rates[count].open + rates[count].close) / 2.0;
   double prevClose = (rates[count].open + rates[count].high + rates[count].low + rates[count].close) / 4.0;

   for(int i = count - 1; i >= 0; i--)
     {
      ha[i].close = (rates[i].open + rates[i].high + rates[i].low + rates[i].close) / 4.0;
      ha[i].open = (prevOpen + prevClose) / 2.0;
      ha[i].high = MathMax(rates[i].high, MathMax(ha[i].open, ha[i].close));
      ha[i].low = MathMin(rates[i].low, MathMin(ha[i].open, ha[i].close));

      prevOpen = ha[i].open;
      prevClose = ha[i].close;
     }

   return true;
  }

//+------------------------------------------------------------------+
//| Calculate Supertrend based on HA                                 |
//+------------------------------------------------------------------+
bool CalculateSupertrend(const HA_Candle &ha[], double &up[], double &dn[], int &trend[])
  {
   int count = ArraySize(ha);
   double atr[];
   ArraySetAsSeries(atr, true);
   if(CopyBuffer(atrHandle, 0, 0, count, atr) < count) return false;

   ArrayResize(up, count);
   ArrayResize(dn, count);
   ArrayResize(trend, count);
   ArraySetAsSeries(up, true);
   ArraySetAsSeries(dn, true);
   ArraySetAsSeries(trend, true);

   for(int i = count - 2; i >= 0; i--)
     {
      double basicUp = ha[i].close - (InpMultiplier * atr[i]);
      double basicDn = ha[i].close + (InpMultiplier * atr[i]);

      up[i] = (ha[i+1].close > up[i+1]) ? MathMax(basicUp, up[i+1]) : basicUp;
      dn[i] = (ha[i+1].close < dn[i+1]) ? MathMin(basicDn, dn[i+1]) : basicDn;

      if(i == count - 2) trend[i+1] = 1;

      trend[i] = trend[i+1];
      if(trend[i+1] == -1 && ha[i].close > dn[i+1]) trend[i] = 1;
      else if(trend[i+1] == 1 && ha[i].close < up[i+1]) trend[i] = -1;
     }

   return true;
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
//| Close positions by type                                          |
//+------------------------------------------------------------------+
void ClosePositions(ENUM_POSITION_TYPE type)
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
        {
         if(PositionGetInteger(POSITION_MAGIC) == MagicNumber &&
            PositionGetString(POSITION_SYMBOL) == _Symbol &&
            PositionGetInteger(POSITION_TYPE) == type)
           {
            trade.PositionClose(ticket);
           }
        }
     }
  }

//+------------------------------------------------------------------+
//| Execute a trade                                                  |
//+------------------------------------------------------------------+
void ExecuteTrade(ENUM_POSITION_TYPE type)
  {
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double price = (type == POSITION_TYPE_BUY) ? ask : bid;

   double lots = CalculateLots();
   if(lots <= 0) return;

   double sl = 0, tp = 0;
   if(type == POSITION_TYPE_BUY)
     {
      sl = ask - Default_SL_Pips * m_pip;
      trade.Buy(lots, _Symbol, ask, sl, tp, TradeComment);
     }
   else
     {
      sl = bid + Default_SL_Pips * m_pip;
      trade.Sell(lots, _Symbol, bid, sl, tp, TradeComment);
     }
  }

//+------------------------------------------------------------------+
//| Calculate Lot Size based on Risk %                               |
//+------------------------------------------------------------------+
double CalculateLots()
  {
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskMoney = balance * RiskPercent / 100.0;

   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double volumeStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

   double slPoints = Default_SL_Pips * (m_pip / _Point);
   double moneyPerLot = (slPoints / tickSize) * tickValue;

   if(moneyPerLot == 0) return 0.01;

   double lots = MathFloor(riskMoney / (moneyPerLot * volumeStep)) * volumeStep;

   double minVol = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxVol = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);

   lots = MathMax(lots, minVol);
   lots = MathMin(lots, maxVol);

   return NormalizeDouble(lots, 2);
  }
//+------------------------------------------------------------------+
