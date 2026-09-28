#!/bin/sh

#传入`供应商`和`网络环境`,配置成具体的工程

#命令行工具输入
# sh projectDeploy.sh -e pre -s s1

# 运行环境
# -e    prd pre

# 供应商 目前只配置 s1 和 s2
# -s
#   1.s1      -> 供应商1
#   2.s2      -> 供应商2
#   3.s3      -> 供应商3


#============= 需要配置的选项 =============

# 1.启动图、桌面图标文件、供应商定制 logo
# 2.bundleID、版本号、build 批次号 app 名称
# 3.微信APPID
# 4.网络环境

#  Created by miaocf on 2019/5/22.

#出现错误退出shell
set -e


#============= 配置项 =============

#默认打pre的包
environment='pre'

#默认供应商是s1
supplier='s1'

#默认 bundleID
bundleID='com.xxx.xxx'

#微信appid s1
wx_app_id='xxx'


#参数接入
while getopts ":e:s:" opt

do
    case $opt in
        e)
            environment=$OPTARG;;

        s)
            supplier=$OPTARG;;

        ?)
            echo "请输入正确的参数"
            exit 1;;
    esac
done

echo "-----> 打包环境 $environment 供应商 $supplier"

#工程绝对路径
project_path=$(pwd)
echo "-----> 工程路径：${project_path}"

#工程名称
project_name=$(ls | grep xcodeproj | awk -F.xcodeproj '{print $1}')
echo "-----> 工程文件名称：${project_name}"

#Info.plist路径
project_infoplist_path=${project_path}/${project_name}/Info.plist
echo "-----> Info.plist路径：${project_infoplist_path}"


#代码管理版本和当前时间 用于上传测试包时用
appVersion="1.0.0"

newTimePath="$(date +%Y%m%d%H%M)"

#app 工程配置函数
function config(){

    buildConfig=${project_path}/${project_name}/AppDelegate.m
    configLine=$(grep -n "static xxx xxx" "${buildConfig}" | head -1 | cut  -d  ":"  -f  1)

    configureFile=${project_path}/xxx/xxx.h

    if [ $configLine ]; then
        if [ $1 = "-s1" ];then

            if [ $2 = "-pre" ]; then

                sed -i '' -e "${configLine}s/^.*$/static xxx xxx = xxx;/" ${buildConfig}

            elif [ $2 = "-prd" ];then

                sed -i '' -e "${configLine}s/^.*$/static xxx xxx = xxx;/" ${buildConfig}
            fi
#            更新 微信APPID
#            wx_configLine=$(grep -n "\[WXApi registerApp" "${buildConfig}" | head -1 | cut  -d  ":"  -f  1)
#            if [ $wx_configLine ]; then

#                sed -i '' -e "${wx_configLine}s/^.*$/ [WXApi registerApp:@\"xxx\"\];/" ${buildConfig}
#            fi
#            /usr/libexec/PlistBuddy -c "set CFBundleURLTypes:2:CFBundleURLSchemes:0 xxx" ${project_infoplist_path}

            #修改支付宝 scheme
            sed -i '' 's/^\#define xxx_SCHEMA_URL.*$/\#define xxx_SCHEMA_URL  @\"xxx.xxx.xxx\"/g' ${configureFile}
            /usr/libexec/PlistBuddy -c "set CFBundleURLTypes:0:CFBundleURLSchemes:0 xxx.xxx.xxx" ${project_infoplist_path}


            #修改bundleID、版本号、APP名称
            /usr/libexec/PlistBuddy -c "set CFBundleIdentifier com.xxx.xxx" ${project_infoplist_path}
            /usr/libexec/PlistBuddy -c "set CFBundleShortVersionString ${appVersion}" ${project_infoplist_path}
            /usr/libexec/PlistBuddy -c "set CFBundleDisplayName xxxx" ${project_infoplist_path}

#文件替换
            rm -rf ${project_path}/${project_name}/Assets.xcassets/*
            cp -r -f ${project_path}/xxx/Assets.xcassets ${project_path}/${project_name}

            cp ${project_path}/xxx/xxx@3x.png ${project_path}/xxx/xxx.bundle
            cp ${project_path}/xxx/xxx@2x.png ${project_path}/xxx/xxx.bundle

        elif [ $1 = "-s2" ];then
            if [ $2 = "-pre" ]; then

                sed -i '' -e "${configLine}s/^.*$/static xxx xxx = xxx;/" ${buildConfig}

            elif [ $2 = "-prd" ];then

                sed -i '' -e "${configLine}s/^.*$/static xxx xxx = xxx;/" ${buildConfig}
            fi

            wx_configLine=$(grep -n "\[WXApi registerApp" "${buildConfig}" | head -1 | cut  -d  ":"  -f  1)
            if [ $wx_configLine ]; then

                sed -i '' -e "${wx_configLine}s/^.*$/ [WXApi registerApp:@\"xxx\"\];/" ${buildConfig}
            fi
            /usr/libexec/PlistBuddy -c "set CFBundleURLTypes:2:CFBundleURLSchemes:0 xxx" ${project_infoplist_path}

#修改支付宝 scheme
sed -i '' 's/^\#define xxx_URL.*$/\#define xxx_URL  @\"xxx.xxx.xxx\"/g' ${configureFile}
/usr/libexec/PlistBuddy -c "set CFBundleURLTypes:0:CFBundleURLSchemes:0 xxx.xxx.xxx" ${project_infoplist_path}

#修改bundleID、版本号、APP名称
            /usr/libexec/PlistBuddy -c "set CFBundleIdentifier com.xxx.xxx" ${project_infoplist_path}
            /usr/libexec/PlistBuddy -c "set CFBundleShortVersionString ${appVersion}" ${project_infoplist_path}
            /usr/libexec/PlistBuddy -c "set CFBundleDisplayName XXX" ${project_infoplist_path}
#文件替换
            rm -rf ${project_path}/${project_name}/Assets.xcassets/*
            cp -r -f ${project_path}/ConfigureSourceFile/S2/Assets.xcassets ${project_path}/${project_name}

            cp ${project_path}/xxx/S2/xxx@3x.png ${project_path}/xxx/xxx.bundle
            cp ${project_path}/xxx/S2/xxx@2x.png ${project_path}/xxx/xxx.bundle
        else
            echo "选择供应商错误, 目前支持的供应商有: s1 s2, 请查正后再试"
        fi
    fi

}

if [ $supplier = "s1" ]; then

    if [ $environment = "pre" ]; then

        config -s1 -pre

    elif [ $environment = "prd" ];then
        config -s1 -prd
    else
        echo "网络环境选择错误,目前 仅支持 pre、prd"
    fi

elif [ $supplier = "s2" ];then
    if [ $environment = "pre" ]; then

        config -s2 -pre

    elif [ $environment = "prd" ];then
    
        config -s2 -prd
    else
        echo "网络环境选择错误,目前 仅支持 pre、prd"
    fi
else

echo "选择供应商错误, 目前支持的供应商有: s1 s2, 请查正后再试"
fi
