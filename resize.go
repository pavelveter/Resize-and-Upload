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

var (
    out_w uint
    out_h uint
    out_b uint
    on_big_size bool
    compress_rate uint
    from_dir string
    out_dir string
)

// Получаем флаги командной строки и инициализируем переменные
func ParceCommandLineFlags() {
    flag.UintVar(&out_b, "b", 0, "biggest dimention")
    flag.UintVar(&out_w, "w", 1920, "image width")
    flag.UintVar(&out_h, "h", 1280, "image height")
    flag.StringVar(&out_dir, "o", "Resized", "output directory")
    flag.StringVar(&from_dir, "f", ".", "input directory")
    flag.UintVar(&compress_rate, "c", 79, "compress rate")
    flag.Parse()

    if out_b != 0 {
        on_big_size = true
    }
    return
}

func main() {
    ParceCommandLineFlags()
    fmt.Println(on_big_size)
}
