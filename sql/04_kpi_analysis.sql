-- =====================================================================
-- 04_KPI_Analysis.sql  (updated for the rebuilt Jan-Aug 2025 data)
-- IMPORTANT ABOUT THE DATA: each row is one dish line item; there is no order id and 'Price_INR' is the item price.
-- So 'orders' = order records and 'revenue/sales' = sum of item prices. Data covers 1 Jan - 31 Aug 2025 only.
-- Trend queries use PER-DAY figures and exclude the anomaly day (dim_date.Is_Anomaly_Day) so months/days compare fairly.
-- =====================================================================
--Use the created Swiggy_DB database

USE Swiggy_DB;
GO

--KPI's

--Total Order Records (one row = one dish line item; there is no order id in the source data)
SELECT COUNT(*) AS Total_Order_Records
FROM fact_swiggy_orders;

--Total Sales Value (sum of item prices, INR)
SELECT SUM(Price_INR) AS Total_Sales_Value
FROM fact_swiggy_orders;

--Average Item Price (equals the average order value for this dataset)
SELECT CAST(AVG(Price_INR) AS DECIMAL(10,2)) AS Avg_Item_Price
FROM fact_swiggy_orders;

--Average Rating: reviewed items only. The weighted version gives items with more reviews more influence.
SELECT
    CAST(AVG(Rating) AS DECIMAL(4,2)) AS Avg_Rating_Simple,
    CAST(SUM(Rating * Rating_Count) * 1.0 / NULLIF(SUM(Rating_Count), 0) AS DECIMAL(4,2)) AS Avg_Rating_Weighted
FROM fact_swiggy_orders
WHERE Rating IS NOT NULL;

--Share of records that have at least one review
SELECT CAST(100.0 * SUM(CASE WHEN Rating IS NOT NULL THEN 1 ELSE 0 END) / COUNT(*) AS DECIMAL(5,2)) AS Pct_Records_With_Reviews
FROM fact_swiggy_orders;

--Granular Requirements
--Deep Dive Business Analysis

--Monthly Order Trends (Orders = total incl. anomaly day; Orders_Per_Day excludes it)
SELECT
    d.Year, d.Month, d.Year_Month,
    COUNT(*) AS Orders,
    CAST(1.0 * SUM(CASE WHEN d.Is_Anomaly_Day = 0 THEN 1 ELSE 0 END)
         / COUNT(DISTINCT CASE WHEN d.Is_Anomaly_Day = 0 THEN d.date_id END) AS DECIMAL(10,1)) AS Orders_Per_Day
FROM fact_swiggy_orders f
JOIN dim_date d ON f.date_id = d.date_id
GROUP BY d.Year, d.Month, d.Year_Month
ORDER BY d.Year, d.Month;

--Monthly Revenue Trends (Revenue_Per_Day excludes the anomaly day)
SELECT
    d.Year, d.Month, d.Year_Month,
    SUM(f.Price_INR) AS Revenue,
    CAST(SUM(CASE WHEN d.Is_Anomaly_Day = 0 THEN f.Price_INR ELSE 0 END)
         / COUNT(DISTINCT CASE WHEN d.Is_Anomaly_Day = 0 THEN d.date_id END) AS DECIMAL(12,0)) AS Revenue_Per_Day
FROM fact_swiggy_orders f
JOIN dim_date d ON f.date_id = d.date_id
GROUP BY d.Year, d.Month, d.Year_Month
ORDER BY d.Year, d.Month;

--Quarterly Trends (anomaly day excluded; Q3 contains only July-August, so compare quarters per day, not in total)
SELECT
    d.Year, d.Quarter,
    COUNT(DISTINCT d.date_id) AS Days_In_Data,
    SUM(f.Price_INR) AS Sales,
    CAST(SUM(f.Price_INR) / COUNT(DISTINCT d.date_id) AS DECIMAL(12,0)) AS Sales_Per_Day,
    CAST(AVG(f.Rating) AS DECIMAL(4,2)) AS Rating,
    COUNT(*) AS Orders
