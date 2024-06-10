if [ $# -ne 3 ]
then
	echo "Usage: ipad.sh <icon-1024x1024> <launch-image-portrait-1536x2008> <launch-image-landscape-2048x1496>"
	exit 1
fi

echo "Generating iPad icons."
sips -s format png -z 128 128 $1 --out Icon-doc@2x~ipad.png
sips -s format png -z 64 64 $1 --out Icon-doc~ipad.png
sips -s format png -z 640 640 $1 --out Icon-doc320@2x~ipad.png
sips -s format png -z 320 320 $1 --out Icon-doc320~ipad.png
sips -s format png -z 100 100 $1 --out Icon-spot@2x~ipad.png
sips -s format png -z 50 50 $1 --out Icon-spot~ipad.png
sips -s format png -z 58 58 $1 --out Icon-settings@2x~ipad.png
sips -s format png -z 29 29 $1 --out Icon-settings~ipad.png
sips -s format png -z 144 144 $1 --out Icon@2x~ipad.png
sips -s format png -z 72 72 $1 --out Icon~ipad.png
sips -s format png -z 1024 1024 $1 --out iTunesArtwork

echo "Generating iPad launch images."
sips -s format png -z 2008 1536 $2 --out Default@2x~ipad.png
sips -s format png -z 1004 768 $2 --out Default~ipad.png
sips -s format png -z 1496 2048 $3 --out Default-Landscape@2x~ipad.png
sips -s format png -z 748 1024 $3 --out Default-Landscape~ipad.png