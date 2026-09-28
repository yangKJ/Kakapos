#!/bin/bash

# 定义用到的变量
imagePath=""
angle=""

# 定义读取输入字符的函数

getImagePath() {
	echo "\n================================================"
	# 监听输入并且赋值给变量
	read -p "Enter image path: " imagePath
	# 如果为空值，从新监听，否则执行旋转函数
	if	test -z "$imagePath"; then
		 getImagePath
	else
		rotationImage
	fi
}


rotationImage() {
	echo "\n================================================"
	read -p "Enter angle(default 90°): " angle
	# 如果为空值，默认设置为90度
	if test -z "$angle"; then
		angle="90"
	fi

	# 使用 sips 命令进行图片旋转
	sips -r "${angle}" "${imagePath}"
		
	echo "\n rotation $angle ° finished!"
		
	# 重新调用旋转函数，方便多次旋转操作
	rotationImage
	
}

# 首先执行函数，给变量赋值
getImagePath