FROM fact_swiggy_orders f
JOIN dim_date d ON f.date_id = d.date_id
WHERE d.Is_Anomaly_Day = 0
GROUP BY d.Year, d.Quarter
ORDER BY d.Year, d.Quarter;

--Yearly Trends

SELECT
d.Year,
COUNT(*) AS Total_Orders
FROM fact_swiggy_orders f
Join dim_date d ON f.date_id = d.date_id
GROUP BY d.Year
ORDER BY COUNT(*) DESC;

--Orders and Revenue by Day of week (Mon-Sun): per-day averages, anomaly day excluded
SELECT
    d.Day_of_Week,
    COUNT(*) AS Orders,
    COUNT(DISTINCT d.date_id) AS Days_In_Data,
    CAST(1.0 * COUNT(*) / COUNT(DISTINCT d.date_id) AS DECIMAL(10,1)) AS Orders_Per_Day,
    SUM(f.Price_INR) AS Revenue,
    CAST(SUM(f.Price_INR) / COUNT(DISTINCT d.date_id) AS DECIMAL(12,0)) AS Revenue_Per_Day
FROM fact_swiggy_orders f
JOIN dim_date d ON f.date_id = d.date_id
WHERE d.Is_Anomaly_Day = 0
GROUP BY d.Day_of_Week, d.Day_Number
ORDER BY d.Day_Number;

--Location Based Analysis

--Top 10 Cities by Orders

SELECT TOP 10
l.City,
COUNT(*) AS Orders
FROM fact_swiggy_orders f
JOIN dim_location l ON f.location_id = l.location_id
GROUP BY l.City
ORDER BY COUNT(*) DESC, l.City;

--Top 10 Cities by Revenue

SELECT TOP 10
l.City,
SUM(Price_INR) AS Revenue
FROM fact_swiggy_orders f
JOIN dim_location l ON f.location_id = l.location_id
GROUP BY l.City
ORDER BY SUM(Price_INR) DESC, l.City;

--Revenue Contribution by State

SELECT
l.State,
SUM(Price_INR) AS Revenue
FROM fact_swiggy_orders f
JOIN dim_location l ON f.location_id = l.location_id
GROUP BY l.State
ORDER BY SUM(Price_INR) DESC, l.State;

--Restaurant Performance

--Top 10 Restaurants by Orders

SELECT TOP 10
r.Restaurant_Name,
COUNT(*) AS Orders
FROM fact_swiggy_orders f
JOIN dim_restaurant r ON f.restaurant_id = r.restaurant_id
GROUP BY r.Restaurant_Name
ORDER BY COUNT(*) DESC, r.Restaurant_Name;

--Top 10 Restaurants by Revenue

SELECT TOP 10
r.Restaurant_Name,
SUM(Price_INR) AS Revenue
FROM fact_swiggy_orders f
JOIN dim_restaurant r ON f.restaurant_id = r.restaurant_id
GROUP BY r.Restaurant_Name
ORDER BY SUM(Price_INR) DESC, r.Restaurant_Name;

--Category & Dish Analysis
--Top 10 Categories by Orders

SELECT TOP 10
c.Category,
COUNT(*) AS Orders
FROM fact_swiggy_orders f
JOIN dim_category c ON f.category_id = c.category_id
GROUP BY c.Category
ORDER BY COUNT(*) DESC, c.Category;

--Top 10 Categories by Revenue

SELECT TOP 10
c.Category,
SUM(Price_INR) AS Revenue
FROM fact_swiggy_orders f
JOIN dim_category c ON f.category_id = c.category_id
GROUP BY c.Category
ORDER BY SUM(Price_INR) DESC, c.Category;

--Top 10 Dishes by Orders

SELECT TOP 10
d.Dish_Name,
COUNT(*) AS Orders
FROM fact_swiggy_orders f
JOIN dim_dish d ON f.dish_id = d.dish_id
GROUP BY d.Dish_Name
ORDER BY COUNT(*) DESC, d.Dish_Name;

--Top 10 Dishes by Revenue

