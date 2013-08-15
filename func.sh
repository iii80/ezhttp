#监控编译安装中是否有错误，有错误就停止安装,并把错误写入到文件/root/ezhttp_errors.log
error_detect(){
local command=$1
local cur_soft=`pwd | awk -F'/' '{print $NF}'`
set -o pipefail
${command}  2>&1 | tee /root/ezhttp_errors.log 
if [ $? != 0 ];then
	clear
	tail /root/ezhttp_errors.log
	distro=`cat /etc/issue`
	architecture=`uname -m`
	cat >>/root/ezhttp_errors.log<<EOF
	lnmp errors:
	distributions:$distro
	architecture:$architecture
	Nginx: ${nginx}
	MySQL Server: $mysql
	PHP Version: $php
	Other Software: ${other_soft_install[@]}
	issue:failed to install $cur_soft
EOF
	echo "#########################################################"
	echo "failed to install $cur_soft."    
	echo "please visit website http://www.centos.bz/ezhttp/"
	echo "and submit /root/ezhttp_errors.log ask for help."
	echo "#########################################################"
	exit 1
fi
}

#保证是在根用户下运行
rootness(){
# Make sure only root can run our script
if [[ $EUID -ne 0 ]]; then
	echo "This script must be run as root" 1>&2
	exit 1
fi
}

#禁止selinux，因为在selinux下会出现很多意想不到的问题
disable_selinux(){
if [ -s /etc/selinux/config ] && grep 'SELINUX=enforcing' /etc/selinux/config; then
	sed -i 's/SELINUX=enforcing/SELINUX=disabled/g' /etc/selinux/config
	setenforce 0
fi
}

#大写转换成小写
upcase_to_lowcase(){
words=$1
echo $words | tr [A-Z] [a-z]
}

#多核并行编译
function parallel_make(){
cpunum=`cat /proc/cpuinfo |grep 'processor'|wc -l`
if [ $cpunum == 1 ];then
	make
else	
	make -j$cpunum
fi	
}

#判断路径输入是否合法
filter_location(){
local location=$1
if ! echo $location | grep -q "^/";then
	while true
	do
		read -p "input error,please input location again." location
		echo $location | grep -q "^/" && echo $location && break
	done
else
	echo $location
fi
}

#下载软件
download_file(){
local url1=$1
local url2=$2
local filename=$3
if [ -s "${cur_dir}/soft/${filename}" ];then
	#check_md5 "$filename"
	echo "${filename} is existed."
else
	[ ! -d "${cur_dir}/soft" ] && mkdir -p ${cur_dir}/soft
	cd ${cur_dir}/soft
	choose_url_download "$url1" "$url2" "$filename"
fi
}


#选择最优下载url
choose_url_download()
{
local url1=$1
local url2=$2
local filename=$3
echo "try to parse baidu network disk download url..."
local url1=`get_baidupan_url $url1`
echo "baidu download url is $url1"
if [ "$url1" == "" ];then
	echo "failed to parse baidu network disk,use url $url2 to download.."
	url=$url2
else
	echo "testing Baidu network disk url download speed..."
	speed1=`curl -m 5 -L -s -w '%{speed_download}' "$url1" -o /dev/null`
	echo "Baidu network disk url download speed is $speed1"
	echo "testing Official url download speed..."
	speed2=`curl -m 5 -L -s -w '%{speed_download}' "$url2" -o /dev/null`
	echo "Official url download speed is $speed2"
	speed1=${speed1%%.*}
	speed2=${speed2%%.*}
	if [ $speed1 -gt $speed2 ];then
		url=$url1
	else
		url=$url2
	fi
	echo "use the url $url to download $filename.."
fi
sleep 1
#开始下载
wget -c --tries=3 ${url} -O $filename
[ $? != 0 ] && echo "fail to download $filename,exited." && exit 1
#check_md5 "$filename"
}

#获取百度网盘下载地址
get_baidupan_url(){
local url=$1
baidu_url="`wget -q  -O - "${url}" | sed -n 's#.*\(http:\\\\\\\\/\\\\\\\\/d\.pcs\.baidu\.com[^"]*\)".*#\1#;s#\\\\\\\\##g;s/\\\\//p' | sed -n '1p'`"
echo $baidu_url
}

#检查软件md5
check_md5(){
local filename=$1
cd ${cur_dir}/soft
grep "$filename" ${cur_dir}/conf/md5.txt | sed 's/\r//g' | md5sum -c -
[ $? != 0 ] && echo "$filename md5 check failed,may be the file is modified or incompleted,please redownload it, exited." && exit 1
}

