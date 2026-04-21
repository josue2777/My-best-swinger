//+------------------------------------------------------------------+
//|                                          BRANDOXCY AUTO AI.mq5  |
//|                          Copyright © 2025, BRANDOXCY AUTO AI     |
//|                       Powered by Advanced Grid Trading Engine    |
//+------------------------------------------------------------------+
#property copyright "Copyright © 2025, BRANDOXCY AUTO AI"
#property link      "https://t.me/simpleforextools"
#property version   "1.00"
#property description "BRANDOXCY AUTO AI — Pure Grid Trading System for MT5"

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\DealInfo.mqh>

//+------------------------------------------------------------------+
//| EXPIRY CONFIGURATION                                             |
//+------------------------------------------------------------------+
// License valid from 08 April 2026 to 16 April 2026
// After expiry the EA halts and shows a renewal notice.
#define LICENSE_START  D'2009.04.08 00:00:00'
#define LICENSE_EXPIRY D'2500.04.16 23:59:59'
#define OWNER_WHATSAPP "+254708777068"
#define EXPIRY_LABEL   "BXCY_EXPIRY_NOTICE"

//+------------------------------------------------------------------+
//| INPUT PARAMETERS                                                 |
//+------------------------------------------------------------------+
input group "═══════ BRANDOXCY AUTO AI ═══════"
input string   EA_Info            = "Grid Mode — Opens trades at every GridStep";

input group "━━━━━ GRID SETTINGS ━━━━━"
input double   Lots               = 0.01;    // Initial lot size
input double   GridStep           = 200;      // Grid step in points between orders
input int      MaxGridOrders      = 20;      // Maximum grid orders per direction
input double   Multiplier         = 1.5;     // Lot multiplier per grid level
input bool     UseMartingale      = true;    // Multiply lots at each level
input ENUM_ORDER_TYPE GridDirection = 0; // Grid direction: BUY / SELL / Both handled below

input group "━━━━━ PROFIT SETTINGS ━━━━━"
input double   TakeProfit         = 100;      // Group take profit in points
input double   StopLoss           = 0;       // Individual stop loss (0 = off)

input group "━━━━━ TRAILING STOP ━━━━━"
input bool     EnableTrailing     = false;   // Enable trailing stop
input int      TrailStart         = 20;      // Profit in points before trailing starts
input int      TrailStep          = 10;      // Trailing step in points

input group "━━━━━ PROTECTION ━━━━━"
input bool     EnableStopOut      = false;   // Enable equity stop-out
input double   StopOutPercent     = 20.0;    // Max drawdown % of starting equity
input bool     EnableTimeout      = false;   // Enable time-based close
input double   TimeoutHours       = 48.0;    // Hours after first trade before timeout close

input group "━━━━━ GRID MODE ━━━━━"
input bool     BothDirections     = true;    // Trade both BUY and SELL grids simultaneously
input bool     UseInitialSignal   = true;    // Use 3-candle signal for first trade; else open immediately

input group "━━━━━ SLIPPAGE & SPREAD ━━━━━"
input int      MaxSlippage        = 10;      // Max allowed slippage in points (0 = off)
input double   MaxSpreadPoints    = 30;      // Max allowed spread in points to open trade (0 = off)

input group "━━━━━ DASHBOARD ━━━━━"
input bool     ShowDashboard      = true;    // Show on-chart dashboard
input int      DashX              = 20;      // Dashboard X position (pixels from left)
input int      DashY              = 30;      // Dashboard Y position (pixels from top)
input color    DashColorBg        = C'18,13,5';       // Dashboard background colour  (deep black-gold)
input color    DashColorHeader    = C'212,170,30';    // Header / accent colour       (rich gold)
input color    DashColorBuy       = C'80,220,130';    // BUY text colour              (emerald green)
input color    DashColorSell      = C'235,80,70';     // SELL text colour             (ruby red)
input color    DashColorText      = C'220,200,140';   // General text colour          (warm parchment)
input color    DashColorWarn      = C'255,210,60';    // Warning / caution colour     (bright gold)

//+------------------------------------------------------------------+
//| OBJECTS                                                          |
//+------------------------------------------------------------------+
CTrade        trade;
CPositionInfo posInfo;

//+------------------------------------------------------------------+
//| CONSTANTS                                                        |
//+------------------------------------------------------------------+
const int     MAGIC = 132679;
const string  EALABEL = "BRANDOXCY AUTO AI";

// Dashboard object name prefix
const string  DASH_PFX = "BXCY_DASH_";

//+------------------------------------------------------------------+
//| GLOBAL STATE                                                     |
//+------------------------------------------------------------------+
datetime  g_LastTickTime      = 0;
datetime  g_TimeoutDeadline   = 0;
double    g_StartEquity       = 0;

// BUY grid state
int       g_BuyGridCount      = 0;
double    g_BuyLowestPrice    = 0;
double    g_BuyWeightedAvg    = 0;
double    g_BuyGroupTP        = 0;

// SELL grid state
int       g_SellGridCount     = 0;
double    g_SellHighestPrice  = 0;
double    g_SellWeightedAvg   = 0;
double    g_SellGroupTP       = 0;

bool      g_GridActive        = false;
bool      g_LicenseExpired    = false;   // ← expiry flag

