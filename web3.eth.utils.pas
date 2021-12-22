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

unit web3.eth.utils;

{$I web3.inc}

interface

uses
  // Delphi
  System.SysUtils,
  // Velthuis' BigNumbers
  Velthuis.BigIntegers,
  // web3
  web3,
  web3.eth.types;

type
  TEthUnit = (
    noether,
    wei,
    kwei,
    babbage,
    femtoether,
    mwei,
    lovelace,
    picoether,
    gwei,
    shannon,
    nanoether,
    nano,
    szabo,
    microether,
    micro,
    finney,
    milliether,
    milli,
    ether,
    kether,
    grand,
    mether,
    gether,
    tether
  );

function fromWei(wei: TWei; &to: TEthUnit; decimals: Byte = 18): string;
function toWei(input: string; &unit: TEthUnit): TWei;

function EthToFloat(const value: string): Double;
function FloatToEth(value: Double): string;

implementation

const
  UnitToWei: array[TEthUnit] of string = (
    '0',
    '1',
    '1000',
    '1000',
    '1000',
    '1000000',
    '1000000',
    '1000000',
    '1000000000',
    '1000000000',
    '1000000000',
    '1000000000',
    '1000000000000',
    '1000000000000',
    '1000000000000',
    '1000000000000000',
    '1000000000000000',
    '1000000000000000',
    '1000000000000000000',
    '1000000000000000000000',
    '1000000000000000000000',
    '1000000000000000000000000',
    '1000000000000000000000000000',
    '1000000000000000000000000000000');

function fromWei(wei: TWei; &to: TEthUnit; decimals: Byte): string;
var
  negative: Boolean;
  base    : BigInteger;
  baseLen : Integer;
  whole   : BigInteger;
  fraction: BigInteger;
begin
  Result := '';
  negative := wei.Negative;
  base := UnitToWei[&to];
  baseLen := UnitToWei[&to].Length;
  if negative then
    wei := wei.Abs;
  BigInteger.DivMod(wei, base, whole, fraction);
  if not fraction.IsZero then
  begin
    Result := fraction.ToString;
    while Result.Length < baseLen - 1 do
      Result := '0' + Result;
    while (Result.Length > 1) and (Result[High(Result)] = '0') do
      Delete(Result, High(Result), 1);
    while Result.Length > decimals do
      Delete(Result, High(Result), 1);
    if Length(Result) > 0 then
      Result := '.' + Result;
  end;
  Result := whole.ToString + Result;
  if negative then
    Result := '-' + Result;
end;

function toWei(input: string; &unit: TEthUnit): TWei;
var
  negative: Boolean;
  base    : BigInteger;
  baseLen : Integer;
  comps   : TArray<string>;
  whole   : string;
  fraction: string;
begin
  base := UnitToWei[&unit];
  baseLen := UnitToWei[&unit].Length;
  // is it negative?
  negative := (input.Length > 0) and (input[System.Low(input)] = '-');
  if negative then
    Delete(input, System.Low(input), 1);
  if (input = '') or (input = '.') then
    raise EWeb3.CreateFmt('Error while converting %s to wei. Invalid value.', [input]);
  // split it into a whole and fractional part
  comps := input.Split(['.']);
  if Length(comps) > 2 then
    raise EWeb3.CreateFmt('Error while converting %s to wei. Too many decimal points.', [input]);
  whole := comps[0];
  if Length(comps) > 1 then
    fraction := comps[1];
  Result := BigInteger.Multiply(whole, base);
  if fraction.Length > 0 then
  begin
    while fraction.Length < baseLen - 1 do
      fraction := fraction + '0';
    Result := BigInteger.Add(Result, fraction);
  end;
  if negative then
    Result := BigInteger.Negate(Result);
end;

function EthToFloat(const value: string): Double;
var
  FS: TFormatSettings;
begin
  FS := TFormatSettings.Create;
  FS.DecimalSeparator := '.';
  Result := StrToFloat(value, FS);
end;

function FloatToEth(value: Double): string;
var
  FS: TFormatSettings;
begin
  FS := TFormatSettings.Create;
  FS.DecimalSeparator := '.';
  Result := FloatToStr(value, FS);
end;

end.
