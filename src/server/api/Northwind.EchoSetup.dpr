program NorthwindEchoSetup;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  Aurelius.Drivers.Base,
  Aurelius.Drivers.Interfaces,
  Aurelius.Drivers.RemoteDB,
  Aurelius.Engine.DatabaseManager,
  Echo.Main,
  Echo.NodeManager,
  RemoteDB.Client.Database,
  VCL.TMSLogging,
  Northwind.Config in '..\..\shared\Northwind.Config.pas';

function CreateRemoteDatabaseConnection: IDBConnection;
var
  Database: TRemoteDBDatabase;
begin
  Database := TRemoteDBDatabase.Create(nil);
  try
    Database.ServerUri := ReadSetting('RemoteDB', 'ServerUri',
      'http://localhost:2001/tms/northwind/remotedb/');
    Database.UserName := RequireEnvironmentVariable('NORTHWIND_REMOTEDB_USER');
    Database.Password := RequireEnvironmentVariable('NORTHWIND_REMOTEDB_PASSWORD');
    Result := TRemoteDBConnectionAdapter.Create(Database, True);
    Database := nil;
  finally
    Database.Free;
  end;
end;

var
  Connection: IDBConnection;
  DatabaseManager: TDatabaseManager;
  Echo: TEcho;
  NodeManager: IEchoNodeManager;
begin
  Connection := nil;
  DatabaseManager := nil;
  Echo := nil;
  NodeManager := nil;
  try
    Connection := CreateRemoteDatabaseConnection;
    DatabaseManager := TDatabaseManager.Create(Connection, TEcho.Explorer);
    DatabaseManager.UpdateDatabase;

    Echo := TEcho.Create(
      TDBConnectionFactory.Create(
        function: IDBConnection
        begin
          Result := CreateRemoteDatabaseConnection;
        end));
    NodeManager := Echo.GetNodeManager;
    if NodeManager.SelfNode = nil then
    begin
      NodeManager.CreateNode('northwind-server');
      NodeManager.DefineSelfNode('northwind-server');
    end;

    TMSLogger.Info('Northwind Echo schema and server node are ready.');
  except
    on E: Exception do
    begin
      TMSLogger.Error(E.Message);
      ExitCode := 1;
    end;
  end;
  NodeManager := nil;
  Echo.Free;
  DatabaseManager.Free;
  Connection := nil;
end.
