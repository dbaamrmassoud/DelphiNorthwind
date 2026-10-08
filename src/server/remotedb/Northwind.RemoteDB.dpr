program NorthwindRemoteDB;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  FireDAC.Comp.Client,
  RemoteDB.Drivers.Base,
  RemoteDB.Drivers.FireDac,
  RemoteDB.Drivers.Interfaces,
  RemoteDB.Server.Module,
  Sparkle.HttpSys.Server,
  VCL.TMSLogging,
  Northwind.Config in '..\..\shared\Northwind.Config.pas';

function CreateDatabaseConnection: IDBConnection;
var
  Connection: TFDConnection;
begin
  Connection := TFDConnection.Create(nil);
  try
    Connection.LoginPrompt := False;
    Connection.DriverName := ReadSetting('Database', 'Driver', 'MSSQL');
    Connection.Params.Values['Server'] :=
      RequireEnvironmentVariable('NORTHWIND_SQL_SERVER');
    Connection.Params.Values['Database'] :=
      ReadSetting('Database', 'Database', 'Northwind');
    Connection.Params.Values['User_Name'] :=
      RequireEnvironmentVariable('NORTHWIND_SQL_USER');
    Connection.Params.Values['Password'] :=
      RequireEnvironmentVariable('NORTHWIND_SQL_PASSWORD');
    Result := TFireDacConnectionAdapter.Create(Connection, True);
    Connection := nil;
  finally
    Connection.Free;
  end;
end;

var
  Server: THttpSysServer;
  Module: TRemoteDBModule;
begin
  Server := nil;
  Module := nil;
  try
    Module := TRemoteDBModule.Create(
      ReadSetting('RemoteDB', 'ServerUri',
        'http://localhost:2001/tms/northwind/remotedb/'),
      TDBConnectionFactory.Create(
        function: IDBConnection
        begin
          Result := CreateDatabaseConnection;
        end));
    Module.UserName := RequireEnvironmentVariable('NORTHWIND_REMOTEDB_USER');
    Module.Password := RequireEnvironmentVariable('NORTHWIND_REMOTEDB_PASSWORD');

    Server := THttpSysServer.Create;
    Server.AddModule(Module);
    Module := nil;
    Server.Start;
    TMSLogger.Info('Northwind RemoteDB service started.');
    ReadLn;
  except
    on E: Exception do
    begin
      TMSLogger.Error(E.Message);
      ExitCode := 1;
    end;
  end;
  Server.Free;
  Module.Free;
end.
