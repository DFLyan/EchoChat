import { ChatMsg, PersonaProfile, PersonaRecord } from '../model/Models';
import { LlmMessage } from './LlmClient';

export class PromptBuilder {
  static buildSystemPrompt(persona: PersonaRecord, profile: PersonaProfile): string {
    let prompt: string = '';
    prompt += '你正在扮演"' + persona.name + '"，通过微信与你的'
      + (profile.relationship === '' ? '朋友' : profile.relationship)
      + '"' + persona.myName + '"聊天。请完全以第一人称、以TA的口吻回复。\n\n';
    prompt += '## 你的说话风格\n';
    if (profile.personaCard !== '') {
      prompt += profile.personaCard + '\n';
    }
    if (profile.speakingStyle.length > 0) {
      prompt += '语气特点：' + profile.speakingStyle.join('、') + '\n';
    }
    if (profile.catchphrases.length > 0) {
      prompt += '常用口头禅：' + profile.catchphrases.join('、') + '\n';
    }
    if (profile.topics.length > 0) {
      prompt += '常聊话题：' + profile.topics.join('、') + '\n';
    }
    if (profile.examples.length > 0) {
      prompt += '\n## 真实对话示例（模仿这种风格与长度）\n';
      for (let i: number = 0; i < profile.examples.length; i++) {
        const dialog = profile.examples[i];
        prompt += '[示例' + (i + 1) + ']\n';
        for (let j: number = 0; j < dialog.messages.length; j++) {
          const turn = dialog.messages[j];
          prompt += (turn.sender === 'me' ? persona.myName : persona.name)
            + '：' + turn.text + '\n';
        }
        prompt += '\n';
      }
    }
    prompt += '## 规则\n';
    prompt += '1. 回复长度贴近示例中TA的真实习惯，通常简短自然，像发微信。\n';
    prompt += '2. 保持口语化，可以使用TA常用的语气词和emoji。\n';
    prompt += '3. 只输出你发出的消息内容，不要输出引号、旁白、动作描写；想表达多句时直接换行。\n';
    prompt += '4. 不要主动提及自己是AI或模型；如果被直接质问，以符合角色身份的方式模糊应对。\n';
    prompt += '5. 你永远以' + persona.name + '本人的身份和视角说话：只说'
      + persona.name + '会说的话、只做' + persona.name + '会做的事；'
      + '绝不替' + persona.myName + '发言，也绝不把'
      + persona.myName + '的经历、习惯说成自己的。\n';
    return prompt;
  }

  static buildMessages(systemPrompt: string, history: ChatMsg[], limit: number): LlmMessage[] {
    const result: LlmMessage[] = [];
    const sys: LlmMessage = { role: 'system', content: systemPrompt };
    result.push(sys);
    const start: number = Math.max(0, history.length - limit);
    for (let i: number = start; i < history.length; i++) {
      const msg: ChatMsg = history[i];
      if (msg.failed || msg.text === '') {
        continue;
      }
      const lm: LlmMessage = { role: msg.role === 'me' ? 'user' : 'assistant', content: msg.text };
      result.push(lm);
    }
    return result;
  }
}
