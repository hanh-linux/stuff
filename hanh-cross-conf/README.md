## Build instructions 
- Combine this with clang-toolchain script or an another cross toolchain
- Link the exact path of toolchain ld-\* to /lib/ (or the directory linked to /lib) (just for different libc, if the same then we can skip this step) 
- Compile and install hanh-linux/pachanh-new to cross-compiler directory (using host compiler), then change `sysroot=<path to toolchain sysroot>` in config 
- Create `<sysroot>/var/lib/pachanh/{remote,system}/` 
- Link to toolchain libgcc,libstdc++/libcxx,libcxxabi,libunwind (-L$toolchain/lib)
- Compile and install libunwind, libcxx, libcxxabi to system (if using Clang/LLVM); install libgcc, libstdc++ if using GCC/Binutils 
- Remove -L$toolchain/lib to use system runtime libraries 
