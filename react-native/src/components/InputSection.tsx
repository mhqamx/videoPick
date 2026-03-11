import React from 'react';
import {View, TextInput, TouchableOpacity, Text, StyleSheet} from 'react-native';

interface Props {
  inputText: string;
  isLoading: boolean;
  onChangeText: (text: string) => void;
  onClear: () => void;
  onPaste: () => void;
  onDownload: () => void;
}

export default function InputSection({
  inputText,
  isLoading,
  onChangeText,
  onClear,
  onPaste,
  onDownload,
}: Props) {
  return (
    <View>
      <View style={styles.inputContainer}>
        <TextInput
          style={styles.textInput}
          value={inputText}
          onChangeText={onChangeText}
          placeholder="粘贴分享链接到这里..."
          placeholderTextColor="#999"
          multiline
          numberOfLines={3}
          editable={!isLoading}
        />
        {inputText.length > 0 && !isLoading && (
          <TouchableOpacity style={styles.clearBtn} onPress={onClear}>
            <Text style={styles.clearBtnText}>✕</Text>
          </TouchableOpacity>
        )}
      </View>
      <View style={styles.buttonRow}>
        <TouchableOpacity
          style={[styles.button, styles.outlineButton]}
          onPress={onPaste}
          disabled={isLoading}>
          <Text style={[styles.buttonText, styles.outlineButtonText]}>
            粘贴
          </Text>
        </TouchableOpacity>
        <View style={styles.buttonSpacer} />
        <TouchableOpacity
          style={[
            styles.button,
            styles.filledButton,
            (isLoading || !inputText.trim()) && styles.disabledButton,
          ]}
          onPress={onDownload}
          disabled={isLoading || !inputText.trim()}>
          <Text style={[styles.buttonText, styles.filledButtonText]}>
            下载
          </Text>
        </TouchableOpacity>
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  inputContainer: {
    borderWidth: 1,
    borderColor: '#ddd',
    borderRadius: 12,
    backgroundColor: '#fff',
    position: 'relative',
  },
  textInput: {
    padding: 12,
    fontSize: 15,
    minHeight: 80,
    textAlignVertical: 'top',
    color: '#1c1b1f',
  },
  clearBtn: {
    position: 'absolute',
    top: 8,
    right: 8,
    width: 24,
    height: 24,
    borderRadius: 12,
    backgroundColor: '#ddd',
    justifyContent: 'center',
    alignItems: 'center',
  },
  clearBtnText: {fontSize: 12, color: '#666'},
  buttonRow: {
    flexDirection: 'row',
    marginTop: 12,
  },
  button: {
    flex: 1,
    paddingVertical: 12,
    borderRadius: 20,
    alignItems: 'center',
    justifyContent: 'center',
  },
  buttonSpacer: {width: 12},
  outlineButton: {
    borderWidth: 1,
    borderColor: '#6750a4',
  },
  filledButton: {
    backgroundColor: '#6750a4',
  },
  disabledButton: {
    opacity: 0.5,
  },
  buttonText: {fontSize: 15, fontWeight: '600'},
  outlineButtonText: {color: '#6750a4'},
  filledButtonText: {color: '#fff'},
});
