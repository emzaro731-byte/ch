# Groq Binance Trading Bot

A small Python crypto **paper-trading bot** using Binance market data and Groq for structured trade analysis.

## Safety first
- Paper trading is enabled by default.
- Live orders are disabled unless `LIVE_TRADING=true`.
- Never give the Binance API key withdrawal permission.
- Store secrets only in GitHub Actions Secrets.

## Setup
1. Add `GROQ_API_KEY` to GitHub Secrets.
2. Optionally add `BINANCE_API_KEY` and `BINANCE_API_SECRET` for authenticated account access.
3. Run locally with Python 3.11+:
```bash
pip install -r requirements.txt
python bot.py
```

## Configuration
Environment variables:
- `SYMBOL=BTCUSDT`
- `QUOTE_AMOUNT=5` (USDT per trade in paper mode)
- `LIVE_TRADING=false`
- `MAX_POSITION_USDT=5`
- `STOP_LOSS_PCT=2`
- `TAKE_PROFIT_PCT=3`
- `GROQ_MODEL=llama-3.3-70b-versatile`

This bot is experimental software, not financial advice, and does not guarantee profit.
