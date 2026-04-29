//+------------------------------------------------------------------+
//|                                      AsiaRange_Breakout_EA.mq5   |
//|        Bot de Trading - Breakout Asia Range by Leo                |
//|        Logique: Breakout High/Low de session → TP2 uniquement     |
//|        Lot: 1% du capital par trade                               |
//|        Type: Expert Advisor (EA)                                  |
//+------------------------------------------------------------------+
#property copyright   "Asia Range Breakout Bot"
#property link        ""
#property version     "1.02"
#property strict
#property expert

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\AccountInfo.mqh>
#include <Trade\SymbolInfo.mqh>

//+------------------------------------------------------------------+
//| INPUT PARAMETERS                                                 |
//+------------------------------------------------------------------+

input group           "══════ Session Asia Range ══════"
input int    InpSessionStartHour   = 21;    // Heure de début
input int    InpSessionStartMin    = 45;    // Minute de début
input int    InpSessionEndHour     = 22;    // Heure de fin
input int    InpSessionEndMin      = 15;    // Minute de fin
input int    InpGMTOffset          = 0;     // Décalage GMT

input group           "══════ Breakout & TP/SL ══════"
input double InpPipSize            = 1.0;   // Taille du pip (XAUUSD=1.0)
input int    InpTP2Pips            = 16;    // TP2 distance (pips)
input bool   InpBreakoutOnClose    = true;  // Breakout sur clôture
input int    InpBreakoutBufferPips = 0;     // Buffer (pips)

input group           "══════ Gestion des Trades ══════"
input int    InpMaxTrades          = 3;     // Max trades par breakout
input int    InpReentryPips        = 2;     // Pips recul ré-entrée
input bool   InpAllowBothSides     = false; // Autoriser les 2 sens

input group           "══════ Gestion du Risque ══════"
input double InpRiskPercent        = 1.0;   // Risk % par trade
input double InpMaxLot             = 10.0;
input double InpMinLot             = 0.01;
input bool   InpUseBreakeven       = true;
input int    InpTP1Pips            = 8;     // TP1 pour breakeven

input group           "══════ Heures de Trading ══════"
input int    InpTradeStartHour     = 0;
input int    InpTradeEndHour       = 20;
input bool   InpCloseAtEndOfDay    = true;
input int    InpCloseHour          = 20;

input group           "══════ Visualisation ══════"
input bool   InpShowRangeLines     = true;
input bool   InpShowSignals        = true;
input bool   InpShowDashboard      = true;
input color  InpBuyColor           = clrDodgerBlue;
input color  InpSellColor          = clrCrimson;

input group           "══════ Général ══════"
input int    InpMagicNumber        = 202505;
input string InpComment            = "AsiaBreakout";
input int    InpMaxSpread          = 30;

//--- Globals
CTrade         g_trade;
CPositionInfo  g_pos;
CAccountInfo   g_account;
CSymbolInfo    g_symbol;

double g_sessionHigh = 0, g_sessionLow = DBL_MAX, g_sessionMid = 0;
bool   g_inSession = false, g_rangeValid = false;
bool   g_breakoutUp = false, g_breakoutDown = false;
int    g_buyCount = 0, g_sellCount = 0;
double g_lastBuyPrice = 0, g_lastSellPrice = 0;
datetime g_sessionDate = 0, g_startTime = 0, g_endTime = 0;
string g_prefix = "ASRNG_";

//+------------------------------------------------------------------+
//| Initialization                                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   g_trade.SetExpertMagicNumber(InpMagicNumber);
   g_symbol.Name(_Symbol);

   long fillMode = SymbolInfoInteger(_Symbol, SYMBOL_FILLING_MODE);
   if((fillMode & SYMBOL_FILLING_FOK) == SYMBOL_FILLING_FOK) g_trade.SetTypeFilling(ORDER_FILLING_FOK);
   else if((fillMode & SYMBOL_FILLING_IOC) == SYMBOL_FILLING_IOC) g_trade.SetTypeFilling(ORDER_FILLING_IOC);
   else g_trade.SetTypeFilling(ORDER_FILLING_RETURN);

   ResetSession();
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason) { ObjectsDeleteAll(0, g_prefix); }

