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

unit web3.crypto;

{$I web3.inc}

interface

uses
  // Delphi
  System.SysUtils,
  System.TypInfo,
  // CryptoLib4Pascal
  ClpBigInteger,
  ClpCryptoLibTypes,
  ClpCustomNamedCurves,
  ClpECDomainParameters,
  ClpECDsaSigner,
  ClpECKeyGenerationParameters,
  ClpECKeyPairGenerator,
  ClpECPrivateKeyParameters,
  ClpIAsymmetricCipherKeyPair,
  ClpIECC,
  ClpIECDomainParameters,
  ClpIECKeyGenerationParameters,
  ClpIECKeyPairGenerator,
  ClpIECPrivateKeyParameters,
  ClpIECPublicKeyParameters,
  ClpISecureRandom,
  ClpIX9ECParameters,
  ClpIX9ECParametersHolder,
  ClpSecureRandom;

type
  TKeyType = (SECP256K1, SECP384R1, SECP521R1, SECT283K1);

type
  TECDsaSignature = record
    r  : TBigInteger;
    s  : TBigInteger;
    rec: TBigInteger;
  end;

type
  TECDsaSignerEx = class(TECDsaSigner)
  public
    function GenerateSignature(aKeyType: TKeyType; const msg: TCryptoLibByteArray): TECDsaSignature; reintroduce;
  end;

function privateKeyFromByteArray(const algorithm: string; aKeyType: TKeyType; const aPrivKey: TBytes): IECPrivateKeyParameters;
function publicKeyFromPrivateKey(aPrivKey: IECPrivateKeyParameters): TBytes;
function generatePrivateKey(const algorithm: string; aKeyType: TKeyType): IECPrivateKeyParameters;

implementation

function getCurveFromKeyType(aKeyType: TKeyType): IX9ECParameters;
var
  curveName: string;
begin
  curveName := GetEnumName(TypeInfo(TKeyType), Ord(aKeyType));
  Result    := TCustomNamedCurves.GetByName(curveName);
end;

function privateKeyFromByteArray(const algorithm: string; aKeyType: TKeyType; const aPrivKey: TBytes): IECPrivateKeyParameters;
var
  domain: IECDomainParameters;
  curve : IX9ECParameters;
  privD : TBigInteger;
begin
  curve  := getCurveFromKeyType(aKeyType);
  domain := TECDomainParameters.Create(curve.Curve, curve.G, curve.N, curve.H, curve.GetSeed);
  privD  := TBigInteger.Create(1, aPrivKey);
  Result := TECPrivateKeyParameters.Create(algorithm, privD, domain);
end;

function publicKeyFromPrivateKey(aPrivKey: IECPrivateKeyParameters): TBytes;
var
  params: IECPublicKeyParameters;
begin
  params := TECKeyPairGenerator.GetCorrespondingPublicKey(aPrivKey);
  Result := params.Q.AffineXCoord.ToBigInteger.ToByteArrayUnsigned
          + params.Q.AffineYCoord.ToBigInteger.ToByteArrayUnsigned;
end;

function generatePrivateKey(const algorithm: string; aKeyType: TKeyType): IECPrivateKeyParameters;
var
  secureRandom    : ISecureRandom;
  customCurve     : IX9ECParameters;
  domainParams    : IECDomainParameters;
  keyPairGenerator: IECKeyPairGenerator;
  keyGenParams    : IECKeyGenerationParameters;
  keyPair         : IAsymmetricCipherKeyPair;
begin
  secureRandom := TSecureRandom.Create;

  customCurve := getCurveFromKeyType(aKeyType);
  domainParams := TECDomainParameters.Create(customCurve.Curve,
    customCurve.G, customCurve.N, customCurve.H, customCurve.GetSeed);
  keyPairGenerator := TECKeyPairGenerator.Create(algorithm);
  keyGenParams := TECKeyGenerationParameters.Create(domainParams, secureRandom);
  keyPairGenerator.Init(keyGenParams);

  keyPair := keyPairGenerator.GenerateKeyPair;
  Result := keyPair.Private as IECPrivateKeyParameters;
end;

{ TECDsaSignerEx }

function TECDsaSignerEx.GenerateSignature(aKeyType: TKeyType; const msg: TCryptoLibByteArray): TECDsaSignature;

  function curveOrder: TBigInteger;
  begin
    Result := getCurveFromKeyType(aKeyType).Curve.Order;
  end;

  function isLowS(const s: TBigInteger): Boolean;
  var
    halfCurveOrder: TBigInteger;
  begin
    halfCurveOrder := curveOrder.ShiftRight(1);
    Result := s.CompareTo(halfCurveOrder) <= 0;
  end;

  procedure makeCanonical(var aSignature: TECDsaSignature);
  begin
    if not isLowS(aSignature.s) then
      aSignature.s := curveOrder.Subtract(aSignature.s);
  end;

var
  ec: IECDomainParameters;
  base: IECMultiplier;
  n, e, d, k: TBigInteger;
  p: IECPoint;
begin
  ec := Fkey.parameters;
  n := ec.n;
  e := CalculateE(n, msg);
  d := (Fkey as IECPrivateKeyParameters).d;

  if FkCalculator.IsDeterministic then
    FkCalculator.Init(n, d, msg)
  else
    FkCalculator.Init(n, Frandom);

  base := CreateBasePointMultiplier;

  repeat // Generate s
    repeat // Generate r
      k := FkCalculator.NextK;
      p := base.Multiply(ec.G, k).Normalize;
      Result.r := p.AffineXCoord.ToBigInteger.&Mod(n);
    until not(Result.r.SignValue = 0);
    Result.s := k.ModInverse(n).Multiply(e.Add(d.Multiply(Result.r))).&Mod(n);
  until not(Result.s.SignValue = 0);

  // https://ethereum.stackexchange.com/questions/42455/during-ecdsa-signing-how-do-i-generate-the-recovery-id
  Result.rec := p.AffineYCoord.ToBigInteger.&And(TBigInteger.One);
  if Result.s.CompareTo(n.Divide(TBigInteger.Two)) = 1 then
    Result.rec := Result.rec.&Xor(TBigInteger.One);

  // https://github.com/bitcoin/bips/blob/master/bip-0062.mediawiki#Low_S_values_in_signatures
  makeCanonical(Result);
end;

end.
