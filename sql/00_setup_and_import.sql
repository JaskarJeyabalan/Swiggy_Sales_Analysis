-- =====================================================================
-- 00_setup_and_import.sql
-- Creates the database, drops old objects, and loads the ORIGINAL dataset
-- (Swiggy_Data.csv: 197,430 rows, 1 Jan - 31 Aug 2025) into raw_swiggy_data.
-- Run order: 00 -> 01 -> 02 -> 03 -> 04 -> 05
-- =====================================================================
IF DB_ID('Swiggy_DB') IS NULL CREATE DATABASE Swiggy_DB;
GO
USE Swiggy_DB;
GO

-- Drop in dependency order (view first, then fact, dimensions, staging). raw_swiggy_data is dropped and re-created further down.
DROP VIEW  IF EXISTS vw_swiggy_analytics;
DROP TABLE IF EXISTS fact_swiggy_orders;
DROP TABLE IF EXISTS dim_date;
DROP TABLE IF EXISTS dim_location;
DROP TABLE IF EXISTS dim_restaurant;
DROP TABLE IF EXISTS dim_category;
DROP TABLE IF EXISTS dim_dish;
DROP TABLE IF EXISTS stg_swiggy_data;
GO

-- Raw table: every column is text, so the load never fails and ALL cleaning is visible in script 01.
-- Order_Date arrives as dd-mm-yyyy text (e.g. 29-06-2025); it is converted explicitly in script 01.
DROP TABLE IF EXISTS raw_swiggy_data;
CREATE TABLE raw_swiggy_data (
    State           NVARCHAR(500),
    City            NVARCHAR(500),
    Order_Date      NVARCHAR(500),
    Restaurant_Name NVARCHAR(500),
    Location        NVARCHAR(500),
    Category        NVARCHAR(500),
    Dish_Name       NVARCHAR(1000),
    Price_INR       NVARCHAR(500),
    Rating          NVARCHAR(500),
    Rating_Count    NVARCHAR(500)
);
GO

-- The CSV uses Windows line endings (CRLF), so the row terminator is 0x0d0a. If it is wrong, Rating_Count keeps a stray
-- carriage return and 'bad_rating_count' in script 01 will not be 0.
-- EDIT THE PATH, then run. FORMAT='CSV' (SQL Server 2017+) is needed because Restaurant/Dish names contain
-- commas and quotes. CODEPAGE 65001 = UTF-8 (about 2,100 dish names have non-English characters).
BULK INSERT raw_swiggy_data
FROM 'C:\Users\Welcome\Downloads\Swiggy_Data.csv'
WITH (FORMAT = 'CSV', FIELDQUOTE = '"', FIRSTROW = 2, CODEPAGE = '65001', FIELDTERMINATOR = ',', ROWTERMINATOR = '0x0d0a', TABLOCK);
GO
-- (Alternative: SSMS > Tasks > Import Flat File into a table named raw_swiggy_data, all columns as text.)

-- CHECK: expected 197430
SELECT COUNT(*) AS raw_rows FROM raw_swiggy_data;
