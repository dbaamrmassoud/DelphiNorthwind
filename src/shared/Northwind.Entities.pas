unit Northwind.Entities;

interface

uses
  Bcl.Types.Nullable,
  Aurelius.Mapping.Attributes,
  Aurelius.Mapping.Metadata,
  Aurelius.Mapping.Register;

type
  [Entity]
  [Table('Customers', 'dbo')]
  [Id('FCustomerID', TIdGenerator.None)]
  TCustomer = class
  private
    [Column('CustomerID', [TColumnProp.Required], 5)]
    FCustomerID: string;
    [Column('CompanyName', [TColumnProp.Required], 40)]
    FCompanyName: string;
    [Column('ContactName', [], 30)]
    FContactName: string;
    [Column('ContactTitle', [], 30)]
    FContactTitle: string;
    [Column('City', [], 15)]
    FCity: string;
    [Column('Country', [], 15)]
    FCountry: string;
    [Column('Phone', [], 24)]
    FPhone: string;
  public
    property CustomerID: string read FCustomerID write FCustomerID;
    property CompanyName: string read FCompanyName write FCompanyName;
    property ContactName: string read FContactName write FContactName;
    property ContactTitle: string read FContactTitle write FContactTitle;
    property City: string read FCity write FCity;
    property Country: string read FCountry write FCountry;
    property Phone: string read FPhone write FPhone;
  end;

  [Entity]
  [Table('Products', 'dbo')]
  [Id('FProductID', TIdGenerator.IdentityOrSequence)]
  TProduct = class
  private
    [Column('ProductID', [TColumnProp.Required, TColumnProp.NoUpdate])]
    FProductID: Integer;
    [Column('ProductName', [TColumnProp.Required], 40)]
    FProductName: string;
    [Column('QuantityPerUnit', [], 20)]
    FQuantityPerUnit: string;
    [Column('UnitPrice', [])]
    FUnitPrice: Nullable<Currency>;
    [Column('UnitsInStock', [])]
    FUnitsInStock: Nullable<SmallInt>;
    [Column('Discontinued', [TColumnProp.Required])]
    FDiscontinued: Boolean;
  public
    property ProductID: Integer read FProductID;
    property ProductName: string read FProductName write FProductName;
    property QuantityPerUnit: string read FQuantityPerUnit write FQuantityPerUnit;
    property UnitPrice: Nullable<Currency> read FUnitPrice write FUnitPrice;
    property UnitsInStock: Nullable<SmallInt> read FUnitsInStock write FUnitsInStock;
    property Discontinued: Boolean read FDiscontinued write FDiscontinued;
  end;

  [Entity]
  [Table('Orders', 'dbo')]
  [Id('FOrderID', TIdGenerator.IdentityOrSequence)]
  TOrder = class
  private
    [Column('OrderID', [TColumnProp.Required, TColumnProp.NoUpdate])]
    FOrderID: Integer;
    [Column('CustomerID', [], 5)]
    FCustomerID: string;
    [Column('OrderDate', [])]
    FOrderDate: Nullable<TDateTime>;
    [Column('RequiredDate', [])]
    FRequiredDate: Nullable<TDateTime>;
    [Column('ShippedDate', [])]
    FShippedDate: Nullable<TDateTime>;
    [Column('Freight', [])]
    FFreight: Nullable<Currency>;
    [Column('ShipName', [], 40)]
    FShipName: string;
    [Column('ShipCity', [], 15)]
    FShipCity: string;
    [Column('ShipCountry', [], 15)]
    FShipCountry: string;
  public
    property OrderID: Integer read FOrderID;
    property CustomerID: string read FCustomerID write FCustomerID;
    property OrderDate: Nullable<TDateTime> read FOrderDate write FOrderDate;
    property RequiredDate: Nullable<TDateTime> read FRequiredDate write FRequiredDate;
    property ShippedDate: Nullable<TDateTime> read FShippedDate write FShippedDate;
    property Freight: Nullable<Currency> read FFreight write FFreight;
    property ShipName: string read FShipName write FShipName;
    property ShipCity: string read FShipCity write FShipCity;
    property ShipCountry: string read FShipCountry write FShipCountry;
  end;

  [Entity]
  [Table('Order Details', 'dbo')]
  [Id('FOrderID', TIdGenerator.None)]
  [Id('FProductID', TIdGenerator.None)]
  TOrderDetail = class
  private
    [Column('OrderID', [TColumnProp.Required, TColumnProp.NoUpdate])]
    FOrderID: Integer;
    [Column('ProductID', [TColumnProp.Required, TColumnProp.NoUpdate])]
    FProductID: Integer;
    [Column('UnitPrice', [TColumnProp.Required])]
    FUnitPrice: Currency;
    [Column('Quantity', [TColumnProp.Required])]
    FQuantity: SmallInt;
    [Column('Discount', [TColumnProp.Required])]
    FDiscount: Single;
  public
    property OrderID: Integer read FOrderID write FOrderID;
    property ProductID: Integer read FProductID write FProductID;
    property UnitPrice: Currency read FUnitPrice write FUnitPrice;
    property Quantity: SmallInt read FQuantity write FQuantity;
    property Discount: Single read FDiscount write FDiscount;
  end;

implementation

initialization
  RegisterEntity(TCustomer);
  RegisterEntity(TProduct);
  RegisterEntity(TOrder);
  RegisterEntity(TOrderDetail);

end.
