unit AlphaERP.Health.Contract;

interface

uses
  XData.Service.Common;

type
  [ServiceContract]
  IAlphaERPHealthService = interface(IInvokable)
    ['{7CBA2C82-79B1-4EA0-BA9E-0486A66DA2E6}']
    function GetStatus: string;
  end;

implementation

initialization
  RegisterServiceType(TypeInfo(IAlphaERPHealthService));

end.