#判断命令是否存在
check_command_exist(){
local command=$1
if ! which $command > /dev/null;then
	echo "$command not found,please install it."
	exit 1
fi
}

#安装编译工具
install_tool(){ 
cat /proc/version | grep -q -E -i "ubuntu|debian"  && apt-get -y update && apt-get -y install gcc g++ make wget perl curl
cat /proc/version | grep -q -E -i "centos|read hat|redhat"  && yum -y install gcc gcc-c++ make wget perl  curl

check_command_exist "gcc"
check_command_exist "g++"
check_command_exist "make"
check_command_exist "wget"
check_command_exist "perl"
}

#判断系统版本
check_sys_version(){
cat /proc/version | grep -q -E -i "ubuntu|debian"  && echo "debian"
cat /proc/version | grep -q -E -i "centos|read hat|redhat"  && echo "centos"
}

#支持包管理工具安装依赖的系统
package_support(){
cat /proc/version | grep -q -E -i "ubuntu|debian"  && echo 1
cat /proc/version | grep -q -E -i "centos|read hat|redhat"  && echo 1
}

#安装cmake
install_cmake(){
download_file "${cmake_baidupan_link}" "${cmake_official_link}" "${cmake_filename}.tar.gz"
cd $cur_dir/soft/
tar xzvf ${cmake_filename}.tar.gz
cd ${cmake_filename}
make clean
error_detect "./configure --prefix=${depends_prefix}/${cmake_filename}"
error_detect "parallel_make"
error_detect "make install"
add_to_env "${depends_prefix}/${cmake_filename}"
}

#安装ncurses
install_ncurses(){
if [ "$mysql" == "${mysql5_1_filename}" ];then
	download_file "${ncurses_baidupan_link2}" "${ncurses_official_link2}" "${ncurses_filename2}.tar.gz"
	cd $cur_dir/soft/
	tar xzvf ${ncurses_filename2}.tar.gz
	cd ${ncurses_filename2}
	make clean
	error_detect "./configure --prefix=${depends_prefix}/${ncurses_filename2} --with-shared"
	error_detect "parallel_make"
	error_detect "make install"
	add_to_env "${depends_prefix}/${ncurses_filename2}"
else
	download_file "${ncurses_baidupan_link}" "${ncurses_official_link}" "${ncurses_filename}.tar.gz"
	cd $cur_dir/soft/
	tar xzvf ${ncurses_filename}.tar.gz
	cd ${ncurses_filename}
	make clean
	error_detect "./configure --prefix=${depends_prefix}/${ncurses_filename} --with-shared"
	error_detect "parallel_make"
	error_detect "make install"
	add_to_env "${depends_prefix}/${ncurses_filename}"	
fi	
}

#安装bison
install_bison(){
download_file "${bison_baidupan_link}" "${bison_official_link}" "${bison_filename}.tar.gz"
cd $cur_dir/soft/
tar xzvf ${bison_filename}.tar.gz
cd ${bison_filename}
make clean
error_detect "./configure --prefix=${depends_prefix}/${bison_filename}"
error_detect "parallel_make"
error_detect "make install"
add_to_env "${depends_prefix}/${bison_filename}"
}

#安装patch
install_patch(){
download_file "${patch_baidupan_link}" "${patch_official_link}" "${patch_filename}.tar.gz"
cd $cur_dir/soft/
tar xzvf ${patch_filename}.tar.gz
cd ${patch_filename}
make clean
error_detect "./configure --prefix=${depends_prefix}/${patch_filename}"
error_detect "parallel_make"
error_detect "make install"
add_to_env "${depends_prefix}/${patch_filename}"
}

#安装autoconf
install_autoconf(){
download_file "${autoconf_baidupan_link}" "${autoconf_official_link}" "${autoconf_filename}.tar.gz"
cd $cur_dir/soft/
tar xzvf ${autoconf_filename}.tar.gz
cd ${autoconf_filename}
make clean
error_detect "./configure --prefix=${depends_prefix}/${autoconf_filename}"
error_detect "parallel_make"
error_detect "make install"
add_to_env "${depends_prefix}/${autoconf_filename}"
}

