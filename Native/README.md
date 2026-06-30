# Native compatibility shim

This directory contains the small C++ extension compiled into `CZvec` on top
of the pinned Zvec v0.5.1 sources.

It exists for three API gaps in that release:

- the C API does not preserve element boundaries when reading binary arrays;
- packed Boolean arrays do not expose their logical element count;
- collection group-by execution is available in C++, but has no C execution
  function and collapses scalar group values in the tested Apple build.

`zvec-cmake-shim.patch` only adds the translation unit to upstream's C binding
target. The public ABI is declared in `zvec_swift_shim.h`; Swift code never
imports C++ types. Group-by compatibility uses the same ordered vector results
and the upstream 100,000-result query ceiling, then applies group limits in the
shim.

The upstream version and commit are pinned in
[`scripts/native-version.env`](../scripts/native-version.env). Revalidate this
shim before changing either value.
