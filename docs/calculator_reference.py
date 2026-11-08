"""Python reference of FairSettlementCalculator (same algorithm as the Dart port)."""
import random
from dataclasses import dataclass, field


@dataclass
class Item:
    id: str
    price: int
    qty: int
    cat: str  # food | regular | premium | personal
    assign: list = field(default_factory=list)  # [(pid, qty)]


@dataclass
class P:
    id: str
    ate: bool = True
    drank: bool = False
    minutes: int | None = None  # attended minutes (None -> no time weighting)


def split_weighted(amount, ids, weights):
    """Largest-remainder split; ties broken by order. Sum == amount exactly."""
    if amount == 0 or not ids:
        return {i: 0 for i in ids}
    W = sum(weights)
    if W == 0:
        weights = [1] * len(ids)
        W = len(ids)
    base = [amount * w // W for w in weights]
    rem = [amount * w % W for w in weights]
    left = amount - sum(base)
    order = sorted(range(len(ids)), key=lambda k: (-rem[k], k))
    for k in order[:left]:
        base[k] += 1
    return dict(zip(ids, base))


def split_by_qty(price, qty):
    b, r = divmod(price, qty)
    return [b + (1 if k < r else 0) for k in range(qty)]


class SettlementError(Exception):
    pass


def calculate(items, ps, receipt_total=None, unit=100, payer=None, seed=0):
    ids = [p.id for p in ps]
    w = {p.id: (p.minutes if p.minutes is not None else 1) for p in ps}
    share = {i: {"food": 0, "regular": 0, "premium": 0, "personal": 0} for i in ids}
    tot = {c: sum(it.price for it in items if it.cat == c) for c in ("food", "regular", "premium", "personal")}

    for cat, flag in (("food", "ate"), ("regular", "drank")):
        if tot[cat] == 0:
            continue
        payers = [p.id for p in ps if getattr(p, flag)]
        if not payers:
            raise SettlementError(cat)
        for i, v in split_weighted(tot[cat], payers, [w[i] for i in payers]).items():
            share[i][cat] += v

    for it in items:
        if it.cat not in ("premium", "personal"):
            continue
        if sum(q for _, q in it.assign) != it.qty:
            raise SettlementError("unassigned")
        units = split_by_qty(it.price, it.qty)
        cur = 0
        for pid, q in it.assign:
            share[pid][it.cat] += sum(units[cur:cur + q])
            cur += q

    sub = {i: sum(share[i].values()) for i in ids}
    items_sum = sum(tot.values())
    target = receipt_total if receipt_total else items_sum
    diff = target - items_sum
    if diff != 0:
        neg = diff < 0
        d = split_weighted(abs(diff), ids, [sub[i] for i in ids])
        disc = {i: (-d[i] if neg else d[i]) for i in ids}
    else:
        disc = {i: 0 for i in ids}
    pre = {i: sub[i] + disc[i] for i in ids}

    floored = {i: (pre[i] // unit) * unit for i in ids}
    remainder = target - sum(floored.values())
    candidates = [i for i in ids if pre[i] > 0]
    if remainder > 0:
        if payer is None:
            payer = candidates[random.Random(seed).randrange(len(candidates))]
        floored[payer] += remainder
    final = floored
    assert sum(final.values()) == target
    return dict(share=share, sub=sub, disc=disc, pre=pre, final=final,
                remainder=remainder, payer=payer, target=target)


if __name__ == "__main__":
    rng = random.Random(1)
    n_ok = n_err = 0
    for trial in range(20000):
        n = rng.randint(1, 8)
        ps = [P(f"p{k}", rng.random() < .85, rng.random() < .6, rng.randint(0, 300)) for k in range(n)]
        items = []
        for k in range(rng.randint(1, 10)):
            cat = rng.choice(["food", "food", "regular", "premium", "personal"])
            qty = rng.randint(1, 4)
            price = rng.randint(1, 60) * 500 + rng.choice([0, 0, 1, 7])
            asg = []
            if cat in ("premium", "personal"):
                left = qty
                for p in rng.sample(ps, len(ps)):
                    if left == 0:
                        break
                    q = rng.randint(1, left)
                    asg.append((p.id, q))
                    left -= q
                if left:
                    asg.append((ps[0].id, left))
            items.append(Item(f"i{k}", price, qty, cat, asg))
        s = sum(i.price for i in items)
        rt = rng.choice([None, s, int(s * .9), s - 3000 if s > 3000 else s])
        try:
            r = calculate(items, ps, rt, seed=trial)
        except SettlementError:
            n_err += 1
            continue
        n_ok += 1
        # 1. 총액 보존
        assert sum(r["final"].values()) == r["target"]
        assert sum(r["sub"].values()) == s
        # 2. 비음주자 일반주류 0원, 안 먹은 사람 음식 0원
        for p in ps:
            if not p.drank:
                assert r["share"][p.id]["regular"] == 0
            if not p.ate:
                assert r["share"][p.id]["food"] == 0
        # 3. 대칭성: 조건이 같은 두 사람의 공용 몫 차이는 반올림 1원 이내
        for a in ps:
            for b in ps:
                if (a.ate, a.drank, a.minutes) == (b.ate, b.drank, b.minutes):
                    for c in ("food", "regular"):
                        assert abs(r["share"][a.id][c] - r["share"][b.id][c]) <= 1
        # 4. 단조성: 같은 조건에서 더 오래 있으면 공용 몫이 적지 않음(1원 오차)
        for a in ps:
            for b in ps:
                if (a.ate, a.drank) == (b.ate, b.drank) and a.minutes >= b.minutes:
                    for c in ("food", "regular"):
                        assert r["share"][a.id][c] >= r["share"][b.id][c] - 1
        # 5. 반올림 후 각자 100원 단위(당첨자 제외), 음수 없음
        for i, v in r["final"].items():
            assert v >= 0
            if i != r["payer"]:
                assert v % 100 == 0
        # 6. 당첨자 추가 부담은 (인원수 x 100원) 미만
        assert 0 <= r["remainder"] < 100 * n
    print(f"property checks passed: {n_ok} settled, {n_err} rejected as invalid input")
