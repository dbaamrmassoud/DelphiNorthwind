program NorthwindApi;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  System.Classes,
  System.SyncObjs,
  Aurelius.Drivers.Base,
  Aurelius.Drivers.Interfaces,
  Aurelius.Drivers.RemoteDB,
  Aurelius.Mapping.Explorer,
  Echo.Entities,
  Echo.Listeners,
  Echo.Main,
  Echo.Server,
  RemoteDB.Client.Database,
  Sparkle.HttpSys.Server,
  Sparkle.Middleware.Jwt,
  VCL.TMSLogging,
  XData.Aurelius.ConnectionPool,
  XData.Server.Module,
  Northwind.Config in '..\..\shared\Northwind.Config.pas',
  Northwind.Entities in '..\..\shared\Northwind.Entities.pas',
  Northwind.OrderService in 'Northwind.OrderService.pas';

type
  TEchoRouterThread = class(TThread)
  private
    FConnectionPool: IDBConnectionPool;
    FStopEvent: TEvent;
  protected
    procedure Execute; override;
  public
    constructor Create(const ConnectionPool: IDBConnectionPool);
    destructor Destroy; override;
    procedure Stop;
  end;

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

constructor TEchoRouterThread.Create(const ConnectionPool: IDBConnectionPool);
begin
  inherited Create(True);
  FreeOnTerminate := False;
  FConnectionPool := ConnectionPool;
  FStopEvent := TEvent.Create(nil, True, False, '');
  Start;
end;

destructor TEchoRouterThread.Destroy;
begin
  Stop;
  FStopEvent.Free;
  inherited;
end;

procedure TEchoRouterThread.Stop;
begin
  FStopEvent.SetEvent;
  WaitFor;
end;

procedure TEchoRouterThread.Execute;
var
  Echo: TEcho;
begin
  while FStopEvent.WaitFor(30000) = wrTimeout do
  begin
    Echo := nil;
    try
      Echo := TEcho.Create(FConnectionPool);
      Echo.Route;
    except
      on E: Exception do
        TMSLogger.Error('Echo routing failed: ' + E.Message);
    end;
    Echo.Free;
  end;
end;

var
  ConnectionFactory: IDBConnectionFactory;
  ConnectionPool: IDBConnectionPool;
  EchoSubscriber: TEchoEventSubscriber;
  EchoModule: TEchoServerModule;
  EchoJwtMiddleware: TJwtMiddleware;
  HttpServer: THttpSysServer;
  JwtMiddleware: TJwtMiddleware;
  RouterThread: TEchoRouterThread;
  XDataModule: TXDataServerModule;
begin
  ConnectionFactory := nil;
  ConnectionPool := nil;
  EchoSubscriber := nil;
  EchoModule := nil;
  EchoJwtMiddleware := nil;
  HttpServer := nil;
  JwtMiddleware := nil;
  RouterThread := nil;
  XDataModule := nil;
  try
    ConnectionFactory := TDBConnectionFactory.Create(
      function: IDBConnection
      begin
        Result := CreateRemoteDatabaseConnection;
      end);
    ConnectionPool := TDBConnectionPool.Create(32, ConnectionFactory);

    EchoSubscriber := TEchoEventSubscriber.Create;
    EchoSubscriber.SubscribeListeners(TMappingExplorer.Default);

    XDataModule := TXDataServerModule.Create(
      ReadSetting('Api', 'BaseUrl',
        'http://localhost:2002/tms/northwind/xdata'),
      ConnectionPool);
    JwtMiddleware := TJwtMiddleware.Create(RequireJwtSecret);
    JwtMiddleware.ForbidAnonymousAccess := True;
    XDataModule.AddMiddleware(JwtMiddleware);
    JwtMiddleware := nil;

    EchoModule := TEchoServerModule.Create(
      ReadSetting('Api', 'EchoBaseUrl',
        'http://localhost:2002/tms/northwind/echo'), ConnectionPool);
    EchoJwtMiddleware := TJwtMiddleware.Create(RequireJwtSecret);
    EchoJwtMiddleware.ForbidAnonymousAccess := True;
    EchoModule.AddMiddleware(EchoJwtMiddleware);
    EchoJwtMiddleware := nil;
    HttpServer := THttpSysServer.Create;
    HttpServer.AddModule(XDataModule);
    XDataModule := nil;
    HttpServer.AddModule(EchoModule);
    EchoModule := nil;
    HttpServer.Start;
    RouterThread := TEchoRouterThread.Create(ConnectionPool);
    TMSLogger.Info('Northwind XData and Echo services started.');
    ReadLn;
  except
    on E: Exception do
    begin
      TMSLogger.Error(E.Message);
      ExitCode := 1;
    end;
  end;

  RouterThread.Free;
  HttpServer.Free;
  EchoModule.Free;
  EchoJwtMiddleware.Free;
  XDataModule.Free;
  JwtMiddleware.Free;
  EchoSubscriber.Free;
  ConnectionPool := nil;
  ConnectionFactory := nil;
end.
