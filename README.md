# Resize and Upload

![Screenshot of go resize cli utility](https://i.ibb.co/nC6BpQ3/Screenshot-2020-07-31-at-21-03-40.png)

## Overview

**Resize and Upload** is a powerful, multithreaded JPEG resize utility designed for photographers. This tool, written in Go, automates the process of resizing and uploading photos to the cloud. After uploading, it even sends a link to the images via Telegram.

## Features

- **Multithreaded Processing**: Efficiently handles multiple images simultaneously.
- **JPEG Resize**: Reduces the size of JPEG images to optimize storage and upload times.
- **Cloud Upload**: Automatically uploads resized images to a specified cloud service.
- **Telegram Integration**: Sends a link to the uploaded images directly to a Telegram chat.

## Installation

To get started with Resize and Upload, follow these steps:

1. **Clone the repository**:
    ```sh
    git clone https://github.com/pavelveter/Resize-and-Upload.git
    cd Resize-and-Upload
    ```

2. **Install dependencies**:
    Ensure you have Go installed on your system. Then, run:
    ```sh
    go mod tidy
    ```

## Usage

### Resizing Images

To resize images, use the `goresize.go` script. This script processes JPEG images and reduces their size.

```sh
./goresize.go /path/to/images

```

### Uploading Images

Instead only resizing, you can resize and upload the images using the up2cloud.sh script. This script uploads the images to your specified cloud service. You'll get a thumbails and link to your Telegram after upload.

```sh
up2cloud /path/to/resized/images
```

## Configuration

Before running the scripts, ensure you configure the necessary settings:

Cloud Service Credentials: Update the up2cloud.sh script with your cloud service credentials. Double check all paths in scripts.
Telegram Bot Token and Chat ID: Update alias in your .zshrc for something like this:

```sh
up2cloud='TG_API=<api_key> TG_CHAT=-<chat_number> ~/veter_scripts/go/goresize/up2cloud.sh'
```

### License

This project is licensed under the MIT License. See the LICENSE file for details.
