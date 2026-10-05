-- =====================================================================
-- 02_dimension_tables.sql
-- Star schema dimensions. Changes: calendar-based dim_date (no missing days), ISO week/year fixed,
-- anomaly-day flag, NVARCHAR text, one row per dish name (unique) so the fact join cannot duplicate rows.
-- =====================================================================
USE Swiggy_DB;
GO

-- Drop in dependency order so this script can be re-run on its own
DROP VIEW  IF EXISTS vw_swiggy_analytics;
DROP TABLE IF EXISTS fact_swiggy_orders;
DROP TABLE IF EXISTS dim_date;
DROP TABLE IF EXISTS dim_location;
DROP TABLE IF EXISTS dim_restaurant;
DROP TABLE IF EXISTS dim_category;
DROP TABLE IF EXISTS dim_dish;
GO

CREATE TABLE dim_date(
    date_id               INT IDENTITY(1,1) PRIMARY KEY,
    Order_Date            DATE NOT NULL,
    Year                  INT,
    Month                 INT,
    Day                   INT,
    Year_Month            VARCHAR(8),
    Year_Month_Sort       INT,
    Month_Name            VARCHAR(20),
    Quarter               INT,
    Week_Number           INT,           -- ISO week
    Year_Week             VARCHAR(8),    -- ISO year + week, e.g. 2025-W01
    Year_Week_Sort        INT,
    Day_Number            INT,           -- Monday = 1 ... Sunday = 7
    Day_of_Week           VARCHAR(20),
    Year_Day_of_Week      VARCHAR(8),
    Year_Day_of_Week_Sort INT,
    Day_Type              VARCHAR(10),
    Is_Anomaly_Day        BIT NOT NULL DEFAULT 0   -- 1 = day with abnormal record volume (see below)
);

CREATE TABLE dim_location(
    location_id INT IDENTITY(1,1) PRIMARY KEY,
    State    NVARCHAR(100),
    City     NVARCHAR(100),
    Location NVARCHAR(200)
);

CREATE TABLE dim_restaurant(
    restaurant_id INT IDENTITY(1,1) PRIMARY KEY,
    Restaurant_Name NVARCHAR(200) NOT NULL UNIQUE
);

CREATE TABLE dim_category(
    category_id INT IDENTITY(1,1) PRIMARY KEY,
    Category NVARCHAR(250) NOT NULL UNIQUE
);

CREATE TABLE dim_dish(
    dish_id INT IDENTITY(1,1) PRIMARY KEY,
    Dish_Name            NVARCHAR(400) NOT NULL UNIQUE,
    Food_Type            VARCHAR(20),
    Food_Type_Confidence VARCHAR(10),
    Cuisine_Type         VARCHAR(50),
    Category_Type        VARCHAR(50)
);
GO

-- dim_date: one row for EVERY calendar day between first and last order date -------------------
SET DATEFIRST 1;   -- Monday = 1, so Saturday = 6 and Sunday = 7

DECLARE @min DATE = (SELECT MIN(Order_Date) FROM stg_swiggy_data);
DECLARE @max DATE = (SELECT MAX(Order_Date) FROM stg_swiggy_data);
DECLARE @median FLOAT;

-- Anomaly rule: a day with more than 1.5 x the median daily record count is flagged (expected: 22 Feb 2025 only,
-- 1,549 rows vs ~811 normal, caused by Bengaluru: ~826 rows vs ~81 normal). Rows are KEPT, only flagged.
;WITH daily AS (SELECT Order_Date, COUNT(*) AS cnt FROM stg_swiggy_data GROUP BY Order_Date)
SELECT TOP 1 @median = PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY cnt) OVER () FROM daily;

;WITH cal AS (
    SELECT @min AS d
    UNION ALL
    SELECT DATEADD(DAY, 1, d) FROM cal WHERE d < @max
),
daily AS (SELECT Order_Date, COUNT(*) AS cnt FROM stg_swiggy_data GROUP BY Order_Date)
INSERT INTO dim_date
(Order_Date, Year, Month, Day, Year_Month, Year_Month_Sort, Month_Name, Quarter, Week_Number, Year_Week, Year_Week_Sort,
 Day_Number, Day_of_Week, Year_Day_of_Week, Year_Day_of_Week_Sort, Day_Type, Is_Anomaly_Day)
