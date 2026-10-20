#!/bin/sh
# Copy the files zufax reads into a fixture tree that mirrors the filesystem.
#
#   capture-fixture.sh OUT_DIR
#
# Run it on the machine or inside the container to capture, e.g.
#
#   podman run --rm --cpus=1.5 --memory=512m \
#     -v "$PWD/data-raw:/capture:ro" -v "$PWD/out:/out" \
#     docker.io/library/alpine sh /capture/capture-fixture.sh /out
#
# Only plain-text files are copied; nothing secret is read (no service account
# token, no environment, no /proc/1/environ). cgroup v2 only: v1 fixtures are
# written by hand.
set -u
out=${1:?usage: capture-fixture.sh OUT_DIR}

copy() {
  for f in "$@"; do
    [ -f "$f" ] && [ -r "$f" ] || continue
    mkdir -p "$out$(dirname "$f")"
    cat "$f" > "$out$f" 2> /dev/null || rm -f "$out$f"
  done
}

copy /proc/self/cgroup /proc/self/mountinfo /proc/self/status \
  /proc/self/limits /proc/self/statm /proc/meminfo /proc/cpuinfo \
  /proc/loadavg /proc/uptime /proc/1/comm /proc/1/cgroup \
  /proc/sys/kernel/osrelease /proc/sys/kernel/version \
  /proc/sys/kernel/hostname /etc/os-release /usr/lib/os-release \
  /var/run/secrets/kubernetes.io/serviceaccount/namespace \
  /sys/devices/system/cpu/online /sys/devices/system/cpu/possible \
  /sys/class/dmi/id/sys_vendor /sys/class/dmi/id/product_name \
  /sys/class/dmi/id/board_vendor /sys/class/dmi/id/chassis_asset_tag \
  /sys/hypervisor/type /.dockerenv /run/.containerenv

# Drop the capture's own bind mounts: they reveal paths on the capturing host.
mi="$out/proc/self/mountinfo"
if [ -f "$mi" ]; then
  grep -v -e " $out " -e " /capture " "$mi" > "$mi.tmp" && mv "$mi.tmp" "$mi"
fi

# Only the boot time line of /proc/stat.
if [ -r /proc/stat ]; then
  mkdir -p "$out/proc"
  grep '^btime ' /proc/stat > "$out/proc/stat"
fi

for d in /sys/devices/system/cpu/cpu[0-9]*; do
  copy "$d/topology/core_id" "$d/topology/physical_package_id"
done

# cgroup v2: the process's own cgroup and every ancestor up to the mount.
cg_files="cgroup.controllers cpu.max cpu.weight cpu.stat cpuset.cpus.effective
  memory.max memory.high memory.current memory.swap.max memory.stat
  memory.events memory.pressure cpu.pressure pids.max"
path=$(sed -n 's/^0:://p' /proc/self/cgroup)
mnt=$(awk '/ - cgroup2 / { print $5; exit }' /proc/self/mountinfo)
root=$(awk '/ - cgroup2 / { print $4; exit }' /proc/self/mountinfo)
if [ -n "$mnt" ] && [ -n "$path" ]; then
  rel=$path
  if [ "$root" != "/" ]; then
    rel=${path#"$root"}
  fi
  [ "$rel" = "/" ] && rel=""
  dir="$mnt$rel"
  [ -d "$dir" ] || dir=$mnt
  while :; do
    for f in $cg_files; do copy "$dir/$f"; done
    [ "$dir" = "$mnt" ] && break
    dir=$(dirname "$dir")
  done
fi
