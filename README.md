# Delphi Northwind Sales Sample

A Delphi 10.3 Rio sample sales-management application built around the SQL Server Northwind database. The intended topology is a DevExpress VCL desktop client, a Sphinx identity provider, an XData API, and a private RemoteDB database gateway. TMS Aurelius is the sole domain-persistence layer; RemoteDB forwards Aurelius SQL to SQL Server through FireDAC. The client does not connect directly to SQL Server or execute domain SQL.

## Repository status

This repository began empty. The source and project structure are being established here; build artifacts, local credentials, database files, and vendor binaries are deliberately excluded.

## Components and responsibilities

| Component | Responsibility |
| --- | --- |
| Delphi 10.3 Rio / VCL | Windows desktop application and server executables |
| DevExpress VCL 25.1 | Desktop navigation, data grids, and editing workflows |
| TMS XData + Sparkle | REST/JSON API and HTTP transport |
| TMS Sphinx | OAuth 2 / OpenID Connect identity provider and desktop login |
| TMS Aurelius | Entity mappings and domain persistence |
| TMS RemoteDB | Private SQL transport between the API and database gateway |
| FireDAC | SQL Server driver, used only by the RemoteDB service |
| TMS Echo | Aurelius change capture and authenticated replication endpoint for replica nodes |
| TMS Logging | Application and service diagnostics |
| FastReport | Product catalog preview using data delivered by the API |

TMS VCL Security is not used. Echo is for synchronization, not background job scheduling: it is an optional replica channel and does not create a second client-to-database CRUD path.

## Prerequisites

- Delphi 10.3 Rio with the Win32 VCL toolchain.
- DevExpress VCL 25.1, FastReport, and compatible Delphi 10.3 builds of the required TMS products, installed and licensed locally.
- SQL Server containing the official Northwind sample schema and data.
- SQL Server FireDAC driver availability on the RemoteDB host.

The Delphi compiler is present in the current development environment. The proprietary DevExpress, FastReport, and TMS package installations have not been found there, so a full Delphi compile/runtime test is not currently available. No vendor binaries or license material are included.

## Database setup

Use Microsoft's published SQL Server Northwind sample script: [instnwnd.sql](https://github.com/microsoft/sql-server-samples/blob/master/samples/databases/northwind-pubs/instnwnd.sql). Create a disposable `Northwind` database first and run the script there. **The upstream script drops and recreates Northwind objects; never run it against a database containing user data.**

Run `database/verify_northwind.sql` in the target database before starting the sample. It is read-only and returns missing required table/column pairs. The application maps the verified `dbo.Customers`, `dbo.Orders`, `dbo.[Order Details]`, and `dbo.Products` tables; it does not create or modify the Northwind schema.

## Configuration and security

Copy `config/Northwind.ini.example` to `Northwind.ini` for non-secret local endpoints. Do not commit the local copy. Passwords and signing keys must be supplied from the host's protected environment/secret store; never put them in source control or distributable configuration.

Set these environment variables before launching the services:

- `NORTHWIND_SQL_SERVER`, `NORTHWIND_SQL_USER`, and `NORTHWIND_SQL_PASSWORD` for the SQL Server connection used only by RemoteDB.
- `NORTHWIND_REMOTEDB_USER` and `NORTHWIND_REMOTEDB_PASSWORD` for RemoteDB Basic authentication. Choose non-default credentials.
- `NORTHWIND_JWT_SECRET` for the shared HMAC signing key; use the same random value in Sphinx and the XData resource server, with at least 32 UTF-8 bytes.

The RemoteDB endpoint is a database-level SQL gateway, not a public API. Keep it bound to a private interface or restrict it by network policy, use HTTPS outside a trusted local development machine, and replace all RemoteDB sample credentials. The XData API accepts access tokens issued by Sphinx and rejects anonymous requests. This sample does not define role-based authorization or production token-audience policy; add both before deploying beyond local development. The desktop client is registered as a public native OAuth client using authorization code with PKCE; no client secret is embedded in the VCL executable.

The identity sample stores its Sphinx users in a local SQLite file under `%LOCALAPPDATA%\DelphiNorthwind`. Self-registration without e-mail confirmation is enabled for local demonstration only. Configure a real e-mail confirmation flow and restore the confirmation requirement before any non-local deployment. The sample binds local HTTP.sys listeners; reserve the configured URLs for the Windows account running each service, and do not expose the HTTP endpoints beyond a trusted development host.

Local defaults use port `2001` for RemoteDB, `2002` for XData/Echo, and `2003` for Sphinx.

## Build and run

Install the required vendor packages into Delphi 10.3 Rio, then open and build these source projects in the IDE, with the corresponding TMS/DevExpress/FastReport packages available on the unit search path:

- `src/server/identity/Northwind.Identity.dpr`
- `src/server/remotedb/Northwind.RemoteDB.dpr`
- `src/server/api/Northwind.Api.dpr`
- `src/server/api/Northwind.EchoSetup.dpr`
- `src/client/Northwind.Desktop.dpr`

