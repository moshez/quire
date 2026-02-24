import type { CapacitorConfig } from '@capacitor/cli';

const config: CapacitorConfig = {
  appId: 'io.quire.app',
  appName: 'Quire',
  webDir: '.',
  server: {
    androidScheme: 'https',
  },
};

export default config;
