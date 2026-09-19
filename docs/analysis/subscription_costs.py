"""EatSet scenario model, not measured usage. Run with Python 3, no dependencies."""
from decimal import Decimal as D

# Google global price list, checked 2026-09-19. First paid band, USD/request.
# https://developers.google.com/maps/billing-and-pricing/pricing
RATES = {'nearby': D('0.035'), 'details': D('0.020'), 'photos': D('0.007')}
FX = D('32')  # Modeling assumption, NOT a current exchange-rate quote.
SCENARIOS = [('較少查詢', 10, 30, 30), ('每日使用', 30, 60, 90), ('較多查詢', 60, 120, 240)]

def api_cost(n, d, p):
    return (D(n)*RATES['nearby'] + D(d)*RATES['details'] + D(p)*RATES['photos'])*FX

rows = []
print('假設：每人每月；免費額度已用完；首階付費費率；USD 1 = TWD 32。')
print('不含主機、稅、退款、客服、獲客、免費用戶補貼；非實測用量。')
for label, n, d, p in SCENARIOS:
    cost = api_cost(n, d, p)
    rows.append({'scenario': label, 'nearby': n, 'details': d, 'photos': p, 'api_twd': float(cost)})
    print(f'{label}: 搜尋 {n}, 詳情 {d}, 照片 {p} → NT${cost:.2f}')
print('\n每日使用情境，扣除抽成假設與 API 後的餘額（不是淨利）：')
margin_rows = []
for price in (69, 149, 199):
    for commission in (D('0.15'), D('0.30')):
        residual = D(price)*(1-commission)-api_cost(30,60,90)
        margin_rows.append({'price_twd': price, 'commission_percent': int(commission*100), 'residual_twd': float(residual)})
        print(f'售價 {price}, 抽成假設 {commission:.0%}: NT${residual:.2f}')
# Independent integer-cents checks of the three paid-band estimates.
assert [r['api_twd'] for r in rows] == [37.12, 92.16, 197.76]
assert api_cost(0,0,0) == 0
assert D('199')*D('0.85') - api_cost(30,60,90) == D('76.99')
