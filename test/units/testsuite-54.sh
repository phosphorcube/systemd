#!/usr/bin/env bash
# SPDX-License-Identifier: LGPL-2.1-or-later
# shellcheck disable=SC2016
set -eux

systemd-analyze log-level debug

# Verify that the creds are properly loaded and we can read them from the service's unpriv user
systemd-run -p LoadCredential=passwd:/etc/passwd \
            -p LoadCredential=shadow:/etc/shadow \
            -p SetCredential=dog:wuff \
            -p DynamicUser=1 \
            --wait \
            --pipe \
            cat '${CREDENTIALS_DIRECTORY}/passwd' '${CREDENTIALS_DIRECTORY}/shadow' '${CREDENTIALS_DIRECTORY}/dog' >/tmp/ts54-concat
( cat /etc/passwd /etc/shadow && echo -n wuff ) | cmp /tmp/ts54-concat
rm /tmp/ts54-concat

# Test that SetCredential= acts as fallback for LoadCredential=
echo piff > /tmp/ts54-fallback
[ "$(systemd-run -p LoadCredential=paff:/tmp/ts54-fallback -p SetCredential=paff:poff --pipe --wait systemd-creds cat paff)" = "piff" ]
rm /tmp/ts54-fallback
[ "$(systemd-run -p LoadCredential=paff:/tmp/ts54-fallback -p SetCredential=paff:poff --pipe --wait systemd-creds cat paff)" = "poff" ]

if systemd-detect-virt -q -c ; then
    # If this test is run in nspawn a credential should have been passed to us. See test/TEST-54-CREDS/test.sh
    [ "$(systemd-creds --system cat mynspawncredential)" = "strangevalue" ]

    # Test that propagation from system credential to service credential works
    [ "$(systemd-run -p LoadCredential=mynspawncredential --pipe --wait systemd-creds cat mynspawncredential)" = "strangevalue" ]

    # Check it also works, if we rename it while propagating it
    [ "$(systemd-run -p LoadCredential=miau:mynspawncredential --pipe --wait systemd-creds cat miau)" = "strangevalue" ]

    # Combine it with a fallback (which should have no effect, given the cred should be passed down)
    [ "$(systemd-run -p LoadCredential=mynspawncredential -p SetCredential=mynspawncredential:zzz --pipe --wait systemd-creds cat mynspawncredential)" = "strangevalue" ]
fi

# Verify that the creds are immutable
systemd-run -p LoadCredential=passwd:/etc/passwd \
            -p DynamicUser=1 \
            --wait \
            touch '${CREDENTIALS_DIRECTORY}/passwd' \
    && { echo 'unexpected success'; exit 1; }
systemd-run -p LoadCredential=passwd:/etc/passwd \
            -p DynamicUser=1 \
            --wait \
            rm '${CREDENTIALS_DIRECTORY}/passwd' \
    && { echo 'unexpected success'; exit 1; }

# Check directory-based loading
mkdir -p /tmp/ts54-creds/sub
echo -n a >/tmp/ts54-creds/foo
echo -n b >/tmp/ts54-creds/bar
echo -n c >/tmp/ts54-creds/baz
echo -n d >/tmp/ts54-creds/sub/qux
systemd-run -p LoadCredential=cred:/tmp/ts54-creds \
            -p DynamicUser=1 \
            --wait \
            --pipe \
            cat '${CREDENTIALS_DIRECTORY}/cred_foo' \
                '${CREDENTIALS_DIRECTORY}/cred_bar' \
                '${CREDENTIALS_DIRECTORY}/cred_baz' \
                '${CREDENTIALS_DIRECTORY}/cred_sub_qux' >/tmp/ts54-concat
( echo -n abcd ) | cmp /tmp/ts54-concat
rm /tmp/ts54-concat
rm -rf /tmp/ts54-creds

# Now test encrypted credentials (only supported when built with OpenSSL though)
if systemctl --version | grep -q -- +OPENSSL ; then
    echo -n $RANDOM >/tmp/test-54-plaintext
    systemd-creds encrypt --name=test-54 /tmp/test-54-plaintext /tmp/test-54-ciphertext
    systemd-creds decrypt --name=test-54 /tmp/test-54-ciphertext | cmp /tmp/test-54-plaintext

    systemd-run -p LoadCredentialEncrypted=test-54:/tmp/test-54-ciphertext \
                --wait \
                --pipe \
                cat '${CREDENTIALS_DIRECTORY}/test-54' | cmp /tmp/test-54-plaintext

    echo -n $RANDOM >/tmp/test-54-plaintext
    systemd-creds encrypt --name=test-54 /tmp/test-54-plaintext /tmp/test-54-ciphertext
    systemd-creds decrypt --name=test-54 /tmp/test-54-ciphertext | cmp /tmp/test-54-plaintext

    systemd-run -p SetCredentialEncrypted=test-54:"$(cat /tmp/test-54-ciphertext)" \
                --wait \
                --pipe \
                cat '${CREDENTIALS_DIRECTORY}/test-54' | cmp /tmp/test-54-plaintext

    rm /tmp/test-54-plaintext /tmp/test-54-ciphertext
fi

systemd-analyze log-level info

echo OK >/testok

exit 0
