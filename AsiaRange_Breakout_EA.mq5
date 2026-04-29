//+------------------------------------------------------------------+
//|                                      AsiaRange_Breakout_EA.mq5   |
//|        Bot de Trading - Breakout Asia Range by Leo                |
//|        Logique: Breakout High/Low de session → TP2 uniquement     |
//|        Lot: 1% du capital par trade                               |
//|        Dual Mode: Expert Advisor + Signal Indicator               |
//+------------------------------------------------------------------+
#property copyright   "Asia Range Breakout Bot"
#property link        ""
#property version     "1.00"
#property strict

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\AccountInfo.mqh>
#include <Trade\SymbolInfo.mqh>

//+------------------------------------------------------------------+
//| INPUT PARAMETERS                                                  |
//+------------------------------------------------------------------+

//--- Session Configuration (Asia Range)
input group           "══════ Session Asia Range ══════"
input int    InpSessionStartHour   = 21;    // Heure de début de la session
input int    InpSessionStartMin    = 45;    // Minute de début de la session
input int    InpSessionEndHour     = 22;    // Heure de fin de la session
input int    InpSessionEndMin      = 15;    // Minute de fin de la session
input int    InpGMTOffset          = 0;     // Décalage GMT du serveur (heures)

//--- Breakout & TP/SL Configuration
input group           "══════ Breakout & TP/SL ══════"
input double InpPipSize            = 1.0;   // Taille du pip (0.0001 forex, 1.0 XAUUSD)
input int    InpTP2Pips            = 16;    // TP2 en pips (distance depuis breakout)
input bool   InpBreakoutOnClose    = true;  // Breakout confirmé sur clôture de bougie
input int    InpBreakoutBufferPips = 0;     // Buffer de breakout en pips (0 = exact)

//--- Trade Management par Breakout
input group           "══════ Gestion des Trades par Breakout ══════"
input int    InpMinTrades          = 1;     // Nombre MINIMUM de trades par breakout
input int    InpMaxTrades          = 3;     // Nombre MAXIMUM de trades par breakout
input int    InpReentryPips        = 2;     // Pips de recul pour ré-entrée après 1er trade
input bool   InpAllowBothSides     = false; // Autoriser trades dans les 2 sens (même session)

//--- Risk Management
input group           "══════ Gestion du Risque ══════"
input double InpRiskPercent        = 1.0;   // Risk % du capital par trade
input double InpMaxLot             = 10.0;  // Lot Maximum
input double InpMinLot             = 0.01;  // Lot Minimum
input bool   InpUseBreakeven       = true;  // Déplacer SL au breakeven quand TP1 atteint
input int    InpTP1Pips            = 8;     // TP1 distance pour breakeven (pips)

//--- Trading Hours (après la session)
input group           "══════ Heures de Trading ══════"
input int    InpTradeStartHour     = 0;     // Heure début trading (après session)
input int    InpTradeEndHour       = 20;    // Heure fin trading
input bool   InpCloseAtEndOfDay    = true;  // Fermer toutes positions en fin de journée
input int    InpCloseHour          = 20;    // Heure de fermeture forcée

//--- Visuals (Indicator features)
input group           "══════ Visualisation (Indicateur) ══════"
input bool   InpShowRangeLines     = true;    // Afficher lignes du range
input bool   InpShowSignals        = true;    // Afficher flèches de signaux
input bool   InpShowDashboard      = true;    // Afficher le tableau de bord
input color  InpBuyColor           = clrDodgerBlue; // Couleur Signaux Achat
input color  InpSellColor          = clrCrimson;    // Couleur Signaux Vente
input color  InpRangeColor         = clrRoyalBlue;  // Couleur du Range

//--- General
input group           "══════ Général ══════"
input int    InpMagicNumber        = 202505;  // Magic Number
input string InpComment            = "AsiaBreakout"; // Commentaire des ordres
input bool   InpAlerts             = true;    // Alertes activées
input bool   InpPushNotif          = false;   // Push Notifications
input int    InpMaxSpread          = 30;      // Spread maximum autorisé (points)

