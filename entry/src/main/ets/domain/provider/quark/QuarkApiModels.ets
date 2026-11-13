export interface QuarkEnvelope<T> {
  status?: number;
  code?: number;
  message?: string;
  data?: T;
  metadata?: QuarkMetadata;
}

export interface QuarkMetadata {
  part_size?: number;
}

export interface QuarkFileRaw {
  fid?: string;
  pdir_fid?: string;
  file_name?: string;
  file_type?: string | number;
  size?: number;
  download_url?: string;
}

export interface QuarkFileListData {
  list?: QuarkFileRaw[];
}

export interface QuarkShareFileRaw {
  fid?: string;
  pdir_fid?: string;
  file_name?: string;
  title?: string;
  file_type?: string | number;
  share_fid_token?: string;
}

export interface QuarkShareData {
  list?: QuarkShareFileRaw[];
  share?: QuarkShareFileRaw;
}

export interface QuarkShareTokenData {
  stoken?: string;
  title?: string;
}

export interface QuarkFolderData {
  fid?: string;
}

export interface QuarkUploadData {
  file_id?: string;
  upload_id?: string;
  file_name?: string;
  rapid_upload?: boolean;
  upload_url?: string;
  bucket?: string;
  obj_key?: string;
  task_id?: string;
  auth_info?: string;
  auth_key?: string;
  callback?: Object | string;
  format_type?: string;
  finish?: boolean;
  part_info_list?: QuarkPartRaw[];
}

export interface QuarkPartRaw {
  part_number?: number;
  upload_url?: string;
}

export interface QuarkProviderData {
  callbackJson: string;
  contentType: string;
  bucket: string;
  objectKey: string;
  uploadUrl: string;
  taskId: string;
  authInfo: string;
}

export interface QuarkPartRequest {
  part_number: number;
}

export interface QuarkRequestBody {
  pdir_fid?: string;
  file_name?: string;
  dir_init_lock?: boolean;
  fids?: string[];
  fid_list?: string[];
  fid_token_list?: string[];
  to_pdir_fid?: string;
  pwd_id?: string;
  stoken?: string;
  scene?: string;
  ccp_hash_update?: boolean;
  parallel_upload?: boolean;
  dir_name?: string;
  size?: number;
  format_type?: string;
  task_id?: string;
  auth_info?: string;
  auth_meta?: string;
  drive_id?: string;
  file_id?: string;
  upload_id?: string;
  part_info_list?: QuarkPartRequest[];
  passcode?: string;
  obj_key?: string;
  md5?: string;
  sha1?: string;
}

export interface QuarkUploadHeaderMap {
  'Authorization': string;
  'X-Oss-Date': string;
  'X-Oss-User-Agent': string;
  'X-Oss-Callback': string;
}
