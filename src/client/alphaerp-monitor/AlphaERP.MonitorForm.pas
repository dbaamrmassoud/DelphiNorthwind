unit AlphaERP.MonitorForm;

interface

uses
  System.Classes,
  System.SyncObjs,
  System.SysUtils,
  Winapi.Messages,
  Winapi.Windows,
  Vcl.Controls,
  Vcl.ExtCtrls,
  Vcl.Forms,
  Vcl.Menus,
  Vcl.StdCtrls,
  AlphaERP.Config,
  AlphaERP.ServiceControl;

type
  TAlphaERPMonitorForm = class(TForm)
  private type
    THealthResult = record
      Succeeded: Boolean;
      ServiceState: string;
      ServiceStartedAt: string;
      ApplicationStartedAt: string;
      ApiState: string;
      ApiBaseUrl: string;
      DatabaseState: string;
      DatabaseServer: string;
      DatabaseName: string;
      LastDatabaseCheck: string;
      LastDatabaseSuccess: string;
      DatabaseError: string;
      ServerError: string;
      LogFile: string;
      ErrorText: string;
      CheckedAt: TDateTime;
    end;
    TCommandResult = record
      Succeeded: Boolean;
      ErrorText: string;
    end;
    THealthMonitorThread = class(TThread)
    private
      FHealthUrl: string;
      FStopEvent: TEvent;
      FWindowHandle: HWND;
      procedure CheckHealth;
    protected
      procedure Execute; override;
    public
      constructor Create(const WindowHandle: HWND; const HealthUrl: string);
      destructor Destroy; override;
      procedure Stop;
    end;
    TServiceCommand = (scStart, scStop, scRestart);
    TServiceCommandThread = class(TThread)
    private
      FCommand: TServiceCommand;
      FServiceName: string;
      FTimeoutMilliseconds: Cardinal;
      FWindowHandle: HWND;
    protected
      procedure Execute; override;
    public
      constructor Create(const WindowHandle: HWND; const ServiceName: string;
        const Command: TServiceCommand; const TimeoutMilliseconds: Cardinal);
    end;
  private
    FApiAddressLabel: TLabel;
    FApiCheckLabel: TLabel;
    FApiErrorLabel: TLabel;
    FApiModeLabel: TLabel;
    FApiStateLabel: TLabel;
    FAppStartedLabel: TLabel;
    FCloseToTray: Boolean;
    FCommandThread: TServiceCommandThread;
    FConfig: TAlphaERPConfig;
    FDatabaseCheckLabel: TLabel;
    FDatabaseErrorLabel: TLabel;
    FDatabaseNameLabel: TLabel;
    FDatabaseServerLabel: TLabel;
    FDatabaseStateLabel: TLabel;
    FHealthThread: THealthMonitorThread;
    FLastErrorLabel: TLabel;
    FLogFileLabel: TLabel;
    FMenu: TPopupMenu;
    FRefreshTimer: TTimer;
    FServiceNameLabel: TLabel;
    FServicePidLabel: TLabel;
    FServiceStartedLabel: TLabel;
    FServiceStateLabel: TLabel;
    FServiceUptimeLabel: TLabel;
    FStateIndicator: TShape;
    FStartButton: TButton;
    FStopButton: TButton;
    FRestartButton: TButton;
    FTrayIcon: TTrayIcon;
    FVersionLabel: TLabel;
    FLatestHealth: THealthResult;
    FHasHealthResult: Boolean;
    procedure AddField(const Parent: TWinControl; const Top: Integer;
      const Caption: string; out ValueLabel: TLabel);
    procedure AddMenuItem(const Caption: string; const Handler: TNotifyEvent);
    procedure ApplyHealthResult(const Result: THealthResult);
    procedure ApplyServiceInfo(const Info: TAlphaERPServiceInfo);
    procedure CloseToTray(Sender: TObject; var CanClose: Boolean);
    procedure CommandFinished(var Message: TMessage);
    procedure ExitMonitor(Sender: TObject);
    procedure HealthResultReceived(var Message: TMessage);
    procedure OpenConfiguration(Sender: TObject);
    procedure OpenDashboard(Sender: TObject);
    procedure OpenLogs(Sender: TObject);
    procedure RefreshStatus(Sender: TObject);
    procedure StartService(Sender: TObject);
    procedure StopService(Sender: TObject);
    procedure RestartService(Sender: TObject);
    procedure TrayDblClick(Sender: TObject);
    procedure UpdateIndicator(const State: string);
  protected
    procedure WndProc(var Message: TMessage); override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
  end;

