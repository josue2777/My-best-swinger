# Multi-Bot Trading Suite for MT5

This repository contains three independent, high-performance MetaTrader 5 Expert Advisors (EAs) designed for different market conditions.

## 1. RSI Scalping Bot (`RSI_Trading_Bot.mq5`)

A precision scalping robot based on Relative Strength Index (RSI) levels and complex price action patterns.

- **Core Strategy**: Identifies overbought/oversold zones (85/16) and triggers on specific candle confirmations (Wicks, Dojis, Fair Value Gaps).
- **Inverted Execution**: Buys on Sell signals and Sells on Buy signals for mean-reversion.
- **Risk Management**: Dynamic lot sizing at 1% of capital per signal.
- **Signal Toggles**: 8 distinct signal types that can be individually enabled/disabled.

## 2. SD HA Supertrend Bot (`SD_HA_Bot.mq5`)

An trend-following EA based on Heikin Ashi candles and the Supertrend indicator.

- **Core Strategy**: Uses Heikin Ashi smoothing to filter noise and follows the Supertrend direction.
- **Close & Reverse**: Automatically closes opposite positions when the trend flips.
- **Risk Management**: 1% capital risk management.

## 3. Asia Range Breakout Bot (`AsiaRange_Breakout_EA.mq5`)

A hybrid Expert Advisor and Indicator focused on the Asian session breakout.

- **Core Strategy**: Captures the high/low of the Asia session (default 21:45 - 22:15) and trades the breakout.
- **Dual Mode**: Provides visual on-chart analysis (range boxes, signal arrows) while executing trades automatically.
- **Targets**: Optimized for high-probability TP2 targets.
- **Features**: Breakeven management and forced end-of-day closure.

---

## Installation & Setup

1. Copy the `.mq5` files to your MetaTrader 5 `MQL5/Experts` directory.
2. Compile the files in MetaEditor.
3. Drag the desired bot onto your chart.
4. Ensure **Algo Trading** is enabled in MT5.
5. In the bot inputs, configure your preferred risk and magic numbers.

## Risk Warning
Trading involves significant risk. Always test these bots on a demo account before using live capital.
