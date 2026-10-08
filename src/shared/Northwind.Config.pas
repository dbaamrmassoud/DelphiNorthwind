unit Northwind.Config;

interface

function ReadSetting(const Section, Name, DefaultValue: string): string;
function RequireEnvironmentVariable(const Name: string): string;
function RequireJwtSecret: string;

implementation

uses
  System.SysUtils,
  System.IniFiles;

function ConfigFileName: string;
begin
  Result := IncludeTrailingPathDelimiter(ExtractFilePath(ParamStr(0))) +
    'Northwind.ini';
end;

function ReadSetting(const Section, Name, DefaultValue: string): string;
var
  Ini: TIniFile;
begin
  Ini := TIniFile.Create(ConfigFileName);
  try
    Result := Ini.ReadString(Section, Name, DefaultValue);
  finally
    Ini.Free;
  end;
end;

function RequireEnvironmentVariable(const Name: string): string;
begin
  Result := GetEnvironmentVariable(Name);
  if Result = '' then
    raise Exception.CreateFmt('Required environment variable %s is not set.', [Name]);
end;

function RequireJwtSecret: string;
var
  SecretBytes: TBytes;
begin
  Result := RequireEnvironmentVariable('NORTHWIND_JWT_SECRET');
  SecretBytes := TEncoding.UTF8.GetBytes(Result);
  if Length(SecretBytes) < 32 then
    raise Exception.Create(
      'NORTHWIND_JWT_SECRET must contain at least 32 UTF-8 bytes.');
end;

end.