var
  AlphaERPMonitorForm: TAlphaERPMonitorForm;

implementation

uses
  System.DateUtils,
  System.IOUtils,
  System.JSON,
  System.StrUtils,
  Winapi.ShellAPI,
  Winapi.WinSvc,
  Vcl.Graphics,
  XData.Client,
  AlphaERP.Health.Contract;

const
  WM_ALPHAERP_HEALTH_RESULT = WM_APP + 41;
  WM_ALPHAERP_COMMAND_RESULT = WM_APP + 42;

var
  TaskbarCreatedMessage: UINT;

function JsonString(const Json: TJSONObject; const Name: string): string;
var
  Value: TJSONValue;
begin
  Value := Json.GetValue(Name);
  if Value = nil then
    Result := ''
  else
    Result := Value.Value;
end;

function FormatHealthDate(const Value: string): string;
var
  DateValue: TDateTime;
begin
  if Value = '' then
    Exit('Not available');
  try
    DateValue := ISO8601ToDate(Value, False);
    Result := DateTimeToStr(DateValue);
  except
    on E: EConvertError do
      Result := Value;
  end;
end;

function ServiceStateName(const State: DWORD): string;
begin
  case State of
    SERVICE_STOPPED: Result := 'Stopped';
    SERVICE_START_PENDING: Result := 'Starting';
    SERVICE_STOP_PENDING: Result := 'Stopping';
    SERVICE_RUNNING: Result := 'Running';
    SERVICE_CONTINUE_PENDING: Result := 'Continuing';
    SERVICE_PAUSE_PENDING: Result := 'Pausing';
    SERVICE_PAUSED: Result := 'Paused';
  else
    Result := 'Unknown';
  end;
end;

constructor TAlphaERPMonitorForm.Create(AOwner: TComponent);
var
  ApiGroup: TGroupBox;
  ButtonsPanel: TPanel;
  DatabaseGroup: TGroupBox;
  ServiceGroup: TGroupBox;
  SystemGroup: TGroupBox;
