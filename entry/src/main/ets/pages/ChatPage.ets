import { common } from '@kit.AbilityKit';
import {
  ChatMsg,
  ChatPageParams,
  PersonaProfile,
  PersonaRecord
} from '../model/Models';
import { PersonaDb } from '../database/PersonaDb';
import { SettingsStore } from '../database/SettingsStore';
import { LlmClient, LlmMessage, LlmOptions, StreamHandle } from '../services/LlmClient';
import { PromptBuilder } from '../services/PromptBuilder';
import { UiUtil } from '../common/UiUtil';

@Builder
export function ChatPageBuilder(): void {
  ChatPage()
}

@Component
struct MessageBubble {
  @ObjectLink msg: ChatMsg;
  avatarText: string = '?';
  avatarColor: string = '#5B8DEF';
  onRetry: () => void = (): void => {};

  @Builder
  BubbleBody() {
    Column() {
      if (this.msg.failed) {
        Text(this.msg.text)
          .fontSize(15)
          .fontColor('#D94838')
          .lineHeight(22)
          .padding({ left: 12, right: 12, top: 8, bottom: 8 })
          .backgroundColor('#FDECEC')
          .borderRadius(8)
          .onClick(() => {
            this.onRetry();
          })
      } else if (this.msg.text === '') {
        LoadingProgress()
          .width(22)
          .height(22)
          .padding(10)
          .backgroundColor(Color.White)
          .borderRadius(8)
      } else {
        Text(this.msg.text)
          .fontSize(16)
          .fontColor('#1A1A1A')
          .lineHeight(23)
          .padding({ left: 12, right: 12, top: 8, bottom: 8 })
          .backgroundColor(this.msg.role === 'me' ? '#95EC69' : Color.White)
          .borderRadius(8)
          .copyOption(CopyOptions.LocalDevice)
      }
    }
    .constraintSize({ maxWidth: '76%' })
    .alignItems(this.msg.role === 'me' ? HorizontalAlign.End : HorizontalAlign.Start)
  }

  build() {
    Row({ space: 8 }) {
      if (this.msg.role === 'me') {
        this.BubbleBody()
        Stack() {
          Text(this.avatarText)
            .fontSize(15)
            .fontColor(Color.White)
        }
        .width(36)
        .height(36)
        .borderRadius(18)
        .backgroundColor(this.avatarColor)
      } else {
        Stack() {
          Text(this.avatarText)
            .fontSize(15)
            .fontColor(Color.White)
        }
        .width(36)
        .height(36)
        .borderRadius(18)
        .backgroundColor(this.avatarColor)
        this.BubbleBody()
      }
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 4, bottom: 4 })
  }
}

@Component
struct ChatPage {
  @State messages: ChatMsg[] = [];
  @State inputText: string = '';
  @State streaming: boolean = false;
  @State persona: PersonaRecord | undefined = undefined;
  @State myNameText: string = '';
  @State themNameText: string = '';
  @State emojiOpen: boolean = false;
  private pathStack: NavPathStack = new NavPathStack();
  private listScroller: Scroller = new Scroller();
  private profile: PersonaProfile | undefined = undefined;
  private nextId: number = 1;
  private streamHandle: StreamHandle | undefined = undefined;
  private emojiList: string[] = [
    '😀', '😄', '😁', '🤣', '😂', '🙂', '😉', '😊',
    '😍', '🥰', '😘', '😜', '🤪', '🤔', '🤗', '🤭',
    '😅', '😏', '😌', '😴', '🥱', '😷', '🤒', '🙃',
    '😇', '🥵', '🥶', '🤯', '🥳', '😎', '🤓', '🧐',
    '😕', '😟', '😮', '😲', '😳', '🥺', '😢', '😭',
    '😤', '😠', '😡', '🤬', '🤨', '😒', '😞', '😔',
    '😱', '😨', '😰', '🤝', '🙏', '👍', '👎', '👌',
    '✌️', '🤞', '👏', '🙌', '💪', '❤️', '💔', '💕',
    '🌹', '🎉', '🎂', '🍺', '🍜', '🥟', '☀️', '🔥'
  ];

  private async loadPersona(personaId: number): Promise<void> {
    const context: common.Context = getContext(this);
    try {
      const p: PersonaRecord | undefined = await PersonaDb.getPersona(context, personaId);
      if (p === undefined) {
        this.getUIContext().getPromptAction().showToast({ message: '角色不存在' });
        this.pathStack.pop();
        return;
      }
      this.persona = p;
      this.myNameText = p.myName;
      this.themNameText = p.name;
      try {
        this.profile = JSON.parse(p.profileJson) as PersonaProfile;
      } catch (error) {
        const empty: PersonaProfile = {
          personaCard: p.personaCard,
          speakingStyle: [],
          catchphrases: [],
          topics: [],
          relationship: '',
          examples: []
        };
        this.profile = empty;
      }
      const list: ChatMsg[] = await PersonaDb.loadChat(context, personaId);
      this.messages = list;
      let maxId: number = 0;
      for (let i: number = 0; i < list.length; i++) {
        if (list[i].id > maxId) {
          maxId = list[i].id;
        }
      }
      this.nextId = maxId + 1;
      setTimeout(() => {
        this.scrollToBottom();
      }, 100);
    } catch (error) {
      this.getUIContext().getPromptAction().showToast({ message: '加载失败' });
    }
  }

