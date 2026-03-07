/**
 * Capacitor Stub Module — used during Vite dev to satisfy imports.
 *
 * Capacitor packages (@capacitor/preferences, @capacitor/network, etc.)
 * only exist inside native iOS/Android shells. During `vite dev` in a
 * browser, these packages aren't installed. Vite's resolve.alias maps
 * all @capacitor/* imports to this stub file during dev.
 *
 * Every named export is a Proxy that throws on access — matching real
 * Capacitor behavior outside native context. The app's try/catch blocks
 * gracefully degrade when these throw.
 */

function makeStub(name: string) {
  return new Proxy(
    {},
    {
      get(_, prop) {
        if (prop === Symbol.toPrimitive || prop === 'toString' || prop === 'valueOf') {
          return () => `[CapacitorStub:${name}]`;
        }
        // Return a function that throws, so both property access and method calls fail gracefully
        return (..._args: unknown[]) => {
          throw new Error(`Capacitor plugin "${name}" is not available in browser mode`);
        };
      },
    },
  );
}

// @capacitor/preferences
export const Preferences = makeStub('Preferences');

// @capacitor/network
export const Network = makeStub('Network');

// @capacitor/app
export const App = makeStub('App');

// @capacitor/camera
export const Camera = makeStub('Camera');

// @capacitor/geolocation
export const Geolocation = makeStub('Geolocation');

// @capacitor/haptics
export const Haptics = makeStub('Haptics');

// @capacitor/splash-screen
export const SplashScreen = makeStub('SplashScreen');

// @capacitor/status-bar
export const StatusBar = makeStub('StatusBar');

// @capacitor-community/sqlite
export const CapacitorSQLite = makeStub('CapacitorSQLite');
export const SQLiteConnection = makeStub('SQLiteConnection');

// @capacitor/core
export const Capacitor = makeStub('Capacitor');
export const registerPlugin = makeStub('registerPlugin');

// Default export (some packages use default)
export default makeStub('CapacitorDefault');
