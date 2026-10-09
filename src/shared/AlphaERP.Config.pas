unit AlphaERP.Config;

interface

type
  TAlphaERPConfig = class
  private
    FApiBaseUrl: string;
    FConfigFileName: string;
    FDatabaseName: string;
    FDatabaseLoginTimeoutSeconds: Integer;
    FDatabasePasswordEnvironmentVariable: string;
    FDatabaseServer: string;
    FDatabaseUserEnvironmentVariable: string;
    FEncryptConnection: Boolean;
    FHealthBaseUrl: string;
    FHealthCheckIntervalSeconds: Integer;
    FJwtSecretEnvironmentVariable: string;
    FLogLevel: string;
    FLogDirectory: string;
    FLogFileName: string;
    FMaxLogFiles: Integer;
    FMaxLogSizeMB: Integer;
    FMaxConnections: Integer;
    FRequestTimeoutMilliseconds: Integer;
    FServiceDisplayName: string;
    FServiceName: string;
    FStartAutomatically: Boolean;
    FTlsCertificateThumbprint: string;
    FTrustServerCertificate: Boolean;
    procedure Validate;
  public
    constructor Create;
    function GetJwtSecret: string;
    property ApiBaseUrl: string read FApiBaseUrl;
    property ConfigFileName: string read FConfigFileName;
    property DatabaseName: string read FDatabaseName;
    property DatabaseLoginTimeoutSeconds: Integer
      read FDatabaseLoginTimeoutSeconds;
    property DatabasePasswordEnvironmentVariable: string
      read FDatabasePasswordEnvironmentVariable;
    property DatabaseServer: string read FDatabaseServer;
    property DatabaseUserEnvironmentVariable: string
      read FDatabaseUserEnvironmentVariable;
    property EncryptConnection: Boolean read FEncryptConnection;
    property HealthBaseUrl: string read FHealthBaseUrl;
    property HealthCheckIntervalSeconds: Integer read FHealthCheckIntervalSeconds;
    property JwtSecretEnvironmentVariable: string
      read FJwtSecretEnvironmentVariable;
    property LogLevel: string read FLogLevel;
    property LogDirectory: string read FLogDirectory;
    property LogFileName: string read FLogFileName;
    property MaxLogFiles: Integer read FMaxLogFiles;
    property MaxLogSizeMB: Integer read FMaxLogSizeMB;
    property MaxConnections: Integer read FMaxConnections;
    property RequestTimeoutMilliseconds: Integer
      read FRequestTimeoutMilliseconds;
    property ServiceDisplayName: string read FServiceDisplayName;
    property ServiceName: string read FServiceName;
    property StartAutomatically: Boolean read FStartAutomatically;
    property TlsCertificateThumbprint: string
      read FTlsCertificateThumbprint;
    property TrustServerCertificate: Boolean read FTrustServerCertificate;
  end;

implementation

uses
  System.IniFiles,
  System.IOUtils,
  System.SysUtils,
  System.StrUtils;

function ConfigPath: string;
begin
  Result := GetEnvironmentVariable('ALPHAERP_CONFIG_FILE');
  if Result = '' then
    Result := TPath.Combine(ExtractFilePath(ParamStr(0)), 'AlphaERP.ini');
end;

function ReadRequiredEnvironmentVariable(const Name: string): string;
begin
  Result := GetEnvironmentVariable(Name);
  if Result = '' then
    raise Exception.CreateFmt(
      'Required environment variable %s is not set.', [Name]);
end;

function ParseUrlHost(const Url: string; out Host: string): Boolean;
var
  Authority: string;
  AuthorityEnd: Integer;
  I: Integer;
  Port: string;
  Remainder: string;
  ColonPosition: Integer;
  PortValue: Integer;