//+------------------------------------------------------------------+
//| GLOBAL VARIABLES                                                  |
//+------------------------------------------------------------------+
CTrade         g_trade;
CPositionInfo  g_position;
CAccountInfo   g_account;
CSymbolInfo    g_symbol;

//--- Session range tracking
double g_sessionHigh      = 0;
double g_sessionLow       = DBL_MAX;
double g_sessionMidline   = 0;
bool   g_inSession        = false;
bool   g_sessionComplete  = false;
bool   g_rangeValid       = false;

//--- Breakout tracking
bool   g_breakoutUp       = false;   // Breakout vers le haut détecté
bool   g_breakoutDown     = false;   // Breakout vers le bas détecté
int    g_buyTradeCount    = 0;       // Nombre de trades BUY pour ce breakout
int    g_sellTradeCount   = 0;       // Nombre de trades SELL pour ce breakout
double g_lastBuyPrice     = 0;       // Dernier prix d'entrée BUY
double g_lastSellPrice    = 0;       // Dernier prix d'entrée SELL
datetime g_sessionDate    = 0;       // Date de la session en cours

//--- Drawing
string g_prefix = "ASRNG_";
datetime g_rangeStartTime = 0;
datetime g_rangeEndTime   = 0;

//+------------------------------------------------------------------+
//| Detect the broker's supported order filling mode                   |
//+------------------------------------------------------------------+
ENUM_ORDER_TYPE_FILLING DetectFillingType()
{
   long fillMode = SymbolInfoInteger(_Symbol, SYMBOL_FILLING_MODE);

   if((fillMode & SYMBOL_FILLING_FOK) == SYMBOL_FILLING_FOK)
      return(ORDER_FILLING_FOK);
   if((fillMode & SYMBOL_FILLING_IOC) == SYMBOL_FILLING_IOC)
      return(ORDER_FILLING_IOC);

   return(ORDER_FILLING_RETURN);
}

//+------------------------------------------------------------------+
//| Check if auto-trading is fully enabled                             |
//+------------------------------------------------------------------+
bool IsAutoTradingEnabled()
{
   if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED)) return(false);
   if(!MQLInfoInteger(MQL_TRADE_ALLOWED)) return(false);
   if(!AccountInfoInteger(ACCOUNT_TRADE_ALLOWED)) return(false);
   return(true);
}

//+------------------------------------------------------------------+
//| Expert initialization                                              |
//+------------------------------------------------------------------+
int OnInit()
{
   g_trade.SetExpertMagicNumber(InpMagicNumber);
   g_trade.SetDeviationInPoints(10);

   g_symbol.Name(_Symbol);
   g_symbol.Refresh();

   //--- Auto-detect the correct filling type
   ENUM_ORDER_TYPE_FILLING fillType = DetectFillingType();
   g_trade.SetTypeFilling(fillType);

   ResetSession();

   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization                                            |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   ObjectsDeleteAll(0, g_prefix);
}

//+------------------------------------------------------------------+
//| Reset session data for new day                                     |
//+------------------------------------------------------------------+
void ResetSession()
{
   g_sessionHigh     = 0;
   g_sessionLow      = DBL_MAX;
   g_sessionMidline  = 0;
   g_inSession       = false;
   g_sessionComplete = false;
   g_rangeValid      = false;
   g_breakoutUp      = false;
   g_breakoutDown    = false;
   g_buyTradeCount   = 0;
   g_sellTradeCount  = 0;
   g_lastBuyPrice    = 0;
   g_lastSellPrice   = 0;
}

//+------------------------------------------------------------------+
//| Check if current time is within session                            |
//+------------------------------------------------------------------+
bool IsInSession()
{
   MqlDateTime dt;
   TimeCurrent(dt);

   int hour = (dt.hour + InpGMTOffset + 24) % 24;
   int currentTime = hour * 100 + dt.min;
   int startTime   = InpSessionStartHour * 100 + InpSessionStartMin;
   int endTime     = InpSessionEndHour * 100 + InpSessionEndMin;

   if(startTime <= endTime)
      return(currentTime >= startTime && currentTime <= endTime);
   else
      return(currentTime >= startTime || currentTime <= endTime);
}