// Slippage / spread tracking
double    g_LastSpread        = 0;
double    g_MaxSpreadSeen     = 0;
int       g_SlippageBlocks    = 0;
int       g_TradesOpened      = 0;

//+------------------------------------------------------------------+
//| EXPIRY CHECK — returns true if licence is valid                  |
//+------------------------------------------------------------------+
bool IsLicenseValid()
  {
   datetime now = TimeCurrent();

   // Not yet activated
   if(now < LICENSE_START)
     {
      Print("BRANDOXCY AUTO AI: Licence not yet active. Starts ", TimeToString(LICENSE_START));
      ShowExpiryNotice("NOT YET ACTIVE",
                       "Licence starts: " + TimeToString(LICENSE_START, TIME_DATE));
      return false;
     }

   // Expired
   if(now > LICENSE_EXPIRY)
     {
      g_LicenseExpired = true;
      Print("═══════════════════════════════════════════════════════");
      Print("  BRANDOXCY AUTO AI — LICENCE EXPIRED                  ");
      Print("  Expiry : ", TimeToString(LICENSE_EXPIRY, TIME_DATE));
      Print("  Please contact the owner for renewal:                ");
      Print("  WhatsApp: ", OWNER_WHATSAPP);
      Print("═══════════════════════════════════════════════════════");
      ShowExpiryNotice("LICENCE EXPIRED",
                       "Contact owner on WhatsApp to renew:\n" + OWNER_WHATSAPP);
      return false;
     }

   // Valid — show days-remaining warning when ≤ 2 days left
   int daysLeft = (int)((LICENSE_EXPIRY - now) / 86400);
   if(daysLeft <= 2)
      Print("BRANDOXCY AUTO AI: WARNING — Licence expires in ", daysLeft, " day(s). "
            "Renew via WhatsApp: ", OWNER_WHATSAPP);

   return true;
  }

//+------------------------------------------------------------------+
//| Draw / refresh the on-chart expiry notice panel                 |
//+------------------------------------------------------------------+
void ShowExpiryNotice(string headline, string detail)
  {
   int px = 60, py = 80, pw = 400, ph = 120;

   // Background — deep red
   string bgName = EXPIRY_LABEL + "_BG";
   if(ObjectFind(0, bgName) < 0)
      ObjectCreate(0, bgName, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, bgName, OBJPROP_CORNER,    CORNER_LEFT_UPPER);
   ObjectSetInteger(0, bgName, OBJPROP_XDISTANCE, px);
   ObjectSetInteger(0, bgName, OBJPROP_YDISTANCE, py);
   ObjectSetInteger(0, bgName, OBJPROP_XSIZE,     pw);
   ObjectSetInteger(0, bgName, OBJPROP_YSIZE,     ph);
   ObjectSetInteger(0, bgName, OBJPROP_BGCOLOR,   C'100,0,0');
   ObjectSetInteger(0, bgName, OBJPROP_BORDER_COLOR, C'255,80,60');
   ObjectSetInteger(0, bgName, OBJPROP_BORDER_TYPE,  BORDER_FLAT);
   ObjectSetInteger(0, bgName, OBJPROP_SELECTABLE,   false);
   ObjectSetInteger(0, bgName, OBJPROP_HIDDEN,        true);

   // Helper lambda — create/update a label inside the notice
   #define ELABEL(tag, txt, ox, oy, fs, clr) \
      { string n = EXPIRY_LABEL + tag; \
        if(ObjectFind(0,n)<0) ObjectCreate(0,n,OBJ_LABEL,0,0,0); \
        ObjectSetInteger(0,n,OBJPROP_CORNER,   CORNER_LEFT_UPPER); \
        ObjectSetInteger(0,n,OBJPROP_XDISTANCE,px+(ox)); \
        ObjectSetInteger(0,n,OBJPROP_YDISTANCE,py+(oy)); \
        ObjectSetInteger(0,n,OBJPROP_FONTSIZE, fs); \
        ObjectSetInteger(0,n,OBJPROP_COLOR,    clr); \
        ObjectSetString (0,n,OBJPROP_FONT,     "Georgia"); \
        ObjectSetString (0,n,OBJPROP_TEXT,     txt); \
        ObjectSetInteger(0,n,OBJPROP_SELECTABLE,false); \
        ObjectSetInteger(0,n,OBJPROP_HIDDEN,    true); }

   ELABEL("_ICON",  "⚠  BRANDOXCY AUTO AI",      12, 10, 10, C'255,222,80')
   ELABEL("_HEAD",  headline,                      12, 32, 11, C'255,100,80')
   ELABEL("_DTL1",  detail,                        12, 56,  9, C'255,200,150')
   ELABEL("_WA",    "WhatsApp: " + OWNER_WHATSAPP, 12, 82,  9, C'100,220,120')
   ELABEL("_HALT",  "⛔  EA IS HALTED — NO TRADES WILL BE PLACED", 12, 100, 8, C'255,80,60')

   #undef ELABEL

   ChartRedraw(0);
  }

//+------------------------------------------------------------------+
//| Remove expiry notice objects                                     |
//+------------------------------------------------------------------+
void RemoveExpiryNotice()
  {
   ObjectsDeleteAll(0, EXPIRY_LABEL);
   ChartRedraw(0);
  }

