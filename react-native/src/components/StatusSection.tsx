import React from 'react';
import {
  View,
  Text,
  TouchableOpacity,
  ActivityIndicator,
  StyleSheet,
} from 'react-native';

interface Props {
  isLoading: boolean;
  errorMessage: string | null;
  successMessage: string | null;
  downloadProgress: number | null;
  onCancel: () => void;
}

export default function StatusSection({
  isLoading,
  errorMessage,
  successMessage,
  downloadProgress,
  onCancel,
}: Props) {
  return (
    <View>
      {errorMessage && (
        <View style={[styles.statusCard, styles.errorCard]}>
          <Text style={styles.errorText}>{errorMessage}</Text>
        </View>
      )}

      {successMessage && (
        <View style={[styles.statusCard, styles.successCard]}>
          <Text style={styles.successText}>{successMessage}</Text>
        </View>
      )}

      {isLoading && (
        <View style={styles.loadingCard}>
          <View style={styles.loadingRow}>
            <ActivityIndicator size="small" color="#6750a4" />
            <Text style={styles.loadingText}>
              {downloadProgress != null
                ? `下载中 ${Math.round(downloadProgress * 100)}%`
                : '解析中...'}
            </Text>
            <TouchableOpacity onPress={onCancel}>
              <Text style={styles.cancelText}>取消</Text>
            </TouchableOpacity>
          </View>
          {downloadProgress != null && (
            <View style={styles.progressBarBg}>
              <View
                style={[
                  styles.progressBarFill,
                  {width: `${Math.round(downloadProgress * 100)}%`},
                ]}
              />
            </View>
          )}
        </View>
      )}
    </View>
  );
}

const styles = StyleSheet.create({
  statusCard: {
    borderRadius: 12,
    padding: 12,
    marginBottom: 8,
    flexDirection: 'row',
    alignItems: 'center',
  },
  errorCard: {backgroundColor: '#fce4ec'},
  errorText: {color: '#c62828', fontSize: 14, flex: 1},
  successCard: {backgroundColor: '#e8f5e9'},
  successText: {color: '#2e7d32', fontSize: 14, flex: 1},
  loadingCard: {
    backgroundColor: '#fff',
    borderRadius: 12,
    padding: 16,
    shadowColor: '#000',
    shadowOffset: {width: 0, height: 1},
    shadowOpacity: 0.1,
    shadowRadius: 3,
    elevation: 2,
  },
  loadingRow: {
    flexDirection: 'row',
    alignItems: 'center',
  },
  loadingText: {
    flex: 1,
    marginLeft: 12,
    fontSize: 14,
    color: '#1c1b1f',
  },
  cancelText: {
    color: '#6750a4',
    fontSize: 14,
    fontWeight: '600',
  },
  progressBarBg: {
    height: 4,
    backgroundColor: '#e0e0e0',
    borderRadius: 2,
    marginTop: 12,
    overflow: 'hidden',
  },
  progressBarFill: {
    height: '100%',
    backgroundColor: '#6750a4',
    borderRadius: 2,
  },
});
