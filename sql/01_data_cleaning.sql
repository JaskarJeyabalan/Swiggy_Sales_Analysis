-- =====================================================================
-- 01_data_cleaning.sql   (rebuilt on the ORIGINAL Jan-Aug 2025 data)
-- raw_swiggy_data -> stg_swiggy_data (cleaned + classified)
-- Fixes vs. the first version: ratings no longer capped (invalid -> NULL), placeholder ratings handled,
-- exact types (DECIMAL for money), whole-word dish matching (no more 'banaana', 'veggie = Non-Veg',
-- 'steam rice = Beverage'), dish display names left untouched, GO between ALTER and UPDATE.
-- =====================================================================
USE Swiggy_DB;
GO

-- 1) RAW CHECKS -------------------------------------------------------------------------------
-- expected: 197430 rows, no NULLs/blanks in any column
SELECT COUNT(*) AS raw_rows FROM raw_swiggy_data;

SELECT
    SUM(CASE WHEN State           IS NULL OR LTRIM(RTRIM(State))           = '' THEN 1 ELSE 0 END) AS blank_state,
    SUM(CASE WHEN City            IS NULL OR LTRIM(RTRIM(City))            = '' THEN 1 ELSE 0 END) AS blank_city,
    SUM(CASE WHEN Order_Date      IS NULL OR LTRIM(RTRIM(Order_Date))      = '' THEN 1 ELSE 0 END) AS blank_date,
    SUM(CASE WHEN Restaurant_Name IS NULL OR LTRIM(RTRIM(Restaurant_Name)) = '' THEN 1 ELSE 0 END) AS blank_restaurant,
    SUM(CASE WHEN Location        IS NULL OR LTRIM(RTRIM(Location))        = '' THEN 1 ELSE 0 END) AS blank_location,
    SUM(CASE WHEN Category        IS NULL OR LTRIM(RTRIM(Category))        = '' THEN 1 ELSE 0 END) AS blank_category,
    SUM(CASE WHEN Dish_Name       IS NULL OR LTRIM(RTRIM(Dish_Name))       = '' THEN 1 ELSE 0 END) AS blank_dish,
    SUM(CASE WHEN TRY_CAST(Price_INR    AS DECIMAL(10,2)) IS NULL THEN 1 ELSE 0 END) AS bad_price,
    SUM(CASE WHEN TRY_CAST(Rating       AS DECIMAL(3,1))  IS NULL THEN 1 ELSE 0 END) AS bad_rating,
    SUM(CASE WHEN TRY_CAST(Rating_Count AS INT)           IS NULL THEN 1 ELSE 0 END) AS bad_rating_count,
    SUM(CASE WHEN TRY_CONVERT(DATE, LTRIM(RTRIM(Order_Date)), 105) IS NULL THEN 1 ELSE 0 END) AS bad_date
FROM raw_swiggy_data;
GO

-- 2) STAGING TABLE ----------------------------------------------------------------------------
DROP TABLE IF EXISTS stg_swiggy_data;   -- lets this script be re-run on its own
GO
CREATE TABLE stg_swiggy_data (
    ID              INT IDENTITY(1,1) PRIMARY KEY,
    State           NVARCHAR(100) NULL,
    City            NVARCHAR(100) NULL,
    Order_Date      DATE          NULL,
    Restaurant_Name NVARCHAR(200) NULL,
    Location        NVARCHAR(200) NULL,
    Category        NVARCHAR(250) NULL,
    Dish_Name       NVARCHAR(400) NULL,
    Price_INR       DECIMAL(10,2) NULL,    -- money is DECIMAL, not FLOAT
    Rating          DECIMAL(3,1)  NULL,
    Rating_Count    INT           NULL
);
GO

INSERT INTO stg_swiggy_data (State, City, Order_Date, Restaurant_Name, Location, Category, Dish_Name, Price_INR, Rating, Rating_Count)
SELECT
    COALESCE(NULLIF(LTRIM(RTRIM(State)),''),'Unknown'),
    COALESCE(NULLIF(LTRIM(RTRIM(City)),''),'Unknown'),
    TRY_CONVERT(DATE, LTRIM(RTRIM(Order_Date)), 105),          -- 105 = dd-mm-yyyy
    COALESCE(NULLIF(LTRIM(RTRIM(Restaurant_Name)),''),'Unknown'),
    COALESCE(NULLIF(LTRIM(RTRIM(Location)),''),'Unknown'),
    COALESCE(NULLIF(LTRIM(RTRIM(Category)),''),'Unknown'),
    COALESCE(NULLIF(LTRIM(RTRIM(Dish_Name)),''),'Unknown'),
    TRY_CAST(Price_INR AS DECIMAL(10,2)),
    -- A rating outside 1-5 is INVALID: it becomes NULL (it is never capped to 5, which would hide bad data)
    CASE WHEN TRY_CAST(Rating AS DECIMAL(3,1)) BETWEEN 1 AND 5 THEN TRY_CAST(Rating AS DECIMAL(3,1)) END,
    TRY_CAST(Rating_Count AS INT)
FROM raw_swiggy_data;

-- CHECK: expected 197430 rows, 0 NULL dates
SELECT COUNT(*) AS stg_rows, SUM(CASE WHEN Order_Date IS NULL THEN 1 ELSE 0 END) AS null_dates FROM stg_swiggy_data;
GO

