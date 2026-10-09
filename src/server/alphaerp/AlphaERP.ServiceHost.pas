unit AlphaERP.ServiceHost;

interface

uses
  System.Classes,
  System.SyncObjs,
  Aurelius.Drivers.Interfaces,
  AlphaERP.Config,
  AlphaERP.Status,
  Sparkle.HttpSys.Server,
  XData.Aurelius.ConnectionPool,
  XData.Server.Module;

type
  TAlphaERPServiceHost = class
  private type
    TDatabaseHealthThread = class(TThread)
    private
      FConfig: TAlphaERPConfig;
      FStatus: TAlphaERPStatusManager;
      FStopEvent: TEvent;
      procedure CheckDatabase;
    protected
      procedure Execute; override;
    public
      constructor Create(const Config: TAlphaERPConfig;
        const Status: TAlphaERPStatusManager);
      destructor Destroy; override;
      procedure Stop;
    end;
  private
    FConfig: TAlphaERPConfig;
    FConnectionFactory: IDBConnectionFactory;
    FConnectionPool: IDBConnectionPool;
    FHealthThread: TDatabaseHealthThread;
    FHttpServer: THttpSysServer;
    FStatus: TAlphaERPStatusManager;
    procedure Cleanup;
    function CreateDatabaseConnection: IDBConnection;
    procedure Initialize;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Start;
    procedure Stop;
    property Status: TAlphaERPStatusManager read FStatus;
  end;

implementation

uses
  System.IOUtils,
  System.SysUtils,
  Aurelius.Drivers.Base,
  Aurelius.Drivers.FireDac,
  FireDAC.Comp.Client,
  FireDAC.Phys.MSSQL,
  FireDAC.Stan.Def,
  AlphaERP.Health.Service,
  AlphaERP.Logging,
  Northwind.Entities,
  Northwind.OrderService,
  Sparkle.Middleware.Jwt,
  VCL.TMSLogging;

function YesNo(const Value: Boolean): string;
begin
  if Value then
    Result := 'Yes'
  else
    Result := 'No';
end;

function RequireEnvironmentVariable(const Name: string): string;
begin
  Result := GetEnvironmentVariable(Name);
  if Result = '' then
    raise Exception.CreateFmt(
      'Required environment variable %s is not set.', [Name]);
end;

function CreateFireDACConnection(const Config: TAlphaERPConfig): TFDConnection;
begin
  Result := TFDConnection.Create(nil);
  try
    Result.LoginPrompt := False;
    Result.DriverName := 'MSSQL';
    Result.Params.Values['Server'] := Config.DatabaseServer;
    Result.Params.Values['Database'] := Config.DatabaseName;
    Result.Params.Values['LoginTimeout'] :=
      IntToStr(Config.DatabaseLoginTimeoutSeconds);
    Result.Params.Values['User_Name'] :=
      RequireEnvironmentVariable(Config.DatabaseUserEnvironmentVariable);
    Result.Params.Values['Password'] :=
      RequireEnvironmentVariable(Config.DatabasePasswordEnvironmentVariable);
    Result.Params.Values['Encrypt'] := YesNo(Config.EncryptConnection);
    Result.Params.Values['TrustServerCertificate'] :=
      YesNo(Config.TrustServerCertificate);
  except
    Result.Free;
    raise;
  end;
end;

procedure VerifyDatabaseConnection(const Config: TAlphaERPConfig);
var
  Connection: TFDConnection;
begin
  Connection := CreateFireDACConnection(Config);
  try
    Connection.Connected := True;
  finally
    Connection.Free;
  end;
end;

constructor TAlphaERPServiceHost.Create;
begin
  inherited Create;
  FStatus := TAlphaERPStatusManager.Create;
  FStatus.SetServiceState(aesStopped);
end;

destructor TAlphaERPServiceHost.Destroy;
begin
  Cleanup;
  FStatus.Free;
  FConfig.Free;
  inherited;
end;

procedure TAlphaERPServiceHost.Initialize;
var
  ApiModule: TXDataServerModule;
  HealthModule: TXDataServerModule;
  JwtMiddleware: TJwtMiddleware;
  JwtSecret: string;
  ProgramData: string;