#安装libxml2
install_libxml2(){
download_file "${libxml2_baidupan_link}" "${libxml2_official_link}" "${libxml2_filename}.tar.gz"
cd $cur_dir/soft/
tar xzvf ${libxml2_filename}.tar.gz
cd ${libxml2_filename}
make clean
error_detect "./configure --prefix=${depends_prefix}/${libxml2_filename}"
error_detect "parallel_make"
error_detect "make install"
add_to_env "${depends_prefix}/${libxml2_filename}"
}

#安装openssl
install_openssl(){
download_file "${openssl_baidupan_link}" "${openssl_official_link}" "${openssl_filename}.tar.gz"
cd $cur_dir/soft/
tar xzvf ${openssl_filename}.tar.gz
cd ${openssl_filename}
make clean
error_detect "./config --prefix=${depends_prefix}/${openssl_filename} shared threads"
#并行编译可能会出错
error_detect "make"
error_detect "make install"
add_to_env "${depends_prefix}/${openssl_filename}"
}

#安装zlib
install_zlib(){
download_file "${zlib_baidupan_link}" "${zlib_official_link}" "${zlib_filename}.tar.gz"
cd $cur_dir/soft/
tar xzvf ${zlib_filename}.tar.gz
cd ${zlib_filename}
make clean
error_detect "./configure --prefix=${depends_prefix}/${zlib_filename}"
error_detect "parallel_make"
error_detect "make install"
add_to_env "${depends_prefix}/${zlib_filename}"
}

#安装libcurl
install_curl(){
download_file "${libcurl_baidupan_link}" "${libcurl_official_link}" "${libcurl_filename}.tar.gz"
cd $cur_dir/soft/
tar xzvf ${libcurl_filename}.tar.gz
cd ${libcurl_filename}
make clean
error_detect "./configure --prefix=${depends_prefix}/${libcurl_filename}"
error_detect "parallel_make"
error_detect "make install"
add_to_env "${depends_prefix}/${libcurl_filename}"
}

#安装pcre
install_pcre(){
download_file "${pcre_baidupan_link}" "${pcre_official_link}" "${pcre_filename}.tar.gz"
cd $cur_dir/soft/
tar xzvf ${pcre_filename}.tar.gz
cd ${pcre_filename}
make clean
error_detect "./configure --prefix=${depends_prefix}/${pcre_filename}"
error_detect "parallel_make"
error_detect "make install"
add_to_env "${depends_prefix}/${pcre_filename}"
}


#安装libtool
install_libtool(){
download_file "${libtool_baidupan_link}" "${libtool_official_link}" "${libtool_filename}.tar.gz"
cd $cur_dir/soft/
tar xzvf ${libtool_filename}.tar.gz
cd ${libtool_filename}
make clean
error_detect "./configure --prefix=${depends_prefix}/${libtool_filename} --enable-ltdl-install"
error_detect "parallel_make"
error_detect "make install"
add_to_env "${depends_prefix}/${libtool_filename}"
}

#安装libjpeg
install_libjpeg(){
download_file "${libjpeg_baidupan_link}" "${libjpeg_official_link}" "${libjpeg_filename}.tar.gz"
cd $cur_dir/soft/
tar xzvf ${libjpeg_filename}.tar.gz
cd ${libjpeg_filename}
make clean
\cp ${depends_prefix}/${libtool_filename}/share/libtool/config/config.sub ./
\cp ${depends_prefix}/${libtool_filename}/share/libtool/config/config.guess ./
error_detect "./configure --prefix=${depends_prefix}/${libjpeg_filename} --enable-shared --enable-static"
mkdir -p ${depends_prefix}/${libjpeg_filename}/include/ ${depends_prefix}/${libjpeg_filename}/lib/ ${depends_prefix}/${libjpeg_filename}/bin/ ${depends_prefix}/${libjpeg_filename}/man/man1/
error_detect "parallel_make"
error_detect "make install"
add_to_env "${depends_prefix}/${libjpeg_filename}"
}

#安装libpng
install_libpng(){
download_file "${libpng_baidupan_link}" "${libpng_official_link}" "${libpng_filename}.tar.gz"
cd $cur_dir/soft/
tar xzvf ${libpng_filename}.tar.gz
cd ${libpng_filename}
make clean
export LDFLAGS="-L${depends_prefix}/${zlib_filename}/lib"
export CPPFLAGS="-I${depends_prefix}/${zlib_filename}/include"
error_detect "./configure --prefix=${depends_prefix}/${libpng_filename}"
error_detect "parallel_make"
error_detect "make install"
unset LDFLAGS CPPFLAGS
add_to_env "${depends_prefix}/${libpng_filename}"
}