-- 3) DUPLICATES -------------------------------------------------------------------------------
-- The dataset has NO order id, so identical rows cannot be proven to be duplicates (they could be repeat
-- orders). We remove copies and document it. SQL Server compares text case-insensitively, so rows that differ only
-- in letter case also count as copies (29 rows here; a case-sensitive check finds 27). Expected rows removed: 29  (197430 -> 197401)
WITH CTE AS (
    SELECT *, ROW_NUMBER() OVER (
        PARTITION BY State, City, Order_Date, Restaurant_Name, Location, Category, Dish_Name, Price_INR, Rating, Rating_Count
        ORDER BY (SELECT NULL)) AS RN
    FROM stg_swiggy_data
)
DELETE FROM CTE WHERE RN > 1;

SELECT COUNT(*) AS stg_rows_after_dedupe FROM stg_swiggy_data;   -- expected 197401
GO

-- 4) RATING PLACEHOLDER FIX -------------------------------------------------------------------
-- In the raw data about 40% of rows have Rating_Count = 0 and ~95% of those carry the same rating, 4.4.
-- That is a default/placeholder, not a customer rating, so it is set to NULL (= not rated).
UPDATE stg_swiggy_data SET Rating = NULL WHERE Rating_Count IS NULL OR Rating_Count = 0;
-- expected rows with NULL rating afterwards:
GO

-- 5) DERIVED COLUMNS --------------------------------------------------------------------------
ALTER TABLE stg_swiggy_data ADD
    Dish_Key             NVARCHAR(500) NULL,   -- normalised text used ONLY for classification
    Food_Type            VARCHAR(20)   NULL,
    Food_Type_Confidence VARCHAR(10)   NULL,
    Cuisine_Type         VARCHAR(50)   NULL,
    Category_Type        VARCHAR(50)   NULL,
    Price_Category       VARCHAR(20)   NULL,
    Rating_Status        VARCHAR(15)   NULL;
GO