begin
  inherited CreateNew(AOwner);
  FConfig := TAlphaERPConfig.Create;
  Caption := 'AlphaERP Service Monitor';
  Width := 820;
  Height := 680;
  Position := poScreenCenter;
  Font.Name := 'Segoe UI';
  Font.Size := 9;
  OnCloseQuery := CloseToTray;

  FStateIndicator := TShape.Create(Self);
  FStateIndicator.Parent := Self;
  FStateIndicator.SetBounds(16, 14, 18, 18);
  FStateIndicator.Shape := stCircle;
  FStateIndicator.Pen.Color := clGray;
  FStateIndicator.Brush.Color := clGray;

  FServiceStateLabel := TLabel.Create(Self);
  FServiceStateLabel.Parent := Self;
  FServiceStateLabel.SetBounds(42, 12, 450, 24);
  FServiceStateLabel.Font.Size := 13;
  FServiceStateLabel.Font.Style := [fsBold];
  FServiceStateLabel.Caption := 'Service state: Connecting';

  FServiceNameLabel := nil;
  FServicePidLabel := nil;
  FServiceUptimeLabel := nil;
  FServiceStartedLabel := nil;
  FVersionLabel := nil;
  FApiStateLabel := nil;
  FApiAddressLabel := nil;
  FApiModeLabel := nil;
  FApiCheckLabel := nil;
  FApiErrorLabel := nil;
  FDatabaseStateLabel := nil;
  FDatabaseServerLabel := nil;
  FDatabaseNameLabel := nil;
  FDatabaseCheckLabel := nil;
  FDatabaseErrorLabel := nil;
  FAppStartedLabel := nil;
  FLogFileLabel := nil;
  FLastErrorLabel := nil;

  ServiceGroup := TGroupBox.Create(Self);
  ServiceGroup.Parent := Self;
  ServiceGroup.Caption := 'Service information';
  ServiceGroup.SetBounds(16, 46, 380, 190);
  AddField(ServiceGroup, 22, 'Service name:', FServiceNameLabel);
  AddField(ServiceGroup, 50, 'Process ID:', FServicePidLabel);
  AddField(ServiceGroup, 78, 'Service uptime:', FServiceUptimeLabel);
  AddField(ServiceGroup, 106, 'Last startup:', FServiceStartedLabel);
  AddField(ServiceGroup, 134, 'Application version:', FVersionLabel);

  ApiGroup := TGroupBox.Create(Self);
  ApiGroup.Parent := Self;
  ApiGroup.Caption := 'REST API';
  ApiGroup.SetBounds(410, 46, 380, 190);
  AddField(ApiGroup, 22, 'Server state:', FApiStateLabel);
  AddField(ApiGroup, 50, 'Listening address/port:', FApiAddressLabel);
  AddField(ApiGroup, 78, 'Protocol:', FApiModeLabel);
  AddField(ApiGroup, 106, 'Last successful health check:', FApiCheckLabel);
  AddField(ApiGroup, 134, 'Latest server error:', FApiErrorLabel);

  DatabaseGroup := TGroupBox.Create(Self);
  DatabaseGroup.Parent := Self;
  DatabaseGroup.Caption := 'Database';
  DatabaseGroup.SetBounds(16, 248, 380, 190);
  AddField(DatabaseGroup, 22, 'Connection state:', FDatabaseStateLabel);
  AddField(DatabaseGroup, 50, 'Server:', FDatabaseServerLabel);
  AddField(DatabaseGroup, 78, 'Database:', FDatabaseNameLabel);
  AddField(DatabaseGroup, 106, 'Last successful check:', FDatabaseCheckLabel);
  AddField(DatabaseGroup, 134, 'Latest connection error:', FDatabaseErrorLabel);

  SystemGroup := TGroupBox.Create(Self);
  SystemGroup.Parent := Self;
  SystemGroup.Caption := 'System information';
  SystemGroup.SetBounds(410, 248, 380, 190);
  AddField(SystemGroup, 22, 'Service process started:', FAppStartedLabel);
  AddField(SystemGroup, 50, 'Current log file:', FLogFileLabel);
  AddField(SystemGroup, 78, 'Last service error:', FLastErrorLabel);

  ButtonsPanel := TPanel.Create(Self);
  ButtonsPanel.Parent := Self;
  ButtonsPanel.Align := alBottom;
  ButtonsPanel.Height := 58;
  ButtonsPanel.BevelOuter := bvNone;

  FStartButton := TButton.Create(Self);
  FStartButton.Parent := ButtonsPanel;
  FStartButton.SetBounds(16, 12, 118, 32);
  FStartButton.Caption := 'Start service';
  FStartButton.OnClick := StartService;

  FStopButton := TButton.Create(Self);
  FStopButton.Parent := ButtonsPanel;
  FStopButton.SetBounds(144, 12, 118, 32);
  FStopButton.Caption := 'Stop service';
  FStopButton.OnClick := StopService;

  FRestartButton := TButton.Create(Self);
  FRestartButton.Parent := ButtonsPanel;
  FRestartButton.SetBounds(272, 12, 118, 32);
  FRestartButton.Caption := 'Restart service';
  FRestartButton.OnClick := RestartService;

  FMenu := TPopupMenu.Create(Self);
  AddMenuItem('Open Dashboard', OpenDashboard);
  AddMenuItem('Start Service', StartService);
  AddMenuItem('Stop Service', StopService);
  AddMenuItem('Restart Service', RestartService);
  AddMenuItem('-', nil);
  AddMenuItem('Open Logs', OpenLogs);
  AddMenuItem('Open Configuration', OpenConfiguration);
  AddMenuItem('-', nil);
  AddMenuItem('Exit Monitor', ExitMonitor);

  FTrayIcon := TTrayIcon.Create(Self);
  FTrayIcon.Icon.Handle := LoadIcon(0, IDI_APPLICATION);
  FTrayIcon.Hint := 'AlphaERP Service Monitor';
  FTrayIcon.PopupMenu := FMenu;
  FTrayIcon.OnDblClick := TrayDblClick;
  FTrayIcon.Visible := True;

  FAppStartedLabel.Caption := DateTimeToStr(Now);
  FVersionLabel.Caption := '1.0.0.0';
  FLogFileLabel.Caption := TPath.Combine(FConfig.LogDirectory,
    FConfig.LogFileName);

  FHealthThread := THealthMonitorThread.Create(Handle, FConfig.HealthBaseUrl);
  FRefreshTimer := TTimer.Create(Self);
  FRefreshTimer.Interval := 3000;
  FRefreshTimer.OnTimer := RefreshStatus;
  FRefreshTimer.Enabled := True;
  RefreshStatus(nil);