begin
  Host := '';
  Result := False;
  if StartsText('https://', Url) then
    Remainder := Copy(Url, Length('https://') + 1, MaxInt)
  else if StartsText('http://', Url) then
    Remainder := Copy(Url, Length('http://') + 1, MaxInt)
  else
    Exit;

  AuthorityEnd := Length(Remainder) + 1;
  for I := 1 to Length(Remainder) do
    if CharInSet(Remainder[I], ['/', '?', '#']) then
    begin
      AuthorityEnd := I;
      Break;
    end;
  Authority := Copy(Remainder, 1, AuthorityEnd - 1);

  if (Authority = '') or (Pos('@', Authority) > 0) then
    Exit;
  if Authority[1] = '[' then
  begin
    ColonPosition := Pos(']', Authority);
    if ColonPosition = 0 then
      Exit;
    Host := Copy(Authority, 1, ColonPosition);
    Remainder := Copy(Authority, ColonPosition + 1, MaxInt);
    if (Remainder <> '') and ((Remainder[1] <> ':') or
       not TryStrToInt(Copy(Remainder, 2, MaxInt), PortValue) or
       (PortValue < 1) or (PortValue > 65535)) then
      Exit;
  end
  else
  begin
    ColonPosition := Pos(':', Authority);
    if ColonPosition > 0 then
    begin
      Host := Copy(Authority, 1, ColonPosition - 1);
      Port := Copy(Authority, ColonPosition + 1, MaxInt);
      if (Pos(':', Port) > 0) or not TryStrToInt(Port, PortValue) or
         (PortValue < 1) or (PortValue > 65535) then
        Exit;
    end
    else
      Host := Authority;
  end;

  Result := Host <> '';
end;

function IsLoopbackHost(const Host: string): Boolean;
begin
  Result := SameText(Host, 'localhost') or
    SameText(Host, '127.0.0.1') or SameText(Host, '[::1]');
end;

function ParseBoolean(const Ini: TIniFile; const Section, Key: string;
  const DefaultValue: Boolean): Boolean;
var
  Value: string;
begin
  Value := Ini.ReadString(Section, Key, '');
  if Value = '' then
    Exit(DefaultValue);
  if SameText(Value, 'true') or SameText(Value, 'yes') or (Value = '1') then
    Exit(True);
  if SameText(Value, 'false') or SameText(Value, 'no') or (Value = '0') then
    Exit(False);
  raise Exception.CreateFmt('Invalid Boolean value for [%s] %s: %s',
    [Section, Key, Value]);
end;

function ParseInteger(const Ini: TIniFile; const Section, Key: string;
  const DefaultValue: Integer; const MinimumValue, MaximumValue: Integer): Integer;
var
  Value: string;
begin
  Value := Ini.ReadString(Section, Key, IntToStr(DefaultValue));
  if not TryStrToInt(Value, Result) or
     (Result < MinimumValue) or (Result > MaximumValue) then
    raise Exception.CreateFmt(
      '[%s] %s must be an integer from %d through %d.',
      [Section, Key, MinimumValue, MaximumValue]);
end;

constructor TAlphaERPConfig.Create;
var
  Ini: TIniFile;
  ProgramData: string;
begin
  inherited Create;
  FConfigFileName := ConfigPath;
  Ini := TIniFile.Create(FConfigFileName);
  try
    FServiceName := Ini.ReadString('Service', 'Name', 'AlphaERPService');
    FServiceDisplayName := Ini.ReadString('Service', 'DisplayName',
      'AlphaERP Service');
    FApiBaseUrl := Trim(Ini.ReadString('Service', 'ApiBaseUrl',
      'http://localhost:2004/tms/alphaerp/xdata'));
    FHealthBaseUrl := Trim(Ini.ReadString('Service', 'HealthBaseUrl',
      'http://127.0.0.1:2005/tms/alphaerp/health'));
    FStartAutomatically := SameText(
      Ini.ReadString('Service', 'StartMode', 'auto'), 'auto');
    if not FStartAutomatically and
       not SameText(Ini.ReadString('Service', 'StartMode', 'auto'), 'manual') then
      raise Exception.Create('[Service] StartMode must be auto or manual.');
    FRequestTimeoutMilliseconds := ParseInteger(Ini, 'Service',
      'RequestTimeoutMilliseconds', 30000, 1000, 300000);
    FHealthCheckIntervalSeconds := ParseInteger(Ini, 'Service',
      'HealthCheckIntervalSeconds', 30, 5, 3600);
    FMaxConnections := ParseInteger(Ini, 'Database', 'MaxConnections',
      32, 1, 256);

    FDatabaseServer := Trim(Ini.ReadString('Database', 'Server', 'localhost'));
    FDatabaseName := Trim(Ini.ReadString('Database', 'Database', 'Northwind'));
    FDatabaseLoginTimeoutSeconds := ParseInteger(Ini, 'Database',
      'LoginTimeoutSeconds', 15, 1, 120);
    FDatabaseUserEnvironmentVariable := Ini.ReadString('Database',
      'UserEnvironmentVariable', 'ALPHAERP_SQL_USER');
    FDatabasePasswordEnvironmentVariable := Ini.ReadString('Database',
      'PasswordEnvironmentVariable', 'ALPHAERP_SQL_PASSWORD');
    FEncryptConnection := ParseBoolean(Ini, 'Database', 'Encrypt', True);
    FTrustServerCertificate := ParseBoolean(Ini, 'Database',
      'TrustServerCertificate', False);

    FJwtSecretEnvironmentVariable := Ini.ReadString('Security',
      'JwtSecretEnvironmentVariable', 'NORTHWIND_JWT_SECRET');
    FTlsCertificateThumbprint := Ini.ReadString('Security',
      'TlsCertificateThumbprint', '');

    ProgramData := GetEnvironmentVariable('PROGRAMDATA');
    if ProgramData = '' then
      ProgramData := ExtractFilePath(ParamStr(0));
    FLogDirectory := Ini.ReadString('Logging', 'Directory',
      TPath.Combine(ProgramData, 'AlphaERP\Logs'));
    FLogDirectory := ExpandFileName(FLogDirectory);
    FLogFileName := Trim(Ini.ReadString('Logging', 'FileName', 'AlphaERP.log'));
    FLogLevel := UpperCase(Trim(Ini.ReadString('Logging', 'Level', 'INFO')));
    FMaxLogSizeMB := ParseInteger(Ini, 'Logging', 'MaxSizeMB', 10, 1, 1024);
    FMaxLogFiles := ParseInteger(Ini, 'Logging', 'MaxFiles', 5, 1, 30);
  finally
    Ini.Free;
  end;

  Validate;
