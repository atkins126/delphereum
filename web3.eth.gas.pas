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

unit web3.eth.gas;

{$I web3.inc}

interface

uses
  // Delphi
  System.JSON,
  System.SysUtils,
  // Velthuis' BigNumbers
  Velthuis.BigIntegers,
  // web3
  web3,
  web3.eth,
  web3.eth.abi,
  web3.eth.types,
  web3.json,
  web3.json.rpc,
  web3.utils;

procedure getGasPrice(const client: IWeb3; const callback: TProc<BigInteger, IError>; const allowCustom: Boolean = True);
procedure getBaseFeePerGas(const client: IWeb3; const callback: TProc<BigInteger, IError>);
procedure getMaxPriorityFeePerGas(const client: IWeb3; const callback: TProc<BigInteger, IError>);
procedure getMaxFeePerGas(const client: IWeb3; const callback: TProc<BigInteger, IError>; const allowCustom: Boolean = True);

procedure estimateGas(
  const client   : IWeb3;
  const from, &to: TAddress;
  const func     : string;
  const args     : array of const;
  const callback : TProc<BigInteger, IError>); overload;
procedure estimateGas(
  const client   : IWeb3;
  const from, &to: TAddress;
  const data     : string;
  const callback : TProc<BigInteger, IError>); overload;

implementation

procedure eth_gasPrice(const client: IWeb3; const callback: TProc<BigInteger, IError>);
begin
  client.Call('eth_gasPrice', [], procedure(response: TJsonObject; err: IError)
  begin
    if Assigned(err) then
      callback(0, err)
    else
      callback(web3.json.getPropAsStr(response, 'result'), nil);
  end);
end;

procedure getGasPrice(const client: IWeb3; const callback: TProc<BigInteger, IError>; const allowCustom: Boolean);
begin
  if allowCustom then
  begin
    const price = client.GetCustomGasPrice;
    if price > 0 then
    begin
      callback(price, nil);
      EXIT;
    end;
  end;

  if client.Chain.TxType >= 2 then // EIP-1559
  begin
    getBaseFeePerGas(client, procedure(baseFee: TWei; err: IError)
    begin
      if Assigned(err) then
        callback(0, err)
      else
        getMaxPriorityFeePerGas(client, procedure(tip: TWei; err: IError)
        begin
          if Assigned(err) then
            callback(0, err)
          else
            callback(baseFee + tip, nil);
        end);
    end);
    EXIT;
  end;

  eth_gasPrice(client, callback);
end;

procedure getBaseFeePerGas(const client: IWeb3; const callback: TProc<BigInteger, IError>);
begin
  web3.eth.getBlockByNumber(client, procedure(block: IBlock; err: IError)
  begin
    if Assigned(err) then
      callback(0, err)
    else
      callback(block.baseFeePerGas, nil);
  end);
end;

procedure getMaxPriorityFeePerGas(const client: IWeb3; const callback: TProc<BigInteger, IError>);
begin
  client.Call('eth_maxPriorityFeePerGas', [], procedure(response: TJsonObject; err: IError)
  begin
    if Assigned(err) then
    begin
      eth_gasPrice(client, procedure(gasPrice: TWei; err: IError)
      begin
        if Assigned(err) then
          callback(0, err)
        else
          getBaseFeePerGas(client, procedure(baseFee: TWei; err: IError)
          begin
            if Assigned(err) then
              callback(0, err)
            else
              callback(TWei.Max(1000000000, gasPrice - baseFee), nil);
          end);
      end);
      EXIT;
    end;
    callback(TWei.Max(1000000000, web3.json.getPropAsStr(response, 'result')), nil);
  end);
end;

