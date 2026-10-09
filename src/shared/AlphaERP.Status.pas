unit AlphaERP.Status;

interface

uses
  System.SyncObjs,
  System.SysUtils;

type
  TAlphaERPServiceState = (aesStopped, aesStarting, aesRunning, aesDegraded,
    aesStopping, aesError);

  TAlphaERPStatusSnapshot = record
    ServiceName: string;
    ServiceState: TAlphaERPServiceState;
    ServiceDetail: string;
    ServiceStartedAt: TDateTime;
    ApiBaseUrl: string;
    ApiState: string;
    DatabaseServer: string;
    DatabaseName: string;
    DatabaseConnected: Boolean;
    LastDatabaseCheck: TDateTime;
    LastSuccessfulDatabaseCheck: TDateTime;
    DatabaseError: string;
    LastServerError: string;
    LogFileName: string;
    ApplicationStartedAt: TDateTime;
  end;

  TAlphaERPStatusManager = class
  private
    FLock: TCriticalSection;
    FSnapshot: TAlphaERPStatusSnapshot;
  public
    constructor Create;
    destructor Destroy; override;
    function Snapshot: TAlphaERPStatusSnapshot;
    procedure SetApiStatus(const State, BaseUrl: string);
    procedure SetDatabaseStatus(const Server, Database: string;
      const Connected: Boolean; const ErrorText: string);
    procedure SetServiceState(const State: TAlphaERPServiceState;
      const Detail: string = '');
    procedure SetStartupInfo(const ServiceName, LogFile: string;
      const ApplicationStartedAt: TDateTime);
    procedure SetServerError(const ErrorText: string);
  end;

function AlphaERPServiceStateName(const State: TAlphaERPServiceState): string;

implementation

function AlphaERPServiceStateName(
  const State: TAlphaERPServiceState): string;
begin
  case State of
    aesStopped: Result := 'Stopped';
    aesStarting: Result := 'Starting';
    aesRunning: Result := 'Running';
    aesDegraded: Result := 'Degraded';
    aesStopping: Result := 'Stopping';
  else
    Result := 'Error';
  end;
end;

constructor TAlphaERPStatusManager.Create;
begin
  inherited Create;
  FLock := TCriticalSection.Create;
  FSnapshot.ServiceState := aesStopped;
  FSnapshot.ApiState := 'Stopped';
end;

destructor TAlphaERPStatusManager.Destroy;
begin
  FLock.Free;
  inherited;
end;

function TAlphaERPStatusManager.Snapshot: TAlphaERPStatusSnapshot;
begin
  FLock.Acquire;
  try
    Result := FSnapshot;
  finally
    FLock.Release;
  end;
end;

procedure TAlphaERPStatusManager.SetApiStatus(const State, BaseUrl: string);
begin
  FLock.Acquire;
  try
    FSnapshot.ApiState := State;
    FSnapshot.ApiBaseUrl := BaseUrl;
  finally
    FLock.Release;
  end;
end;

procedure TAlphaERPStatusManager.SetDatabaseStatus(const Server,
  Database: string; const Connected: Boolean; const ErrorText: string);
begin
  FLock.Acquire;
  try
    FSnapshot.DatabaseServer := Server;
    FSnapshot.DatabaseName := Database;
    FSnapshot.DatabaseConnected := Connected;
    FSnapshot.LastDatabaseCheck := Now;
    if Connected then
      FSnapshot.LastSuccessfulDatabaseCheck := FSnapshot.LastDatabaseCheck;
    FSnapshot.DatabaseError := ErrorText;
  finally
    FLock.Release;
  end;
end;

procedure TAlphaERPStatusManager.SetServiceState(
  const State: TAlphaERPServiceState; const Detail: string);
begin
  FLock.Acquire;
  try
    if (State in [aesRunning, aesDegraded]) and
       (FSnapshot.ServiceStartedAt = 0) then
      FSnapshot.ServiceStartedAt := Now;
    FSnapshot.ServiceState := State;
    FSnapshot.ServiceDetail := Detail;
    if (State = aesStopped) or (State = aesStopping) then
      FSnapshot.ServiceStartedAt := 0;
  finally
    FLock.Release;
  end;
end;

procedure TAlphaERPStatusManager.SetStartupInfo(const ServiceName,
  LogFile: string; const ApplicationStartedAt: TDateTime);
begin
  FLock.Acquire;
  try
    FSnapshot.ServiceName := ServiceName;
    FSnapshot.LogFileName := LogFile;
    FSnapshot.ApplicationStartedAt := ApplicationStartedAt;
  finally
    FLock.Release;
  end;
end;

procedure TAlphaERPStatusManager.SetServerError(const ErrorText: string);
begin
  FLock.Acquire;
  try
    FSnapshot.LastServerError := ErrorText;
  finally
    FLock.Release;
  end;
end;

end.
