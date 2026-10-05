-- =====================================================================
-- 03_fact_table.sql
-- Grain: ONE ROW PER SOURCE RECORD (one dish line item). The source has no order id, so order_id below is a
-- surrogate key, not a real order number. Joins are on single natural keys; a row-count check proves no row is lost.
-- =====================================================================
USE Swiggy_DB;
GO

DROP VIEW  IF EXISTS vw_swiggy_analytics;
DROP TABLE IF EXISTS fact_swiggy_orders;   -- lets this script be re-run on its own
GO

CREATE TABLE fact_swiggy_orders(
    order_id      INT IDENTITY(1,1) PRIMARY KEY,
    date_id       INT NOT NULL,
    location_id   INT NOT NULL,
    restaurant_id INT NOT NULL,
    category_id   INT NOT NULL,
    dish_id       INT NOT NULL,
    Price_INR     DECIMAL(10,2),
    Rating        DECIMAL(3,1),        -- NULL = no reviews
    Rating_Count  INT,
    Price_Category VARCHAR(20),
    Rating_Status  VARCHAR(15),
    FOREIGN KEY (date_id)       REFERENCES dim_date(date_id),
    FOREIGN KEY (location_id)   REFERENCES dim_location(location_id),
    FOREIGN KEY (restaurant_id) REFERENCES dim_restaurant(restaurant_id),
    FOREIGN KEY (category_id)   REFERENCES dim_category(category_id),
    FOREIGN KEY (dish_id)       REFERENCES dim_dish(dish_id)
);
GO

INSERT INTO fact_swiggy_orders
(date_id, location_id, restaurant_id, category_id, dish_id, Price_INR, Rating, Rating_Count, Price_Category, Rating_Status)
SELECT dd.date_id, dl.location_id, dr.restaurant_id, dc.category_id, dsh.dish_id,
       s.Price_INR, s.Rating, s.Rating_Count, s.Price_Category, s.Rating_Status
FROM stg_swiggy_data s
JOIN dim_date       dd  ON dd.Order_Date      = s.Order_Date
JOIN dim_location   dl  ON dl.State = s.State AND dl.City = s.City AND dl.Location = s.Location
JOIN dim_restaurant dr  ON dr.Restaurant_Name = s.Restaurant_Name
JOIN dim_category   dc  ON dc.Category        = s.Category
JOIN dim_dish       dsh ON dsh.Dish_Name      = s.Dish_Name;
GO

-- Indexes on the foreign keys (faster joins in the KPI queries and Power BI)
CREATE INDEX ix_fact_date       ON fact_swiggy_orders(date_id);
CREATE INDEX ix_fact_location   ON fact_swiggy_orders(location_id);
CREATE INDEX ix_fact_restaurant ON fact_swiggy_orders(restaurant_id);
CREATE INDEX ix_fact_dish       ON fact_swiggy_orders(dish_id);
GO

-- RECONCILIATION: the two numbers MUST be equal (expected 197401). If not, a join dropped or duplicated rows.
SELECT (SELECT COUNT(*) FROM stg_swiggy_data)     AS stg_rows,
       (SELECT COUNT(*) FROM fact_swiggy_orders)  AS fact_rows;
SELECT (SELECT SUM(Price_INR) FROM stg_swiggy_data)    AS stg_value,
       (SELECT SUM(Price_INR) FROM fact_swiggy_orders) AS fact_value;   -- must match too