//+------------------------------------------------------------------+
//| Check if within trading hours (after session)                      |
//+------------------------------------------------------------------+
bool IsTradingTime()
{
   MqlDateTime dt;
   TimeCurrent(dt);
   int hour = (dt.hour + InpGMTOffset + 24) % 24;

   if(InpTradeStartHour < InpTradeEndHour)
      return(hour >= InpTradeStartHour && hour < InpTradeEndHour);
   else
      return(hour >= InpTradeStartHour || hour < InpTradeEndHour);
}

//+------------------------------------------------------------------+
//| Check if it's time to force close                                  |
//+------------------------------------------------------------------+
bool IsCloseTime()
{
   if(!InpCloseAtEndOfDay) return(false);

   MqlDateTime dt;
   TimeCurrent(dt);
   int hour = (dt.hour + InpGMTOffset + 24) % 24;

   return(hour >= InpCloseHour);
}

//+------------------------------------------------------------------+
//| Calculate lot size                                                 |
//+------------------------------------------------------------------+
double CalculateLotSize(double slDistance)
{
   if(slDistance <= 0) return(InpMinLot);

   double balance    = g_account.Balance();
   double riskAmount = balance * (InpRiskPercent / 100.0);

   g_symbol.Refresh();
   double tickValue  = g_symbol.TickValue();
   double tickSize   = g_symbol.TickSize();
   double point      = g_symbol.Point();

   if(tickValue <= 0 || tickSize <= 0 || point <= 0)
      return(InpMinLot);

   double pointValuePerLot = tickValue / tickSize * point;
   double lots = riskAmount / (slDistance * pointValuePerLot);

   double lotStep = g_symbol.LotsStep();
   lots = MathFloor(lots / lotStep) * lotStep;

   lots = MathMax(lots, InpMinLot);
   lots = MathMin(lots, InpMaxLot);

   return(NormalizeDouble(lots, 2));
}

//+------------------------------------------------------------------+
//| Position Counting                                                  |
//+------------------------------------------------------------------+
int CountPositions(ENUM_POSITION_TYPE type)
{
   int count = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(g_position.SelectByIndex(i))
      {
         if(g_position.Symbol() == _Symbol && g_position.Magic() == InpMagicNumber && g_position.PositionType() == type)
            count++;
      }
   }
   return(count);
}

//+------------------------------------------------------------------+
//| BREAKEVEN MANAGEMENT                                               |
//+------------------------------------------------------------------+
void ManageBreakeven()
{
   if(!InpUseBreakeven) return;
   double tp1Distance = InpTP1Pips * InpPipSize;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(!g_position.SelectByIndex(i)) continue;
      if(g_position.Symbol() != _Symbol || g_position.Magic() != InpMagicNumber) continue;

      double openPrice = g_position.PriceOpen();
      double currentSL = g_position.StopLoss();

      if(g_position.PositionType() == POSITION_TYPE_BUY)
      {
         if(g_symbol.Bid() >= openPrice + tp1Distance)
         {
            double newSL = NormalizeDouble(openPrice + g_symbol.Spread() * _Point, _Digits);
            if(newSL > currentSL) g_trade.PositionModify(g_position.Ticket(), newSL, g_position.TakeProfit());
         }
      }
      else if(g_position.PositionType() == POSITION_TYPE_SELL)
      {
         if(g_symbol.Ask() <= openPrice - tp1Distance)
         {
            double newSL = NormalizeDouble(openPrice - g_symbol.Spread() * _Point, _Digits);
            if(newSL < currentSL || currentSL == 0) g_trade.PositionModify(g_position.Ticket(), newSL, g_position.TakeProfit());
         }
      }
   }
}

