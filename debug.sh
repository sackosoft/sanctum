set -euox pipefail

exe="REDACTED"

zig build

if [ $# -gt 0 ]; then
  args=(${@:2})
  echo "Invoking with args: '$args'"
  gdb -tui -q -ex=r -x tui.txt --args $exe $args
else
  echo "Invoking without args"
  gdb -tui -q -ex=r -x tui.txt $exe
fi
