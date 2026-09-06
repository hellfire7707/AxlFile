#!/bin/bash
# AxlFile 전용 자체 서명 인증서를 만들어 로그인 키체인에 등록한다.
#
# 왜 필요한가:
#   ad-hoc 서명(CODE_SIGN_IDENTITY="-")으로 빌드하면 앱의 designated requirement 가
#   cdhash 뿐이라 빌드할 때마다 값이 바뀐다. macOS TCC(개인정보 보호)는 이 값을 기준으로
#   "다운로드/데스크탑/문서 폴더 접근 허용"을 기억하므로, 재빌드할 때마다 앱이
#   완전히 다른 앱으로 인식되어 접근 허용 창이 다시 뜬다.
#   고정된 인증서로 서명하면 requirement 가 인증서 기준이 되어 허용이 계속 유지된다.
#
# 사용법:  ./scripts/create-signing-identity.sh
#          (키체인 접근 허용을 위해 사용자 암호 입력 창이 뜬다)
set -euo pipefail

CN="AxlFile Self Signed"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-identity -v -p codesigning | grep -q "$CN"; then
    echo "이미 등록되어 있음: $CN"
    security find-identity -v -p codesigning | grep "$CN"
    exit 0
fi

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

echo "▸ 자체 서명 인증서 생성 (10년)"
openssl req -x509 -newkey rsa:2048 -nodes -sha256 -days 3650 \
    -keyout "$TMP/key.pem" -out "$TMP/cert.pem" -subj "/CN=$CN" \
    -addext "basicConstraints=critical,CA:false" \
    -addext "keyUsage=critical,digitalSignature" \
    -addext "extendedKeyUsage=critical,codeSigning" 2>/dev/null

openssl pkcs12 -export -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
    -out "$TMP/id.p12" -passout pass:

echo "▸ 로그인 키체인에 가져오기"
security import "$TMP/id.p12" -k "$KEYCHAIN" -P "" \
    -T /usr/bin/codesign -T /usr/bin/security

echo "▸ 코드 서명 용도로 신뢰 설정 (암호 입력 창이 뜹니다)"
security add-trusted-cert -r trustRoot -p codeSign -k "$KEYCHAIN" "$TMP/cert.pem"

echo "▸ codesign 이 키를 쓸 수 있도록 파티션 목록 설정 (로그인 암호 입력)"
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "" "$KEYCHAIN" >/dev/null 2>&1 || \
security set-key-partition-list -S apple-tool:,apple:,codesign: -s "$KEYCHAIN" >/dev/null

echo
echo "완료. 사용 가능한 서명 신원:"
security find-identity -v -p codesigning | grep "$CN"
echo
echo "이제 다음처럼 빌드하세요:"
echo "  xcodebuild -project AxlFile.xcodeproj -scheme AxlFile -configuration Release \\"
echo "    -archivePath build/AxlFile.xcarchive archive CODE_SIGN_IDENTITY=\"$CN\""
echo
echo "Xcode(Cmd+R) 로 실행할 때도 적용하려면 타겟 > Signing & Capabilities 에서"
echo "Signing Certificate 를 '$CN' 으로 선택하세요."
