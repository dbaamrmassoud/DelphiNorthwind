unit Identity.MainForm;

interface

uses
  System.Classes,
  Vcl.Forms,
  Aurelius.Comp.Connection,
  Aurelius.Comp.DBSchema,
  Sphinx.Comp.ClientApp,
  Sphinx.Comp.Config,
  Sphinx.Comp.Server,
  Sparkle.Comp.HttpSysDispatcher,
  XData.Comp.ConnectionPool;

type
  TIdentityMainForm = class(TForm)
  private
    FAureliusConnection: TAureliusConnection;
    FAureliusSchema: TAureliusDBSchema;
    FConnectionPool: TXDataConnectionPool;
    FDispatcher: TSparkleHttpSysDispatcher;
    FSphinxConfig: TSphinxConfig;
    FSphinxServer: TSphinxServer;
    procedure GetSigningData(Sender: TObject; Args: TGetSigningDataArgs);
    procedure InitializeIdentityDatabase;
    procedure RegisterDesktopClient;
  public
    constructor Create(AOwner: TComponent); override;
  end;

var
  IdentityMainForm: TIdentityMainForm;

implementation

uses
  Northwind.Config,
  System.IOUtils,
  System.SysUtils,
  VCL.TMSLogging;

constructor TIdentityMainForm.Create(AOwner: TComponent);
begin
  inherited CreateNew(AOwner);
  Caption := 'Northwind Identity';
  Width := 480;
  Height := 160;

  FDispatcher := TSparkleHttpSysDispatcher.Create(Self);
  FSphinxConfig := TSphinxConfig.Create(Self);
  FAureliusConnection := TAureliusConnection.Create(Self);
  FAureliusSchema := TAureliusDBSchema.Create(Self);
  FConnectionPool := TXDataConnectionPool.Create(Self);
  FSphinxServer := TSphinxServer.Create(Self);

  InitializeIdentityDatabase;
  RegisterDesktopClient;

  FSphinxConfig.OnGetSigningData := GetSigningData;
  FSphinxServer.BaseUrl := 'http://localhost:2003/tms/northwind/sphinx';
  FSphinxServer.Config := FSphinxConfig;
  FSphinxServer.Dispatcher := FDispatcher;
  FSphinxServer.Pool := FConnectionPool;
  FDispatcher.Active := True;
  TMSLogger.Info('Northwind Sphinx identity provider started.');
end;

procedure TIdentityMainForm.InitializeIdentityDatabase;
var
  DatabaseDirectory: string;
begin
  DatabaseDirectory := GetEnvironmentVariable('LOCALAPPDATA');
  if DatabaseDirectory = '' then
    raise Exception.Create('LOCALAPPDATA is not set.');
  DatabaseDirectory := TPath.Combine(DatabaseDirectory, 'DelphiNorthwind');
  if not ForceDirectories(DatabaseDirectory) then
    raise EFCreateError.CreateFmt(
      'Could not create the identity data directory: %s',
      [DatabaseDirectory]);

  FAureliusConnection.DriverName := 'SQLite';
  FAureliusConnection.Params.Values['Database'] :=
    TPath.Combine(DatabaseDirectory, 'NorthwindIdentity.sqlite');
  FAureliusConnection.Params.Values['EnableForeignKeys'] := 'True';

  FAureliusSchema.Connection := FAureliusConnection;
  FAureliusSchema.ModelNames.Add('Biz.Sphinx');
  FAureliusSchema.UpdateDatabase;

  FConnectionPool.Connection := FAureliusConnection;
end;

procedure TIdentityMainForm.RegisterDesktopClient;
var
  Client: TSphinxClientApp;
begin
  Client := FSphinxConfig.Clients.Add;
  Client.ClientId := 'northwind-desktop';
  Client.DisplayName := 'Northwind Desktop';
  Client.RedirectUris.Add('http://127.0.0.1');
  Client.RequireClientSecret := False;
  Client.AllowedGrantTypes := [
    TGrantType.gtAuthorizationCode,
    TGrantType.gtRefreshToken
  ];
  Client.ValidScopes.Add('openid');
  Client.ValidScopes.Add('email');
  Client.ValidScopes.Add('northwind-api');
  Client.ValidScopes.Add('offline_access');
  Client.RequirePkce := True;

  FSphinxConfig.LoginOptions.RequireConfirmedEmail := False;
end;

procedure TIdentityMainForm.GetSigningData(Sender: TObject;
  Args: TGetSigningDataArgs);
begin
  Args.Data.Key := TEncoding.UTF8.GetBytes(RequireJwtSecret);
end;

end.
