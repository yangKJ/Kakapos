if [ $# -ne 1 ]
then
	echo "Usage: toolbar.sh <icon-40x40>"
	exit 1
fi

[[ $1 =~ ([^.]*)\..{3}.? ]]
filePrefix=${BASH_REMATCH[1]}

iconPrefix="Toolbar-icon-"$filePrefix
icon=$iconPrefix".png"
retinaIcon=$iconPrefix"@2x.png"

echo "Generating tool- or navigation bar icons."
sips -s format png -z 40 40 $1 --out $retinaIcon
sips -s format png -z 20 20 $1 --out $icon