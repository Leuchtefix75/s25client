#!/bin/bash

TYPE=$1
SRCDIR=$2

usage()
{
	echo "$0 [nightly|stable] srcdir"
	echo "set environment FORCE to 1 to force update of archive"
	exit 1
}

cleanup()
{
	echo -n ""
	#rm -rf /tmp/$$
}

error()
{
	cleanup
	exit 1
}

if [ -z "$TYPE" ] ; then
	usage
fi

if [ ! -d "$SRCDIR" ] ; then
	usage
fi

RELEASEDEF=$SRCDIR/release/release.$TYPE.def
source $RELEASEDEF || error

if [ ! -d "$TARGET" ] ; then
	echo "ERROR: $RELEASEDEF does not contain TARGET"
	error
fi

# get arch
PLATFORM_NAME="$(grep PLATFORM_NAME:INTERNAL= CMakeCache.txt | head -n 1 | cut -d '=' -f 2)"
PLATFORM_ARCH="$(grep PLATFORM_ARCH:INTERNAL= CMakeCache.txt | head -n 1 | cut -d '=' -f 2)"
if [[ -z ${PLATFORM_NAME} ]]; then
	echo "ERROR: PLATFORM_NAME not found"
	error
fi
if [[ -z ${PLATFORM_ARCH} ]]; then
	echo "ERROR: PLATFORM_ARCH not found"
	error
fi
ARCH="${PLATFORM_NAME}.${PLATFORM_ARCH}"

# current and new package directory
ARCHDIR=$TARGET/$ARCH
ARCHNEWDIR=$TARGET/$ARCH.new

rm -rf $ARCHNEWDIR
mkdir -p $ARCHNEWDIR/packed
mkdir -p $ARCHNEWDIR/unpacked
mkdir -p $ARCHNEWDIR/updater

touch $ARCHNEWDIR/.writetest || error
rm -f $ARCHNEWDIR/.writetest

# redirect output to log AND stdout
npipe=/tmp/$$.log
trap "rm -f $npipe" EXIT
mknod $npipe p
tee <$npipe $ARCHNEWDIR/build.log &
exec 1>&-
exec 1>$npipe

echo "Building $TYPE for $ARCH in $SRCDIR"

make || error