//+------------------------------------------------------------------+
//| Detect suitable filling mode for the broker                      |
//+------------------------------------------------------------------+
ENUM_ORDER_TYPE_FILLING GetFillingMode()
  {
   long filling = SymbolInfoInteger(_Symbol, SYMBOL_FILLING_MODE);
   if((filling & SYMBOL_FILLING_FOK) != 0) return ORDER_FILLING_FOK;
   if((filling & SYMBOL_FILLING_IOC) != 0) return ORDER_FILLING_IOC;
   return ORDER_FILLING_RETURN;
  }

//+------------------------------------------------------------------+
//| INIT                                                             |
//+------------------------------------------------------------------+
int OnInit()
  {
   trade.SetExpertMagicNumber(MAGIC);
   trade.SetDeviationInPoints(MaxSlippage > 0 ? MaxSlippage : 10);
   trade.SetTypeFilling(GetFillingMode());

   // ── LICENCE CHECK ────────────────────────────────────────────────
   if(!IsLicenseValid())
     {
      // Allow init to succeed so the notice stays visible,
      // but grid will never run (checked every tick/timer).
      Print("BRANDOXCY AUTO AI: Licence invalid — EA halted.");
      EventSetTimer(60); // refresh notice every minute
      return(INIT_SUCCEEDED);
     }

   EventSetTimer(1);

   g_StartEquity      = AccountInfoDouble(ACCOUNT_EQUITY);
   g_LastTickTime     = 0;
   g_TimeoutDeadline  = 0;
   g_BuyGridCount     = 0;
   g_SellGridCount    = 0;
   g_BuyLowestPrice   = 0;
   g_SellHighestPrice = 0;
   g_GridActive       = false;
   g_MaxSpreadSeen    = 0;
   g_SlippageBlocks   = 0;
   g_TradesOpened     = 0;

   if(ShowDashboard) BuildDashboard();

   Print("════════════════════════════════════════════");
   Print("    BRANDOXCY AUTO AI  |  GRID MODE         ");
   Print("    GridStep=", GridStep, " pts  |  MaxOrders=", MaxGridOrders);
   Print("    Lots=", Lots, "  |  Multiplier=", Multiplier);
   Print("    BothDirections=", BothDirections);
   Print("    MaxSlippage=", MaxSlippage, " pts  |  MaxSpread=", MaxSpreadPoints, " pts");
   Print("    Licence valid until: ", TimeToString(LICENSE_EXPIRY, TIME_DATE));
   Print("════════════════════════════════════════════");

   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| DEINIT                                                           |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   EventKillTimer();
   RemoveDashboard();
   RemoveExpiryNotice();
   Print("BRANDOXCY AUTO AI stopped. Reason: ", reason);
  }

//+------------------------------------------------------------------+
//| ON TICK — main execution                                        |
//+------------------------------------------------------------------+
void OnTick()
  {
   // ── LICENCE GATE ─────────────────────────────────────────────────
   if(!IsLicenseValid()) return;

   if(EnableTrailing) RunTrailingStop();
   RunGridLogic();
   if(ShowDashboard) RefreshDashboard();
  }

//+------------------------------------------------------------------+
//| ON TIMER — safety net every 1 second (or 60 s when expired)    |
//+------------------------------------------------------------------+
void OnTimer()
  {
   // ── LICENCE GATE ─────────────────────────────────────────────────
   if(!IsLicenseValid()) return;

   RunGridLogic();
   if(ShowDashboard) RefreshDashboard();
  }

//+------------------------------------------------------------------+
//| SPREAD GUARD — returns false if spread is too wide              |
//+------------------------------------------------------------------+
bool IsSpreadOK()
  {
   if(MaxSpreadPoints <= 0) return true;

   double ask    = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid    = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double spread = (ask - bid) / _Point;

   g_LastSpread = spread;
   if(spread > g_MaxSpreadSeen) g_MaxSpreadSeen = spread;

   if(spread > MaxSpreadPoints)
     {
      g_SlippageBlocks++;
      Print("BRANDOXCY AUTO AI: SPREAD TOO WIDE — ", DoubleToString(spread, 1),
            " pts (max=", MaxSpreadPoints, ")");
      return false;
     }
   return true;
  }

