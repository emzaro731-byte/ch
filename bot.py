import json
import math
import os
import time

import requests
from groq import Groq

SYMBOL = os.getenv("SYMBOL", "BTCUSDT").upper()
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

LIVE_TRADING = (
    os.getenv("LIVE_TRADING", "false").lower() == "true"
    and os.getenv("ENABLE_LIVE_TRADING", "") == "I_UNDERSTAND"
)

groq = Groq(api_key=os.environ["GROQ_API_KEY"])


def fetch_candles(product="BTC-USD", granularity=300, count=200):
    end = int(time.time())
    start = end - count * granularity
    r = requests.get(
        f"https://api.exchange.coinbase.com/products/{product}/candles",
        params={
            "granularity": granularity,
            "start": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(start)),
            "end": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(end)),
        },
        headers={"User-Agent": "Veylola-Trade-Bot/3.0"},
        timeout=15,
    )
    r.raise_for_status()
    raw = r.json()
    if not isinstance(raw, list) or len(raw) < min(80, count):
        raise RuntimeError(f"Not enough candles for {product} {granularity}s")
    rows = sorted(
        [
            {
                "time": int(x[0]),
                "low": float(x[1]),
                "high": float(x[2]),
                "open": float(x[3]),
                "close": float(x[4]),
                "volume": float(x[5]),
            }
            for x in raw
        ],
        key=lambda x: x["time"],
    )
    # Avoid basing a signal on a candle that may still be forming.
    return rows[:-1] if len(rows) > 80 else rows


def candles():
    return fetch_candles("BTC-USD", 300, 200)


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
    return 100 if avg_loss == 0 else 100 - (100 / (1 + avg_gain / avg_loss))


def atr(rows, period=14):
    if len(rows) <= period:
        raise ValueError("Not enough candles for ATR")
    true_ranges = []
    for i in range(1, len(rows)):
        true_ranges.append(
            max(
                rows[i]["high"] - rows[i]["low"],
                abs(rows[i]["high"] - rows[i - 1]["close"]),
                abs(rows[i]["low"] - rows[i - 1]["close"]),
            )
        )
    value = sum(true_ranges[:period]) / period
    for item in true_ranges[period:]:
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
    variance = sum((x - mean) ** 2 for x in sample) / period
    std = math.sqrt(variance)
    return mean, mean + deviations * std, mean - deviations * std


def volume_ratio(rows, period=20):
    recent = rows[-1]["volume"]
    average = sum(x["volume"] for x in rows[-period - 1:-1]) / period
    return recent / average if average else 0


def adx(rows, period=14):
    # Wilder-style ADX. Higher values indicate a stronger trend regime.
    if len(rows) < period * 2 + 2:
        return 0.0
    trs, plus_dm, minus_dm = [], [], []
    for i in range(1, len(rows)):
        high, low, prev_close = rows[i]["high"], rows[i]["low"], rows[i - 1]["close"]
        up = high - rows[i - 1]["high"]
        down = rows[i - 1]["low"] - low
        trs.append(max(high - low, abs(high - prev_close), abs(low - prev_close)))
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
        plus_di = 100 * plus_v / atr_v if atr_v else 0
        minus_di = 100 * minus_v / atr_v if atr_v else 0
        dx.append(100 * abs(plus_di - minus_di) / (plus_di + minus_di) if plus_di + minus_di else 0)

    return ema(dx[-period:], period) if len(dx) >= period else sum(dx) / len(dx)


def trend_snapshot(rows):
    closes = [x["close"] for x in rows]
    price = closes[-1]
    e20 = ema(closes[-100:], 20)
    e50 = ema(closes[-150:], 50)
    e200 = ema(closes[-200:], 200) if len(closes) >= 200 else ema(closes, min(100, len(closes)))
    return {
        "price": price,
        "ema20": e20,
        "ema50": e50,
        "ema200": e200,
        "trend_up": price > e20 > e50,
        "long_term_up": price > e200,
    }


