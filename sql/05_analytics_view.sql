-- =====================================================================
-- 05_analytics_view.sql  - one flat view for Power BI / Python export
-- =====================================================================
USE Swiggy_DB;
GO
DROP VIEW IF EXISTS vw_swiggy_analytics;
GO
CREATE VIEW vw_swiggy_analytics AS
SELECT
    f.order_id,
    d.Order_Date, d.Year, d.Month, d.Day, d.Year_Month, d.Year_Month_Sort, d.Month_Name, d.Quarter,
    d.Week_Number, d.Year_Week, d.Year_Week_Sort, d.Day_Number, d.Day_of_Week, d.Year_Day_of_Week,
    d.Year_Day_of_Week_Sort, d.Day_Type, d.Is_Anomaly_Day,
    l.State, l.City, l.Location,
    r.Restaurant_Name,
    c.Category,
    di.Dish_Name, di.Food_Type, di.Food_Type_Confidence, di.Cuisine_Type, di.Category_Type,
    f.Price_INR, f.Rating, f.Rating_Count, f.Price_Category, f.Rating_Status
FROM fact_swiggy_orders f
JOIN dim_date       d  ON f.date_id       = d.date_id
JOIN dim_location   l  ON f.location_id   = l.location_id
JOIN dim_restaurant r  ON f.restaurant_id = r.restaurant_id
JOIN dim_category   c  ON f.category_id   = c.category_id
JOIN dim_dish       di ON f.dish_id       = di.dish_id;
GO

-- CHECK: expected 197401 rows
SELECT COUNT(*) AS view_rows FROM vw_swiggy_analytics;
