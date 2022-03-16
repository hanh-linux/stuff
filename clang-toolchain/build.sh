# Reference: protonesso/crossdev (GitLab); iglunix/iglunix-bootstrap (iglunix)

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
	echo "     Build compiler-rt         - no if no_compiler_rt=yes  "
	echo "     Build libunwind           - no if no_libunwind=yes    "
	echo "     Build libcxxabi           - no if no_libcxxabi=yes    "
	echo "     Build LLVM tree*          - no if no_llvm=yes         "
	echo "     Create cross binaries     - no if no_llvm_bin=yes     "
	echo "     Build Musl libc           - no if no_musl=yes         "
	echo "-----------------------------------------------------------"
	echo "*: LLVM tree contains: LLVM, Clang, LLD, libc++"
	echo "- Controlling variables: "
	echo "p=<non-empty value>         parallel build"
	echo "host=<non-empty value>      set host triple"
	echo "NINJA=<path to ninja>       set ninja builder"
	echo "MK=<path to make>           set make builder"
	echo "See build.conf for more values"
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

vmusl="1.2.2"
vllvm="13.0.0"

test -n "$no_download"     && download=no      || download=yes
test -n "$no_unpack"       && unpack=no        || unpack=yes
test -n "$no_compiler_rt"  && compiler_rt=no   || compiler_rt=yes
test -n "$no_libunwind"    && unwind=no        || unwind=yes
test -n "$no_libcxxabi"    && libcxxabi=no     || libcxxabi=yes
test -n "$no_llvm"         && llvm=no          || llvm=yes
test -n "$no_llvm_bin"     && llvm_bin=no      || llvm_bin=yes
test -n "$no_musl"         && musl=no          || musl=yes
test -z "$clean"           && clean_build=no   || clean_build=yes

echo "Printing summary"
echo "=Build steps==========================================="
echo "Clean build               : $clean_build"
echo "Download sources          : $download"
echo "Unpack sources            : $unpack"
echo "Build compiler-rt         : $compiler_rt"
echo "Build libunwind           : $unwind"
echo "Build libcxxabi           : $libcxxabi" 
echo "Build LLVM tree           : $llvm "
echo "Create cross binaries     : $llvm_bin"
echo "Build Musl libc           : $musl "
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


eval LLVM_CPPFLAGS="-I$toolchain/include"
if test -n "$clean"; then
rm -rf $sysdir $toolchain $srcdir
fi
mkdir -p $sysdir $srcdir $sourcedir $toolchain

if test -z "$no_download"; then
msg Downloading source code
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
fi

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
tar -xf $sourcedir/musl-$vmusl.tar.gz
fi

if test -z "$no_compiler_rt"; then 
msg Configuring compiler-rt
cd $srcdir/compiler-rt
cmake -S . -B build \
	-DCMAKE_INSTALL_PREFIX=$toolchain \
	-DCOMPILER_RT_BUILD_BUILTINS=ON \
	-DCOMPILER_RT_BUILD_LIBFUZZER=OFF \
	-DCOMPILER_RT_INCLUDE_TESTS=OFF \
	-DCOMPILER_RT_BUILD_MEMPROF=OFF \
	-DCOMPILER_RT_BUILD_PROFILE=OFF \
	-DCOMPILER_RT_BUILD_SANITIZERS=OFF \
	-DCOMPILER_RT_BUILD_XRAY=OFF \
	-DCOMPILER_RT_DEFAULT_TARGET_TRIPLE=$target \
	-DCOMPILER_RT_DEFAULT_TARGET_ONLY=OFF  \
	-DCOMPILER_RT_USE_BUILTINS_LIBRARY=ON \
	-Wno-dev -G "Ninja"
msg Building compiler-rt
cd build
ninja -j$core || die Failed to build compiler-rt
msg Installing compiler-rt 
ninja -j$core install || die Failed to install compiler-rt
fi

if test -z "$no_libunwind"; then 
# Source: iglunix/iglunix-bootstrap/boot_libunwind.sh
msg Configuring libunwind
cd $srcdir/libunwind 
cmake -S . -B build -DCMAKE_BUILD_TYPE=MinSizeRel \
	-DCMAKE_INSTALL_PREFIX=$toolchain \
	-DLIBUNWIND_USE_COMPILER_RT=ON       \
	-Wno-dev -G "Ninja" || die Failed to configure libunwind
msg Building libunwind
cd build
eval $NINJA -j$core unwind || die Failed to build libunwind
msg Installing libunwind
eval $NINJA -j$core install-unwind || die Failed to install libunwind