SELECT
    c.d,
    YEAR(c.d), MONTH(c.d), DAY(c.d),
    CAST(YEAR(c.d) AS VARCHAR(4)) + '-' + LEFT(DATENAME(MONTH, c.d), 3),
    YEAR(c.d) * 100 + MONTH(c.d),
    DATENAME(MONTH, c.d),
    DATEPART(QUARTER, c.d),
    DATEPART(ISO_WEEK, c.d),
    -- ISO year (not calendar year!) so 29-31 Dec do not fall into week 1 of the same year
    CAST(YEAR(DATEADD(DAY, 26 - DATEPART(ISO_WEEK, c.d), c.d)) AS VARCHAR(4)) + '-W' + RIGHT('00' + CAST(DATEPART(ISO_WEEK, c.d) AS VARCHAR(2)), 2),
    YEAR(DATEADD(DAY, 26 - DATEPART(ISO_WEEK, c.d), c.d)) * 100 + DATEPART(ISO_WEEK, c.d),
    ((DATEPART(WEEKDAY, c.d) + @@DATEFIRST - 2) % 7) + 1,
    DATENAME(WEEKDAY, c.d),
    CAST(YEAR(c.d) AS VARCHAR(4)) + '-' + LEFT(DATENAME(WEEKDAY, c.d), 3),
    YEAR(c.d) * 100 + ((DATEPART(WEEKDAY, c.d) + @@DATEFIRST - 2) % 7) + 1,
    CASE WHEN ((DATEPART(WEEKDAY, c.d) + @@DATEFIRST - 2) % 7) + 1 >= 6 THEN 'Weekend' ELSE 'Weekday' END,   -- same formula as Day_Number, so it does not depend on DATEFIRST
    CASE WHEN ISNULL(dy.cnt, 0) > 1.5 * @median THEN 1 ELSE 0 END
FROM cal c
LEFT JOIN daily dy ON dy.Order_Date = c.d
OPTION (MAXRECURSION 0);

-- CHECK: expected 243 days (1 Jan - 31 Aug 2025), 1 anomaly day, 0 days without records
SELECT COUNT(*) AS days, SUM(CAST(Is_Anomaly_Day AS INT)) AS anomaly_days FROM dim_date;
SELECT d.Order_Date FROM dim_date d LEFT JOIN stg_swiggy_data s ON s.Order_Date = d.Order_Date WHERE s.ID IS NULL;  -- expected: no rows
SELECT Order_Date FROM dim_date WHERE Is_Anomaly_Day = 1;   -- expected: 2025-02-22
GO

-- dim_location / restaurant / category / dish --------------------------------------------------
INSERT INTO dim_location (State, City, Location)
SELECT DISTINCT State, City, Location FROM stg_swiggy_data;

INSERT INTO dim_restaurant (Restaurant_Name)
SELECT DISTINCT Restaurant_Name FROM stg_swiggy_data;

INSERT INTO dim_category (Category)
SELECT DISTINCT Category FROM stg_swiggy_data;

-- One row per dish name (labels are derived from the name, so MAX() just picks the single value).
INSERT INTO dim_dish (Dish_Name, Food_Type, Food_Type_Confidence, Cuisine_Type, Category_Type)
SELECT Dish_Name, MAX(Food_Type), MAX(Food_Type_Confidence), MAX(Cuisine_Type), MAX(Category_Type)
FROM stg_swiggy_data
GROUP BY Dish_Name;
GO

-- CHECKS
SELECT 'dim_location' AS tbl, COUNT(*) AS n FROM dim_location
UNION ALL SELECT 'dim_restaurant', COUNT(*) FROM dim_restaurant
UNION ALL SELECT 'dim_category',   COUNT(*) FROM dim_category
UNION ALL SELECT 'dim_dish',       COUNT(*) FROM dim_dish;