//+------------------------------------------------------------------+
//| CORE GRID LOGIC                                                  |
//+------------------------------------------------------------------+
void RunGridLogic()
  {
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

   //--- Timeout check
   if(EnableTimeout && g_TimeoutDeadline > 0 && TimeCurrent() >= g_TimeoutDeadline)
     {
      CloseAllPositions(true, true);
      g_TimeoutDeadline = 0;
      g_GridActive      = false;
      Print("BRANDOXCY AUTO AI: TIMEOUT — all positions closed");
      return;
     }

   //--- Equity stop-out
   if(EnableStopOut)
     {
      double equity   = AccountInfoDouble(ACCOUNT_EQUITY);
      double drawdown = g_StartEquity - equity;
      if(drawdown > 0 && (drawdown / g_StartEquity * 100.0) >= StopOutPercent)
        {
         CloseAllPositions(true, true);
         g_GridActive = false;
         Print("BRANDOXCY AUTO AI: STOP-OUT — drawdown exceeded ", StopOutPercent, "%");
         return;
        }
     }

   //--- Refresh grid counts and state
   ScanGrid();

   //--- If grid is flat, decide whether to start
   if(g_BuyGridCount == 0 && g_SellGridCount == 0)
     {
      g_GridActive  = false;
      g_StartEquity = AccountInfoDouble(ACCOUNT_EQUITY);

      if(UseInitialSignal)
        {
         double c1 = iClose(_Symbol, PERIOD_M1, 3);
         double c2 = iClose(_Symbol, PERIOD_M1, 2);
         double c3 = iClose(_Symbol, PERIOD_M1, 1);

         bool bullish = (c3 > c2 && c2 > c1);
         bool bearish = (c3 < c2 && c2 < c1);

         if(bullish)
           {
            if(BothDirections || GridDirection == ORDER_TYPE_BUY)
               TryOpenBuyGrid(ask);
           }
         if(bearish)
           {
            if(BothDirections || GridDirection == ORDER_TYPE_SELL)
               TryOpenSellGrid(bid);
           }
         if(!bullish && !bearish) return;
        }
      else
        {
         if(BothDirections || GridDirection == ORDER_TYPE_BUY)
            TryOpenBuyGrid(ask);
         if(BothDirections || GridDirection == ORDER_TYPE_SELL)
            TryOpenSellGrid(bid);
        }
      return;
     }

   //--- BUY GRID: add next level if price dropped GridStep from lowest buy
   if((BothDirections || GridDirection == ORDER_TYPE_BUY) &&
      g_BuyGridCount > 0 && g_BuyGridCount < MaxGridOrders)
     {
      double trigger = g_BuyLowestPrice - GridStep * _Point;
      if(ask <= trigger)
         TryOpenBuyGrid(ask);
     }

   //--- SELL GRID: add next level if price rose GridStep from highest sell
   if((BothDirections || GridDirection == ORDER_TYPE_SELL) &&
      g_SellGridCount > 0 && g_SellGridCount < MaxGridOrders)
     {
      double trigger = g_SellHighestPrice + GridStep * _Point;
      if(bid >= trigger)
         TryOpenSellGrid(bid);
     }

   //--- Update group TPs after scan
   UpdateGroupTP(true);
   UpdateGroupTP(false);
  }

//+------------------------------------------------------------------+
//| Open next BUY grid order                                        |
//+------------------------------------------------------------------+
void TryOpenBuyGrid(double price)
  {
   if(!IsSpreadOK()) return;

   int    level  = g_BuyGridCount;
   double lots   = CalcLots(level);

   if(!CheckMargin(ORDER_TYPE_BUY, lots)) return;

   string cmt    = EALABEL + "-BUY-" + IntegerToString(level);
   double slPrice = (StopLoss > 0) ? NormalizeDouble(price - StopLoss * _Point, _Digits) : 0;

   if(trade.Buy(lots, _Symbol, 0, slPrice, 0, cmt))
     {
      g_TradesOpened++;
      if(!g_GridActive)
        {
         g_GridActive      = true;
         g_TimeoutDeadline = EnableTimeout
                             ? TimeCurrent() + (datetime)(TimeoutHours * 3600)
                             : 0;
        }
      Print("BRANDOXCY AUTO AI: BUY GRID #", level,
            " opened | Lots=", lots, " | ~Price=", price,
            " | Total BUY orders=", g_BuyGridCount + 1);
      ScanGrid();
      UpdateGroupTP(true);
     }
   else
      Print("BRANDOXCY AUTO AI: BUY #", level, " FAILED [",
            trade.ResultRetcode(), "] ", trade.ResultRetcodeDescription());
  }

//+------------------------------------------------------------------+
//| Open next SELL grid order                                       |
//+------------------------------------------------------------------+
void TryOpenSellGrid(double price)
  {
   if(!IsSpreadOK()) return;

   int    level  = g_SellGridCount;
   double lots   = CalcLots(level);

   if(!CheckMargin(ORDER_TYPE_SELL, lots)) return;

   string cmt    = EALABEL + "-SELL-" + IntegerToString(level);
   double slPrice = (StopLoss > 0) ? NormalizeDouble(price + StopLoss * _Point, _Digits) : 0;

   if(trade.Sell(lots, _Symbol, 0, slPrice, 0, cmt))
     {
      g_TradesOpened++;
      if(!g_GridActive)
        {
         g_GridActive      = true;
         g_TimeoutDeadline = EnableTimeout
                             ? TimeCurrent() + (datetime)(TimeoutHours * 3600)
                             : 0;
        }
      Print("BRANDOXCY AUTO AI: SELL GRID #", level,
            " opened | Lots=", lots, " | ~Price=", price,
            " | Total SELL orders=", g_SellGridCount + 1);
      ScanGrid();
      UpdateGroupTP(false);
     }
   else
      Print("BRANDOXCY AUTO AI: SELL #", level, " FAILED [",
            trade.ResultRetcode(), "] ", trade.ResultRetcodeDescription());
  }

