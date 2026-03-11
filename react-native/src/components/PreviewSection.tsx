import React from 'react';
import {
  View,
  Text,
  Image,
  TouchableOpacity,
  StyleSheet,
  Dimensions,
} from 'react-native';
import Video from 'react-native-video';
import {VideoInfo, MediaType} from '../models/VideoInfo';

interface Props {
  videoInfo: VideoInfo | null;
  showPreview: boolean;
  onSave: () => void;
  onImageTap: (index: number) => void;
}

const SCREEN_WIDTH = Dimensions.get('window').width - 32; // 16 padding each side

export default function PreviewSection({
  videoInfo,
  showPreview,
  onSave,
  onImageTap,
}: Props) {
  if (!showPreview || !videoInfo) return null;

  return (
    <View>
      {videoInfo.title ? (
        <Text style={styles.title} numberOfLines={2}>
          {videoInfo.title}
        </Text>
      ) : null}

      {videoInfo.mediaType === MediaType.video && videoInfo.localPath && (
        <View style={styles.videoContainer}>
          <Video
            source={{uri: videoInfo.localPath}}
            style={styles.video}
            controls
            resizeMode="contain"
            paused={false}
          />
        </View>
      )}

      {videoInfo.mediaType === MediaType.images &&
        videoInfo.localImagePaths.length > 0 && (
          <View style={styles.imageGrid}>
            {videoInfo.localImagePaths.map((path, index) => (
              <TouchableOpacity
                key={index}
                style={styles.imageWrapper}
                onPress={() => onImageTap(index)}>
                <Image
                  source={{uri: `file://${path}`}}
                  style={styles.gridImage}
                  resizeMode="cover"
                />
              </TouchableOpacity>
            ))}
          </View>
        )}

      <TouchableOpacity style={styles.saveButton} onPress={onSave}>
        <Text style={styles.saveButtonText}>
          {videoInfo.mediaType === MediaType.images
            ? `保存 ${videoInfo.localImagePaths.length} 张图片到相册`
            : '保存视频到相册'}
        </Text>
      </TouchableOpacity>
    </View>
  );
}

const imageSize = (SCREEN_WIDTH - 8) / 3;

const styles = StyleSheet.create({
  title: {
    fontSize: 15,
    fontWeight: '500',
    color: '#1c1b1f',
    marginBottom: 8,
  },
  videoContainer: {
    borderRadius: 12,
    overflow: 'hidden',
    backgroundColor: '#000',
    aspectRatio: 16 / 9,
  },
  video: {
    width: '100%',
    height: '100%',
  },
  imageGrid: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    gap: 4,
  },
  imageWrapper: {
    borderRadius: 8,
    overflow: 'hidden',
  },
  gridImage: {
    width: imageSize,
    height: imageSize,
  },
  saveButton: {
    backgroundColor: '#6750a4',
    paddingVertical: 14,
    borderRadius: 20,
    alignItems: 'center',
    marginTop: 12,
  },
  saveButtonText: {
    color: '#fff',
    fontSize: 15,
    fontWeight: '600',
  },
});
