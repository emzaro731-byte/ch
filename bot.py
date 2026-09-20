import json
import math
import os
import time
from datetime import datetime, timezone

import requests
from groq import Groq

MARKET = os.getenv("MARKET", "crypto").lower()
SYMBOL = os.getenv("SYMBOL", "BTCUSDT").upper()
PRODUCT = os.getenv("PRODUCT", "BTC-USD")
FOREX_PAIRS = [x.strip().upper() for x in os.getenv(
    "FOREX_PAIRS", "EURUSD,GBPUSD,USDJPY,AUDUSD,USDCAD,USDCHF,NZDUSD"
).split(",") if x.strip()]

QUOTE_AMOUNT = float(os.getenv("QUOTE_AMOUNT", "5"))
MAX_POSITION_USDT = float(os.getenv("MAX_POSITION_USDT", "5"))
RISK_PER_TRADE_PCT = float(os.getenv("RISK_PER_TRADE_PCT", "0.5"))
MAX_DAILY_LOSS_PCT = float(os.getenv("MAX_DAILY_LOSS_PCT", "2"))
MAX_TRADES_PER_DAY = int(os.getenv("MAX_TRADES_PER_DAY", "3"))
MIN_SIGNAL_SCORE = float(os.getenv("MIN_SIGNAL_SCORE", "75"))
MIN_AI_CONFIDENCE = float(os.getenv("MIN_AI_CONFIDENCE", "75"))
MAX_SPREAD_PCT = float(os.getenv("MAX_SPREAD_PCT", "0.20"))
FEE_PCT = float(os.getenv("FEE_PCT", "0.10"))
SLIPPAGE_PCT = float(os.getenv("SLIPPAGE_PCT", "0.05"))
GROQ_MODEL = os.getenv("GROQ_MODEL", "openai/gpt-oss-120b")

# Safety-first: this build never sends live orders.
LIVE_TRADING = False
groq = Groq(api_key=os.environ["GROQ_API_KEY"])


def forex_yahoo_symbol(pair):
    if len(pair) != 6:
        raise ValueError(f"Invalid forex pair: {pair}")
    return f"{pair[:3]}{pair[3:]}=X"


def fetch_candles(product=PRODUCT, granularity=300, count=200):
    """Crypto OHLCV from Coinbase."""
    end = int(time.time())
    start = end - count * granularity
    r = requests.get(
        f"https://api.exchange.coinbase.com/products/{product}/candles",
        params={
            "granularity": granularity,
            "start": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(start)),
            "end": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(end)),
        },
        headers={"User-Agent": "Veylola-Trade-Bot/5.0"},
        timeout=15,
    )
    r.raise_for_status()
    raw = r.json()
    if not isinstance(raw, list) or len(raw) < min(80, count):
        raise RuntimeError(f"Not enough candles for {product} {granularity}s")
    rows = sorted([{
        "time": int(x[0]), "low": float(x[1]), "high": float(x[2]),
        "open": float(x[3]), "close": float(x[4]), "volume": float(x[5])
    } for x in raw], key=lambda x: x["time"])
    return rows[:-1] if len(rows) > 80 else rows


def fetch_forex_candles(pair, interval="5m", count=200):
    """Public Yahoo Finance market data for forex analysis only."""
    symbol = forex_yahoo_symbol(pair)
    range_map = {"5m": "5d", "1h": "1mo"}
    if interval not in range_map:
        raise ValueError("Unsupported forex interval")
    r = requests.get(
        f"https://query1.finance.yahoo.com/v8/finance/chart/{symbol}",
        params={"range": range_map[interval], "interval": interval, "events": "history"},
        headers={"User-Agent": "Veylola-Trade-Bot/5.0"},
        timeout=15,
    )
    r.raise_for_status()
    data = r.json()["chart"]["result"][0]
    timestamps = data.get("timestamp") or []
    quote = data["indicators"]["quote"][0]
    rows = []
    for i, ts in enumerate(timestamps):
        if quote["open"][i] is None or quote["high"][i] is None or quote["low"][i] is None or quote["close"][i] is None:
            continue
        rows.append({
            "time": int(ts),
            "low": float(quote["low"][i]),
            "high": float(quote["high"][i]),
            "open": float(quote["open"][i]),
            "close": float(quote["close"][i]),
            "volume": float(quote.get("volume", [0] * len(timestamps))[i] or 0),
        })
    if len(rows) < 80:
        raise RuntimeError(f"Not enough forex candles for {pair} {interval}")
    return rows[:-1]


