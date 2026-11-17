import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';

export class SettingsStore {
  private static readonly PREF_NAME: string = 'echo_settings';
  private static readonly KEY_API_KEY: string = 'deepseek_api_key';
  private static readonly KEY_BASE_URL: string = 'deepseek_base_url';
  private static readonly KEY_MODEL: string = 'deepseek_model';
  public static readonly DEFAULT_BASE_URL: string = 'https://api.deepseek.com';
  public static readonly DEFAULT_MODEL: string = 'deepseek-chat';

  private static async open(context: common.Context): Promise<preferences.Preferences> {
    return await preferences.getPreferences(context, SettingsStore.PREF_NAME);
  }

  static async loadApiKey(context: common.Context): Promise<string> {
    const store: preferences.Preferences = await SettingsStore.open(context);
    return store.getSync(SettingsStore.KEY_API_KEY, '') as string;
  }

  static async saveApiKey(context: common.Context, value: string): Promise<void> {
    const store: preferences.Preferences = await SettingsStore.open(context);
    store.putSync(SettingsStore.KEY_API_KEY, value);
    await store.flush();
  }

  static async loadBaseUrl(context: common.Context): Promise<string> {
    const store: preferences.Preferences = await SettingsStore.open(context);
    const value: string =
      store.getSync(SettingsStore.KEY_BASE_URL, SettingsStore.DEFAULT_BASE_URL) as string;
    if (value === '') {
      return SettingsStore.DEFAULT_BASE_URL;
    }
    return value;
  }

  static async saveBaseUrl(context: common.Context, value: string): Promise<void> {
    const store: preferences.Preferences = await SettingsStore.open(context);
    store.putSync(SettingsStore.KEY_BASE_URL, value);
    await store.flush();
  }

  static async loadModel(context: common.Context): Promise<string> {
    const store: preferences.Preferences = await SettingsStore.open(context);
    const value: string =
      store.getSync(SettingsStore.KEY_MODEL, SettingsStore.DEFAULT_MODEL) as string;
    if (value === '') {
      return SettingsStore.DEFAULT_MODEL;
    }
    return value;
  }

  static async saveModel(context: common.Context, value: string): Promise<void> {
    const store: preferences.Preferences = await SettingsStore.open(context);
    store.putSync(SettingsStore.KEY_MODEL, value);
    await store.flush();
  }
}
