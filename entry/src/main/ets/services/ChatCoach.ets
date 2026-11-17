import { common } from '@kit.AbilityKit';
import { LlmClient, LlmMessage, LlmOptions } from './LlmClient';
import { SettingsStore } from '../database/SettingsStore';
import { ParsedMessage } from '../model/Models';

export interface CoachReport {
  summary: string;
  strengths: string[];
  problems: string[];
  suggestions: string[];
}

export class ChatCoach {
  private static readonly CHAR_BUDGET: number = 40000;

  static async analyze(context: common.Context, messages: ParsedMessage[],
    selfName: string, theirName: string): Promise<CoachReport> {
    const apiKey: string = await SettingsStore.loadApiKey(context);
    const baseUrl: string = await SettingsStore.loadBaseUrl(context);
    const model: string = await SettingsStore.loadModel(context);
    const transcript: string = ChatCoach.buildTranscript(messages, selfName);
    const sys: LlmMessage = {
      role: 'system',
      content: '你是资深的社交与沟通教练，擅长从真实聊天记录中发现沟通问题并给出可落地的建议，只输出合法的 JSON。'
    };
    const user: LlmMessage = { role: 'user', content: ChatCoach.buildPrompt(transcript, selfName, theirName) };
    const options: LlmOptions = { temperature: 0.4, maxTokens: 8192, jsonMode: true };
    const raw: string = await LlmClient.chat(baseUrl, apiKey, model, [sys, user], options);
    return ChatCoach.parseReport(raw);
  }

  private static buildTranscript(messages: ParsedMessage[], selfSender: string): string {
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
    if (total > ChatCoach.CHAR_BUDGET) {
      const step: number = Math.ceil(total / ChatCoach.CHAR_BUDGET);
      selected = [];
      for (let i: number = 0; i < lines.length; i += step) {
        selected.push(lines[i]);
      }
    }
    return selected.join('\n');
  }

  private static buildPrompt(transcript: string, selfName: string, theirName: string): string {
    return '以下是"' + selfName + '"（记录中的"我"）和"' + theirName
      + '"（记录中的"TA"）的全部微信聊天记录节选。\n\n'
      + transcript
      + '\n\n请以聊天教练的视角，全局复盘"我"在这段关系中的聊天表现，帮助"我"提升与对方的沟通质量。只输出一个 JSON 对象，格式如下：\n'
      + '{\n'
      + '  "summary": "整体评价：两人的聊天氛围、关系状态与走势，150字以内",\n'
      + '  "strengths": ["我做得好的地方，每条附简短依据", "..."],\n'
      + '  "problems": ["我的沟通问题，每条引用或概括聊天记录中的具体表现作证据", "..."],\n'
      + '  "suggestions": ["具体、可直接照做的改进建议，针对上面的问题逐条给出", "..."]\n'
      + '}\n'
      + '要求：\n'
      + '1. strengths、problems、suggestions 各提供3-6条。\n'
      + '2. problems 只聚焦"我"（' + selfName + '）的问题，例如：话题终结、回复敷衍、'
      + '不回应对方的情绪、自说自话、缺乏提问与好奇、过度讨好、只在有事时才找对方等，'
      + '必须基于记录中的真实表现，不要泛泛而谈。\n'
      + '3. suggestions 要具体到话术或行为层面。\n'
      + '4. 所有字段都必须有内容。';
  }

  private static parseReport(raw: string): CoachReport {
    let text: string = raw.trim();
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
      throw new Error('报告 JSON 解析失败，请重试');
    }
    const summary: string = ChatCoach.strField(root['summary']).trim();
    if (summary === '') {
      throw new Error('报告内容为空，请重试');
    }
    const report: CoachReport = {
      summary: summary,
      strengths: ChatCoach.strArray(root['strengths']),
      problems: ChatCoach.strArray(root['problems']),
      suggestions: ChatCoach.strArray(root['suggestions'])
    };
    return report;
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
}
