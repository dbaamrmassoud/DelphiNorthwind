program AlphaERPService;

uses
  Winapi.Windows,
  Winapi.WinSvc,
  System.SysUtils,
  Vcl.SvcMgr,
  AlphaERP.Config in '..\..\shared\AlphaERP.Config.pas',
  AlphaERP.ServiceControl in '..\..\shared\AlphaERP.ServiceControl.pas',
  AlphaERP.Health.Contract in '..\..\shared\AlphaERP.Health.Contract.pas',
  AlphaERP.Logging in '..\..\shared\AlphaERP.Logging.pas',
  AlphaERP.Status in '..\..\shared\AlphaERP.Status.pas',
  Northwind.Entities in '..\..\shared\Northwind.Entities.pas',
  Northwind.OrderService.Contract in '..\..\shared\Northwind.OrderService.Contract.pas',
  AlphaERP.Health.Service in 'AlphaERP.Health.Service.pas',
  AlphaERP.ServiceHost in 'AlphaERP.ServiceHost.pas',
  AlphaERP.ServiceModule in 'AlphaERP.ServiceModule.pas',
  Northwind.OrderService in '..\api\Northwind.OrderService.pas';

procedure PrintToConsole(const Text: string);
var
  ConsoleHandle: THandle;
  Written: DWORD;
begin
  AllocConsole;
  try
    ConsoleHandle := GetStdHandle(STD_OUTPUT_HANDLE);
    if ConsoleHandle <> INVALID_HANDLE_VALUE then
      WriteConsole(ConsoleHandle, PChar(Text + sLineBreak), Length(Text) +
        Length(sLineBreak), Written, nil);
  finally
    FreeConsole;
  end;
end;

function ServiceStateText(const State: DWORD): string;
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

function RunManagementCommand: Boolean;
var
  Config: TAlphaERPConfig;
  Info: TAlphaERPServiceInfo;
  Command: string;
  Text: string;
begin
  Result := True;
  Command := LowerCase(ParamStr(1));
  if (Command <> '--status') and (Command <> '/status') and
     (Command <> '--start') and (Command <> '/start') and
     (Command <> '--stop') and (Command <> '/stop') and
     (Command <> '--restart') and (Command <> '/restart') then
    Exit(False);

  Config := TAlphaERPConfig.Create;
  try
    try
      if (Command = '--status') or (Command = '/status') then
      begin
        Info := QueryAlphaERPService(Config.ServiceName);
        if Info.Installed then
          Text := Format('%s: %s (PID %d)',
            [Config.ServiceName, ServiceStateText(Info.State), Info.ProcessId])
        else
          Text := Config.ServiceName + ': Not installed';
        ExitCode := 0;
      end
      else if (Command = '--start') or (Command = '/start') then
      begin
        StartAlphaERPService(Config.ServiceName);
        Text := Config.ServiceName + ': start requested';
        ExitCode := 0;
      end
      else if (Command = '--stop') or (Command = '/stop') then
      begin
        StopAlphaERPService(Config.ServiceName);
        Text := Config.ServiceName + ': stop requested';
        ExitCode := 0;
      end
      else
      begin
        RestartAlphaERPService(Config.ServiceName,
          Cardinal(Config.RequestTimeoutMilliseconds));
        Text := Config.ServiceName + ': restarted';
        ExitCode := 0;
      end;
    except
      on E: Exception do
      begin
        Text := E.Message;
        ExitCode := 1;
      end;
    end;
  finally
    Config.Free;
  end;
  PrintToConsole(Text);
end;

begin
  if RunManagementCommand then
    Exit;

  if not Application.DelayInitialize or Application.Installing then
    Application.Initialize;
  Application.Title := 'AlphaERP Service';
  Application.CreateForm(TAlphaERPService, AlphaERPService);
  Application.Run;
end.
