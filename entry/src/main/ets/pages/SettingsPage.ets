import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { SettingsStore } from '../database/SettingsStore';
import { LlmClient, LlmMessage, LlmOptions } from '../services/LlmClient';

@Builder
export function SettingsPageBuilder(): void {
  SettingsPage()
}

@Component
struct SettingsPage {
  @State apiKey: string = '';
  @State baseUrl: string = '';
  @State model: string = SettingsStore.DEFAULT_MODEL;
  @State modelOptions: string[] = [];
  @State fetchingModels: boolean = false;
  @State modelFetchError: string = '';
  @State testing: boolean = false;
  @State testResult: string = '';
  @State testOk: boolean = false;
  private pathStack: NavPathStack = new NavPathStack();

  aboutToAppear(): void {
    const context: common.Context = getContext(this);
    SettingsStore.loadApiKey(context).then((v: string): void => {
      this.apiKey = v;
    });
    SettingsStore.loadBaseUrl(context).then((v: string): void => {
      this.baseUrl = v;
    });
    SettingsStore.loadModel(context).then((v: string): void => {
      this.model = v;
    });
  }

  private async saveSettings(): Promise<void> {
    const context: common.Context = getContext(this);
    await SettingsStore.saveApiKey(context, this.apiKey.trim());
    await SettingsStore.saveBaseUrl(context, this.baseUrl.trim() === ''
      ? SettingsStore.DEFAULT_BASE_URL : this.baseUrl.trim());
    await SettingsStore.saveModel(context, this.model.trim() === ''
      ? SettingsStore.DEFAULT_MODEL : this.model.trim());
  }

  private resolveModel(): string {
    return this.model.trim() === '' ? SettingsStore.DEFAULT_MODEL : this.model.trim();
  }

  private async fetchModels(): Promise<void> {
    if (this.fetchingModels) {
      return;
    }
    const key: string = this.apiKey.trim();
    if (key === '') {
      this.modelFetchError = '请先填写 API Key';
      return;
    }
    this.fetchingModels = true;
    this.modelFetchError = '';
    const base: string = this.baseUrl.trim() === ''
      ? SettingsStore.DEFAULT_BASE_URL : this.baseUrl.trim();
    try {
      const list: string[] = await LlmClient.listModels(base, key);
      this.modelOptions = list;
    } catch (error) {
      const err = error as BusinessError;
      this.modelOptions = [];
      this.modelFetchError = '获取失败：' + err.message;
    }
    this.fetchingModels = false;
  }

  private async testConnection(): Promise<void> {
    if (this.testing) {
      return;
    }
    this.testing = true;
    this.testResult = '';
    await this.saveSettings();
    const messages: LlmMessage[] = [{ role: 'user', content: '请只回复四个字：连接成功' }];
    const options: LlmOptions = { temperature: 0.1, maxTokens: 20, jsonMode: false };
    const model: string = this.resolveModel();
    try {
      const reply: string = await LlmClient.chat(this.baseUrl.trim() === ''
        ? SettingsStore.DEFAULT_BASE_URL : this.baseUrl.trim(),
      this.apiKey.trim(), model, messages, options);
      this.testOk = true;
      this.testResult = '连接成功：' + reply;
    } catch (error) {
      const err = error as BusinessError;
      this.testOk = false;
      this.testResult = '连接失败：' + err.message;
    }
    this.testing = false;
  }

  build() {
    NavDestination() {
      Scroll() {
        Column({ space: 14 }) {
          Text('DeepSeek API Key')
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor('#1A1A1A')
          TextInput({ text: this.apiKey, placeholder: 'sk-...' })
            .width('100%')
            .height(44)
            .fontSize(14)
            .type(InputType.Password)
            .backgroundColor(Color.White)
            .borderRadius(8)
            .onChange((v: string) => {
              this.apiKey = v;
            })

          Text('API 地址')
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor('#1A1A1A')
          TextInput({ text: this.baseUrl, placeholder: SettingsStore.DEFAULT_BASE_URL })
            .width('100%')
            .height(44)
            .fontSize(14)
            .backgroundColor(Color.White)
            .borderRadius(8)
            .onChange((v: string) => {
              this.baseUrl = v;
            })

          Text('模型')
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor('#1A1A1A')
          TextInput({ text: this.model, placeholder: '输入模型名，或点击下方按钮获取' })
            .width('100%')
            .height(44)
            .fontSize(14)
            .backgroundColor(Color.White)
            .borderRadius(8)
            .onChange((v: string) => {
              this.model = v;
            })

          Button(this.fetchingModels ? '获取中…' : '获取可用模型列表')
            .width('100%')
            .height(40)
            .fontSize(14)
            .backgroundColor('#F0F0F0')
            .fontColor('#333333')
            .enabled(!this.fetchingModels)
            .margin({ top: 8 })
            .onClick(() => {
              this.fetchModels();
            })

          if (this.modelFetchError !== '') {
            Text(this.modelFetchError)
              .fontSize(12)
              .fontColor('#E64340')
          }
          if (this.modelOptions.length > 0) {
            Text('共 ' + this.modelOptions.length + ' 个可用模型，点击选择')
              .fontSize(12)
              .fontColor('#999999')
            ForEach(this.modelOptions, (m: string) => {
              Text(m)
                .fontSize(14)
                .fontWeight(this.resolveModel() === m ? FontWeight.Bold : FontWeight.Normal)
                .fontColor(this.resolveModel() === m ? '#07C160' : '#333333')
                .width('100%')
                .padding({ top: 9, bottom: 9 })
                .onClick(() => {
                  this.model = m;
                  this.saveSettings();
                })
            }, (m: string) => m)
          }

          Button(this.testing ? '测试中…' : '测试连接')
            .width('100%')
            .height(44)
            .fontSize(15)
            .backgroundColor('#F0F0F0')
            .fontColor('#333333')
            .enabled(!this.testing)
            .onClick(() => {
              this.testConnection();
            })

          if (this.testResult !== '') {
            Text(this.testResult)
              .fontSize(13)
              .fontColor(this.testOk ? '#07C160' : '#E64340')
              .lineHeight(19)
          }

          Button('保存')
            .width('100%')
            .height(46)
            .fontSize(16)
            .backgroundColor('#07C160')
            .onClick(() => {
              this.saveSettings().then((): void => {
                this.getUIContext().getPromptAction().showToast({ message: '已保存' });
              });
            })

          Text('API Key 仅保存在本机，用于直接请求 DeepSeek 接口。')
            .fontSize(12)
            .fontColor('#999999')
        }
        .padding(16)
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .height('100%')
      .backgroundColor('#F7F7F7')
    }
    .title('设置')
    .onReady((ctx: NavDestinationContext) => {
      this.pathStack = ctx.pathStack;
    })
  }
}