def get_market_candles(symbol, interval="5m", count=200):
    if MARKET == "forex":
        return fetch_forex_candles(symbol, interval, count)
    granularity = 300 if interval == "5m" else 3600
    return fetch_candles(PRODUCT, granularity, count)


def ema(values, period):
    if len(values) < period:
        raise ValueError(f"Need at least {period} values")
    k = 2 / (period + 1)
    value = values[0]
    for item in values[1:]:
        value = item * k + value * (1 - k)
    return value


def rsi(values, period=14):
    if len(values) <= period:
        raise ValueError("Not enough values for RSI")
    gains, losses = [], []
    for i in range(1, len(values)):
        change = values[i] - values[i - 1]
        gains.append(max(change, 0))
        losses.append(max(-change, 0))
    avg_gain = sum(gains[:period]) / period
    avg_loss = sum(losses[:period]) / period
    for i in range(period, len(gains)):
        avg_gain = (avg_gain * (period - 1) + gains[i]) / period
        avg_loss = (avg_loss * (period - 1) + losses[i]) / period
    return 100 if avg_loss == 0 else 100 - 100 / (1 + avg_gain / avg_loss)


def atr(rows, period=14):
    trs = []
    for i in range(1, len(rows)):
        trs.append(max(
            rows[i]["high"] - rows[i]["low"],
            abs(rows[i]["high"] - rows[i - 1]["close"]),
            abs(rows[i]["low"] - rows[i - 1]["close"]),
        ))
    if len(trs) < period:
        raise ValueError("Not enough candles for ATR")
    value = sum(trs[:period]) / period
    for item in trs[period:]:
        value = (value * (period - 1) + item) / period
    return value


def macd(values):
    fast = ema(values[-120:], 12)
    slow = ema(values[-120:], 26)
    line = fast - slow
    history = []
    for end in range(40, len(values) + 1):
        sample = values[max(0, end - 120):end]
        history.append(ema(sample, 12) - ema(sample, 26))
    signal = ema(history[-9:], 9)
    return line, signal, line - signal


def bollinger(values, period=20, deviations=2):
    sample = values[-period:]
    mean = sum(sample) / period
    std = math.sqrt(sum((x - mean) ** 2 for x in sample) / period)
    return mean, mean + deviations * std, mean - deviations * std


def volume_ratio(rows, period=20):
    volumes = [x["volume"] for x in rows]
    avg = sum(volumes[-period - 1:-1]) / period
    if avg <= 0:
        # Spot FX feeds commonly have no centralized volume.
        return 1.0
    return volumes[-1] / avg


def adx(rows, period=14):
    if len(rows) < period * 2 + 2:
        return 0.0
    trs, plus_dm, minus_dm = [], [], []
    for i in range(1, len(rows)):
        high, low, prev = rows[i]["high"], rows[i]["low"], rows[i - 1]
        up = high - prev["high"]
        down = prev["low"] - low
        trs.append(max(high - low, abs(high - prev["close"]), abs(low - prev["close"])))
        plus_dm.append(up if up > down and up > 0 else 0)
        minus_dm.append(down if down > up and down > 0 else 0)

    atr_v = sum(trs[:period]) / period
    plus_v = sum(plus_dm[:period]) / period
    minus_v = sum(minus_dm[:period]) / period
    dx = []
    for i in range(period, len(trs)):
        atr_v = (atr_v * (period - 1) + trs[i]) / period
        plus_v = (plus_v * (period - 1) + plus_dm[i]) / period
        minus_v = (minus_v * (period - 1) + minus_dm[i]) / period
        pdi = 100 * plus_v / atr_v if atr_v else 0
        mdi = 100 * minus_v / atr_v if atr_v else 0
        dx.append(100 * abs(pdi - mdi) / (pdi + mdi) if pdi + mdi else 0)
    return ema(dx[-period:], period) if len(dx) >= period else sum(dx) / len(dx)