cd ..
install -dm755 $toolchain/include/mach-o || die Failed to install libunwind
# Install header to prevent failure with llvm
install -Dm755 include/mach-o/compact_unwind_encoding.h $toolchain/include/mach-o/compact_unwind_encoding.h || die Failed to install libunwind
fi

if test -z "$no_libcxxabi"; then
msg Configuring libcxxabi 
cd $srcdir/libcxxabi
cmake -S . -B build \
	-DCMAKE_INSTALL_PREFIX=$toolchain \
	-DLIBCXXABI_USE_COMPILER_RT=ON \
	-DLIBCXXABI_USE_LLVM_UNWINDER=ON \
	-DLIBCXXABI_STATICALLY_LINK_UNWINDER_IN_SHARED_LIBRARY=YES \
	-Wno-dev -G "Ninja" || die Failed to configure libcxxabi
msg Building libcxxabi
cd build 
eval $NINJA -j$core || die Failed to build libcxxabi
msg Installing libcxxabi 
eval $NINJA -j$core install || die Failed to install libcxxabi
fi

if test -z "$no_llvm"; then
# Source: ataraxialinux/crossdev/packages/build_llvm()
# and iglunix/iglunix-bootstrap/boot-libcxx.sh
# Build a complete llvm tree
msg Configuring LLVM tree 
cd $srcdir/llvm
cmake -S . -B build \
	-DCMAKE_INSTALL_PREFIX="$toolchain" \
	-DCMAKE_BUILD_TYPE=MinSizeRel \
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
	-DLIBCXX_HAS_MUSL_LIBC=ON \
	-DLIBCXX_USE_COMPILER_RT=ON \
	-DLIBCXX_CXX_ABI=ON \
	-DLIBCXX_HAS_ATOMIC_LIB=OFF \
	-DLIBCXX_STATICALLY_LINK_ABI_IN_SHARED_LIBRARY=ON \
	-DLIBCXX_STATICALLY_LINK_ABI_IN_STATIC_LIBRARY=ON \
	-DLIBCXX_ABI_LIBRARY_PATH=$toolchain/lib \
	-DLIBCXXABI_USE_LLVM_UNWINDER=ON \
	-DLIBCXXABI_USE_COMPILER_RT=ON \
	-DLIBCXXABI_STATICALLY_LINK_UNWINDER_IN_SHARED_LIBRARY=YES \
	-DENABLE_LINKER_BUILD_ID=ON \
	-DDEFAULT_SYSROOT=$sysdir \
	-Wno-dev -G "Ninja" || die Failed to configure LLVM tree
cd build
msg Building LLVM tree
eval $NINJA -j$core || die Failed to build LLVM tree
msg Installing LLVM tree
eval $NINJA -j$core install || die Failed to install LLVM tree
fi 

if test -z "$no_llvm_bin"; then
# Source: ataraxialinux/crossdev/packages/build_llvm()
msg Create important binaries
cd $toolchain/bin

for i in clang clang++ clang-cpp; do
	cp -v clang-13 $target-$i || die Failed to copy $target-$i
done
for i in ar as dwp nm objcopy objdump size strings symbolizer cxxfilt cov ar readobj; do
	cp -v llvm-$i $target-llvm-$i || die Failed to copy $target-llvm-$i
done
cp -v llvm-ar $target-llvm-ranlib || die Failed to copy $target-llvm-ranlib
cp -v llvm-objcopy $target-llvm-strip || die Failed to copy $target-llvm-strip
cp -v lld $target-ld.lld || die Failed to copy $target-ld.lld
cp -v llvm-readobj $target-llvm-readelf || die Failed to copy $target-llvm-readelf
fi 

if test -z "$no_musl" ; then
# Source: iglunix/iglunix-bootstrap/boot_musl.sh
export ORG_CFLAGS="$CFLAGS"
export CFLAGS="$CFLAGS --ld-path=$toolchain/bin/$target-ld.lld \
	-L$toolchain/lib -L$toolchain/lib/clang/$vllvm/lib/linux/ -lclang_rt.builtins-x86_64" # prevent missing symbols

msg Configuring musl
cd $srcdir/musl-$vmusl/
CC=$toolchain/bin/$target-clang  \
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
	ln -sr libc.so $x || die Failed to create symlink $x
done

mkdir -p $sysdir/usr/bin
ln -sf ../lib/libc.so $sysdir/usr/bin/ldd || die Failed to create symlink ldd
export CFLAGS="$ORG_CFLAGS"
fi
