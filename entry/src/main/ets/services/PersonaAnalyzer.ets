import { common } from '@kit.AbilityKit';
import { LlmClient, LlmMessage, LlmOptions } from './LlmClient';
import { SettingsStore } from '../database/SettingsStore';
import { ExampleDialog, ExampleTurn, ParsedMessage, PersonaProfile } from '../model/Models';

export class PersonaAnalyzer {

  static async analyze(context: common.Context, messages: ParsedMessage[],
    selfSender: string, theirName: string, charBudget: number): Promise<PersonaProfile> {
    const apiKey: string = await SettingsStore.loadApiKey(context);
    const baseUrl: string = await SettingsStore.loadBaseUrl(context);
    const model: string = await SettingsStore.loadModel(context);
    const transcript: string = PersonaAnalyzer.buildTranscript(messages, selfSender, charBudget);
    const prompt: string = PersonaAnalyzer.buildPrompt(transcript, theirName);
    const sys: LlmMessage = {
      role: 'system',
      content: '你是聊天记录分析专家，只输出合法的 JSON，不输出任何其他文字。'
    };
    const user: LlmMessage = { role: 'user', content: prompt };
    const options: LlmOptions = { temperature: 0.4, maxTokens: 8192, jsonMode: true };
    const raw: string = await LlmClient.chat(baseUrl, apiKey, model, [sys, user], options);
    const profile: PersonaProfile = PersonaAnalyzer.parseProfile(raw);
    profile.examples = PersonaAnalyzer.validateExamples(profile.examples, messages);
    return profile;
  }

  private static buildTranscript(messages: ParsedMessage[], selfSender: string,
    budget: number): string {
    const lines: string[] = [];
    let total: number = 0;
    for (let i: number = 0; i < messages.length; i++) {
      const m: ParsedMessage = messages[i];
      const label: string = m.sender === selfSender ? '我' : 'TA';
      const line: string = label + '：' + m.text.replace(/\n/g, ' ');
      lines.push(line);
      total += line.length;
    }
    let selected: string[] = lines;
    if (total > budget) {
      const step: number = Math.ceil(total / budget);
      selected = [];
      for (let i: number = 0; i < lines.length; i += step) {
        selected.push(lines[i]);
      }
    }
    return selected.join('\n');
  }

  private static buildPrompt(transcript: string, theirName: string): string {
    return '以下是"我"和"' + theirName + '"的微信聊天记录节选。'
      + '对话中标注为"TA"的一方是 ' + theirName + '（本次的分析对象），'
      + '标注为"我"的一方是记录主人。\n\n'
      + transcript
      + '\n\n请深入分析"' + theirName + '"的说话风格与性格，只输出一个 JSON 对象，格式如下：\n'
      + '{\n'
      + '  "personaCard": "用第二人称描述TA的性格、语气、聊天习惯，150字以内",\n'
      + '  "speakingStyle": ["语气特点", "..."],\n'
      + '  "catchphrases": ["TA常用的口头禅或语气词", "..."],\n'
      + '  "topics": ["TA常聊的话题", "..."],\n'
      + '  "relationship": "两人的关系（如大学室友、同事、老友）",\n'
      + '  "examples": [\n'
      + '    {"messages": [{"sender": "me", "text": "原文"}, {"sender": "them", "text": "原文"}]}\n'
      + '  ]\n'
      + '}\n'
      + '要求：\n'
      + '1. personaCard、speakingStyle、catchphrases、topics 都只基于'
      + theirName + '（即标注为TA的一方）的真实发言归纳；'
      + '"我"的发言仅作上下文参考，绝不能混入TA的风格与经历。\n'
      + '2. examples 提供3-5段，必须是聊天记录中TA的真实原文连续片段，逐字摘录不得改写；'
      + '每段6-12条消息，以TA的发言为主，能体现TA的典型说话风格。\n'
      + '3. examples 中 "me" 表示我发的消息，"them" 表示'
      + theirName + '发的消息。\n'
      + '4. 所有字段都必须有内容。';
  }

