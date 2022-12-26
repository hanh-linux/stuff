# Reference: protonesso/crossdev (GitLab); iglunix/iglunix-bootstrap (GitHub); glaucuslinux/mussel (GitHub)
# https://git.sr.ht/~protonesso/ataraxia/tree/main/item/tools/build-toolchain

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

eval "$*"

source $(pwd)/build.conf
export $USE_FLAGS

if test -n "$help"; then
	echo "Hanh Linux clang toolchain building script (for x86_64)"
	echo "- Requirements:" 
	echo "     + libcxx, libcxxabi, libunwind"
	echo "     + clang, lld, llvm"
	echo "     + ninja, cmake, make, sh, base packages" 
	echo "- Build step: "
	echo "-----------------------------------------------------------"
	echo " Step                          - Controlling var=value     "
	echo "-----------------------------------------------------------"
	echo "     Clean                     -    if clean=yes           "
	echo "     Download sources          - no if no_download=yes     "
	echo "     Unpack sources            - no if no_unpack=yes       "
	echo "     Build LLVM tree(1)        - no if no_llvm=yes         "
	echo "     Create cross binaries     - no if no_llvm_bin=yes     "
	echo "     Install musl headers      - no if no_musl_headers=yes "
	echo "     Install kernel headers    - no if no_kern_headers=yes "
	echo "     Build compiler-rt         - no if no_compiler_rt=yes  "
	echo "     Build musl libc           - no if no_musl=yes         "
	echo "     Build libunwind           - no if no_unwind=yes       "
	echo "     Build libcxx(2)           - no if no_libcxx=yes       "
	echo "-----------------------------------------------------------"
	echo "(1) : LLVM tree contains: LLVM, Clang, LLD                 "
	echo "(2) : Build static libcxxabi without installing it         "
	echo "- Controlling variables: "
	echo "p=<non-empty value>         parallel build"
	echo "host=<non-empty value>      set host triple"
	echo "NINJA=<path to ninja>       set ninja builder"
	echo "MK=<path to make>           set make builder"
	echo "See build.conf for more values"
	echo "Source"
	echo "- https://gitlab.com/ataraxialinux/crossdev"
	echo "- https://github.com/iglunix/iglunix-bootstrap"
	echo "- https://github.com/firasuke/mussel"
	echo "- https://git.sr.ht/~protonesso/ataraxia/tree/main/item/tools/build-toolchain"
	exit 0
fi

test -z "$downloader" && downloader="wget --no-check-certificate -nc"
test -z $MK           && MK=make
test -z $NINJA        && NINJA=ninja
bin_download=$(echo $downloader | cut -d " " -f 1)

for cmd in clang llvm-ar ld.lld $NINJA $MK $bin_download; do 
if ! command -v $cmd > /dev/null 2>&1; then
test "$cmd" = "llvm-ar" && cmd=LLVM
die "$cmd not found!"
fi
done

for library in libc++.so libc++abi.so libunwind.so; do 
if test -z $(whereis $library | cut -d " " -f 2); then
die "$library not found"
fi
done

if test -z "$host"; then
	host=$(clang -dumpmachine)
fi

if test -z "$core"; then
	if test -z "$p"; then
		parallel=no
		core=1
	else
		core=$(nproc)
		parallel="yes (Number of cores: $core)"
	fi
else
	test "$core" -lt 1 && die "Core number must be above than 1"
	if test "$core" = 1; then 
		parallel=no 
	else
		parallel="yes (Number of cores: $core)"
	fi
fi

arch=x86_64
target=x86_64-linux-musl
llvm_arch=X86

workdir=$(pwd)
sysdir=$workdir/sysroot
srcdir=$workdir/src
sourcedir=$workdir/sources
toolchain=$workdir/toolchain

TOOLCHAIN_CC="$toolchain/bin/$target-clang"
TOOLCHAIN_CXX="$toolchain/bin/$target-clangxx"
TOOLCHAIN_AR="$toolchain/bin/$target-llvm-ar"
TOOLCHAIN_NM="$toolchain/bin/$target-llvm-nm"
TOOLCHAIN_RANLIB="$toolchain/bin/$target-llvm-ranlib"

ORG_CFLAGS="$CFLAGS"
ORG_CXXFLAGS="$CXXFLAGS"
ORG_LDFLAGS="$LDFLAGS"

