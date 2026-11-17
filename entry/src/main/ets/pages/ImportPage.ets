import { common } from '@kit.AbilityKit';
import { BusinessError, zlib } from '@kit.BasicServicesKit';
import { fileIo as fs, picker } from '@kit.CoreFileKit';
import {
  ExampleDialog,
  ExampleTurn,
  ImportPageParams,
  ParseResult,
  ParsedMessage,
  PersonaProfile,
  SenderInfo
} from '../model/Models';
import { PersonaDb } from '../database/PersonaDb';
import { ChatParser } from '../services/ChatParser';
import { WeChatExportParser, WxMsg } from '../services/WeChatExportParser';
import { PersonaAnalyzer } from '../services/PersonaAnalyzer';

class DepthOption {
  label: string = '';
  desc: string = '';
  budget: number = 15000;

  constructor(label: string, desc: string, budget: number) {
    this.label = label;
    this.desc = desc;
    this.budget = budget;
  }
}

@Builder
export function ImportPageBuilder(): void {
  ImportPage()
}

@Component
struct ImportPage {
  @State step: number = 0;
  @State senders: SenderInfo[] = [];
  @State messageCount: number = 0;
  @State selfSender: string = '';
  @State myName: string = '';
  @State themName: string = '';
  @State personaCardText: string = '';
  @State profile: PersonaProfile | undefined = undefined;
  @State errorText: string = '';
  @State importing: boolean = false;
  @State progressText: string = '';
  @State depthIndex: number = 0;
  private pathStack: NavPathStack = new NavPathStack();
  private messages: ParsedMessage[] = [];
  private depthOptions: DepthOption[] = [
    new DepthOption('快速', '采样约 1.5 万字，速度最快', 15000),
    new DepthOption('标准', '采样约 3 万字，风格更准（推荐）', 30000),
    new DepthOption('深度', '采样约 6 万字，最全面，耗时较长', 60000)
  ];

  private pickFile(): void {
    const context: common.Context = getContext(this);
    const docPicker = new picker.DocumentViewPicker(context);
    docPicker.select({
      maxSelectNumber: 500,
      fileSuffixFilters: ['文本(.txt)|.txt', '微信导出(.js)|.js', '压缩包(.zip)|.zip']
    })
      .then((uris: Array<string>): void => {
        if (uris.length === 0) {
          return;
        }
        this.processUris(uris);
      })
      .catch((e: BusinessError): void => {
        this.errorText = '选择文件已取消';
      });
  }

  private readText(uri: string): string {
    const file = fs.openSync(uri, fs.OpenMode.READ_ONLY);
    try {
      const stat = fs.statSync(file.fd);
      const buffer = new ArrayBuffer(stat.size);
      fs.readSync(file.fd, buffer);
      return ChatParser.decodeBytes(new Uint8Array(buffer));
    } finally {
      fs.closeSync(file);
    }
  }

  private classifyText(text: string, wxOut: WxMsg[], txtOut: ParsedMessage[]): boolean {
    const trimmed: string = text.trim();
    if (trimmed.startsWith('window.__wxChunk=')) {
      const msgs: WxMsg[] = WeChatExportParser.parseChunk(trimmed);
      for (let i: number = 0; i < msgs.length; i++) {
        wxOut.push(msgs[i]);
      }
      return msgs.length > 0;
    }
    const result: ParseResult = ChatParser.parse(text);
    for (let i: number = 0; i < result.messages.length; i++) {
      txtOut.push(result.messages[i]);
    }
    return result.messages.length > 0;
  }

  private processSingle(uri: string, wxOut: WxMsg[], txtOut: ParsedMessage[]): void {
    const text: string = this.readText(uri);
    if (!this.classifyText(text, wxOut, txtOut)) {
      throw new Error('unrecognized file');
    }
  }