# get version
VERSION=$(grep WINDOW_VERSION build_version_defines.h | cut -d ' ' -f 3 | cut -d \" -f 2)

# get revision
REVISION=$(grep WINDOW_REVISION build_version_defines.h | cut -d ' ' -f 3 | cut -d \" -f 2)

if [[ $1 =~ "^[0-9]+$" ]] && [ $REVISION -eq 0 ] ; then
	echo "error: revision is null"
	error
fi

# get savegame version
SAVEGAMEVERSION=$(grep "; // SaveGameVersion -- " $SRCDIR/src/Savegame.cpp | cut -d " " -f 6 | cut -d \; -f 1)

echo "Current version is: $VERSION-$REVISION"
echo "Savegame version:   $SAVEGAMEVERSION"

unpackedPath=$ARCHNEWDIR/unpacked/s25rttr_$VERSION

rm -rf "${unpackedPath}"

# save build version
cp -v build_version_defines.h build_version_defines.h.bak

# Install into this folder
cmake . -DCMAKE_INSTALL_PREFIX="${unpackedPath}" || error

# restore build version, so that it stays definitly the same
cp -v build_version_defines.h.bak build_version_defines.h

make install || error
DESTDIR="${unpackedPath}" ./prepareRelease.sh
if [ ! $? = 0 ]; then
	echo "error: Could not prepare release (strip executables etc.)"
	error
fi

# do they differ?
CHANGED=1
if [ "$FORCE" = "1" ] ; then
	echo "FORCE is set - forcing update"
elif [ -d $ARCHDIR/unpacked/s25rttr_$VERSION ] ; then
	diff -qrN $ARCHDIR/unpacked/s25rttr_$VERSION $unpackedPath
	CHANGED=$?
fi

FORMAT=".tar.bz2"
if [[ "$ARCH" =~ windows.* ]] ; then
	FORMAT=".zip"
fi

# create packed data and updater
if [ $CHANGED -eq 1 ] || [ ! -f $ARCHDIR/packed/s25rttr$FORMAT ] ; then
	echo "creating new archive"

	# remove old build artefacts
	rm -f ../s25rttr*$FORMAT

	# pack
	case "$FORMAT" in
		.tar.bz2)
			tar -C $ARCHNEWDIR/unpacked \
				--exclude=.svn \
				--exclude=dbg \
				--exclude s25rttr_$VERSION/share/s25rttr/RTTR/MUSIC/SNG/SNG_*.OGG \
				--exclude s25rttr_$VERSION/RTTR/MUSIC/SNG/SNG_*.OGG \
				--exclude s25rttr_$VERSION/s25client.app/Contents/MacOS/share/s25rttr/RTTR/MUSIC/SNG/SNG_*.OGG \
				-cvjf $ARCHNEWDIR/packed/s25rttr$FORMAT s25rttr_$VERSION || error
		;;
		.zip)
			(cd $ARCHNEWDIR/unpacked && \
				zip -r9 \
					$ARCHNEWDIR/packed/s25rttr$FORMAT \
					-x "s25rttr_$VERSION/dbg/*" \
					-x "s25rttr_$VERSION/RTTR/MUSIC/SNG/SNG_*.OGG" \
					-- s25rttr_$VERSION) || error
		;;
	esac
	
	cp -v $ARCHNEWDIR/packed/s25rttr$FORMAT ../s25rttr_$VERSION-${REVISION}_$ARCH$FORMAT || exit

	if [ -d $ARCHNEWDIR/unpacked/s25rttr_$VERSION/dbg ] ; then
		case "$FORMAT" in
			.tar.bz2)
				tar -C $ARCHNEWDIR/unpacked \
					-cvjf $ARCHNEWDIR/packed/s25rttr_dbg$FORMAT s25rttr_$VERSION/dbg || error
			;;
			.zip)
				(cd $ARCHNEWDIR/unpacked && \
					zip -r9 \
						$ARCHNEWDIR/packed/s25rttr_dbg$FORMAT s25rttr_$VERSION/dbg) || error
			;;
		esac

		cp -v $ARCHNEWDIR/packed/s25rttr_dbg$FORMAT ../s25rttr-dbg_$VERSION-${REVISION}_$ARCH$FORMAT || exit 1 
	else
		touch ../s25rttr-dbg_$VERSION-${REVISION}_$ARCH$FORMAT
	fi
	
	# link to archive
	mkdir -p $ARCHIVE
	ln -v $ARCHNEWDIR/packed/s25rttr$FORMAT $ARCHIVE/s25rttr_$VERSION-${REVISION}_$ARCH$FORMAT || \
		cp -v $ARCHNEWDIR/packed/s25rttr$FORMAT $ARCHIVE/s25rttr_$VERSION-${REVISION}_$ARCH$FORMAT || exit 1

	if [ -d $ARCHNEWDIR/unpacked/s25rttr_$VERSION/dbg ] ; then
		ln -v $ARCHNEWDIR/packed/s25rttr_dbg$FORMAT $ARCHIVE/s25rttr-dbg_$VERSION-${REVISION}_$ARCH$FORMAT || \
			cp -v $ARCHNEWDIR/packed/s25rttr_dbg$FORMAT $ARCHIVE/s25rttr-dbg_$VERSION-${REVISION}_$ARCH$FORMAT || exit 1
	fi

	# do upload
	if [ ! "$NOUPLOAD" = "1" ] && [ ! -z "$UPLOADTARGET" ] ; then
		if [ -z "$UPLOADTO" ] ; then
			UPLOADTO="$VERSION/"
		fi
		
		echo "uploading file to $UPLOADTARGET$UPLOADTO"
		ssh $UPLOADHOST "mkdir -vp $UPLOADPATH$UPLOADTO" || echo "mkdir $UPLOADPATH$UPLOADTO failed"
		rsync -avz --progress $ARCHIVE/s25rttr_$VERSION-${REVISION}_$ARCH$FORMAT $UPLOADTARGET$UPLOADTO || echo "scp failed"
		if [ ! -z "$UPLOADTARGET" ] ; then
			echo "$(date +%s);${UPLOADURL}${UPLOADTO}s25rttr_$VERSION-${REVISION}_$ARCH$FORMAT" >> ${UPLOADFILE}rapidshare.txt
		fi
	fi
	
	echo "creating new updater tree"

	# fastcopy files (only dirs and files, no symlinks
	(cd $ARCHNEWDIR/unpacked/s25rttr_$VERSION && find -type d -a ! -path */dbg* -exec mkdir -vp $ARCHNEWDIR/updater/{} \;)
	(cd $ARCHNEWDIR/unpacked/s25rttr_$VERSION && find -type f -a ! -name *.dbg -exec cp {} $ARCHNEWDIR/updater/{} \;)
	
	# note symlinks
	L=/tmp/links.$$
	echo -n > $L
	echo "reading links"
	(cd $ARCHNEWDIR/unpacked/s25rttr_$VERSION && find -type l -exec bash -c 'echo "{} $(readlink {})"' \;) | tee $L
	
	# savegame version
	UPDATERPATH=$(dirname $(find $ARCHNEWDIR/updater -name "s25update*" | head -n 1))
	S=/tmp/savegameversion.$$
	echo "reading savegame version"
	echo $SAVEGAMEVERSION > $S	
	cp -v $S $UPDATERPATH/savegameversion || exit 1	
	
	# note hashes
	F=/tmp/files.$$
	echo "reading files"
	(cd $ARCHNEWDIR/updater && md5deep -r -l .) | tee $F

	# bzip files
	find $ARCHNEWDIR/updater -type f -exec bzip2 -v {} \;
	
	# move file lists
	mv -v $L $ARCHNEWDIR/updater/links || exit 1
	mv -v $F $ARCHNEWDIR/updater/files || exit 1
	mv -v $S $ARCHNEWDIR/updater/savegameversion || exit 1	

	# create human version notifier
	echo "$REVISION" > $ARCHNEWDIR/revision-${REVISION} || exit 1
	echo "$VERSION"  > $ARCHNEWDIR/version-$VERSION || exit 1
	echo "$REVISION" > $ARCHNEWDIR/revision || exit 1
	echo "$VERSION"  > $ARCHNEWDIR/version || exit 1
	echo "${VERSION}-${REVISION}" > $ARCHNEWDIR/full-version || exit 1

	
	# rotate trees
	rm -rf $ARCHDIR.5
	mv $ARCHDIR.4 $ARCHDIR.5
	mv $ARCHDIR.3 $ARCHDIR.4
	mv $ARCHDIR.2 $ARCHDIR.3
	mv $ARCHDIR.1 $ARCHDIR.2
	mv $ARCHDIR $ARCHDIR.1
	mv $ARCHNEWDIR $ARCHDIR || exit 1

	echo "done"
else
	echo "nothing changed - no update necessary"
fi

cleanup
exit 0