procedure getMaxFeePerGas(const client: IWeb3; const callback: TProc<BigInteger, IError>; const allowCustom: Boolean);
begin
  if allowCustom then
  begin
    const price = client.GetCustomGasPrice;
    if price > 0 then
    begin
      callback(price, nil);
      EXIT;
    end;
  end;

  getBaseFeePerGas(client, procedure(baseFee: TWei; err: IError)
  begin
    if Assigned(err) then
      callback(0, err)
    else
      getMaxPriorityFeePerGas(client, procedure(tip: TWei; err: IError)
      begin
        if Assigned(err) then
          callback(0, err)
        else
          callback((2 * baseFee) + tip, nil);
      end);
  end);
end;

procedure estimateGas(
  const client   : IWeb3;
  const from, &to: TAddress;
  const func     : string;
  const args     : array of const;
  const callback : TProc<BigInteger, IError>);
begin
  estimateGas(client, from, &to, web3.eth.abi.encode(func, args), callback);
end;

procedure estimateGas(
  const client   : IWeb3;
  const from, &to: TAddress;
  const data     : string;
  const callback : TProc<BigInteger, IError>);
begin
  // estimate how much gas is necessary for the transaction to complete (without creating a transaction on the blockchain)
  const eth_estimateGas = procedure(client: IWeb3; const json: string; callback: TProc<BigInteger, IError>)
  begin
    const obj = web3.json.unmarshal(json) as TJsonObject;
    try
      client.Call('eth_estimateGas', [obj], procedure(response: TJsonObject; err: IError)
      begin
        if Assigned(err) then
          callback(0, err)
        else
          callback(web3.json.getPropAsStr(response, 'result'), nil);
      end);
    finally
      obj.Free;
    end;
  end;

  // if strict, then factor in your gas price (otherwise ignore your gas price while estimating gas)
  const doEstimateGasEx = procedure(client: IWeb3; from, &to: TAddress; &strict: Boolean; callback: TProc<BigInteger, IError>)
  begin
    if not &strict then
    begin
      eth_estimateGas(client, Format(
        '{"from": %s, "to": %s, "data": %s}',
        [quoteString(string(from), '"'), quoteString(string(&to), '"'), quoteString(data, '"')]
      ), callback);
      EXIT;
    end;
    // construct the eip-1559 transaction call object
    if client.Chain.TxType >= 2 then
    begin
      getMaxPriorityFeePerGas(client, procedure(tip: TWei; err: IError)
      begin
        if Assigned(err) then
          callback(0, err)
        else
          getMaxFeePerGas(client, procedure(max: TWei; err: IError)
          begin
            if Assigned(err) then
              callback(0, err)
            else
              eth_estimateGas(client, Format(
                '{"from": %s, "to": %s, "data": %s, "maxPriorityFeePerGas": %s, "maxFeePerGas": %s}', [
                  web3.json.quoteString(string(from), '"'),
                  web3.json.quoteString(string(&to), '"'),
                  web3.json.quoteString(data, '"'),
                  web3.json.quoteString(toHex(tip, [zeroAs0x0]), '"'),
                  web3.json.quoteString(toHex(max, [zeroAs0x0]), '"')
                ]
              )
              , callback);
          end, False);
      end);
      EXIT;
    end;
    // construct the legacy transaction call object
    getGasPrice(client, procedure(gasPrice: TWei; err: IError)
    begin
      if Assigned(err) then
        callback(0, err)
      else
        eth_estimateGas(client, Format(
          '{"from": %s, "to": %s, "data": %s, "gasPrice": %s}', [
            web3.json.quoteString(string(from), '"'),
            web3.json.quoteString(string(&to), '"'),
            web3.json.quoteString(data, '"'),
            web3.json.quoteString(toHex(gasPrice, [zeroAs0x0]), '"')
          ]
        ), callback);
    end, False);
  end;

  // do a loosely estimate first, then a strict estimate if an error occurred
  doEstimateGasEx(client, from, &to, False, procedure(qty: BigInteger; err: IError)
  begin
    if Assigned(err) then
      doEstimateGasEx(client, from, &to, True, callback)
    else
      callback(qty, nil);
  end);
end;

end.