  private async processZip(uri: string, wxOut: WxMsg[], txtOut: ParsedMessage[]): Promise<void> {
    const context: common.Context = getContext(this);
    const stamp: string = Date.now().toString();
    const zipPath: string = context.tempDir + '/import_' + stamp + '.zip';
    const extractDir: string = context.tempDir + '/extract_' + stamp;
    try {
      const srcFile = fs.openSync(uri, fs.OpenMode.READ_ONLY);
      try {
        await fs.copyFile(srcFile.fd, zipPath);
      } finally {
        fs.closeSync(srcFile);
      }
      fs.mkdirSync(extractDir, true);
      await zlib.decompressFile(zipPath, extractDir);
      const names: string[] = fs.listFileSync(extractDir, { recursion: true, listNum: 0 });
      let handled: number = 0;
      for (let i: number = 0; i < names.length; i++) {
        const lower: string = names[i].toLowerCase();
        if (!lower.endsWith('.js') && !lower.endsWith('.txt')) {
          continue;
        }
        try {
          const text: string = this.readText(extractDir + names[i]);
          if (this.classifyText(text, wxOut, txtOut)) {
            handled++;
          }
        } catch (error) {
          continue;
        }
      }
      if (handled === 0) {
        throw new Error('no chat data in zip');
      }
    } finally {
      try {
        fs.rmdirSync(extractDir);
      } catch (error) {
      }
      try {
        fs.unlinkSync(zipPath);
      } catch (error) {
      }
    }
  }

  private async processUris(uris: string[]): Promise<void> {
    this.importing = true;
    this.errorText = '';
    this.progressText = '准备导入…';
    const wxOut: WxMsg[] = [];
    const txtOut: ParsedMessage[] = [];
    let parsedCount: number = 0;
    for (let i: number = 0; i < uris.length; i++) {
      const uri: string = uris[i];
      this.progressText = `正在解析第 ${i + 1}/${uris.length} 个文件…`;
      try {
        const lower: string = uri.toLowerCase();
        if (lower.endsWith('.js') || lower.endsWith('.txt')) {
          this.processSingle(uri, wxOut, txtOut);
        } else {
          await this.processZip(uri, wxOut, txtOut);
        }
        parsedCount++;
      } catch (error) {
        continue;
      }
    }
    this.importing = false;
    this.progressText = '';
    if (parsedCount === 0) {
      this.errorText = '未能识别出聊天记录：请选择 Moect 导出的 c*.js 或其 zip 压缩包，也可以是留痕导出的 txt';
      return;
    }
    this.finalizeImport(wxOut, txtOut);
  }

  private finalizeImport(wxMsgs: WxMsg[], txtMsgs: ParsedMessage[]): void {
    const dominant: WxMsg[] = WeChatExportParser.pickDominantSession(wxMsgs);
    const merged: ParsedMessage[] = txtMsgs.concat(WeChatExportParser.toParsed(dominant));
    const seen: Set<string> = new Set<string>();
    const unique: ParsedMessage[] = [];
    for (let i: number = 0; i < merged.length; i++) {
      const key: string =
        merged[i].time.toString() + '|' + merged[i].sender + '|' + merged[i].text;
      if (!seen.has(key)) {
        seen.add(key);
        unique.push(merged[i]);
      }
    }
    unique.sort((a: ParsedMessage, b: ParsedMessage): number => a.time - b.time);
    if (unique.length === 0) {
      this.errorText = '未能识别出聊天记录：请选择 Moect 导出的 c*.js 或其 zip 压缩包，也可以是留痕导出的 txt';
      return;
    }
    const countMap: Map<string, number> = new Map<string, number>();
    for (let i: number = 0; i < unique.length; i++) {
      const sender: string = unique[i].sender;
      const prev: number | undefined = countMap.get(sender);
      if (prev === undefined) {
        countMap.set(sender, 1);
      } else {
        countMap.set(sender, prev + 1);
      }
    }
    const senders: SenderInfo[] = [];
    countMap.forEach((count: number, name: string) => {
      const info: SenderInfo = { name: name, count: count };
      senders.push(info);
    });
    senders.sort((a: SenderInfo, b: SenderInfo): number => b.count - a.count);
    let selfName: string = senders[0].name;
    let themName: string = senders.length > 1 ? senders[1].name : '';
    if (dominant.length > 0) {
      const wxSelf: string = WeChatExportParser.detectSelf(dominant);
      const wxThem: string = WeChatExportParser.detectThem(dominant);
      if (wxSelf !== '') {
        selfName = wxSelf;
      }
      if (wxThem !== '') {
        themName = wxThem;
      }
    }
    this.errorText = '';
    this.messages = unique;
    this.senders = senders;
    this.messageCount = unique.length;
    this.selfSender = selfName;
    this.myName = selfName;
    this.themName = themName;
    this.step = 1;
  }

