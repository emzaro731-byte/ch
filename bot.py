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
STOP_LOSS_PCT = float(os.getenv("STOP_LOSS_PCT", "2"))
TAKE_PROFIT_PCT = float(os.getenv("TAKE_PROFIT_PCT", "3"))
GROQ_MODEL = os.getenv("GROQ_MODEL", "llama-3.3-70b-versatile")

# Safety: live trading requires an explicit two-part opt-in.
LIVE_TRADING = (
    os.getenv("LIVE_TRADING", "false").lower() == "true"
    and os.getenv("ENABLE_LIVE_TRADING", "") == "I_UNDERSTAND"
)

BINANCE_API_KEY = os.getenv("BINANCE_API_KEY", "")
BINANCE_API_SECRET = os.getenv("BINANCE_API_SECRET", "")
BINANCE_BASE = os.getenv("BINANCE_BASE", "https://api.binance.com").rstrip("/")

groq = Groq(api_key=os.environ["GROQ_API_KEY"])


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

    return {
        "symbol": SYMBOL,
        "price": current,
        "sma20": sma(20),
        "sma50": sma(50),
        "change_20_candles_pct": (current / closes[-21] - 1) * 100,
    }


def groq_decision(summary):
    prompt = f"""You are a conservative crypto trading analysis engine.
Analyze this 5-minute market snapshot: {json.dumps(summary)}.

Return ONLY valid JSON:
{{"action":"BUY|SELL|HOLD","confidence":0-100,"reason":"short reason"}}

Do not invent prices, news, balances, or indicators. Prefer HOLD when evidence is weak.
The program, not the model, controls risk and order permissions."""

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
    url = f"{BINANCE_BASE}{path}?{query}&signature={signature}"
    response = requests.request(method, url, headers=headers, timeout=15)
    response.raise_for_status()
    return response.json()


def account_balance(asset):
    data = signed_request("GET", "/api/v3/account", {"recvWindow": 5000})
    for item in data.get("balances", []):
        if item["asset"] == asset:
            return float(item["free"])
    return 0.0


def market_buy(quote_amount):
    # Uses quoteOrderQty so the bot spends at most the configured USDT amount.
    return signed_request(
        "POST",
        "/api/v3/order",
        {
            "symbol": SYMBOL,
            "side": "BUY",
            "type": "MARKET",
            "quoteOrderQty": f"{quote_amount:.8f}",
            "newOrderRespType": "FULL",
            "recvWindow": 5000,
        },
    )


def market_sell(quantity):
    return signed_request(
        "POST",
        "/api/v3/order",
        {
            "symbol": SYMBOL,
            "side": "SELL",
            "type": "MARKET",
            "quantity": f"{quantity:.8f}",
            "newOrderRespType": "FULL",
            "recvWindow": 5000,
        },
    )


def execute(action, price):
    if QUOTE_AMOUNT <= 0 or QUOTE_AMOUNT > MAX_POSITION_USDT:
        return "blocked: QUOTE_AMOUNT exceeds configured position limit"

    if not LIVE_TRADING:
        return f"PAPER {action} @ {price:.2f} (no real order sent)"

    if action == "BUY":
        result = market_buy(QUOTE_AMOUNT)
        return f"LIVE BUY submitted: orderId={result.get('orderId')}"

    if action == "SELL":
        base_asset = SYMBOL.removesuffix("USDT")
        qty = account_balance(base_asset)
        if qty <= 0:
            return f"blocked: no free {base_asset} balance to sell"
        result = market_sell(qty)
        return f"LIVE SELL submitted: orderId={result.get('orderId')}"

    return "no trade"


def main():
    summary = market_summary()
    price = summary["price"]
    decision = groq_decision(summary)

    action = decision.get("action")
    confidence = float(decision.get("confidence", 0))

    if action not in {"BUY", "SELL", "HOLD"}:
        raise ValueError("Groq returned an invalid action")

    print(json.dumps({
        "market": summary,
        "decision": decision,
        "mode": "LIVE" if LIVE_TRADING else "PAPER",
    }, indent=2))

    if action in {"BUY", "SELL"} and confidence >= 65:
        print(execute(action, price))
    else:
        print("HOLD: no trade threshold met")


if __name__ == "__main__":
    main()