end;

destructor TAlphaERPMonitorForm.Destroy;
var
  Message: TMsg;
  Data: ^THealthResult;
  CommandData: ^TCommandResult;
begin
  if FRefreshTimer <> nil then
    FRefreshTimer.Enabled := False;
  if FHealthThread <> nil then
  begin
    FHealthThread.Stop;
    FreeAndNil(FHealthThread);
  end;
  if FCommandThread <> nil then
  begin
    FCommandThread.Terminate;
    FCommandThread.WaitFor;
    FreeAndNil(FCommandThread);
  end;
  while PeekMessage(Message, Handle, WM_ALPHAERP_HEALTH_RESULT,
    WM_ALPHAERP_HEALTH_RESULT, PM_REMOVE) do
  begin
    Data := Pointer(Message.lParam);
    Dispose(Data);
  end;
  while PeekMessage(Message, Handle, WM_ALPHAERP_COMMAND_RESULT,
    WM_ALPHAERP_COMMAND_RESULT, PM_REMOVE) do
  begin
    CommandData := Pointer(Message.lParam);
    Dispose(CommandData);
  end;
  if FTrayIcon <> nil then
    FTrayIcon.Visible := False;
  FConfig.Free;
  inherited;
end;

procedure TAlphaERPMonitorForm.AddField(const Parent: TWinControl;
  const Top: Integer; const Caption: string; out ValueLabel: TLabel);
var
  FieldLabel: TLabel;
begin
  FieldLabel := TLabel.Create(Self);
  FieldLabel.Parent := Parent;
  FieldLabel.SetBounds(12, Top, 144, 22);
  FieldLabel.Caption := Caption;
  FieldLabel.Font.Style := [fsBold];

  ValueLabel := TLabel.Create(Self);
  ValueLabel.Parent := Parent;
  ValueLabel.SetBounds(158, Top, Parent.Width - 172, 26);
  ValueLabel.AutoSize := False;
  ValueLabel.WordWrap := True;
  ValueLabel.Caption := 'Not available';
end;

procedure TAlphaERPMonitorForm.AddMenuItem(const Caption: string;
  const Handler: TNotifyEvent);
var
  Item: TMenuItem;
begin
  Item := TMenuItem.Create(FMenu);
  Item.Caption := Caption;
  Item.OnClick := Handler;
  FMenu.Items.Add(Item);
end;

procedure TAlphaERPMonitorForm.ApplyHealthResult(
  const Result: THealthResult);
