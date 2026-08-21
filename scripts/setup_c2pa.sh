#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TOOL_VERSION="0.27.15"
CONFORMANCE_COMMIT="44c81e07fc92b39a525412f4e7a1c2cda0757beb"
TOOL_URL="https://github.com/contentauth/c2pa-rs/releases/download/c2patool-v${TOOL_VERSION}/c2patool-v${TOOL_VERSION}-universal-apple-darwin.zip"
TOOL_ARCHIVE_SHA256="394789e3e6f9d41f545612df6677b3a0f95291e40c066d40a916d7e47e5d3de0"
TOOL_BINARY_SHA256="daa5c37631ba9388ae30af18ece470d2926f139fda8641895ae65a2baf7d6d57"
CONFORMANCE_SOURCE_URL="https://raw.githubusercontent.com/contentauth/c2pa-conformance-tool/${CONFORMANCE_COMMIT}/src/lib/CertificateManager.svelte"
CONFORMANCE_SOURCE_SHA256="357826172a73b7fdb51e8eabe1d6ef80c2891f7386b3f6fc4106da20b75047aa"
TEST_ROOT_SHA256="ad66f955c63d7fc28771a40b730b3d594643dd2ff3a764858d97615245bb9216"
TEST_SIGNING_CERT_FINGERPRINT="B2:7C:27:D4:50:19:DC:80:D4:75:5A:26:20:7B:9E:02:E2:36:E5:4D:70:92:85:73:D6:8E:4E:CE:18:06:87:55"

TOOL_DIRECTORY="$REPO_ROOT/.tooling/c2pa/$TOOL_VERSION/c2patool"
TOOL_PATH="$TOOL_DIRECTORY/c2patool"
TRUST_DIRECTORY="$REPO_ROOT/.c2pa-test/trust"
ROOT_PATH="$TRUST_DIRECTORY/test-root-cert.pem"
TRUST_CONFIG_PATH="$TRUST_DIRECTORY/store.cfg"
SIGNING_BUNDLE="${1:-${LOOP_GENERATOR_C2PA_SIGNING_BUNDLE:-$HOME/Downloads/test-signing-bundle.pem}}"

for command_name in curl shasum unzip awk openssl cmp; do
    command -v "$command_name" >/dev/null || {
        echo "Required command is missing: $command_name" >&2
        exit 1
    }
done

[[ -r "$SIGNING_BUNDLE" ]] || {
    echo "C2PA test signing bundle not found: $SIGNING_BUNDLE" >&2
    exit 1
}

TEMP_DIRECTORY="$(mktemp -d "${TMPDIR:-/tmp}/loop-generator-c2pa.XXXXXX")"
cleanup() {
    rm -f "$TEMP_DIRECTORY/tool.zip" "$TEMP_DIRECTORY/CertificateManager.svelte"
    rm -f "$TEMP_DIRECTORY/cert-public.pem" "$TEMP_DIRECTORY/key-public.pem"
    rmdir "$TEMP_DIRECTORY" 2>/dev/null || true
}
trap cleanup EXIT

mkdir -p "$TOOL_DIRECTORY" "$TRUST_DIRECTORY"
if [[ ! -x "$TOOL_PATH" ]] || \
   [[ "$(shasum -a 256 "$TOOL_PATH" | awk '{print $1}')" != "$TOOL_BINARY_SHA256" ]]; then
    curl --fail --location --silent --show-error "$TOOL_URL" -o "$TEMP_DIRECTORY/tool.zip"
    [[ "$(shasum -a 256 "$TEMP_DIRECTORY/tool.zip" | awk '{print $1}')" == "$TOOL_ARCHIVE_SHA256" ]] || {
        echo "c2patool archive checksum mismatch" >&2
        exit 1
    }
    unzip -jo "$TEMP_DIRECTORY/tool.zip" "c2patool/c2patool" -d "$TOOL_DIRECTORY" >/dev/null
    chmod +x "$TOOL_PATH"
fi

curl --fail --location --silent --show-error \
    "$CONFORMANCE_SOURCE_URL" \
    -o "$TEMP_DIRECTORY/CertificateManager.svelte"
[[ "$(shasum -a 256 "$TEMP_DIRECTORY/CertificateManager.svelte" | awk '{print $1}')" == "$CONFORMANCE_SOURCE_SHA256" ]] || {
    echo "Conformance-tool source checksum mismatch" >&2
    exit 1
}
awk '
    /const TEST_ROOT_CERT_PEM = `-----BEGIN CERTIFICATE-----/ {
        print "-----BEGIN CERTIFICATE-----"
        in_certificate = 1
        next
    }
    in_certificate {
        sub(/`$/, "")
        if ($0 == "-----END CERTIFICATE-----") {
            printf "%s", $0
            exit
        }
        print
    }
' "$TEMP_DIRECTORY/CertificateManager.svelte" > "$ROOT_PATH"
[[ "$(shasum -a 256 "$ROOT_PATH" | awk '{print $1}')" == "$TEST_ROOT_SHA256" ]] || {
    echo "C2PA Conformance Test Root checksum mismatch" >&2
    exit 1
}
printf '%s\n' '1.3.6.1.5.5.7.3.36' > "$TRUST_CONFIG_PATH"

ACTUAL_FINGERPRINT="$(openssl x509 -in "$SIGNING_BUNDLE" -noout -fingerprint -sha256 | awk -F= '{print $2}')"
[[ "$ACTUAL_FINGERPRINT" == "$TEST_SIGNING_CERT_FINGERPRINT" ]] || {
    echo "The external PEM is not the official C2PA Conformance Test signing credential" >&2
    exit 1
}
openssl x509 -in "$SIGNING_BUNDLE" -pubkey -noout > "$TEMP_DIRECTORY/cert-public.pem"
openssl pkey -in "$SIGNING_BUNDLE" -pubout > "$TEMP_DIRECTORY/key-public.pem" 2>/dev/null
cmp -s "$TEMP_DIRECTORY/cert-public.pem" "$TEMP_DIRECTORY/key-public.pem" || {
    echo "The signing certificate and private key do not match" >&2
    exit 1
}
openssl verify -purpose any -CAfile "$ROOT_PATH" "$SIGNING_BUNDLE" >/dev/null

echo "C2PA test runtime ready"
echo "c2patool: $($TOOL_PATH --version)"
echo "trust mode: C2PA Conformance Test Root enabled"
echo "signing credential: external file verified at $SIGNING_BUNDLE"
echo "private key copied into repository: no"
