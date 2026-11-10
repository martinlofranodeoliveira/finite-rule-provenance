#!/bin/sh
set -eu
cd /work/source
export HOME=/work/home
mkdir -p "$HOME" /work/artifacts /work/consumer
raco pkg show --all --long > /work/artifacts/racket-installed-packages.txt
cmp qualification/racket-installed-packages.txt /work/artifacts/racket-installed-packages.txt
/bin/sh scripts/test-offline.sh
racket qualification/independent-sql-oracle.rkt
# Archive before creating binary outputs. Raco's actual package metadata and
# checksums are retained; dependency searching/downloading is forbidden.
raco pkg create --source --format zip --dest /work/artifacts /work/source
racket qualification/verify-package.rkt /work/artifacts/source.zip /work/source > /work/artifacts/package-source.sha256
raco pkg install --scope user --deps fail --batch --no-setup --name finite-rule-provenance /work/artifacts/source.zip
# A production executable must compile without the test checkout.
mv tests /work/artifacts/source-tests
/bin/sh scripts/build-offline.sh
for mode in text assert json both; do
  case "$mode" in
    text) /bin/sh scripts/demo-offline.sh ;;
    assert) /bin/sh scripts/demo-offline.sh --assert ;;
    json) /bin/sh scripts/demo-offline.sh --json ;;
    both) /bin/sh scripts/demo-offline.sh --assert --json ;;
  esac
done
cp qualification/consumer.rkt /work/consumer/consumer.rkt
cd /work/consumer
# The installed collection path is asserted; this directory has no source tree.
racket consumer.rkt
/work/source/dist/distribution/bin/finite-rule-provenance demo --assert --json
sha256sum /work/artifacts/source.zip /work/artifacts/source.zip.CHECKSUM /work/source/dist/distribution/bin/finite-rule-provenance > /work/artifacts/distributions.sha256
printf '%s\n' 'COMPLETE: native tests, independent SQLite oracle, exact archive, isolated installed API, production-only executable and four demo modes'
