### **Setup**

Copy `test.config.example` into `test.config` and set parameters in it.
Copy `links_image.example` into `links_image` and set parameters in it.
Copy `links_video.example` into `links_video` and set parameters in it.

For the script to work correctly, you must place two test files in the directory specified in the **`config.lua`** file under **`config.mediaBaseFilepath`**.


- **`leva_test_video_luamp_do_not_rename.mp4`** - for video tests.
- **`leva_test_image_lua_do_not_rename.jpeg`** - for image tests.

The script should only be run from the `tests` directory.

### **Usage:**

The script supports the following modes of operation:

1. `--init`: initialization - loading the original videos and images for future comparison. This mode should be called once in order to download reference files that test files will be compared against.
2. Without arguments: download and compare both video and image files.
3. `--video`: download and compare video files.
4. `--image`: download and compare image files.

**Initialization (--init)**

To initialize, execute the following command:

```bash
./test.sh --init
```

In this mode, the script will download reference videos and images, calculate their hash sums, and create checksum files for future verification.

**Processing Videos Only (--video)**

To process video files only, execute the following command:

```bash
./test.sh --video
```

In this mode, the script will download and compare video files with reference video files.

**Processing Images Only (--image)**

To process images only, execute the following command:

```bash
./test.sh --image
```

In this mode, the script will download and verify images, comparing them with reference images.

**Processing Both Videos and Images (No Arguments)**

The script can also be run without any arguments, which will compare both video and image files with the reference files:

```bash
./test.sh
```

### **How the Script Works**

The script operates as follows:

- **Initialization (--init):** It downloads the source videos and images, calculates and records their hash sums in respective files. Within the **`tests`** folder, a directory called **`originals`** is created. Subsequently, **`video`** and **`images`** directories are created within it, where the original/reference files are downloaded. In the **`originals`** folder, **`.txt`** files are created, specifically **`checksums.txt`**, **`checksums_video.txt`**, and **`checksums_images.txt`**. Hash sums of the original files are recorded in the **`.txt`** files for future comparisons.


- **Video Testing (--video) and Image Testing (--image):** It loads files for processing and verifies their integrity by comparing them with the original files in the **`originals`** directory. Within the **`tests`** folder, a **`runfiles`** directory is created. Subsequently, **`video`** and **`images`** directories are created within **`runfiles`**, and test files are downloaded into them. In the **`runfiles`** folder, **`.txt`** files are generated, specifically **`checksums_video.txt`** and **`checksums_images.txt`**. In the **`.txt`** files, if the files don't match the originals, it displays an error message; if they match the original files, it shows an **`"OK"`** message.


- **Testing Both Video and Images (Without Arguments):** Performs both types of processing as described above.