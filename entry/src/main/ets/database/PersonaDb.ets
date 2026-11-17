import { relationalStore } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { ChatMsg, ParsedMessage, PersonaRecord } from '../model/Models';

export class PersonaDb {
  private static db: relationalStore.RdbStore | undefined = undefined;

  private static async getStore(context: common.Context): Promise<relationalStore.RdbStore> {
    if (PersonaDb.db !== undefined) {
      return PersonaDb.db;
    }
    const config: relationalStore.StoreConfig = {
      name: 'echochat.db',
      securityLevel: relationalStore.SecurityLevel.S1
    };
    const db: relationalStore.RdbStore = await relationalStore.getRdbStore(context, config);
    await db.executeSql('CREATE TABLE IF NOT EXISTS persona ('
      + 'id INTEGER PRIMARY KEY AUTOINCREMENT, '
      + 'name TEXT NOT NULL, '
      + 'my_name TEXT NOT NULL, '
      + 'persona_card TEXT NOT NULL, '
      + 'profile_json TEXT NOT NULL, '
      + 'source_count INTEGER NOT NULL, '
      + 'created_at INTEGER NOT NULL)');
    await db.executeSql('CREATE TABLE IF NOT EXISTS chat_message ('
      + 'id INTEGER PRIMARY KEY AUTOINCREMENT, '
      + 'persona_id INTEGER NOT NULL, '
      + 'role TEXT NOT NULL, '
      + 'content TEXT NOT NULL, '
      + 'ts INTEGER NOT NULL)');
    await db.executeSql('CREATE TABLE IF NOT EXISTS source_message ('
      + 'id INTEGER PRIMARY KEY AUTOINCREMENT, '
      + 'persona_id INTEGER NOT NULL, '
      + 'seq INTEGER NOT NULL, '
      + 'time INTEGER NOT NULL, '
      + 'sender TEXT NOT NULL, '
      + 'text TEXT NOT NULL)');
    PersonaDb.db = db;
    return db;
  }

  static async addPersona(context: common.Context, name: string, myName: string,
    personaCard: string, profileJson: string, sourceCount: number): Promise<number> {
    const db: relationalStore.RdbStore = await PersonaDb.getStore(context);
    const bucket: relationalStore.ValuesBucket = {
      'name': name,
      'my_name': myName,
      'persona_card': personaCard,
      'profile_json': profileJson,
      'source_count': sourceCount,
      'created_at': Date.now()
    };
    return await db.insert('persona', bucket);
  }

  static async listPersonas(context: common.Context): Promise<PersonaRecord[]> {
    const db: relationalStore.RdbStore = await PersonaDb.getStore(context);
    const result: PersonaRecord[] = [];
    const rs: relationalStore.ResultSet = await db.querySql(
      'SELECT id, name, my_name, persona_card, profile_json, source_count, created_at '
      + 'FROM persona ORDER BY created_at DESC', []);
    while (rs.goToNextRow()) {
      const record: PersonaRecord = {
        id: rs.getLong(rs.getColumnIndex('id')),
        name: rs.getString(rs.getColumnIndex('name')),
        myName: rs.getString(rs.getColumnIndex('my_name')),
        personaCard: rs.getString(rs.getColumnIndex('persona_card')),
        profileJson: rs.getString(rs.getColumnIndex('profile_json')),
        sourceCount: rs.getLong(rs.getColumnIndex('source_count')),
        createdAt: rs.getLong(rs.getColumnIndex('created_at'))
      };
      result.push(record);
    }
    rs.close();
    return result;
  }

