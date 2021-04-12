{******************************************************************************}
{                                                                              }
{                                  Delphereum                                  }
{                                                                              }
{             Copyright(c) 2018 Stefan van As <svanas@runbox.com>              }
{           Github Repository <https://github.com/svanas/delphereum>           }
{                                                                              }
{   Distributed under Creative Commons NonCommercial (aka CC BY-NC) license.   }
{                                                                              }
{******************************************************************************}

unit web3.json.rpc.https;

{$I web3.inc}

interface

uses
  // Delphi
  System.JSON,
  // web3
  web3,
  web3.http.throttler,
  web3.json.rpc;

type
  TJsonRpcHttps = class(TCustomJsonRpc)
  strict private
    FThrottler: IThrottler;
  public
    function Send(
      const URL   : string;
      security    : TSecurity;
      const method: string;
      args        : array of const): TJsonObject; overload; override;
    procedure Send(
      const URL   : string;
      security    : TSecurity;
      const method: string;
      args        : array of const;
      callback    : TAsyncJsonObject); overload; override;
    constructor Create; overload;
    constructor Create(const throttler: IThrottler); overload;
  end;

implementation

uses
  // Delphi
  System.Classes,
  System.Net.URLClient,
  // web3
  web3.http,
  web3.json;

{ TJsonRpcHttps }

constructor TJsonRpcHttps.Create;
begin
  inherited Create;
end;

constructor TJsonRpcHttps.Create(const throttler: IThrottler);
begin
  inherited Create;
  FThrottler := throttler;
end;

function TJsonRpcHttps.Send(
  const URL   : string;
  security    : TSecurity;
  const method: string;
  args        : array of const): TJsonObject;
var
  source: TStream;
  resp  : TJsonValue;
  error : TJsonObject;
begin
  Result := nil;
  source := TStringStream.Create(GetPayload(method, args));
  try
    web3.http.post(
      URL,
      source,
      [TNetHeader.Create('Content-Type', 'application/json')],
      resp
    );
    if Assigned(resp) then
    try
      // did we receive an error? then translate that into an exception
      error := web3.json.getPropAsObj(resp, 'error');
      if Assigned(error) then
        raise EJsonRpc.Create(
          web3.json.getPropAsInt(error, 'code'),
          web3.json.getPropAsStr(error, 'message')
        );
      Result := resp.Clone as TJsonObject;
    finally
      resp.Free;
    end;
  finally
    source.Free;
  end;
end;

procedure TJsonRpcHttps.Send(
  const URL   : string;
  security    : TSecurity;
  const method: string;
  args        : array of const;
  callback    : TAsyncJsonObject);
var
  handler: TAsyncJsonObject;
  payload: string;
  headers: TNetHeaders;
  source : TStream;
begin
  handler := procedure(resp: TJsonObject; err: IError)
  var
    error: TJsonObject;
  begin
    if Assigned(err) then
    begin
      callback(nil, err);
      EXIT;
    end;
    // did we receive an error?
    error := web3.json.getPropAsObj(resp, 'error');
    if Assigned(error) then
      callback(resp, TJsonRpcError.Create(
        web3.json.getPropAsInt(error, 'code'),
        web3.json.getPropAsStr(error, 'message')
      ))
    else
      // if we reached this far, then we have a valid response object
      callback(resp, nil);
  end;

  payload := GetPayload(method, args);
  headers := [TNetHeader.Create('Content-Type', 'application/json')];

  if Assigned(FThrottler) then
  begin
    FThrottler.Post(TPost.Create(URL, payload, headers, handler));
    EXIT;
  end;

  source := TStringStream.Create(payload);
  web3.http.post(URL, source, headers, procedure(resp: TJsonObject; err: IError)
  begin
    try
      handler(resp, err);
    finally
      source.Free;
    end;
  end);
end;

end.
