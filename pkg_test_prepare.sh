#!/bin/bash

fakeroot=`which fakeroot 2>/dev/null`
if [ -z "$fakeroot" ];then
  echo "ERROR - missing fakeroot"
  exit 1
fi

lintian=`which lintian 2>/dev/null`
if [ -z "$lintian" ];then
  echo "ERROR - missing lintian"
  exit 1
fi

dpkg_deb=`which dpkg-deb 2>/dev/null`
if [ -z "$dpkg-deb" ];then
  echo "ERROR - missing dpkg-deb"
  exit 1
fi

#chrpath=`which chrpath 2>/dev/null`
#if [ -z "$chrpath" ];then
#  echo "ERROR - missing chrpath"
#  exit 1
#fi
#
strip=`which strip 2>/dev/null`
if [ -z "$strip" ];then
  echo "ERROR - missing strip"
  exit 1
fi

if [ ! -f "debian/usr/lib/scaledb/ha_scaledb.so" ];then
   echo "ERROR - missing ha_scaledb.so"
   exit 1
fi

if [ ! -f "debian/usr/lib/scaledb/libscaledb.so" ];then
   echo "ERROR - missing libscaledb.so"
   exit 1
fi

if [ ! -f "debian/usr/sbin/scaledb_cas" ];then
   echo "ERROR - missing usr/sbin/scaledb_cas"
   exit 1
fi

if [ ! -f "debian/usr/sbin/scaledb_slm" ];then
   echo "ERROR - missing usr/sbin/scaledb_slm"
   exit 1
fi


set -e

cd debian
if [ $? -ne 0 ];then
  echo "ERROR - failed chdir to debian"
  exit 1
fi

set -e
echo "Updating file permissions"
chmod 0644 DEBIAN/conffiles
chmod 0755 DEBIAN/postinst 
chmod 0755 DEBIAN/postrm
chmod 0755 DEBIAN/preinst
chmod 0755 DEBIAN/prerm
find etc -type d -exec chmod 0755 {} \;
chmod 0644 etc/scaledb/*.cnf 
chmod 0755 etc/init.d/*
chmod 0755 usr/bin/*
chmod 0755 usr/sbin/*
chmod 0755 usr/lib/*
chmod 0644 usr/share/doc/scaledb-ude/ScaleDB_ONE-16.01-EULA.txt 
chmod 0644 usr/share/doc/scaledb-ude/bash_profile_text
chmod 0644 usr/share/doc/scaledb-ude/changelog.Debian.gz 
chmod 0644 usr/share/doc/scaledb-ude/copyright 
chmod 0644 usr/share/doc/scaledb-ude/scaledb.cnf-simple 
chmod 0644 usr/share/doc/scaledb-ude/version.txt 
chmod 0644 usr/share/scaledb-ude/*.cnf
chmod 0755 usr/share/scaledb-ude/scaledb_cas 
chmod 0755 usr/share/scaledb-ude/scaledb_mariadb
chmod 0755 usr/share/scaledb-ude/scaledb_slm
chmod 0644 usr/share/scaledb-ude/*.cnf
find usr/ -type d -exec chmod 0755 {} \;

echo "Stripping"
strip --strip-debug --strip-unneeded usr/lib/scaledb/{ha_scaledb.so,libscaledb.so} usr/sbin/{scaledb_cas,scaledb_slm}
echo "Running chrpath"
#$chrpath --delete usr/lib/ha_scaledb.so
#$chrpath --delete usr/lib/libscaledb.so

cd ../

if [ -f scaledb-ude-16.01.deb ];then
  rm -rf scaledb-ude-16.01.deb 
fi

if [ -f lintian.out ];then
  rm -rf litnia.out
fi

echo "Running fakeroot"
$fakeroot dpkg-deb --build debian
mv debian.deb scaledb-ude-16.01.deb

set +e
echo "Running lintian"
$lintian scaledb-ude-16.01.deb >&lintian.out
cat lintian.out
