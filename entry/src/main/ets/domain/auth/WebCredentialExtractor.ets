import { AppError, AppErrorCode } from '../../common/error/AppError';

interface AliyunTokenPayload {
  access_token?: string;
  refresh_token?: string;
}

export interface AliyunWebCredentials {
  accessToken: string;
  refreshToken: string;
}

export class WebCredentialExtractor {
  static extractAliyun(rawValue: string): AliyunWebCredentials {
    let value = rawValue.trim();
    if (value === 'null' || value === 'undefined' || value.length === 0) {
      throw new AppError(AppErrorCode.UNAUTHORIZED, '页面中未找到阿里云盘登录凭据');
    }
    try {
      if (value.startsWith('"') && value.endsWith('"')) {
        value = JSON.parse(value) as string;
      }
      const payload = JSON.parse(value) as AliyunTokenPayload;
      const accessToken = payload.access_token ?? '';
      const refreshToken = payload.refresh_token ?? '';
      if (accessToken.length === 0 && refreshToken.length === 0) {
        throw new AppError(AppErrorCode.PARSE, '阿里云盘凭据缺少 token 字段');
      }
      return { accessToken: accessToken, refreshToken: refreshToken };
    } catch (error) {
      if (error instanceof AppError) {
        throw error;
      }
      throw new AppError(AppErrorCode.PARSE, '阿里云盘凭据格式无效');
    }
  }

  static validateQuarkCookie(cookie: string): string {
    const value = cookie.trim();
    if (value.length === 0 || (!value.includes('__puus=') && !value.includes('__kps='))) {
      throw new AppError(AppErrorCode.UNAUTHORIZED, '页面中未找到有效的夸克登录 Cookie');
    }
    return value;
  }
}
