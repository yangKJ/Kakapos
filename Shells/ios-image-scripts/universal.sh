#see https://developer.apple.com/library/ios/#documentation/UserExperience/Conceptual/MobileHIG/IconsImages/IconsImages.html#//apple_ref/doc/uid/TP40006556-CH14-SW8

if [ $# -ne 7 ]
then
	echo "Usage: universal.sh <iphone-icon-base-1024x1024> <iphone-icon-base-44x58> <iphone-launch-image-portrait-640x960> <iphone-launch-image-portrait-iphone5-640x1135> <ipad-icon-1024x1024> <ipad-launch-image-portrait-1536x2008> <ipad-launch-image-landscape-2048x1496>"
	exit 1
fi

sh iphone.sh $1 $2 $3 $4
sh ipad.sh $5 $6 $7