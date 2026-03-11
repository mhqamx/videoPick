import React, {useState, useCallback} from 'react';
import {
  View,
  ScrollView,
  StyleSheet,
  Alert,
  Platform,
} from 'react-native';
import {useNavigation} from '@react-navigation/native';
import {NativeStackNavigationProp} from '@react-navigation/native-stack';
import {CameraRoll} from '@react-native-camera-roll/camera-roll';
import Clipboard from '@react-native-clipboard/clipboard';
import {RootStackParamList} from '../App';
import {VideoInfo, MediaType} from '../models/VideoInfo';
import {DownloadService} from '../services/DownloadService';
import HeaderSection from '../components/HeaderSection';
import InputSection from '../components/InputSection';
import StatusSection from '../components/StatusSection';
import PreviewSection from '../components/PreviewSection';

type NavigationProp = NativeStackNavigationProp<RootStackParamList>;

export default function DownloadScreen() {
  const navigation = useNavigation<NavigationProp>();

  const [inputText, setInputText] = useState('');
  const [isLoading, setIsLoading] = useState(false);
  const [errorMessage, setErrorMessage] = useState<string | null>(null);
  const [successMessage, setSuccessMessage] = useState<string | null>(null);
  const [videoInfo, setVideoInfo] = useState<VideoInfo | null>(null);
  const [showPreview, setShowPreview] = useState(false);
  const [downloadProgress, setDownloadProgress] = useState<number | null>(null);

  const clearInput = useCallback(() => {
    setInputText('');
    setErrorMessage(null);
    setSuccessMessage(null);
    setVideoInfo(null);
    setShowPreview(false);
    setDownloadProgress(null);
  }, []);

  const pasteFromClipboard = useCallback(async () => {
    const text = await Clipboard.getString();
    if (text) setInputText(text);
  }, []);

  const processInput = useCallback(async () => {
    if (!inputText.trim()) return;

    setIsLoading(true);
    setErrorMessage(null);
    setSuccessMessage(null);
    setVideoInfo(null);
    setShowPreview(false);
    setDownloadProgress(null);

    try {
      const info = await DownloadService.parseAndDownload(
        inputText,
        (progress: number) => {
          setDownloadProgress(progress);
        },
      );
      setVideoInfo(info);
      setShowPreview(true);
      setDownloadProgress(null);
    } catch (e: any) {
      setErrorMessage(e.message ?? String(e));
    } finally {
      setIsLoading(false);
    }
  }, [inputText]);

  const cancelDownload = useCallback(() => {
    setIsLoading(false);
    setDownloadProgress(null);
  }, []);

  const saveMedia = useCallback(async () => {
    if (!videoInfo) return;

    try {
      if (videoInfo.mediaType === MediaType.images) {
        for (const path of videoInfo.localImagePaths) {
          await CameraRoll.saveAsset(
            Platform.OS === 'android' ? `file://${path}` : path,
            {type: 'photo'},
          );
        }
        setSuccessMessage(
          `已保存 ${videoInfo.localImagePaths.length} 张图片到相册`,
        );
      } else if (videoInfo.localPath) {
        await CameraRoll.saveAsset(
          Platform.OS === 'android'
            ? `file://${videoInfo.localPath}`
            : videoInfo.localPath,
          {type: 'video'},
        );
        setSuccessMessage('视频已保存到相册');
      }
    } catch (e: any) {
      Alert.alert('保存失败', e.message ?? String(e));
    }
  }, [videoInfo]);

  const openCookieSettings = useCallback(() => {
    navigation.navigate('CookieSettings');
  }, [navigation]);

  const openFullscreenImage = useCallback(
    (index: number) => {
      if (videoInfo) {
        navigation.navigate('FullscreenImage', {
          imagePaths: videoInfo.localImagePaths,
          initialIndex: index,
        });
      }
    },
    [navigation, videoInfo],
  );

  return (
    <ScrollView
      style={styles.container}
      contentContainerStyle={styles.content}
      keyboardShouldPersistTaps="handled">
      <HeaderSection />
      <View style={styles.spacer20} />
      <InputSection
        inputText={inputText}
        isLoading={isLoading}
        onChangeText={setInputText}
        onClear={clearInput}
        onPaste={pasteFromClipboard}
        onDownload={processInput}
      />
      <View style={styles.spacer16} />
      <StatusSection
        isLoading={isLoading}
        errorMessage={errorMessage}
        successMessage={successMessage}
        downloadProgress={downloadProgress}
        onCancel={cancelDownload}
      />
      <View style={styles.spacer16} />
      <PreviewSection
        videoInfo={videoInfo}
        showPreview={showPreview}
        onSave={saveMedia}
        onImageTap={openFullscreenImage}
      />
    </ScrollView>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: '#f5f5f5',
  },
  content: {
    padding: 16,
  },
  spacer20: {height: 20},
  spacer16: {height: 16},
});
