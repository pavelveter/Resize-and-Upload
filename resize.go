package main

/*  Программа выполняет ресайз изображений в формате jpeg, что полезно для создания
    уменьшенных версий картинок для просмотра и интернета.

    Как запускать: <resize> [-b=N | -w=X -h=Y] [-c=%] [-f=dir] -o=dir

    w — размер изображения по горизонтали в пикселях
    h — размер изображения по вертикали в пикселях
или b - размер изображения по большей стороне в пикселях

    % — процент сжатия

    f - директория, откуда брать оригинальные фотографии, если не указана - брать из текущей директории
    o - директория, куда складывать сжатые файлы, если её нет - создастся
        
    Примеры: <resize> -w=1920 -h=1280 -c=70 -d="1. Для просмотра и интернета"
             <resize> -b=1920
*/

import (
    "flag"
    "fmt"
//    "log"
//    "os"

//    "image"
//    "image/color"
//    "github.com/disintegration/imaging"
)

const (
    default_out_dir = "Resized"
    default_from_dir = "."
    default_out_width = 1920
    default_out_height = 1280
    default_out_biggest_dim = 0
    default_compress_rate = 79
)

var (
    out_width uint
    out_height uint
    out_biggest_dim uint
    on_big_size bool
    compress_rate uint
    from_dir string
    out_dir string
)

// Получаем флаги командной строки и инициализируем переменные
func ParseCommandLineFlags() {
    flag.UintVar(&out_biggest_dim, "b", default_out_biggest_dim, "biggest dimention")
    flag.UintVar(&out_width, "w", default_out_width, "image width")
    flag.UintVar(&out_height, "h", default_out_height, "image height")
    flag.StringVar(&out_dir, "o", default_out_dir, "output directory")
    flag.StringVar(&from_dir, "f", default_from_dir, "input directory")
    flag.UintVar(&compress_rate, "c", default_compress_rate, "compress rate")
    flag.Parse()

    if out_biggest_dim != 0 {
        on_big_size = true
    }
    return
}

func main() {
    ParseCommandLineFlags()
    fmt.Println(on_big_size)
}
