export interface HlsKey {
  method: string;
  uri: string;
  iv: string;
}

export interface HlsSegment {
  index: number;
  url: string;
  key?: HlsKey;
}

export interface HlsMediaPlaylist {
  segments: HlsSegment[];
  mediaSequence: number;
}

interface HlsVariant {
  bandwidth: number;
  url: string;
}

export class HlsPlaylistParser {
  static selectMediaPlaylist(content: string, playlistUrl: string): string {
    const lines = HlsPlaylistParser.lines(content);
    const variants: HlsVariant[] = [];
    for (let index = 0; index < lines.length; index++) {
      if (!lines[index].startsWith('#EXT-X-STREAM-INF:')) {
        continue;
      }
      const bandwidth = HlsPlaylistParser.numberAttribute(lines[index], 'BANDWIDTH');
      const next = HlsPlaylistParser.nextUri(lines, index + 1);
      if (next.length > 0) {
        variants.push({
          bandwidth: bandwidth,
          url: HlsPlaylistParser.resolveUrl(playlistUrl, next)
        });
      }
    }
    if (variants.length === 0) {
      return playlistUrl;
    }
    variants.sort((left: HlsVariant, right: HlsVariant) => right.bandwidth - left.bandwidth);
    return variants[0].url;
  }

  static parseMedia(content: string, playlistUrl: string): HlsMediaPlaylist {
    const lines = HlsPlaylistParser.lines(content);
    const segments: HlsSegment[] = [];
    let mediaSequence = 0;
    let currentKey: HlsKey | undefined;
    lines.forEach((line: string) => {
      if (line.startsWith('#EXT-X-MEDIA-SEQUENCE:')) {
        mediaSequence = Number(line.substring('#EXT-X-MEDIA-SEQUENCE:'.length)) || 0;
      } else if (line.startsWith('#EXT-X-KEY:')) {
        const method = HlsPlaylistParser.stringAttribute(line, 'METHOD');
        const uri = HlsPlaylistParser.stringAttribute(line, 'URI');
        const iv = HlsPlaylistParser.stringAttribute(line, 'IV');
        if (method === 'NONE') {
          currentKey = undefined;
        } else if (uri.length > 0) {
          currentKey = {
            method: method,
            uri: HlsPlaylistParser.resolveUrl(playlistUrl, uri),
            iv: iv
          };
        }
      } else if (line.length > 0 && !line.startsWith('#')) {
        const segment: HlsSegment = {
          index: segments.length,
          url: HlsPlaylistParser.resolveUrl(playlistUrl, line),
          key: currentKey
        };
        segments.push(segment);
      }
    });
    return { segments: segments, mediaSequence: mediaSequence };
  }

  static resolveUrl(baseUrl: string, reference: string): string {
    if (/^https?:\/\//i.test(reference)) {
      return reference;
    }
    const schemeIndex = baseUrl.indexOf('://');
    if (schemeIndex < 0) {
      return reference;
    }
    const authorityStart = schemeIndex + 3;
    const pathStart = baseUrl.indexOf('/', authorityStart);
    const origin = pathStart < 0 ? baseUrl : baseUrl.substring(0, pathStart);
    if (reference.startsWith('//')) {
      return `${baseUrl.substring(0, schemeIndex)}:${reference}`;
    }
    if (reference.startsWith('/')) {
      return `${origin}${HlsPlaylistParser.normalizePath(reference)}`;
    }
    const basePath = pathStart < 0 ? '/' : baseUrl.substring(pathStart).split(/[?#]/)[0];
    const directory = basePath.substring(0, basePath.lastIndexOf('/') + 1);
    return `${origin}${HlsPlaylistParser.normalizePath(`${directory}${reference}`)}`;
  }

  private static normalizePath(pathWithQuery: string): string {
    const queryIndex = pathWithQuery.search(/[?#]/);
    const path = queryIndex < 0 ? pathWithQuery : pathWithQuery.substring(0, queryIndex);
    const suffix = queryIndex < 0 ? '' : pathWithQuery.substring(queryIndex);
    const output: string[] = [];
    path.split('/').forEach((part: string) => {
      if (part.length === 0 || part === '.') {
        return;
      }
      if (part === '..') {
        output.pop();
      } else {
        output.push(part);
      }
    });
    return `/${output.join('/')}${suffix}`;
  }

  private static lines(content: string): string[] {
    return content.split(/\r?\n/).map((line: string) => line.trim()).filter((line: string) => line.length > 0);
  }

  private static nextUri(lines: string[], start: number): string {
    for (let index = start; index < lines.length; index++) {
      if (!lines[index].startsWith('#')) {
        return lines[index];
      }
    }
    return '';
  }

  private static numberAttribute(line: string, name: string): number {
    const value = HlsPlaylistParser.stringAttribute(line, name);
    return Number(value) || 0;
  }

  private static stringAttribute(line: string, name: string): string {
    const expression = new RegExp(`(?:^|,)${name}=("[^"]*"|[^,]*)`);
    const body = line.substring(line.indexOf(':') + 1);
    const match = body.match(expression);
    if (match === null || match.length < 2) {
      return '';
    }
    const value = match[1];
    return value.startsWith('"') && value.endsWith('"') ? value.substring(1, value.length - 1) : value;
  }
}
