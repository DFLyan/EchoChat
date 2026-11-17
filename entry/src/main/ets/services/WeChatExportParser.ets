import { ParsedMessage } from '../model/Models';

export class WxMsgRaw {
  sender: string = '';
  is_sender: boolean = false;
  create_time: number = 0;
  text: string = '';
  kind: string = '';
  session: string = '';
  server_id: string = '';
}

export class WxMsg {
  sender: string;
  isSender: boolean;
  time: number;
  text: string;
  session: string;
  serverId: string;

  constructor(sender: string, isSender: boolean, time: number, text: string,
    session: string, serverId: string) {
    this.sender = sender;
    this.isSender = isSender;
    this.time = time;
    this.text = text;
    this.session = session;
    this.serverId = serverId;
  }
}

export class WeChatExportParser {
  private static readonly MARKER: string = 'window.__wxChunk=';

  static parseChunk(content: string): WxMsg[] {
    const out: WxMsg[] = [];
    let body: string = content.trim();
    if (!body.startsWith(WeChatExportParser.MARKER)) {
      return out;
    }
    body = body.substring(WeChatExportParser.MARKER.length).trim();
    if (body.endsWith(';')) {
      body = body.substring(0, body.length - 1).trim();
    }
    if (!body.startsWith('[')) {
      return out;
    }
    let rawList: WxMsgRaw[] = [];
    try {
      rawList = JSON.parse(body) as WxMsgRaw[];
    } catch (error) {
      return out;
    }
    for (let i: number = 0; i < rawList.length; i++) {
      if (rawList[i] === null) {
        continue;
      }
      const raw: WxMsgRaw = rawList[i];
      const kind: string = typeof raw.kind === 'string' ? raw.kind : '';
      if (kind !== 'text') {
        continue;
      }
      const text: string = typeof raw.text === 'string' ? raw.text.trim() : '';
      if (text === '') {
        continue;
      }
      const sender: string = typeof raw.sender === 'string' ? raw.sender : '';
      if (sender === '') {
        continue;
      }
      const createTime: number = typeof raw.create_time === 'number' ? raw.create_time : 0;
      const session: string = typeof raw.session === 'string' ? raw.session : '';
      const serverId: string = typeof raw.server_id === 'string' ? raw.server_id : '';
      out.push(new WxMsg(sender, raw.is_sender === true, createTime * 1000, text, session, serverId));
    }
    return out;
  }

  static pickDominantSession(msgs: WxMsg[]): WxMsg[] {
    if (msgs.length === 0) {
      return [];
    }
    const countMap: Map<string, number> = new Map<string, number>();
    for (let i: number = 0; i < msgs.length; i++) {
      const prev: number | undefined = countMap.get(msgs[i].session);
      if (prev === undefined) {
        countMap.set(msgs[i].session, 1);
      } else {
        countMap.set(msgs[i].session, prev + 1);
      }
    }
    let bestSession: string = '';
    let bestCount: number = -1;
    countMap.forEach((count: number, session: string) => {
      if (count > bestCount) {
        bestCount = count;
        bestSession = session;
      }
    });
    const out: WxMsg[] = [];
    for (let i: number = 0; i < msgs.length; i++) {
      if (msgs[i].session === bestSession) {
        out.push(msgs[i]);
      }
    }
    return out;
  }

  static toParsed(msgs: WxMsg[]): ParsedMessage[] {
    const out: ParsedMessage[] = [];
    for (let i: number = 0; i < msgs.length; i++) {
      const msg: ParsedMessage = { time: msgs[i].time, sender: msgs[i].sender, text: msgs[i].text };
      out.push(msg);
    }
    return out;
  }

  static detectSelf(msgs: WxMsg[]): string {
    return WeChatExportParser.topSender(msgs, true);
  }

  static detectThem(msgs: WxMsg[]): string {
    return WeChatExportParser.topSender(msgs, false);
  }

  private static topSender(msgs: WxMsg[], wantSelf: boolean): string {
    const countMap: Map<string, number> = new Map<string, number>();
    for (let i: number = 0; i < msgs.length; i++) {
      if (msgs[i].isSender !== wantSelf) {
        continue;
      }
      const prev: number | undefined = countMap.get(msgs[i].sender);
      if (prev === undefined) {
        countMap.set(msgs[i].sender, 1);
      } else {
        countMap.set(msgs[i].sender, prev + 1);
      }
    }
    let best: string = '';
    let bestCount: number = 0;
    countMap.forEach((count: number, name: string) => {
      if (count > bestCount) {
        bestCount = count;
        best = name;
      }
    });
    return best;
  }
}
