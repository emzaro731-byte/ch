# Groq + Binance Trading Bot

A Python crypto trading bot that uses Groq for market analysis and Binance Spot API for optional order execution.

## Default safety mode

**Paper trading is ON by default.** No real Binance order is sent unless BOTH are set:

- `LIVE_TRADING=true`
- `ENABLE_LIVE_TRADING=I_UNDERSTAND`

The Binance API key should have only the permissions required for Spot trading. Do **not** enable withdrawals. Binance documents API keys and the separate `TRADE` permission in its Spot API documentation.

## GitHub Secrets

In **Settings → Secrets and variables → Actions**, create:

- `GROQ_API_KEY`
- `BINANCE_API_KEY`
- `BINANCE_API_SECRET`

Never commit these values to the repository.

## Bot settings

- `SYMBOL=BTCUSDT`
- `QUOTE_AMOUNT=5`
- `MAX_POSITION_USDT=5`
- `STOP_LOSS_PCT=2`
- `TAKE_PROFIT_PCT=3`
- `LIVE_TRADING=false`

The starter bot intentionally keeps live trading disabled in GitHub Actions. Test paper mode first and review the logs.

## Local test

```bash
pip install -r requirements.txt
export GROQ_API_KEY="your-key"
python bot.py
```

This software is experimental and does not guarantee profit or prevent losses.