def trend_snapshot(rows):
    closes = [x["close"] for x in rows]
    return {
        "price": closes[-1],
        "ema20": ema(closes[-100:], 20),
        "ema50": ema(closes[-150:], 50),
        "ema200": ema(closes[-200:], 200) if len(closes) >= 200 else ema(closes, min(100, len(closes))),
    }


def pivot_levels(rows, lookback=60):
    sample = rows[-lookback:]
    resistance = max(x["high"] for x in sample[:-2])
    support = min(x["low"] for x in sample[:-2])
    return support, resistance


def market_summary(symbol):
    rows = get_market_candles(symbol, "5m", 200)
    hourly = get_market_candles(symbol, "1h", 120)
    closes = [x["close"] for x in rows]
    price = closes[-1]
    short = trend_snapshot(rows)
    higher = trend_snapshot(hourly)

    rsi14 = rsi(closes)
    atr14 = atr(rows)
    atr_pct = atr14 / price * 100
    macd_line, macd_signal, macd_hist = macd(closes)
    bb_mid, bb_upper, bb_lower = bollinger(closes)
    vol_ratio = volume_ratio(rows)
    adx14 = adx(rows)
    support, resistance = pivot_levels(rows)

    trend_up = price > short["ema20"] > short["ema50"]
    higher_tf_up = higher["price"] > higher["ema20"] > higher["ema50"] and higher["price"] > higher["ema200"]
    momentum_ok = 50 <= rsi14 <= 68
    macd_ok = macd_line > macd_signal and macd_hist > 0
    volume_ok = vol_ratio >= 1.05
    volatility_ok = (0.05 <= atr_pct <= 1.50) if MARKET != "forex" else (0.002 <= atr_pct <= 0.50)
    trend_strength_ok = adx14 >= 18
    not_overextended = price <= bb_upper * 0.997
    price_above_mid = price >= bb_mid
    room_to_resistance = resistance > price and ((resistance - price) / price * 100) >= max(
        0.05 if MARKET == "forex" else 0.25, atr_pct * 0.7
    )
    support_ok = support < price

    checks = {
        "5m_trend": trend_up,
        "1h_trend_alignment": higher_tf_up,
        "momentum": momentum_ok,
        "macd": macd_ok,
        "volume_or_fx_activity": volume_ok,
        "volatility": volatility_ok,
        "trend_strength": trend_strength_ok,
        "not_overextended": not_overextended,
        "above_bollinger_mid": price_above_mid,
        "room_to_resistance": room_to_resistance,
        "support_structure": support_ok,
    }
    weights = {
        "5m_trend": 1.3, "1h_trend_alignment": 2.0, "momentum": 0.9,
        "macd": 1.1, "volume_or_fx_activity": 0.7, "volatility": 0.7,
        "trend_strength": 1.3, "not_overextended": 0.8,
        "above_bollinger_mid": 0.6, "room_to_resistance": 0.8,
        "support_structure": 0.5,
    }
    score = 100 * sum(weights[k] for k, v in checks.items() if v) / sum(weights.values())

    stop_distance = max(1.6 * atr14, price * (0.001 if MARKET == "forex" else 0.004))
    stop_loss = max(price - stop_distance, support * 0.995)
    actual_risk = price - stop_loss
    if actual_risk <= 0:
        actual_risk = stop_distance
        stop_loss = price - actual_risk
    take_profit = min(price + actual_risk * 2.2, resistance * 0.995)
    if take_profit <= price:
        take_profit = price + actual_risk * 1.5

    expected_move_pct = (take_profit - price) / price * 100
    round_trip_cost_pct = 2 * (FEE_PCT + SLIPPAGE_PCT)
    cost_buffer_ok = expected_move_pct > round_trip_cost_pct * 1.5

    deterministic_buy = (
        score >= MIN_SIGNAL_SCORE
        and higher_tf_up
        and trend_strength_ok
        and room_to_resistance
        and cost_buffer_ok
    )
    if not cost_buffer_ok:
        score = min(score, MIN_SIGNAL_SCORE - 1)

    return {
        "market": MARKET,
        "symbol": symbol,
        "timeframe": "5m",
        "higher_timeframe": "1h",
        "timestamp_utc": datetime.now(timezone.utc).isoformat(),
        "price": price,
        "ema20": short["ema20"], "ema50": short["ema50"], "ema200": short["ema200"],
        "higher_tf_ema20": higher["ema20"], "higher_tf_ema50": higher["ema50"],
        "higher_tf_ema200": higher["ema200"],
        "rsi14": rsi14, "atr14": atr14, "atr_pct": atr_pct, "adx14": adx14,
        "macd": macd_line, "macd_signal": macd_signal, "macd_histogram": macd_hist,
        "bollinger_mid": bb_mid, "bollinger_upper": bb_upper, "bollinger_lower": bb_lower,
        "activity_ratio": vol_ratio, "support": support, "resistance": resistance,
        "signal_score": round(score, 1), "checks": checks,
        "deterministic_action": "BUY" if deterministic_buy else "HOLD",
        "stop_loss": stop_loss, "take_profit": take_profit,
        "risk_reward": round((take_profit - price) / actual_risk, 2),
        "estimated_round_trip_cost_pct": round_trip_cost_pct,
        "cost_buffer_ok": cost_buffer_ok,
        "data_source": "Yahoo Finance public market data" if MARKET == "forex" else f"Coinbase Exchange {PRODUCT}",
        "execution": "paper_only",
    }


