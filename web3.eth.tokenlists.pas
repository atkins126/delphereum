{******************************************************************************}
{                                                                              }
{                                  Delphereum                                  }
{                                                                              }
{             Copyright(c) 2022 Stefan van As <svanas@runbox.com>              }
{           Github Repository <https://github.com/svanas/delphereum>           }
{                                                                              }
{             Distributed under GNU AGPL v3.0 with Commons Clause              }
{                                                                              }
{   This program is free software: you can redistribute it and/or modify       }
{   it under the terms of the GNU Affero General Public License as published   }
{   by the Free Software Foundation, either version 3 of the License, or       }
{   (at your option) any later version.                                        }
{                                                                              }
{   This program is distributed in the hope that it will be useful,            }
{   but WITHOUT ANY WARRANTY; without even the implied warranty of             }
{   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the              }
{   GNU Affero General Public License for more details.                        }
{                                                                              }
{   You should have received a copy of the GNU Affero General Public License   }
{   along with this program.  If not, see <https://www.gnu.org/licenses/>      }
{                                                                              }
{******************************************************************************}

unit web3.eth.tokenlists;

{$I web3.inc}

interface

uses
  // Delphi
  System.JSON,
  System.SysUtils,
  System.Types,
  // Velthuis' BigNumbers
  Velthuis.BigIntegers,
  // web3
  web3,
  web3.eth.types;

type
  IToken = interface
    function ChainId: UInt32;
    function Address: TAddress;
    function Name: string;
    function Symbol: string;
    function Decimals: Integer;
    function Logo: TURL;
    procedure Balance(const client: IWeb3; const owner: TAddress; const callback: TProc<BigInteger, IError>);
  end;

  TTokens = TArray<IToken>;

  TTokensHelper = record helper for TTokens
    procedure Enumerate(const foreach: TProc<Integer, TProc>; const done: TProc);
    function IndexOf(const address: TAddress): Integer;
    function Length: Integer;
  end;

function count(const source: TURL; const callback: TProc<BigInteger, IError>): IAsyncResult; overload;
function count(const chain: TChain; const callback: TProc<BigInteger, IError>): IAsyncResult; overload;

function tokens(const source: TURL; const callback: TProc<TJsonArray, IError>): IAsyncResult; overload;
function tokens(const source: TURL; const callback: TProc<TTokens, IError>): IAsyncResult; overload;
function tokens(const chain: TChain; const callback: TProc<TTokens, IError>): IAsyncResult; overload;

function unsupported(const chain: TChain; const callback: TProc<TTokens, IError>): IAsyncResult;
function token(const chain: TChain; const token: TAddress; const callback: TProc<IToken, IError>): IAsyncResult;

implementation

uses
  // Delphi
  System.Generics.Collections,
  // web3
  web3.eth.erc20,
  web3.http,
  web3.json;

{----------------------------------- TToken -----------------------------------}

type
  TToken = class(TCustomDeserialized, IToken)
  private
    FChainId: UInt32;
    FAddress: TAddress;
    FName: string;
    FSymbol: string;
    FDecimals: Integer;
    FLogo: TURL;
  public
    function ChainId: UInt32;
    function Address: TAddress;
    function Name: string;
    function Symbol: string;
    function Decimals: Integer;
    function Logo: TURL;
    procedure Balance(const client: IWeb3; const owner: TAddress; const callback: TProc<BigInteger, IError>);
    constructor Create(const aJsonValue: TJsonValue); override;
  end;

constructor TToken.Create(const aJsonValue: TJsonValue);
begin
  inherited Create(aJsonValue);
  FChainId := getPropAsInt(aJsonValue, 'chainId');
  FAddress := TAddress.Create((function: string
  begin
    Result := getPropAsStr(aJsonValue, 'address');
    if Result = '' then Result := getPropAsStr(aJsonValue, 'contract');
  end)());
  FName := getPropAsStr(aJsonValue, 'name');
  FSymbol := getPropAsStr(aJsonValue, 'symbol');
  FDecimals := getPropAsInt(aJsonValue, 'decimals');
  FLogo := (function: string
  begin
    Result := getPropAsStr(aJsonValue, 'logoURI');
    if Result = '' then Result := getPropAsStr(aJsonValue, 'image');
  end)();
end;

function TToken.ChainId: UInt32;
begin
  Result := FChainId;
end;

function TToken.Address: TAddress;
begin
  Result := FAddress;
end;

function TToken.Name: string;
begin
  Result := FName;
end;

function TToken.Symbol: string;
begin
  Result := FSymbol;
end;

function TToken.Decimals: Integer;
begin
  Result := FDecimals;
end;

function TToken.Logo: TURL;
begin
  Result := FLogo;
end;

procedure TToken.Balance(const client: IWeb3; const owner: TAddress; const callback: TProc<BigInteger, IError>);
begin
  web3.eth.erc20.create(client, Self.Address).BalanceOf(owner, callback);
end;

{------------------------------- TTokensHelper --------------------------------}

procedure TTokensHelper.Enumerate(const foreach: TProc<Integer, TProc>; const done: TProc);
begin
  var next: TProc<TTokens, Integer>;

  next := procedure(tokens: TTokens; idx: Integer)
  begin
    if idx >= tokens.Length then
    begin
      if Assigned(done) then done;
      EXIT;
    end;
    foreach(idx, procedure
    begin
      next(tokens, idx + 1);
    end);
  end;

  if Self.Length = 0 then
  begin
    if Assigned(done) then done;
    EXIT;
  end;

  next(Self, 0);
end;

function TTokensHelper.IndexOf(const address: TAddress): Integer;
begin
  for Result := 0 to Self.Length - 1 do
    if Self[Result].Address.SameAs(address) then
      EXIT;
  Result := -1;
end;

function TTokensHelper.Length: Integer;
begin
  Result := System.Length(Self);
end;

{------------------------------ public functions ------------------------------}

function count(const source: TURL; const callback: TProc<BigInteger, IError>): IAsyncResult;
begin
  Result := tokens(source, procedure(arr: TJsonArray; err: IError)
  begin
    if Assigned(err) then
      callback(0, err)
    else if not Assigned(arr) then
      callback(0, nil)
    else
      callback(arr.Count, nil);
  end);
end;

function count(const chain: TChain; const callback: TProc<BigInteger, IError>): IAsyncResult;
begin
  Result := tokens(chain, procedure(tokens: TTokens; err: IError)
  begin
    callback(tokens.Length, nil);
  end);
end;

function tokens(const source: TURL; const callback: TProc<TJsonArray, IError>): IAsyncResult;
begin
  Result := web3.http.get(source, [], procedure(response: TJsonValue; err: IError)
  begin
    const result = (function: TJsonArray
    begin
      Result := getPropAsArr(response, 'tokens');
      if (Result = nil) and (response is TJsonArray) then Result := response as TJsonArray;
    end)();
    callback(result, err);
  end);
end;

function tokens(const source: TURL; const callback: TProc<TTokens, IError>): IAsyncResult;
begin
  Result := tokens(source, procedure(arr: TJsonArray; err: IError)
  begin
    if Assigned(err) or not Assigned(arr) then
    begin
      callback(nil, err);
      EXIT;
    end;
    const result = (function: TTokens
    begin
      SetLength(Result, arr.Count);
      for var I := 0 to Pred(arr.Count) do
        Result[I] := TToken.Create(arr[I] as TJsonObject);
    end)();
    callback(result, nil);
  end);
end;

function tokens(const chain: TChain; const callback: TProc<TTokens, IError>): IAsyncResult;
begin
  // step #1: get the (multi-chain) Uniswap list
  Result := tokens('https://tokens.uniswap.org', procedure(tokens1: TTokens; err1: IError)
  begin
    if Assigned(err1) or not Assigned(tokens1) then
    begin
      callback(nil, err1);
      EXIT;
    end;
    var result: TTokens;
    for var token1 in tokens1 do
      if token1.ChainId = chain.Id then
        result := result + [token1];
    // step #2: add tokens from a chain-specific token list (if any)
    if chain.Tokens = '' then
    begin
      callback(result, nil);
      EXIT;
    end;
    tokens(chain.Tokens, procedure(tokens2: TTokens; err2: IError)
    begin
      if Assigned(err2) or not Assigned(tokens2) then
      begin
        callback(result, err2);
        EXIT;
      end;
      for var token2 in tokens2 do
        if ((token2.ChainId = chain.Id) or (token2.ChainId = 0)) and (result.IndexOf(token2.Address) = -1) then
          result := result + [token2];
      callback(result, nil);
    end);
  end);
end;

function unsupported(const chain: TChain; const callback: TProc<TTokens, IError>): IAsyncResult;
begin
  Result := tokens('https://unsupportedtokens.uniswap.org', procedure(tokens: TTokens; err: IError)
  begin
    if Assigned(err) or not Assigned(tokens) then
      callback(nil, err)
    else
      callback((function: TTokens
      begin
        Result := [];
        for var token in tokens do if token.ChainId = chain.Id then result := result + [token];
      end)(), nil);
  end);
end;

function token(const chain: TChain; const token: TAddress; const callback: TProc<IToken, IError>): IAsyncResult;
begin
  Result := tokens(chain, procedure(tokens: TTokens; err: IError)
  begin
    if Assigned(err) then
    begin
      callback(nil, err);
      EXIT;
    end;
    const I = tokens.IndexOf(token);
    if I = -1 then
      callback(nil, nil)
    else
      callback(tokens[I], nil);
  end);
end;

end.