//+------------------------------------------------------------------+
//| DRAW INDICATOR VISUALS                                             |
//+------------------------------------------------------------------+
void UpdateVisuals()
{
   if(!InpShowRangeLines || !g_rangeValid) return;

   datetime rightEdge = TimeCurrent() + PeriodSeconds() * 50;

   //--- Range Box
   string nameBox = g_prefix + "Box";
   ObjectCreate(0, nameBox, OBJ_RECTANGLE, 0, g_rangeStartTime, g_sessionHigh, g_rangeEndTime, g_sessionLow);
   ObjectSetInteger(0, nameBox, OBJPROP_COLOR, InpRangeColor);
   ObjectSetInteger(0, nameBox, OBJPROP_FILL, true);
   ObjectSetInteger(0, nameBox, OBJPROP_BACK, true);

   //--- Session High/Low Lines
   ObjectCreate(0, g_prefix+"High", OBJ_TREND, 0, g_rangeEndTime, g_sessionHigh, rightEdge, g_sessionHigh);
   ObjectSetInteger(0, g_prefix+"High", OBJPROP_COLOR, InpSellColor);
   ObjectSetInteger(0, g_prefix+"High", OBJPROP_STYLE, STYLE_DASH);

   ObjectCreate(0, g_prefix+"Low", OBJ_TREND, 0, g_rangeEndTime, g_sessionLow, rightEdge, g_sessionLow);
   ObjectSetInteger(0, g_prefix+"Low", OBJPROP_COLOR, InpBuyColor);
   ObjectSetInteger(0, g_prefix+"Low", OBJPROP_STYLE, STYLE_DASH);

   //--- TP2 Target Lines
   double tp2Buy  = g_sessionHigh + InpTP2Pips * InpPipSize;
   double tp2Sell = g_sessionLow - InpTP2Pips * InpPipSize;

   ObjectCreate(0, g_prefix+"TP2Buy", OBJ_TREND, 0, g_rangeEndTime, tp2Buy, rightEdge, tp2Buy);
   ObjectSetInteger(0, g_prefix+"TP2Buy", OBJPROP_COLOR, clrDodgerBlue);

   ObjectCreate(0, g_prefix+"TP2Sell", OBJ_TREND, 0, g_rangeEndTime, tp2Sell, rightEdge, tp2Sell);
   ObjectSetInteger(0, g_prefix+"TP2Sell", OBJPROP_COLOR, clrCrimson);
}

void DrawSignal(ENUM_POSITION_TYPE type, double price)
{
   if(!InpShowSignals) return;
   string name = g_prefix + "Signal_" + TimeToString(TimeCurrent());
   ObjectCreate(0, name, OBJ_ARROW, 0, TimeCurrent(), price);
   ObjectSetInteger(0, name, OBJPROP_ARROWCODE, (type == POSITION_TYPE_BUY ? 233 : 234));
   ObjectSetInteger(0, name, OBJPROP_COLOR, (type == POSITION_TYPE_BUY ? InpBuyColor : InpSellColor));
   ObjectSetInteger(0, name, OBJPROP_WIDTH, 3);
}

//+------------------------------------------------------------------+
//| EXECUTE TRADES                                                     |
//+------------------------------------------------------------------+
void OpenBuy()
{
   g_symbol.Refresh();
   double ask = g_symbol.Ask();
   double sl = NormalizeDouble((g_sessionLow + g_sessionMidline) / 2.0, _Digits);
   double tp = NormalizeDouble(g_sessionHigh + InpTP2Pips * InpPipSize, _Digits);

   double lots = CalculateLotSize(ask - sl);
   if(g_trade.Buy(lots, _Symbol, ask, sl, tp, InpComment))
   {
      g_buyTradeCount++;
      g_lastBuyPrice = ask;
      DrawSignal(POSITION_TYPE_BUY, g_sessionHigh);
   }
}

void OpenSell()
{
   g_symbol.Refresh();
   double bid = g_symbol.Bid();
   double sl = NormalizeDouble((g_sessionHigh + g_sessionMidline) / 2.0, _Digits);
   double tp = NormalizeDouble(g_sessionLow - InpTP2Pips * InpPipSize, _Digits);

   double lots = CalculateLotSize(sl - bid);
   if(g_trade.Sell(lots, _Symbol, bid, sl, tp, InpComment))
   {
      g_sellTradeCount++;
      g_lastSellPrice = bid;
      DrawSignal(POSITION_TYPE_SELL, g_sessionLow);
   }
}

