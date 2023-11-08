source test.config
CURRENT_DIR=$(pwd)
VIDEO_FILE="leva_test_video_luamp_do_not_rename.mp4"
IMAGE_FILE="leva_test_image_lua_do_not_rename"
IMAGE_FORMATS=("jpeg")
LINKS_VIDEO=($(cat $CURRENT_DIR/links_video))
LINKS_IMAGES=($(cat $CURRENT_DIR/links_image))

if [ $# -eq 0 ]; then
  argument="null"
else
  argument="$1"
fi

if [ "$argument" == "--init" ]; then
    rm -fr ./originals/*
    mkdir -p ./originals/video
    touch ./originals/checksums_video.txt


    INDEX=1
    for LINK in "${LINKS_VIDEO[@]}"
    do
        FULL_LINK="$HOST$LINK"
        wget -q -O "originals/video/$INDEX.mp4" "$FULL_LINK$VIDEO_FILE"
        INDEX=$(expr $INDEX + 1)
    done

    sleep 5

    cd originals/video/
    for FILE in ./*
    do
        shasum "$FILE" >> ../checksums_video.txt
    done

    cd ../../

    mkdir -p ./originals/images
    touch ./originals/checksums_images.txt

    INDEX=1
    for LINK in "${LINKS_IMAGES[@]}"; do
      for FORMAT in "${IMAGE_FORMATS[@]}"; do
        FULL_LINK="$HOST$LINK$IMAGE_FILE.$FORMAT"
        wget -q -O "originals/images/$INDEX.$FORMAT" "$FULL_LINK"
      done
        INDEX=$(expr $INDEX + 1)
    done

    sleep 5

    cd originals/images/
    for FILE in ./*
    do
        shasum "$FILE" >> ../checksums_images.txt
    done

    cd ../
    touch checksums.txt
    cat checksums_video.txt >> checksums.txt
    cat checksums_images.txt >> checksums.txt
fi
if [ "$argument" = "null" ] || [ "$argument" = "--video" ]; then
  cd $CURRENT_DIR
  rm -fr ./runfiles/video
  mkdir -p runfiles/video
  find "$MEDIA_DIR" -name "$VIDEO_FILE" -exec shasum {} + | grep -v "c8b2ca0dde83154818f8718488aa7128f3a15454" | cut -c 43- | xargs rm
  INDEX=1
  for LINK in "${LINKS_VIDEO[@]}"
  do
      FULL_LINK="$HOST$LINK"
      wget -q -O "$CURRENT_DIR/runfiles/video/$INDEX.mp4" "$FULL_LINK$VIDEO_FILE"
      diff <(cd originals/video && ffprobe -hide_banner $INDEX.mp4 2>&1) <(cd runfiles/video && ffprobe -hide_banner $INDEX.mp4 2>&1)
      INDEX=$(expr $INDEX + 1)
  done
  cp originals/checksums_video.txt runfiles/checksums_video.txt
  cd runfiles/video/
  shasum -c $CURRENT_DIR/runfiles/checksums_video.txt
fi
if [ "$argument" = "null" ] || [ "$argument" = "--image" ]; then
  cd $CURRENT_DIR
  rm -fr ./runfiles/images
  mkdir -p  runfiles/images
  find "$MEDIA_DIR" -name "$IMAGE_FILE" -exec shasum {} + | grep -v "fb02cdbe98744713d2b9ef09a2e264b56fd8274b" | cut -c 43- | xargs rm
  INDEX=1
  for LINK in "${LINKS_IMAGES[@]}"; do
    for FORMAT in "${IMAGE_FORMATS[@]}"; do
      FULL_LINK="$HOST$LINK$IMAGE_FILE.$FORMAT"
      wget -q -O "$CURRENT_DIR/runfiles/images/$INDEX.$FORMAT" "$FULL_LINK"
      diff <(cd originals/images && ffprobe -hide_banner "$INDEX.$FORMAT" 2>&1) <(cd runfiles/images && ffprobe -hide_banner "$INDEX.$FORMAT" 2>&1)
    done
    INDEX=$(expr $INDEX + 1)
  done
  cp originals/checksums_images.txt runfiles/checksums_images.txt
  cd runfiles/images
  shasum -c $CURRENT_DIR/runfiles/checksums_images.txt
fi
