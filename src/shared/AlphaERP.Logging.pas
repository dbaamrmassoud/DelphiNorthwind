unit AlphaERP.Logging;

interface

type
  TAlphaERPLogLevel = (allDebug, allInfo, allWarning, allError);

  TAlphaERPLogger = class
  public
    class procedure Initialize(const FileName: string;
      const MinimumLevel: TAlphaERPLogLevel; const MaxSizeMB,
      MaxFiles: Integer); static;
    class procedure Debug(const MessageText: string); static;
    class procedure Info(const MessageText: string); static;
    class procedure Warning(const MessageText: string); static;
    class procedure Error(const MessageText: string); static;
  end;

function AlphaERPLogLevelFromString(const Value: string): TAlphaERPLogLevel;

implementation

uses
  System.Classes,
  System.IOUtils,
  System.SyncObjs,
  System.SysUtils,
  VCL.TMSLogging;

var
  LogLock: TCriticalSection;
  LogFileName: string;
  LogMinimumLevel: TAlphaERPLogLevel;
  LogMaxSizeBytes: Int64;
  LogMaxFiles: Integer;

function AlphaERPLogLevelFromString(const Value: string): TAlphaERPLogLevel;
begin
  if SameText(Value, 'DEBUG') then
    Exit(allDebug);
  if SameText(Value, 'INFO') then
    Exit(allInfo);
  if SameText(Value, 'WARNING') then
    Exit(allWarning);
  if SameText(Value, 'ERROR') then
    Exit(allError);
  raise Exception.CreateFmt('Unsupported log level: %s', [Value]);
end;

function LogLevelName(const Level: TAlphaERPLogLevel): string;
begin
  case Level of
    allDebug: Result := 'DEBUG';
    allInfo: Result := 'INFO';
    allWarning: Result := 'WARNING';
  else
    Result := 'ERROR';
  end;
end;

function LogLevelEnabled(const Level: TAlphaERPLogLevel): Boolean;
begin
  Result := Ord(Level) >= Ord(LogMinimumLevel);
end;

procedure RotateLogFiles;
var
  CurrentName: string;
  NextName: string;
  Stream: TFileStream;
  I: Integer;
begin
  if not FileExists(LogFileName) then
    Exit;
  Stream := TFileStream.Create(LogFileName, fmOpenRead or fmShareDenyNone);
  try
    if Stream.Size < LogMaxSizeBytes then
      Exit;
  finally
    Stream.Free;
  end;

  for I := LogMaxFiles downto 1 do
  begin
    CurrentName := LogFileName + '.' + IntToStr(I);
    if I = LogMaxFiles then
    begin
      if FileExists(CurrentName) and
         not System.SysUtils.DeleteFile(CurrentName) then
        raise EFCreateError.CreateFmt('Could not remove old log file %s.',
          [CurrentName]);
    end
    else if FileExists(CurrentName) then
    begin
      NextName := LogFileName + '.' + IntToStr(I + 1);
      if FileExists(NextName) and
         not System.SysUtils.DeleteFile(NextName) then
        raise EFCreateError.CreateFmt('Could not remove old log file %s.',
          [NextName]);
      if not System.SysUtils.RenameFile(CurrentName, NextName) then
        raise EFCreateError.CreateFmt('Could not rotate log file %s.',
          [CurrentName]);
    end;
  end;

  NextName := LogFileName + '.1';
  if not System.SysUtils.RenameFile(LogFileName, NextName) then
    raise EFCreateError.CreateFmt('Could not rotate log file %s.',
      [LogFileName]);
end;

procedure WriteLog(const Level: TAlphaERPLogLevel; const MessageText: string);
var
  Line: string;
begin
  if not LogLevelEnabled(Level) then
    Exit;
  Line := FormatDateTime('yyyy"-"mm"-"dd"T"hh":"nn":"ss"."zzz',
    Now) + ' [' + LogLevelName(Level) + '] ' + MessageText + sLineBreak;

  LogLock.Acquire;
  try
    if LogFileName = '' then
      raise Exception.Create('AlphaERP logger has not been initialized.');
    RotateLogFiles;
    TFile.AppendAllText(LogFileName, Line, TEncoding.UTF8);
    case Level of
      allError: TMSLogger.Error(MessageText);
      allWarning: TMSLogger.Info('[WARNING] ' + MessageText);
      allDebug: TMSLogger.Info('[DEBUG] ' + MessageText);
    else
      TMSLogger.Info(MessageText);
    end;
  finally
    LogLock.Release;
  end;
end;

class procedure TAlphaERPLogger.Initialize(const FileName: string;
  const MinimumLevel: TAlphaERPLogLevel; const MaxSizeMB, MaxFiles: Integer);
var
  DirectoryName: string;
begin
  if FileName = '' then
    raise Exception.Create('The AlphaERP log file name cannot be empty.');
  if (MaxSizeMB < 1) or (MaxFiles < 1) then
    raise Exception.Create('Log rotation settings must be positive.');
  DirectoryName := ExtractFilePath(FileName);
  if (DirectoryName <> '') and not DirectoryExists(DirectoryName) and
     not ForceDirectories(DirectoryName) then
    raise EFCreateError.CreateFmt('Could not create log directory: %s',
      [DirectoryName]);

  LogLock.Acquire;
  try
    LogFileName := ExpandFileName(FileName);
    LogMinimumLevel := MinimumLevel;
    LogMaxSizeBytes := Int64(MaxSizeMB) * 1024 * 1024;
    LogMaxFiles := MaxFiles;
  finally
    LogLock.Release;
  end;
end;

class procedure TAlphaERPLogger.Debug(const MessageText: string);
begin
  WriteLog(allDebug, MessageText);
end;

class procedure TAlphaERPLogger.Error(const MessageText: string);
begin
  WriteLog(allError, MessageText);
end;

class procedure TAlphaERPLogger.Info(const MessageText: string);
begin
  WriteLog(allInfo, MessageText);
end;

class procedure TAlphaERPLogger.Warning(const MessageText: string);
begin
  WriteLog(allWarning, MessageText);
end;

initialization
  LogLock := TCriticalSection.Create;
  LogMinimumLevel := allInfo;
  LogMaxSizeBytes := 10 * 1024 * 1024;
  LogMaxFiles := 5;

finalization
  LogLock.Free;

end.