begin
  ProgramData := GetEnvironmentVariable('PROGRAMDATA');
  if ProgramData = '' then
    ProgramData := ExtractFilePath(ParamStr(0));
  TAlphaERPLogger.Initialize(
    TPath.Combine(TPath.Combine(ProgramData, 'AlphaERP\Logs'),
      'AlphaERP.log'),
    allInfo, 10, 5);
  FConfig := TAlphaERPConfig.Create;
  TAlphaERPLogger.Initialize(
    TPath.Combine(FConfig.LogDirectory, FConfig.LogFileName),
    AlphaERPLogLevelFromString(FConfig.LogLevel),
    FConfig.MaxLogSizeMB, FConfig.MaxLogFiles);
  TAlphaERPLogger.Info('Starting AlphaERP service host.');
  TAlphaERPLogger.Info('Loading service configuration from ' +
    FConfig.ConfigFileName);
  FStatus.SetStartupInfo(FConfig.ServiceName,
    TPath.Combine(FConfig.LogDirectory, FConfig.LogFileName), Now);
  FStatus.SetApiStatus('Starting', FConfig.ApiBaseUrl);
  FStatus.SetDatabaseStatus(FConfig.DatabaseServer, FConfig.DatabaseName,
    False, '');

  JwtSecret := FConfig.GetJwtSecret;
  RequireEnvironmentVariable(FConfig.DatabaseUserEnvironmentVariable);
  RequireEnvironmentVariable(FConfig.DatabasePasswordEnvironmentVariable);

  try
    VerifyDatabaseConnection(FConfig);
    FStatus.SetDatabaseStatus(FConfig.DatabaseServer, FConfig.DatabaseName,
      True, '');
    TAlphaERPLogger.Info('Initial database connectivity check succeeded.');
  except
    on E: Exception do
    begin
      FStatus.SetDatabaseStatus(FConfig.DatabaseServer, FConfig.DatabaseName,
        False, E.Message);
      TAlphaERPLogger.Warning('Initial database connectivity check failed: ' +
        E.Message);
    end;
  end;

  FConnectionFactory := TDBConnectionFactory.Create(
    function: IDBConnection
    begin
      Result := CreateDatabaseConnection;
    end);
  FConnectionPool := TDBConnectionPool.Create(FConfig.MaxConnections,
    FConnectionFactory);

  ApiModule := nil;
  HealthModule := nil;
  JwtMiddleware := nil;
  try
    ApiModule := TXDataServerModule.Create(FConfig.ApiBaseUrl, FConnectionPool);
    JwtMiddleware := TJwtMiddleware.Create(JwtSecret);
    JwtMiddleware.ForbidAnonymousAccess := True;
    ApiModule.AddMiddleware(JwtMiddleware);
    JwtMiddleware := nil;

    HealthModule := TXDataServerModule.Create(FConfig.HealthBaseUrl,
      FConnectionPool);
    SetAlphaERPHealthStatusManager(FStatus);
    FHttpServer := THttpSysServer.Create;
    FHttpServer.AddModule(ApiModule);
    ApiModule := nil;
    FHttpServer.AddModule(HealthModule);
    HealthModule := nil;
    FHttpServer.Start;
  finally
    JwtMiddleware.Free;
    ApiModule.Free;
    HealthModule.Free;
  end;

  FStatus.SetApiStatus('Running', FConfig.ApiBaseUrl);
  FStatus.SetServerError('');
  FStatus.SetServiceState(aesRunning);
  TAlphaERPLogger.Info('XData REST API started at ' + FConfig.ApiBaseUrl);
  TAlphaERPLogger.Info('Local health endpoint started at ' +
    FConfig.HealthBaseUrl);

  if not FStatus.Snapshot.DatabaseConnected then
    FStatus.SetServiceState(aesDegraded,
      'The REST server is running, but the database is unavailable.');
  FHealthThread := TDatabaseHealthThread.Create(FConfig, FStatus);
end;

function TAlphaERPServiceHost.CreateDatabaseConnection: IDBConnection;
var
  Connection: TFDConnection;
begin
  Connection := CreateFireDACConnection(FConfig);
  try
    Result := TFireDacConnectionAdapter.Create(Connection, True);
    Connection := nil;
  finally
    Connection.Free;
  end;
end;

