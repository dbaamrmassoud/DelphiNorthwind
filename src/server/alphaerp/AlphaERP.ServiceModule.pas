unit AlphaERP.ServiceModule;

interface

uses
  System.Classes,
  Vcl.SvcMgr,
  AlphaERP.ServiceHost;

type
  TAlphaERPService = class(TService)
  private
    FHost: TAlphaERPServiceHost;
    procedure ServiceExecute(Sender: TService);
    procedure ServiceShutdown(Sender: TService);
    procedure ServiceStart(Sender: TService; var Started: Boolean);
    procedure ServiceStop(Sender: TService; var Stopped: Boolean);
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    function GetServiceController: TServiceController; override;
  end;

var
  AlphaERPService: TAlphaERPService;

implementation

uses
  System.SysUtils,
  Winapi.Windows,
  AlphaERP.Config,
  VCL.TMSLogging;

constructor TAlphaERPService.Create(AOwner: TComponent);
var
  Config: TAlphaERPConfig;
begin
  inherited CreateNew(AOwner);
  Config := TAlphaERPConfig.Create;
  try
    Name := Config.ServiceName;
    DisplayName := Config.ServiceDisplayName;
    if Config.StartAutomatically then
      StartType := stAuto
    else
      StartType := stManual;
    WaitHint := Config.RequestTimeoutMilliseconds;
  finally
    Config.Free;
  end;
  AllowStop := True;
  AllowPause := False;
  OnStart := ServiceStart;
  OnStop := ServiceStop;
  OnShutdown := ServiceShutdown;
  OnExecute := ServiceExecute;
end;

destructor TAlphaERPService.Destroy;
begin
  FHost.Free;
  inherited;
end;

procedure ServiceController(CtrlCode: DWord); stdcall; forward;

function TAlphaERPService.GetServiceController: TServiceController;
begin
  Result := ServiceController;
end;

procedure TAlphaERPService.ServiceExecute(Sender: TService);
begin
  while not Terminated do
  begin
    ServiceThread.ProcessRequests(False);
    Sleep(100);
  end;
end;

procedure TAlphaERPService.ServiceStart(Sender: TService;
  var Started: Boolean);
begin
  Started := False;
  try
    if FHost = nil then
      FHost := TAlphaERPServiceHost.Create;
    FHost.Start;
    Started := True;
    LogMessage('AlphaERP service start request completed.',
      EVENTLOG_INFORMATION_TYPE);
    TMSLogger.Info('Windows Service start request completed.');
  except
    on E: Exception do
    begin
      LogMessage('AlphaERP service failed to start: ' + E.Message,
        EVENTLOG_ERROR_TYPE);
      TMSLogger.Error('Windows Service failed to start: ' + E.Message);
      FreeAndNil(FHost);
      Started := False;
    end;
  end;
end;

procedure TAlphaERPService.ServiceStop(Sender: TService;
  var Stopped: Boolean);
begin
  Stopped := False;
  try
    if FHost <> nil then
      FHost.Stop;
    FreeAndNil(FHost);
    Stopped := True;
    LogMessage('AlphaERP service stop request completed.',
      EVENTLOG_INFORMATION_TYPE);
    TMSLogger.Info('Windows Service stop request completed.');
  except
    on E: Exception do
    begin
      LogMessage('AlphaERP service failed to stop cleanly: ' + E.Message,
        EVENTLOG_ERROR_TYPE);
      TMSLogger.Error('Windows Service failed to stop cleanly: ' + E.Message);
      Stopped := False;
    end;
  end;
end;

procedure TAlphaERPService.ServiceShutdown(Sender: TService);
begin
  try
    if FHost <> nil then
      FHost.Stop;
    FreeAndNil(FHost);
    LogMessage('AlphaERP service stopped for Windows shutdown.',
      EVENTLOG_INFORMATION_TYPE);
  except
    on E: Exception do
    begin
      LogMessage('AlphaERP service shutdown error: ' + E.Message,
        EVENTLOG_ERROR_TYPE);
      TMSLogger.Error('Windows shutdown error: ' + E.Message);
      FreeAndNil(FHost);
    end;
  end;
end;

procedure ServiceController(CtrlCode: DWord); stdcall;
begin
  AlphaERPService.Controller(CtrlCode);
end;

end.