//+------------------------------------------------------------------+
//| Scan all open positions and rebuild grid state                  |
//+------------------------------------------------------------------+
void ScanGrid()
  {
   g_BuyGridCount     = 0;
   g_SellGridCount    = 0;
   g_BuyLowestPrice   = 0;
   g_SellHighestPrice = 0;

   double buyTotalVal  = 0, buyTotalLots  = 0;
   double sellTotalVal = 0, sellTotalLots = 0;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(!posInfo.SelectByIndex(i)) continue;
      if(posInfo.Symbol() != _Symbol) continue;
      if((int)posInfo.Magic() != MAGIC) continue;

      double openPrice = posInfo.PriceOpen();
      double vol       = posInfo.Volume();

      if(posInfo.PositionType() == POSITION_TYPE_BUY)
        {
         g_BuyGridCount++;
         buyTotalVal  += openPrice * vol;
         buyTotalLots += vol;
         if(g_BuyLowestPrice == 0 || openPrice < g_BuyLowestPrice)
            g_BuyLowestPrice = openPrice;
        }
      else if(posInfo.PositionType() == POSITION_TYPE_SELL)
        {
         g_SellGridCount++;
         sellTotalVal  += openPrice * vol;
         sellTotalLots += vol;
         if(g_SellHighestPrice == 0 || openPrice > g_SellHighestPrice)
            g_SellHighestPrice = openPrice;
        }
     }

   g_BuyWeightedAvg  = (buyTotalLots  > 0) ? NormalizeDouble(buyTotalVal  / buyTotalLots,  _Digits) : 0;
   g_SellWeightedAvg = (sellTotalLots > 0) ? NormalizeDouble(sellTotalVal / sellTotalLots, _Digits) : 0;
  }

//+------------------------------------------------------------------+
//| Update group TP based on weighted average                       |
//+------------------------------------------------------------------+
void UpdateGroupTP(bool isBuy)
  {
   double avg = isBuy ? g_BuyWeightedAvg : g_SellWeightedAvg;
   if(avg <= 0) return;

   double tpPrice = isBuy
                    ? NormalizeDouble(avg + TakeProfit * _Point, _Digits)
                    : NormalizeDouble(avg - TakeProfit * _Point, _Digits);

   ENUM_POSITION_TYPE pType    = isBuy ? POSITION_TYPE_BUY : POSITION_TYPE_SELL;
   double             storedTP = isBuy ? g_BuyGroupTP : g_SellGroupTP;

   if(MathAbs(tpPrice - storedTP) < _Point) return;

   if(isBuy)  g_BuyGroupTP  = tpPrice;
   else       g_SellGroupTP = tpPrice;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(!posInfo.SelectByIndex(i)) continue;
      if(posInfo.Symbol() != _Symbol) continue;
      if((int)posInfo.Magic() != MAGIC) continue;
      if(posInfo.PositionType() != pType) continue;

      if(MathAbs(posInfo.TakeProfit() - tpPrice) > _Point)
         trade.PositionModify(posInfo.Ticket(), posInfo.StopLoss(), tpPrice);
     }

   Print("BRANDOXCY AUTO AI: ", isBuy ? "BUY" : "SELL",
         " group TP set to ", tpPrice,
         " | Avg=", avg,
         " | Orders=", isBuy ? g_BuyGridCount : g_SellGridCount);
  }

//+------------------------------------------------------------------+
//| Calculate lot size for grid level                               |
//+------------------------------------------------------------------+
double CalcLots(int level)
  {
   double volMin  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double volMax  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double volStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

   double lots = UseMartingale
                 ? Lots * MathPow(Multiplier, level)
                 : Lots;

   lots = MathFloor(lots / volStep) * volStep;
   lots = NormalizeDouble(lots, 2);
   lots = MathMax(lots, volMin);
   lots = MathMin(lots, volMax);
   return lots;
  }

//+------------------------------------------------------------------+
//| Check free margin before opening order                          |
//+------------------------------------------------------------------+
bool CheckMargin(ENUM_ORDER_TYPE type, double lots)
  {
   double margin   = 0;
   double refPrice = (type == ORDER_TYPE_BUY)
                     ? SymbolInfoDouble(_Symbol, SYMBOL_ASK)
                     : SymbolInfoDouble(_Symbol, SYMBOL_BID);

   if(!OrderCalcMargin(type, _Symbol, lots, refPrice, margin))
     {
      Print("BRANDOXCY AUTO AI: Margin calculation error");
      return false;
     }

   double freeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
   if(freeMargin < margin * 1.1)
     {
      Print("BRANDOXCY AUTO AI: INSUFFICIENT MARGIN — Need=", margin,
            " Have=", freeMargin);
      return false;
     }
   return true;
  }

//+------------------------------------------------------------------+
//| Close all EA positions by direction                             |
//+------------------------------------------------------------------+
void CloseAllPositions(bool closeBuys, bool closeSells)
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(!posInfo.SelectByIndex(i)) continue;
      if(posInfo.Symbol() != _Symbol) continue;
      if((int)posInfo.Magic() != MAGIC) continue;

      if(closeBuys  && posInfo.PositionType() == POSITION_TYPE_BUY)
         trade.PositionClose(posInfo.Ticket());
      if(closeSells && posInfo.PositionType() == POSITION_TYPE_SELL)
         trade.PositionClose(posInfo.Ticket());
      Sleep(200);
     }
   ScanGrid();
  }

