#!/bin/bash

# 定义用到的变量
projectAppPath=""
outputPath=""
ipaFileName=""

# 定义读取输入字符的函数
getProjectAppPath() {
	# 输出换行，方便查看
	echo "\n================================================"
	# 监听输入并且赋值给变量
	read -p " Enter .app path: " projectAppPath
	# 如果为空值，从新监听
	if test -z "$projectAppPath"; then
		getprojectAppPath
	fi
}

getOutputPath() {
	# 输出换行，方便查看
	echo "\n================================================"
	# 监听输入并且赋值给变量
	read -p " Enter output path: " outputPath

	if test -z "$outputPath"; then
		outputPath="Desktop" # 如果没有输出路径，默认输出到桌面
	fi
}

getipaFileName() {
	# 输出换行，方便查看
	echo "\n================================================"
	# 监听输入并且赋值给变量
	read -p " Enter ipa file name: " ipaFileName

	if test -z "$ipaFileName"; then
		getipaFileName
	fi
}

# 执行函数，给变量赋值
getProjectAppPath
getOutputPath
getipaFileName

# 切换到当前用户的home目录，方便创建桌面目录
cd ~

# 在输出路径下创建 Payload 文件夹
mkdir -p "${outputPath}/Payload"

# 将.app 文件复制到 输出路径的 Payload 文件夹下
cp -r "${projectAppPath}" "${outputPath}/Payload/"

# 切换到输出路径
cd "${outputPath}"

# 将 Payload 文件夹压缩成 ipa 包
zip -r "${ipaFileName}.ipa" Payload

# 删除当前路径下 Payload 文件夹【-r 就是向下递归，不管有多少级目录，一并删除 -f 就是直接强行删除，不作任何提示的意思】
rm -rf "Payload"

# 成功提示
echo "\n\n=====================【转换ipa完成】=========================\n"

echo ${outputPath}
## 打开输出的路径
#open -a Finder "${outputPath}"
# 从当前位置打开finder
#open .

# 结束退出
exit 0
