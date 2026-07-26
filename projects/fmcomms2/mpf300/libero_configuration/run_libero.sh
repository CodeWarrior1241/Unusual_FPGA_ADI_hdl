#!/usr/bin/env bash
# Libero SoC 2025.2 launcher for Ubuntu 24.04.
#  - Points tools at the local FlexLM server (port 1702).
#  - Forces the SYSTEM libstdc++ so Ubuntu 24.04's libicu (needs GLIBCXX_3.4.30)
#    is satisfied; Libero's bundled RHEL libstdc++ (max 3.4.28) is too old.
LIBERO_ROOT=/media/fpgadev/Dev_Tools/Microchip/Libero_SoC

export LM_LICENSE_FILE=1702@localhost${LM_LICENSE_FILE:+:$LM_LICENSE_FILE}
export LD_PRELOAD=/usr/lib/x86_64-linux-gnu/libstdc++.so.6${LD_PRELOAD:+:$LD_PRELOAD}

exec "$LIBERO_ROOT/Designer/bin/libero" "$@"