unit Northwind.OrderService.Contract;

interface

uses
  XData.Service.Common;

type
  [ServiceContract]
  IOrderEntryService = interface(IInvokable)
    ['{CC160087-6B6F-4FB4-AE50-5EB2EFD0D008}']
    function CreateOrder(const CustomerID: string; ProductID: Integer;
      Quantity: SmallInt): Integer;
  end;

implementation

initialization
  RegisterServiceType(TypeInfo(IOrderEntryService));

end.
