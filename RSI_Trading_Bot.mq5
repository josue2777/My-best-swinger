//+------------------------------------------------------------------+
//| ProjectName RSI Trading Bot                                                     |
//| Copyright 2026, CompanyName                                      |
//| http://www.companyname.net                                       |
//+------------------------------------------------------------------+
#include <Trade/Trade.mqh>

CTrade trade;
CPositionInfo pos;
COrderInfo ord;

// Dashboard object name prefix
const string  DASH_PFX = "CDMB_DASH_";

input group "=== Trading Inputs ==="
input double RiskPercent = 1; //Risk as % of Trading Capital
input int Tppoints = 450; //Take profit (10 points = 1 pip)
input int Slpoints = 250; //Stoploss points (10 points = 1 pip)
input int TslTriggerPoints = 10; //Points in profit before Trailing SL is activated (10 points = 1 pip)
input int TslPoints = 10; //Trailing Stop loss (10 points = 1 pip)
input ENUM_TIMEFRAMES Timeframe = PERIOD_CURRENT; //Time frame to run
input int InpMagic = 123; //Expert advisor identification
input string TradeComment = "Scalping Robot";
input string ExpirationDate = "999999999999999.05.30";

input group "=== Dashboard Settings ==="
input bool     ShowDashboard      = true;    // Show on-chart dashboard
input int      DashX              = 20;      // Dashboard X position (pixels from left)
input int      DashY              = 30;      // Dashboard Y position (pixels from top)

input group "=== Telegram Settings ==="
input string TelegramToken = "7801637901:AAHAoFEk3eXcOneF5hpy6FIAuD3R_clEAtw"; // API key Botfather !!!LEAVE EMPTY IN CODE - INSERT IN INPUTS!!!
input string TelegramChatID = "7505313544"; // Telegram group/channel chat ID !!!LEAVE EMPTY IN CODE - INSERT IN INPUTS!!!

input group "=== RSI Settings ==="
input int RSI_Period = 6;
input ENUM_APPLIED_PRICE RSI_AppliedPrice = PRICE_WEIGHTED;
input int RSI_Overbought = 85;
input int RSI_Oversold = 16;

int rsiHandle = INVALID_HANDLE;

enum StartHour
  {
   S_Inactive=0,
   S_0100=1,
   S_0200=2,
   S_0300=3,
   S_0400=4,
   S_0500=5,
   S_0600=6,
   S_0700=7,
   S_0800=8,
   S_0900=9,
   S_1000=10,
   S_1100=11,
   S_1200=12,
   S_1300=13,
   S_1400=14,
   S_1500=15,
   S_1600=16,
   S_1700=17,
   S_1800=18,
   S_1900=19,
   S_2000=20,
   S_2100=21,
   S_2200=22,
   S_2300=23
  };
input StartHour SHInput = 8; //Start Hour

enum EndHour
  {
   E_Inactive=0,
   E_0100=1,
   E_0200=2,
   E_0300=3,
   E_0400=4,
   E_0500=5,
   E_0600=6,
   E_0700=7,
   E_0800=8,
   E_0900=9,
   E_1000=10,
   E_1100=11,
   E_1200=12,
   E_1300=13,
   E_1400=14,
   E_1500=15,
   E_1600=16,
   E_1700=17,
   E_1800=18,
   E_1900=19,
   E_2000=20,
   E_2100=21,
   E_2200=22,
   E_2300=23
  };
input EndHour EHInput = 21; //End Hour

int SHchoice, EHChoice;

struct TradeTracking
  {
   ulong             ticket;
   bool              notified;
  };

