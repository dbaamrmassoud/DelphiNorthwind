unit AlphaERP.Health.Service;

interface

uses
  AlphaERP.Status;

procedure SetAlphaERPHealthStatusManager(
  StatusManager: TAlphaERPStatusManager);

implementation

uses
  System.JSON,
  System.SyncObjs,
  System.SysUtils,
  System.DateUtils,
  AlphaERP.Health.Contract,
  XData.Service.Common;

type
  [ServiceImplementation]
  TAlphaERPHealthService = class(TInterfacedObject, IAlphaERPHealthService)
  private
    function GetStatus: string;
  end;

var
  StatusLock: TCriticalSection;
  CurrentStatusManager: TAlphaERPStatusManager;

procedure SetAlphaERPHealthStatusManager(
  StatusManager: TAlphaERPStatusManager);
begin
  StatusLock.Acquire;
  try
    CurrentStatusManager := StatusManager;
  finally
    StatusLock.Release;
  end;
end;

function DateTimeAsIso8601(const Value: TDateTime): string;
begin
  if Value = 0 then
    Exit('');
  Result := DateToISO8601(Value, False);
end;

function TAlphaERPHealthService.GetStatus: string;
var
  Snapshot: TAlphaERPStatusSnapshot;
  Json: TJSONObject;
begin
  StatusLock.Acquire;
  try
    if CurrentStatusManager = nil then
      raise Exception.Create('The service status manager is unavailable.');
    Snapshot := CurrentStatusManager.Snapshot;
  finally
    StatusLock.Release;
  end;

  Json := TJSONObject.Create;
  try
    Json.AddPair('service_name', Snapshot.ServiceName);
    Json.AddPair('service_state',
      AlphaERPServiceStateName(Snapshot.ServiceState));
    Json.AddPair('service_detail', Snapshot.ServiceDetail);
    Json.AddPair('service_started_at',
      DateTimeAsIso8601(Snapshot.ServiceStartedAt));
    Json.AddPair('application_started_at',
      DateTimeAsIso8601(Snapshot.ApplicationStartedAt));
    Json.AddPair('api_base_url', Snapshot.ApiBaseUrl);
    Json.AddPair('api_state', Snapshot.ApiState);
    Json.AddPair('database_server', Snapshot.DatabaseServer);
    Json.AddPair('database_name', Snapshot.DatabaseName);
    if Snapshot.DatabaseConnected then
      Json.AddPair('database_state', 'Connected')
    else
      Json.AddPair('database_state', 'Disconnected');
    Json.AddPair('last_database_check',
      DateTimeAsIso8601(Snapshot.LastDatabaseCheck));
    Json.AddPair('last_database_success',
      DateTimeAsIso8601(Snapshot.LastSuccessfulDatabaseCheck));
    Json.AddPair('database_error', Snapshot.DatabaseError);
    Json.AddPair('last_server_error', Snapshot.LastServerError);
    Json.AddPair('log_file', Snapshot.LogFileName);
    Result := Json.ToJSON;
  finally
    Json.Free;
  end;
end;

initialization
  StatusLock := TCriticalSection.Create;
  RegisterServiceType(TAlphaERPHealthService);

finalization
  StatusLock.Free;

end.
