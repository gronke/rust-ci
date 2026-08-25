#!/usr/bin/env bash
# Background resource sampler. Argv: <samples.tsv> <interval seconds> <pidfile>.
#
# One line per tick: epoch_ms, CPU busy percent since the previous tick, used
# and total memory in kB, free disk on the workspace filesystem in kB.
#
# CPU comes from /proc/stat deltas rather than /proc/loadavg on purpose. Load is
# a one-minute exponential average, so it lags into the following stage and
# under-reports any stage shorter than its own window: a three-minute compile
# that pins every core reads as half idle, and the stage after it inherits the
# tail. A delta between consecutive ticks is the actual utilization of the
# interval it covers, which is the only form that attributes to a stage.
#
# Deliberately dependency-free and failure-tolerant: it runs unsupervised for
# the whole job, and a sampler that dies half way would misreport the tail of
# the run as idle. Every read is guarded and a bad tick is skipped, not fatal.
set -uo pipefail

out="$1"
interval="$2"
pidfile="${3:-}"

# setsid gave this process its own session, so its PID is also its process
# group. It writes the pid itself because $! in the parent is nohup's or
# setsid's, not this process, and killing that would leave the sampler running
# for the rest of the job.
[ -n "$pidfile" ] && echo "$$" > "$pidfile"

# Cumulative jiffies since boot: busy is everything except idle and iowait.
cpu_totals() {
  awk '/^cpu /{
         idle = $5 + $6
         total = 0
         for (i = 2; i <= NF; i++) total += $i
         printf "%d %d", total, idle
         exit
       }' /proc/stat 2>/dev/null
}

read -r prev_total prev_idle <<<"$(cpu_totals)"
: "${prev_total:=0}" "${prev_idle:=0}"

while :; do
  sleep "$interval"

  now="$(date +%s%3N 2>/dev/null || true)"
  case "$now" in
    '' | *[!0-9]*) now="$(( $(date +%s) * 1000 ))" ;;
  esac

  read -r total idle <<<"$(cpu_totals)"
  : "${total:=0}" "${idle:=0}"
  busy_pct=0
  dt=$(( total - prev_total ))
  di=$(( idle - prev_idle ))
  if [ "$dt" -gt 0 ]; then
    busy_pct=$(( (dt - di) * 100 / dt ))
    [ "$busy_pct" -lt 0 ] && busy_pct=0
    [ "$busy_pct" -gt 100 ] && busy_pct=100
  fi
  prev_total=$total
  prev_idle=$idle

  mem="$(awk '/^MemTotal:/{t=$2} /^MemAvailable:/{a=$2} END{printf "%d\t%d", (t>a? t-a : 0), t}' /proc/meminfo 2>/dev/null || printf '0\t0')"
  disk="$(df -kP . 2>/dev/null | awk 'NR==2{print $4}')"
  [ -n "$disk" ] || disk=0

  printf '%s\t%s\t%s\t%s\n' "$now" "$busy_pct" "$mem" "$disk" >> "$out" 2>/dev/null || exit 0
done