//+------------------------------------------------------------------+
//| Trailing stop — runs every tick                                 |
//+------------------------------------------------------------------+
void RunTrailingStop()
  {
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(!posInfo.SelectByIndex(i)) continue;
      if(posInfo.Symbol() != _Symbol) continue;
      if((int)posInfo.Magic() != MAGIC) continue;

      if(posInfo.PositionType() == POSITION_TYPE_BUY)
        {
         double profit = (bid - posInfo.PriceOpen()) / _Point;
         if(profit >= TrailStart)
           {
            double newSL = NormalizeDouble(bid - TrailStep * _Point, _Digits);
            if(posInfo.StopLoss() == 0 || newSL > posInfo.StopLoss())
               trade.PositionModify(posInfo.Ticket(), newSL, posInfo.TakeProfit());
           }
        }
      else if(posInfo.PositionType() == POSITION_TYPE_SELL)
        {
         double profit = (posInfo.PriceOpen() - ask) / _Point;
         if(profit >= TrailStart)
           {
            double newSL = NormalizeDouble(ask + TrailStep * _Point, _Digits);
            if(posInfo.StopLoss() == 0 || newSL < posInfo.StopLoss())
               trade.PositionModify(posInfo.Ticket(), newSL, posInfo.TakeProfit());
           }
        }
     }
  }

//+------------------------------------------------------------------+
//| ═══════════════  DASHBOARD  ═══════════════                     |
//+------------------------------------------------------------------+

#define GOLD_DEEP      C'18,13,5'
#define GOLD_BORDER    C'120,88,10'
#define GOLD_HDR_BG    C'40,28,4'
#define GOLD_HDR_LINE  C'212,170,30'
#define GOLD_SECTION   C'30,22,4'
#define GOLD_SHIMMER   C'255,222,80'
#define GOLD_MID       C'200,155,25'
#define GOLD_DIM       C'130,100,40'
#define GOLD_PARCHMENT C'228,208,158'
#define GOLD_GREEN     C'72,210,120'
#define GOLD_RED       C'230,75,65'
#define GOLD_AMBER     C'255,200,50'
#define GOLD_TITLE_BG  C'25,18,3'

void DashLabel(string name, string text, int x, int y,
               int fontSize, color clr, string font = "Consolas",
               ENUM_ANCHOR_POINT anchor = ANCHOR_LEFT_UPPER)
  {
   string fullName = DASH_PFX + name;
   if(ObjectFind(0, fullName) < 0)
     {
      ObjectCreate(0, fullName, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, fullName, OBJPROP_SELECTABLE,  false);
      ObjectSetInteger(0, fullName, OBJPROP_HIDDEN,      true);
      ObjectSetInteger(0, fullName, OBJPROP_CORNER,      CORNER_LEFT_UPPER);
      ObjectSetInteger(0, fullName, OBJPROP_ANCHOR,      anchor);
     }
   ObjectSetInteger(0, fullName, OBJPROP_XDISTANCE,  x);
   ObjectSetInteger(0, fullName, OBJPROP_YDISTANCE,  y);
   ObjectSetInteger(0, fullName, OBJPROP_FONTSIZE,   fontSize);
   ObjectSetInteger(0, fullName, OBJPROP_COLOR,      clr);
   ObjectSetString (0, fullName, OBJPROP_FONT,       font);
   ObjectSetString (0, fullName, OBJPROP_TEXT,       text);
  }

void DashRect(string name, int x, int y, int w, int h, color bg, color border)
  {
   string fullName = DASH_PFX + name;
   if(ObjectFind(0, fullName) < 0)
     {
      ObjectCreate(0, fullName, OBJ_RECTANGLE_LABEL, 0, 0, 0);
      ObjectSetInteger(0, fullName, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, fullName, OBJPROP_HIDDEN,     true);
      ObjectSetInteger(0, fullName, OBJPROP_CORNER,     CORNER_LEFT_UPPER);
     }
   ObjectSetInteger(0, fullName, OBJPROP_XDISTANCE,  x);
   ObjectSetInteger(0, fullName, OBJPROP_YDISTANCE,  y);
   ObjectSetInteger(0, fullName, OBJPROP_XSIZE,      w);
   ObjectSetInteger(0, fullName, OBJPROP_YSIZE,      h);
   ObjectSetInteger(0, fullName, OBJPROP_BGCOLOR,    bg);
   ObjectSetInteger(0, fullName, OBJPROP_BORDER_COLOR, border);
   ObjectSetInteger(0, fullName, OBJPROP_BORDER_TYPE, BORDER_FLAT);
  }

