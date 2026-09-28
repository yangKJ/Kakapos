if [ $# -ne 4 ]
then
	echo "Usage: iphone.sh <icon-base-1024x1024> <icon-base-44x58> <launch-image-portrait-640x960> <launch-image-portrait-iphone5-640x1135>"
	exit 1
fi

echo "Generating iPhone icons."
sips -s format png -z 29 29 $1 --out Icon-settings.png
sips -s format png -z 58 58 $1 --out Icon-settings@2x.png
sips -s format png -z 57 57 $1 --out Icon.png
sips -s format png -z 114 114 $1 --out Icon@2x.png
sips -s format png -z 1024 1024 $1 --out iTunesArtwork
sips -s format png -z 29 22 $2 --out Icon-doc.png
sips -s format png -z 58 44 $2 --out Icon-doc@2x.png

echo "Generating iPhone launch images."
sips -s format png -z 480 320 $3 --out Default.png
sips -s format png -z 960 640 $3 --out Default@2x.png
sips -s format png -z 1136 640 $4 --out Default-568h@2x.png