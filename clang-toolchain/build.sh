# Reference: protonesso/crossdev (GitLab); iglunix/iglunix-autobuild (iglunix)

msg() {
echo ">> $@..."
}

err() {
echo ">>> ERROR: $@"
}

die() {
err "$@"
exit 1
}

if test "$1" = "--help"; then
	echo "Hanh Linux clang toolchain building script"
	echo "Requirements: clang, lld, llvm, libcxx, libcxxabi, libunwind,..."
fi

if ! command -v clang > /dev/null 2>&1; then
die "clang not found!"
fi

eval "$*"

if test -z "$host"; then
	host=$(clang -dumpmachine)
fi
if test -z "$p"; then
	core=1
else
	core=$(nproc)
fi

arch=x86_64
target=x86_64-linux-musl
llvm_arch=X86

workdir=$(pwd)
sysdir=$workdir/sysroot
srcdir=$workdir/src
sourcedir=$workdir/sources
toolchain=$workdir/toolchain

source $workdir/build.conf
export $USE_FLAGS

if test -z "$downloader"; then
	downloader="wget --no-check-certificate -nc"
fi
vmusl="1.2.2"
vllvm="13.0.0"
kver=5.15.16

eval LLVM_CPPFLAGS="-I$toolchain/include"
if test "$clean" = "yes"; then
rm -rf $sysdir $toolchain $srcdir
fi
mkdir -p $sysdir $srcdir $sourcedir $toolchain

msg Downloading neccessary files
cd $sourcedir
# No kernel download. 
eval $downloader https://musl.libc.org/releases/musl-$vmusl.tar.gz 
eval $downloader https://github.com/llvm/llvm-project/releases/download/llvmorg-$vllvm/compiler-rt-$vllvm.src.tar.xz
eval $downloader https://github.com/llvm/llvm-project/releases/download/llvmorg-$vllvm/llvm-$vllvm.src.tar.xz
eval $downloader https://github.com/llvm/llvm-project/releases/download/llvmorg-$vllvm/lld-$vllvm.src.tar.xz
eval $downloader https://github.com/llvm/llvm-project/releases/download/llvmorg-$vllvm/clang-$vllvm.src.tar.xz
eval $downloader https://github.com/llvm/llvm-project/releases/download/llvmorg-$vllvm/libunwind-$vllvm.src.tar.xz
eval $downloader https://github.com/llvm/llvm-project/releases/download/llvmorg-$vllvm/libcxx-$vllvm.src.tar.xz
eval $downloader https://github.com/llvm/llvm-project/releases/download/llvmorg-$vllvm/libcxxabi-$vllvm.src.tar.xz

if test -z "$no_unpack"; then
# All projects now need to be in a monopoly layout
msg Unpacking source code
cd $srcdir
tar -xf $sourcedir/llvm-$vllvm.src.tar.xz
mv llvm-$vllvm.src llvm
tar -xf $sourcedir/clang-$vllvm.src.tar.xz 
mv $srcdir/clang-$vllvm.src llvm/tools/clang
tar -xf $sourcedir/lld-$vllvm.src.tar.xz
mv $srcdir/lld-$vllvm.src llvm/tools/lld
tar -xf $sourcedir/compiler-rt-$vllvm.src.tar.xz
cp -r $srcdir/compiler-rt-$vllvm.src llvm/projects/compiler-rt
mv compiler-rt-$vllvm.src compiler-rt
tar -xf $sourcedir/libunwind-$vllvm.src.tar.xz
mv libunwind-$vllvm.src libunwind
tar -xf $sourcedir/libcxx-$vllvm.src.tar.xz
mv libcxx-$vllvm.src libcxx
cp -r libcxx llvm/projects/libcxx
tar -xf $sourcedir/libcxxabi-$vllvm.src.tar.xz
mv libcxxabi-$vllvm.src libcxxabi
cp -r libcxxabi llvm/projects/libcxxabi
tar -xf $sourcedir/musl-$vmusl.tar.gz
# tar -xf $sourcedir/linux-$kver.tar.xz
fi