void BuildDashboard()
  {
   int bx = DashX;
   int by = DashY;
   int bw = 290;
   int bh = 356;   // +16 for expiry row

   DashRect("BORDER",  bx-1,  by-1,  bw+2,  bh+2,  GOLD_BORDER,  GOLD_BORDER);
   DashRect("BG",      bx,    by,    bw,    bh,    GOLD_DEEP,    GOLD_BORDER);
   DashRect("HDR_BG",  bx,    by,    bw,    28,    GOLD_HDR_BG,  GOLD_HDR_BG);
   DashRect("HDR_LN",  bx,    by+28, bw,    2,     GOLD_HDR_LINE, GOLD_HDR_LINE);

   DashRect("SEC_MKT",  bx+2, by+32,  bw-4, 84,  GOLD_SECTION, GOLD_SECTION);
   DashRect("SEP_LN1",  bx+6, by+118, bw-12, 1,  GOLD_MID,     GOLD_MID);
   DashRect("SEC_ACC",  bx+2, by+121, bw-4, 70,  GOLD_SECTION, GOLD_SECTION);
   DashRect("SEP_LN2",  bx+6, by+193, bw-12, 1,  GOLD_MID,     GOLD_MID);
   DashRect("SEC_GRD",  bx+2, by+196, bw-4, 84,  GOLD_SECTION, GOLD_SECTION);
   DashRect("SEP_LN3",  bx+6, by+282, bw-12, 1,  GOLD_MID,     GOLD_MID);
   DashRect("SEC_TRD",  bx+2, by+285, bw-4, 16,  GOLD_SECTION, GOLD_SECTION);
   DashRect("SEP_LN4",  bx+6, by+303, bw-12, 1,  GOLD_MID,     GOLD_MID);
   // Expiry row
   DashRect("SEC_EXP",  bx+2, by+306, bw-4, 30,  GOLD_SECTION, GOLD_SECTION);

   DashLabel("TitleTxt", "✦  BRANDOXCY AUTO AI  ✦",
             bx+14, by+7,  10, GOLD_SHIMMER, "Georgia");
   DashLabel("VerTxt",   "v1.00",
             bx+246, by+9,  7, GOLD_DIM,    "Consolas");

   DashLabel("SH_MKT",  "MARKET",   bx+6, by+33,  6, GOLD_MID, "Consolas");
   DashLabel("SH_ACC",  "ACCOUNT",  bx+6, by+122, 6, GOLD_MID, "Consolas");
   DashLabel("SH_GRD",  "GRID",     bx+6, by+197, 6, GOLD_MID, "Consolas");
   DashLabel("SH_TRD",  "SESSION",  bx+6, by+286, 6, GOLD_MID, "Consolas");
   DashLabel("SH_EXP",  "LICENCE",  bx+6, by+307, 6, GOLD_MID, "Consolas");

   int lx = bx + 10;

   DashLabel("L_SYM",   "Symbol  :",  lx, by+42,  8, GOLD_PARCHMENT, "Consolas");
   DashLabel("L_BID",   "Bid     :",  lx, by+56,  8, GOLD_PARCHMENT, "Consolas");
   DashLabel("L_ASK",   "Ask     :",  lx, by+70,  8, GOLD_PARCHMENT, "Consolas");
   DashLabel("L_SPR",   "Spread  :",  lx, by+84,  8, GOLD_PARCHMENT, "Consolas");
   DashLabel("L_MSPR",  "MaxSprd :",  lx, by+98,  8, GOLD_PARCHMENT, "Consolas");
   DashLabel("L_SLIP",  "Slip.Blk:",  lx, by+112, 8, GOLD_PARCHMENT, "Consolas");

   DashLabel("L_BAL",   "Balance :",  lx, by+131, 8, GOLD_PARCHMENT, "Consolas");
   DashLabel("L_EQ",    "Equity  :",  lx, by+145, 8, GOLD_PARCHMENT, "Consolas");
   DashLabel("L_DD",    "DrawDown:",  lx, by+159, 8, GOLD_PARCHMENT, "Consolas");
   DashLabel("L_FR",    "Free Mrg:",  lx, by+173, 8, GOLD_PARCHMENT, "Consolas");
   DashLabel("L_PNL",   "Open P&L:",  lx, by+187, 8, GOLD_PARCHMENT, "Consolas");

   DashLabel("L_BGRD",  "BUY Grid:",  lx, by+206, 8, GOLD_PARCHMENT, "Consolas");
   DashLabel("L_BWAV",  "BUY Avg :",  lx, by+220, 8, GOLD_PARCHMENT, "Consolas");
   DashLabel("L_BTP",   "BUY  TP :",  lx, by+234, 8, GOLD_PARCHMENT, "Consolas");
   DashLabel("L_SGRD",  "SEL Grid:",  lx, by+250, 8, GOLD_PARCHMENT, "Consolas");
   DashLabel("L_SWAV",  "SEL Avg :",  lx, by+264, 8, GOLD_PARCHMENT, "Consolas");
   DashLabel("L_STP",   "SEL  TP :",  lx, by+278, 8, GOLD_PARCHMENT, "Consolas");

   DashLabel("L_TRDCNT","Trades  :",  lx, by+288, 8, GOLD_PARCHMENT, "Consolas");

   // Expiry static labels
   DashLabel("L_EXPIRY","Expires :",  lx, by+316, 8, GOLD_PARCHMENT, "Consolas");

   ChartRedraw(0);
  }

