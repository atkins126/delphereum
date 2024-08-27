{******************************************************************************}
{                                                                              }
{                                  Delphereum                                  }
{                                                                              }
{             Copyright(c) 2018 Stefan van As <svanas@runbox.com>              }
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

unit web3.json;

{$I web3.inc}

interface

uses
  // Delphi
  System.JSON,
  System.SysUtils,
  // Velthuis' BigNumbers
  Velthuis.BigIntegers,
  // web3
  web3;

type
  TCustomDeserialized = class abstract(TInterfacedObject)
  public
    constructor Create(const aJsonValue: TJsonValue); virtual;
  end;

  TDeserialized = class abstract(TCustomDeserialized)
  protected
    FJsonValue: TJsonValue;
  public
    constructor Create(const aJsonValue: TJsonValue); override;
    destructor Destroy; override;
    function ToString: string; override;
  end;

  IDeserializedArray<T: IInterface> = interface
    function Count: Integer;
    procedure Delete(const Index: Integer);
    function Item(const Index: Integer): T;
    function ToString: string;
  end;

  TDeserializedArray<T: IInterface> = class abstract(TDeserialized, IDeserializedArray<T>)
  public
    function Count: Integer;
    procedure Delete(const Index: Integer);
    function Item(const Index: Integer): T; virtual; abstract;
  end;

function marshal(const value: TJsonValue): string;
function unmarshal(const value: string): TJsonValue;

function getPropAsStr(const obj: TJsonValue; const name: string; const def: string = ''): string;
function getPropAsInt(const obj: TJsonValue; const name: string; const def: Integer = 0): Integer;
function getPropAsUInt64(const obj: TJsonValue; const name: string; const def: UInt64 = 0): UInt64;
function getPropAsDouble(const obj: TJsonValue; const name: string; const def: Double = 0): Double;
function getPropAsBigInt(const obj: TJsonValue; const name: string): BigInteger; overload;
function getPropAsBigInt(const obj: TJsonValue; const name: string; const def: BigInteger): BigInteger; overload;
function getPropAsObj(const obj: TJsonValue; const name: string): TJsonObject;
function getPropAsArr(const obj: TJsonValue; const name: string): TJsonArray;
function getPropAsBool(const obj: TJsonValue; const name: string; const def: Boolean = False): Boolean;

function quoteString(const S: string; const Quote: Char = '"'): string;

implementation

{---------------------------- TCustomDeserialized -----------------------------}

constructor TCustomDeserialized.Create(const aJsonValue: TJsonValue);
begin
  inherited Create;
end;

{------------------------------- TDeserialized --------------------------------}

constructor TDeserialized.Create(const aJsonValue: TJsonValue);
begin
  inherited Create(aJsonValue);
  if Assigned(aJsonValue) then
    FJsonValue := aJsonValue.Clone as TJsonValue
  else
    FJsonValue := nil;
end;

destructor TDeserialized.Destroy;
begin
  if Assigned(FJsonValue) then FJsonValue.Free;
  inherited Destroy;
end;

function TDeserialized.ToString: string;
begin
  Result := web3.json.marshal(Self.FJsonValue);
end;

{--------------------------- TDeserializedArray<T> ----------------------------}

function TDeserializedArray<T>.Count: Integer;
begin
  if Assigned(Self.FJsonValue) and (Self.FJsonValue is TJsonArray) then
    Result := TJsonArray(Self.FJsonValue).Count
  else
    Result := 0;
end;

procedure TDeserializedArray<T>.Delete(const Index: Integer);
begin
  if not Assigned(Self.FJsonValue) then
    EXIT;
  if not(Self.FJsonValue is TJsonArray) then
    EXIT;
  TJsonArray(Self.FJsonValue).Remove(Index);
end;

{------------------------------ global functions ------------------------------}

function marshal(const value: TJsonValue): string;
begin
  Result := '';

  if not Assigned(value) then
    EXIT;

  var I := value.EstimatedByteSize;
  if I <= 0 then
    EXIT;

  var B: TBytes;
  SetLength(B, I);

  I := value.ToBytes(B, 0);
  if I <= 0 then
    SetLength(B, 0)
  else
    SetLength(B, I);

  Result := TEncoding.UTF8.GetString(B);
end;

function unmarshal(const value: string): TJsonValue;
begin
  Result := TJsonObject.ParseJsonValue(value.Trim);
end;

function getPropAsStr(const obj: TJsonValue; const name: string; const def: string): string;
begin
  Result := def;
  if not Assigned(obj) then
    EXIT;
  if not(obj is TJsonObject) then
    EXIT;
  const P = TJsonObject(obj).Get(name);
  if Assigned(P) then
    if Assigned(P.JsonValue) then
    begin
      if P.JsonValue is TJsonString then
        Result := TJsonString(P.JsonValue).Value
      else
        Result := P.JsonValue.ToString;
      if SameText(Result, 'null') or SameText(Result, 'undefined') then
        Result := def;
    end;
end;