void ResetSession()
{
   g_sessionHigh = 0; g_sessionLow = DBL_MAX; g_sessionMid = 0;
   g_inSession = false; g_rangeValid = false;
   g_breakoutUp = false; g_breakoutDown = false;
   g_buyCount = 0; g_sellCount = 0;
}

bool IsInSession()
{
   MqlDateTime dt; TimeCurrent(dt);
   int curr = ((dt.hour + InpGMTOffset + 24) % 24) * 100 + dt.min;
   int start = InpSessionStartHour * 100 + InpSessionStartMin;
   int end = InpSessionEndHour * 100 + InpSessionEndMin;
   return (start <= end) ? (curr >= start && curr <= end) : (curr >= start || curr <= end);
}

double GetLotSize(double sl)
{
   if(sl <= 0) return InpMinLot;
   double risk = g_account.Balance() * (InpRiskPercent / 100.0);
   g_symbol.Refresh();
   double tickV = g_symbol.TickValue(), tickS = g_symbol.TickSize(), pt = g_symbol.Point();
   if(tickV <= 0 || tickS <= 0 || pt <= 0) return InpMinLot;
   double lots = risk / (sl * (tickV / tickS * pt));
   double step = g_symbol.LotsStep();
   lots = MathFloor(lots / step) * step;
   return NormalizeDouble(MathMax(InpMinLot, MathMin(InpMaxLot, lots)), 2);
}

void UpdateVisuals()
{
   if(!InpShowRangeLines || !g_rangeValid) return;
   datetime edge = TimeCurrent() + PeriodSeconds() * 50;
   ObjectCreate(0, g_prefix+"Box", OBJ_RECTANGLE, 0, g_startTime, g_sessionHigh, g_endTime, g_sessionLow);
   ObjectSetInteger(0, g_prefix+"Box", OBJPROP_COLOR, clrRoyalBlue);
   ObjectSetInteger(0, g_prefix+"Box", OBJPROP_FILL, true);
   ObjectSetInteger(0, g_prefix+"Box", OBJPROP_BACK, true);

   ObjectCreate(0, g_prefix+"H", OBJ_TREND, 0, g_endTime, g_sessionHigh, edge, g_sessionHigh);
   ObjectSetInteger(0, g_prefix+"H", OBJPROP_COLOR, InpSellColor);
   ObjectSetInteger(0, g_prefix+"H", OBJPROP_STYLE, STYLE_DASH);

   ObjectCreate(0, g_prefix+"L", OBJ_TREND, 0, g_endTime, g_sessionLow, edge, g_sessionLow);
   ObjectSetInteger(0, g_prefix+"L", OBJPROP_COLOR, InpBuyColor);
   ObjectSetInteger(0, g_prefix+"L", OBJPROP_STYLE, STYLE_DASH);
}

