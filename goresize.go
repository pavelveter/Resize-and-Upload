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
	"time"
    "github.com/disintegration/imaging"
)

const (
	default_out_dir       = "1. Для просмотра и интернета"
    default_from_dir      = "2. Для печати и дизайна"
    dir_separator         = "/"
	default_out_width     = 1920
	default_out_height    = 1920
	default_compress_rate = 89
    attention             = "ATTENTION: "
    inp_dir_s             = "input directory of original images"
    out_dir_s             = "output directory for resized images"
    compr_rate_s          = "jpeg compression rate"
    res_max_width_s       = "resized image max width"
    res_max_height_s      = "resized image max height"
    author_s              = "coded by github.com/pavelveter with golang"
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

// Standart if check
func isFatal(message string, err interface{}) {
    if err != nil {
        log.Fatalf(attention + message + " %v", err)
    }
}

// It gets the command line flags and initializes the variables. 
func parseCommandLineFlags() {
	flag.UintVar(&out_width, "w", default_out_width, res_max_width_s)
	flag.UintVar(&out_height, "h", default_out_height, res_max_height_s)
	flag.StringVar(&out_dir, "o", default_out_dir, out_dir_s)
	flag.StringVar(&from_dir, "i", default_from_dir, inp_dir_s)
	flag.UintVar(&compress_rate, "c", default_compress_rate, compr_rate_s)
	flag.Parse()

	if flag.NFlag() == 0 {
		fmt.Println(attention + "No Flags. We use defaults.")
        fmt.Printf("%s: %v, %s: %v\n", res_max_width_s, out_width, res_max_height_s, out_height)
        fmt.Printf(inp_dir_s + ": %s\n", from_dir)
        fmt.Printf(out_dir_s + ": %s\n", out_dir)
        fmt.Printf(compr_rate_s + ": %v%%\n\n", compress_rate)
	}
}

// Let's check the validity of the command line flags. 
func checkVarsForValidity() {
	if compress_rate <= 9 || compress_rate >= 101 {
        fmt.Println(attention + "Compress rate must be in the range of 10 to 100")
		flag.PrintDefaults()
		os.Exit(1)
	}
}

// See if there's a directory to write pictures of, if not, we create it. 
func checkOutputDir() {
    if _, err := os.Stat(out_dir); os.IsNotExist(err) {
        fmt.Printf(attention + "Directory '%s' not found and will be created.\n", out_dir)
        err := os.Mkdir(out_dir, 0755)
        isFatal("Failed to make directory " + out_dir, err)
    }
}

// Return filesize
func sizeOfFile(fname string) uint {
    fi, err := os.Stat(fname)
    isFatal("Failed to get filesize of " + fname, err)

    return uint(fi.Size())
}

// Do resize one picture and do some statistics
func doResizeOneImage(fname string) {
    srcImage, err := imaging.Open(from_dir + dir_separator + fname, imaging.AutoOrientation(true))
    isFatal("Failed to open image: " + fname + " from " + from_dir, err)

  // imaging.Fit — resize to fit in rectangle
    dstImage := imaging.Fit(srcImage, int(out_width), int(out_height), imaging.Lanczos)

    err = imaging.Save(dstImage, out_dir + dir_separator + fname, imaging.JPEGQuality(int(compress_rate)))
    isFatal("Failed to save image:" + fname + " to " + out_dir , err)

    from_file_size := sizeOfFile(from_dir + dir_separator + fname)
    out_file_size := sizeOfFile(out_dir + dir_separator + fname)

    total_files_processed += 1
    total_from_files_size += from_file_size
    total_out_files_size += out_file_size

    fmt.Printf("%s processed, %vk -> %vk.\n", fname, from_file_size / 1024, out_file_size / 1024)
}

// Is the right extension for the picture? 
func isItPictureExtension(fname string) bool {
    switch ext := strings.ToLower(filepath.Ext(fname)); ext {
        case ".jpg": return true
        case ".jpeg": return true
        default: return false
    }
}

// Let's scan the directory where we need to pick up the image files. 
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
    t0 := time.Now()

    parseCommandLineFlags()
	checkVarsForValidity()
    checkOutputDir()
    doFromDirScan()

    fmt.Printf("\nTOTAL: %v files processed, %vM -> %vM. Took time: %3v\n", total_files_processed, total_from_files_size / 1024 / 1024, total_out_files_size / 1024 / 1024, time.Since(t0))
    fmt.Println(author_s)
}
