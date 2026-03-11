import React from 'react';
import {View, Text, StyleSheet} from 'react-native';

const PLATFORMS = ['抖音', 'TikTok', 'Instagram', 'X (Twitter)', 'B站', '快手', '小红书'];

export default function HeaderSection() {
  return (
    <View style={styles.container}>
      <View style={styles.iconContainer}>
        <Text style={styles.icon}>🎬</Text>
      </View>
      <Text style={styles.title}>短视频/图文下载</Text>
      <Text style={styles.subtitle}>无水印下载，支持视频和图文</Text>
      <View style={styles.chipContainer}>
        {PLATFORMS.map(p => (
          <View key={p} style={styles.chip}>
            <Text style={styles.chipText}>{p}</Text>
          </View>
        ))}
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {alignItems: 'center'},
  iconContainer: {
    width: 56,
    height: 56,
    borderRadius: 28,
    backgroundColor: '#e8def8',
    justifyContent: 'center',
    alignItems: 'center',
  },
  icon: {fontSize: 28},
  title: {
    fontSize: 22,
    fontWeight: '700',
    marginTop: 12,
    color: '#1c1b1f',
  },
  subtitle: {
    fontSize: 14,
    color: '#79747e',
    marginTop: 4,
  },
  chipContainer: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    justifyContent: 'center',
    marginTop: 12,
    gap: 6,
  },
  chip: {
    backgroundColor: '#e8e8e8',
    paddingHorizontal: 10,
    paddingVertical: 4,
    borderRadius: 16,
  },
  chipText: {fontSize: 12, color: '#444'},
});