void OnTick()
{
   g_symbol.Refresh();
   bool inSess = IsInSession();
   if(inSess && !g_inSession) { ResetSession(); g_startTime = TimeCurrent(); g_inSession = true; }
   if(inSess) { g_sessionHigh = MathMax(g_sessionHigh, iHigh(_Symbol, _Period, 0)); g_sessionLow = MathMin(g_sessionLow, iLow(_Symbol, _Period, 0)); }
   if(!inSess && g_inSession) { g_inSession = false; if(g_sessionHigh > g_sessionLow && g_sessionLow > 0) { g_sessionMid = (g_sessionHigh + g_sessionLow) / 2.0; g_rangeValid = true; g_endTime = TimeCurrent(); UpdateVisuals(); } }

   // Breakeven
   if(InpUseBreakeven)
   {
      for(int i=PositionsTotal()-1; i>=0; i--)
         if(g_pos.SelectByIndex(i) && g_pos.Magic()==InpMagicNumber)
         {
            double op = g_pos.PriceOpen(), sl = g_pos.StopLoss();
            if(g_pos.PositionType()==POSITION_TYPE_BUY && g_symbol.Bid() >= op + InpTP1Pips * InpPipSize)
            {
               double nsl = NormalizeDouble(op + g_symbol.Spread() * _Point, _Digits);
               if(nsl > sl) g_trade.PositionModify(g_pos.Ticket(), nsl, g_pos.TakeProfit());
            }
            if(g_pos.PositionType()==POSITION_TYPE_SELL && g_symbol.Ask() <= op - InpTP1Pips * InpPipSize)
            {
               double nsl = NormalizeDouble(op - g_symbol.Spread() * _Point, _Digits);
               if(nsl < sl || sl == 0) g_trade.PositionModify(g_pos.Ticket(), nsl, g_pos.TakeProfit());
            }
         }
   }

   // Breakout
   if(g_rangeValid && !g_inSession)
   {
      double price = iClose(_Symbol, _Period, (InpBreakoutOnClose ? 1 : 0));
      double buf = InpBreakoutBufferPips * InpPipSize;

      if(price > g_sessionHigh + buf && g_buyCount < InpMaxTrades)
      {
         if(!g_breakoutUp) { g_breakoutUp = true; g_buyCount = 0; }
         if((g_buyCount == 0 || g_symbol.Bid() <= g_lastBuyPrice - InpReentryPips * InpPipSize) && g_symbol.Spread() <= InpMaxSpread)
         {
            double sl = NormalizeDouble((g_sessionLow + g_sessionMid) / 2.0, _Digits);
            double tp = NormalizeDouble(g_sessionHigh + InpTP2Pips * InpPipSize, _Digits);
            if(g_trade.Buy(GetLotSize(g_symbol.Ask()-sl), _Symbol, g_symbol.Ask(), sl, tp, InpComment)) { g_buyCount++; g_lastBuyPrice = g_symbol.Ask(); }
         }
      }
      if(price < g_sessionLow - buf && g_sellCount < InpMaxTrades)
      {
         if(!InpAllowBothSides && g_breakoutUp) return;
         if(!g_breakoutDown) { g_breakoutDown = true; g_sellCount = 0; }
         if((g_sellCount == 0 || g_symbol.Ask() >= g_lastSellPrice + InpReentryPips * InpPipSize) && g_symbol.Spread() <= InpMaxSpread)
         {
            double sl = NormalizeDouble((g_sessionHigh + g_sessionMid) / 2.0, _Digits);
            double tp = NormalizeDouble(g_sessionLow - InpTP2Pips * InpPipSize, _Digits);
            if(g_trade.Sell(GetLotSize(sl-g_symbol.Bid()), _Symbol, g_symbol.Bid(), sl, tp, InpComment)) { g_sellCount++; g_lastSellPrice = g_symbol.Bid(); }
         }
      }
   }

   // Dashboard
   if(InpShowDashboard)
   {
      string t = "═══ ASIA BREAKOUT ═══\n";
      if(g_rangeValid) t += StringFormat("Range: %.*f - %.*f\nTrades: B:%d S:%d", _Digits, g_sessionHigh, _Digits, g_sessionLow, g_buyCount, g_sellCount);
      else t += (g_inSession ? "Scanning..." : "Waiting...");
      ObjectCreate(0, g_prefix+"Dash", OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, g_prefix+"Dash", OBJPROP_XDISTANCE, 10);
      ObjectSetInteger(0, g_prefix+"Dash", OBJPROP_YDISTANCE, 30);
      ObjectSetString(0, g_prefix+"Dash", OBJPROP_TEXT, t);
      ObjectSetInteger(0, g_prefix+"Dash", OBJPROP_COLOR, clrWhite);
   }
}
