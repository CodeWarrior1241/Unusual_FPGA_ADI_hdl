#!/usr/bin/env bash
# Libero SoC batch/GUI launcher (developed on Ubuntu 24.04; verified on
# Libero 2025.2 and 2026.1 -- default is 2026.1).
#
# Environment overrides (all optional):
#   LIBERO_INSTALL_DIR     Libero_SoC install dir (the one containing
#                          Designer/bin/libero). Same variable as the
#                          Questa sim scripts. Default: dev-box path below.
#   LIBERO_LICENSE_SERVER  FlexLM server, e.g. 1702@licserver.
#                          Default: 1702@localhost (local lmgrd).
#
# The system libstdc++ is LD_PRELOADed when present: Ubuntu 24.04's libicu
# needs GLIBCXX_3.4.30, newer than Libero's bundled RHEL libstdc++ (3.4.28).
# Both the Debian/Ubuntu multiarch path and the RHEL/SUSE lib64 path are
# probed; if neither exists the preload is simply skipped.
LIBERO_ROOT="${LIBERO_INSTALL_DIR:-/media/fpgadev/Dev_Tools/Microchip_FPGA/2026.1/Libero_SoC}"

if [ ! -x "$LIBERO_ROOT/Designer/bin/libero" ]; then
    echo "ERROR: libero not found at $LIBERO_ROOT/Designer/bin/libero" >&2
    echo "       Set LIBERO_INSTALL_DIR to your Libero_SoC install directory" >&2
    echo "       (the one containing Designer/bin/libero)." >&2
    exit 1
fi

export LM_LICENSE_FILE="${LIBERO_LICENSE_SERVER:-1702@localhost}${LM_LICENSE_FILE:+:$LM_LICENSE_FILE}"

for libcxx in /usr/lib/x86_64-linux-gnu/libstdc++.so.6 /usr/lib64/libstdc++.so.6; do
    if [ -e "$libcxx" ]; then
        export LD_PRELOAD="$libcxx${LD_PRELOAD:+:$LD_PRELOAD}"
        break
    fi
done

exec "$LIBERO_ROOT/Designer/bin/libero" "$@"
