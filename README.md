# RSI Scalping Bot

A high-frequency scalping robot for MetaTrader 5 based on RSI levels and price action patterns (Wicks, Dojis, and Fair Value Gaps).

## Strategy Overview

The bot monitors the RSI indicator (Period 6, Weighted Close) to identify overbought (Sell) and oversold (Buy) zones. When the price is in these zones, it looks for specific "confirmation" signals to enter trades.

### Entry Zones
- **Buy Zone**: RSI <= 16
- **Sell Zone**: RSI >= 85

### Signal Types (Configurable)
The bot includes 8 specific signal detection types that can be enabled or disabled in the inputs:

1. **Long Wick Signal**: A candle wick of at least 100 pips pointing in the direction of the trade (lower wick for Buy, upper wick for Sell).
2. **RSI Extreme + Doji**: RSI reaches 91 (Sell) or 8 (Buy) combined with a Doji candle.
3. **Doji + Large FVG**: A Doji candle accompanied by an adjacent Fair Value Gap (FVG) of at least 50 pips.
4. **Doji + Double FVG**: A Doji candle accompanied by two consecutive FVGs of at least 20 pips each.
5. **Doji + Recent FVG**: A Doji candle with an FVG of at least 54 pips occurring within the previous 4 candles.
6. **RSI Extreme + Medium Wick**: RSI reaches 91 (Sell) or 8 (Buy) combined with a wick of at least 41 pips.
7. **Doji + Medium Wick**: A Doji candle with a wick of at least 55 pips.
8. **RSI Ultimate Extreme**: RSI reaches 95 (Sell) or 5 (Buy).

## Trade Management

- **TP/SL**: Fixed at 150 pips each.
- **Trades Per Signal**: Configure how many individual positions to open when a signal is detected.
- **Max Total Trades**: Total limit of concurrent open positions.
- **Signal Filtering**: If any trades are already open, new signals are ignored until all current trades are closed.

## Installation

1. Copy `RSI_Trading_Bot.mq5` to your MetaTrader 5 `MQL5/Experts` folder.
2. Compile the file in MetaEditor.
3. Attach the Expert Advisor to your desired chart.
4. Ensure "Algo Trading" is enabled in your MetaTrader 5 terminal.

## Parameters

| Parameter | Description |
|-----------|-------------|
| RSI_Period | Period for the RSI indicator (Default: 6) |
| RSI_AppliedPrice | Price type for RSI calculation (Default: Weighted) |
| SL_Pips | Stop Loss in pips (Default: 150) |
| TP_Pips | Take Profit in pips (Default: 150) |
| TradesPerSignal | Number of trades to open per signal |
| MaxTotalTrades | Maximum allowed concurrent trades |
| Enable_Signal_1-8 | Toggle switches for each signal type |
