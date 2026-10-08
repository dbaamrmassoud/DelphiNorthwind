unit Northwind.OrderService;

interface

uses
  Northwind.OrderService.Contract,
  XData.Service.Common;

type
  [ServiceImplementation]
  TOrderEntryService = class(TInterfacedObject, IOrderEntryService)
  private
    function CreateOrder(const CustomerID: string; ProductID: Integer;
      Quantity: SmallInt): Integer;
  end;

implementation

uses
  System.SysUtils,
  Aurelius.Drivers.Interfaces,
  Aurelius.Engine.ObjectManager,
  Bcl.Types.Nullable,
  Northwind.Entities,
  XData.Server.Exceptions,
  XData.Server.Module;

function TOrderEntryService.CreateOrder(const CustomerID: string;
  ProductID: Integer; Quantity: SmallInt): Integer;
var
  Customer: TCustomer;
  Detail: TOrderDetail;
  Manager: TObjectManager;
  Order: TOrder;
  Product: TProduct;
  Transaction: IDBTransaction;
begin
  if Length(Trim(CustomerID)) <> 5 then
    raise EXDataHttpBadRequest.Create('Customer ID must contain five characters.');
  if ProductID <= 0 then
    raise EXDataHttpBadRequest.Create('Product ID must be positive.');
  if Quantity <= 0 then
    raise EXDataHttpBadRequest.Create('Quantity must be positive.');

  Manager := TXDataOperationContext.Current.GetManager;
  Customer := Manager.Find<TCustomer>(UpperCase(Trim(CustomerID)));
  if Customer = nil then
    raise EXDataHttpBadRequest.Create('The specified customer does not exist.');

  Product := Manager.Find<TProduct>(ProductID);
  if Product = nil then
    raise EXDataHttpBadRequest.Create('The specified product does not exist.');
  if Product.Discontinued then
    raise EXDataHttpBadRequest.Create('The specified product is discontinued.');
  if not Product.UnitPrice.HasValue then
    raise EXDataHttpBadRequest.Create('The specified product has no unit price.');

  Order := nil;
  Detail := nil;
  Transaction := Manager.Connection.BeginTransaction;
  try
    Order := TOrder.Create;
    Order.CustomerID := Customer.CustomerID;
    Order.OrderDate := Nullable<TDateTime>.Create(Now);
    Order.Freight := Nullable<Currency>.Create(0);
    Manager.Save(Order);
    Result := Order.OrderID;
    Order := nil;

    Detail := TOrderDetail.Create;
    Detail.OrderID := Result;
    Detail.ProductID := Product.ProductID;
    Detail.UnitPrice := Product.UnitPrice.Value;
    Detail.Quantity := Quantity;
    Detail.Discount := 0;
    Manager.Save(Detail);
    Detail := nil;

    Transaction.Commit;
  except
    if Detail <> nil then
      Detail.Free;
    if Order <> nil then
      Order.Free;
    Transaction.Rollback;
    raise;
  end;
end;

initialization
  RegisterServiceType(TOrderEntryService);

end.
