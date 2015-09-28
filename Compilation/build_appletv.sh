#!/bin/bash

# original script taken from iTransmission project
# (https://github.com/ccp0101/iTransmission/blob/master/make_depend/build.sh)

ARCHS="x86_64"
PARALLEL_NUM=1

CURL_VERSION=7.44.0
LIBEVENT_VERSION="2.0.22-stable"
OPENSSL_VERSION=1.0.2d
TRANSMISSION_VERSION=2.84

export TEMP_DIR="$PWD/temp"
export PATCH_DIR="$PWD/patches"
export DEPENDENCY_DIR="$PWD/dependency"
export BUILD_FILTER="ssl,curl,trans,libev"
export Min_IPHONE_OS=9.0

function do_abort {
	echo $1 >&2
	exit 1
}

function do_loadenv {
	export BUILD_DIR="$PWD/out/${ARCH}"
	export TRANS_LINKER_FLAGS="-framework CoreFoundation "

	if [ ${ARCH} = "x86_64" ]
		then
		PLATFORM="AppleTVSimulator"
		SDK="appletvsimulator"
	elif [ ${ARCH} = "armv7s" ]
		then
		PLATFORM="AppleTVOS"
		SDK="appletvos"		
	elif [ ${ARCH} = "arm64" ]
		then
		PLATFORM="AppleTVOS"
		SDK="appletvos"		
	else
		do_abort "invalid arch ${ARCH} specified"
	fi
}

function do_export {
	unset CFLAGS

	export DEVROOT=`xcode-select -print-path`
	export SDKROOT=`xcrun --sdk ${SDK} --show-sdk-path`
	export LD=${DEVROOT}/usr/bin/ld
	export CPP="xcrun -sdk ${SDK} cpp"
    export CXX="xcrun -sdk ${SDK} clang++ -fembed-bitcode" 
	unset AR
	unset AS
	export NM=${DEVROOT}/usr/bin/nm
	export CXXCPP="xcrun -sdk ${SDK} cpp"
	export RANLIB="xcrun -sdk ${SDK} ranlib"
	export CFLAGS="-arch ${ARCH} -isysroot ${SDKROOT} -mtvos-version-min=${Min_IPHONE_OS}"
	export LDFLAGS="-L${SDKROOT}/usr/lib -L${DEVROOT}/usr/lib -isysroot ${SDKROOT}"
	export HAVE_CXX="yes"
	export CC="xcrun -sdk ${SDK} clang -fembed-bitcode"
	export CFLAGS="${CFLAGS} -I${BUILD_DIR}/include -I${SDKROOT}/usr/include -pipe -no-cpp-precomp"
	export CXXFLAGS="${CFLAGS}"
	export LDFLAGS="-L${SDKROOT}/usr/lib -L${BUILD_DIR}/lib -pipe -no-cpp-precomp ${LDFLAGS}"
	export COMMON_OPTIONS="--disable-shared --enable-static --disable-ipv6 --disable-manual "
	export HAVE_CXX="yes"
	
	if [ ${PLATFORM} = "AppleTVOS" ]
		then
		COMMON_OPTIONS="--host arm-apple-darwin ${COMMON_OPTIONS}"
	elif [ ${PLATFORM} = "AppleTVSimulator" ]
		then
			if [[ $ARCH == "x86_64" ]]; then
				COMMON_OPTIONS="--host x86_64-apple-darwin ${COMMON_OPTIONS}"
			elif [[ $ARCH == "i386" ]]; then
				COMMON_OPTIONS="--host i386-apple-darwin ${COMMON_OPTIONS}"
			fi
	fi	

	export PKG_CONFIG_PATH="${SDKROOT}/usr/lib/pkgconfig:${BUILD_DIR}/lib/pkgconfig"
}

