//+------------------------------------------------------------------+
//| ProjectName RSI Scalping Bot                                     |
//| Copyright 2026, CompanyName                                      |
//| http://www.companyname.net                                       |
//+------------------------------------------------------------------+
#include <Trade/Trade.mqh>

// RSI Parameters from user
input group "=== RSI Settings ==="
input int RSI_Period = 6;
input ENUM_APPLIED_PRICE RSI_AppliedPrice = PRICE_WEIGHTED;
input double RSI_Level_High = 85.0;
input double RSI_Level_Mid  = 0.0;
input double RSI_Level_Low  = 16.0;

int rsiHandle = INVALID_HANDLE;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
   rsiHandle = iRSI(_Symbol, _Period, RSI_Period, RSI_AppliedPrice);
   if(rsiHandle == INVALID_HANDLE)
     {
      Print("Failed to create RSI handle");
      return(INIT_FAILED);
     }
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
   // Logic to be added by user instruction
  }
//+------------------------------------------------------------------+
