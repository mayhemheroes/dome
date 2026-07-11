#!/usr/bin/env bash
# dome/mayhem/build.sh — build DOME's `embed` tool as the fuzz target.
#
# DOME is a C game engine that embeds the Wren scripting language and links SDL2 for its runtime.
# The OLD mayhemheroes integration did NOT fuzz the whole engine: its single target was `embed`
# (old Mayhemfile: `target: embed`, `cmd: /embed @@`; old Dockerfile.mayhem built the engine with
# `make` but copied out ONLY src/tools/embed). We keep that same, small fuzz surface here.
#
# `embed` is a self-contained file-input CLI: src/tools/embed-standalone.c #includes embedlib.c and
# implements main() — it reads args[1] as a source file (EMBED_readEntireFile) and EMBED_encode()s
# the bytes into a generated C include file (`<input>.inc`, the dome build step that turns *.wren
# modules into compilable C arrays). It links NO SDL and NO Wren VM — the Makefile's `embed` rule
# (src/tools/embed: ...) compiles embed-standalone.c with $(CFLAGS) only. So this build needs no
# SDL2 dev libs; the realistic fuzzed code is embed's own file read + encoder.
#
# The Mayhem target is FILE-INPUT (CLI): the fuzz bytes are handed to /mayhem/embed as a source
# file, exercising the read + encode path. There is NO libFuzzer harness — the embed binary IS the
# natural fuzz surface and is its own single-input reproducer (so no *-standalone artifact either:
# the file-input target already crashes naturally on one input file, exactly like the lacc/my_basic
# file-input templates).
#
# The repo ships NO functional test suite for `embed` (no known-answer/golden tests upstream), so
# there is no mayhem/test.sh — see the note where the template stub would have lived.
set -euo pipefail

# clang rejects SOURCE_DATE_EPOCH='' (empty) — must be unset or a valid integer.
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

# Build knobs from the base ENV, overridable. SANITIZER_FLAGS uses `=` (not `:=`) so an explicit
# empty value (--build-arg SANITIZER_FLAGS=) is honored → no-sanitizer build (embed's natural
# crash). embed links nothing beyond libc (no -lm, no SDL), so the empty-sanitizer build links
# cleanly with no extra flags.
: "${SANITIZER_FLAGS=-fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer -g}"
: "${DEBUG_FLAGS:=-g -gdwarf-3}"
: "${CC:=clang}"
: "${MAYHEM_JOBS:=$(nproc)}"
export SANITIZER_FLAGS DEBUG_FLAGS CC MAYHEM_JOBS

cd "$SRC"

# DOME's Makefile builds embed as:
#   $(CC) -o src/tools/embed $(CFLAGS) src/tools/embed-standalone.c $(WINDOW_MODE_FLAG)
# where (Linux) CFLAGS adds the project's -std=c99 -pedantic + warning suppressions and a DOME_HASH
# define derived from `git rev-parse`, and WINDOW_MODE_FLAG is empty on Linux. We compile embed
# directly here with the same dialect (-std=c99) PLUS $SANITIZER_FLAGS so the FUZZED code (embed's
# file read + EMBED_encode) is instrumented (ASan+UBSan, halting, by default). We keep upstream's
# warning suppressions so the clean build stays quiet, and silence the rest with -w (warnings don't
# affect the encoder's behavior). No SANITIZER off-switch special-casing is needed: with an empty
# SANITIZER_FLAGS the same command line links a plain binary.
WARN="-Wall -Wno-unused-parameter -Wno-unused-function -Wno-unused-value -w"

# -D_XOPEN_SOURCE=500 is exactly what DOME's Makefile adds for Linux (CFLAGS += -D_XOPEN_SOURCE=500):
# embed-standalone.c uses strdup(), which under -std=c99 is hidden behind a feature-test macro, so
# without it clang errors on the implicit declaration. Match upstream's Linux build to expose it.
XOPEN="-D_XOPEN_SOURCE=500"

# LeakSanitizer off — bake __asan_default_options with detect_leaks=0 (NOT ASAN_OPTIONS in the
# Mayhemfile). embed's main() (src/tools/embed-standalone.c) reads the whole input into a malloc'd
# buffer and never frees it before returning, so LSan reports a "leak" on EVERY input — the default
# seed and every valid program included. That floods the fuzzer with leaks before it can reach a real
# memory defect. We disable ONLY leak detection; ASan's real memory-safety checks (overflow,
# use-after-free, …) AND halting UBSan stay fully ON, so genuine defects in the read/encode path
# still crash. Done as an ADDITIVE linked object (a weak __asan_default_options override) — no edit
# to the upstream source. Only emitted when ASan is active (skipped for the empty-sanitizer build).
ASAN_OPTS_OBJ=""
if printf '%s' "$SANITIZER_FLAGS" | grep -q address; then
  cat > /tmp/embed_asan_opts.c <<'EOF'
/* Disable LSan: embed never frees its input buffer (benign, fires on every input). */
const char* __asan_default_options(void) { return "detect_leaks=0"; }
EOF
  $CC -std=c99 -c /tmp/embed_asan_opts.c -o /tmp/embed_asan_opts.o
  ASAN_OPTS_OBJ=/tmp/embed_asan_opts.o
fi

# Build the file-input fuzz target at /mayhem/embed (kept the OLD target name `embed` for parity).
# embed-standalone.c #includes embedlib.c, so a single source compile produces the whole tool.
# shellcheck disable=SC2086
$CC -std=c99 $XOPEN $WARN $SANITIZER_FLAGS $DEBUG_FLAGS \
    "$SRC/src/tools/embed-standalone.c" $ASAN_OPTS_OBJ \
    -o /mayhem/embed

echo "build.sh: built /mayhem/embed (sanitized file-input fuzz target)"
ls -l /mayhem/embed
