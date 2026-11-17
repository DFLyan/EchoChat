import { BusinessError } from '@kit.BasicServicesKit';
import { ChatPageParams, ImportPageParams, PersonaRecord } from '../model/Models';
import { PersonaDb } from '../database/PersonaDb';
import { UiUtil } from '../common/UiUtil';

@Entry
@Component
struct Index {
  @State personas: PersonaRecord[] = [];
  @StorageLink('personaVersion') @Watch('onPersonaVersionChange') personaVersion: number = 0;
  @StorageLink('pendingImportTick') @Watch('onPendingImportTick') pendingImportTick: number = 0;
  private pathStack: NavPathStack = new NavPathStack();

  aboutToAppear(): void {
    this.loadPersonas();
    this.consumePendingImport();
  }

  onPersonaVersionChange(): void {
    this.loadPersonas();
  }

  onPendingImportTick(): void {
    this.consumePendingImport();
  }

  private consumePendingImport(): void {
    const uri: string | undefined = AppStorage.get<string>('pendingImportUri');
    if (uri === undefined || uri === '') {
      return;
    }
    AppStorage.setOrCreate('pendingImportUri', '');
    const param: ImportPageParams = { autoUri: uri };
    setTimeout(() => {
      this.pathStack.pushDestinationByName('ImportPage', param).catch((): void => {});
    }, 250);
  }

  private loadPersonas(): void {
    PersonaDb.listPersonas(getContext(this)).then((list: PersonaRecord[]): void => {
      this.personas = list;
    }).catch((error: BusinessError): void => {
      this.getUIContext().getPromptAction().showToast({ message: '加载角色失败' });
    });
  }

  private goImport(): void {
    this.pathStack.pushDestinationByName('ImportPage', '').catch((): void => {});
  }

  private goSettings(): void {
    this.pathStack.pushDestinationByName('SettingsPage', '').catch((): void => {});
  }

  private openChat(personaId: number): void {
    const param: ChatPageParams = { personaId: personaId };
    this.pathStack.pushDestinationByName('ChatPage', param).catch((): void => {});
  }

  @Builder
  EmptyView() {
    Column({ space: 12 }) {
      Text('暂无角色')
        .fontSize(18)
        .fontWeight(FontWeight.Medium)
        .fontColor('#666666')
      Text('导入一份微信聊天记录\n创建一个和TA一样说话的AI角色')
        .fontSize(14)
        .fontColor('#999999')
        .textAlign(TextAlign.Center)
        .lineHeight(22)
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  PersonaCard(p: PersonaRecord) {
    Row({ space: 12 }) {
      Stack() {
        Text(UiUtil.firstChar(p.name))
          .fontSize(20)
          .fontWeight(FontWeight.Medium)
          .fontColor(Color.White)
      }
      .width(48)
      .height(48)
      .borderRadius(24)
      .backgroundColor(UiUtil.avatarColor(p.name))

      Column({ space: 4 }) {
        Text(p.name)
          .fontSize(17)
          .fontWeight(FontWeight.Medium)
          .fontColor('#1A1A1A')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(`${p.sourceCount} 条聊天记录`)
          .fontSize(12)
          .fontColor('#999999')
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Text('›')
        .fontSize(20)
        .fontColor('#CCCCCC')
    }
    .width('100%')
    .padding(14)
    .backgroundColor(Color.White)
    .borderRadius(14)
    .onClick(() => {
      this.openChat(p.id);
    })
  }

  build() {
    Navigation(this.pathStack) {
      Column() {
        Row() {
          Text('回声')
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor('#1A1A1A')
            .layoutWeight(1)
          Text('＋')
            .fontSize(24)
            .fontColor('#1A1A1A')
            .width(38)
            .height(38)
            .textAlign(TextAlign.Center)
            .onClick(() => {
              this.goImport();
            })
          Text('⋯')
            .fontSize(22)
            .fontColor('#1A1A1A')
            .width(38)
            .height(38)
            .textAlign(TextAlign.Center)
            .onClick(() => {
              this.goSettings();
            })
        }
        .width('100%')
        .height(52)
        .padding({ left: 16, right: 6 })
        .backgroundColor('#F5F6F7')

        if (this.personas.length === 0) {
          this.EmptyView()
        } else {
          List({ space: 10 }) {
            ForEach(this.personas, (p: PersonaRecord) => {
              ListItem() {
                this.PersonaCard(p)
              }
            }, (p: PersonaRecord) => p.id.toString())
          }
          .width('100%')
          .layoutWeight(1)
          .padding({ left: 14, right: 14, top: 12 })
        }

        Column() {
          Button('＋ 导入聊天记录')
            .width('100%')
            .height(48)
            .fontSize(16)
            .backgroundColor('#07C160')
            .onClick(() => {
              this.goImport();
            })
        }
        .width('100%')
        .padding(14)
      }
      .width('100%')
      .height('100%')
      .backgroundColor('#F5F6F7')
    }
    .hideTitleBar(true)
    .mode(NavigationMode.Stack)
  }
}
