/*
  Read-only preflight for the official Microsoft SQL Server Northwind schema.
  An empty result means all required tables and columns were found.
*/
WITH RequiredColumns AS
(
    SELECT *
    FROM (VALUES
        (N'Customers', N'CustomerID'),
        (N'Customers', N'CompanyName'),
        (N'Orders', N'OrderID'),
        (N'Orders', N'CustomerID'),
        (N'Orders', N'OrderDate'),
        (N'Order Details', N'OrderID'),
        (N'Order Details', N'ProductID'),
        (N'Order Details', N'UnitPrice'),
        (N'Order Details', N'Quantity'),
        (N'Order Details', N'Discount'),
        (N'Products', N'ProductID'),
        (N'Products', N'ProductName'),
        (N'Products', N'UnitPrice'),
        (N'Products', N'Discontinued')
    ) AS Required(TableName, ColumnName)
)
SELECT
    RequiredColumns.TableName,
    RequiredColumns.ColumnName AS MissingColumn
FROM RequiredColumns
LEFT JOIN sys.tables AS Tables
    ON Tables.name = RequiredColumns.TableName
    AND SCHEMA_NAME(Tables.schema_id) = N'dbo'
LEFT JOIN sys.columns AS Columns
    ON Columns.object_id = Tables.object_id
    AND Columns.name = RequiredColumns.ColumnName
WHERE Columns.column_id IS NULL
ORDER BY RequiredColumns.TableName, RequiredColumns.ColumnName;
