export interface SenderInfo {
  name: string;
  count: number;
}

export interface ParsedMessage {
  time: number;
  sender: string;
  text: string;
}

export interface ParseResult {
  messages: ParsedMessage[];
  senders: SenderInfo[];
}

export interface ChatPageParams {
  personaId: number;
}

export interface ImportPageParams {
  autoUri: string;
}

export interface ExampleTurn {
  sender: string;
  text: string;
}

export interface ExampleDialog {
  messages: ExampleTurn[];
}

export interface PersonaProfile {
  personaCard: string;
  speakingStyle: string[];
  catchphrases: string[];
  topics: string[];
  relationship: string;
  examples: ExampleDialog[];
}

export interface PersonaRecord {
  id: number;
  name: string;
  myName: string;
  personaCard: string;
  profileJson: string;
  sourceCount: number;
  createdAt: number;
}

@Observed
export class ChatMsg {
  id: number;
  role: string;
  text: string;
  ts: number;
  failed: boolean;
  streaming: boolean;

  constructor(id: number, role: string, text: string, ts: number,
    failed: boolean, streaming: boolean) {
    this.id = id;
    this.role = role;
    this.text = text;
    this.ts = ts;
    this.failed = failed;
    this.streaming = streaming;
  }
}
