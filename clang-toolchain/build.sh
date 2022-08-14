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
	echo "     Build LLVM tree*          - no if no_llvm=yes         "
	echo "     Create cross binaries     - no if no_llvm_bin=yes     "
	echo "     Build Musl libc           - no if no_musl=yes         "
	echo "-----------------------------------------------------------"
	echo "*: LLVM tree contains: LLVM, Clang, LLD"
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

vmusl="1.2.3"
vllvm="14.0.5"
vllvm_major="$(echo $vllvm | cut -d '.' -f1)"

test -n "$no_download"     && download=no      || download=yes
test -n "$no_unpack"       && unpack=no        || unpack=yes
test -n "$no_compiler_rt"  && compiler_rt=no   || compiler_rt=yes
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
cp -r compiler-rt-* compiler-rt
tar -xf $sourcedir/libunwind-$vllvm.src.tar.xz
cp -r libunwind-$vllvm.src libunwind
cp -r libunwind llvm/projects/libunwind
tar -xf $sourcedir/libcxx-$vllvm.src.tar.xz
cp -r libcxx-* libcxx
cp -r libcxx llvm/projects/libcxx
tar -xf $sourcedir/libcxxabi-$vllvm.src.tar.xz
cp -r libcxxabi-* libcxxabi
cp -r libcxxabi llvm/projects/libcxxabi
tar -xf $sourcedir/musl-$vmusl.tar.gz
fi

if test -z "$no_compiler_rt"; then 
cd $srcdir/compiler-rt 
cmake -S . -B build \
	-DCMAKE_INSTALL_PREFIX="$toolchain" \
	-DCMAKE_BUILD_TYPE=Release \
	-DLLVM_INCLUDE_BENCHMARKS=OFF \
	-DCOMPILER_RT_BUILD_BUILTINS=ON \
	-DCOMPILER_RT_BUILD_CRT=ON \
	-DCOMPILER_RT_BUILD_LIBFUZZER=OFF \
	-DCOMPILER_RT_BUILD_MEMPROF=OFF \
	-DCOMPILER_RT_BUILD_ORC=OFF \
	-DCOMPILER_RT_BUILD_PROFILE=OFF \
	-DCOMPILER_RT_BUILD_SANITIZERS=OFF \
	-DCOMPILER_RT_DEFAULT_TARGET_TRIPLE=$target \
	-DCOMPILER_RT_BUILD_XRAY=OFF \
	-DCOMPILER_RT_INSTALL_PATH="$toolchain/lib/clang/$vllvm" \
	-Wno-dev -G "Ninja" || die Failed to configure compiler-rt 
cd build 
eval $NINJA -j$core || die Failed to build compiler-rt
eval $NINJA -j$core install || die Failed to install compiler-rt
fi

if test -z "$no_llvm"; then
# Source: ataraxialinux/crossdev/packages/build_llvm()
# Build a working LLVM tree
msg Configuring LLVM tree 
cd $srcdir/llvm
export CFLAGS="$CFLAGS -I$toolchain/include"
export CXXFLAGS="$CXXFLAGS -I$toolchain/include"
install -dm755 $toolchain/include/mach-o
install -Dm644 $srcdir/libunwind/include/mach-o/compact_unwind_encoding.h $toolchain/include/mach-o/
cmake -S . -B build \
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
	-DLLVM_INCLUDE_BENCHMARKS=OFF \
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
cd $srcdir/llvm/build 
msg Building LLVM compiler
eval $NINJA -j$core || die Failed to build LLVM tree
msg Installing LLVM compiler
eval $NINJA -j$core install || die Failed to install LLVM tree
fi

if test -z "$no_llvm_bin"; then
# Source: ataraxialinux/crossdev/packages/build_llvm()
msg Create important binaries
cd $toolchain/bin

for i in clang clang++ clang-cpp; do
	cp -v clang-$vllvm_major $target-$i || die Failed to copy $target-$i
done
for i in as dwp nm objcopy objdump size strings symbolizer cxxfilt cov ar readobj; do
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
export CFLAGS="$CFLAGS \
	-L$toolchain/lib/clang/$vllvm/lib/linux \
	--ld-path=$toolchain/bin/$target-ld.lld \
	-lclang_rt.builtins-x86_64" # prevent missing symbols

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
