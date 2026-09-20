import hashlib
import hmac
import json
import os
import time
from urllib.parse import urlencode

import requests
from groq import Groq

SYMBOL = os.getenv("SYMBOL", "BTCUSDT").upper()
QUOTE_AMOUNT = float(os.getenv("QUOTE_AMOUNT", "5"))
MAX_POSITION_USDT = float(os.getenv("MAX_POSITION_USDT", "5"))
RISK_PER_TRADE_PCT = float(os.getenv("RISK_PER_TRADE_PCT", "0.5"))
MAX_DAILY_LOSS_PCT = float(os.getenv("MAX_DAILY_LOSS_PCT", "2"))
MAX_TRADES_PER_DAY = int(os.getenv("MAX_TRADES_PER_DAY", "3"))
GROQ_MODEL = os.getenv("GROQ_MODEL", "openai/gpt-oss-120b")

LIVE_TRADING = (
    os.getenv("LIVE_TRADING", "false").lower() == "true"
    and os.getenv("ENABLE_LIVE_TRADING", "") == "I_UNDERSTAND"
)

BINANCE_API_KEY = os.getenv("BINANCE_API_KEY", "")
BINANCE_API_SECRET = os.getenv("BINANCE_API_SECRET", "")
BINANCE_BASE = os.getenv("BINANCE_BASE", "https://api.binance.com").rstrip("/")
groq = Groq(api_key=os.environ["GROQ_API_KEY"])


def candles():
    end = int(time.time())
    start = end - 200 * 300
    r = requests.get(
        "https://api.exchange.coinbase.com/products/BTC-USD/candles",
        params={
            "granularity": 300,
            "start": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(start)),
            "end": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(end)),
        },
        headers={"User-Agent": "Velo-Trading-Bot/1.0"},
        timeout=15,
    )
    r.raise_for_status()
    rows = r.json()
    if not isinstance(rows, list) or len(rows) < 60:
        raise RuntimeError("Not enough 5-minute BTC candles")
    return sorted(
        [
            {
                "time": int(x[0]),
                "low": float(x[1]),
                "high": float(x[2]),
                "open": float(x[3]),
                "close": float(x[4]),
                "volume": float(x[5]),
            }
            for x in rows
        ],
        key=lambda x: x["time"],
    )


def ema(values, period):
    k = 2 / (period + 1)
    e = values[0]
    for value in values[1:]:
        e = value * k + e * (1 - k)
    return e


def rsi(values, period=14):
    gains, losses = [], []
    for i in range(1, len(values)):
        d = values[i] - values[i - 1]
        gains.append(max(d, 0))
        losses.append(max(-d, 0))
    avg_gain = sum(gains[:period]) / period
    avg_loss = sum(losses[:period]) / period
    for i in range(period, len(gains)):
        avg_gain = (avg_gain * (period - 1) + gains[i]) / period
        avg_loss = (avg_loss * (period - 1) + losses[i]) / period
    return 100 if avg_loss == 0 else 100 - (100 / (1 + avg_gain / avg_loss))


def atr(rows, period=14):
    tr = []
    for i in range(1, len(rows)):
        tr.append(
            max(
                rows[i]["high"] - rows[i]["low"],
                abs(rows[i]["high"] - rows[i - 1]["close"]),
                abs(rows[i]["low"] - rows[i - 1]["close"]),
            )
        )
    value = sum(tr[:period]) / period
    for item in tr[period:]:
        value = (value * (period - 1) + item) / period
    return value


def market_summary():
    rows = candles()
    closes = [x["close"] for x in rows]
    price = closes[-1]
    ema20 = ema(closes[-100:], 20)
    ema50 = ema(closes[-150:], 50)
    rsi14 = rsi(closes)
    atr14 = atr(rows)
    atr_pct = atr14 / price * 100

    trend_up = ema20 > ema50 and price > ema20
    momentum_ok = 52 <= rsi14 <= 68
    volatility_ok = 0.05 <= atr_pct <= 1.5
    deterministic_buy = trend_up and momentum_ok and volatility_ok

    return {
        "symbol": SYMBOL,
        "timeframe": "5m",
        "price": price,
        "ema20": ema20,
        "ema50": ema50,
        "rsi14": rsi14,
        "atr14": atr14,
        "atr_pct": atr_pct,
        "trend_up": trend_up,
        "momentum_ok": momentum_ok,
        "volatility_ok": volatility_ok,
        "deterministic_action": "BUY" if deterministic_buy else "HOLD",
        "stop_loss": price - 1.5 * atr14,
        "take_profit": price + 3 * atr14,
        "risk_reward": "1:2",
        "source": "Coinbase Exchange BTC-USD",
    }


def groq_decision(summary):
    prompt = f"""You are a conservative crypto trading confirmation engine.
The deterministic strategy already calculated the signal below.

Return ONLY JSON:
{{"confirm":"BUY|HOLD","confidence":0-100,"reason":"short reason"}}

Confirm BUY only when the deterministic signal is strong. Never override risk rules.
Do not invent data.

Signal:
{json.dumps(summary)}
"""
    response = groq.chat.completions.create(
        model=GROQ_MODEL,
        temperature=0,
        messages=[
            {"role": "system", "content": "Return strict JSON only."},
            {"role": "user", "content": prompt},
        ],
    )
    return json.loads(response.choices[0].message.content.strip())


def signed_request(method, path, params=None):
    if not BINANCE_API_KEY or not BINANCE_API_SECRET:
        raise RuntimeError("BINANCE_API_KEY and BINANCE_API_SECRET are required.")
    params = dict(params or {})
    params["timestamp"] = int(time.time() * 1000)
    query = urlencode(params, doseq=True)
    signature = hmac.new(
        BINANCE_API_SECRET.encode(), query.encode(), hashlib.sha256
    ).hexdigest()
    headers = {"X-MBX-APIKEY": BINANCE_API_KEY}
    response = requests.request(
        method,
        f"{BINANCE_BASE}{path}?{query}&signature={signature}",
        headers=headers,
        timeout=15,
    )
    response.raise_for_status()
    return response.json()


def execute(action, price):
    if QUOTE_AMOUNT <= 0 or QUOTE_AMOUNT > MAX_POSITION_USDT:
        return "blocked: position limit"
    if not LIVE_TRADING:
        return f"PAPER {action} @ {price:.2f} (no real order sent)"
    return "LIVE execution intentionally disabled in this build"


def main():
    summary = market_summary()
    ai = groq_decision(summary)
    final_action = (
        "BUY"
        if summary["deterministic_action"] == "BUY"
        and ai.get("confirm") == "BUY"
        and float(ai.get("confidence", 0)) >= 70
        else "HOLD"
    )
    output = {
        "market": summary,
        "ai_confirmation": ai,
        "final_action": final_action,
        "risk": {
            "risk_per_trade_pct": RISK_PER_TRADE_PCT,
            "max_daily_loss_pct": MAX_DAILY_LOSS_PCT,
            "max_trades_per_day": MAX_TRADES_PER_DAY,
            "leverage": 0,
            "execution": "disabled",
        },
    }
    print(json.dumps(output, indent=2))
    print(execute(final_action, summary["price"]) if final_action == "BUY" else "HOLD: filters not satisfied")


if __name__ == "__main__":
    main()