TradeTracking trackedPositions[];
TradeTracking trackedOrders[];

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void ExecuteMarketBuy()
  {
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double sl = ask - Slpoints * _Point;
   double tp = ask + Tppoints * _Point;
   double lots = 0.01;

   if(RiskPercent > 0)
      lots = calcLots(ask - sl);

   trade.Buy(lots, _Symbol, ask, sl, tp, TradeComment);
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void ExecuteMarketSell()
  {
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double sl = bid + Slpoints * _Point;
   double tp = bid - Tppoints * _Point;
   double lots = 0.01;

   if(RiskPercent > 0)
      lots = calcLots(sl - bid);

   trade.Sell(lots, _Symbol, bid, sl, tp, TradeComment);
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
int OnInit()
  {
   trade.SetExpertMagicNumber(InpMagic);
   ChartSetInteger(0, CHART_SHOW_GRID, false);

   if(ShowDashboard) BuildDashboard();

   rsiHandle = iRSI(_Symbol, Timeframe, RSI_Period, RSI_AppliedPrice);
   if(rsiHandle == INVALID_HANDLE)
     {
      Print("Failed to create RSI handle");
      return(INIT_FAILED);
     }

   string startMsg = "🤖 Trading Bot Started\n\n";
   startMsg += "Symbol: " + _Symbol + "\n";
   startMsg += "Timeframe: " + EnumToString(Timeframe) + "\n";
   startMsg += "Magic: " + IntegerToString(InpMagic) + "\n";
   startMsg += "Risk: " + DoubleToString(RiskPercent, 1) + "%\n";
   startMsg += "TP: " + IntegerToString(Tppoints) + " | SL: " + IntegerToString(Slpoints) + "\n";
   startMsg += "Trading Hours: " + IntegerToString(SHInput) + ":00 - " + IntegerToString(EHInput) + ":00";
   datetime exp = StringToTime(ExpirationDate);
   if(TimeCurrent() > exp)
     {
      Alert("❌ License expired");
      return INIT_FAILED;
     }

   SendTelegramMessage(startMsg);

   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   RemoveDashboard();
   if(rsiHandle != INVALID_HANDLE)
      IndicatorRelease(rsiHandle);

   string msg = "🛑 Bot Stopped\n\n";
   msg += "Reason: ";

   switch(reason)
     {
      case REASON_PROGRAM:
         msg += "Program terminated";
         break;
      case REASON_REMOVE:
         msg += "EA removed from chart";
         break;
      case REASON_RECOMPILE:
         msg += "EA recompiled";
         break;
      case REASON_CHARTCHANGE:
         msg += "Symbol/timeframe changed";
         break;
      case REASON_CHARTCLOSE:
         msg += "Chart closed";
         break;
      case REASON_PARAMETERS:
         msg += "Parameters changed";
         break;
      case REASON_ACCOUNT:
         msg += "Account changed";
         break;
      case REASON_TEMPLATE:
         msg += "Template loaded";
         break;
      case REASON_INITFAILED:
         msg += "Initialization failed";
         break;
      case REASON_CLOSE:
         msg += "Terminal closed";
         break;
      default:
         msg += "Unknown (" + IntegerToString(reason) + ")";
     }

   SendTelegramMessage(msg);
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void OnTick()
  {
   TrailStop();
   CheckTradeEvents();
   if(ShowDashboard) RefreshDashboard();

   if(!IsNewBar())
      return;

   MqlDateTime time;
   TimeToStruct(TimeCurrent(), time);
   int Hournow = time.hour;

   SHchoice = SHInput;
   EHChoice = EHInput;

   if(Hournow < SHchoice)
     {
      CloseAllOrders();
      return;
     }
   if(Hournow >= EHChoice && EHChoice != 0)
     {
      CloseAllOrders();
      return;
     }

   int BuyTotal=0;
   int SellTotal=0;

   for(int i = PositionsTotal()-1; i>=0; i--)
     {
      if(pos.SelectByIndex(i))
        {
         if(pos.PositionType()==POSITION_TYPE_BUY && pos.Symbol()==_Symbol && pos.Magic()==InpMagic)
            BuyTotal++;
         if(pos.PositionType()==POSITION_TYPE_SELL && pos.Symbol()==_Symbol && pos.Magic()==InpMagic)
            SellTotal++;
        }
     }

   for(int i = OrdersTotal()-1; i>=0; i--)
     {
      if(ord.SelectByIndex(i))
        {
         if(ord.OrderType()==ORDER_TYPE_BUY_STOP && ord.Symbol()==_Symbol && ord.Magic()==InpMagic)
            BuyTotal++;
         if(ord.OrderType()==ORDER_TYPE_SELL_STOP && ord.Symbol()==_Symbol && ord.Magic()==InpMagic)
            SellTotal++;
        }
     }

   double rsi[];
   ArraySetAsSeries(rsi, true);
   if(CopyBuffer(rsiHandle, 0, 1, 1, rsi) != 1)
     {
      Print("Failed to copy RSI data");
      return;
     }

   double currentRsi = rsi[0];

   if(BuyTotal <= 0 && currentRsi < RSI_Oversold)
     {
      ExecuteMarketBuy();
     }
   if(SellTotal <= 0 && currentRsi > RSI_Overbought)
     {
      ExecuteMarketSell();
     }
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void CheckTradeEvents()
  {
   CheckNewPositions();
   CheckClosedPositions();
   CheckNewOrders();
   CheckDeletedOrders();
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void CheckNewPositions()
  {
   for(int i = PositionsTotal()-1; i>=0; i--)
     {
      if(pos.SelectByIndex(i))
        {
         if(pos.Symbol()==_Symbol && pos.Magic()==InpMagic)
           {
            ulong ticket = pos.Ticket();

            if(!IsPositionTracked(ticket))
              {
               AddTrackedPosition(ticket);

               string msg = "✅ *Trade Opened*\n\n";
               msg += "Symbol: " + pos.Symbol() + "\n";
               msg += "Type: " + (pos.PositionType()==POSITION_TYPE_BUY ? "BUY 🟢" : "SELL 🔴") + "\n";
               msg += "Entry: " + DoubleToString(pos.PriceOpen(), _Digits) + "\n";
               msg += "Lots: " + DoubleToString(pos.Volume(), 2) + "\n";
               msg += "SL: " + DoubleToString(pos.StopLoss(), _Digits) + "\n";
               msg += "TP: " + DoubleToString(pos.TakeProfit(), _Digits) + "\n";
               msg += "Ticket: " + IntegerToString(ticket);

               SendTelegramMessage(msg);
              }
           }
        }
     }
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void CheckClosedPositions()
  {
   for(int i = ArraySize(trackedPositions)-1; i>=0; i--)
     {
      bool found = false;

      for(int j = PositionsTotal()-1; j>=0; j--)
        {
         if(pos.SelectByIndex(j))
           {
            if(pos.Ticket() == trackedPositions[i].ticket)
              {
               found = true;
               break;
              }
           }
        }

      if(!found)
        {
         ulong ticket = trackedPositions[i].ticket;

         if(HistorySelectByPosition(ticket))
           {
            for(int h = HistoryDealsTotal()-1; h>=0; h--)
              {
               ulong dealTicket = HistoryDealGetTicket(h);

               if(HistoryDealGetInteger(dealTicket, DEAL_POSITION_ID) == ticket)
                 {
                  double profit = HistoryDealGetDouble(dealTicket, DEAL_PROFIT);
                  double volume = HistoryDealGetDouble(dealTicket, DEAL_VOLUME);
                  double price = HistoryDealGetDouble(dealTicket, DEAL_PRICE);
                  ENUM_DEAL_REASON reason = (ENUM_DEAL_REASON)HistoryDealGetInteger(dealTicket, DEAL_REASON);

                  string msg = (profit >= 0 ? "💰 *Trade Closed - Profit*\n\n" : "❌ *Trade Closed - Loss*\n\n");
                  msg += "Ticket: " + IntegerToString(ticket) + "\n";
                  msg += "Exit: " + DoubleToString(price, _Digits) + "\n";
                  msg += "Lots: " + DoubleToString(volume, 2) + "\n";
                  msg += "P/L: " + DoubleToString(profit, 2) + " " + AccountInfoString(ACCOUNT_CURRENCY) + "\n";
                  msg += "Reason: " + GetDealReasonText(reason);

                  SendTelegramMessage(msg);
                  break;
                 }
              }
           }

         RemoveTrackedPosition(i);
        }
     }
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void CheckNewOrders()
  {
   for(int i = OrdersTotal()-1; i>=0; i--)
     {
      if(ord.SelectByIndex(i))
        {
         if(ord.Symbol()==_Symbol && ord.Magic()==InpMagic)
           {
            ulong ticket = ord.Ticket();

            if(!IsOrderTracked(ticket))
              {
               AddTrackedOrder(ticket);

               string msg = "📝 *New Pending Order*\n\n";
               msg += "Symbol: " + ord.Symbol() + "\n";
               msg += "Type: " + GetOrderTypeText(ord.OrderType()) + "\n";
               msg += "Entry: " + DoubleToString(ord.PriceOpen(), _Digits) + "\n";
               msg += "Lots: " + DoubleToString(ord.VolumeInitial(), 2) + "\n";
               msg += "SL: " + DoubleToString(ord.StopLoss(), _Digits) + "\n";
               msg += "TP: " + DoubleToString(ord.TakeProfit(), _Digits) + "\n";
               msg += "Expiry: " + TimeToString(ord.TimeExpiration()) + "\n";
               msg += "Ticket: " + IntegerToString(ticket);

               SendTelegramMessage(msg);
              }
           }
        }
     }
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void CheckDeletedOrders()
  {
   for(int i = ArraySize(trackedOrders)-1; i>=0; i--)
     {
      bool found = false;

      for(int j = OrdersTotal()-1; j>=0; j--)
        {
         if(ord.SelectByIndex(j))
           {
            if(ord.Ticket() == trackedOrders[i].ticket)
              {
               found = true;
               break;
              }
           }
        }

      if(!found)
        {
         ulong ticket = trackedOrders[i].ticket;

         string msg = "🗑️ *Order Deleted*\n\n";
         msg += "Ticket: " + IntegerToString(ticket) + "\n";

         if(HistoryOrderSelect(ticket))
           {
            ENUM_ORDER_STATE state = (ENUM_ORDER_STATE)HistoryOrderGetInteger(ticket, ORDER_STATE);
            msg += "Reason: " + GetOrderStateText(state);
           }
         else
           {
            msg += "Reason: Order not found in history";
           }

         SendTelegramMessage(msg);
         RemoveTrackedOrder(i);
        }
     }
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
string GetOrderTypeText(ENUM_ORDER_TYPE type)
  {
   switch(type)
     {
      case ORDER_TYPE_BUY_STOP:
         return "BUY STOP 🟢⬆️";
      case ORDER_TYPE_SELL_STOP:
         return "SELL STOP 🔴⬇️";
      case ORDER_TYPE_BUY_LIMIT:
         return "BUY LIMIT 🟢⬇️";
      case ORDER_TYPE_SELL_LIMIT:
         return "SELL LIMIT 🔴⬆️";
      default:
         return "UNKNOWN";
     }
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
string GetDealReasonText(ENUM_DEAL_REASON reason)
  {
   switch(reason)
     {
      case DEAL_REASON_SL:
         return "Stop Loss";
      case DEAL_REASON_TP:
         return "Take Profit";
      case DEAL_REASON_SO:
         return "Stop Out";
      case DEAL_REASON_EXPERT:
         return "EA Closed";
      default:
         return "Manual/Other";
     }
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
string GetOrderStateText(ENUM_ORDER_STATE state)
  {
   switch(state)
     {
      case ORDER_STATE_CANCELED:
         return "Canceled";
      case ORDER_STATE_EXPIRED:
         return "Expired";
      case ORDER_STATE_FILLED:
         return "Filled";
      case ORDER_STATE_REJECTED:
         return "Rejected";
      default:
         return "Unknown";
     }
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool IsPositionTracked(ulong ticket)
  {
   for(int i=0; i<ArraySize(trackedPositions); i++)
     {
      if(trackedPositions[i].ticket == ticket)
         return true;
     }
   return false;
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool IsOrderTracked(ulong ticket)
  {
   for(int i=0; i<ArraySize(trackedOrders); i++)
     {
      if(trackedOrders[i].ticket == ticket)
         return true;
     }
   return false;
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void AddTrackedPosition(ulong ticket)
  {
   int size = ArraySize(trackedPositions);
   ArrayResize(trackedPositions, size+1);
   trackedPositions[size].ticket = ticket;
   trackedPositions[size].notified = true;
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void AddTrackedOrder(ulong ticket)
  {
   int size = ArraySize(trackedOrders);
   ArrayResize(trackedOrders, size+1);
   trackedOrders[size].ticket = ticket;
   trackedOrders[size].notified = true;
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void RemoveTrackedPosition(int index)
  {
   int size = ArraySize(trackedPositions);
   if(index < 0 || index >= size)
      return;

   for(int i=index; i<size-1; i++)
     {
      trackedPositions[i] = trackedPositions[i+1];
     }
   ArrayResize(trackedPositions, size-1);
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void RemoveTrackedOrder(int index)
  {
   int size = ArraySize(trackedOrders);
   if(index < 0 || index >= size)
      return;

   for(int i=index; i<size-1; i++)
     {
      trackedOrders[i] = trackedOrders[i+1];
     }
   ArrayResize(trackedOrders, size-1);
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void SendTelegramMessage(string text)
  {
   if(TelegramToken == "" || TelegramChatID == "")
     {
      Print("Telegram not configured!");
      return;
     }

   string url = "https://api.telegram.org/bot" + TelegramToken + "/sendMessage";

   string postData = "chat_id=" + TelegramChatID + "&text=" + text + "&parse_mode=Markdown";

   char data[];
   char result[];
   string headers;

   int dataSize = StringToCharArray(postData, data, 0, WHOLE_ARRAY, CP_UTF8) - 1;
   if(dataSize > 0)
      ArrayResize(data, dataSize);

   int res = WebRequest("POST", url, NULL, NULL, 5000, data, ArraySize(data), result, headers);

   if(res == -1)
     {
      Print("WebRequest error: ", GetLastError());
      Print("Enable URL in MT5: Tools -> Options -> Expert Advisors -> Allow WebRequest for URL: https://api.telegram.org");
     }
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool IsNewBar()
  {
   static datetime previousTime = 0;
   datetime currentTime = iTime(_Symbol, Timeframe, 0);
   if(previousTime != currentTime)
     {
      previousTime = currentTime;
      return true;
     }
   return false;
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
double calcLots(double slPoints)
  {
   double risk = AccountInfoDouble(ACCOUNT_BALANCE) * RiskPercent / 100;

   double ticksize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double tickvalue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double loststep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double minvolume = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_MIN);
   double maxvolume = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_MAX);
   double volumelimit = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_LIMIT);

   double moneyPerLotstep = slPoints / ticksize * tickvalue * loststep;
   double lots = MathFloor(risk / moneyPerLotstep) * loststep;

   if(volumelimit != 0)
      lots = MathMin(lots, volumelimit);
   if(maxvolume != 0)
      lots = MathMin(lots, SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX));
   if(minvolume != 0)
      lots = MathMax(lots, SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN));
   lots = NormalizeDouble(lots, 2);

   return lots;
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void CloseAllOrders()
  {
   int deletedCount = 0;

   for(int i = OrdersTotal()-1; i >= 0; i--)
     {
      if(ord.SelectByIndex(i))
        {
         ulong ticket = ord.Ticket();
         if(ord.Symbol() == _Symbol && ord.Magic() == InpMagic)
           {
            if(trade.OrderDelete(ticket))
               deletedCount++;
           }
        }
     }

   if(deletedCount > 0)
     {
      string msg = "🔔 Trading Hours Ended\n\n";
      msg += "Orders Deleted: " + IntegerToString(deletedCount);
      SendTelegramMessage(msg);
     }
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void TrailStop()
  {
   double sl = 0;
   double tp = 0;

   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   for(int i=PositionsTotal()-1; i>=0; i--)
     {
      if(pos.SelectByIndex(i))
        {
         ulong ticket = pos.Ticket();

         if(pos.Magic()==InpMagic && pos.Symbol()==_Symbol)
           {
            if(pos.PositionType()==POSITION_TYPE_BUY)
              {
               if(bid-pos.PriceOpen()>TslTriggerPoints*_Point)
                 {
                  tp=pos.TakeProfit();
                  sl=bid-(TslPoints*_Point);

                  if(sl > pos.StopLoss() && sl!=0)
                    {
                     if(trade.PositionModify(ticket, sl, tp))
                       {
                        string msg = "🔄 *Trailing Stop Activated*\n\n";
                        msg += "Ticket: " + IntegerToString(ticket) + "\n";
                        msg += "New SL: " + DoubleToString(sl, _Digits);
                        SendTelegramMessage(msg);
                       }
                    }
                 }
              }
            else
               if(pos.PositionType()==POSITION_TYPE_SELL)
                 {
                  if(ask+(TslTriggerPoints*_Point)<pos.PriceOpen())
                    {
                     tp = pos.TakeProfit();
                     sl = ask + (TslPoints * _Point);
                     if(sl<pos.StopLoss() && sl!=0)
                       {
                        if(trade.PositionModify(ticket,sl,tp))
                          {
                           string msg = "🔄 *Trailing Stop Activated*\n\n";
                           msg += "Ticket: " + IntegerToString(ticket) + "\n";
                           msg += "New SL: " + DoubleToString(sl, _Digits);
                           SendTelegramMessage(msg);
                          }
                       }
                    }
                 }
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
   int bh = 320;

   DashRect("BORDER",  bx-1,  by-1,  bw+2,  bh+2,  GOLD_BORDER,  GOLD_BORDER);
   DashRect("BG",      bx,    by,    bw,    bh,    GOLD_DEEP,    GOLD_BORDER);
   DashRect("HDR_BG",  bx,    by,    bw,    28,    GOLD_HDR_BG,  GOLD_HDR_BG);
   DashRect("HDR_LN",  bx,    by+28, bw,    2,     GOLD_HDR_LINE, GOLD_HDR_LINE);

   DashRect("SEC_MKT",  bx+2, by+32,  bw-4, 70,  GOLD_SECTION, GOLD_SECTION);
   DashRect("SEP_LN1",  bx+6, by+104, bw-12, 1,  GOLD_MID,     GOLD_MID);
   DashRect("SEC_ACC",  bx+2, by+107, bw-4, 70,  GOLD_SECTION, GOLD_SECTION);
   DashRect("SEP_LN2",  bx+6, by+179, bw-12, 1,  GOLD_MID,     GOLD_MID);
   DashRect("SEC_GRD",  bx+2, by+182, bw-4, 70,  GOLD_SECTION, GOLD_SECTION);
   DashRect("SEP_LN3",  bx+6, by+254, bw-12, 1,  GOLD_MID,     GOLD_MID);
   DashRect("SEC_INF",  bx+2, by+257, bw-4, 58,  GOLD_SECTION, GOLD_SECTION);

   DashLabel("TitleTxt", "✦  RSI TRADING BOT  ✦",
             bx+40, by+7,  10, GOLD_SHIMMER, "Georgia");

   DashLabel("SH_MKT",  "MARKET",   bx+6, by+33,  6, GOLD_MID, "Consolas");
   DashLabel("SH_ACC",  "ACCOUNT",  bx+6, by+108, 6, GOLD_MID, "Consolas");
   DashLabel("SH_TRD",  "TRADING",  bx+6, by+183, 6, GOLD_MID, "Consolas");
   DashLabel("SH_INF",  "INFO",     bx+6, by+258, 6, GOLD_MID, "Consolas");

   int lx = bx + 10;

   DashLabel("L_SYM",   "Symbol  :",  lx, by+42,  8, GOLD_PARCHMENT, "Consolas");
   DashLabel("L_BID",   "Bid     :",  lx, by+56,  8, GOLD_PARCHMENT, "Consolas");
   DashLabel("L_ASK",   "Ask     :",  lx, by+70,  8, GOLD_PARCHMENT, "Consolas");
   DashLabel("L_SPR",   "Spread  :",  lx, by+84,  8, GOLD_PARCHMENT, "Consolas");

   DashLabel("L_BAL",   "Balance :",  lx, by+117, 8, GOLD_PARCHMENT, "Consolas");
   DashLabel("L_EQ",    "Equity  :",  lx, by+131, 8, GOLD_PARCHMENT, "Consolas");
   DashLabel("L_FR",    "Free Mrg:",  lx, by+145, 8, GOLD_PARCHMENT, "Consolas");
   DashLabel("L_PNL",   "Open P&L:",  lx, by+159, 8, GOLD_PARCHMENT, "Consolas");

   DashLabel("L_BBUY",  "Buy Pos :",  lx, by+192, 8, GOLD_PARCHMENT, "Consolas");
   DashLabel("L_SSELL", "Sell Pos:",  lx, by+206, 8, GOLD_PARCHMENT, "Consolas");
   DashLabel("L_MAGIC", "Magic # :",  lx, by+220, 8, GOLD_PARCHMENT, "Consolas");
   DashLabel("L_RISK",  "Risk %  :",  lx, by+234, 8, GOLD_PARCHMENT, "Consolas");

   DashLabel("L_HOURS", "Hours   :",  lx, by+267, 8, GOLD_PARCHMENT, "Consolas");
   DashLabel("L_EXP",   "License :",  lx, by+281, 8, GOLD_PARCHMENT, "Consolas");
   DashLabel("L_COMM",  "Comment :",  lx, by+295, 8, GOLD_PARCHMENT, "Consolas");

   ChartRedraw(0);
  }

void RefreshDashboard()
  {
   double bid    = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask    = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double spread = (ask - bid) / _Point;

   double balance    = AccountInfoDouble(ACCOUNT_BALANCE);
   double equity     = AccountInfoDouble(ACCOUNT_EQUITY);
   double freeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);

   int BuyTotal=0;
   int SellTotal=0;
   double openPnl = 0;

   for(int i = PositionsTotal()-1; i>=0; i--)
     {
      if(pos.SelectByIndex(i))
        {
         if(pos.Symbol()==_Symbol && pos.Magic()==InpMagic)
           {
            if(pos.PositionType()==POSITION_TYPE_BUY) BuyTotal++;
            if(pos.PositionType()==POSITION_TYPE_SELL) SellTotal++;
            openPnl += pos.Profit() + pos.Swap() + pos.Commission();
           }
        }
     }

   int vx = DashX + 128;
   int by = DashY;

   DashLabel("V_SYM",  _Symbol,                             vx, by+42,  8, GOLD_SHIMMER,   "Consolas");
   DashLabel("V_BID",  DoubleToString(bid, _Digits),        vx, by+56,  8, GOLD_PARCHMENT, "Consolas");
   DashLabel("V_ASK",  DoubleToString(ask, _Digits),        vx, by+70,  8, GOLD_PARCHMENT, "Consolas");
   DashLabel("V_SPR",  DoubleToString(spread, 1) + " pts",  vx, by+84,  8, GOLD_PARCHMENT, "Consolas");

   DashLabel("V_BAL",  DoubleToString(balance,    2),       vx, by+117, 8, GOLD_SHIMMER,   "Consolas");
   DashLabel("V_EQ",   DoubleToString(equity,     2),       vx, by+131, 8, GOLD_PARCHMENT, "Consolas");
   DashLabel("V_FR",   DoubleToString(freeMargin, 2),       vx, by+145, 8, GOLD_PARCHMENT, "Consolas");
   DashLabel("V_PNL",  DoubleToString(openPnl,   2),        vx, by+159, 8, (openPnl>=0?GOLD_GREEN:GOLD_RED), "Consolas");

   DashLabel("V_BBUY",  IntegerToString(BuyTotal),          vx, by+192, 8, GOLD_GREEN,     "Consolas");
   DashLabel("V_SSELL", IntegerToString(SellTotal),         vx, by+206, 8, GOLD_RED,       "Consolas");
   DashLabel("V_MAGIC", IntegerToString(InpMagic),          vx, by+220, 8, GOLD_PARCHMENT, "Consolas");
   DashLabel("V_RISK",  DoubleToString(RiskPercent, 1)+"%", vx, by+234, 8, GOLD_PARCHMENT, "Consolas");

   string hours = IntegerToString(SHInput)+":00-"+IntegerToString(EHInput)+":00";
   DashLabel("V_HOURS", hours,                              vx, by+267, 8, GOLD_PARCHMENT, "Consolas");
   DashLabel("V_EXP",   ExpirationDate,                     vx, by+281, 8, GOLD_PARCHMENT, "Consolas");
   DashLabel("V_COMM",  TradeComment,                       vx, by+295, 8, GOLD_PARCHMENT, "Consolas");

   ChartRedraw(0);
  }

void RemoveDashboard()
  {
   ObjectsDeleteAll(0, DASH_PFX);
   ChartRedraw(0);
  }
//+------------------------------------------------------------------+
