set -euo pipefail

exe=$1
tui=$(fd tui . | head -n 1)

zig build

if [ $# -gt 1 ]; then
  args=(${@:2})
  echo "Invoking with args:"
  echo "  ${args[@]}"
  gdb -tui -q -ex=r -x $tui --args $exe "${args[@]}"
else
  echo "Invoking without args"
  gdb -tui -q -ex=r -x $tui $exe
fi