  static async getPersona(context: common.Context, id: number): Promise<PersonaRecord | undefined> {
    const db: relationalStore.RdbStore = await PersonaDb.getStore(context);
    const rs: relationalStore.ResultSet = await db.querySql(
      'SELECT id, name, my_name, persona_card, profile_json, source_count, created_at '
      + 'FROM persona WHERE id = ?', [id]);
    let record: PersonaRecord | undefined = undefined;
    if (rs.goToNextRow()) {
      record = {
        id: rs.getLong(rs.getColumnIndex('id')),
        name: rs.getString(rs.getColumnIndex('name')),
        myName: rs.getString(rs.getColumnIndex('my_name')),
        personaCard: rs.getString(rs.getColumnIndex('persona_card')),
        profileJson: rs.getString(rs.getColumnIndex('profile_json')),
        sourceCount: rs.getLong(rs.getColumnIndex('source_count')),
        createdAt: rs.getLong(rs.getColumnIndex('created_at'))
      };
    }
    rs.close();
    return record;
  }

  static async deletePersona(context: common.Context, id: number): Promise<void> {
    const db: relationalStore.RdbStore = await PersonaDb.getStore(context);
    await db.executeSql('DELETE FROM persona WHERE id = ?', [id]);
    await db.executeSql('DELETE FROM chat_message WHERE persona_id = ?', [id]);
    await db.executeSql('DELETE FROM source_message WHERE persona_id = ?', [id]);
  }

  static async addChatMessage(context: common.Context, personaId: number,
    role: string, content: string, ts: number): Promise<number> {
    const db: relationalStore.RdbStore = await PersonaDb.getStore(context);
    const bucket: relationalStore.ValuesBucket = {
      'persona_id': personaId,
      'role': role,
      'content': content,
      'ts': ts
    };
    return await db.insert('chat_message', bucket);
  }

  static async loadChat(context: common.Context, personaId: number): Promise<ChatMsg[]> {
    const db: relationalStore.RdbStore = await PersonaDb.getStore(context);
    const result: ChatMsg[] = [];
    const rs: relationalStore.ResultSet = await db.querySql(
      'SELECT id, role, content, ts FROM chat_message '
      + 'WHERE persona_id = ? ORDER BY ts ASC, id ASC', [personaId]);
    while (rs.goToNextRow()) {
      const msg: ChatMsg = new ChatMsg(
        rs.getLong(rs.getColumnIndex('id')),
        rs.getString(rs.getColumnIndex('role')),
        rs.getString(rs.getColumnIndex('content')),
        rs.getLong(rs.getColumnIndex('ts')),
        false,
        false
      );
      result.push(msg);
    }
    rs.close();
    return result;
  }

  static async clearChat(context: common.Context, personaId: number): Promise<void> {
    const db: relationalStore.RdbStore = await PersonaDb.getStore(context);
    await db.executeSql('DELETE FROM chat_message WHERE persona_id = ?', [personaId]);
  }

  static async saveSourceMessages(context: common.Context, personaId: number,
    messages: ParsedMessage[]): Promise<void> {
    const db: relationalStore.RdbStore = await PersonaDb.getStore(context);
    const chunk: number = 500;
    for (let start: number = 0; start < messages.length; start += chunk) {
      const buckets: Array<relationalStore.ValuesBucket> = [];
      const end: number = Math.min(start + chunk, messages.length);
      for (let i: number = start; i < end; i++) {
        const m: ParsedMessage = messages[i];
        const bucket: relationalStore.ValuesBucket = {
          'persona_id': personaId,
          'seq': i,
          'time': m.time,
          'sender': m.sender,
          'text': m.text
        };
        buckets.push(bucket);
      }
      await db.batchInsert('source_message', buckets);
    }
  }

  static async loadSourceMessages(context: common.Context,
    personaId: number): Promise<ParsedMessage[]> {
    const db: relationalStore.RdbStore = await PersonaDb.getStore(context);
    const result: ParsedMessage[] = [];
    const rs: relationalStore.ResultSet = await db.querySql(
      'SELECT time, sender, text FROM source_message '
      + 'WHERE persona_id = ? ORDER BY seq ASC', [personaId]);
    while (rs.goToNextRow()) {
      const m: ParsedMessage = {
        time: rs.getLong(rs.getColumnIndex('time')),
        sender: rs.getString(rs.getColumnIndex('sender')),
        text: rs.getString(rs.getColumnIndex('text'))
      };
      result.push(m);
    }
    rs.close();
    return result;
  }
}