var
  ApiUrl: string;
begin
  FLatestHealth := Result;
  FHasHealthResult := Result.Succeeded;
  if not Result.Succeeded then
  begin
    FApiStateLabel.Caption := 'Unavailable';
    FApiAddressLabel.Caption := FConfig.ApiBaseUrl;
    FApiModeLabel.Caption := 'Unknown';
    FApiErrorLabel.Caption := Result.ErrorText;
    FDatabaseStateLabel.Caption := 'Unknown';
    FDatabaseCheckLabel.Caption := 'Not available';
    FDatabaseErrorLabel.Caption := 'Health endpoint unavailable';
    FLastErrorLabel.Caption := Result.ErrorText;
    Exit;
  end;

  FApiStateLabel.Caption := Result.ApiState;
  ApiUrl := Result.ApiBaseUrl;
  if ApiUrl = '' then
    ApiUrl := FConfig.ApiBaseUrl;
  FApiAddressLabel.Caption := ApiUrl;
  if StartsText('https://', ApiUrl) then
    FApiModeLabel.Caption := 'HTTPS'
  else
    FApiModeLabel.Caption := 'HTTP';
  FApiCheckLabel.Caption := DateTimeToStr(Result.CheckedAt);
  FApiErrorLabel.Caption := Result.ServerError;

  FDatabaseStateLabel.Caption := Result.DatabaseState;
  FDatabaseServerLabel.Caption := Result.DatabaseServer;
  FDatabaseNameLabel.Caption := Result.DatabaseName;
  if Result.DatabaseState = 'Connected' then
    FDatabaseCheckLabel.Caption := FormatHealthDate(Result.LastDatabaseSuccess)
  else
    FDatabaseCheckLabel.Caption := FormatHealthDate(Result.LastDatabaseSuccess);
  FDatabaseErrorLabel.Caption := Result.DatabaseError;
  FLastErrorLabel.Caption := Result.ServerError;
  if (FLastErrorLabel.Caption = '') and (Result.DatabaseError <> '') then
    FLastErrorLabel.Caption := Result.DatabaseError;
end;

procedure TAlphaERPMonitorForm.ApplyServiceInfo(
  const Info: TAlphaERPServiceInfo);
var
  StateName: string;
begin
  if not Info.Installed then
  begin
    StateName := 'Not installed';
    FServicePidLabel.Caption := '-';
    FServiceUptimeLabel.Caption := '-';
  end
  else
  begin
    StateName := ServiceStateName(Info.State);
    if (Info.State = SERVICE_RUNNING) and FHasHealthResult and
       SameText(FLatestHealth.ServiceState, 'Degraded') then
      StateName := 'Degraded';
    if (Info.State = SERVICE_RUNNING) and (FLatestHealth.CheckedAt > 0) and
       not FLatestHealth.Succeeded then
      StateName := 'Degraded';
    if Info.ProcessId = 0 then
    begin
      FServicePidLabel.Caption := '-';
      FServiceUptimeLabel.Caption := '-';
    end
    else
    begin
      FServicePidLabel.Caption := IntToStr(Info.ProcessId);
      if FHasHealthResult and (FLatestHealth.ServiceStartedAt <> '') then
        FServiceUptimeLabel.Caption := Format('%d d %s',
          [Trunc(Now - ISO8601ToDate(FLatestHealth.ServiceStartedAt, False)),
           FormatDateTime('hh":"nn":"ss',
             Frac(Now - ISO8601ToDate(
               FLatestHealth.ServiceStartedAt, False)))])
      else
        FServiceUptimeLabel.Caption := 'Unknown';
    end;
  end;
  FServiceNameLabel.Caption := FConfig.ServiceName;
  FServiceStateLabel.Caption := 'Service state: ' + StateName;
  FServiceStartedLabel.Caption := 'Not available';
  if FHasHealthResult then
  begin
    FServiceStartedLabel.Caption :=
      FormatHealthDate(FLatestHealth.ServiceStartedAt);
    if FLatestHealth.ApplicationStartedAt <> '' then
      FAppStartedLabel.Caption :=
        FormatHealthDate(FLatestHealth.ApplicationStartedAt);
    if FLatestHealth.LogFile <> '' then
      FLogFileLabel.Caption := FLatestHealth.LogFile;
  end;
  FStartButton.Enabled := not Info.Installed or
    (Info.State = SERVICE_STOPPED);
  FStopButton.Enabled := Info.Installed and
    (Info.State in [SERVICE_RUNNING, SERVICE_PAUSED]);
  FRestartButton.Enabled := Info.Installed;
  UpdateIndicator(StateName);
  FTrayIcon.Hint := 'AlphaERP: ' + StateName;
