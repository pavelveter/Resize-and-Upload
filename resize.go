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
    attention             = "ATTENTION: "
)

var (
	out_width uint
	out_height uint
	compress_rate uint
	from_dir string
	out_dir string

    total_files_processed uint
    total_from_files_size uint
    total_out_files_size uint
)

// Надоело писать ифы
func isFatal(message string, err interface{}) {
    if err != nil {
        log.Fatalf(attention + message + " %v", err)
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
		fmt.Println(attention + "No Flags. We use defaults.")
        fmt.Printf("Trying to convert image to fit in rectange %vx%v\n", out_width, out_height)
        fmt.Println("Input Directory:", from_dir)
        fmt.Println("Output Directory:", out_dir)
        fmt.Printf("JPEG Quality: %v%%\n\n", compress_rate)
	}
}

// Проверяем на допустимость флаги командной строки.
func checkVarsForValidity() {
	if compress_rate <= 9 || compress_rate >= 101 {
        fmt.Println(attention + "Compress rate must be in the range of 10 to 100")
		flag.PrintDefaults()
		os.Exit(1)
	}
}

// Проверяем, есть ли директория, куда сливать фотки, если нет — создаём
func checkOutputDir() {
    if _, err := os.Stat(out_dir); os.IsNotExist(err) {
        fmt.Println(attention + "Directory '" + out_dir + "' not found and will be created.")
        err := os.Mkdir(out_dir, 0755)
        isFatal("Failed to make directory " + out_dir, err)
    }
}

// вычисляет размер файла
func sizeOfFile(fname string) uint {
    fi, err := os.Stat(fname)
    isFatal("Failed to get filesize of " + fname, err)

    return uint(fi.Size())
}

// Делаем ресайз одной картинки
func doResizeOneImage(fname string) {
    srcImage, err := imaging.Open(from_dir + dir_separator + fname, imaging.AutoOrientation(true))
    isFatal("Failed to open image: " + fname + " from " + from_dir, err)

  // imaging.Fit — чтобы влезло в прямоугольник заданной ширины
    dstImage := imaging.Fit(srcImage, int(out_width), int(out_height), imaging.Lanczos)

    err = imaging.Save(dstImage, out_dir + dir_separator + fname, imaging.JPEGQuality(int(compress_rate)))
    isFatal("Failed to save image:" + fname + " to " + out_dir , err)

    from_file_size := sizeOfFile(from_dir + dir_separator + fname)
    out_file_size := sizeOfFile(out_dir + dir_separator + fname)

    total_files_processed += 1
    total_from_files_size += from_file_size
    total_out_files_size += out_file_size

    fmt.Println(fname + " processed.", from_file_size / 1024,"kib ->", out_file_size / 1024,"kib")
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
    isFatal("Can't open directory " + from_dir, err)

    files, err := f.Readdir(-1)
    f.Close()
    isFatal("Can't read directory " + from_dir, err)

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

    fmt.Printf("\nTOTAL: %v files processed, %v mib -> %v mib\n", total_files_processed, total_from_files_size / 1024 / 1024, total_out_files_size / 1024 / 1024)
}