vmusl="1.2.3"
vllvm="15.0.6"
vllvm_major="$(echo $vllvm | cut -d '.' -f1)"
kern_headers="linux-headers-5.19.1.tar.xz"

test -n "$no_download"            && download=no      || download=yes
test -n "$no_unpack"              && unpack=no        || unpack=yes
test -n "$no_llvm"                && llvm=no          || llvm=yes
test -n "$no_llvm_bin"            && llvm_bin=no      || llvm_bin=yes
test -n "$no_musl_headers"        && musl_headers=no  || musl_headers=yes
test -n "$no_kern_headers"        && kern_headers=no  || kern_headers=yes
test -n "$no_compiler_rt"         && compiler_rt=no   || compiler_rt=yes
test -n "$no_musl"                && musl=no          || musl=yes
test -n "$no_unwind"              && unwind=no        || unwind=yes
test -n "$no_libcxx"              && libcxx=no        || libcxx=yes
test -z "$clean"                  && clean_build=no   || clean_build=yes

echo "Printing summary"
echo "=Build steps==========================================="
echo "Clean build               : $clean_build"
echo "Download sources          : $download"
echo "Unpack sources            : $unpack"
echo "Build LLVM tree           : $llvm"
echo "Create cross binaries     : $llvm_bin"
echo "Install musl headers      : $musl_headers"
echo "Install kernel headers    : $kern_headers"
echo "Build musl libc           : $musl"
echo "Build libunwind           : $unwind"
echo "Build libcxx              : $libcxx"
echo "=Compilation tools====================================="
echo "C compiler                : $CC "
echo "C++ compiler              : $CXX"
echo "Linker                    : $LD "
echo "AR                        : $AR "
echo "RANLIB                    : $RANLIB"
echo "NM                        : $NM"
echo "STRIP                     : $STRIP" 
echo "OBJCOPY                   : $OBJCOPY" 
echo "OBJDUMP                   : $OBJDUMP"
echo "READELF                   : $READELF"
echo "SIZE                      : $SIZE"
echo "=Compilation flags====================================="
echo "Host triple               : $host"
echo "Target triple             : $target"
echo "Parallel build            : $parallel"  
echo "CFLAGS                    "
echo "       $CFLAGS"
echo "CXXFLAGS                  "
echo "       $CXXFLAGS"
echo "LDFLAGS                   "
echo "       $LDFLAGS"
echo "=Other tools==========================================="
echo "Download command          : $downloader"
echo "Ninja builder             : $NINJA"
echo "Makefile builder          : $MK"
sleep 5 

if test -n "$clean"; then
rm -rf $sysdir $toolchain $srcdir
fi
mkdir -p $sysdir $srcdir $sourcedir $toolchain

if test -z "$no_download"; then
msg Downloading source code
cd $sourcedir
# No kernel download. 
eval $downloader https://musl.libc.org/releases/musl-$vmusl.tar.gz
# Too lazy to download specified parts 
eval $downloader https://github.com/llvm/llvm-project/releases/download/llvmorg-$vllvm/llvm-project-$vllvm.src.tar.xz
fi

if test -z "$no_unpack"; then
# All projects now need to be in a monopoly layout
msg Unpacking source code
cd $srcdir
tar -xf $sourcedir/llvm-project-$vllvm.src.tar.xz
mv $srcdir/llvm-project-$vllvm.src $srcdir/llvm-project
tar -xf $sourcedir/musl-$vmusl.tar.gz
fi

