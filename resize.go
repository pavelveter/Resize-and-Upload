package main

/*  Программа выполняет ресайз изображений в формате jpeg, что полезно для создания
    уменьшенных версий картинок для просмотра и интернета.

    Как запускать: <resize> -w=X [-h=Y] [-c=%] [-f=dir] -o=dir

    w — размер изображения по горизонтали в пикселях
    h — размер изображения по вертикали в пикселях

    c — процент сжатия

    f - директория, откуда брать оригинальные фотографии, если не указана - брать из текущей директории
    o - директория, куда складывать сжатые файлы, если её нет - создастся

    Примеры: <resize> -w=1920 -h=1280 -c=70 -d="1. Для просмотра и интернета"
*/

import (
	"flag"
	"fmt"
	"log"
	"os"
    "path/filepath"
	//    "image"
	//    "image/color"
	    "github.com/disintegration/imaging"
)

const (
	default_out_dir       = "Resized"
	default_from_dir      = "."
    dir_separator         = "/"
	default_out_width     = 1920
	default_out_height    = 0
	default_compress_rate = 79
)

var (
	out_width     uint
	out_height    uint
	on_big_size   bool
	compress_rate uint
	from_dir      string
	out_dir       string
)

// Получаем флаги командной строки и инициализируем переменные
func parseCommandLineFlags() {
	flag.UintVar(&out_width, "w", default_out_width, "resized image width")
	flag.UintVar(&out_height, "h", default_out_height, "resized image height")
	flag.StringVar(&out_dir, "o", default_out_dir, "output directory for resized images")
	flag.StringVar(&from_dir, "f", default_from_dir, "input directory of original images")
	flag.UintVar(&compress_rate, "c", default_compress_rate, "jpeg compress rate")
	flag.Parse()

	if flag.NFlag() == 0 {
		fmt.Println("ATTENTION: No Flags. We use defaults.")
	}

	if out_height == 0 {
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
func checkOutDir() {
    if _, err := os.Stat(out_dir); os.IsNotExist(err) {
        fmt.Println("ATTENTION: Directory '" + out_dir + "' not found and will be created.")
        err := os.Mkdir(out_dir, 0755)
        if err != nil {
            log.Fatal(err)
        }
    }
}

// Делаем ресайз одной картинки
func doResizeOneImage(fname string) {
    srcImage, err := imaging.Open(from_dir + dir_separator + fname, imaging.AutoOrientation(true))
    if err != nil {
        log.Fatalf("ATTENTION: Failed to open image: %v", err)
    }
    
    dstImage := imaging.Resize(srcImage, int(out_width), int(out_height), imaging.Lanczos)

    err = imaging.Save(dstImage, out_dir + dir_separator + fname)
    if err != nil {
        log.Fatalf("ATTENTION: Failed to save image: %v", err)
    }
}

// Сканируем директорию, откуда надо забирать файлы изображений
func doFromDirScan() {
    f, err := os.Open(from_dir)
    if err != nil {
        log.Fatal(err)
    }

    files, err := f.Readdir(-1)
    f.Close()
    if err != nil {
        log.Fatal(err)
    }

    for _, file := range files {
        if ext := filepath.Ext(file.Name()); ext == ".jpg" || ext == ".jpeg" || ext == ".JPG" || ext == ".JPEG" {
            doResizeOneImage(file.Name())
        }
    }
}


func main() {
	parseCommandLineFlags()
	checkVarsForValidity()
    checkOutDir()
    doFromDirScan()
}