  private async loadSample(): Promise<void> {
    const context: common.Context = getContext(this);
    const data: Uint8Array =
      await context.resourceManager.getRawFileContent('sample_chat.txt');
    const text: string = ChatParser.decodeBytes(data);
    const wxOut: WxMsg[] = [];
    const txtOut: ParsedMessage[] = [];
    this.classifyText(text, wxOut, txtOut);
    this.finalizeImport(wxOut, txtOut);
  }

  private selectSelf(name: string): void {
    this.selfSender = name;
    this.myName = name;
    for (let i: number = 0; i < this.senders.length; i++) {
      if (this.senders[i].name !== name) {
        this.themName = this.senders[i].name;
      }
    }
  }

  private async startAnalyze(): Promise<void> {
    if (this.selfSender === '' || this.messages.length === 0) {
      return;
    }
    this.step = 2;
    this.errorText = '';
    const context: common.Context = getContext(this);
    try {
      const profile: PersonaProfile = await PersonaAnalyzer.analyze(context,
        this.messages, this.selfSender, this.themName.trim(),
        this.depthOptions[this.depthIndex].budget);
      this.profile = profile;
      this.personaCardText = profile.personaCard;
      this.step = 3;
    } catch (error) {
      const err = error as BusinessError;
      this.errorText = '分析失败：' + err.message;
      this.step = 1;
    }
  }

  private async savePersona(): Promise<void> {
    if (this.profile === undefined || this.selfSender === '') {
      return;
    }
    const finalProfile: PersonaProfile = this.profile;
    finalProfile.personaCard = this.personaCardText.trim();
    const context: common.Context = getContext(this);
    const profileJson: string = JSON.stringify(finalProfile);
    const personaId: number = await PersonaDb.addPersona(context, this.themName.trim(),
      this.myName.trim(), finalProfile.personaCard, profileJson, this.messages.length);
    await PersonaDb.saveSourceMessages(context, personaId, this.messages);
    const cur: number | undefined = AppStorage.get<number>('personaVersion');
    let next: number = 1;
    if (typeof cur === 'number') {
      next = cur + 1;
    }
    AppStorage.setOrCreate('personaVersion', next);
    this.getUIContext().getPromptAction().showToast({ message: '角色已创建' });
    this.pathStack.pop();
  }