#安装mhash
install_mhash(){
download_file "${mhash_baidupan_link}" "${mhash_official_link}" "${mhash_filename}.tar.gz"
cd $cur_dir/soft/
tar xzvf ${mhash_filename}.tar.gz
cd ${mhash_filename}
make clean
error_detect "./configure --prefix=${depends_prefix}/${mhash_filename}"
error_detect "parallel_make"
error_detect "make install"
add_to_env "${depends_prefix}/${mhash_filename}"
}

#安装libmcrypt
install_libmcrypt(){
download_file "${libmcrypt_baidupan_link}" "${libmcrypt_official_link}" "${libmcrypt_filename}.tar.gz"
cd $cur_dir/soft/
tar xzvf ${libmcrypt_filename}.tar.gz
cd ${libmcrypt_filename}
make clean
error_detect "./configure --prefix=${depends_prefix}/${libmcrypt_filename}"
error_detect "parallel_make"
error_detect "make install"
add_to_env "${depends_prefix}/${libmcrypt_filename}"
}

#安装m4
install_m4(){
download_file "${m4_baidupan_link}" "${m4_official_link}" "${m4_filename}.tar.gz"
cd $cur_dir/soft/
tar xzvf ${m4_filename}.tar.gz
cd ${m4_filename}
make clean
error_detect "./configure --prefix=${depends_prefix}/${m4_filename}"
error_detect "parallel_make"
error_detect "make install"
add_to_env "${depends_prefix}/${m4_filename}"
}

#安装ImageMagick
install_ImageMagick(){
download_file "${ImageMagick_baidupan_link}" "${ImageMagick_official_link}" "${ImageMagick_filename}.tar.gz"
cd $cur_dir/soft/
tar xzvf ${ImageMagick_filename}.tar.gz
cd ${ImageMagick_filename}
error_detect "./configure --prefix=${depends_prefix}/${ImageMagick_filename}"
error_detect "parallel_make"
error_detect "make install"
#修复php-ImageMagick找不到MagickWand.h的问题
cd ${depends_prefix}/${ImageMagick_filename}/include
ln -s ImageMagick-6 ImageMagick
add_to_env "${depends_prefix}/${ImageMagick_filename}"
}

#安装pkgconfig
install_pkgconfig(){
download_file "${pkgconfig_baidupan_link}" "${pkgconfig_official_link}" "${pkgconfig_filename}.tar.gz"
cd $cur_dir/soft/
tar xzvf ${pkgconfig_filename}.tar.gz
cd ${pkgconfig_filename}
error_detect "./configure --prefix=${depends_prefix}/${pkgconfig_filename}"
error_detect "parallel_make"
error_detect "make install"
add_to_env "${depends_prefix}/${pkgconfig_filename}"
}

#添加必要的环境变量
add_to_env(){
local location=$1
cd ${location} && [ ! -d lib ] && [ -d lib64 ] && ln -s lib64 lib
[ -d "${location}/lib" ] && export LD_LIBRARY_PATH=${location}/lib:$LD_LIBRARY_PATH
[ -d "${location}/bin" ] &&	export PATH=${location}/bin:$PATH
}

#测试元素是否在数组里
if_in_array(){
local element=$1
local array=$2
for i in $array
do
	if [ "$i" == "$element" ];then
		return 0
	fi
done
return 1
}

#判断php版本
check_php_version(){
local location=$1
$location/bin/php -v | grep -q -i -E "php[ ]+5\.2" && echo "5.2"
$location/bin/php -v | grep -q -i -E "php[ ]+5\.3" && echo "5.3"
$location/bin/php -v | grep -q -i -E "php[ ]+5\.4" && echo "5.4"
}


#安装libevent
install_libevent(){
download_file "${libevent_baidupan_link}" "${libevent_official_link}" "${libevent_filename}.tar.gz"
cd $cur_dir/soft/
tar xzvf ${libevent_filename}.tar.gz
cd ${libevent_filename}
make clean
error_detect "./configure --prefix=${depends_prefix}/${libevent_filename}"
error_detect "parallel_make"
error_detect "make install"
add_to_env "${depends_prefix}/${libevent_filename}"
}

#检测是否安装，存在就不安装了
check_installed(){
local command=$1
local location=$2
if [ -d "$location" ];then
	echo "$location found,skip the installation."
	add_to_env "$location"
else
	${command}
fi
}