end;

procedure TAlphaERPMonitorForm.CloseToTray(Sender: TObject;
  var CanClose: Boolean);
begin
  if FCloseToTray then
  begin
    CanClose := True;
    Exit;
  end;
  CanClose := False;
  Hide;
end;

procedure TAlphaERPMonitorForm.CommandFinished(var Message: TMessage);
var
  CommandData: ^TCommandResult;
begin
  CommandData := Pointer(Message.LParam);
  try
    if not CommandData^.Succeeded then
      Application.MessageBox(PChar(CommandData^.ErrorText),
        'AlphaERP Service Monitor', MB_OK or MB_ICONERROR);
  finally
    Dispose(CommandData);
  end;
  FreeAndNil(FCommandThread);
  RefreshStatus(nil);
end;

procedure TAlphaERPMonitorForm.ExitMonitor(Sender: TObject);
begin
  FCloseToTray := True;
  FTrayIcon.Visible := False;
  Close;
end;

procedure TAlphaERPMonitorForm.HealthResultReceived(var Message: TMessage);
var
  HealthData: ^THealthResult;
begin
  HealthData := Pointer(Message.LParam);
  try
    ApplyHealthResult(HealthData^);
  finally
    Dispose(HealthData);
  end;
end;

procedure TAlphaERPMonitorForm.OpenConfiguration(Sender: TObject);
begin
  if not FileExists(FConfig.ConfigFileName) then
  begin
    Application.MessageBox(
      PChar('Configuration file was not found: ' + FConfig.ConfigFileName),
      'AlphaERP Service Monitor', MB_OK or MB_ICONINFORMATION);
    Exit;
  end;
  if NativeInt(ShellExecute(Handle, 'open', PChar(FConfig.ConfigFileName),
    nil, nil, SW_SHOWNORMAL)) <= 32 then
    Application.MessageBox(PChar('Could not open ' + FConfig.ConfigFileName),
      'AlphaERP Service Monitor', MB_OK or MB_ICONERROR);
end;

procedure TAlphaERPMonitorForm.OpenDashboard(Sender: TObject);
begin
  Show;
  WindowState := wsNormal;
  BringToFront;
  RefreshStatus(nil);
end;

procedure TAlphaERPMonitorForm.OpenLogs(Sender: TObject);
var
  LogFile: string;
begin
  LogFile := TPath.Combine(FConfig.LogDirectory, FConfig.LogFileName);
  if DirectoryExists(FConfig.LogDirectory) then
  begin
    if FileExists(LogFile) then
    begin
      if NativeInt(ShellExecute(Handle, 'open', PChar(LogFile),
        nil, nil, SW_SHOWNORMAL)) > 32 then
        Exit;
    end;
    if NativeInt(ShellExecute(Handle, 'open', PChar(FConfig.LogDirectory),
      nil, nil, SW_SHOWNORMAL)) > 32 then
      Exit;
  end;
  Application.MessageBox(PChar('Log directory is not available: ' +
    FConfig.LogDirectory), 'AlphaERP Service Monitor',
    MB_OK or MB_ICONINFORMATION);
end;