function do_openssl {
	export PACKAGE_NAME="openssl-${OPENSSL_VERSION}"
	pushd ${TEMP_DIR}
	if [ ! -e "${PACKAGE_NAME}.tar.gz" ]
	then
	  /usr/bin/curl -O -L "http://www.openssl.org/source/${PACKAGE_NAME}.tar.gz" || do_abort "$FUNCNAME: fetch failed "
	fi
	
	rm -rf "${PACKAGE_NAME}"
	tar zxvf "${PACKAGE_NAME}.tar.gz" || do_abort "$FUNCNAME: unpack failed "
	
	pushd ${PACKAGE_NAME}
	
	LANG=C sed -i -- 's/define HAVE_FORK 1/define HAVE_FORK 0/' "./apps/speed.c"
	LANG=C sed -i -- 's/D\_REENTRANT\:iOS/D\_REENTRANT\:tvOS/' "./Configure"
	sed -ie "s!static volatile sig_atomic_t intr_signal;!static volatile intr_signal;!" "crypto/ui/ui_openssl.c"
	
	do_export
	if [[ "${ARCH}" == "x86_64" ]]; then
		./Configure no-asm darwin64-x86_64-cc --openssldir=${BUILD_DIR} || do_abort "$FUNCNAME: configure failed "
	else
		./Configure iphoneos-cross --openssldir=${BUILD_DIR} || do_abort "$FUNCNAME: configure failed "
	fi

	# Patch for iOS, taken from https://github.com/st3fan/ios-openssl/blame/master/build.sh
	perl -i -pe "s|static volatile sig_atomic_t intr_signal|static volatile int intr_signal|" ./crypto/ui/ui_openssl.c
	perl -i -pe "s|^CC= gcc|CC= ${CC}|g" Makefile
	perl -i -pe "s|^CFLAG= (.*)|CFLAG= ${CFLAGS} $1|g" Makefile
	
	xcrun -sdk ${SDK} make -j ${PARALLEL_NUM} || do_abort "$FUNCNAME: make failed "
	xcrun -sdk ${SDK} make install_sw || do_abort "$FUNCNAME: install failed "
	
	rm -rf ${BUILD_DIR}/share/man
	
	popd
	popd
}

function do_curl {
	export PACKAGE_NAME="curl-${CURL_VERSION}"
	pushd ${TEMP_DIR}
	if [ ! -e "${PACKAGE_NAME}.tar.gz" ]
	then
	  /usr/bin/curl -O -L "http://www.execve.net/curl/${PACKAGE_NAME}.tar.gz" || do_abort "$FUNCNAME: fetch failed "
	fi
	
	if [[ -z $DONT_OVERWRITE ]]; then
		rm -rf "${PACKAGE_NAME}"
		tar zxvf "${PACKAGE_NAME}.tar.gz" || do_abort "$FUNCNAME: unpack failed "
	fi
	
	pushd ${PACKAGE_NAME}

	do_export

	./configure --prefix="${BUILD_DIR}" ${COMMON_OPTIONS} --disable-ntlm-wb --with-random=/dev/urandom --with-ssl --with-zlib LDFLAGS="${LDFLAGS}" || do_abort "$FUNCNAME: configure failed "

	LANG=C sed -i -- 's/define HAVE_FORK 1/define HAVE_FORK 0/' "./lib/curl_config.h"
	
	xcrun -sdk ${SDK} make -j ${PARALLEL_NUM} || do_abort "$FUNCNAME: make failed "
	xcrun -sdk ${SDK} make install || do_abort "$FUNCNAME: install failed "
	
	popd
	popd
}

function do_libevent {

	export PACKAGE_NAME="libevent-${LIBEVENT_VERSION}"
	pushd ${TEMP_DIR}
	if [ ! -e "${PACKAGE_NAME}.tar.gz" ]
	then
	  /usr/bin/curl -O -L "https://github.com/libevent/libevent/releases/download/release-${LIBEVENT_VERSION}/${PACKAGE_NAME}.tar.gz" || do_abort "$FUNCNAME: fetch failed "
	fi
	
    if [[ -z $DONT_OVERWRITE ]]; then
        rm -rf "${PACKAGE_NAME}"
        tar zxvf "${PACKAGE_NAME}.tar.gz" || do_abort "$FUNCNAME: unpack failed "
    fi

	pushd ${PACKAGE_NAME}
	
	# libevent patch to hardcode google public dns servers for iOS
	# as there is no /etc/resolv.conf in iOS
	# (TODO... it properly.. XD)
	patch -N < ${PATCH_DIR}/libevent-nameservers.patch
	
	do_export

	if [[ ! -z $DONT_OVERWRITE ]]; then
		xcrun -sdk ${SDK} make clean
	fi
	
	LC_ALL=C find ./test -type f -exec sed -i '' 's/= fork()/= 1/g' {} +
	
	./configure --prefix="${BUILD_DIR}" ${COMMON_OPTIONS} || do_abort "$FUNCNAME: configure failed "
	
	xcrun -sdk ${SDK} make -j ${PARALLEL_NUM} || do_abort "$FUNCNAME: make failed "
	xcrun -sdk ${SDK} make install || do_abort "$FUNCNAME: install failed "
	
	popd
	popd
}

