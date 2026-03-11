import React, {useState, useEffect} from 'react';
import {
  View,
  Text,
  TextInput,
  ScrollView,
  TouchableOpacity,
  StyleSheet,
  Alert,
  ActivityIndicator,
  Platform,
} from 'react-native';
import {useNavigation} from '@react-navigation/native';
import {CookieStore, supportedPlatforms} from '../services/CookieStore';

export default function CookieSettingsScreen() {
  const navigation = useNavigation();
  const [values, setValues] = useState<Record<string, string>>({});
  const [loaded, setLoaded] = useState(false);

  useEffect(() => {
    (async () => {
      const newValues: Record<string, string> = {};
      for (const platform of supportedPlatforms) {
        const cookies = await CookieStore.getCookies(platform.platform);
        for (const field of platform.fields) {
          newValues[`${platform.platform}::${field.key}`] =
            cookies[field.key] ?? '';
        }
      }
      setValues(newValues);
      setLoaded(true);
    })();
  }, []);

  const handleSave = async () => {
    for (const platform of supportedPlatforms) {
      const cookies: Record<string, string> = {};
      for (const field of platform.fields) {
        const value = values[`${platform.platform}::${field.key}`] ?? '';
        if (value.trim()) cookies[field.key] = value;
      }
      await CookieStore.saveCookies(platform.platform, cookies);
    }
    Alert.alert('', 'Cookie 已保存');
    navigation.goBack();
  };

  const handleClear = async (platformKey: string) => {
    await CookieStore.clearCookies(platformKey);
    const newValues = {...values};
    const platform = supportedPlatforms.find(p => p.platform === platformKey);
    if (platform) {
      for (const field of platform.fields) {
        newValues[`${platformKey}::${field.key}`] = '';
      }
    }
    setValues(newValues);
  };

  React.useLayoutEffect(() => {
    navigation.setOptions({
      headerRight: () => (
        <TouchableOpacity onPress={handleSave}>
          <Text style={styles.saveButton}>保存</Text>
        </TouchableOpacity>
      ),
    });
  });

  if (!loaded) {
    return (
      <View style={styles.loadingContainer}>
        <ActivityIndicator size="large" />
      </View>
    );
  }

  return (
    <ScrollView style={styles.container} contentContainerStyle={styles.content}>
      {supportedPlatforms.map(platform => (
        <View key={platform.platform} style={styles.card}>
          <View style={styles.cardHeader}>
            <Text style={styles.platformTitle}>{platform.displayName}</Text>
            <TouchableOpacity onPress={() => handleClear(platform.platform)}>
              <Text style={styles.clearButton}>清除</Text>
            </TouchableOpacity>
          </View>
          {platform.fields.map(field => (
            <View key={field.key} style={styles.fieldContainer}>
              <Text style={styles.fieldLabel}>{field.displayName}</Text>
              <TextInput
                style={styles.fieldInput}
                value={values[`${platform.platform}::${field.key}`] ?? ''}
                onChangeText={text =>
                  setValues(prev => ({
                    ...prev,
                    [`${platform.platform}::${field.key}`]: text,
                  }))
                }
                placeholder={field.displayName}
                autoCapitalize="none"
                autoCorrect={false}
              />
            </View>
          ))}
          <Text style={styles.footerText}>{platform.footerText}</Text>
        </View>
      ))}
    </ScrollView>
  );
}

const styles = StyleSheet.create({
  container: {flex: 1, backgroundColor: '#f5f5f5'},
  content: {padding: 16},
  loadingContainer: {flex: 1, justifyContent: 'center', alignItems: 'center'},
  card: {
    backgroundColor: '#fff',
    borderRadius: 12,
    padding: 16,
    marginBottom: 24,
    shadowColor: '#000',
    shadowOffset: {width: 0, height: 1},
    shadowOpacity: 0.1,
    shadowRadius: 3,
    elevation: 2,
  },
  cardHeader: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    marginBottom: 12,
  },
  platformTitle: {fontSize: 17, fontWeight: '600'},
  clearButton: {color: '#ff3b30', fontSize: 15},
  saveButton: {color: '#007AFF', fontSize: 17, fontWeight: '600'},
  fieldContainer: {marginBottom: 12},
  fieldLabel: {fontSize: 13, color: '#666', marginBottom: 4},
  fieldInput: {
    borderWidth: 1,
    borderColor: '#ddd',
    borderRadius: 8,
    padding: 10,
    fontSize: 13,
    fontFamily: Platform.OS === 'ios' ? 'Menlo' : 'monospace',
    backgroundColor: '#fafafa',
  },
  footerText: {fontSize: 12, color: '#999', marginTop: 4},
});