if test -z "$no_libunwind"; then 
# Source: iglunix/iglunix-bootstrap/boot_libunwind.sh
msg Configuring libunwind
cd $srcdir/libunwind 
cmake -S . -B build -DCMAKE_BUILD_TYPE=MinSizeRel \
	-DCMAKE_C_COMPILER=clang \
	-DCMAKE_CXX_COMPILER=clang++ \
	-DCMAKE_C_FLAGS="$CFLAGS $UNWIND_FLAGS" \
	-DCMAKE_CXX_FLAGS="$CXXFLAGS $UNWIND_FLAGS" \
	-DCMAKE_INSTALL_PREFIX=$toolchain \
	-DLIBUNWIND_USE_COMPILER_RT=ON       \
	-Wno-dev -G "Ninja"
msg Building libunwind
cd build
ninja -j$core unwind || exit 1
msg Installing libunwind
ninja -j$core install-unwind || exit 1

cd ..
install -dm755 $toolchain/include/mach-o
# Install header to prevent failure with llvm
install -Dm755 include/mach-o/compact_unwind_encoding.h $toolchain/include/mach-o/compact_unwind_encoding.h
fi

if test -z "$no_llvm"; then
# Source: ataraxialinux/crossdev/packages/build_llvm()
# Build a complete llvm tree
msg Configuring LLVM tree 
cd $srcdir/llvm
cmake -S . -B build \
	-DCMAKE_INSTALL_PREFIX="$toolchain" \
	-DCMAKE_BUILD_TYPE=MinSizeRel \
	-DCMAKE_C_FLAGS="$CFLAGS $LLVM_CPPFLAGS" \
	-DCMAKE_CXX_FLAGS="$CXXFLAGS $LLVM_CPPFLAGS" \
	-DLLVM_DEFAULT_TARGET_TRIPLE=$target \
	-DLLVM_ENABLE_LLD=ON \
	-DLLVM_HOST_TRIPLE=$host \
	-DLLVM_TARGET_ARCH=$arch \
	-DLLVM_TARGETS_TO_BUILD=$llvm_arch \
	-DLLVM_INCLUDE_DOCS=OFF \
	-DLLVM_INCLUDE_EXAMPLES=OFF \
	-DLLVM_INCLUDE_TESTS=OFF \
	-DLLVM_BUILD_DOCS=OFF \
	-DCLANG_DEFAULT_CXX_STDLIB=libc++ \
	-DCLANG_DEFAULT_LINKER=ld.lld \
	-DCLANG_DEFAULT_OBJCOPY=llvm-objcopy \
	-DCLANG_DEFAULT_RTLIB=compiler-rt \
	-DCLANG_DEFAULT_UNWINDLIB=libunwind \
	-DCLANG_INCLUDE_TESTS=OFF \
	-DCLANG_VENDOR=Hanh \
	-DCOMPILER_RT_BUILD_LIBFUZZER=OFF \
	-DCOMPILER_RT_BUILD_MEMPROF=OFF \
	-DCOMPILER_RT_BUILD_PROFILE=OFF \
	-DCOMPILER_RT_BUILD_SANITIZERS=OFF \
	-DCOMPILER_RT_BUILD_XRAY=OFF \
	-DCOMPILER_RT_DEFAULT_TARGET_TRIPLE=$target \
	-DENABLE_LINKER_BUILD_ID=ON \
	-DDEFAULT_SYSROOT=$sysdir \
	-Wno-dev -G "Ninja"
cd build
msg Building LLVM tree
ninja -j$core || exit 1
msg Installing LLVM tree
ninja -j$core install || exit 1
fi 

if test -z "$no_llvm_bin"; then
# Source: ataraxialinux/crossdev/packages/build_llvm()
msg Create important binaries
cd $toolchain/bin

for i in clang clang++ clang-cpp; do
	cp -v clang-13 $target-$i
done
for i in ar dwp nm objcopy objdump size strings symbolizer cxxfilt cov ar readobj; do
	cp -v llvm-$i $target-llvm-$i
done
cp -v llvm-ar $target-llvm-ranlib
cp -v llvm-objcopy $target-llvm-strip
cp -v lld $target-ld.lld
cp -v llvm-readobj $target-llvm-readelf
fi 

