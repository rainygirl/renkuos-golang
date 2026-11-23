#!/bin/bash
# Build a NATIVE gcc 13.3 + binutils 2.41 for RenkuOS arm64 and package it,
# so `CGO_ENABLED=1 go build` works on the machine itself.
#
# RENKU's arm64 repositories carry gcc_syslibs (the runtime libraries) but no
# compiler, so cgo could only be used by cross-compiling. This is a Canadian
# cross run inside haiku-builder: build = linux/arm64, host = target =
# aarch64-unknown-haiku, compiled with the image's own cross tools
# (generated.arm64/cross-tools-arm64) against a sysroot of haiku.hpkg +
# haiku_devel.hpkg + gcc_syslibs(_devel). Only the compiler drivers and cc1/
# cc1plus are built (make all-gcc); libgcc, crt*.o, libstdc++ headers and
# static archives are the cross toolchain's own target files, copied as-is
# (they are the same aarch64-unknown-haiku binaries a native build would make).
# Sources: the buildtools checkout the image is built from (gcc, binutils with
# in-tree gmp/mpfr/mpc/isl).
#
#   docker cp scripts/cross-arm64-gcc.sh haiku-builder:/root/
#   docker exec haiku-builder bash /root/cross-arm64-gcc.sh
#   -> $W/gcc-13.3.0-$REV-arm64.hpkg
#
# Installs as /boot/system/develop/tools/{bin,lib,libexec,include,...} with
# bin/ symlinks (gcc, g++, cc, c++, cpp, as, ld, ar, ...), the layout gcc's
# own Haiku config expects (headers come from haiku_devel via the sysroot "/").
set -e
REV=${REV:-2}
BT=${BT:-/root/renku-arm64-work/buildtools}
GEN=${GEN:-/root/renku-arm64-work/generated.arm64}
XT=$GEN/cross-tools-arm64
W=${W:-/root/gccstage}
S=$W/sysroot
DEST=$W/root
PREFIX=/boot/system/develop/tools
V=13.3.0
PKG=$GEN/objects/linux/arm64/release/tools/package/package
export LD_LIBRARY_PATH=$GEN/objects/linux/lib
export PATH=$XT/bin:$PATH
T=aarch64-unknown-haiku

mkdir -p $W $S/boot/system $DEST

# 1. sysroot
if [ ! -d $S/boot/system/develop/headers ]; then
	(cd $S/boot/system &&
	 $PKG extract $GEN/objects/haiku/arm64/packaging/packages/haiku.hpkg &&
	 $PKG extract $GEN/objects/haiku/arm64/packaging/packages/haiku_devel.hpkg &&
	 for d in $GEN/build_packages/gcc_syslibs-*-arm64 $GEN/build_packages/gcc_syslibs_devel-*-arm64; do
		cp -a $d/. .
	 done)
fi
HOSTENV=(CC="$T-gcc --sysroot=$S" CXX="$T-g++ --sysroot=$S" AR=$T-ar RANLIB=$T-ranlib)
COMMON="--build=aarch64-unknown-linux-gnu --host=$T --target=$T --prefix=$PREFIX --with-sysroot=/ --disable-nls"

# 2. binutils
mkdir -p $W/binutils-build && cd $W/binutils-build
[ -f Makefile ] || env "${HOSTENV[@]}" $BT/binutils/configure $COMMON \
	--disable-werror --disable-gdb --disable-gdbserver --disable-gprofng --disable-sim \
	--disable-libdecnumber --disable-readline --disable-gold --enable-plugins=no --without-zstd
make -j"$(nproc)" MAKEINFO=true
make install DESTDIR=$DEST MAKEINFO=true

# 3. gcc (compiler only)
mkdir -p $W/gcc-build && cd $W/gcc-build
# configure cannot run a test program for the host when cross compiling
export ac_cv_c_bigendian=no
[ -f Makefile ] || env "${HOSTENV[@]}" \
	CC_FOR_TARGET="$T-gcc --sysroot=$S" CXX_FOR_TARGET="$T-g++ --sysroot=$S" \
	$BT/gcc/configure $COMMON --with-build-sysroot=$S \
	--enable-languages=c,c++ --disable-lto --enable-frame-pointer \
	--enable-__cxa-atexit --enable-threads=posix --with-default-libstdcxx-abi=gcc4-compatible \
	--disable-maintainer-mode --disable-libgomp --disable-libatomic --disable-multilib \
	--disable-bootstrap --disable-plugin --without-zstd
make -j"$(nproc)" all-gcc MAKEINFO=true
make install-gcc DESTDIR=$DEST MAKEINFO=true

# 4. target runtime files from the cross toolchain
P=$DEST$PREFIX
mkdir -p $P/lib/gcc/$T/$V $P/include $P/$T/lib
cp -a $XT/lib/gcc/$T/$V/. $P/lib/gcc/$T/$V/
rm -rf $P/lib/gcc/$T/$V/plugin $P/lib/gcc/$T/$V/install-tools
cp -a $XT/$T/include/c++ $P/include/          # g++ looks in $PREFIX/include/c++/$V
cp -a $XT/$T/lib/*.a $P/$T/lib/
rm -rf $P/share/info $P/share/man $P/lib/bfd-plugins
for f in $P/bin/* $P/libexec/gcc/$T/$V/* $P/$T/bin/*; do
	[ -f "$f" ] && [ ! -L "$f" ] && file "$f" | grep -q ELF && $T-strip "$f" || true
done

# 5. package
R=$W/pkgroot
rm -rf $R && mkdir -p $R/develop $R/bin
mkdir -p $R/develop/tools
# no hard links in the package (gcc/c++/ld.bfd are hard links after make install)
tar --hard-dereference -C $P -cf - . | tar -C $R/develop/tools -xf -
for b in gcc g++ c++ cpp gcov as ld ar nm ranlib strip objcopy objdump readelf size strings addr2line c++filt; do
	ln -s ../develop/tools/bin/$b $R/bin/$b
done
ln -s ../develop/tools/bin/gcc $R/bin/cc
cat > $R/.PackageInfo <<INFO
name		gcc
version		$V-$REV
architecture	arm64
summary		"GNU C/C++ compiler and binutils for RenkuOS arm64"
description	"Native gcc $V (C, C++) and binutils 2.41, built as a Canadian cross from the same buildtools sources as the image's own cross compiler. Needed for cgo (CGO_ENABLED=1 go build) and for building C/C++ code on the machine itself."
packager	"RENKU <renku@localhost>"
vendor		"RENKU"
copyrights {
	"Free Software Foundation, Inc."
}
licenses {
	"GNU GPL v3"
	"GNU LGPL v3"
}
provides {
	gcc = $V
	binutils = 2.41
	cmd:gcc = $V
	cmd:g++ = $V
	cmd:cc = $V
	cmd:c++ = $V
	cmd:cpp = $V
	cmd:as = 2.41
	cmd:ld = 2.41
	cmd:ar = 2.41
	cmd:nm = 2.41
	cmd:ranlib = 2.41
	cmd:strip = 2.41
	cmd:objdump = 2.41
	cmd:readelf = 2.41
}
requires {
	haiku
	haiku_devel
	gcc_syslibs_devel
	lib:libstdc++
}
INFO
(cd $R && $PKG create -z zlib -9 "$W/gcc-$V-$REV-arm64.hpkg" >/dev/null)
"$PKG" list "$W/gcc-$V-$REV-arm64.hpkg" | head -20
echo "-> $W/gcc-$V-$REV-arm64.hpkg"