procedure TAlphaERPServiceHost.Start;
begin
  if FHttpServer <> nil then
    Exit;
  FStatus.SetServiceState(aesStarting, 'Initializing backend components.');
  try
    Initialize;
  except
    on E: Exception do
    begin
      FStatus.SetApiStatus('Error', '');
      FStatus.SetServerError(E.Message);
      FStatus.SetServiceState(aesError, E.Message);
      try
        TAlphaERPLogger.Error('AlphaERP service startup failed: ' + E.Message);
      except
        on LogError: Exception do
          TMSLogger.Error('AlphaERP startup failed: ' + E.Message +
            '; writing the service log also failed: ' + LogError.Message);
      end;
      Cleanup;
      raise;
    end;
  end;
end;

procedure TAlphaERPServiceHost.Stop;
begin
  if (FHttpServer = nil) and (FHealthThread = nil) then
  begin
    FStatus.SetServiceState(aesStopped);
    Exit;
  end;

  FStatus.SetServiceState(aesStopping, 'Stopping backend components.');
  try
    TAlphaERPLogger.Info('Stopping AlphaERP service host.');
  finally
    Cleanup;
    FStatus.SetApiStatus('Stopped', '');
    FStatus.SetServiceState(aesStopped);
  end;
  TAlphaERPLogger.Info('AlphaERP service host stopped.');
end;

procedure TAlphaERPServiceHost.Cleanup;
begin
  try
    if FHealthThread <> nil then
    begin
      FHealthThread.Stop;
      FreeAndNil(FHealthThread);
    end;
  finally
    try
      FHttpServer.Free;
    finally
      FHttpServer := nil;
      SetAlphaERPHealthStatusManager(nil);
      FConnectionPool := nil;
      FConnectionFactory := nil;
      FreeAndNil(FConfig);
    end;
  end;
end;

constructor TAlphaERPServiceHost.TDatabaseHealthThread.Create(
  const Config: TAlphaERPConfig; const Status: TAlphaERPStatusManager);
begin
  inherited Create(True);
  FreeOnTerminate := False;
  FConfig := Config;
  FStatus := Status;
  FStopEvent := TEvent.Create(nil, True, False, '');
  Start;
end;

destructor TAlphaERPServiceHost.TDatabaseHealthThread.Destroy;
begin
  Stop;
  FStopEvent.Free;
  inherited;
end;

procedure TAlphaERPServiceHost.TDatabaseHealthThread.CheckDatabase;
var
  Previous: TAlphaERPStatusSnapshot;
begin
  Previous := FStatus.Snapshot;
  try
    VerifyDatabaseConnection(FConfig);
    FStatus.SetDatabaseStatus(FConfig.DatabaseServer, FConfig.DatabaseName,
      True, '');
    if Previous.DatabaseConnected = False then
      TAlphaERPLogger.Info('Database connectivity check succeeded.');
    if FStatus.Snapshot.ApiState = 'Running' then
      FStatus.SetServiceState(aesRunning);
  except
    on E: Exception do
    begin
      FStatus.SetDatabaseStatus(FConfig.DatabaseServer, FConfig.DatabaseName,
        False, E.Message);
      if Previous.DatabaseConnected or (Previous.DatabaseError <> E.Message) then
        TAlphaERPLogger.Warning('Database connectivity check failed: ' +
          E.Message);
      if FStatus.Snapshot.ApiState = 'Running' then
        FStatus.SetServiceState(aesDegraded,
          'The REST server is running, but the database is unavailable.');
    end;
  end;
end;

procedure TAlphaERPServiceHost.TDatabaseHealthThread.Execute;
begin
  while not Terminated do
  begin
    if FStopEvent.WaitFor(FConfig.HealthCheckIntervalSeconds * 1000) <>
      wrTimeout then
      Break;
    try
      CheckDatabase;
    except
      on E: Exception do
      begin
        FStatus.SetDatabaseStatus(FConfig.DatabaseServer, FConfig.DatabaseName,
          False, E.Message);
        FStatus.SetServiceState(aesDegraded, E.Message);
        TMSLogger.Error('Database health monitor failed: ' + E.Message);
      end;
    end;
  end;
end;

procedure TAlphaERPServiceHost.TDatabaseHealthThread.Stop;
begin
  Terminate;
  FStopEvent.SetEvent;
  WaitFor;
end;

end.
