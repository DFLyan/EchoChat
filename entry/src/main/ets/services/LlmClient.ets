import { http } from '@kit.NetworkKit';
import { util } from '@kit.ArkTS';
import { BusinessError } from '@kit.BasicServicesKit';

export interface LlmMessage {
  role: string;
  content: string;
}

export interface LlmOptions {
  temperature: number;
  maxTokens: number;
  jsonMode: boolean;
}

export interface StreamHandle {
  cancel: () => void;
}

export class LlmClient {
  static async chat(baseUrl: string, apiKey: string, model: string,
    messages: LlmMessage[], options: LlmOptions): Promise<string> {
    if (apiKey === '') {
      throw new Error('未配置 API Key，请先在设置中填写');
    }
    const url: string = LlmClient.buildUrl(baseUrl);
    const body: Record<string, Object> = LlmClient.buildBody(model, messages, options, false);
    const header: Record<string, string> = {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer ' + apiKey
    };
    const client: http.HttpRequest = http.createHttp();
    try {
      const resp: http.HttpResponse = await client.request(url, {
        method: http.RequestMethod.POST,
        header: header,
        extraData: JSON.stringify(body),
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: 15000,
        readTimeout: 120000
      });
      const text: string = resp.result as string;
      if (resp.responseCode !== 200) {
        throw new Error('HTTP ' + resp.responseCode + '：'
          + LlmClient.brief(LlmClient.extractApiError(text)));
      }
      return LlmClient.parseContent(text);
    } finally {
      client.destroy();
    }
  }

  static async listModels(baseUrl: string, apiKey: string): Promise<string[]> {
    if (apiKey === '') {
      throw new Error('未配置 API Key，请先在设置中填写');
    }
    const trimmed: string = baseUrl.trim();
    const base: string = trimmed.endsWith('/')
      ? trimmed.substring(0, trimmed.length - 1) : trimmed;
    const url: string = base + '/models';
    const header: Record<string, string> = {
      'Authorization': 'Bearer ' + apiKey
    };
    const client: http.HttpRequest = http.createHttp();
    try {
      const resp: http.HttpResponse = await client.request(url, {
        method: http.RequestMethod.GET,
        header: header,
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: 15000,
        readTimeout: 30000
      });
      const text: string = resp.result as string;
      if (resp.responseCode !== 200) {
        throw new Error('HTTP ' + resp.responseCode + '：'
          + LlmClient.brief(LlmClient.extractApiError(text)));
      }
      const root: Record<string, Object> = JSON.parse(text) as Record<string, Object>;
      const dataObj: Object | undefined = root['data'];
      if (dataObj === undefined || dataObj === null) {
        throw new Error('接口未返回模型列表');
      }
      const arr: Array<Record<string, Object>> = dataObj as Array<Record<string, Object>>;
      const models: string[] = [];
      for (let i: number = 0; i < arr.length; i++) {
        const item: Record<string, Object> = arr[i];
        const idObj: Object | undefined = item['id'];
        if (typeof idObj === 'string' && idObj !== '') {
          models.push(idObj);
        }
      }
      if (models.length === 0) {
        throw new Error('接口返回的模型列表为空');
      }
      models.sort();
      return models;
    } finally {
      client.destroy();
    }
  }

  static chatStream(baseUrl: string, apiKey: string, model: string,
    messages: LlmMessage[], options: LlmOptions,
    onDelta: (text: string) => void,
    onDone: (full: string) => void,
    onError: (message: string) => void): StreamHandle {
    if (apiKey === '') {
      onError('未配置 API Key，请先在设置中填写');
      const idle: StreamHandle = { cancel: (): void => {} };
      return idle;
    }
    const url: string = LlmClient.buildUrl(baseUrl);
    const body: Record<string, Object> = LlmClient.buildBody(model, messages, options, true);
    const header: Record<string, string> = {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer ' + apiKey
    };
    const client: http.HttpRequest = http.createHttp();
    const decoder: util.TextDecoder = util.TextDecoder.create('utf-8');
    let sseBuffer: string = '';
    let rawText: string = '';
    let full: string = '';
    let responseCode: number = -1;
    let ended: boolean = false;
    let finished: boolean = false;

    const consumeSse = (): void => {
      let idx: number = sseBuffer.indexOf('\n');
      while (idx >= 0) {
        const line: string = sseBuffer.substring(0, idx).trim();
        sseBuffer = sseBuffer.substring(idx + 1);
        const delta: string = LlmClient.consumeSseLine(line);
        if (delta !== '') {
          full += delta;
          onDelta(delta);
        }
        idx = sseBuffer.indexOf('\n');
      }
    };

    const cleanup = (): void => {
      client.off('dataReceive');
      client.off('dataEnd');
      client.destroy();
    };

    const finish = (): void => {
      if (finished || responseCode < 0) {
        return;
      }
      finished = true;
      cleanup();
      if (responseCode !== 200) {
        let message: string = 'HTTP ' + responseCode + '：请求失败';
        if (rawText !== '') {
          message = 'HTTP ' + responseCode + '：'
            + LlmClient.brief(LlmClient.extractApiError(rawText));
        }
        onError(message);
        return;
      }
      onDone(full);
    };

    client.on('dataReceive', (chunk: ArrayBuffer) => {
      if (finished) {
        return;
      }
      const piece: string = decoder.decodeToString(new Uint8Array(chunk), { stream: true });
      if (responseCode !== 200) {
        rawText += piece;
        return;
      }
      sseBuffer += piece;
      consumeSse();
    });
    client.on('dataEnd', () => {
      if (finished) {
        return;
      }
      ended = true;
      finish();
    });

    const handle: StreamHandle = {
      cancel: (): void => {
        if (finished) {
          return;
        }
        finished = true;
        cleanup();
      }
    };

    const requestOptions: http.HttpRequestOptions = {
      method: http.RequestMethod.POST,
      header: header,
      extraData: JSON.stringify(body),
      expectDataType: http.HttpDataType.STRING,
      connectTimeout: 15000,
      readTimeout: 120000
    };
    client.requestInStream(url, requestOptions).then((code: number) => {
      responseCode = code;
      if (!finished && code === 200 && rawText !== '') {
        sseBuffer += rawText;
        rawText = '';
        consumeSse();
      }
      if (ended) {
        finish();
      }
    }).catch((err: BusinessError) => {
      if (!finished) {
        finished = true;
        cleanup();
        onError('网络请求失败：' + err.message);
      }
    });
    return handle;
  }