#检测是否安装,带确认对话
check_installed_ask(){
local command=$1
local location=$2
if [ -d "$location" ];then
	while true
	do
		read -p "directory $location found,may be the software had installed,remove it and reinstall it? [y/N]" cover
		cover="`upcase_to_lowcase $cover`"
		case $cover in
		y) rm -rf $location && ${command} ; break;;
		n) echo "do not reinstall this software." ; break;;
		*) echo "input error." 
		esac
	done
else
	${command}
fi
}

#发行版判断
ReleaseCheck(){
	local release=$1
	cat /proc/version | grep -q  -i "$release"  && return 0 || return 1
	cat /proc/version | grep -q  -i "$release"  && return 0 || return 1
}

#获取版本号
VersionGet(){
	grep -oE  "[0-9.]+" /etc/issue
}

#判断centos版本
CentOSVerCheck(){
	local code=$1
	local version="`VersionGet`"
	local main_ver=${version%.*}
	if [ $main_ver == $code ];then
		return 0
	else
		return 1
	fi		
}

#安装php依赖
install_php_depends(){
	#安装依赖
	if [ "`check_sys_version`" == "debian" ];then
		apt-get -y install m4 autoconf libcurl4-gnutls-dev  autoconf2.13 libxml2-dev openssl zlib1g-dev libpcre3-dev libtool libjpeg-dev libpng12-dev libmhash-dev libmcrypt-dev
		create_lib_link "libjpeg.so"
		create_lib_link "libpng.so"
		create_lib_link "libltdl.so"
	elif [ "`check_sys_version`" == "centos" ];then
		yum -y install m4 autoconf libxml2-devel openssl  zlib-devel curl-devel pcre-devel libtool-libs libjpeg-devel libpng-devel mhash-devel libmcrypt-devel
		create_lib_link "libjpeg.so"
		create_lib_link "libpng.so"
		create_lib_link "libltdl.so"
		#解决centos 6 libmcrypt不在在的问题
		if CentOSVerCheck 6;then
			if [ `getconf WORD_BIT` = '32' ] && [ `getconf LONG_BIT` = '64' ] ; then
				rpm -i $cur_dir/conf/libmcrypt-2.5.7-1.2.el6.rf.x86_64.rpm
				rpm -i $cur_dir/conf/libmcrypt-devel-2.5.7-1.2.el6.rf.x86_64.rpm
			else
				rpm -i $cur_dir/conf/libmcrypt-2.5.7-1.2.el6.rf.i686.rpm
				rpm -i $cur_dir/conf/libmcrypt-devel-2.5.7-1.2.el6.rf.i686.rpm
			fi	
		fi			
	else
		check_installed "install_m4" "${depends_prefix}/${m4_filename}"
		check_installed "install_autoconf" "${depends_prefix}/${autoconf_filename}"
		check_installed "install_libxml2" "${depends_prefix}/${libxml2_filename}"
		check_installed "install_openssl" "${depends_prefix}/${openssl_filename}"
		check_installed "install_zlib " "${depends_prefix}/${zlib_filename}"
		check_installed "install_curl" "${depends_prefix}/${libcurl_filename}"
		check_installed "install_pcre" "${depends_prefix}/${pcre_filename}"
		check_installed "install_libtool" "${depends_prefix}/${libtool_filename}"
		check_installed "install_libjpeg" "${depends_prefix}/${libjpeg_filename}"
		check_installed "install_libpng" "${depends_prefix}/${libpng_filename}"
		check_installed "install_mhash " "${depends_prefix}/${mhash_filename}"
		check_installed "install_libmcrypt" "${depends_prefix}/${libmcrypt_filename}"
	fi

}

#在/usr/lib创建库文件的链接
create_lib_link(){
	updatedb
	local lib=$1
	local libpath="`locate $lib | sed -n 1p`"
	[ $libpath != "" ] && [ ! -s "/usr/lib/$lib" ]&& ln -s $libpath /usr/lib/$lib
}

#显示菜单
display_menu(){
local soft=$1
local prompt="which ${soft} you'd install: "
eval arr=(\${${soft}_arr[@]})
while true
do
	echo -e "#################### ${soft} setting ####################\n\n"
	for ((i=1;i<=${#arr[@]};i++ )); do echo -e "$i) ${arr[$i-1]}"; done
	echo
	read -p "${prompt}" $soft
	if [ "${arr[$soft-1]}" == ""  ];then
		prompt="input errors,please input a number: "
	else
		eval $soft=${arr[$soft-1]}
		eval echo "your selection: \$$soft"             
		break
	fi
done
}
