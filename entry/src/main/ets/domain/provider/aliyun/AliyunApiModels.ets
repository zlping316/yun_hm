export interface AliyunFileRaw {
  file_id?: string;
  parent_file_id?: string;
  name?: string;
  type?: string;
  size?: number;
  content_hash?: string;
}

export interface AliyunFileListRaw {
  items?: AliyunFileRaw[];
  next_marker?: string;
}

export interface AliyunShareFileRaw {
  file_id?: string;
  parent_file_id?: string;
  file_name?: string;
  name?: string;
  type?: string;
}

export interface AliyunShareListRaw {
  items?: AliyunShareFileRaw[];
  next_marker?: string;
}

export interface AliyunShareInfoRaw {
  share_name?: string;
  share_title?: string;
  display_name?: string;
}

export interface AliyunTokenRaw {
  share_token?: string;
  access_token?: string;
  refresh_token?: string;
}

export interface AliyunCreateRaw {
  file_id?: string;
  upload_id?: string;
  file_name?: string;
  rapid_upload?: boolean;
  part_info_list?: AliyunPartRaw[];
}

export interface AliyunPartRaw {
  part_number?: number;
  upload_url?: string;
}

export interface AliyunDownloadRaw {
  url?: string;
  size?: number;
  content_hash?: string;
  content_hash_name?: string;
  crc64_hash?: string;
}

export interface AliyunVoidRaw {
  responses?: Object[];
}

export interface AliyunPartRequest {
  part_number: number;
}

export interface AliyunBatchCopyBody {
  file_id: string;
  share_id: string;
  auto_rename: boolean;
  to_parent_file_id: string;
  to_drive_id: string;
}

export interface AliyunBatchHeaders {
  'Content-Type': string;
}

export interface AliyunBatchRequest {
  body: AliyunBatchCopyBody;
  headers: AliyunBatchHeaders;
  id: string;
  method: string;
  url: string;
}

export interface AliyunRequestBody {
  drive_id?: string;
  parent_file_id?: string;
  limit?: number;
  marker?: string;
  all?: boolean;
  fields?: string;
  order_by?: string;
  order_direction?: string;
  name?: string;
  check_name_mode?: string;
  type?: string;
  file_id?: string;
  expire_sec?: number;
  share_id?: string;
  share_pwd?: string;
  requests?: AliyunBatchRequest[];
  resource?: string;
  part_info_list?: AliyunPartRequest[];
  pre_hash?: string;
  size?: number;
  content_hash?: string;
  content_hash_name?: string;
  proof_code?: string;
  proof_version?: string;
  upload_id?: string;
  refresh_token?: string;
  grant_type?: string;
}