-- 5a) Dish_Key = lower-case, punctuation -> space, single spaces, one space padded each side.
--     The padding lets LIKE '% chicken%' match the START of a word only (so 'veggie' never matches 'egg').
UPDATE stg_swiggy_data SET Dish_Key = REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(LOWER(Dish_Name), N'-', N' '), N'(', N' '), N')', N' '), N'[', N' '), N']', N' '), N'{', N' '), N'}', N' '), N',', N' '), N'/', N' '), N'&', N' '), N'.', N' '), N'+', N' '), N':', N' '), N';', N' '), N'!', N' '), N'*', N' '), N'"', N' '), N'''', N' '), N'’', N' '), N'|', N' ');
UPDATE stg_swiggy_data SET Dish_Key = REPLACE(Dish_Key, N'  ', N' ');
UPDATE stg_swiggy_data SET Dish_Key = REPLACE(Dish_Key, N'  ', N' ');
UPDATE stg_swiggy_data SET Dish_Key = REPLACE(Dish_Key, N'  ', N' ');
UPDATE stg_swiggy_data SET Dish_Key = N' ' + LTRIM(RTRIM(Dish_Key)) + N' ';

-- Spelling fixes on WHOLE WORDS only (the old version replaced 'nan' inside 'banana' -> 'banaana').
-- The dish display name (Dish_Name) is left exactly as in the source.
UPDATE stg_swiggy_data SET Dish_Key =
REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(Dish_Key, N' chciken ', N' chicken '), N' panneer ', N' paneer '), N' panner ', N' paneer '), N' briyani ', N' biryani '), N' biriyani ', N' biryani '), N' bryani ', N' biryani '), N' lolypop ', N' lollipop '), N' hydrabadi ', N' hyderabadi '), N' hyderabadhi ', N' hyderabadi '), N' chowmin ', N' chowmein '), N' fride ', N' fried '), N' burji ', N' bhurji '), N' masla ', N' masala '), N' shezwan ', N' schezwan '), N' kheema ', N' keema '), N' choclate ', N' chocolate '), N' idly ', N' idli '), N' parrota ', N' parotta '), N' makkanvala ', N' makhanwala '), N' vanila ', N' vanilla '), N' strawbery ', N' strawberry '), N' bluebery ', N' blueberry '), N' manchurain ', N' manchurian '), N' nan ', N' naan '), N' kuma ', N' kurma '), N' tutty fruity ', N' tutti frutti '), N' channa bathura ', N' chole bhature '), N' chana bathura ', N' chole bhature ');
GO

-- 5b) Veg / Non-Veg.  Order matters: strong non-veg words -> explicit veg words -> weak non-veg -> typical-veg staples.
--     'eggless' / 'eggplant' are excluded from the egg rule.  Anything else stays 'Unknown' (honest, not guessed).
UPDATE stg_swiggy_data
SET Food_Type =
CASE
-- Veg 'keema' dishes (soya / paneer / veg keema) must win over the non-veg word 'keema'
WHEN (Dish_Key LIKE '% soya keema%' OR Dish_Key LIKE '% paneer keema%' OR Dish_Key LIKE '% veg keema%')
     AND NOT (Dish_Key LIKE '% chicken%' OR Dish_Key LIKE '% mutton%' OR Dish_Key LIKE '% non veg%')
THEN 'Veg'
WHEN (Dish_Key LIKE '% non veg%'
     OR Dish_Key LIKE '% nonveg%'
     OR Dish_Key LIKE '% chicken%'
     OR Dish_Key LIKE '% mutton%'
     OR Dish_Key LIKE '% lamb%'
     OR Dish_Key LIKE '% fish%'
     OR Dish_Key LIKE '% prawn%'
     OR Dish_Key LIKE '% shrimp%'
     OR Dish_Key LIKE '% crab%'
     OR Dish_Key LIKE '% squid%'
     OR Dish_Key LIKE '% egg%'
     OR Dish_Key LIKE '% omelette%'
     OR Dish_Key LIKE '% omelet%'
     OR Dish_Key LIKE '% bacon%'
     OR Dish_Key LIKE '% sausage%'
     OR Dish_Key LIKE '% pepperoni%'
     OR Dish_Key LIKE '% salami%'
     OR Dish_Key LIKE '% beef%'
     OR Dish_Key LIKE '% pork%'
     OR Dish_Key LIKE '% keema%'
     OR Dish_Key LIKE '% wings%'
     OR Dish_Key LIKE '% tuna%'
     OR Dish_Key LIKE '% salmon%'
     OR Dish_Key LIKE '% pomfret%'
     OR Dish_Key LIKE '% seafood%')
     AND NOT (Dish_Key LIKE '% eggless%'
     OR Dish_Key LIKE '% eggplant%'
     OR Dish_Key LIKE '% egg less%')
THEN 'Non-Veg'
WHEN (Dish_Key LIKE '% veg%'
     OR Dish_Key LIKE '% paneer%'
     OR Dish_Key LIKE '% mushroom%'
     OR Dish_Key LIKE '% aloo%'
     OR Dish_Key LIKE '% gobi%'
     OR Dish_Key LIKE '% palak%'
     OR Dish_Key LIKE '% rajma%'
     OR Dish_Key LIKE '% chole%'
     OR Dish_Key LIKE '% chana%'
     OR Dish_Key LIKE '% tofu%'
     OR Dish_Key LIKE '% soya%'
     OR Dish_Key LIKE '% eggless%'
     OR Dish_Key LIKE '% eggplant%'
     OR Dish_Key LIKE '% baby corn%'
     OR Dish_Key LIKE '% sweet corn%'
     OR Dish_Key LIKE '% corn%'
     OR Dish_Key LIKE '% dal%'
     OR Dish_Key LIKE '% poori%'
     OR Dish_Key LIKE '% tikki%'
     OR Dish_Key LIKE '% hara bhara%'
     OR Dish_Key LIKE '% dahi%'
     OR Dish_Key LIKE '% kathal%'
     OR Dish_Key LIKE '% jackfruit%'
     OR Dish_Key LIKE '% beetroot%'
     OR Dish_Key LIKE '% subz%')
THEN 'Veg'
WHEN (Dish_Key LIKE '% kebab%'
     OR Dish_Key LIKE '% kabab%'
     OR Dish_Key LIKE '% tikka%'
     OR Dish_Key LIKE '% seekh%'
     OR Dish_Key LIKE '% tangdi%'
     OR Dish_Key LIKE '% lollipop%'
     OR Dish_Key LIKE '% zinger%'
     OR Dish_Key LIKE '% mcspicy%'
     OR Dish_Key LIKE '% whopper%'
     OR Dish_Key LIKE '% bucket%')
THEN 'Non-Veg'
WHEN (Dish_Key LIKE '% idli%'
     OR Dish_Key LIKE '% dosa%'
     OR Dish_Key LIKE '% uttapam%'
     OR Dish_Key LIKE '% uttappam%'
     OR Dish_Key LIKE '% upma%'
     OR Dish_Key LIKE '% pongal%'
     OR Dish_Key LIKE '% sambar%'
     OR Dish_Key LIKE '% rasam%'
     OR Dish_Key LIKE '% curd%'
     OR Dish_Key LIKE '% raita%'
     OR Dish_Key LIKE '% raitha%'
     OR Dish_Key LIKE '% gulab%'
     OR Dish_Key LIKE '% jamun%'
     OR Dish_Key LIKE '% halwa%'
     OR Dish_Key LIKE '% rasgulla%'
     OR Dish_Key LIKE '% laddu%'
     OR Dish_Key LIKE '% ladoo%'
     OR Dish_Key LIKE '% barfi%'
     OR Dish_Key LIKE '% kulfi%'
     OR Dish_Key LIKE '% jalebi%'
     OR Dish_Key LIKE '% samosa%'
     OR Dish_Key LIKE '% pakoda%'
     OR Dish_Key LIKE '% pakora%'
     OR Dish_Key LIKE '% bhaji%'
     OR Dish_Key LIKE '% khichdi%'
     OR Dish_Key LIKE '% lassi%'
     OR Dish_Key LIKE '% juice%'
     OR Dish_Key LIKE '% coffee%'
     OR Dish_Key LIKE '% tea %'
     OR Dish_Key LIKE '% chai%'
     OR Dish_Key LIKE '% soda%'
     OR Dish_Key LIKE '% mojito%'
     OR Dish_Key LIKE '% lemonade%'
     OR Dish_Key LIKE '% buttermilk%'
     OR Dish_Key LIKE '% shake%'
     OR Dish_Key LIKE '%milkshake%'
     OR Dish_Key LIKE '% ice cream%'
     OR Dish_Key LIKE '% fries%'
     OR Dish_Key LIKE '% french fries%'
     OR Dish_Key LIKE '% chips%'
     OR Dish_Key LIKE '% naan%'
     OR Dish_Key LIKE '% roti %'
     OR Dish_Key LIKE '% rotis %'
     OR Dish_Key LIKE '% chapati%'
     OR Dish_Key LIKE '% paratha%'
     OR Dish_Key LIKE '% kulcha%'
     OR Dish_Key LIKE '% phulka%'
     OR Dish_Key LIKE '% papad%'
     OR Dish_Key LIKE '% pickle%'
     OR Dish_Key LIKE '% chutney%'
     OR Dish_Key LIKE '% murukku%'
     OR Dish_Key LIKE '% mixture%'
     OR Dish_Key LIKE '% kheer%'
     OR Dish_Key LIKE '% payasam%'
     OR Dish_Key LIKE '% rasmalai%')
THEN 'Veg'
ELSE 'Unknown'
END,
    Food_Type_Confidence =
CASE
WHEN (Dish_Key LIKE '% soya keema%' OR Dish_Key LIKE '% paneer keema%' OR Dish_Key LIKE '% veg keema%')
     AND NOT (Dish_Key LIKE '% chicken%' OR Dish_Key LIKE '% mutton%' OR Dish_Key LIKE '% non veg%')
THEN 'High'
WHEN (Dish_Key LIKE '% non veg%'
     OR Dish_Key LIKE '% nonveg%'
     OR Dish_Key LIKE '% chicken%'
     OR Dish_Key LIKE '% mutton%'
     OR Dish_Key LIKE '% lamb%'
     OR Dish_Key LIKE '% fish%'
     OR Dish_Key LIKE '% prawn%'
     OR Dish_Key LIKE '% shrimp%'
     OR Dish_Key LIKE '% crab%'
     OR Dish_Key LIKE '% squid%'
     OR Dish_Key LIKE '% egg%'
     OR Dish_Key LIKE '% omelette%'
     OR Dish_Key LIKE '% omelet%'
     OR Dish_Key LIKE '% bacon%'
     OR Dish_Key LIKE '% sausage%'
     OR Dish_Key LIKE '% pepperoni%'
     OR Dish_Key LIKE '% salami%'
     OR Dish_Key LIKE '% beef%'
     OR Dish_Key LIKE '% pork%'
     OR Dish_Key LIKE '% keema%'
     OR Dish_Key LIKE '% wings%'
     OR Dish_Key LIKE '% tuna%'
     OR Dish_Key LIKE '% salmon%'
     OR Dish_Key LIKE '% pomfret%'
     OR Dish_Key LIKE '% seafood%')
     AND NOT (Dish_Key LIKE '% eggless%'
     OR Dish_Key LIKE '% eggplant%'
     OR Dish_Key LIKE '% egg less%')
THEN 'High'
WHEN (Dish_Key LIKE '% veg%'
     OR Dish_Key LIKE '% paneer%'
     OR Dish_Key LIKE '% mushroom%'
     OR Dish_Key LIKE '% aloo%'
     OR Dish_Key LIKE '% gobi%'
     OR Dish_Key LIKE '% palak%'
     OR Dish_Key LIKE '% rajma%'
     OR Dish_Key LIKE '% chole%'
     OR Dish_Key LIKE '% chana%'
     OR Dish_Key LIKE '% tofu%'
     OR Dish_Key LIKE '% soya%'
     OR Dish_Key LIKE '% eggless%'
     OR Dish_Key LIKE '% eggplant%'
     OR Dish_Key LIKE '% baby corn%'
     OR Dish_Key LIKE '% sweet corn%'
     OR Dish_Key LIKE '% corn%'
     OR Dish_Key LIKE '% dal%'
     OR Dish_Key LIKE '% poori%'
     OR Dish_Key LIKE '% tikki%'
     OR Dish_Key LIKE '% hara bhara%'
     OR Dish_Key LIKE '% dahi%'
     OR Dish_Key LIKE '% kathal%'
     OR Dish_Key LIKE '% jackfruit%'
     OR Dish_Key LIKE '% beetroot%'
     OR Dish_Key LIKE '% subz%')
THEN 'High'
WHEN (Dish_Key LIKE '% kebab%'
     OR Dish_Key LIKE '% kabab%'
     OR Dish_Key LIKE '% tikka%'
     OR Dish_Key LIKE '% seekh%'
     OR Dish_Key LIKE '% tangdi%'
     OR Dish_Key LIKE '% lollipop%'
     OR Dish_Key LIKE '% zinger%'
     OR Dish_Key LIKE '% mcspicy%'
     OR Dish_Key LIKE '% whopper%'
     OR Dish_Key LIKE '% bucket%')
THEN 'Medium'
WHEN (Dish_Key LIKE '% idli%'
     OR Dish_Key LIKE '% dosa%'
     OR Dish_Key LIKE '% uttapam%'
     OR Dish_Key LIKE '% uttappam%'
     OR Dish_Key LIKE '% upma%'
     OR Dish_Key LIKE '% pongal%'
     OR Dish_Key LIKE '% sambar%'
     OR Dish_Key LIKE '% rasam%'
     OR Dish_Key LIKE '% curd%'
     OR Dish_Key LIKE '% raita%'
     OR Dish_Key LIKE '% raitha%'
     OR Dish_Key LIKE '% gulab%'
     OR Dish_Key LIKE '% jamun%'
     OR Dish_Key LIKE '% halwa%'
     OR Dish_Key LIKE '% rasgulla%'
     OR Dish_Key LIKE '% laddu%'
     OR Dish_Key LIKE '% ladoo%'
     OR Dish_Key LIKE '% barfi%'
     OR Dish_Key LIKE '% kulfi%'
     OR Dish_Key LIKE '% jalebi%'
     OR Dish_Key LIKE '% samosa%'
     OR Dish_Key LIKE '% pakoda%'
     OR Dish_Key LIKE '% pakora%'
     OR Dish_Key LIKE '% bhaji%'
     OR Dish_Key LIKE '% khichdi%'
     OR Dish_Key LIKE '% lassi%'
     OR Dish_Key LIKE '% juice%'
     OR Dish_Key LIKE '% coffee%'
     OR Dish_Key LIKE '% tea %'
     OR Dish_Key LIKE '% chai%'
     OR Dish_Key LIKE '% soda%'
     OR Dish_Key LIKE '% mojito%'
     OR Dish_Key LIKE '% lemonade%'
     OR Dish_Key LIKE '% buttermilk%'
     OR Dish_Key LIKE '% shake%'
     OR Dish_Key LIKE '%milkshake%'
     OR Dish_Key LIKE '% ice cream%'
     OR Dish_Key LIKE '% fries%'
     OR Dish_Key LIKE '% french fries%'
     OR Dish_Key LIKE '% chips%'
     OR Dish_Key LIKE '% naan%'
     OR Dish_Key LIKE '% roti %'
     OR Dish_Key LIKE '% rotis %'
     OR Dish_Key LIKE '% chapati%'
     OR Dish_Key LIKE '% paratha%'
     OR Dish_Key LIKE '% kulcha%'
     OR Dish_Key LIKE '% phulka%'
     OR Dish_Key LIKE '% papad%'
     OR Dish_Key LIKE '% pickle%'
     OR Dish_Key LIKE '% chutney%'
     OR Dish_Key LIKE '% murukku%'
     OR Dish_Key LIKE '% mixture%'
     OR Dish_Key LIKE '% kheer%'
     OR Dish_Key LIKE '% payasam%'
     OR Dish_Key LIKE '% rasmalai%')
THEN 'Medium'
ELSE 'Low'
END;
GO

-- 5c) Cuisine type.  Order matters (first match wins).  Unmatched = 'Unclassified' (not a real cuisine).
UPDATE stg_swiggy_data
SET Cuisine_Type =
CASE
-- Beverage
WHEN (Dish_Key LIKE '% juice%'
     OR Dish_Key LIKE '% shake%'
     OR Dish_Key LIKE '%milkshake%'
     OR Dish_Key LIKE '% lassi%'
     OR Dish_Key LIKE '% coffee%'
     OR Dish_Key LIKE '% tea %'
     OR Dish_Key LIKE '% teas %'
     OR Dish_Key LIKE '% chai%'
     OR Dish_Key LIKE '% soda%'
     OR Dish_Key LIKE '% mojito%'
     OR Dish_Key LIKE '% cooler%'
     OR Dish_Key LIKE '% sharbat%'
     OR Dish_Key LIKE '% smoothie%'
     OR Dish_Key LIKE '% coke%'
     OR Dish_Key LIKE '% cola%'
     OR Dish_Key LIKE '% pepsi%'
     OR Dish_Key LIKE '% fanta%'
     OR Dish_Key LIKE '% 7up%'
     OR Dish_Key LIKE '% sprite%'
     OR Dish_Key LIKE '% lemonade%'
     OR Dish_Key LIKE '% buttermilk%'
     OR Dish_Key LIKE '% badam milk%'
     OR Dish_Key LIKE '% thums up%'
     OR Dish_Key LIKE '% limca%'
     OR Dish_Key LIKE '% frappe%'
     OR Dish_Key LIKE '% cappuccino%'
     OR Dish_Key LIKE '% latte%'
     OR Dish_Key LIKE '% espresso%'
     OR Dish_Key LIKE '% mocktail%')
THEN 'Beverage'

-- Dessert
WHEN (Dish_Key LIKE '% ice cream%'
     OR Dish_Key LIKE '% cake%'
     OR Dish_Key LIKE '%cupcake%'
     OR Dish_Key LIKE '%cheesecake%'
     OR Dish_Key LIKE '% brownie%'
     OR Dish_Key LIKE '% halwa%'
     OR Dish_Key LIKE '% jamun%'
     OR Dish_Key LIKE '% rasgulla%'
     OR Dish_Key LIKE '% laddu%'
     OR Dish_Key LIKE '% ladoo%'
     OR Dish_Key LIKE '% barfi%'
     OR Dish_Key LIKE '% peda%'
     OR Dish_Key LIKE '% pedha%'
     OR Dish_Key LIKE '% kulfi%'
     OR Dish_Key LIKE '% falooda%'
     OR Dish_Key LIKE '% mousse%'
     OR Dish_Key LIKE '% sundae%'
     OR Dish_Key LIKE '% chocolate%'
     OR Dish_Key LIKE '% cinnamon roll%'
     OR Dish_Key LIKE '% swiss roll%'
     OR Dish_Key LIKE '% sweet roll%'
     OR Dish_Key LIKE '% choco roll%'
     OR Dish_Key LIKE '% gulab%'
     OR Dish_Key LIKE '% jalebi%'
     OR Dish_Key LIKE '% rasmalai%'
     OR Dish_Key LIKE '% kheer%'
     OR Dish_Key LIKE '% payasam%'
     OR Dish_Key LIKE '% tiramisu%'
     OR Dish_Key LIKE '% donut%'
     OR Dish_Key LIKE '% doughnut%'
     OR Dish_Key LIKE '% pastry%'
     OR Dish_Key LIKE '% waffle%'
     OR Dish_Key LIKE '% cookie%'
     OR Dish_Key LIKE '% macaron%')
THEN 'Dessert'

-- Biryani
WHEN (Dish_Key LIKE '% biryani%')
THEN 'Biryani'

-- Korean
WHEN (Dish_Key LIKE '% korean%')
THEN 'Korean'

-- Chinese
WHEN (Dish_Key LIKE '% noodle%'
     OR Dish_Key LIKE '% fried rice%'
     OR Dish_Key LIKE '% manchurian%'
     OR Dish_Key LIKE '% schezwan%'
     OR Dish_Key LIKE '% hakka%'
     OR Dish_Key LIKE '% chilli%'
     OR Dish_Key LIKE '% chowmein%'
     OR Dish_Key LIKE '% dimsum%'
     OR Dish_Key LIKE '% dim sum%'
     OR Dish_Key LIKE '% spring roll%'
     OR Dish_Key LIKE '% szechuan%'
     OR Dish_Key LIKE '% hot and sour%'
     OR Dish_Key LIKE '% sweet and sour%'
     OR Dish_Key LIKE '% wonton%'
     OR Dish_Key LIKE '% chopsuey%'
     OR Dish_Key LIKE '% thukpa%')
     AND NOT (Dish_Key LIKE '% chilli cheese%'
     OR Dish_Key LIKE '% chilli flakes%')
THEN 'Chinese'

-- Fast Food
WHEN (Dish_Key LIKE '% pizza%'
     OR Dish_Key LIKE '% burger%'
     OR Dish_Key LIKE '% pasta%'
     OR Dish_Key LIKE '% fries%'
     OR Dish_Key LIKE '% sandwich%'
     OR Dish_Key LIKE '% wrap%'
     OR Dish_Key LIKE '% roll%'
     OR Dish_Key LIKE '% shawarma%'
     OR Dish_Key LIKE '% taco%'
     OR Dish_Key LIKE '% nacho%'
     OR Dish_Key LIKE '% momo%'
     OR Dish_Key LIKE '% burrito%'
     OR Dish_Key LIKE '% zinger%'
     OR Dish_Key LIKE '% whopper%'
     OR Dish_Key LIKE '% mcspicy%'
     OR Dish_Key LIKE '% mcaloo%'
     OR Dish_Key LIKE '% bucket%'
     OR Dish_Key LIKE '% evm %'
     OR Dish_Key LIKE '% vada pav%'
     OR Dish_Key LIKE '% vadapav%'
     OR Dish_Key LIKE '% pav bhaji%'
     OR Dish_Key LIKE '% nugget%'
     OR Dish_Key LIKE '% hot dog%'
     OR Dish_Key LIKE '% puff%'
     OR Dish_Key LIKE '% garlic bread%'
     OR Dish_Key LIKE '% quesadilla%')
THEN 'Fast Food'

-- South Indian
WHEN (Dish_Key LIKE '% dosa%'
     OR Dish_Key LIKE '% idli%'
     OR Dish_Key LIKE '% vada%'
     OR Dish_Key LIKE '% appam%'
     OR Dish_Key LIKE '% puttu%'
     OR Dish_Key LIKE '% rasam%'
     OR Dish_Key LIKE '% sambar%'
     OR Dish_Key LIKE '% poori%'
     OR Dish_Key LIKE '% upma%'
     OR Dish_Key LIKE '% akki roti%'
     OR Dish_Key LIKE '% pongal%'
     OR Dish_Key LIKE '% uttapam%'
     OR Dish_Key LIKE '% uttappam%'
     OR Dish_Key LIKE '% parotta%'
     OR Dish_Key LIKE '% parota%'
     OR Dish_Key LIKE '% chettinad%'
     OR Dish_Key LIKE '% andhra%'
     OR Dish_Key LIKE '% curd rice%'
     OR Dish_Key LIKE '% lemon rice%'
     OR Dish_Key LIKE '% bisibele%'
     OR Dish_Key LIKE '% meals%')
THEN 'South Indian'

-- North Indian
WHEN (Dish_Key LIKE '% naan%'
     OR Dish_Key LIKE '% kulcha%'
     OR Dish_Key LIKE '% paratha%'
     OR Dish_Key LIKE '% korma%'
     OR Dish_Key LIKE '% makhani%'
     OR Dish_Key LIKE '% butter chicken%'
     OR Dish_Key LIKE '% kadai%'
     OR Dish_Key LIKE '% kadhai%'
     OR Dish_Key LIKE '% tikka masala%'
     OR Dish_Key LIKE '% tandoori%'
     OR Dish_Key LIKE '% rajma%'
     OR Dish_Key LIKE '% chole%'
     OR Dish_Key LIKE '% bhature%'
     OR Dish_Key LIKE '% dal tadka%'
     OR Dish_Key LIKE '% dal fry%'
     OR Dish_Key LIKE '% jeera rice%'
     OR Dish_Key LIKE '% roti %'
     OR Dish_Key LIKE '% rotis %'
     OR Dish_Key LIKE '% tandoor%'
     OR Dish_Key LIKE '% palak paneer%'
     OR Dish_Key LIKE '% paneer butter%'
     OR Dish_Key LIKE '% shahi%'
     OR Dish_Key LIKE '% malai%'
     OR Dish_Key LIKE '% amritsari%')
THEN 'North Indian'
ELSE 'Unclassified'
END;
GO

-- 5d) Meal role (needs Cuisine_Type, so it is a separate statement).
UPDATE stg_swiggy_data
SET Category_Type =
CASE
-- Beverage
WHEN Cuisine_Type = 'Beverage'
THEN 'Beverage'

-- Dessert
WHEN Cuisine_Type = 'Dessert'
THEN 'Dessert'

-- Breakfast Item
WHEN (Dish_Key LIKE '% dosa%'
     OR Dish_Key LIKE '% idli%'
     OR Dish_Key LIKE '% vada%'
     OR Dish_Key LIKE '% upma%'
     OR Dish_Key LIKE '% appam%'
     OR Dish_Key LIKE '% puttu%'
     OR Dish_Key LIKE '% pongal%'
     OR Dish_Key LIKE '% akki roti%'
     OR Dish_Key LIKE '% poori%'
     OR Dish_Key LIKE '% uttapam%'
     OR Dish_Key LIKE '% uttappam%')
     AND NOT (Dish_Key LIKE '% vada pav%'
     OR Dish_Key LIKE '% vadapav%')
THEN 'Breakfast Item'

-- Snacks
WHEN (Dish_Key LIKE '% chips%'
     OR Dish_Key LIKE '% papad%'
     OR Dish_Key LIKE '% nacho%'
     OR Dish_Key LIKE '% popcorn%'
     OR Dish_Key LIKE '% pakoda%'
     OR Dish_Key LIKE '% pakora%'
     OR Dish_Key LIKE '% peanuts%'
     OR Dish_Key LIKE '% fries%'
     OR Dish_Key LIKE '% murukku%'
     OR Dish_Key LIKE '% mixture%'
     OR Dish_Key LIKE '% samosa%'
     OR Dish_Key LIKE '% vada pav%'
     OR Dish_Key LIKE '% vadapav%'
     OR Dish_Key LIKE '% puff%')
     AND NOT (Dish_Key LIKE '% popcorn chicken%')
THEN 'Snacks'

-- Soup
WHEN (Dish_Key LIKE '% soup%')
THEN 'Soup'

-- Bread
WHEN (Dish_Key LIKE '% naan%'
     OR Dish_Key LIKE '% roti %'
     OR Dish_Key LIKE '% rotis %'
     OR Dish_Key LIKE '% chapati%'
     OR Dish_Key LIKE '% kulcha%'
     OR Dish_Key LIKE '% paratha%'
     OR Dish_Key LIKE '% phulka%'
     OR Dish_Key LIKE '% garlic bread%')
THEN 'Bread'

-- Main Course
WHEN (Dish_Key LIKE '% biryani%'
     OR Dish_Key LIKE '% rice%'
     OR Dish_Key LIKE '% pulav%'
     OR Dish_Key LIKE '% pulao%'
     OR Dish_Key LIKE '% noodle%'
     OR Dish_Key LIKE '% curry%'
     OR Dish_Key LIKE '% dal%'
     OR Dish_Key LIKE '% parotta%'
     OR Dish_Key LIKE '% parota%'
     OR Dish_Key LIKE '% meals%'
     OR Dish_Key LIKE '% thali%'
     OR Dish_Key LIKE '% shawarma%'
     OR Dish_Key LIKE '% wrap%'
     OR Dish_Key LIKE '% roll%'
     OR Dish_Key LIKE '% burger%'
     OR Dish_Key LIKE '% pizza%'
     OR Dish_Key LIKE '% pasta%'
     OR Dish_Key LIKE '% dum %'
     OR Dish_Key LIKE '% makhani%'
     OR Dish_Key LIKE '% sandwich%')
     AND NOT (Dish_Key LIKE '% spring roll%')
THEN 'Main Course'

-- Starter
WHEN (Dish_Key LIKE '% wings%'
     OR Dish_Key LIKE '% lollipop%'
     OR Dish_Key LIKE '% tikka%'
     OR Dish_Key LIKE '% kebab%'
     OR Dish_Key LIKE '% kabab%'
     OR Dish_Key LIKE '% nugget%'
     OR Dish_Key LIKE '% popcorn chicken%'
     OR Dish_Key LIKE '% chilli chicken%'
     OR Dish_Key LIKE '% manchurian%'
     OR Dish_Key LIKE '% seekh%'
     OR Dish_Key LIKE '% tangdi%'
     OR Dish_Key LIKE '% finger%'
     OR Dish_Key LIKE '% 65 %'
     OR Dish_Key LIKE '% fry %'
     OR Dish_Key LIKE '% pepper %'
     OR Dish_Key LIKE '% chilli%'
     OR Dish_Key LIKE '% tandoori%'
     OR Dish_Key LIKE '% grilled%'
     OR Dish_Key LIKE '% peri %'
     OR Dish_Key LIKE '% crispy%'
     OR Dish_Key LIKE '% spring roll%')
THEN 'Starter'

-- Side Dish
WHEN (Dish_Key LIKE '% salad%'
     OR Dish_Key LIKE '% raita%'
     OR Dish_Key LIKE '% raitha%'
     OR Dish_Key LIKE '% pickle%'
     OR Dish_Key LIKE '% dip %'
     OR Dish_Key LIKE '% chutney%'
     OR Dish_Key LIKE '% sauce%'
     OR Dish_Key LIKE '% salan%'
     OR Dish_Key LIKE '% podi%'
     OR Dish_Key LIKE '% curd%')
THEN 'Side Dish'
ELSE 'Unclassified'
END;
GO

-- 5e) Price tier = relative terciles of the cleaned data (Low = cheapest third, High = most expensive third).
DECLARE @P33 FLOAT, @P66 FLOAT;
SELECT TOP 1
    @P33 = PERCENTILE_CONT(0.33) WITHIN GROUP (ORDER BY Price_INR) OVER (),
    @P66 = PERCENTILE_CONT(0.66) WITHIN GROUP (ORDER BY Price_INR) OVER ()
FROM stg_swiggy_data WHERE Price_INR IS NOT NULL;

UPDATE stg_swiggy_data
SET Price_Category = CASE
        WHEN Price_INR IS NULL THEN 'Unknown'
        WHEN Price_INR <= @P33 THEN 'Low'
        WHEN Price_INR <= @P66 THEN 'Medium'
        ELSE 'High' END;

-- 5f) Rating status (meaningful now: NULL rating = no reviews)
UPDATE stg_swiggy_data SET Rating_Status = CASE WHEN Rating IS NULL THEN 'Not Rated' ELSE 'Rated' END;
GO

-- 6) FINAL CHECKS -------------------------------------
SELECT COUNT(*) AS rows_total FROM stg_swiggy_data;
SELECT Food_Type, COUNT(*) AS n FROM stg_swiggy_data GROUP BY Food_Type ORDER BY n DESC;
SELECT Cuisine_Type, COUNT(*) AS n FROM stg_swiggy_data GROUP BY Cuisine_Type ORDER BY n DESC;
SELECT Category_Type, COUNT(*) AS n FROM stg_swiggy_data GROUP BY Category_Type ORDER BY n DESC;
SELECT Price_Category, COUNT(*) AS n, MIN(Price_INR) AS min_price, MAX(Price_INR) AS max_price FROM stg_swiggy_data GROUP BY Price_Category;
SELECT Rating_Status, COUNT(*) AS n FROM stg_swiggy_data GROUP BY Rating_Status;

-- Bug-fix spot checks (each query should return the labels shown in the comment)
SELECT TOP 5 Dish_Name, Food_Type FROM stg_swiggy_data WHERE Dish_Name LIKE '%veggie%' AND Dish_Name NOT LIKE '%chicken%';  -- Veg
SELECT TOP 5 Dish_Name, Food_Type FROM stg_swiggy_data WHERE Dish_Name LIKE '%hara bhara%' OR Dish_Name LIKE '%dahi%kebab%';  -- Veg
SELECT TOP 5 Dish_Name, Food_Type FROM stg_swiggy_data WHERE Dish_Name LIKE '%soya keema%' OR Dish_Name LIKE '%paneer keema%';  -- Veg
SELECT TOP 5 Dish_Name, Cuisine_Type FROM stg_swiggy_data WHERE Dish_Name LIKE '%steam%rice%';                              -- not Beverage
SELECT TOP 5 Dish_Name, Cuisine_Type FROM stg_swiggy_data WHERE Dish_Name LIKE '%vada pav%';                                -- Fast Food

-- Expected: 1 row, "Banaana Milk Shake" (a typo that exists in the source file)
SELECT Dish_Name FROM stg_swiggy_data WHERE Dish_Name LIKE '%banaana%';

-- Expected: 0  (proves our cleaning did not create any new 'banaana')
SELECT COUNT(*) AS banaana_created_by_cleaning FROM stg_swiggy_data
WHERE Dish_Key LIKE '%banaana%' AND Dish_Name NOT LIKE '%banaana%';

-- Expected: more than 0  (real bananas are still 'banana')
SELECT COUNT(*) AS banana_kept_intact FROM stg_swiggy_data WHERE Dish_Key LIKE '% banana%';