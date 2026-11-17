import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { ChatPageParams, ParsedMessage, PersonaRecord } from '../model/Models';
import { PersonaDb } from '../database/PersonaDb';
import { ChatCoach, CoachReport } from '../services/ChatCoach';

@Builder
export function CoachPageBuilder(): void {
  CoachPage()
}

@Component
struct CoachPage {
  @State persona: PersonaRecord | undefined = undefined;
  @State analyzing: boolean = false;
  @State report: CoachReport | undefined = undefined;
  @State errorText: string = '';
  private pathStack: NavPathStack = new NavPathStack();

  private async loadBase(personaId: number): Promise<void> {
    const context: common.Context = getContext(this);
    try {
      const p: PersonaRecord | undefined = await PersonaDb.getPersona(context, personaId);
      if (p === undefined) {
        this.getUIContext().getPromptAction().showToast({ message: '角色不存在' });
        this.pathStack.pop();
        return;
      }
      this.persona = p;
    } catch (error) {
      this.getUIContext().getPromptAction().showToast({ message: '加载失败' });
      this.pathStack.pop();
    }
  }

  private async runAnalysis(): Promise<void> {
    if (this.persona === undefined || this.analyzing) {
      return;
    }
    this.analyzing = true;
    this.errorText = '';
    this.report = undefined;
    const context: common.Context = getContext(this);
    try {
      const msgs: ParsedMessage[] = await PersonaDb.loadSourceMessages(context, this.persona.id);
      if (msgs.length === 0) {
        this.errorText = '没有找到原始聊天记录，无法分析';
        this.analyzing = false;
        return;
      }
      const report: CoachReport = await ChatCoach.analyze(context, msgs,
        this.persona.myName, this.persona.name);
      this.report = report;
    } catch (error) {
      const err = error as BusinessError;
      this.errorText = '分析失败：' + err.message;
    }
    this.analyzing = false;
  }

  @Builder
  SectionTitle(label: string, color: string) {
    Text(label)
      .fontSize(16)
      .fontWeight(FontWeight.Bold)
      .fontColor(color)
  }

  @Builder
  ReportList(items: string[], color: string) {
    Column({ space: 8 }) {
      ForEach(items, (item: string, i: number) => {
        Text(`${i + 1}. ${item}`)
          .fontSize(14)
          .fontColor('#333333')
          .lineHeight(21)
          .width('100%')
          .padding(10)
          .backgroundColor(Color.White)
          .borderRadius(8)
      }, (item: string, i: number) => `${i}-${item.length}`)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  build() {
    NavDestination() {
      Scroll() {
        Column({ space: 14 }) {
          if (this.analyzing) {
            Column({ space: 16 }) {
              LoadingProgress()
                .width(48)
                .height(48)
                .color('#07C160')
              Text('正在全局分析聊天记录…')
                .fontSize(15)
                .fontColor('#333333')
              Text('分析全部历史消息，通常需要 1~2 分钟')
                .fontSize(13)
                .fontColor('#999999')
            }
            .width('100%')
            .layoutWeight(1)
            .justifyContent(FlexAlign.Center)
          } else if (this.report === undefined) {
            Column({ space: 14 }) {
              Text('聊天复盘')
                .fontSize(22)
                .fontWeight(FontWeight.Bold)
                .fontColor('#1A1A1A')
              Text('AI 将以聊天教练的视角，通读你俩的全部原始聊天记录，'
                + '分析你的聊天表现：哪些做得好、哪些沟通方式有问题'
                + '（比如话题终结、不接情绪、回复敷衍），并给出可以直接照做的改进建议。')
                .fontSize(14)
                .fontColor('#666666')
                .lineHeight(22)
              if (this.persona !== undefined) {
                Text(`分析对象：你 和 ${this.persona.name}（${this.persona.sourceCount} 条原始消息）`)
                  .fontSize(13)
                  .fontColor('#999999')
              }
              Button('开始分析')
                .width('100%')
                .height(46)
                .fontSize(16)
                .backgroundColor('#07C160')
                .onClick(() => {
                  this.runAnalysis();
                })
            }
            .width('100%')
          } else {
            Text('整体评价')
              .fontSize(16)
              .fontWeight(FontWeight.Bold)
              .fontColor('#1A1A1A')
            Text(this.report.summary)
              .fontSize(14)
              .fontColor('#333333')
              .lineHeight(21)
              .width('100%')
              .padding(12)
              .backgroundColor(Color.White)
              .borderRadius(10)

            if (this.report.strengths.length > 0) {
              this.SectionTitle('做得好的地方', '#07C160')
              this.ReportList(this.report.strengths, '#07C160')
            }
            if (this.report.problems.length > 0) {
              this.SectionTitle('存在的问题', '#E64340')
              this.ReportList(this.report.problems, '#E64340')
            }
            if (this.report.suggestions.length > 0) {
              this.SectionTitle('改进建议', '#5B8DEF')
              this.ReportList(this.report.suggestions, '#5B8DEF')
            }
            Button('重新分析')
              .width('100%')
              .height(44)
              .fontSize(15)
              .backgroundColor('#F0F0F0')
              .fontColor('#333333')
              .onClick(() => {
                this.runAnalysis();
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
      .height('100%')
      .backgroundColor('#F7F7F7')
    }
    .title('聊天分析')
    .onReady((ctx: NavDestinationContext) => {
      this.pathStack = ctx.pathStack;
      const p = ctx.pathInfo.param as ChatPageParams;
      if (p !== undefined && p !== null && p.personaId > 0) {
        this.loadBase(p.personaId);
      }
    })
  }
}
