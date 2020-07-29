package main

/*  Программа выполняет ресайз изображений в формате jpeg, что полезно для создания
    уменьшенных версий картинок для просмотра и интернета. 

    Как запускать: <resize> [-w=X] [-h=Y] [-c=%] [-i=dir] [-o=dir]

    w — размер изображения по горизонтали в пикселях
    h — размер изображения по вертикали в пикселях
    c — процент сжатия
    i - директория, откуда брать оригинальные фотографии
    o - директория, куда складывать сжатые файлы, если её нет - создастся

    Пример: <resize> -w=1920 -h=1280 -c=70 -d="1. Для просмотра и интернета"
*/

import (
    "flag"
	"fmt"
	"log"
	"os"
    "path/filepath"
    "strings"
	//"image"
	//"image/jpeg"
	"github.com/disintegration/imaging"
)

const (
	default_out_dir       = "1. Для просмотра и интернета"
    default_from_dir      = "2. Для дизайна и печати"
    dir_separator         = "/"
	default_out_width     = 1920
	default_out_height    = 1920
	default_compress_rate = 89
)

var (
	out_width     uint
	out_height    uint
	on_big_size   bool
	compress_rate uint
	from_dir      string
	out_dir       string
)

// Надоело писать ифы
func isFatal(message string, err interface{}) {
    if err != nil {
        log.Fatalf("ATTENTION:" + message + " %v", err)
    }
}

// Получаем флаги командной строки и инициализируем переменные
func parseCommandLineFlags() {
	flag.UintVar(&out_width, "w", default_out_width, "resized image width")
	flag.UintVar(&out_height, "h", default_out_height, "resized image height")
	flag.StringVar(&out_dir, "o", default_out_dir, "output directory for resized images")
	flag.StringVar(&from_dir, "i", default_from_dir, "input directory of original images")
	flag.UintVar(&compress_rate, "c", default_compress_rate, "jpeg compression rate")
	flag.Parse()

	if flag.NFlag() == 0 {
		fmt.Println("ATTENTION: No Flags. We use defaults.")
	}

	if out_height == out_width {
		on_big_size = true
	}
	return
}

// Проверяем на допустимость переменные.
func checkVarsForValidity() {
	if compress_rate <= 9 || compress_rate >= 101 {
		fmt.Println("ATTENTION: Compress rate must be in should be in the range of 10 to 100")
		flag.PrintDefaults()
		os.Exit(1)
	}
}

// Проверяем, есть ли директория, куда сливать фотки, если нет — создаём
func checkOutputDir() {
    if _, err := os.Stat(out_dir); os.IsNotExist(err) {
        fmt.Println("ATTENTION: Directory '" + out_dir + "' not found and will be created.")
        err := os.Mkdir(out_dir, 0755)
        isFatal("Failed to make directory " + out_dir, err)
    }
}

// Делаем ресайз одной картинки
func doResizeOneImage(fname string) {
    srcImage, err := imaging.Open(from_dir + dir_separator + fname, imaging.AutoOrientation(true))
    isFatal("Failed to open image: " + fname + " from " + from_dir, err)

    dstImage := imaging.Fit(srcImage, int(out_width), int(out_height), imaging.Lanczos)

    err = imaging.Save(dstImage, out_dir + dir_separator + fname, imaging.JPEGQuality(int(compress_rate)))
    isFatal("Failed to save image:" + fname + " to " + out_dir , err)

  //  fmt.Println(
}

// Проверяем, что картинка по расширению — картинка
func isItPictureExtension(fname string) bool {
    switch ext := strings.ToLower(filepath.Ext(fname)); ext {
        case ".jpg": return true
        case ".jpeg": return true
        default: return false
    }
}

// Сканируем директорию, откуда надо забирать файлы изображений
func doFromDirScan() {
    f, err := os.Open(from_dir)
    isFatal("Can't open directory" + from_dir, err)

    files, err := f.Readdir(-1)
    f.Close()
    isFatal("Can't read directory", err)

    for _, file := range files {
        if isItPictureExtension(file.Name()) {
            doResizeOneImage(file.Name())
        }
    }
}

func main() {
	parseCommandLineFlags()
	checkVarsForValidity()
    checkOutputDir()
    doFromDirScan()
}