  private static consumeSseLine(line: string): string {
    if (!line.startsWith('data:')) {
      return '';
    }
    const payload: string = line.substring(5).trim();
    if (payload === '' || payload === '[DONE]') {
      return '';
    }
    try {
      const root: Record<string, Object> = JSON.parse(payload) as Record<string, Object>;
      const choicesObj: Object | undefined = root['choices'];
      if (choicesObj === undefined || choicesObj === null) {
        return '';
      }
      const choices: Array<Record<string, Object>> = choicesObj as Array<Record<string, Object>>;
      if (choices.length === 0) {
        return '';
      }
      const first: Record<string, Object> = choices[0];
      const deltaObj: Object | undefined = first['delta'];
      if (deltaObj === undefined || deltaObj === null) {
        return '';
      }
      const deltaRec: Record<string, Object> = deltaObj as Record<string, Object>;
      const contentObj: Object | undefined = deltaRec['content'];
      if (typeof contentObj === 'string') {
        return contentObj;
      }
      return '';
    } catch (error) {
      return '';
    }
  }

  private static buildUrl(baseUrl: string): string {
    const trimmed: string = baseUrl.trim();
    const base: string = trimmed.endsWith('/')
      ? trimmed.substring(0, trimmed.length - 1) : trimmed;
    return base + '/chat/completions';
  }

  private static buildBody(model: string, messages: LlmMessage[],
    options: LlmOptions, stream: boolean): Record<string, Object> {
    const msgRecords: Array<Record<string, Object>> =
      messages.map((m: LlmMessage): Record<string, Object> => {
        const rec: Record<string, Object> = { 'role': m.role, 'content': m.content };
        return rec;
      });
    const body: Record<string, Object> = {
      'model': model,
      'messages': msgRecords,
      'stream': stream,
      'temperature': options.temperature,
      'max_tokens': options.maxTokens
    };
    if (options.jsonMode) {
      const fmt: Record<string, Object> = { 'type': 'json_object' };
      body['response_format'] = fmt;
    }
    return body;
  }

  private static brief(text: string): string {
    if (text === null || text === undefined || text === '') {
      return '未知错误';
    }
    if (text.length > 160) {
      return text.substring(0, 160);
    }
    return text;
  }

  private static extractApiError(text: string): string {
    try {
      const root: Record<string, Object> = JSON.parse(text) as Record<string, Object>;
      const errObj: Object | undefined = root['error'];
      if (errObj !== undefined && errObj !== null) {
        const errRec: Record<string, Object> = errObj as Record<string, Object>;
        const msgObj: Object | undefined = errRec['message'];
        if (typeof msgObj === 'string' && msgObj !== '') {
          return msgObj;
        }
      }
    } catch (error) {
    }
    return text;
  }

  private static parseContent(text: string): string {
    const root: Record<string, Object> = JSON.parse(text) as Record<string, Object>;
    const choicesObj: Object | undefined = root['choices'];
    if (choicesObj === undefined || choicesObj === null) {
      const apiErr: string = LlmClient.extractApiError(text);
      if (apiErr !== text) {
        throw new Error(apiErr);
      }
      throw new Error('AI 响应格式异常');
    }
    const choices: Array<Record<string, Object>> = choicesObj as Array<Record<string, Object>>;
    if (choices.length === 0) {
      throw new Error('AI 返回空结果');
    }
    const first: Record<string, Object> = choices[0];
    const finishObj: Object | undefined = first['finish_reason'];
    const finish: string = typeof finishObj === 'string' ? finishObj : '';
    const msgObj: Object | undefined = first['message'];
    if (msgObj === undefined || msgObj === null) {
      throw new Error('AI 返回缺少内容');
    }
    const msg: Record<string, Object> = msgObj as Record<string, Object>;
    const contentObj: Object | undefined = msg['content'];
    if (typeof contentObj === 'string' && contentObj !== '') {
      return contentObj;
    }
    const reasonObj: Object | undefined = msg['reasoning_content'];
    const hasReason: boolean = typeof reasonObj === 'string' && reasonObj !== '';
    if (hasReason || finish === 'length') {
      throw new Error('AI 输出被 max_tokens 截断（思考过程耗尽了输出额度），'
        + '请在设置中更换为非推理模型，或减小任务规模后重试');
    }
    throw new Error('AI 返回内容为空（finish_reason='
      + (finish === '' ? '未知' : finish) + '），请重试或更换模型');
  }
}