  @Builder
  PickStep() {
    Scroll() {
      Column({ space: 14 }) {
        Text('导入微信聊天记录')
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor('#1A1A1A')
        Text('支持 Moect 导出的微信 PC 聊天记录，也兼容「留痕 MemoTrace」等工具导出的 txt。')
          .fontSize(14)
          .fontColor('#666666')
          .lineHeight(22)
        Column({ space: 6 }) {
          Text('推荐做法')
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontColor('#333333')
          Text('1. 电脑上把导出文件夹内的 c000001.js 等分片文件全部选中，压缩成一个 zip（约十几 MB）\n2. 把 zip 发送到手机\n3. 回到这里选择 zip 导入；也可直接多选 .js 或 .txt 文件')
            .fontSize(12)
            .fontColor('#888888')
            .lineHeight(19)
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .backgroundColor('#EEEEEE')
        .borderRadius(10)
        .padding(12)

        Button(this.importing ? '正在导入…' : '选择聊天记录文件')
          .width('100%')
          .height(46)
          .fontSize(16)
          .backgroundColor('#07C160')
          .enabled(!this.importing)
          .onClick(() => {
            this.pickFile();
          })
        Button('使用示例记录体验')
          .width('100%')
          .height(46)
          .fontSize(16)
          .backgroundColor('#F0F0F0')
          .fontColor('#333333')
          .enabled(!this.importing)
          .onClick(() => {
            this.loadSample();
          })
        if (this.importing) {
          Row({ space: 8 }) {
            LoadingProgress()
              .width(20)
              .height(20)
              .color('#07C160')
            Text(this.progressText)
              .fontSize(13)
              .fontColor('#666666')
          }
          .width('100%')
          .justifyContent(FlexAlign.Center)
        }
        if (this.errorText !== '') {
          Text(this.errorText)
            .fontSize(13)
            .fontColor('#E64340')
        }
      }
      .padding(16)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .layoutWeight(1)
  }

  @Builder
  AnalyzingStep() {
    Column({ space: 16 }) {
      LoadingProgress()
        .width(48)
        .height(48)
        .color('#07C160')
      Text('正在分析聊天记录，生成人设卡…')
        .fontSize(15)
        .fontColor('#333333')
      Text('通常需要 30~60 秒，请保持网络畅通')
        .fontSize(13)
        .fontColor('#999999')
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  ConfirmStep() {
    Scroll() {
      Column({ space: 14 }) {
        Text(`共识别 ${this.messageCount} 条消息`)
          .fontSize(14)
          .fontColor('#666666')
        if (this.senders.length >= 2) {
          Text('哪一个是"我"（你自己）？点击选择')
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor('#1A1A1A')
          ForEach(this.senders, (s: SenderInfo) => {
            Row({ space: 10 }) {
              if (this.selfSender === s.name) {
                Stack() {
                  Text('✓')
                    .fontSize(12)
                    .fontColor(Color.White)
                }
                .width(20)
                .height(20)
                .borderRadius(10)
                .backgroundColor('#07C160')
              } else {
                Stack()
                  .width(20)
                  .height(20)
                  .borderRadius(10)
                  .border({ width: 1.5, color: '#CCCCCC' })
              }
              Text(`${s.name}（${s.count} 条）`)
                .fontSize(15)
                .fontColor('#333333')
            }
            .width('100%')
            .padding(12)
            .borderRadius(10)
            .backgroundColor(this.selfSender === s.name ? '#E8F8EE' : Color.White)
            .onClick(() => {
              this.selectSelf(s.name);
            })
          }, (s: SenderInfo) => s.name)

          Text('角色昵称（TA）')
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor('#1A1A1A')
          TextInput({ text: this.themName })
            .width('100%')
            .height(44)
            .fontSize(15)
            .backgroundColor(Color.White)
            .borderRadius(8)
            .onChange((v: string) => {
              this.themName = v;
            })

          Text('我的昵称')
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor('#1A1A1A')
          TextInput({ text: this.myName })
            .width('100%')
            .height(44)
            .fontSize(15)
            .backgroundColor(Color.White)
            .borderRadius(8)
            .onChange((v: string) => {
              this.myName = v;
            })

          Text('分析深度（聊天记录很多时可提高采样量）')
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor('#1A1A1A')
          ForEach(this.depthOptions, (opt: DepthOption, i: number) => {
            Row({ space: 10 }) {
              if (this.depthIndex === i) {
                Stack() {
                  Text('✓')
                    .fontSize(12)
                    .fontColor(Color.White)
                }
                .width(20)
                .height(20)
                .borderRadius(10)
                .backgroundColor('#07C160')
              } else {
                Stack()
                  .width(20)
                  .height(20)
                  .borderRadius(10)
                  .border({ width: 1.5, color: '#CCCCCC' })
              }
              Column({ space: 2 }) {
                Text(opt.label)
                  .fontSize(15)
                  .fontColor('#333333')
                Text(opt.desc)
                  .fontSize(12)
                  .fontColor('#999999')
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)
            }
            .width('100%')
            .padding(12)
            .borderRadius(10)
            .backgroundColor(this.depthIndex === i ? '#E8F8EE' : Color.White)
            .onClick(() => {
              this.depthIndex = i;
            })
          }, (opt: DepthOption) => opt.label)

          Button('开始生成人设卡')
            .width('100%')
            .height(46)
            .fontSize(16)
            .backgroundColor('#07C160')
            .enabled(this.selfSender !== '' && this.themName.trim() !== ''
              && this.myName.trim() !== '')
            .onClick(() => {
              this.startAnalyze();
            })
        } else {
          Text('只识别到一方的发言，无法建立双人对话，请检查聊天记录文件')
            .fontSize(14)
            .fontColor('#E64340')
            .lineHeight(22)
          Button('重新选择文件')
            .width('100%')
            .height(46)
            .fontSize(16)
            .backgroundColor('#07C160')
            .onClick(() => {
              this.step = 0;
            })
        }
        if (this.errorText !== '') {
          Text(this.errorText)
            .fontSize(13)
            .fontColor('#E64340')
        }
      }
      .padding(16)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .layoutWeight(1)
  }

  @Builder
  LabeledText(label: string, content: string) {
    Column({ space: 4 }) {
      Text(label)
        .fontSize(12)
        .fontColor('#999999')
      Text(content)
        .fontSize(14)
        .fontColor('#333333')
        .lineHeight(21)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  ReviewDetail(profile: PersonaProfile) {
    Column({ space: 10 }) {
      if (profile.relationship !== '') {
        this.LabeledText('关系', profile.relationship)
      }
      if (profile.speakingStyle.length > 0) {
        this.LabeledText('语气特点', profile.speakingStyle.join('、'))
      }
      if (profile.catchphrases.length > 0) {
        this.LabeledText('口头禅', profile.catchphrases.join('、'))
      }
      if (profile.topics.length > 0) {
        this.LabeledText('常聊话题', profile.topics.join('、'))
      }
      if (profile.examples.length > 0) {
        Text('精选对话示例')
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor('#1A1A1A')
        ForEach(profile.examples, (dialog: ExampleDialog, dIndex: number) => {
          Column({ space: 4 }) {
            Text(`示例 ${dIndex + 1}`)
              .fontSize(12)
              .fontColor('#999999')
            ForEach(dialog.messages, (turn: ExampleTurn) => {
              Text((turn.sender === 'me' ? this.myName : this.themName) + '：' + turn.text)
                .fontSize(13)
                .fontColor('#444444')
                .lineHeight(19)
            }, (turn: ExampleTurn, tIndex: number) => `${dIndex}-${tIndex}`)
          }
          .width('100%')
          .padding(10)
          .backgroundColor(Color.White)
          .borderRadius(8)
          .alignItems(HorizontalAlign.Start)
        }, (dialog: ExampleDialog, dIndex: number) => dIndex.toString())
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  ReviewStep() {
    Scroll() {
      Column({ space: 14 }) {
        Text('人设卡（可编辑）')
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor('#1A1A1A')
        TextArea({ text: this.personaCardText })
          .width('100%')
          .height(130)
          .fontSize(14)
          .backgroundColor(Color.White)
          .borderRadius(8)
          .onChange((v: string) => {
            this.personaCardText = v;
          })
        if (this.profile !== undefined) {
          this.ReviewDetail(this.profile)
        }
        Row({ space: 10 }) {
          Button('重新分析')
            .layoutWeight(1)
            .height(44)
            .fontSize(15)
            .backgroundColor('#F0F0F0')
            .fontColor('#333333')
            .onClick(() => {
              this.startAnalyze();
            })
          Button('保存角色')
            .layoutWeight(1)
            .height(44)
            .fontSize(15)
            .backgroundColor('#07C160')
            .onClick(() => {
              this.savePersona();
            })
        }
        .width('100%')
      }
      .padding(16)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .layoutWeight(1)
  }

  build() {
    NavDestination() {
      Column() {
        if (this.step === 0) {
          this.PickStep()
        } else if (this.step === 1) {
          this.ConfirmStep()
        } else if (this.step === 2) {
          this.AnalyzingStep()
        } else {
          this.ReviewStep()
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor('#F7F7F7')
    }
    .title('导入聊天记录')
    .onReady((ctx: NavDestinationContext) => {
      this.pathStack = ctx.pathStack;
      const p = ctx.pathInfo.param as ImportPageParams;
      if (p !== undefined && p !== null && typeof p.autoUri === 'string' && p.autoUri !== '') {
        this.processUris([p.autoUri]).catch((): void => {
          this.importing = false;
          this.progressText = '';
        });
      }
    })
  }
}