  private static parseProfile(raw: string): PersonaProfile {
    let text: string = raw.trim();
    if (text.indexOf('{') < 0) {
      throw new Error('AI 返回格式异常，请重试');
    }
    if (!text.startsWith('{')) {
      const start: number = text.indexOf('{');
      const end: number = text.lastIndexOf('}');
      if (start < 0 || end <= start) {
        throw new Error('AI 返回格式异常，请重试');
      }
      text = text.substring(start, end + 1);
    }
    let root: Record<string, Object>;
    try {
      root = JSON.parse(text) as Record<string, Object>;
    } catch (error) {
      throw new Error('人设 JSON 解析失败，请重试');
    }
    const personaCard: string = PersonaAnalyzer.strField(root['personaCard']).trim();
    if (personaCard === '') {
      throw new Error('人设卡内容为空，请重试');
    }
    const profile: PersonaProfile = {
      personaCard: personaCard,
      speakingStyle: PersonaAnalyzer.strArray(root['speakingStyle']),
      catchphrases: PersonaAnalyzer.strArray(root['catchphrases']),
      topics: PersonaAnalyzer.strArray(root['topics']),
      relationship: PersonaAnalyzer.strField(root['relationship']).trim(),
      examples: PersonaAnalyzer.parseExamples(root['examples'])
    };
    return profile;
  }

  private static strField(obj: Object | undefined): string {
    if (typeof obj === 'string') {
      return obj;
    }
    return '';
  }

  private static strArray(obj: Object | undefined): string[] {
    const result: string[] = [];
    if (obj === undefined || obj === null) {
      return result;
    }
    const arr: Object[] = obj as Object[];
    for (let i: number = 0; i < arr.length; i++) {
      const item: Object = arr[i];
      if (typeof item === 'string' && item !== '') {
        result.push(item);
      }
    }
    return result;
  }

  private static parseExamples(obj: Object | undefined): ExampleDialog[] {
    const result: ExampleDialog[] = [];
    if (obj === undefined || obj === null) {
      return result;
    }
    const arr: Object[] = obj as Object[];
    for (let i: number = 0; i < arr.length; i++) {
      const dialogObj: Object = arr[i];
      if (dialogObj === undefined || dialogObj === null) {
        continue;
      }
      const rec: Record<string, Object> = dialogObj as Record<string, Object>;
      const turnsObj: Object | undefined = rec['messages'];
      if (turnsObj === undefined || turnsObj === null) {
        continue;
      }
      const turnArr: Object[] = turnsObj as Object[];
      const turns: ExampleTurn[] = [];
      for (let j: number = 0; j < turnArr.length; j++) {
        const tObj: Object = turnArr[j];
        if (tObj === undefined || tObj === null) {
          continue;
        }
        const tRec: Record<string, Object> = tObj as Record<string, Object>;
        const sender: string = PersonaAnalyzer.strField(tRec['sender']);
        const txt: string = PersonaAnalyzer.strField(tRec['text']);
        if ((sender === 'me' || sender === 'them') && txt !== '') {
          const turn: ExampleTurn = { sender: sender, text: txt };
          turns.push(turn);
        }
      }
      if (turns.length >= 2) {
        const dialog: ExampleDialog = { messages: turns };
        result.push(dialog);
      }
    }
    return result;
  }

  private static normalize(text: string): string {
    return text.replace(/\s+/g, '');
  }

  private static validateExamples(examples: ExampleDialog[],
    messages: ParsedMessage[]): ExampleDialog[] {
    const source: Set<string> = new Set<string>();
    for (let i: number = 0; i < messages.length; i++) {
      const t: string = PersonaAnalyzer.normalize(messages[i].text);
      if (t !== '') {
        source.add(t);
      }
    }
    const result: ExampleDialog[] = [];
    for (let i: number = 0; i < examples.length; i++) {
      const dialog = examples[i];
      let ok: boolean = true;
      for (let j: number = 0; j < dialog.messages.length; j++) {
        if (!source.has(PersonaAnalyzer.normalize(dialog.messages[j].text))) {
          ok = false;
          break;
        }
      }
      if (ok) {
        result.push(dialog);
      }
    }
    return result;
  }
}