  private scrollToBottom(): void {
    if (this.messages.length === 0) {
      return;
    }
    this.listScroller.scrollToIndex(this.messages.length - 1);
  }

  private sendMessage(): void {
    const text: string = this.inputText.trim();
    if (text === '' || this.streaming) {
      return;
    }
    if (this.persona === undefined || this.profile === undefined) {
      this.getUIContext().getPromptAction().showToast({ message: '角色数据加载中' });
      return;
    }
    this.inputText = '';
    const meMsg: ChatMsg = new ChatMsg(this.nextId, 'me', text, Date.now(), false, false);
    this.nextId++;
    this.messages.push(meMsg);
    this.scrollToBottom();
    const context: common.Context = getContext(this);
    PersonaDb.addChatMessage(context, this.persona.id, 'me', text, meMsg.ts).catch((): void => {});
    this.requestReply();
  }

  private async requestReply(): Promise<void> {
    if (this.persona === undefined || this.profile === undefined) {
      return;
    }
    this.streaming = true;
    const ph: ChatMsg = new ChatMsg(this.nextId, 'them', '', Date.now(), false, true);
    this.nextId++;
    this.messages.push(ph);
    this.scrollToBottom();
    const context: common.Context = getContext(this);
    const baseUrl: string = await SettingsStore.loadBaseUrl(context);
    const apiKey: string = await SettingsStore.loadApiKey(context);
    const model: string = await SettingsStore.loadModel(context);
    if (this.persona === undefined || this.profile === undefined) {
      return;
    }
    const personaId: number = this.persona.id;
    const systemPrompt: string = PromptBuilder.buildSystemPrompt(this.persona, this.profile);
    const llmMessages: LlmMessage[] = PromptBuilder.buildMessages(systemPrompt, this.messages, 20);
    const options: LlmOptions = { temperature: 0.8, maxTokens: 1024, jsonMode: false };
    this.streamHandle = LlmClient.chatStream(baseUrl, apiKey, model, llmMessages, options,
      (delta: string): void => {
        ph.text += delta;
        this.scrollToBottom();
      },
      (full: string): void => {
        this.streaming = false;
        this.streamHandle = undefined;
        if (full.trim() === '') {
          ph.failed = true;
          ph.text = 'AI 回复为空，点击重试';
          return;
        }
        ph.streaming = false;
        PersonaDb.addChatMessage(context, personaId, 'them', full, Date.now())
          .catch((): void => {});
      },
      (message: string): void => {
        this.streaming = false;
        this.streamHandle = undefined;
        ph.failed = true;
        ph.text = message + '（点击重试）';
      });
  }

  private retryLast(): void {
    if (this.streaming) {
      return;
    }
    for (let i: number = this.messages.length - 1; i >= 0; i--) {
      const m: ChatMsg = this.messages[i];
      if (m.failed) {
        this.messages.splice(i, 1);
        break;
      }
    }
    this.requestReply();
  }

  private confirmClear(): void {
    AlertDialog.show({
      title: '清空对话',
      message: '确定清空当前对话记录吗？',
      primaryButton: {
        value: '清空',
        fontColor: '#D94838',
        action: (): void => {
          this.doClear();
        }
      },
      secondaryButton: {
        value: '取消',
        action: (): void => {}
      }
    });
  }

  private async doClear(): Promise<void> {
    if (this.persona === undefined) {
      return;
    }
    if (this.streamHandle !== undefined) {
      this.streamHandle.cancel();
      this.streamHandle = undefined;
    }
    this.streaming = false;
    const context: common.Context = getContext(this);
    await PersonaDb.clearChat(context, this.persona.id);
    this.messages = [];
    this.nextId = 1;
  }

  private confirmDelete(): void {
    AlertDialog.show({
      title: '删除角色',
      message: '将删除该角色及其全部聊天记录，无法恢复。',
      primaryButton: {
        value: '删除',
        fontColor: '#D94838',
        action: (): void => {
          this.doDelete();
        }
      },
      secondaryButton: {
        value: '取消',
        action: (): void => {}
      }
    });
  }

  private async doDelete(): Promise<void> {
    if (this.persona === undefined) {
      return;
    }
    if (this.streamHandle !== undefined) {
      this.streamHandle.cancel();
      this.streamHandle = undefined;
    }
    const context: common.Context = getContext(this);
    await PersonaDb.deletePersona(context, this.persona.id);
    const cur: number | undefined = AppStorage.get<number>('personaVersion');
    let next: number = 1;
    if (typeof cur === 'number') {
      next = cur + 1;
    }
    AppStorage.setOrCreate('personaVersion', next);
    this.pathStack.pop();
  }