if test -z "$no_musl" ; then
# Source: iglunix/iglunix-bootstrap/boot_musl.sh
export ORG_CFLAGS="$CFLAGS"
export CFLAGS="$CFLAGS --ld-path=$toolchain/bin/$target-ld.lld $CPRT_FLAGS \
	-L$toolchain/lib -L$toolchain/lib/clang/$vllvm/lib/linux/ -lclang_rt.builtins-x86_64" # prevent missing symbols

msg Configuring musl
cd $srcdir/musl-$vmusl/
CC=$toolchain/bin/$target-clang  \
	./configure --prefix=/usr \
	--enable-wrapper=no || exit 1
msg Building musl
make -j$core || exit 1
msg Installing musl
make -j$core DESTDIR=$sysdir install || exit 1

cd $sysdir
rm -rf $sysdir/lib
ln -sf usr/lib $sysdir/lib

cd $sysdir/usr/lib/
for x in ld-musl-$arch.so.1 libc.so.6 libcrypt.so.1 libdl.so.2 libm.so.6 libpthread.so.0 libresolv.so.2; do
	ln -sr libc.so $x || exit 1
done

mkdir -p $sysdir/usr/bin
ln -sf ../lib/libc.so $sysdir/usr/bin/ldd
export CFLAGS="$ORG_CFLAGS"
fi

no_kernel_header=yes
if test -z "$no_kernel_headers"; then 
cd $srcdir/linux-$kver
msg Compiling linux-headers
make mrproper
make ARCH=$arch -j$core headers || exit 1
find usr/include -name '.*' -delete
rm usr/include/Makefile
msg Installing linux-headers
cp -rv usr/include/* $toolchain/include/
fi

# Stage 2 compiler-rt not working 
no_stage_compiler_rt=yes 
if test -z "$no_stage_compiler_rt" ; then 
# Source: ataraxialinux/crossdev/packages/build_compiler-rt()
msg Configuring Stage 2 Compiler-RT
cd $srcdir/compiler-rt
cmake -S . -B stage2_build \
	-DCMAKE_INSTALL_PREFIX="$toolchain" \
	-DCMAKE_BUILD_TYPE=MinSizeRel \
	-DCMAKE_C_COMPILER="$toolchain/bin/$target-clang" \
	-DCMAKE_CXX_COMPILER="$toolchain/bin/$target-clang++" \
	-DCMAKE_AR="$toolchain/bin/$target-llvm-ar"     \
	-DCMAKE_LINKER="$toolchain/bin/$target-ld.lld"  \
	-DCMAKE_NM="$toolchain/bin/$target-llvm-nm"     \
	-DCMAKE_OBJCOPY="$toolchain/bin/$target-llvm-objcopy" \
	-DCMAKE_OBJDUMP="$toolchain/bin/$target-llvm-objdump" \
	-DCMAKE_RANLIB="$toolchain/bin/$target-llvm-ranlib"   \
	-DCMAKE_READELF="$toolchain/bin/$target-llvm-readelf" \
	-DCMAKE_STRIP="$toolchain/bin/$target-llvm-strip"     \
	-DCMAKE_FIND_ROOT_PATH="$sysdir" \
	-DCMAKE_FIND_ROOT_PATH_MODE_PROGRAM=NEVER \
	-DCMAKE_FIND_ROOT_PATH_MODE_LIBRARY=ONLY \
	-DCMAKE_FIND_ROOT_PATH_MODE_INCLUDE=ONLY \
	-DCOMPILER_RT_BUILD_LIBFUZZER=OFF \
	-DCOMPILER_RT_BUILD_MEMPROF=OFF \
	-DCOMPILER_RT_BUILD_PROFILE=OFF \
	-DCOMPILER_RT_BUILD_SANITIZERS=OFF \
	-DCOMPILER_RT_BUILD_XRAY=OFF \
	-DCOMPILER_RT_USE_BUILTINS_LIBRARY=ON \
	-DCOMPILER_RT_DEFAULT_TARGET_TRIPLE="$target" \
	-Wno-dev -G "Ninja"
cd stage2_build 
msg Building Stage 2 Compiler-RT
ninja -j$core || exit 1
msg Installing Stage 2 Compiler-RT
ninja -j$core install || exit 1
fi