def groq_decision(summary):
    prompt = f"""You are the second-stage confirmation engine for a conservative
market-analysis system. Numeric market data and risk rules are authoritative.

Return ONLY valid JSON:
{{"confirm":"BUY|HOLD","confidence":0-100,"reason":"short reason","risk_flags":["..."]}}

Rules:
- Confirm BUY only when deterministic_action is BUY.
- Require both 5m and 1h trend alignment.
- Require strong trend, momentum and MACD agreement.
- For forex, do not treat spot FX volume as centralized exchange volume.
- Reject if price is overextended or too close to resistance.
- Check that expected move is meaningfully larger than estimated costs.
- Never invent data, news, or certainty.
- Never promise profit.
- Uncertainty or conflicting signals => HOLD.

Market data:
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
    raw = response.choices[0].message.content.strip()
    try:
        return json.loads(raw)
    except json.JSONDecodeError:
        return {"confirm": "HOLD", "confidence": 0, "reason": "Invalid AI JSON", "risk_flags": ["ai_parse_error"]}


def execute(action, price):
    if QUOTE_AMOUNT <= 0 or QUOTE_AMOUNT > MAX_POSITION_USDT:
        return "blocked: position limit"
    return f"PAPER {action} @ {price:.5f} (no real order sent)"


def analyze_symbol(symbol):
    summary = market_summary(symbol)
    ai = groq_decision(summary)
    try:
        ai_confidence = float(ai.get("confidence", 0))
    except (TypeError, ValueError):
        ai_confidence = 0
    final_action = (
        "BUY"
        if summary["deterministic_action"] == "BUY"
        and ai.get("confirm") == "BUY"
        and ai_confidence >= MIN_AI_CONFIDENCE
        else "HOLD"
    )
    return {
        "market": summary,
        "ai_confirmation": ai,
        "final_action": final_action,
    }


def main():
    symbols = FOREX_PAIRS if MARKET == "forex" else [SYMBOL]
    results = []
    for symbol in symbols:
        try:
            results.append(analyze_symbol(symbol))
        except Exception as exc:
            results.append({
                "market": MARKET, "symbol": symbol,
                "final_action": "HOLD",
                "error": str(exc),
            })

    output = {
        "timestamp_utc": datetime.now(timezone.utc).isoformat(),
        "market_mode": MARKET,
        "results": results,
        "risk": {
            "risk_per_trade_pct": RISK_PER_TRADE_PCT,
            "max_daily_loss_pct": MAX_DAILY_LOSS_PCT,
            "max_trades_per_day": MAX_TRADES_PER_DAY,
            "max_position_usdt": MAX_POSITION_USDT,
            "max_spread_pct": MAX_SPREAD_PCT,
            "fee_pct": FEE_PCT,
            "slippage_pct": SLIPPAGE_PCT,
            "leverage": 0,
            "execution": "paper_only",
            "ai_min_confidence": MIN_AI_CONFIDENCE,
        },
    }
    print(json.dumps(output, indent=2))
    for item in results:
        if item.get("final_action") == "BUY":
            print(execute("BUY", item["market"]["price"]))
        else:
            print(f'HOLD: {item.get("market", {}).get("symbol", item.get("symbol", "unknown"))}')


if __name__ == "__main__":
    main()