function getPropAsInt(const obj: TJsonValue; const name: string; const def: Integer): Integer;
begin
  Result := def;
  if not Assigned(obj) then
    EXIT;
  if not(obj is TJsonObject) then
    EXIT;
  const P = TJsonObject(obj).Get(name);
  if Assigned(P) then
    if Assigned(P.JsonValue) then
      if P.JsonValue is TJsonNumber then
        Result := TJsonNumber(P.JsonValue).AsInt
      else
        if P.JsonValue is TJsonString then
          Result := StrToIntDef(TJsonString(P.JsonValue).Value, def)
        else
          Result := def;
end;

function getPropAsUInt64(const obj: TJsonValue; const name: string; const def: UInt64): UInt64;
begin
  Result := def;
  if not Assigned(obj) then
    EXIT;
  if not(obj is TJsonObject) then
    EXIT;
  const P = TJsonObject(obj).Get(name);
  if Assigned(P) and Assigned(P.JsonValue) then
    if P.JsonValue is TJsonNumber then
      {$IF CompilerVersion < 35}
      Result := StrToUInt64Def(P.JsonValue.Value, def)
      {$ELSE}
      Result := TJsonNumber(P.JsonValue).AsUInt64
      {$IFEND}
    else if P.JsonValue is TJsonString then
      Result := StrToUInt64Def(TJsonString(P.JsonValue).Value, def);
end;

function getPropAsDouble(const obj: TJsonValue; const name: string; const def: Double): Double;
begin
  Result := def;
  if not Assigned(obj) then
    EXIT;
  if not(obj is TJsonObject) then
    EXIT;
  const P = TJsonObject(obj).Get(name);
  if Assigned(P) then
    if Assigned(P.JsonValue) then
      if P.JsonValue is TJsonNumber then
        Result := TJsonNumber(P.JsonValue).AsDouble
      else
        if P.JsonValue is TJsonString then
        begin
          var FS := TFormatSettings.Create;
          FS.DecimalSeparator := '.';
          Result := StrToFloat(TJsonString(P.JsonValue).Value, FS);
        end;
end;

function getPropAsBigInt(const obj: TJsonValue; const name: string): BigInteger;
begin
  Result := getPropAsBigInt(obj, name, BigInteger.Zero);
end;

function getPropAsBigInt(const obj: TJsonValue; const name: string; const def: BigInteger): BigInteger;
begin
  Result := def;
  if not Assigned(obj) then
    EXIT;
  if not(obj is TJsonObject) then
    EXIT;
  const P = TJsonObject(obj).Get(name);
  if Assigned(P) then
    if Assigned(P.JsonValue) then
      if P.JsonValue is TJsonNumber then
        Result := TJsonNumber(P.JsonValue).AsInt64
      else
        if P.JsonValue is TJsonString then
          Result := BigInteger.Create(TJsonString(P.JsonValue).Value)
        else
          Result := def;
end;

function getPropAsObj(const obj: TJsonValue; const name: string): TJsonObject;
begin
  Result := nil;
  if not Assigned(obj) then
    EXIT;
  if not(obj is TJsonObject) then
    EXIT;
  const P = TJsonObject(obj).Get(name);
  if Assigned(P) then
    if Assigned(P.JsonValue) then
      if P.JsonValue is TJsonObject then
        Result := TJsonObject(P.JsonValue);
end;

function getPropAsArr(const obj: TJsonValue; const name: string): TJsonArray;
begin
  Result := nil;
  if not Assigned(obj) then
    EXIT;
  if not(obj is TJsonObject) then
    EXIT;
  const P = TJsonObject(obj).Get(name);
  if Assigned(P) then
    if Assigned(P.JsonValue) then
      if P.JsonValue is TJsonArray then
        Result := TJsonArray(P.JsonValue);
end;

function getPropAsBool(const obj: TJsonValue; const name: string; const def: Boolean): Boolean;
begin
  Result := def;
  if not Assigned(obj) then
    EXIT;
  if not(obj is TJsonObject) then
    EXIT;
  const P = TJsonObject(obj).Get(name);
  if Assigned(P) then
    if Assigned(P.JsonValue) then
      if P.JsonValue is TJsonTrue then
        Result := True
      else
        if P.JsonValue is TJsonFalse then
          Result := False
        else
          if P.JsonValue is TJsonString then
            Result := SameText(TJsonString(P.JsonValue).Value, '1')
                   or SameText(TJsonString(P.JsonValue).Value, 'yes')
                   or SameText(TJsonString(P.JsonValue).Value, 'true');
end;

function quoteString(const S: string; const Quote: Char): string;
begin
  Result := S;
  if Length(Result) > 0 then
  begin
    var I: Integer;
    // add extra backslash is there is a backslash, for example: c:\ --> c:\\
    I := System.Low(Result);
    while I <= Length(Result) do
      if Result[I] = '\' then
      begin
        Result := Copy(Result, 1, I) + '\' + Copy(Result, I + 1, Length(Result));
        I := I + 2;
      end
      else
        Inc(I);
    // add backslash if there is a double quote, for example: "a" --> \"a\"
    I := System.Low(Result);
    while I <= Length(Result) do
      if Result[I] = Quote then
      begin
          Result := Copy(Result, 1, I - 1) + '\' + Copy(Result, I, Length(Result));
          I := I + 2;
      end
      else
        Inc(I);
  end;
  Result := Quote + Result + Quote;
end;

end.
