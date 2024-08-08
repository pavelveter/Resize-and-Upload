#!/usr/bin/env bash

# Путь к папке с изображениями
directory="1. Для просмотра и интернета"

# Функция для склонения слов
decline_word() {
    number=$1
    word_one=$2
    word_two=$3
    word_five=$4

    if (( number % 10 == 1 && number % 100 != 11 )); then
        echo "$word_one"
    elif (( number % 10 >= 2 && number % 10 <= 4 && (number % 100 < 10 || number % 100 >= 20) )); then
        echo "$word_two"
    else
        echo "$word_five"
    fi
}

# Проверка наличия первого параметра для указания пользовательской папки
if [[ -n "$1" ]]; then
    directory="$1"
fi

# Проверка наличия папки и файлов
if [[ ! -d "$directory" || ! $(ls "$directory"/*.jpg 2>/dev/null) ]]; then
    echo "Ошибка: Папка '$directory' не существует или не содержит файлов jpg."
    exit 1
fi

# Извлечение данных из изображений
exif_data=$(exiftool -T -createdate -model -lensmodel -flash -filename "$directory"/*.jpg | sort)

# Получение даты и времени создания первого и последнего изображения
first_image=$(echo "$exif_data" | head -n 1 | awk -F'\t' '{print $1}')
last_image=$(echo "$exif_data" | tail -n 1 | awk -F'\t' '{print $1}')
camera_models=$(echo "$exif_data" | awk -F'\t' '{print $2}' | sort | uniq)
lenses=$(echo "$exif_data" | awk -F'\t' '{print $3}' | sort | uniq)

# Замена двоеточий на точки в датах, сохранение двоеточий во времени
first_image_date=$(echo "$first_image" | awk '{print $1}' | sed 's/:/./g')
first_image_time=$(echo "$first_image" | awk '{print $2}')
last_image_date=$(echo "$last_image" | awk '{print $1}' | sed 's/:/./g')
last_image_time=$(echo "$last_image" | awk '{print $2}')

# Преобразование даты в формат
translate_month() {
    date_string=$1
    formatted_date=$(date -j -f "%Y.%m.%d" "$date_string" "+%d %B %Y")
    echo "$formatted_date" | sed 's/January/января/; s/February/февраля/; s/March/марта/; s/April/апреля/; s/May/мая/; s/June/июня/; s/July/июля/; s/August/августа/; s/September/сентября/; s/October/октября/; s/November/ноября/; s/December/декабря/'
}

formatted_first_date=$(translate_month "$first_image_date")
formatted_last_date=$(translate_month "$last_image_date")

# Условное отображение даты и времени
if [[ "$first_image_date" == "$last_image_date" ]]; then
    echo "Съёмка велась ${formatted_first_date} года, с ${first_image_time} до ${last_image_time}."
else
    echo "Съёмка велась с ${formatted_first_date} года, ${first_image_time} до ${formatted_last_date} года, ${last_image_time}."
fi

# Преобразование дат в формат UNIX time
first_time=$(date -j -f "%Y.%m.%d %H:%M:%S" "${first_image_date} ${first_image_time}" "+%s" 2>/dev/null)
last_time=$(date -j -f "%Y.%m.%d %H:%M:%S" "${last_image_date} ${last_image_time}" "+%s" 2>/dev/null)

# Проверка успешности преобразования даты
if [[ -z "$first_time" || -z "$last_time" ]]; then
    echo "Не удалось распознать даты. Убедитесь, что даты в правильном формате."
    exit 1
fi

# Расчёт длительности съёмки в минутах
duration=$(( (last_time - first_time) / 60 ))

# Подсчёт количества файлов
num_files=$(find "$directory" -maxdepth 1 -type f -name "*.jpg" | wc -l | xargs)

# Расчёт кадров в минуту с плавающей запятой
if [[ $duration -gt 0 ]]; then
    num_files_word=$(decline_word "$num_files" "кадр" "кадра" "кадров")
    duration_word=$(decline_word "$duration" "минута" "минуты" "минут")
    echo "Длительность – $duration $duration_word, получилось $num_files $num_files_word."

    frames_per_minute=$(echo "scale=2; $num_files / $duration" | bc)
    if [[ "$frames_per_minute" == *.* ]]; then
      frames_per_minute_word="кадра"
    else
      frames_per_minute_word=$(decline_word "${frames_per_minute%.*}" "кадр" "кадра" "кадров")
    fi
    echo "В среднем – $frames_per_minute $frames_per_minute_word в минуту."
else
    echo "Длительность съёмки слишком коротка для рассчёта количества кадров в минуту."
fi

# Подсчёт количества кадров для каждой камеры и линзы
declare -A camera_counts
declare -A lens_counts
flash_count=0

while IFS=$'\t' read -r _ camera lens flash _; do
    ((camera_counts["$camera"]++))
    ((lens_counts["$lens"]++))
    if [[ "$flash" == "On, Fired" ]]; then
        ((flash_count++))
    fi
done <<< "$exif_data"

# Определение количества уникальных камер и линз
num_cameras=$(echo "$camera_models" | wc -l | xargs)
num_lenses=$(echo "$lenses" | wc -l | xargs)

# Вывод моделей камер и линз с количеством кадров, если их больше одной
echo -e "\nИспользованные камеры:"
for camera in "${!camera_counts[@]}"; do
    if [[ $num_cameras -gt 1 ]]; then
        camera_word=$(decline_word "${camera_counts[$camera]}" "кадр" "кадра" "кадров")
        echo "${camera//ILCE-/Sony } (${camera_counts[$camera]} $camera_word)"
    else
        echo "${camera//ILCE-/Sony }"
    fi
done

echo -e "\nИспользованные объективы:"
for lens in "${!lens_counts[@]}"; do
    if [[ $num_lenses -gt 1 ]]; then
        lens_word=$(decline_word "${lens_counts[$lens]}" "кадр" "кадра" "кадров")
        echo "$lens (${lens_counts[$lens]} $lens_word)"
    else
        echo "$lens"
    fi
done

# Вывод количества срабатываний вспышки, если больше нуля
if [[ $flash_count -gt 0 ]]; then
    flash_word=$(decline_word "$flash_count" "раз" "раза" "раз")
    echo -e "\nСрабатывание вспышки: $flash_count $flash_word."
fi

# Расчёт времени, прошедшего с момента съёмки последнего фото
current_time=$(date "+%s")
time_since_shooting=$((current_time - last_time))
days_since=$((time_since_shooting / 86400))
hours_since=$(( (time_since_shooting % 86400) / 3600 ))

days_word=$(decline_word "$days_since" "день" "дня" "дней")
hours_word=$(decline_word "$hours_since" "час" "часа" "часов")

echo -e "\nВремя, прошедшее с момента последнего фото: $days_since $days_word, $hours_since $hours_word."