SELECT TOP 10
d.Dish_Name,
SUM(Price_INR) AS Revenue
FROM fact_swiggy_orders f
JOIN dim_dish d ON f.dish_id = d.dish_id
GROUP BY d.Dish_Name
ORDER BY SUM(Price_INR) DESC, d.Dish_Name;

--Food Type Analysis

SELECT
	d.Food_Type,
	COUNT(*) AS Orders,
	SUM(Price_INR) AS Revenue,
	CAST(AVG(Rating) AS DECIMAL(4,2)) AS Avg_Rating
FROM fact_swiggy_orders f
JOIN dim_dish d ON f.dish_id = d.dish_id
GROUP BY d.Food_Type
ORDER BY Revenue DESC;

-- Food Type Confidence Analysis

SELECT
	d.Food_Type_Confidence,
	COUNT(*) AS Orders,
	SUM(Price_INR) AS Revenue,
	CAST(AVG(Rating) AS DECIMAL(4,2)) AS Avg_Rating
FROM fact_swiggy_orders f
JOIN dim_dish d ON f.dish_id = d.dish_id
GROUP BY d.Food_Type_Confidence
ORDER BY Revenue DESC;

-- Cuisine Type Analysis

SELECT
	d.Cuisine_Type,
	COUNT(*) AS Orders,
	SUM(Price_INR) AS Revenue,
	CAST(AVG(Rating) AS DECIMAL(4,2)) AS Avg_Rating
FROM fact_swiggy_orders f
JOIN dim_dish d ON f.dish_id = d.dish_id
GROUP BY d.Cuisine_Type
ORDER BY Revenue DESC;

-- Category Type Analysis

SELECT
	d.Category_Type,
	COUNT(*) AS Orders,
	SUM(Price_INR) AS Revenue,
	CAST(AVG(Rating) AS DECIMAL(4,2)) AS Avg_Rating
FROM fact_swiggy_orders f
JOIN dim_dish d ON f.dish_id = d.dish_id
GROUP BY d.Category_Type
ORDER BY Revenue DESC;

--Price Category Analysis

SELECT
	Price_Category,
	COUNT(*) AS Orders,
	SUM(Price_INR) AS Revenue,
	SUM(Price_INR) * 1.0 / COUNT(*) AS Avg_Order_Value,
	CAST(AVG(Rating) AS DECIMAL(4,2)) AS Avg_Rating
FROM fact_swiggy_orders
GROUP BY Price_Category
ORDER BY Orders DESC;

--Rating Status Analysis

SELECT
	Rating_Status,
	COUNT(*) AS Orders,
	SUM(Price_INR) AS Revenue,
	SUM(Price_INR) * 1.0 / COUNT(*) AS Avg_Order_Value,
	CAST(AVG(Rating) AS DECIMAL(4,2)) AS Avg_Rating
FROM fact_swiggy_orders
GROUP BY Rating_Status;

--Weekday vs Weekend: PER-DAY averages (weekdays are 5 days, weekends 2, so totals would be misleading)
SELECT
    d.Day_Type,
    COUNT(f.order_id) AS Orders,
    COUNT(DISTINCT d.date_id) AS Days_In_Data,
    CAST(1.0 * COUNT(f.order_id) / COUNT(DISTINCT d.date_id) AS DECIMAL(10,1)) AS Orders_Per_Day,
    SUM(f.Price_INR) AS Revenue,
    CAST(SUM(f.Price_INR) / COUNT(DISTINCT d.date_id) AS DECIMAL(12,0)) AS Revenue_Per_Day,
    CAST(AVG(f.Price_INR) AS DECIMAL(10,2)) AS Avg_Item_Price,
    CAST(AVG(f.Rating) AS DECIMAL(4,2)) AS Avg_Rating
FROM fact_swiggy_orders f
JOIN dim_date d ON f.date_id = d.date_id
WHERE d.Is_Anomaly_Day = 0
GROUP BY d.Day_Type
ORDER BY d.Day_Type;

