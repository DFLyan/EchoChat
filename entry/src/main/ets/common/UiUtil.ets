export class UiUtil {
  private static readonly COLORS: string[] =
    ['#5B8DEF', '#F5A623', '#7ED321', '#E8618C', '#50C1E9', '#B085F5', '#F26B5E', '#3FA7A0'];

  static firstChar(name: string): string {
    if (name.length === 0) {
      return '?';
    }
    return name.substring(0, 1);
  }

  static avatarColor(name: string): string {
    let hash: number = 0;
    for (let i: number = 0; i < name.length; i++) {
      hash = (hash * 31 + name.charCodeAt(i)) % 100000;
    }
    return UiUtil.COLORS[hash % UiUtil.COLORS.length];
  }

  static pad2(v: number): string {
    return v < 10 ? '0' + v.toString() : v.toString();
  }

  static formatChatTime(ts: number, now: number): string {
    const d: Date = new Date(ts);
    const n: Date = new Date(now);
    const hhmm: string = UiUtil.pad2(d.getHours()) + ':' + UiUtil.pad2(d.getMinutes());
    const sameDay: boolean = d.getFullYear() === n.getFullYear()
      && d.getMonth() === n.getMonth() && d.getDate() === n.getDate();
    if (sameDay) {
      return hhmm;
    }
    const y: Date = new Date(now - 86400000);
    const isYesterday: boolean = d.getFullYear() === y.getFullYear()
      && d.getMonth() === y.getMonth() && d.getDate() === y.getDate();
    if (isYesterday) {
      return '昨天 ' + hhmm;
    }
    const day: string = (d.getMonth() + 1) + '月' + d.getDate() + '日 ' + hhmm;
    if (d.getFullYear() === n.getFullYear()) {
      return day;
    }
    return d.getFullYear() + '年' + day;
  }
}