procedure TAlphaERPMonitorForm.RefreshStatus(Sender: TObject);
var
  Info: TAlphaERPServiceInfo;
begin
  try
    Info := QueryAlphaERPService(FConfig.ServiceName);
    ApplyServiceInfo(Info);
  except
    on E: Exception do
    begin
      FServiceStateLabel.Caption := 'Service state: Unavailable';
      FServicePidLabel.Caption := 'Unknown';
      FServiceUptimeLabel.Caption := 'Unknown';
      FLastErrorLabel.Caption := E.Message;
      UpdateIndicator('Error');
    end;
  end;
end;

procedure TAlphaERPMonitorForm.StartService(Sender: TObject);
begin
  if FCommandThread <> nil then
    Exit;
  FCommandThread := TServiceCommandThread.Create(Handle, FConfig.ServiceName,
    scStart, Cardinal(FConfig.RequestTimeoutMilliseconds));
  FStartButton.Enabled := False;
  FStopButton.Enabled := False;
  FRestartButton.Enabled := False;
end;

procedure TAlphaERPMonitorForm.StopService(Sender: TObject);
begin
  if FCommandThread <> nil then
    Exit;
  FCommandThread := TServiceCommandThread.Create(Handle, FConfig.ServiceName,
    scStop, Cardinal(FConfig.RequestTimeoutMilliseconds));
  FStartButton.Enabled := False;
  FStopButton.Enabled := False;
  FRestartButton.Enabled := False;
end;

procedure TAlphaERPMonitorForm.RestartService(Sender: TObject);
begin
  if FCommandThread <> nil then
    Exit;
  FCommandThread := TServiceCommandThread.Create(Handle, FConfig.ServiceName,
    scRestart, Cardinal(FConfig.RequestTimeoutMilliseconds));
  FStartButton.Enabled := False;
  FStopButton.Enabled := False;
  FRestartButton.Enabled := False;
end;

procedure TAlphaERPMonitorForm.TrayDblClick(Sender: TObject);
begin
  OpenDashboard(Sender);
end;

procedure TAlphaERPMonitorForm.UpdateIndicator(const State: string);
var
  Color: TColor;
begin
  if SameText(State, 'Running') then
    Color := clGreen
  else if SameText(State, 'Degraded') or SameText(State, 'Starting') or
          SameText(State, 'Stopping') then
    Color := clYellow
  else if SameText(State, 'Error') then
    Color := clRed
  else
    Color := clGray;
  FStateIndicator.Brush.Color := Color;
  FStateIndicator.Pen.Color := Color;
end;

procedure TAlphaERPMonitorForm.WndProc(var Message: TMessage);
begin
  if Message.Msg = WM_ALPHAERP_HEALTH_RESULT then
  begin
    HealthResultReceived(Message);
    Exit;
  end;
  if Message.Msg = WM_ALPHAERP_COMMAND_RESULT then
  begin
    CommandFinished(Message);
    Exit;
  end;
  if (TaskbarCreatedMessage <> 0) and
     (Message.Msg = TaskbarCreatedMessage) then
  begin
    FTrayIcon.Visible := False;
    FTrayIcon.Visible := True;
  end;
  inherited WndProc(Message);
end;

constructor TAlphaERPMonitorForm.THealthMonitorThread.Create(
  const WindowHandle: HWND; const HealthUrl: string);
begin
  inherited Create(True);
  FreeOnTerminate := False;
  FWindowHandle := WindowHandle;
  FHealthUrl := HealthUrl;
  FStopEvent := TEvent.Create(nil, True, False, '');
  Start;
end;

destructor TAlphaERPMonitorForm.THealthMonitorThread.Destroy;
begin
  Stop;
  FStopEvent.Free;
  inherited;
end;

procedure TAlphaERPMonitorForm.THealthMonitorThread.CheckHealth;
var
  Client: TXDataClient;
  HealthJson: string;
  Json: TJSONObject;
  JsonValue: TJSONValue;
  HealthData: ^THealthResult;