--Day-type queries below exclude the anomaly day and show the SHARE within each day type
--(weekdays are 5 days and weekends 2, so raw totals would not be comparable).

--Category-wise Order Distribution by Day Type (Weekday vs Weekend)

SELECT
    d.Day_Type,
    c.Category,
    COUNT(f.order_id) AS Orders,
    CAST(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (PARTITION BY d.Day_Type) AS DECIMAL(5,2)) AS Pct_Within_Day_Type
FROM fact_swiggy_orders f
JOIN dim_date d ON f.date_id = d.date_id
JOIN dim_category c ON f.category_id = c.category_id
WHERE d.Is_Anomaly_Day = 0
GROUP BY d.Day_Type, c.Category
ORDER BY d.Day_Type, Orders DESC;

--Price Category Analysis by Day Type (Weekday vs Weekend)

SELECT
    d.Day_Type,
    f.Price_Category,
    COUNT(f.order_id) AS Orders,
    CAST(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (PARTITION BY d.Day_Type) AS DECIMAL(5,2)) AS Pct_Within_Day_Type,
    SUM(f.Price_INR) AS Revenue,
    CAST(AVG(f.Rating) AS DECIMAL(4,2)) AS Avg_Rating
FROM fact_swiggy_orders f
JOIN dim_date d ON f.date_id = d.date_id
WHERE d.Is_Anomaly_Day = 0
GROUP BY d.Day_Type, f.Price_Category
ORDER BY d.Day_Type, Orders DESC;

--Rating Status Analysis by Day Type (Weekday vs Weekend)

SELECT
    d.Day_Type,
    f.Rating_Status,
    COUNT(f.order_id) AS Orders,
    CAST(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (PARTITION BY d.Day_Type) AS DECIMAL(5,2)) AS Pct_Within_Day_Type,
    SUM(f.Price_INR) AS Revenue,
    SUM(f.Price_INR) * 1.0 / COUNT(f.order_id) AS Avg_Price_Value
FROM fact_swiggy_orders f
JOIN dim_date d ON f.date_id = d.date_id
WHERE d.Is_Anomaly_Day = 0
GROUP BY d.Day_Type, f.Rating_Status
ORDER BY d.Day_Type, Orders DESC;

--Category Performance (Orders + Avg Rating)

SELECT
	c.Category,
	COUNT(*) AS Orders,
	CAST(AVG(f.Rating) AS DECIMAL(4,2)) AS Avg_Rating
FROM fact_swiggy_orders f
JOIN dim_category c ON f.category_id = c.category_id
GROUP BY c.Category
ORDER BY COUNT(*) DESC, c.Category;

--Customer Spending Insights
--Total Orders by Price Range

-- Half-open ranges (>= low AND < high): the old BETWEEN version put prices like 199.50 into 'Above 500'
WITH Price_Bucket AS (
    SELECT *,
        CASE
            WHEN Price_INR < 100 THEN '1. Below 100 INR'
            WHEN Price_INR < 200 THEN '2. 100-199 INR'
            WHEN Price_INR < 300 THEN '3. 200-299 INR'
            WHEN Price_INR < 400 THEN '4. 300-399 INR'
            WHEN Price_INR < 500 THEN '5. 400-499 INR'
            ELSE '6. 500 INR and above'
        END AS Price_Range
    FROM fact_swiggy_orders
)
SELECT Price_Range, COUNT(*) AS Orders, SUM(Price_INR) AS Sales_Value
FROM Price_Bucket
GROUP BY Price_Range
ORDER BY Price_Range;

--Rating Distribution (reviewed items only)
SELECT
    Rating,
    COUNT(*) AS Orders
FROM fact_swiggy_orders
WHERE Rating IS NOT NULL
GROUP BY Rating
ORDER BY Rating DESC;


--Top 10 Cities Contributing % to Total Revenue