//+------------------------------------------------------------------+
//| Expert tick function                                                |
//+------------------------------------------------------------------+
void OnTick()
{
   g_symbol.Refresh();
   bool inSession = IsInSession();

   //--- 1. CAPTURE RANGE
   if(inSession && !g_inSession)
   {
      ResetSession();
      g_rangeStartTime = TimeCurrent();
      g_inSession = true;
   }

   if(inSession)
   {
      g_sessionHigh = MathMax(g_sessionHigh, iHigh(_Symbol, PERIOD_CURRENT, 0));
      g_sessionLow = MathMin(g_sessionLow, iLow(_Symbol, PERIOD_CURRENT, 0));
   }

   if(!inSession && g_inSession)
   {
      g_inSession = false;
      g_sessionComplete = true;
      if(g_sessionHigh > g_sessionLow && g_sessionLow > 0)
      {
         g_sessionMidline = (g_sessionHigh + g_sessionLow) / 2.0;
         g_rangeValid = true;
         g_rangeEndTime = TimeCurrent();
         UpdateVisuals();
      }
   }

   //--- 2. TRADE MANAGEMENT
   ManageBreakeven();

   if(IsCloseTime() && CountPositions(POSITION_TYPE_BUY)+CountPositions(POSITION_TYPE_SELL) > 0)
   {
      for(int i=PositionsTotal()-1; i>=0; i--)
         if(g_position.SelectByIndex(i) && g_position.Magic()==InpMagicNumber) g_trade.PositionClose(g_position.Ticket());
   }

   //--- 3. BREAKOUT DETECTION
   if(g_rangeValid && !g_inSession && IsTradingTime())
   {
      double price = iClose(_Symbol, PERIOD_CURRENT, (InpBreakoutOnClose ? 1 : 0));
      double buffer = InpBreakoutBufferPips * InpPipSize;

      // BUY
      if(price > g_sessionHigh + buffer && g_buyTradeCount < InpMaxTrades)
      {
         if(!g_breakoutUp) { g_breakoutUp = true; g_buyTradeCount = 0; }
         bool reentry = (g_buyTradeCount == 0) || (g_symbol.Bid() <= g_lastBuyPrice - InpReentryPips * InpPipSize);
         if(reentry && CountPositions(POSITION_TYPE_BUY) < InpMaxTrades && IsAutoTradingEnabled() && g_symbol.Spread() <= InpMaxSpread) OpenBuy();
      }

      // SELL
      if(price < g_sessionLow - buffer && g_sellTradeCount < InpMaxTrades)
      {
         if(!InpAllowBothSides && g_breakoutUp) return;
         if(!g_breakoutDown) { g_breakoutDown = true; g_sellTradeCount = 0; }
         bool reentry = (g_sellTradeCount == 0) || (g_symbol.Ask() >= g_lastSellPrice + InpReentryPips * InpPipSize);
         if(reentry && CountPositions(POSITION_TYPE_SELL) < InpMaxTrades && IsAutoTradingEnabled() && g_symbol.Spread() <= InpMaxSpread) OpenSell();
      }
   }

   //--- 4. INDICATOR DASHBOARD
   if(InpShowDashboard)
   {
      string name = g_prefix + "Dashboard";
      string text = "═══ ASIA RANGE BREAKOUT ═══\n";
      if(g_rangeValid)
      {
         text += StringFormat("Range: %.*f - %.*f\n", _Digits, g_sessionHigh, _Digits, g_sessionLow);
         text += StringFormat("Signal: %s\n", (g_breakoutUp ? "UP ↗" : (g_breakoutDown ? "DOWN ↘" : "Wait...")));
         text += StringFormat("Trades: B:%d S:%d", g_buyTradeCount, g_sellTradeCount);
      }
      else text += (g_inSession ? "Scanning Session..." : "Waiting for Session...");

      ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, name, OBJPROP_XDISTANCE, 10);
      ObjectSetInteger(0, name, OBJPROP_YDISTANCE, 30);
      ObjectSetString(0, name, OBJPROP_TEXT, text);
      ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 10);
      ObjectSetString(0, name, OBJPROP_FONT, "Consolas");
   }
}
