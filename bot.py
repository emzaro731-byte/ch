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
        headers={"User-Agent": "Veylola-Trade-Bot/2.0"},
        timeout=15,
    )
    r.raise_for_status()
    rows = r.json()
    if not isinstance(rows, list) or len(rows) < 100:
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
    value = values[0]
    for item in values[1:]:
        value = item * k + value * (1 - k)
    return value


def rsi(values, period=14):
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

    # A small MACD history gives a more useful histogram direction.
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


def market_summary():
    rows = candles()
    closes = [x["close"] for x in rows]
    price = closes[-1]

    ema20 = ema(closes[-100:], 20)
    ema50 = ema(closes[-150:], 50)
    ema200 = ema(closes[-200:], 200) if len(closes) >= 200 else ema(closes, min(100, len(closes)))
    rsi14 = rsi(closes)
    atr14 = atr(rows)
    atr_pct = atr14 / price * 100
    macd_line, macd_signal, macd_hist = macd(closes)
    bb_mid, bb_upper, bb_lower = bollinger(closes)
    vol_ratio = volume_ratio(rows)

    trend_up = price > ema20 > ema50
    long_term_up = price > ema200
    momentum_ok = 50 <= rsi14 <= 68
    macd_ok = macd_line > macd_signal and macd_hist > 0
    volume_ok = vol_ratio >= 1.05
    volatility_ok = 0.05 <= atr_pct <= 1.50
    not_overextended = price <= bb_upper
    gross_reward_risk = 2.2

    # Score independent confirmations before asking the language model.
    checks = {
        "trend": trend_up,
        "long_term_trend": long_term_up,
        "momentum": momentum_ok,
        "macd": macd_ok,
        "volume": volume_ok,
        "volatility": volatility_ok,
        "not_overextended": not_overextended,
    }
    score = sum(1 for passed in checks.values() if passed) / len(checks) * 100
    deterministic_buy = score >= MIN_SIGNAL_SCORE

    # Volatility-based exits adapt to the market instead of fixed percentages.
    stop_distance = max(1.5 * atr14, price * 0.004)
    stop_loss = price - stop_distance
    take_profit = price + stop_distance * gross_reward_risk

    estimated_round_trip_cost_pct = 2 * (FEE_PCT + SLIPPAGE_PCT)
    expected_move_pct = (take_profit - price) / price * 100
    cost_buffer_ok = expected_move_pct > estimated_round_trip_cost_pct * 1.5

    if not cost_buffer_ok:
        deterministic_buy = False
        score = min(score, MIN_SIGNAL_SCORE - 1)

    return {
        "symbol": SYMBOL,
        "timeframe": "5m",
        "price": price,
        "ema20": ema20,
        "ema50": ema50,
        "ema200": ema200,
        "rsi14": rsi14,
        "atr14": atr14,
        "atr_pct": atr_pct,
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
        "risk_reward": f"1:{gross_reward_risk}",
        "estimated_round_trip_cost_pct": estimated_round_trip_cost_pct,
        "cost_buffer_ok": cost_buffer_ok,
        "source": "Coinbase Exchange BTC-USD",
    }


def groq_decision(summary):
    prompt = f"""You are a conservative crypto trading confirmation engine.
Use ONLY the supplied market data. The deterministic strategy has already
filtered the setup. Your job is to reject weak or contradictory setups.

Return ONLY JSON:
{{"confirm":"BUY|HOLD","confidence":0-100,"reason":"short reason",
"risk_flags":["..."]}}

Rules:
- Confirm BUY only when the signal score is strong and multiple indicators agree.
- Reject if trend, momentum, MACD, volume, volatility or cost conditions conflict.
- Never invent market data.
- Never promise profit.
- Never override the risk limits.

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
        headers={"User-Agent": "Veylola-Trade/2.0"},
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

    ai_confidence = float(ai.get("confidence", 0))
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
            "execution": "disabled" if not LIVE_TRADING else "blocked",
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