  build() {
    NavDestination() {
      Column() {
        Row() {
          Text('‹')
            .fontSize(30)
            .fontWeight(FontWeight.Medium)
            .fontColor('#1A1A1A')
            .width(42)
            .height(42)
            .textAlign(TextAlign.Center)
            .onClick(() => {
              this.pathStack.pop();
            })
          Text(this.persona === undefined ? '对话' : this.persona.name)
            .layoutWeight(1)
            .fontSize(17)
            .fontWeight(FontWeight.Medium)
            .fontColor('#1A1A1A')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text('⋯')
            .fontSize(22)
            .fontColor('#1A1A1A')
            .width(42)
            .height(42)
            .textAlign(TextAlign.Center)
            .bindMenu([
              { value: '聊天分析', action: (): void => {
                if (this.persona !== undefined) {
                  const param: ChatPageParams = { personaId: this.persona.id };
                  this.pathStack.pushDestinationByName('CoachPage', param).catch((): void => {});
                }
              } },
              { value: '清空聊天记录', action: (): void => {
                this.confirmClear();
              } },
              { value: '删除角色', action: (): void => {
                this.confirmDelete();
              } }
            ])
        }
        .width('100%')
        .height(52)
        .padding({ left: 4, right: 4 })
        .backgroundColor('#F7F7F7')

        List({ scroller: this.listScroller, space: 12 }) {
          if (this.messages.length === 0) {
            ListItem() {
              Text('开始和TA聊天吧')
                .fontSize(14)
                .fontColor('#999999')
            }
          }
          ForEach(this.messages, (msg: ChatMsg, idx: number) => {
            ListItem() {
              Column({ space: 8 }) {
                if (idx === 0 || msg.ts - this.messages[idx - 1].ts > 300000) {
                  Text(UiUtil.formatChatTime(msg.ts, Date.now()))
                    .fontSize(12)
                    .fontColor('#999999')
                    .width('100%')
                    .textAlign(TextAlign.Center)
                }
                MessageBubble({
                  msg: msg,
                  avatarText: msg.role === 'me'
                    ? UiUtil.firstChar(this.myNameText) : UiUtil.firstChar(this.themNameText),
                  avatarColor: msg.role === 'me'
                    ? UiUtil.avatarColor(this.myNameText) : UiUtil.avatarColor(this.themNameText),
                  onRetry: (): void => {
                    this.retryLast();
                  }
                })
              }
              .width('100%')
            }
          }, (msg: ChatMsg) => msg.id.toString())
        }
        .width('100%')
        .layoutWeight(1)
        .backgroundColor('#EDEDED')
        .padding({ top: 12, bottom: 12 })

        if (this.emojiOpen) {
          Grid() {
            ForEach(this.emojiList, (e: string) => {
              GridItem() {
                Text(e)
                  .fontSize(26)
                  .width(38)
                  .height(42)
                  .textAlign(TextAlign.Center)
                  .onClick(() => {
                    this.inputText += e;
                  })
              }
            }, (e: string) => e)
          }
          .columnsTemplate('1fr 1fr 1fr 1fr 1fr 1fr 1fr 1fr')
          .columnsGap(4)
          .height(268)
          .width('100%')
          .padding({ left: 8, right: 8, top: 6, bottom: 6 })
          .backgroundColor('#F7F7F7')
        }

        Row({ space: 8 }) {
          Text(this.emojiOpen ? '⌨' : '😊')
            .fontSize(24)
            .fontColor('#333333')
            .width(36)
            .height(40)
            .textAlign(TextAlign.Center)
            .onClick(() => {
              this.emojiOpen = !this.emojiOpen;
            })
          TextInput({ placeholder: '输入消息…', text: this.inputText })
            .layoutWeight(1)
            .height(40)
            .fontSize(15)
            .backgroundColor(Color.White)
            .borderRadius(6)
            .onChange((v: string) => {
              this.inputText = v;
            })
            .onSubmit(() => {
              this.sendMessage();
            })
          Button(this.streaming ? '…' : '发送')
            .height(40)
            .fontSize(15)
            .backgroundColor('#07C160')
            .enabled(!this.streaming && this.inputText.trim() !== '')
            .onClick(() => {
              this.sendMessage();
            })
        }
        .width('100%')
        .padding(12)
        .backgroundColor('#F7F7F7')
      }
      .width('100%')
      .height('100%')
    }
    .hideTitleBar(true)
    .onReady((ctx: NavDestinationContext) => {
      this.pathStack = ctx.pathStack;
      const p = ctx.pathInfo.param as ChatPageParams;
      if (p !== undefined && p !== null && p.personaId > 0) {
        this.loadPersona(p.personaId);
      }
    })
    .onHidden(() => {
      if (this.streamHandle !== undefined) {
        this.streamHandle.cancel();
        this.streamHandle = undefined;
      }
      this.streaming = false;
    })
  }
}