Run `Northwind.RemoteDB` first, then `Northwind.EchoSetup` once against the disposable Northwind database. The setup utility adds only TMS Echo's own metadata tables and registers the central node; it does not create or change the Northwind sales tables. Start the identity and API services next, then launch the VCL client and sign in through Sphinx. The client supports customer creation, transactional order creation with one product line, customer/product/order/order-line browsing, and a FastReport product catalog preview.

The API subscribes Aurelius changes to Echo, routes changes periodically, and exposes Echo's authenticated XData synchronization module at `/tms/northwind/echo`. The Echo module is for replica synchronization, not a second SQL client path. This desktop client does not yet host an offline replica; using Echo from a replica additionally requires an Echo-compatible local database, Echo's local metadata schema, node registration, and an initial data load, configured with the installed Echo release.

The exact project build and run steps depend on the installed vendor package versions and SQL Server connection policy. After those local prerequisites are present, the project can be compiled and the endpoint workflows exercised against a disposable Northwind database.

## AlphaERP Windows service and monitor

The repository also includes an independent Win32 Windows Service host and VCL tray monitor:

| Project / unit | Purpose |
| --- | --- |
| `src/server/alphaerp/AlphaERP.Service.dpr` | Native Delphi service executable and management command entry point |
| `src/server/alphaerp/AlphaERP.ServiceHost.pas` | XData/HTTP.sys lifecycle, Aurelius connection pool, and database health checks |
| `src/server/alphaerp/AlphaERP.ServiceModule.pas` | Windows Service Control Manager lifecycle wrapper |
| `src/server/alphaerp/AlphaERP.Health.Service.pas` | Local-only XData health service |
| `src/client/alphaerp-monitor/AlphaERP.Monitor.dpr` | Separate interactive VCL monitoring application |
| `src/shared/AlphaERP.Config.pas` | Validated external INI configuration and secret lookup |
| `src/shared/AlphaERP.Logging.pas` | Timestamped, leveled file logging with bounded size rotation |
| `src/shared/AlphaERP.Status.pas` | Thread-safe service, API, and database status snapshot |
| `src/shared/AlphaERP.ServiceControl.pas` | SCM query/start/stop/restart operations |
| `config/AlphaERP.ini.example` | Documented non-secret service configuration |

The service reuses this repository's current Northwind Aurelius entities and `CreateOrder` XData operation; it does not define an AlphaERP-specific database schema or business model. The REST API is mounted at the configured `ApiBaseUrl` and requires the same HMAC JWT key used by the token issuer. The separate health module has no bearer-token requirement, but its URL is validated to bind to a loopback host only. It reports service/API state, process start information, recent database connectivity, and diagnostic errors. The tray monitor queries the Windows SCM for state and PID, polls this local health interface on a worker thread, and offers dashboard, service control, log/config opening, and Explorer-restart tray-icon recovery.

### Configure and install

1. Build `AlphaERP.Service.dpr` and `AlphaERP.Monitor.dpr` in Delphi 10.3 Rio / Win32 with the installed TMS XData, Aurelius, Sparkle, TMS Logging, and FireDAC SQL Server packages. The repository uses `.dpr` source projects (as the existing applications do); Delphi can create local IDE project metadata when opened.
2. Copy `config/AlphaERP.ini.example` to `AlphaERP.ini` beside each executable, or set `ALPHAERP_CONFIG_FILE` to the same absolute configuration path for the service and monitor.
3. Set `ALPHAERP_SQL_USER`, `ALPHAERP_SQL_PASSWORD`, and `NORTHWIND_JWT_SECRET` in the service account's protected environment/secret store. The JWT secret must contain at least 32 UTF-8 bytes and must match the issuer. Do not put secrets in the INI file.
4. Grant the service account permission to the log directory and HTTP.sys URL reservations for the configured API and health prefixes. For a non-loopback API URL, use HTTPS, provision the HTTP.sys certificate binding separately, and restrict the endpoint at the network firewall. `TlsCertificateThumbprint` is retained for operator documentation; the certificate itself is bound by Windows HTTP.sys, not loaded from the INI.
5. From an elevated command prompt, install and manage the service with `AlphaERP.Service.exe /install`, `/uninstall`, `/start`, `/stop`, `/restart`, or `/status`. `/install` uses the configured `StartMode`; the service executable handles the remaining management commands. Run `AlphaERP.Monitor.exe` in the interactive user session; do not run the VCL monitor inside the service process.

The sample binds API HTTP only to `localhost` and health HTTP only to `127.0.0.1`; change neither to a public host without HTTPS and corresponding HTTP.sys/network configuration. The API uses the existing `TJwtMiddleware` convention and denies anonymous access. The health response is intentionally minimal and loopback-only; do not publish it through a reverse proxy.

The Delphi 10.3 compiler is available in the development environment, but the proprietary TMS XData/Aurelius/Sparkle/Logging packages are not installed there. Consequently the service and monitor projects cannot be fully compiled or exercised in this checkout. Their XData server construction, Aurelius FireDAC adapter, and service APIs follow the existing repository examples and Delphi VCL service conventions and must be verified against the exact local vendor package builds. In particular, request-level logging hooks and XData/Sparkle HTTP request timeout configuration are version-specific and are not guessed; the implementation logs host lifecycle, configuration/startup failures, and database health transitions. The configured timeout bounds service-control restart waits, not individual REST requests.