end;

function TAlphaERPConfig.GetJwtSecret: string;
var
  SecretBytes: TBytes;
begin
  Result := ReadRequiredEnvironmentVariable(FJwtSecretEnvironmentVariable);
  SecretBytes := TEncoding.UTF8.GetBytes(Result);
  if Length(SecretBytes) < 32 then
    raise Exception.CreateFmt(
      '%s must contain at least 32 UTF-8 bytes.',
      [FJwtSecretEnvironmentVariable]);
end;

procedure TAlphaERPConfig.Validate;
var
  ApiHost: string;
  HealthHost: string;
  I: Integer;
  LogName: string;
begin
  if FServiceName = '' then
    raise Exception.Create('[Service] Name cannot be empty.');
  if not CharInSet(FServiceName[1], ['A'..'Z', 'a'..'z', '_']) then
    raise Exception.Create(
      '[Service] Name must be a valid Delphi service identifier.');
  for I := 2 to Length(FServiceName) do
    if not CharInSet(FServiceName[I], ['A'..'Z', 'a'..'z', '0'..'9', '_']) then
      raise Exception.Create(
        '[Service] Name must be a valid Delphi service identifier.');
  if FServiceDisplayName = '' then
    raise Exception.Create('[Service] DisplayName cannot be empty.');
  if not ParseUrlHost(FApiBaseUrl, ApiHost) then
    raise Exception.Create('[Service] ApiBaseUrl must be an absolute HTTP URL.');
  if StartsText('http://', FApiBaseUrl) and not IsLoopbackHost(ApiHost) then
    raise Exception.Create(
      '[Service] ApiBaseUrl must use HTTPS; HTTP is allowed only on loopback.');
  if not ParseUrlHost(FHealthBaseUrl, HealthHost) or
     not IsLoopbackHost(HealthHost) then
    raise Exception.Create('[Service] HealthBaseUrl must resolve to loopback.');
  if FDatabaseServer = '' then
    raise Exception.Create('[Database] Server cannot be empty.');
  if FDatabaseName = '' then
    raise Exception.Create('[Database] Database cannot be empty.');
  if (FDatabaseUserEnvironmentVariable = '') or
     (FDatabasePasswordEnvironmentVariable = '') then
    raise Exception.Create(
      '[Database] Credential environment variable names cannot be empty.');
  if FJwtSecretEnvironmentVariable = '' then
    raise Exception.Create(
      '[Security] JwtSecretEnvironmentVariable cannot be empty.');
  if (FLogLevel <> 'DEBUG') and (FLogLevel <> 'INFO') and
     (FLogLevel <> 'WARNING') and (FLogLevel <> 'ERROR') then
    raise Exception.Create(
      '[Logging] Level must be DEBUG, INFO, WARNING, or ERROR.');
  LogName := ExtractFileName(FLogFileName);
  if (LogName = '') or (LogName <> FLogFileName) or
     (FLogFileName = '.') or (FLogFileName = '..') then
    raise Exception.Create(
      '[Logging] FileName must be a file name, not a path.');
end;

end.