if test -z "$no_llvm"; then
# Source: ataraxialinux/crossdev/packages/build_llvm()
# Build a working LLVM tree
msg Configuring LLVM tree 
cd $srcdir/llvm-project
export CFLAGS="$CFLAGS -I$toolchain/include"
export CXXFLAGS="$CXXFLAGS -I$toolchain/include"
# Prevent build failure with OS using non-GNU libunwind (instead of LLVM)
install -dm755 $toolchain/include/mach-o
install -Dm644 $srcdir/llvm-project/libunwind/include/mach-o/compact_unwind_encoding.h $toolchain/include/mach-o/
cmake -S llvm/ -B build \
	-DLLVM_INCLUDE_BENCHMARKS=OFF \
	-DLIBCXX_INCLUDE_BENCHMARKS=OFF \
	-DCMAKE_INSTALL_PREFIX="$toolchain" \
	-DCMAKE_BUILD_TYPE=Release \
	-DLLVM_DEFAULT_TARGET_TRIPLE=$target \
	-DLLVM_HOST_TRIPLE=$host \
	-DLLVM_TARGET_ARCH=$arch \
	-DLLVM_TARGETS_TO_BUILD=$llvm_arch \
	-DLLVM_INCLUDE_DOCS=OFF \
	-DLLVM_INCLUDE_EXAMPLES=OFF \
	-DLLVM_INCLUDE_TESTS=OFF \
	-DLLVM_ENABLE_OCAMLDOC=OFF \
        -DLLVM_ENABLE_SPHINX=OFF \
        -DLLVM_ENABLE_DOXYGEN=OFF \
        -DLLVM_ENABLE_BINDINGS=OFF \
	-DLLVM_BUILD_DOCS=OFF \
	-DLLVM_ENABLE_LLD=ON \
	-DLLVM_ENABLE_PROJECTS="clang;lld" \
	-DCLANG_DEFAULT_CXX_STDLIB=libc++ \
	-DCLANG_DEFAULT_LINKER=ld.lld \
	-DCLANG_DEFAULT_OBJCOPY=llvm-objcopy \
	-DCLANG_DEFAULT_RTLIB=compiler-rt \
	-DCLANG_DEFAULT_UNWINDLIB=libunwind \
	-DCLANG_INCLUDE_TESTS=OFF \
	-DCLANG_VENDOR=Hanh \
	-DENABLE_LINKER_BUILD_ID=ON \
	-DDEFAULT_SYSROOT=$sysdir \
	-DLIBUNWIND_USE_COMPILER_RT=ON \
       	-Wno-dev -G "Ninja" || die Failed to configure LLVM tree
cd $srcdir/llvm-project/build 
msg Building LLVM compiler
eval $NINJA -j$core || die Failed to build LLVM tree
msg Installing LLVM compiler
eval $NINJA -j$core install || die Failed to install LLVM tree
export CFLAGS="$ORG_CFLAGS"
export CXXFLAGS="$ORG_CXXFLAGS"
fi

if test -z "$no_llvm_bin"; then
# Source: ataraxialinux/crossdev/packages/build_llvm()
msg Create important binaries
cd $toolchain/bin

for i in clang clang++ clang-cpp; do
	cp -v clang-$vllvm_major $target-$i || die Failed to copy $target-$i
done

echo "$toolchain/bin/$target-clang++" '-D_LIBCPP_HAS_MUSL_LIBC $*' > $toolchain/bin/$target-clangxx
chmod 755 $toolchain/bin/$target-clangxx

for i in as dwp nm objcopy objdump size strings symbolizer cxxfilt cov ar readobj; do
	cp -v llvm-$i $target-llvm-$i || die Failed to copy $target-llvm-$i
done
cp -v llvm-ar $target-llvm-ranlib || die Failed to copy $target-llvm-ranlib
cp -v llvm-objcopy $target-llvm-strip || die Failed to copy $target-llvm-strip
cp -v lld $target-ld.lld || die Failed to copy $target-ld.lld
cp -v llvm-readobj $target-llvm-readelf || die Failed to copy $target-llvm-readelf
fi 


if test -z "$no_musl_headers"; then
# Source: glaucuslinux/mussel/build.sh	
cd $srcdir/musl-$vmusl
msg Installing musl-headers
eval $MK -j$core \
	DESTDIR=$sysdir \
	prefix=/usr \
	ARCH=$arch \
	install-headers || die Failed to install musl-headers
fi

if test -z "$no_kern_headers"; then
cd $workdir
msg Installing kernel headers 
tar -C $toolchain/include -xf $kern_headers
fi

if test -z "$no_compiler_rt"; then
# Source: ataraxialinux/build-toolchain/build_compiler_rt()
export CFLAGS="$CFLAGS -fPIC"
export CXXFLAGS="$CXXFLAGS -fPIC"

