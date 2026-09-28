# See "Images Fill Their Allotted Space"
# http://developer.apple.com/library/ios/#Documentation/UserExperience/Conceptual/PassKit_PG/Chapters/Creating.html#//apple_ref/doc/uid/TP40012195-CH4-SW52

if [ $# -ne 6 ]
then
	echo "Usage: passkit.sh <background-360x440> <footer-572x30> <icon-100x100> <logo-320x100> <thumbnail-180x180> <strip_event-624x168_with-square-barcode-624x220_other-624x246>"
	exit 1
fi

echo "Generating background."
sips -s format png -z 220 180 $1 --out background.png
sips -s format png -z 440 360 $1 --out background@2x.png

echo "Generating footer."
sips -s format png -z 15 286 $2 --out footer.png
sips -s format png -z 30 572 $2 --out footer@2x.png

echo "Generating icons."
sips -s format png -z 29 29 $1 --out icon.png
sips -s format png -z 58 58 $1 --out icon@2x.png
sips -s format png -z 50 50 $1 --out icon~ipad.png
sips -s format png -z 100 100 $1 --out icon@2x~ipad.png

echo "Generating logo."
sips -s format png -z 50 160 $2 --out logo.png
sips -s format png -z 100 320 $2 --out logo@2x.png

echo "Generating thumbnail."
sips -s format png -z 90 90 $2 --out thumbnail.png
sips -s format png -z 180 180 $2 --out thumbnail@2x.png

echo "Generating strip images. Please choose and rename the required strip image to 'strip.png' and delete others."
echo "Generating images for event tickets."
sips -s format png -z 84 312 $3 --out strip-event.png
sips -s format png -z 168 624 $3 --out strip-event@2x.png
echo "Generating images for other pass styles with a square barcode."
sips -s format png -z 110 312 $3 --out strip-square_barcode.png
sips -s format png -z 220 624 $3 --out strip-square_barcode@2x.png
echo "Generating images for all other pass styles."
sips -s format png -z 123 312 $3 --out strip-other.png
sips -s format png -z 246 624 $3 --out strip-other@2x.png
