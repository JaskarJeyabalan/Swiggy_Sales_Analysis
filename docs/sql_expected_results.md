# SQL expected results (Jan-Aug 2025)

Computed independently with pandas using exactly the same cleaning rules as `01_data_cleaning.sql`. After running each script in SQL Server, the checks printed by the script should match these numbers. If one differs, that step has a problem - tell me which and send the result.

*(Distinct counts assume SQL Server's default case-insensitive collation.)*


## Script 01 - cleaning

- raw rows: **197,430**; rows after exact-duplicate removal: **197,401** (29 removed)
- bad/blank values in raw: **0** in every column; bad dates: **0**
- rows with NULL rating after placeholder fix (Rating_Count = 0): **79,080** (40.1%)

## Food_Type

| Food_Type   |   rows |   share % |
|:------------|-------:|----------:|
| Veg         |  84024 |      42.6 |
| Unknown     |  58196 |      29.5 |
| Non-Veg     |  55181 |      28   |

## Food_Type_Confidence

| Food_Type_Confidence   |   rows |   share % |
|:-----------------------|-------:|----------:|
| High                   | 105582 |      53.5 |
| Low                    |  58196 |      29.5 |
| Medium                 |  33623 |      17   |

## Cuisine_Type

| Cuisine_Type   |   rows |   share % |
|:---------------|-------:|----------:|
| Unclassified   |  67359 |      34.1 |
| Fast Food      |  47187 |      23.9 |
| Dessert        |  23001 |      11.7 |
| North Indian   |  17468 |       8.8 |
| Beverage       |  15533 |       7.9 |
| Chinese        |  12878 |       6.5 |
| South Indian   |   5613 |       2.8 |
| Biryani        |   4870 |       2.5 |
| Korean         |   3492 |       1.8 |

## Category_Type

| Category_Type   |   rows |   share % |
|:----------------|-------:|----------:|
| Main Course     |  57461 |      29.1 |
| Unclassified    |  53157 |      26.9 |
| Dessert         |  23001 |      11.7 |
| Starter         |  16565 |       8.4 |
| Beverage        |  15533 |       7.9 |
| Bread           |  11561 |       5.9 |
| Snacks          |   8954 |       4.5 |
| Breakfast Item  |   5038 |       2.6 |
| Side Dish       |   3844 |       1.9 |
| Soup            |   2287 |       1.2 |

## Price_Category (terciles)

P33 = **169.00**, P66 = **290.00**

| Price_Category   |   rows |   min_price |   max_price |
|:-----------------|-------:|------------:|------------:|
| High             |  66439 |      290.47 |        8000 |
| Low              |  65149 |        0.95 |         169 |
| Medium           |  65813 |      169.05 |         290 |

## Rating_Status

| Rating_Status   |   rows |
|:----------------|-------:|
| Rated           | 118321 |
| Not Rated       |  79080 |

## Script 02 - dimensions

- dim_date rows: **243** (2025-01-01 to 2025-08-31); days without records: **0**
- median daily rows: 810; anomaly days (> 1.5 x median): **1** -> 2025-02-22 (1,549 rows)
- dim_location: **961**; dim_restaurant: **984**; dim_category: **4,730**; dim_dish: **53,983**
- states: 28, cities: 28

## Script 03 / 05 - fact and view

- fact rows = stg rows = view rows = **197,401**; total of Price_INR in stg and fact must both equal **53,002,740.47**

## Script 04 - headline KPIs

- Total order records: **197,401**
- Total sales value: **53,002,740.47** INR (= 5.30 Cr)
- Average item price: **268.50**; median item price: **229.00**
- Average rating (reviewed items): simple **4.31**, weighted by Rating_Count **4.36**
- Records with at least one review: **59.94%**

## Weekday vs Weekend (anomaly day excluded)

| Day_Type   |   orders |   days |   orders_per_day |     revenue |   revenue_per_day |
|:-----------|---------:|-------:|-----------------:|------------:|------------------:|
| Weekday    |   139999 |    173 |            809.2 | 3.75878e+07 |            217271 |
| Weekend    |    55853 |     69 |            809.5 | 1.49848e+07 |            217171 |

## Monthly per-day figures (anomaly day excluded)

|   Month |   orders |   days |   orders_per_day |   revenue_per_day |
|--------:|---------:|-------:|-----------------:|------------------:|
|       1 |    25393 |     31 |            819.1 |            220128 |
|       2 |    21742 |     27 |            805.3 |            216223 |
|       3 |    24400 |     31 |            787.1 |            212024 |
|       4 |    24584 |     30 |            819.5 |            219682 |
|       5 |    25188 |     31 |            812.5 |            219117 |
|       6 |    24382 |     30 |            812.7 |            217123 |
|       7 |    24936 |     31 |            804.4 |            214525 |
|       8 |    25227 |     31 |            813.8 |            219061 |

## Price ranges (half-open: >= low and < high)

| Price_Range      |   orders |
|:-----------------|---------:|
| 1. Below 100     |    26795 |
| 2. 100-199       |    56368 |
| 3. 200-299       |    54773 |
| 4. 300-399       |    31276 |
| 5. 400-499       |    12492 |
| 6. 500 and above |    15697 |
