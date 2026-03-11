import React from 'react';
import {NavigationContainer} from '@react-navigation/native';
import {createNativeStackNavigator} from '@react-navigation/native-stack';
import DownloadScreen from './screens/DownloadScreen';
import CookieSettingsScreen from './screens/CookieSettingsScreen';
import FullscreenImageScreen from './screens/FullscreenImageScreen';

export type RootStackParamList = {
  Download: undefined;
  CookieSettings: undefined;
  FullscreenImage: {imagePaths: string[]; initialIndex: number};
};

const Stack = createNativeStackNavigator<RootStackParamList>();

export default function App() {
  return (
    <NavigationContainer>
      <Stack.Navigator>
        <Stack.Screen
          name="Download"
          component={DownloadScreen}
          options={({navigation}) => ({
            title: 'VideoPick',
            headerRight: () => (
              <React.Fragment>
                <CookieButton onPress={() => navigation.navigate('CookieSettings')} />
              </React.Fragment>
            ),
          })}
        />
        <Stack.Screen
          name="CookieSettings"
          component={CookieSettingsScreen}
          options={{title: 'Cookie 设置'}}
        />
        <Stack.Screen
          name="FullscreenImage"
          component={FullscreenImageScreen}
          options={{
            headerShown: false,
            presentation: 'fullScreenModal',
          }}
        />
      </Stack.Navigator>
    </NavigationContainer>
  );
}

import {TouchableOpacity, Text} from 'react-native';

function CookieButton({onPress}: {onPress: () => void}) {
  return (
    <TouchableOpacity onPress={onPress}>
      <Text style={{fontSize: 22}}>🍪</Text>
    </TouchableOpacity>
  );
}
