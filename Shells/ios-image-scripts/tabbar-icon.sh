if [ $# -ne 1 ]
then
	echo "Usage: tabbar-icon.sh <icon-60x60>"
	exit 1
fi

[[ $1 =~ ([^.]*)\..{3}.? ]]
filePrefix=${BASH_REMATCH[1]}

iconPrefix="Tabbar-icon-"$filePrefix
icon=$iconPrefix".png"
retinaIcon=$iconPrefix"@2x.png"

echo "Generating tab bar icons."
sips -s format png -z 60 60 $1 --out $retinaIcon
sips -s format png -z 30 30 $1 --out $icon