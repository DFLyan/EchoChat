import { util } from '@kit.ArkTS';
import { ParseResult, ParsedMessage, SenderInfo } from '../model/Models';

export class ChatParser {
  private static readonly LINE_RE: RegExp =
    /^(\d{4})-(\d{1,2})-(\d{1,2})[ T](\d{1,2}):(\d{2}):(\d{2})\s+(.+)$/;

  static decodeBytes(bytes: Uint8Array): string {
    const utf8: util.TextDecoder = util.TextDecoder.create('utf-8');
    const text: string = utf8.decodeToString(bytes);
    let bad: number = 0;
    for (let i: number = 0; i < text.length; i++) {
      if (text.charCodeAt(i) === 0xFFFD) {
        bad++;
      }
    }
    if (bad * 100 > text.length) {
      try {
        const gbk: util.TextDecoder = util.TextDecoder.create('gbk');
        return gbk.decodeToString(bytes);
      } catch (error) {
        return text;
      }
    }
    return text;
  }

  static parse(rawText: string): ParseResult {
    const normalized: string = rawText.replace(/\r\n/g, '\n').replace(/\r/g, '\n');
    const lines: string[] = normalized.split('\n');
    const messages: ParsedMessage[] = [];
    const countMap: Map<string, number> = new Map<string, number>();
    let i: number = 0;
    while (i < lines.length) {
      const header: RegExpMatchArray | null = lines[i].match(ChatParser.LINE_RE);
      if (header === null) {
        i++;
        continue;
      }
      const year: number = Number(header[1]);
      const month: number = Number(header[2]);
      const day: number = Number(header[3]);
      const hour: number = Number(header[4]);
      const minute: number = Number(header[5]);
      const second: number = Number(header[6]);
      const sender: string = header[7].trim();
      const time: number = new Date(year, month - 1, day, hour, minute, second).getTime();
      const bodyParts: string[] = [];
      let j: number = i + 1;
      while (j < lines.length && lines[j].trim() !== '') {
        bodyParts.push(lines[j]);
        j++;
      }
      const content: string = bodyParts.join('\n').trim();
      if (sender !== '' && content !== '') {
        const msg: ParsedMessage = { time: time, sender: sender, text: content };
        messages.push(msg);
        const prev: number | undefined = countMap.get(sender);
        if (prev === undefined) {
          countMap.set(sender, 1);
        } else {
          countMap.set(sender, prev + 1);
        }
      }
      i = j + 1;
    }
    const senders: SenderInfo[] = [];
    countMap.forEach((count: number, name: string) => {
      const info: SenderInfo = { name: name, count: count };
      senders.push(info);
    });
    senders.sort((a: SenderInfo, b: SenderInfo): number => b.count - a.count);
    const result: ParseResult = { messages: messages, senders: senders };
    return result;
  }
}
