import json
import os
import time
from dataclasses import dataclass
from typing import Literal

import requests
from groq import Groq

SYMBOL = os.getenv("SYMBOL", "BTCUSDT").upper()
QUOTE_AMOUNT = float(os.getenv("QUOTE_AMOUNT", "5"))
LIVE_TRADING = os.getenv("LIVE_TRADING", "false").lower() == "true"
MAX_POSITION_USDT = float(os.getenv("MAX_POSITION_USDT", "5"))
STOP_LOSS_PCT = float(os.getenv("STOP_LOSS_PCT", "2"))
TAKE_PROFIT_PCT = float(os.getenv("TAKE_PROFIT_PCT", "3"))
GROQ_MODEL = os.getenv("GROQ_MODEL", "llama-3.3-70b-versatile")

BINANCE_BASE = "https://api.binance.com"
client = Groq(api_key=os.environ["GROQ_API_KEY"])


@dataclass
class Position:
    qty: float = 0.0
    entry: float = 0.0


position = Position()


def candles(limit=100):
    r = requests.get(
        f"{BINANCE_BASE}/api/v3/klines",
        params={"symbol": SYMBOL, "interval": "5m", "limit": limit},
        timeout=15,
    )
    r.raise_for_status()
    return r.json()


def market_summary():
    data = candles()
    closes = [float(x[4]) for x in data]
    current = closes[-1]

    def sma(n):
        return sum(closes[-n:]) / n

    sma20 = sma(20)
    sma50 = sma(50)
    change_20 = (current / closes[-21] - 1) * 100

    return {
        "symbol": SYMBOL,
        "price": current,
        "sma20": sma20,
        "sma50": sma50,
        "change_20_candles_pct": change_20,
    }


def groq_decision(summary):
    prompt = f"""You are a conservative crypto trading analysis engine.
Analyze this 5-minute market snapshot: {json.dumps(summary)}.

Return ONLY valid JSON with:
{{"action":"BUY|SELL|HOLD","confidence":0-100,"reason":"short reason"}}

Do not invent prices or news. Prefer HOLD when evidence is weak.
This is analysis only; risk controls in the program decide whether an order is allowed."""

    response = client.chat.completions.create(
        model=GROQ_MODEL,
        temperature=0,
        messages=[
            {"role": "system", "content": "Return strict JSON only."},
            {"role": "user", "content": prompt},
        ],
    )
    raw = response.choices[0].message.content.strip()
    return json.loads(raw)


def execute(action, price):
    global position

    if action == "BUY" and position.qty == 0:
        qty = QUOTE_AMOUNT / price
        if QUOTE_AMOUNT > MAX_POSITION_USDT:
            return "blocked: position limit"
        if LIVE_TRADING:
            return "LIVE order not implemented in this starter build; paper mode required."
        position = Position(qty=qty, entry=price)
        return f"PAPER BUY {qty:.8f} {SYMBOL} @ {price:.2f}"

    if action == "SELL" and position.qty > 0:
        pnl = (price - position.entry) * position.qty
        if LIVE_TRADING:
            return "LIVE order not implemented in this starter build; paper mode required."
        position = Position()
        return f"PAPER SELL @ {price:.2f}; PnL={pnl:.4f} USDT"

    return "no trade"


def risk_exit(price):
    if position.qty == 0:
        return None
    change = (price / position.entry - 1) * 100
    if change <= -STOP_LOSS_PCT:
        return "SELL"
    if change >= TAKE_PROFIT_PCT:
        return "SELL"
    return None


def main():
    summary = market_summary()
    price = summary["price"]

    forced = risk_exit(price)
    decision = {"action": forced, "confidence": 100, "reason": "risk exit"} if forced else groq_decision(summary)

    print(json.dumps({
        "market": summary,
        "decision": decision,
        "mode": "LIVE" if LIVE_TRADING else "PAPER",
    }, indent=2))

    if decision["action"] not in {"BUY", "SELL", "HOLD"}:
        raise ValueError("Invalid Groq action")

    if decision["confidence"] >= 65 or forced:
        print(execute(decision["action"], price))
    else:
        print("HOLD: confidence below threshold")


if __name__ == "__main__":
    main()
