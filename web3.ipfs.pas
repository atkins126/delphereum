{******************************************************************************}
{                                                                              }
{                                  Delphereum                                  }
{                                                                              }
{             Copyright(c) 2019 Stefan van As <svanas@runbox.com>              }
{           Github Repository <https://github.com/svanas/delphereum>           }
{                                                                              }
{   Distributed under Creative Commons NonCommercial (aka CC BY-NC) license.   }
{                                                                              }
{******************************************************************************}

unit web3.ipfs;

{$I web3.inc}

interface

uses
  // Delphi
  System.Types,
  // web3
  web3,
  web3.http;

type
  TGateway = (
    Canonical,
    ProtocolLabs,
    Infura,
    Cloudflare);

type
  IFile = interface
    function Name: string;
    function Hash: string;
    function Size: UInt64;
    function Endpoint(Gateway: TGateway): string;
  end;

type
  TAsyncFile = reference to procedure(F: IFile; E: IError);

function add(const fileName: string; callback: TAsyncJsonObject): IAsyncResult; overload;
function add(const fileName: string; callback: TAsyncFile): IAsyncResult; overload;

function add(const apiHost, fileName: string; callback: TAsyncJsonObject): IAsyncResult; overload;
function add(const apiHost, fileName: string; callback: TAsyncFile): IAsyncResult; overload;

function pin(const hash: string; callback: TAsyncJsonObject): IAsyncResult; overload;
function pin(const apiHost, hash: string; callback: TAsyncJsonObject): IAsyncResult; overload;

function cat(const hash: string; callback: TAsyncResponse): IAsyncResult; overload;
function cat(const apiHost, hash: string; callback: TAsyncResponse): IAsyncResult; overload;

implementation

uses
  // Delphi
  System.JSON,
  System.NetEncoding,
  System.Net.Mime,
  System.Net.URLClient,
  // web3
  web3.json;

const
  IPFS_HOST: array[TGateway] of string = (
    'ipfs://',
    'https://gateway.ipfs.io/',
    'https://ipfs.infura.io/',
    'https://cloudflare-ipfs.com/');

{ TFile }

type
  TFile = class(TInterfacedObject, IFile)
  private
    FJsonObject: TJsonObject;
  public
    function Name: string;
    function Hash: string;
    function Size: UInt64;
    function Endpoint(Gateway: TGateway): string;
    constructor Create(aJsonObject: TJsonObject);
    destructor Destroy; override;
  end;

constructor TFile.Create(aJsonObject: TJsonObject);
begin
  inherited Create;
  FJsonObject := aJsonObject;
end;

destructor TFile.Destroy;
begin
  if Assigned(FJsonObject) then
    FJsonObject.Free;
  inherited Destroy;
end;

function TFile.Name: string;
begin
  Result := getPropAsStr(FJsonObject, 'Name');
end;

function TFile.Hash: string;
begin
  Result := getPropAsStr(FJsonObject, 'Hash');
end;

function TFile.Size: UInt64;
begin
  Result := getPropAsInt(FJsonObject, 'Size');
end;

function TFile.Endpoint(Gateway: TGateway): string;
begin
  Result := IPFS_HOST[Gateway] + 'ipfs/' + TNetEncoding.URL.Encode(Hash);
end;

{ global functions }

function add(const fileName: string; callback: TAsyncJsonObject): IAsyncResult;
begin
  Result := add('https://ipfs.infura.io:5001', fileName, callback);
end;

function add(const fileName: string; callback: TAsyncFile): IAsyncResult;
begin
  Result := add('https://ipfs.infura.io:5001', fileName, callback);
end;

function add(const apiHost, fileName: string; callback: TAsyncJsonObject): IAsyncResult;
var
  source: TMultipartFormData;
begin
  source := TMultipartFormData.Create;
  source.AddFile('file', fileName);
  web3.http.post(
    apiHost + '/api/v0/add',
    source,
    [TNetHeader.Create('Content-Type', source.MimeTypeHeader)],
    procedure(resp: TJsonObject; err: IError)
  begin
    try
      callback(resp, err);
    finally
      source.Free;
    end;
  end);
end;

function add(const apiHost, fileName: string; callback: TAsyncFile): IAsyncResult;
begin
  Result := add(apiHost, fileName, procedure(obj: TJsonObject; err: IError)
  begin
    if Assigned(err) then
    begin
      callback(nil, err);
      EXIT;
    end;
    callback(TFile.Create(obj.Clone as TJsonObject), nil);
  end);
end;

function pin(const hash: string; callback: TAsyncJsonObject): IAsyncResult;
begin
  Result := pin('https://ipfs.infura.io:5001', hash, callback);
end;

function pin(const apiHost, hash: string; callback: TAsyncJsonObject): IAsyncResult;
begin
  Result := web3.http.get(
    apiHost + '/api/v0/pin/add?arg=' + TNetEncoding.URL.Encode(hash),
    callback
  );
end;

function cat(const hash: string; callback: TAsyncResponse): IAsyncResult;
begin
  Result := cat('https://ipfs.infura.io:5001', hash, callback);
end;

function cat(const apiHost, hash: string; callback: TAsyncResponse): IAsyncResult;
begin
  Result := web3.http.get(
    apiHost + '/api/v0/cat?arg=' + TNetEncoding.URL.Encode(hash),
    callback
  );
end;

end.