cd $srcdir/llvm-project/compiler-rt/
msg Configuring compiler-rt
	cmake \
		-S "." \
		-B build -G Ninja \
		-DCMAKE_CROSSCOMPILING=ON \
		-DCMAKE_INSTALL_PREFIX="$toolchain" \
		-DCMAKE_BUILD_TYPE=MinSizeRel \
		-DCMAKE_ASM_COMPILER="$TOOLCHAIN_CC" \
		-DCMAKE_C_COMPILER="$TOOLCHAIN_CC" \
		-DCMAKE_CXX_COMPILER="$TOOLCHAIN_CXX" \
		-DCMAKE_AR="$TOOLCHAIN_AR" \
		-DCMAKE_NM="$TOOLCHAIN_NM" \
		-DCMAKE_RANLIB="$TOOLCHAIN_RANLIB" \
		-DCMAKE_TRY_COMPILE_TARGET_TYPE=STATIC_LIBRARY \
		-DCOMPILER_RT_INSTALL_PATH="$toolchain/lib/clang/$vllvm" \
		-DCOMPILER_RT_BUILD_BUILTINS=ON \
		-DCOMPILER_RT_BUILD_CRT=ON \
		-DCOMPILER_RT_BUILD_LIBFUZZER=OFF \
		-DCOMPILER_RT_BUILD_MEMPROF=OFF \
		-DCOMPILER_RT_BUILD_ORC=OFF \
		-DCOMPILER_RT_BUILD_PROFILE=ON \
		-DCOMPILER_RT_BUILD_SANITIZERS=OFF \
		-DCOMPILER_RT_DEFAULT_TARGET_TRIPLE=$target \
		-DCOMPILER_RT_DEFAULT_TARGET_ONLY=OFF \
		-DCOMPILER_RT_BUILD_XRAY=OFF \
		-Wno-dev || die Failed to configure compiler-rt
msg Building compiler-rt 
cd build
eval $NINJA -j$core || die Failed to build compiler-rt
msg Installing compiler-rt 
eval $NINJA -j$core install || die Failed to install compiler-rt
export CFLAGS="$ORG_CFLAGS"
export CXXFLAGS="$ORG_CXXFLAGS"
fi

if test -z "$no_musl" ; then
# Source: iglunix/iglunix-bootstrap/boot_musl.sh
export CFLAGS="$CFLAGS --ld-path=$toolchain/bin/$target-ld.lld \
	-lclang_rt.builtins-x86_64 \
	-L$toolchain/lib/clang/$vllvm/lib/linux/" # prevent missing symbols

msg Configuring musl
cd $srcdir/musl-$vmusl/
CC=$TOOLCHAIN_CC \
	ARCH=$arch \
	./configure --prefix=/usr \
	--enable-wrapper=no || die Failed to configure musl
msg Building musl
eval $MK -j$core || die Failed to build musl
msg Installing musl
eval $MK -j$core DESTDIR=$sysdir install || die Failed to install musl 

cd $sysdir
rm -rf $sysdir/lib
ln -sf usr/lib $sysdir/lib

cd $sysdir/usr/lib/
for x in ld-musl-$arch.so.1 libc.so.6 libcrypt.so.1 libdl.so.2 libm.so.6 libpthread.so.0 libresolv.so.2; do
	ln -srf libc.so $x || die Failed to create symlink $x
done

mkdir -p $sysdir/usr/bin
ln -sf ../lib/libc.so $sysdir/usr/bin/ldd || die Failed to create symlink ldd
export CFLAGS="$ORG_CFLAGS"
fi

if test -z "$no_unwind"; then
export CFLAGS="$CFLAGS -fPIC --ld-path=$toolchain/bin/$target-ld.lld"
export CXXFLAGS="$CXXFLAGS -fPIC --ld-path=$toolchain/bin/$target-ld.lld"
cd $srcdir/llvm-project/
msg Configuring libunwind
	cmake \
		-S "$srcdir/llvm-project/runtimes" \
		-B build-unwind -G Ninja \
		-DCMAKE_CROSSCOMPILING=ON \
		-DCMAKE_INSTALL_PREFIX="/usr" \
		-DCMAKE_BUILD_TYPE=MinSizeRel \
		-DCMAKE_ASM_COMPILER="$TOOLCHAIN_CC" \
		-DCMAKE_C_COMPILER="$TOOLCHAIN_CC" \
		-DCMAKE_CXX_COMPILER="$TOOLCHAIN_CXX" \
		-DCMAKE_AR="$TOOLCHAIN_AR" \
		-DCMAKE_NM="$TOOLCHAIN_NM" \
		-DCMAKE_RANLIB="$TOOLCHAIN_RANLIB" \
		-DCMAKE_TRY_COMPILE_TARGET_TYPE=STATIC_LIBRARY \
		-DLLVM_ENABLE_RUNTIMES="libunwind" \
		-DLIBUNWIND_ENABLE_ASSERTIONS=ON \
		-DLIBUNWIND_ENABLE_CROSS_UNWINDING=ON \
		-DLIBUNWIND_ENABLE_SHARED=ON \
		-DLIBUNWIND_ENABLE_STATIC=ON \
		-DLIBUNWIND_INSTALL_HEADERS=ON \
		-DLIBUNWIND_USE_COMPILER_RT=ON \
		-Wno-dev || die Failed to configure libunwind