WITH City_Revenue AS (
SELECT
	l.City,
	SUM(f.Price_INR) AS revenue
FROM fact_swiggy_orders f
JOIN dim_location l ON f.location_id = l.location_id
GROUP BY l.City
),
Total_Revenue AS (
	SELECT SUM(revenue) AS Total_Rev
	FROM City_Revenue
)
SELECT TOP 10
	c.City,
	c.revenue AS Revenue,
	CAST(
		(c.revenue * 100.0 / t.Total_Rev)
		AS DECIMAL(5,2)
		) AS Contribution_Percentage
FROM City_Revenue c
CROSS JOIN Total_Revenue t
ORDER BY c.revenue DESC;

--Month-Over-Month Growth % (based on revenue PER DAY, anomaly day excluded, so short months are not penalised)
--First month shows NULL because there is no previous month to compare with.

WITH Monthly_Revenue AS (
	SELECT
		d.Year,
		d.Month,
		d.Year_Month,
		SUM(CASE WHEN d.Is_Anomaly_Day = 0 THEN f.Price_INR ELSE 0 END) * 1.0
			/ COUNT(DISTINCT CASE WHEN d.Is_Anomaly_Day = 0 THEN d.date_id END) AS revenue   -- revenue PER DAY
	FROM fact_swiggy_orders f
	JOIN dim_date d ON f.date_id = d.date_id
	GROUP BY d.Year, d.Month,d.Year_Month
)
SELECT
	Year,
	Month,
	Year_Month,
	LAG(revenue) OVER (ORDER BY Year, Month)
	AS Previous_Month_Revenue,
	CAST(
	(
		(revenue - LAG(revenue) OVER (ORDER BY Year, Month)) * 100.0
		/ NULLIF(LAG(revenue) OVER (ORDER BY Year, Month), 0)
	) AS DECIMAL(5,2)
	) AS MoM_Growth_Percentage
FROM Monthly_Revenue
ORDER BY Year, Month;

--Running Total Revenue

SELECT
	d.Year,
	d.Month,
	d.Year_Month,
	SUM(f.Price_INR) AS Monthly_Revenue,
	SUM(SUM(f.Price_INR)) OVER (ORDER BY d.Year, d.Month)
	AS Running_Total_Revenue
FROM fact_swiggy_orders f
JOIN dim_date d ON f.date_id = d.date_id
GROUP BY d.Year, d.Month, d.Year_Month
ORDER BY d.Year, d.Month;

--Revenue per Restaurant per Month

SELECT
	d.Year,
	d.Month,
	d.Year_Month,
	r.Restaurant_Name,
	SUM(f.Price_INR) AS Monthly_Revenue
FROM fact_swiggy_orders f
JOIN dim_date d ON f.date_id = d.date_id
JOIN dim_restaurant r ON f.restaurant_id = r.restaurant_id
GROUP BY d.Year, d.Month, d.Year_Month, r.Restaurant_Name
ORDER BY d.Year, d.Month, r.Restaurant_Name;

--Restaurant Ranking by Monthly Revenue

WITH Restaurant_Monthly_Revenue AS (
	SELECT
		d.Year,
		d.Month,
		d.Year_Month,
		r.Restaurant_Name,
		SUM(f.Price_INR) AS Monthly_Revenue
	FROM fact_swiggy_orders f
	JOIN dim_date d ON f.date_id = d.date_id
	JOIN dim_restaurant r ON f.restaurant_id = r.restaurant_id
	GROUP BY d.Year, d.Month, d.Year_Month, r.Restaurant_Name
)
SELECT*
FROM (
	SELECT *,
		RANK() OVER (PARTITION BY Year, Month ORDER BY Monthly_Revenue DESC) AS Revenue_Rank
	FROM Restaurant_Monthly_Revenue
	) ranked
WHERE Revenue_Rank <= 5
ORDER BY Year, Month, Revenue_Rank;

--Average Order Value (AOV): one record = one dish line item, so AOV = average item price.
SELECT
    COUNT(*) AS Order_Records,
    SUM(Price_INR) AS Sales_Value,
    CAST(AVG(Price_INR) AS DECIMAL(10,2)) AS Avg_Item_Price,
    (SELECT DISTINCT PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY Price_INR) OVER () FROM fact_swiggy_orders) AS Median_Item_Price
