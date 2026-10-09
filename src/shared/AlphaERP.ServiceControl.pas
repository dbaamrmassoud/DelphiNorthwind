unit AlphaERP.ServiceControl;

interface

uses
  Winapi.Windows,
  Winapi.WinSvc;

type
  TAlphaERPServiceInfo = record
    Installed: Boolean;
    State: DWORD;
    ProcessId: DWORD;
    CheckPoint: DWORD;
    WaitHint: DWORD;
  end;

function QueryAlphaERPService(const ServiceName: string): TAlphaERPServiceInfo;
procedure StartAlphaERPService(const ServiceName: string);
procedure StopAlphaERPService(const ServiceName: string);
procedure RestartAlphaERPService(const ServiceName: string;
  const TimeoutMilliseconds: Cardinal);

implementation

uses
  System.SysUtils;

procedure RaiseServiceControlError(const Operation: string;
  const ErrorCode: DWORD);
begin
  raise EOSError.CreateFmt('%s failed (Win32 error %d): %s',
    [Operation, ErrorCode, SysErrorMessage(ErrorCode)]);
end;

function OpenManager: SC_HANDLE;
begin
  Result := OpenSCManager(nil, nil, SC_MANAGER_CONNECT);
  if Result = 0 then
    RaiseServiceControlError('OpenSCManager', GetLastError);
end;

function OpenNamedService(const Manager: SC_HANDLE; const ServiceName: string;
  const DesiredAccess: DWORD): SC_HANDLE;
begin
  Result := OpenService(Manager, PChar(ServiceName), DesiredAccess);
  if Result = 0 then
    RaiseServiceControlError('OpenService ' + ServiceName, GetLastError);
end;

function QueryAlphaERPService(const ServiceName: string): TAlphaERPServiceInfo;
var
  BytesNeeded: DWORD;
  ErrorCode: DWORD;
  Manager: SC_HANDLE;
  Service: SC_HANDLE;
  Status: SERVICE_STATUS_PROCESS;
begin
  FillChar(Result, SizeOf(Result), 0);
  Manager := OpenManager;
  try
    Service := OpenService(Manager, PChar(ServiceName), SERVICE_QUERY_STATUS);
    if Service = 0 then
    begin
      ErrorCode := GetLastError;
      if ErrorCode = ERROR_SERVICE_DOES_NOT_EXIST then
        Exit;
      RaiseServiceControlError('OpenService ' + ServiceName, ErrorCode);
    end;
    try
      BytesNeeded := 0;
      if not QueryServiceStatusEx(Service, SC_STATUS_PROCESS_INFO, @Status,
        SizeOf(Status), BytesNeeded) then
        RaiseServiceControlError('QueryServiceStatusEx', GetLastError);
      Result.Installed := True;
      Result.State := Status.dwCurrentState;
      Result.ProcessId := Status.dwProcessId;
      Result.CheckPoint := Status.dwCheckPoint;
      Result.WaitHint := Status.dwWaitHint;
    finally
      CloseServiceHandle(Service);
    end;
  finally
    CloseServiceHandle(Manager);
  end;
end;

procedure StartAlphaERPService(const ServiceName: string);
var
  ErrorCode: DWORD;
  ServiceArgs: LPCWSTR;
  Manager: SC_HANDLE;
  Service: SC_HANDLE;
begin
  ServiceArgs := nil;
  Manager := OpenManager;
  try
    Service := OpenNamedService(Manager, ServiceName,
      SERVICE_START or SERVICE_QUERY_STATUS);
    try
      if not StartService(Service, 0, ServiceArgs) then
      begin
        ErrorCode := GetLastError;
        if ErrorCode <> ERROR_SERVICE_ALREADY_RUNNING then
          RaiseServiceControlError('StartService ' + ServiceName, ErrorCode);
      end;
    finally
      CloseServiceHandle(Service);
    end;
  finally
    CloseServiceHandle(Manager);
  end;
end;

procedure StopAlphaERPService(const ServiceName: string);
var
  ErrorCode: DWORD;
  Manager: SC_HANDLE;
  Service: SC_HANDLE;
  Status: SERVICE_STATUS;
begin
  Manager := OpenManager;
  try
    Service := OpenNamedService(Manager, ServiceName,
      SERVICE_STOP or SERVICE_QUERY_STATUS);
    try
      if not ControlService(Service, SERVICE_CONTROL_STOP, Status) then
      begin
        ErrorCode := GetLastError;
        if ErrorCode <> ERROR_SERVICE_NOT_ACTIVE then
          RaiseServiceControlError('ControlService STOP ' + ServiceName,
            ErrorCode);
      end;
    finally
      CloseServiceHandle(Service);
    end;
  finally
    CloseServiceHandle(Manager);
  end;
end;

procedure RestartAlphaERPService(const ServiceName: string;
  const TimeoutMilliseconds: Cardinal);
var
  StartedAt: Cardinal;
  Info: TAlphaERPServiceInfo;
begin
  Info := QueryAlphaERPService(ServiceName);
  if not Info.Installed then
    raise Exception.CreateFmt('Windows service %s is not installed.',
      [ServiceName]);
  if (Info.State <> SERVICE_STOPPED) then
  begin
    StopAlphaERPService(ServiceName);
    StartedAt := GetTickCount;
    repeat
      Sleep(200);
      Info := QueryAlphaERPService(ServiceName);
      if not Info.Installed then
        raise Exception.CreateFmt('Windows service %s was removed while stopping.',
          [ServiceName]);
      if Info.State = SERVICE_STOPPED then
        Break;
    until Cardinal(GetTickCount - StartedAt) >= TimeoutMilliseconds;
    if Info.State <> SERVICE_STOPPED then
      raise Exception.CreateFmt(
        'Timed out waiting for Windows service %s to stop.', [ServiceName]);
  end;
  StartAlphaERPService(ServiceName);
end;

end.
