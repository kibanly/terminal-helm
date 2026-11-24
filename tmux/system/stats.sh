#!/usr/bin/env bash
# CPU and RAM for the tmux status bar (#(…), every status-interval seconds).
# Linux: CPU is the average since the previous call (/proc/stat, kept in a small cache
# file), RAM used = total - available. macOS: CPU from ps (summed per core, the way
# Activity Monitor adds it up), RAM used = app + wired + compressed memory (vm_stat).
# tmux runs #(…) once per attached terminal, a moment apart: the second one would measure the
# CPU over a millisecond (noise), so a line printed under 2 s ago is printed again instead.
cache=${XDG_RUNTIME_DIR:-${TMPDIR:-/tmp}}
cache=${cache%/}/tmux-cpu-$UID
# (bash builtins where they can: this runs every few seconds for every terminal attached)
if (( BASH_VERSINFO[0] * 100 + BASH_VERSINFO[1] >= 402 )); then printf -v now '%(%s)T' -1; else now=$(date +%s); fi
if read -r at line 2>/dev/null < "$cache.line" && [[ $at =~ ^[0-9]+$ ]] && (( now - at < 2 )); then
  printf '%s' "$line"; exit 0
fi
colour() { if (( $1 >= 90 )); then REPLY='#f38ba8'; elif (( $1 >= 70 )); then REPLY='#f9e2af'; else REPLY='#a6adc8'; fi; }

if [[ -r /proc/stat ]]; then
  read -r _ u n s i w q sq _ < /proc/stat; total=$((u+n+s+i+w+q+sq)); idle=$((i+w))
  cpu=0
  if [[ -r $cache ]] && read -r pt pi < "$cache" && (( total > pt )); then
    cpu=$(( 100 * ((total - pt) - (idle - pi)) / (total - pt) ))
  fi
  echo "$total $idle" > "$cache"
  while read -r k v _; do case $k in MemTotal:) mt=$v;; MemAvailable:) ma=$v;; esac; done < /proc/meminfo
  used_kb=$(( mt - ma ))
else                                                   # macOS
  # cores and RAM never change: asked once, then read from a file (two sysctl less per call)
  if ! { read -r cores mt 2>/dev/null < "$cache.static" && [[ $cores =~ ^[0-9]+$ && $mt =~ ^[0-9]+$ ]]; }; then
    cores=$(sysctl -n hw.ncpu); mt=$(( $(sysctl -n hw.memsize) / 1024 ))
    echo "$cores $mt" > "$cache.static.$$" && mv -f "$cache.static.$$" "$cache.static"
  fi
  # summed in bash, in tenths of a percent ("12.3" → 123): no awk to start, ~14 ms less per call
  tenths=0
  while read -r v; do
    [[ $v == *.* ]] || v=$v.0
    i=${v%%.*} f=${v#*.}
    tenths=$(( tenths + 10#${i:-0} * 10 + 10#${f:0:1} ))
  done < <(LC_ALL=C ps -A -o %cpu=)
  cpu=$(( tenths / (cores * 10) )); (( cpu > 100 )) && cpu=100
  size=16384 app=0 purge=0 wired=0 comp=0
  while IFS=: read -r k v; do
    v=${v//[!0-9]/}
    case $k in
      *"page size of"*)             [[ $k =~ size\ of\ ([0-9]+) ]] && size=${BASH_REMATCH[1]} ;;
      "Anonymous pages")            app=$v ;;
      "Pages purgeable")            purge=$v ;;
      "Pages wired down")           wired=$v ;;
      "Pages occupied by compressor") comp=$v ;;
    esac
  done < <(vm_stat)
  used_kb=$(( (app - purge + wired + comp) * size / 1024 ))
fi
mem=$(( used_kb * 100 / mt ))
t=$(( (used_kb * 10 + 524288) / 1048576 ))           # GiB in tenths, rounded (as %.1f did)
used="$(( t / 10 )).$(( t % 10 ))G"
colour "$cpu"; c_cpu=$REPLY; colour "$mem"; c_mem=$REPLY
printf -v line '#[fg=%s]󰍛 %d%%  #[fg=%s]󰘚 %s' "$c_cpu" "$cpu" "$c_mem" "$used"
printf '%s' "$line"
echo "$now $line" > "$cache.line.$$" && mv -f "$cache.line.$$" "$cache.line"
