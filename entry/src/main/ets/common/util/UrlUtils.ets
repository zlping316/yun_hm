export class UrlUtils {
  static appendQuery(url: string, values: Map<string, string>): string {
    if (values.size === 0) {
      return url;
    }
    const items: string[] = [];
    values.forEach((value: string, key: string) => {
      items.push(`${encodeURIComponent(key)}=${encodeURIComponent(value)}`);
    });
    const separator = url.includes('?') ? '&' : '?';
    return `${url}${separator}${items.join('&')}`;
  }
}
