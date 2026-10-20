# Facts with their status and source

Returns one row per fact, with the metadata recorded while resolving it.

## Usage

``` r
facts_df(x = facts(), namespaces = NULL)
```

## Arguments

- x:

  A `zufax` object from
  [`facts()`](https://pedrobtz.github.io/zufax/reference/facts.md).

- namespaces:

  Namespaces to include. With `NULL`, all default namespaces plus any
  opt-in namespace already resolved in `x`.

## Value

A data frame with columns:

- `fact`: the fact name.

- `value`: a list-column of values (`NA` when not available).

- `status`: `"ok"`, `"not_applicable"`, `"unavailable"` or `"error"`.

- `source`: the files, commands, environment variables or URLs used.

- `resolver`: the id of the resolver that produced the value.

- `elapsed`: resolution time in seconds.

- `message`: why the status is not `"ok"`.

## Examples

``` r
facts_df(facts(), "cpu")
#>                   fact
#> 1            cpu.model
#> 2           cpu.vendor
#> 3            cpu.flags
#> 4        cpu.isa_level
#> 5     cpu.host.logical
#> 6    cpu.host.physical
#> 7     cpu.host.sockets
#> 8         cpu.affinity
#> 9             cpu.load
#> 10    cpu.cgroup.quota
#> 11   cpu.cgroup.cpuset
#> 12   cpu.cgroup.weight
#> 13 cpu.cgroup.pressure
#> 14       cpu.effective
#> 15 cpu.effective_exact
#>                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                         value
#> 1                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                             AMD EPYC 9V45 96-Core Processor
#> 2                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                         AMD
#> 3  fpu, vme, de, pse, tsc, msr, pae, mce, cx8, apic, sep, mtrr, pge, mca, cmov, pat, pse36, clflush, mmx, fxsr, sse, sse2, ht, syscall, nx, mmxext, fxsr_opt, pdpe1gb, rdtscp, lm, constant_tsc, rep_good, nopl, xtopology, tsc_reliable, nonstop_tsc, cpuid, extd_apicid, aperfmperf, tsc_known_freq, pni, pclmulqdq, ssse3, fma, cx16, pcid, sse4_1, sse4_2, x2apic, movbe, popcnt, aes, xsave, avx, f16c, rdrand, hypervisor, lahf_lm, cmp_legacy, svm, cr8_legacy, abm, sse4a, misalignsse, 3dnowprefetch, osvw, topoext, vmmcall, fsgsbase, bmi1, avx2, smep, bmi2, erms, invpcid, avx512f, avx512dq, rdseed, adx, smap, avx512ifma, clflushopt, clwb, avx512cd, sha_ni, avx512bw, avx512vl, xsaveopt, xsavec, xgetbv1, xsaves, user_shstk, avx_vnni, avx512_bf16, clzero, xsaveerptr, rdpru, arat, npt, nrip_save, tsc_scale, vmcb_clean, flushbyasid, decodeassists, pausefilter, pfthreshold, v_vmsave_vmload, avx512vbmi, umip, avx512_vbmi2, gfni, vaes, vpclmulqdq, avx512_vnni, avx512_bitalg, avx512_vpopcntdq, rdpid, fsrm, avx512_vp2intersect
#> 4                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                   x86-64-v4
#> 5                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                           4
#> 6                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                           2
#> 7                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                           1
#> 8                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                           4
#> 9                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            1.07, 0.52, 0.21
#> 10                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        Inf
#> 11                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                          4
#> 12                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        100
#> 13                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                       0, 0
#> 14                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                          4
#> 15                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                          4
#>    status
#> 1      ok
#> 2      ok
#> 3      ok
#> 4      ok
#> 5      ok
#> 6      ok
#> 7      ok
#> 8      ok
#> 9      ok
#> 10     ok
#> 11     ok
#> 12     ok
#> 13     ok
#> 14     ok
#> 15     ok
#>                                                                                                                                            source
#> 1                                                                                                                                   /proc/cpuinfo
#> 2                                                                                                                                   /proc/cpuinfo
#> 3                                                                                                                                   /proc/cpuinfo
#> 4                                                                                                                                   /proc/cpuinfo
#> 5                                                                                                                  /sys/devices/system/cpu/online
#> 6                                                                                                                                   /proc/cpuinfo
#> 7                                                                                                                                   /proc/cpuinfo
#> 8                                                                                                                               /proc/self/status
#> 9                                                                                                                                   /proc/loadavg
#> 10 /proc/self/cgroup; /proc/self/mountinfo; /sys/fs/cgroup/system.slice/hosted-compute-agent.service/cpu.max; /sys/fs/cgroup/system.slice/cpu.max
#> 11                        /proc/self/cgroup; /proc/self/mountinfo; /sys/fs/cgroup/system.slice/hosted-compute-agent.service/cpuset.cpus.effective
#> 12                                   /proc/self/cgroup; /proc/self/mountinfo; /sys/fs/cgroup/system.slice/hosted-compute-agent.service/cpu.weight
#> 13                                 /proc/self/cgroup; /proc/self/mountinfo; /sys/fs/cgroup/system.slice/hosted-compute-agent.service/cpu.pressure
#> 14                                                                                                                                           <NA>
#> 15                                                                                                                                           <NA>
#>               resolver elapsed message
#> 1            cpu.model   0.000    <NA>
#> 2           cpu.vendor   0.000    <NA>
#> 3            cpu.flags   0.000    <NA>
#> 4        cpu.isa_level   0.000    <NA>
#> 5     cpu.host.logical   0.000    <NA>
#> 6    cpu.host.physical   0.000    <NA>
#> 7     cpu.host.sockets   0.000    <NA>
#> 8         cpu.affinity   0.000    <NA>
#> 9             cpu.load   0.000    <NA>
#> 10    cpu.cgroup.quota   0.001    <NA>
#> 11   cpu.cgroup.cpuset   0.001    <NA>
#> 12   cpu.cgroup.weight   0.001    <NA>
#> 13 cpu.cgroup.pressure   0.000    <NA>
#> 14       cpu.effective   0.003    <NA>
#> 15 cpu.effective_exact   0.000    <NA>
```
