# Swiggy Sales Analysis: Final Report

**Period:** 1 Jan to 31 Aug 2025 (243 days) · **Tools:** SQL Server, Python (pandas), Power BI

## 1. Summary

I cleaned and analysed 197,430 raw Swiggy dish records across 28 cities. After removing duplicates, 197,401 records remain, with a total sales value of INR 5.30 Cr. The main result is that **sales are very stable**: sales per day barely change across months or between weekdays and weekends. The business is concentrated in a few places and brands (Bengaluru, KFC, McDonald's), and expensive items carry a large share of value. One day, 22 Feb 2025, is unusual and is handled separately.

> **Terms.** The file has no order id, so one row is one dish line item ("order record"). "Sales value" is the sum of item prices, not Swiggy's revenue.

## 2. Objective and questions

1. How large is the business and how is it spread (time, city, restaurant, price)?
2. Is there growth, seasonality or a weekday/weekend pattern?
3. How reliable are the ratings?
4. Can daily sales be forecast, and does a model add anything over a simple average?

## 3. Data and cleaning

| Problem | Action |
|---|---|
| 6,655 dish names with extra spaces | Trimmed all text columns |
| 29 duplicate rows (ignoring case) | Removed: 197,430 to 197,401 |
| 79,080 rows with no reviews, 94.9% of them showing a default 4.4 | Rating set to NULL, `Rating_Status` added |
| Price tiers needed | Terciles: Low up to 169, Medium up to 290, High above |
| 22 Feb 2025 has 1,549 rows (median day: 810) | Flagged `Is_Anomaly_Day`, kept, excluded from per-day figures |
| Older Sep to Dec rows | Found to be artificially generated, not used |

## 4. Method

1. **Audit** of the raw file (7 findings and a decisions table).
2. **SQL Server pipeline:** staging table, cleaning, star schema (1 fact, 5 dimensions), KPI queries and one flat view for Power BI.
3. **Python (pandas):** the same cleaning rebuilt independently, with 15 reconciliation checks against the expected SQL results. All 15 matched in my run on the real file.
4. **EDA** with per-day comparisons, so short months and 2-vs-5 day weeks do not mislead.
5. **Power BI** dashboard with six pages.
6. **Forecast check** with a rolling-origin backtest of simple baselines.

## 5. Results

### Headline numbers

| Metric | Value |
|---|---|
| Order records | 197,401 |
| Sales value | INR 53,002,740 (5.30 Cr) |
| Average / median item price | INR 268.50 / 229 |
| Records with reviews | 59.9% |
| Average rating, reviewed items | 4.31 (4.36 weighted by review count) |
| Sales per day (22 Feb excluded) | INR 217,242 |

### Time

Sales per day by month (22 Feb excluded):

| Month | Jan | Feb | Mar | Apr | May | Jun | Jul | Aug |
|---|---|---|---|---|---|---|---|---|
| INR thousand per day | 220 | 216 | 212 | 220 | 219 | 217 | 215 | 219 |

- Range is INR 212K to 220K, with no growth or decline. February's 8.1% fall in total sales is mostly because it is a shorter month (about 1.8% lower per day).
- **Weekday vs weekend:** INR 217,271 vs INR 217,171 per day. Average item price is also the same (268.5 vs 268.3).
- **Quarters per day:** Q1 216K, Q2 219K, Q3 217K (Q3 has only July and August).

### Geography

| City | Sales value | Share |
|---|---|---|
| Bengaluru | INR 5.46M | 10.3% |
| Lucknow | INR 3.12M | 5.9% |
| Hyderabad | INR 3.02M | 5.7% |
| Mumbai | INR 3.02M | 5.7% |
| New Delhi | INR 2.83M | 5.3% |

Bengaluru has about 1.8x the order records of the next city even without 22 Feb.

### Restaurants

- Top 5 restaurants (KFC, McDonald's, Pizza Hut, Burger King, Domino's) make up **25.4%** of sales value, and the top 10 make up 34.2%.
- KFC alone is 8.0%. 36 of 993 restaurant names account for half of all sales value.

### Prices

| Price range | % of records | % of sales value |
|---|---|---|
| Below 100 | 13.6 | 3.4 |
| 100 to 199 | 28.6 | 16.1 |
| 200 to 299 | 27.7 | 25.9 |
| 300 to 399 | 15.8 | 20.5 |
| 400 to 499 | 6.3 | 10.5 |
| 500 and above | 8.0 | 23.6 |

### Ratings

- 40.1% of records have no reviews, so ratings describe reviewed items only.
- Price and rating are almost unrelated (correlation 0.03).
- City averages range from 4.10 (Srinagar) to 4.46 (Kochi) among cities with 500+ reviewed records.

### The 22 Feb anomaly

Bengaluru has about 10x its usual volume that day while every other city is normal. The cause is unknown (a real event or a data collection effect), so the day is flagged, kept, and left out of per-day figures. A smaller Bengaluru bump on 16 Feb is not flagged.

### Forecasting

The daily series is flat with no weekday effect, so I test only simple baselines (naive, mean, moving averages, seasonal naive, weekday profile) in section 11 of `swiggy_analysis.ipynb`. The expected outcome is that a plain average is about as good as any model, because there is no trend or pattern to learn.

Backtest result (11 folds, 30-day horizon, lower is better):

| Model | MAE (INR/day) | WAPE % |
|---|---|---|
| Mean of all history | 8,467 | 3.90 |
| Moving avg 28d | 8,646 | 3.98 |
| Moving avg 14d | 8,772 | 4.04 |
| Moving avg 7d | 8,898 | 4.10 |
| Weekday profile (8 weeks) | 9,023 | 4.15 |
| Seasonal naive (7d) | 11,488 | 5.28 |
| Naive (last day) | 12,100 | 5.57 |

**Conclusion:** the plain average is the best model, and every smoothing method is within about 0.3 points of it. The weekday profile is worse than the average, which confirms there is no usable weekday pattern. Daily sales can be forecast to about 4% error simply by using the average level, so a complex model is not justified on this data. With only 11 folds, the order of the close models is not reliable.

## 6. Recommendations

1. **Do not expect growth stories from this data.** Sales are flat. Any month-to-month change in totals should be read per day.
2. **Protect the concentration points.** Bengaluru and five brands carry a large share of value. Losing one has an outsized effect.
3. **Look at the INR 500+ items.** They are 8% of records but 23.6% of sales value.
4. **Fix rating coverage.** With 40% of records unrated, rating-based decisions are weak. Use the weighted rating (4.36) with care.
5. **Find out what happened on 22 Feb** with the data owner before using that day in any analysis.

## 7. Limitations

- Eight months only: no yearly seasonality and nothing about Q4.
- A row is a dish line item, not a verified order. Sales value is not revenue.
- Ratings are item-level and 40% are missing.
- The analysis is descriptive. It shows patterns, not causes.
- Veg/Non-Veg and cuisine labels come from keyword rules, and a large share is Unclassified.

## 8. Project status

| Part | Status |
|---|---|
| Data audit and cleaning | Done |
| Python cleaning, EDA, 15 reconciliation checks | Done (matched on real data) |
| Power BI dashboard | Done (check the MoM growth card, which looked like 14.70% instead of about 2.1% for Aug vs Jul) |
| SQL scripts 00 to 05 | Written. **Run them in SQL Server and compare with `docs/sql_expected_results.md`** |
| Forecast check (notebook section 11) | Done (run on real data) |
| README and this report | Done |

## 9. Files

`README.md` · `swiggy_analysis.ipynb` · `sql/` · `images/` · `FINAL_REPORT.md`