def market_summary():
    rows = candles()
    closes = [x["close"] for x in rows]
    price = closes[-1]

    # 5m execution timeframe plus 1h regime filter.
    hourly = fetch_candles("BTC-USD", 3600, 120)
    short = trend_snapshot(rows)
    higher = trend_snapshot(hourly)

    rsi14 = rsi(closes)
    atr14 = atr(rows)
    atr_pct = atr14 / price * 100
    macd_line, macd_signal, macd_hist = macd(closes)
    bb_mid, bb_upper, bb_lower = bollinger(closes)
    vol_ratio = volume_ratio(rows)
    adx14 = adx(rows)

    trend_up = short["trend_up"]
    higher_tf_up = higher["trend_up"] and higher["long_term_up"]
    momentum_ok = 50 <= rsi14 <= 68
    macd_ok = macd_line > macd_signal and macd_hist > 0
    volume_ok = vol_ratio >= 1.05
    volatility_ok = 0.05 <= atr_pct <= 1.50
    trend_strength_ok = adx14 >= 18
    not_overextended = price <= bb_upper
    price_above_mid = price >= bb_mid

    checks = {
        "5m_trend": trend_up,
        "1h_trend_alignment": higher_tf_up,
        "momentum": momentum_ok,
        "macd": macd_ok,
        "volume": volume_ok,
        "volatility": volatility_ok,
        "trend_strength": trend_strength_ok,
        "not_overextended": not_overextended,
        "above_bollinger_mid": price_above_mid,
    }

    # Weighted score: higher timeframe and trend structure carry more weight.
    weights = {
        "5m_trend": 1.4,
        "1h_trend_alignment": 2.0,
        "momentum": 1.0,
        "macd": 1.2,
        "volume": 0.8,
        "volatility": 0.8,
        "trend_strength": 1.3,
        "not_overextended": 0.8,
        "above_bollinger_mid": 0.7,
    }
    score = 100 * sum(weights[k] for k, v in checks.items() if v) / sum(weights.values())

    # Adaptive exits: wider in volatile markets, but never below a minimum distance.
    stop_distance = max(1.6 * atr14, price * 0.004)
    stop_loss = price - stop_distance
    take_profit = price + stop_distance * 2.2

    estimated_round_trip_cost_pct = 2 * (FEE_PCT + SLIPPAGE_PCT)
    expected_move_pct = (take_profit - price) / price * 100
    cost_buffer_ok = expected_move_pct > estimated_round_trip_cost_pct * 1.5

    deterministic_buy = (
        score >= MIN_SIGNAL_SCORE
        and cost_buffer_ok
        and higher_tf_up
        and trend_strength_ok
    )

    if not cost_buffer_ok:
        score = min(score, MIN_SIGNAL_SCORE - 1)

    return {
        "symbol": SYMBOL,
        "timeframe": "5m",
        "higher_timeframe": "1h",
        "price": price,
        "ema20": short["ema20"],
        "ema50": short["ema50"],
        "ema200": short["ema200"],
        "higher_tf_ema20": higher["ema20"],
        "higher_tf_ema50": higher["ema50"],
        "higher_tf_ema200": higher["ema200"],
        "rsi14": rsi14,
        "atr14": atr14,
        "atr_pct": atr_pct,
        "adx14": adx14,
        "macd": macd_line,
        "macd_signal": macd_signal,
        "macd_histogram": macd_hist,
        "bollinger_mid": bb_mid,
        "bollinger_upper": bb_upper,
        "bollinger_lower": bb_lower,
        "volume_ratio": vol_ratio,
        "signal_score": round(score, 1),
        "checks": checks,
        "deterministic_action": "BUY" if deterministic_buy else "HOLD",
        "stop_loss": stop_loss,
        "take_profit": take_profit,
        "risk_reward": "1:2.2",
        "estimated_round_trip_cost_pct": estimated_round_trip_cost_pct,
        "cost_buffer_ok": cost_buffer_ok,
        "source": "Coinbase Exchange BTC-USD",
    }


def groq_decision(summary):
    prompt = f"""You are the second-stage confirmation engine for a conservative
crypto trading system. The numeric strategy is authoritative for market data.
Use ONLY the supplied data.

Return ONLY valid JSON:
{{"confirm":"BUY|HOLD","confidence":0-100,"reason":"short reason",
"risk_flags":["..."]}}

Rules:
- Confirm BUY only if the deterministic action is BUY.
- Require 1h and 5m trend alignment, adequate trend strength and several
  independent confirmations.
- Prefer HOLD when indicators disagree or the setup is extended.
- Never invent prices, news, volume, or other data.
- Never promise profit and never override risk controls.
- If uncertain, return HOLD.

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
    return json.loads(response.choices[0].message.content.strip())


def busha_pairs():
    """Read Busha public pair data when available."""
    r = requests.get(
        "https://api.busha.co/v1/pairs",
        params={"currency": "NGN", "type": "crypto"},
        headers={"User-Agent": "Veylola-Trade/3.0"},
        timeout=15,
    )
    r.raise_for_status()
    return r.json()


def execute(action, price):
    if QUOTE_AMOUNT <= 0 or QUOTE_AMOUNT > MAX_POSITION_USDT:
        return "blocked: position limit"
    if not LIVE_TRADING:
        return f"PAPER {action} @ {price:.2f} (no real order sent)"
    return "LIVE execution intentionally disabled in this build"


def main():
    summary = market_summary()
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

    output = {
        "market": summary,
        "ai_confirmation": ai,
        "final_action": final_action,
        "risk": {
            "risk_per_trade_pct": RISK_PER_TRADE_PCT,
            "max_daily_loss_pct": MAX_DAILY_LOSS_PCT,
            "max_trades_per_day": MAX_TRADES_PER_DAY,
            "max_position_usdt": MAX_POSITION_USDT,
            "max_spread_pct": MAX_SPREAD_PCT,
            "fee_pct": FEE_PCT,
            "slippage_pct": SLIPPAGE_PCT,
            "leverage": 0,
            "execution": "disabled",
        },
    }

    print(json.dumps(output, indent=2))
    print(
        execute(final_action, summary["price"])
        if final_action == "BUY"
        else "HOLD: setup did not pass all AI and risk filters"
    )


if __name__ == "__main__":
    main()