//+------------------------------------------------------------------+
//| Update all dynamic values every tick / timer                    |
//+------------------------------------------------------------------+
void RefreshDashboard()
  {
   if(!ShowDashboard) return;

   double bid    = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask    = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double spread = (ask - bid) / _Point;
   if(spread > g_MaxSpreadSeen) g_MaxSpreadSeen = spread;
   g_LastSpread = spread;

   double balance    = AccountInfoDouble(ACCOUNT_BALANCE);
   double equity     = AccountInfoDouble(ACCOUNT_EQUITY);
   double freeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
   double drawdown   = (g_StartEquity > 0)
                       ? MathMax(0.0, (g_StartEquity - equity) / g_StartEquity * 100.0)
                       : 0.0;

   double openPnl = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(!posInfo.SelectByIndex(i)) continue;
      if(posInfo.Symbol() != _Symbol) continue;
      if((int)posInfo.Magic() != MAGIC) continue;
      openPnl += posInfo.Profit() + posInfo.Swap() + posInfo.Commission();
     }

   int vx = DashX + 128;
   int by = DashY;

   color sprClr  = (MaxSpreadPoints > 0 && spread > MaxSpreadPoints) ? GOLD_RED : GOLD_GREEN;
   color slipClr = (g_SlippageBlocks > 0) ? GOLD_AMBER : GOLD_PARCHMENT;
   color ddClr   = (drawdown > StopOutPercent * 0.75) ? GOLD_RED
                   : (drawdown > StopOutPercent * 0.40) ? GOLD_AMBER
                   : GOLD_PARCHMENT;
   color pnlClr  = (openPnl >= 0) ? GOLD_GREEN : GOLD_RED;

   DashLabel("V_SYM",  _Symbol,                             vx, by+42,  8, GOLD_SHIMMER,   "Consolas");
   DashLabel("V_BID",  DoubleToString(bid, _Digits),        vx, by+56,  8, GOLD_PARCHMENT, "Consolas");
   DashLabel("V_ASK",  DoubleToString(ask, _Digits),        vx, by+70,  8, GOLD_PARCHMENT, "Consolas");
   DashLabel("V_SPR",  DoubleToString(spread, 1) + " pts",  vx, by+84,  8, sprClr,         "Consolas");
   DashLabel("V_MSPR", DoubleToString(g_MaxSpreadSeen, 1) + " pts", vx, by+98,  8, GOLD_AMBER, "Consolas");
   DashLabel("V_SLIP", IntegerToString(g_SlippageBlocks),   vx, by+112, 8, slipClr,        "Consolas");

   DashLabel("V_BAL",  DoubleToString(balance,    2),       vx, by+131, 8, GOLD_SHIMMER,   "Consolas");
   DashLabel("V_EQ",   DoubleToString(equity,     2),       vx, by+145, 8, GOLD_PARCHMENT, "Consolas");
   DashLabel("V_DD",   DoubleToString(drawdown,   2) + " %",vx, by+159, 8, ddClr,          "Consolas");
   DashLabel("V_FR",   DoubleToString(freeMargin, 2),       vx, by+173, 8, GOLD_PARCHMENT, "Consolas");
   DashLabel("V_PNL",  DoubleToString(openPnl,   2),        vx, by+187, 8, pnlClr,         "Consolas");

   string buyGrdTxt  = IntegerToString(g_BuyGridCount)  + " / " + IntegerToString(MaxGridOrders);
   string sellGrdTxt = IntegerToString(g_SellGridCount) + " / " + IntegerToString(MaxGridOrders);

   DashLabel("V_BGRD", buyGrdTxt,                           vx, by+206, 8, GOLD_GREEN,     "Consolas");
   DashLabel("V_BWAV", g_BuyWeightedAvg  > 0
             ? DoubleToString(g_BuyWeightedAvg, _Digits) : "—", vx, by+220, 8, GOLD_GREEN, "Consolas");
   DashLabel("V_BTP",  g_BuyGroupTP > 0
             ? DoubleToString(g_BuyGroupTP, _Digits) : "—",     vx, by+234, 8, GOLD_GREEN, "Consolas");
   DashLabel("V_SGRD", sellGrdTxt,                          vx, by+250, 8, GOLD_RED,       "Consolas");
   DashLabel("V_SWAV", g_SellWeightedAvg > 0
             ? DoubleToString(g_SellWeightedAvg, _Digits) : "—",vx, by+264, 8, GOLD_RED,   "Consolas");
   DashLabel("V_STP",  g_SellGroupTP > 0
             ? DoubleToString(g_SellGroupTP, _Digits) : "—",    vx, by+278, 8, GOLD_RED,   "Consolas");

   DashLabel("V_TRDCNT", IntegerToString(g_TradesOpened),   vx, by+288, 8, GOLD_SHIMMER,  "Consolas");

   // ── Licence / expiry row ─────────────────────────────────────────
   datetime now      = TimeCurrent();
   int      daysLeft = (int)((LICENSE_EXPIRY - now) / 86400);
   string   expTxt;
   color    expClr;

   if(now > LICENSE_EXPIRY)
     {
      expTxt = "EXPIRED — WA: " + OWNER_WHATSAPP;
      expClr = GOLD_RED;
     }
   else if(daysLeft <= 2)
     {
      expTxt = TimeToString(LICENSE_EXPIRY, TIME_DATE) +
               "  (" + IntegerToString(daysLeft) + "d left!)";
      expClr = GOLD_AMBER;
     }
   else
     {
      expTxt = TimeToString(LICENSE_EXPIRY, TIME_DATE) +
               "  (" + IntegerToString(daysLeft) + "d left)";
      expClr = GOLD_GREEN;
     }

   DashLabel("V_EXPIRY", expTxt, vx, by+316, 8, expClr, "Consolas");

   ChartRedraw(0);
  }

void RemoveDashboard()
  {
   ObjectsDeleteAll(0, DASH_PFX);
   ChartRedraw(0);
  }
//+------------------------------------------------------------------+