msg Building libunwind
cd $srcdir/llvm-project/build-unwind/ 
eval $NINJA -j$core || die Failed to build libunwind
msg Installing libunwind 
eval DESTDIR=$sysdir $NINJA -j$core install || die Failed to install libunwind
ln -sf libunwind.so.1.0 $sysdir/usr/lib/libunwind_shared.so
export CFLAGS="$ORG_CFLAGS"
export CXXFLAGS="$ORG_CXXFLAGS"
fi

if test -z "$no_libcxx"; then
export CFLAGS="$CFLAGS -fPIC --ld-path=$toolchain/bin/$target-ld.lld -I$toolchain/include"
export CXXFLAGS="$CXXFLAGS -fPIC --ld-path=$toolchain/bin/$target-ld.lld -I$toolchain/include"
cd $srcdir/llvm-project/ 
# musl libc doesn't provide cxa_thread_atexit_impl() support
msg Configuring libcxx
	cmake \
		-S "$srcdir/llvm-project/runtimes" \
		-B build-cxx -G Ninja \
		-DLLVM_INCLUDE_BENCHMARKS=OFF \
		-DCMAKE_CROSSCOMPILING=ON \
		-DCMAKE_INSTALL_PREFIX="/usr" \
		-DCMAKE_BUILD_TYPE=MinSizeRel \
		-DCMAKE_ASM_COMPILER="$TOOLCHAIN_CC" \
		-DCMAKE_C_COMPILER="$TOOLCHAIN_CC" \
		-DCMAKE_CXX_COMPILER="$TOOLCHAIN_CXX" \
		-DCMAKE_AR="$TOOLCHAIN_AR" \
		-DCMAKE_NM="$TOOLCHAIN_NM" \
		-DCMAKE_RANLIB="$TOOLCHAIN_RANLIB" \
		-DCMAKE_TRY_COMPILE_TARGET_TYPE=STATIC_LIBRARY \
		-DLLVM_ENABLE_RUNTIMES="libcxx;libcxxabi" \
		-DLIBCXX_CXX_ABI="libcxxabi" \
		-DLIBCXX_ENABLE_ASSERTIONS=ON \
		-DLIBCXX_ENABLE_SHARED=ON \
		-DLIBCXX_ENABLE_STATIC=ON \
		-DLIBCXX_ENABLE_STATIC_ABI_LIBRARY=ON \
		-DLIBCXX_HAS_ATOMIC_LIB=OFF \
		-DLIBCXX_USE_COMPILER_RT=ON \
		-DLIBCXX_HAS_MUSL_LIBC=ON \
		-DLIBCXXABI_ENABLE_ASSERTIONS=ON \
		-DLIBCXXABI_ENABLE_SHARED=OFF \
		-DLIBCXXABI_ENABLE_STATIC=ON \
		-DLIBCXXABI_INSTALL_LIBRARY=OFF \
		-DLIBCXXABI_USE_COMPILER_RT=ON \
		-DLIBCXXABI_USE_LLVM_UNWINDER=ON \
		-DLIBCXXABI_HAS_CXA_THREAD_ATEXIT_IMPL=OFF \
		-Wno-dev || die Failed to configure libcxx
cd build-cxx
msg Building libcxx
eval $NINJA -j$core || die Failed to build libcxx
msg Installing libcxx 
eval DESTDIR=$sysdir $NINJA -j$core install || die Failed to install libcxx 
export CFLAGS="$ORG_CFLAGS"
export CXXFLAGS="$ORG_CXXFLAGS"
fi