FROM fact_swiggy_orders;

--Restaurant Contribution %

SELECT
	r.Restaurant_Name,
	SUM(f.Price_INR) AS Restaurant_Revenue,
	CAST(
		SUM(f.Price_INR) * 100.0 /
		SUM(SUM(f.Price_INR)) OVER () AS DECIMAL(5,2)
		) AS Contribution_Percentage
FROM fact_swiggy_orders f
JOIN dim_restaurant r ON f.restaurant_id = r.restaurant_id
GROUP BY r.Restaurant_Name
ORDER BY Restaurant_Revenue DESC;

--Category Contribution %

SELECT
	c.Category,
	SUM(f.Price_INR) AS Category_Revenue,
	CAST(
		SUM(f.Price_INR) * 100.0 /
		SUM(SUM(f.Price_INR)) OVER () AS DECIMAL(5,2)
		) AS Contribution_Percentage
FROM fact_swiggy_orders f
JOIN dim_category c ON f.category_id = c.category_id
GROUP BY c.Category
ORDER BY Contribution_Percentage DESC;

--Top 10 Restaurants by Revenue %

WITH Restaurant_Revenue AS (
SELECT
	r.Restaurant_Name,
	SUM(f.Price_INR) AS revenue,
	CAST(
		SUM(f.Price_INR) * 100.0 /
		SUM(SUM(f.Price_INR)) OVER ()
		AS DECIMAL(5,2)
		) AS Revenue_Percentage
FROM fact_swiggy_orders f
JOIN dim_restaurant r ON f.restaurant_id = r.restaurant_id
GROUP BY r.Restaurant_Name
)
SELECT TOP 10
	Restaurant_Name,
	revenue AS Revenue,
	Revenue_Percentage AS Revenue_Percentage
FROM Restaurant_Revenue
ORDER BY Revenue_Percentage DESC;

--Revenue Decline Detection (Month-wise, revenue per day)

WITH Monthly_Revenue AS (
	SELECT
		d.Year,
		d.Month,
		d.Year_Month,
		SUM(CASE WHEN d.Is_Anomaly_Day = 0 THEN f.Price_INR ELSE 0 END) * 1.0
			/ COUNT(DISTINCT CASE WHEN d.Is_Anomaly_Day = 0 THEN d.date_id END) AS revenue   -- revenue PER DAY
	FROM fact_swiggy_orders f
	JOIN dim_date d ON f.date_id = d.date_id
	GROUP BY d.Year, d.Month, d.Year_Month
)
SELECT *,
	LAG(revenue) OVER (ORDER BY Year, Month) AS Previous_Month_Revenue,
	revenue - LAG(revenue) OVER (ORDER BY Year, Month) AS Revenue_Change
FROM Monthly_Revenue
ORDER BY Year, Month;

--Revenue Trend Flagging (Growth / Decline, revenue per day)

WITH Monthly_Revenue AS (
	SELECT
		d.Year,
		d.Month,
		d.Year_Month,
		SUM(CASE WHEN d.Is_Anomaly_Day = 0 THEN f.Price_INR ELSE 0 END) * 1.0
			/ COUNT(DISTINCT CASE WHEN d.Is_Anomaly_Day = 0 THEN d.date_id END) AS revenue   -- revenue PER DAY
	FROM fact_swiggy_orders f
	JOIN dim_date d ON f.date_id = d.date_id
	GROUP BY d.Year, d.Month, d.Year_Month
)
SELECT *,
	CASE
	WHEN revenue > LAG(revenue) OVER (ORDER BY Year, Month) THEN 'Growth'
	WHEN revenue < LAG(revenue) OVER (ORDER BY Year, Month) THEN 'Decline'
	ELSE 'No Change'
	END AS Revenue_Trend
FROM Monthly_Revenue
ORDER BY Year, Month;

--Check
SELECT COUNT(*) AS fact_rows FROM fact_swiggy_orders;   -- expected 197401
