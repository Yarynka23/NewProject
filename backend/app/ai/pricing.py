PRICES = {  # $ за 1M токенів: (вхід, вихід)
    "us.amazon.nova-pro-v1:0":   (0.80, 3.20),
    "us.amazon.nova-lite-v1:0":  (0.06, 0.24),
    "us.amazon.nova-micro-v1:0": (0.035, 0.14),
}

def cost_usd(model: str, usage: dict) -> float:
    pin, pout = PRICES[model]
    return round(usage["input_tokens"] * pin / 1e6 + usage["output_tokens"] * pout / 1e6, 6)