function do_transmission {	
	export PACKAGE_NAME="transmission-${TRANSMISSION_VERSION}"
	pushd ${TEMP_DIR}
	if [ ! -e "${PACKAGE_NAME}.tar.xz" ]
	then
	  /usr/bin/curl -O -L "http://download.transmissionbt.com/files/${PACKAGE_NAME}.tar.xz" || do_abort "$FUNCNAME: fetch failed "
	fi
	
	if [[ -z $DONT_OVERWRITE ]]; then
		rm -rf "${PACKAGE_NAME}"
		tar xvfJ "${PACKAGE_NAME}.tar.xz" || do_abort "$FUNCNAME: unpack failed "
	fi
	
	pushd ${PACKAGE_NAME}
	
	#apply whitelist patch (to allow LAN clients by default)
	pushd libtransmission
	patch -N < ${PATCH_DIR}/rpc_lan_whitelist.patch
	patch -N < ${PATCH_DIR}/sessionid.patch	
	patch -N < ${PATCH_DIR}/upload.patch	
	patch -N < ${PATCH_DIR}/fork.patch	
		
	popd

	LANG=C sed -i -- 's/define USE_TR_DAEMON/define USE_NO_DAEMON/' "./daemon/daemon.c"		
	LANG=C sed -i -- 's/define USE_OS_DAEMON/define USE_NO_DAEMON/' "./daemon/daemon.c"			
	
	do_export

	if [[ ! -z $DONT_OVERWRITE ]]; then
		xcrun -sdk ${SDK} make clean
	fi

	export CFLAGS="${CFLAGS} -framework CoreFoundation"
	export LDFLAGS="${LDFLAGS} -lcurl -liconv"

	./configure --prefix="${BUILD_DIR}" ${COMMON_OPTIONS} --enable-utp --enable-largefile --disable-nls --enable-lightweight --enable-cli --enable-daemon --disable-mac --with-kqueue --with-gtk=no || do_abort "$FUNCNAME: configure failed "
	
	mkdir -p ${BUILD_DIR}/include/net
	cp "${DEPENDENCY_DIR}/route.h" "${BUILD_DIR}/include/net/route.h"
	
	xcrun -sdk ${SDK} make -j ${PARALLEL_NUM} || do_abort "$FUNCNAME: make failed "
	xcrun -sdk ${SDK} make install || do_abort "$FUNCNAME: install failed "
	
	# Default installation doesn't copy library and header files
	mkdir -p ${BUILD_DIR}/include/libtransmission
	mkdir -p ${BUILD_DIR}/lib
	find ./libtransmission -name "*.h" -exec cp "{}" ${BUILD_DIR}/include/libtransmission \;
	find . -name "*.a" -exec cp "{}" ${BUILD_DIR}/lib \;
	
	popd
	popd
}

SSL_LIBS="libcrypto libssl"
do_lipo_ssl () {
    LIB_FILE=$1
    LIPO_FLAGS=
    for ARCH in $ARCHS
    do
        ARCH_LIB_FILE="$PWD/out/${ARCH}/lib/$LIB_FILE"
        if [ -f "$ARCH_LIB_FILE" ]; then
            LIPO_FLAGS="$LIPO_FLAGS $ARCH_LIB_FILE"
        else
            echo "skip $LIB_FILE of $ARCH";
        fi
    done

    if [ "$LIPO_FLAGS" != "" ]; then
        xcrun lipo -create $LIPO_FLAGS -output $PWD/out/universal/lib/$LIB_FILE
        xcrun lipo -info $PWD/out/universal/lib/$LIB_FILE
    fi
}


for ARCH in $ARCHS
do
do_loadenv

while getopts ":o:a:ne" opt; do
  	case $opt in
		a)
		  export ARCH="$OPTARG"
		  do_loadenv
		  ;;
	    o)
	      export BUILD_FILTER="$OPTARG"
	      ;;
		n)
		  export DONT_OVERWRITE="YES"
		  ;;
		e)
		  export BUILD_FILTER=""
		  do_export
		  ;;
	    ?)
	      do_abort "Invalid option: -$OPTARG"
	      ;;
	    :)
	      do_abort "Option -$OPTARG requires an argument."
	      ;;
	esac
done

echo "ARCH: ${ARCH}"

mkdir -p ${TEMP_DIR}
mkdir -p $PWD/out/universal/lib
mkdir -p $PWD/out/universal/include

#do_openssl
do_curl
do_libevent
do_transmission

done

for SSL_LIB in $SSL_LIBS
do
    do_lipo_ssl "$SSL_LIB.a";
done