begin
  New(HealthData);
  Client := nil;
  try
    try
      Client := TXDataClient.Create;
      Client.Uri := FHealthUrl;
      HealthJson := Client.Service<IAlphaERPHealthService>.GetStatus;
      JsonValue := TJSONObject.ParseJSONValue(HealthJson);
      if not (JsonValue is TJSONObject) then
      begin
        JsonValue.Free;
        raise Exception.Create('Health endpoint returned invalid JSON.');
      end;
      Json := TJSONObject(JsonValue);
      try
        HealthData^.Succeeded := True;
        HealthData^.ServiceState := JsonString(Json, 'service_state');
        HealthData^.ServiceStartedAt :=
          JsonString(Json, 'service_started_at');
        HealthData^.ApplicationStartedAt :=
          JsonString(Json, 'application_started_at');
        HealthData^.ApiState := JsonString(Json, 'api_state');
        HealthData^.ApiBaseUrl := JsonString(Json, 'api_base_url');
        HealthData^.DatabaseState := JsonString(Json, 'database_state');
        HealthData^.DatabaseServer := JsonString(Json, 'database_server');
        HealthData^.DatabaseName := JsonString(Json, 'database_name');
        HealthData^.LastDatabaseCheck :=
          JsonString(Json, 'last_database_check');
        HealthData^.LastDatabaseSuccess :=
          JsonString(Json, 'last_database_success');
        HealthData^.DatabaseError := JsonString(Json, 'database_error');
        HealthData^.ServerError := JsonString(Json, 'last_server_error');
        HealthData^.LogFile := JsonString(Json, 'log_file');
        HealthData^.CheckedAt := Now;
      finally
        Json.Free;
      end;
    except
      on E: Exception do
      begin
        HealthData^.Succeeded := False;
        HealthData^.ErrorText := E.Message;
        HealthData^.CheckedAt := Now;
      end;
    end;
  finally
    Client.Free;
  end;

  if not PostMessage(FWindowHandle, WM_ALPHAERP_HEALTH_RESULT, 0,
    LPARAM(HealthData)) then
    Dispose(HealthData);
end;

procedure TAlphaERPMonitorForm.THealthMonitorThread.Execute;
begin
  while not Terminated do
  begin
    CheckHealth;
    if FStopEvent.WaitFor(15000) <> wrTimeout then
      Break;
  end;
end;

procedure TAlphaERPMonitorForm.THealthMonitorThread.Stop;
begin
  Terminate;
  FStopEvent.SetEvent;
  WaitFor;
end;

constructor TAlphaERPMonitorForm.TServiceCommandThread.Create(
  const WindowHandle: HWND; const ServiceName: string;
  const Command: TServiceCommand; const TimeoutMilliseconds: Cardinal);
begin
  inherited Create(True);
  FreeOnTerminate := False;
  FWindowHandle := WindowHandle;
  FServiceName := ServiceName;
  FCommand := Command;
  FTimeoutMilliseconds := TimeoutMilliseconds;
  Start;
end;

procedure TAlphaERPMonitorForm.TServiceCommandThread.Execute;
var
  CommandData: ^TCommandResult;
begin
  New(CommandData);
  CommandData^.Succeeded := False;
  CommandData^.ErrorText := '';
  try
    case FCommand of
      scStart: StartAlphaERPService(FServiceName);
      scStop: StopAlphaERPService(FServiceName);
      scRestart: RestartAlphaERPService(FServiceName, FTimeoutMilliseconds);
    end;
    CommandData^.Succeeded := True;
  except
    on E: Exception do
      CommandData^.ErrorText := E.Message;
  end;
  if not PostMessage(FWindowHandle, WM_ALPHAERP_COMMAND_RESULT, 0,
    LPARAM(CommandData)) then
    Dispose(CommandData);
end;

initialization
  TaskbarCreatedMessage := RegisterWindowMessage('TaskbarCreated');

end.
