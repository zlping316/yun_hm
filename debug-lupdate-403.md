# Debug Session: lupdate-403
- **Status**: [CLOSED]
- **progress_status**: verified
- **Issue**: Sync page LUpdate still reports failure after restoring cloud backup from Quark.
- **Evidence Source**: existing local log path, captured from device with `hdc shell hilog -x`
- **Evidence Directory**: `/tmp/yun-debug-lupdate-403`
- **Debug Server**: not active, using project `LsLogger` local hilog fallback
- **Log File**: not applicable for HTTP; focused captures are saved under `/tmp/yun_lupdate_*.txt`

## Reproduction Steps
1. Install signed HAP on API 22 phone target.
2. Open Sync page.
3. Tap `LUpdate`.
4. Observe UI reports request failure.
5. Capture device logs with `hdc shell hilog -x`.

## Hypotheses & Verification
| ID | Hypothesis | Likelihood | Effort | Evidence |
|----|------------|------------|--------|----------|
| A | Quark direct download URL returned by download API is expired or signed for a different request shape. | High | Low | Pending: compare download API response fields and direct GET failure body. |
| B | Range uses a size inconsistent with the downloadable object. | Medium | Low | Pending: log list size, download-info size, and actual Range header. |
| C | Cookie or Quark-specific request headers cause OSS/CDN 403, while another header strategy would work. | Medium | Low | Pending: log attempt index/header strategy/status for each direct GET. |
| D | The selected newest backup file is a bad/old payload and restore never reaches a valid Android-format file. | Medium | Low | Pending: log selected files and parse skip reasons. |
| E | Upload log succeeds but address log fails in a separate directory/download path. | Low | Low | Pending: stage-scoped logs for upload/address phases. |

## Log Evidence
Pre-instrumentation evidence showed:
- `GET https://drive-pc.quark.cn/.../file/sort` returned `200`.
- `POST https://drive-pc.quark.cn/.../file/download` returned `200`.
- Direct backup GET to `dl-pc-zb.pds.quark.cn` returned `403`.

Instrumentation run `/tmp/yun_lupdate_pre_fix.txt`:
- line 135: `restoreLatest provider=quark`, log folder `4aa1...0daf`, address folder `7aa9...258d`.
- lines 163-170: Quark list API returns `200`; upload-log folder has 14 valid `upload_log_*.json` candidates.
- line 171: newest candidate is `upload_log_1794379298676.json`, size `532987`.
- lines 181-182: Quark `file/download` returns `200`; `fileSize=532987`, `downloadSize=532987`, `range=bytes=0-532986`, URL host is `dl-pc-zb.pds.quark.cn`.
- line 187: direct GET returns `403` with OSS XML body: `RequestDeniedByCallback`, `require login [auth expired]`.
- line 198: no-cookie retry returns `403` with OSS XML body: `RequestDeniedByCallback`, `require login [auth not found]`.

User follow-up click run `/tmp/yun_lupdate_after_click.txt`:
- line 3900: `restoreLatest provider=quark`.
- lines 4681-4685: upload-log folder list still succeeds and selects `upload_log_1794379298676.json`.
- lines 4723-4724: Quark `file/download` still returns `200`; `fileSize=532987`, `downloadSize=532987`, `range=bytes=0-532986`.
- line 4823: direct GET with Cookie still returns `403`, XML body `RequestDeniedByCallback`, `require login [auth expired]`.
- line 4834: no-cookie retry still returns `403`, XML body `RequestDeniedByCallback`, `require login [auth not found]`.

New failure run `/tmp/yun_lupdate_no_valid_backup.txt`:
- lines 1953-1955: upload-log list succeeds and iterates 14 `upload_log_*.json` files.
- lines 1962...2044 and 2149...2225: all 14 candidates download but fail parse.
- First 6 newest files fail with `upload backup is not an Android string array`.
- Older 8 files fail with `Cannot read property indexOf of null`, meaning the payload is an Android array but includes null entries.
- Additional static evidence: `ShareListBackupController` also uploaded share-list files as `upload_log_<timestamp>.json`, so if the share backup folder is or was the same as the upload-log folder, resource restore will see non-upload-history JSON under the upload-log prefix.

## Verification Conclusion
The initial failure was caused by an expired Quark login authorization on the direct download URL. After Quark auth was refreshed, restore progressed to payload parsing. The new `未找到有效备份` failure is caused by two issues: some polluted/non-upload-history files use the `upload_log_` prefix, and valid Android upload-history arrays may contain null entries that must be skipped rather than crash parsing.

## Fix Attempt 1
- `decodeAndroidUploadBackup` now skips null/empty entries while still rejecting non-array payloads.
- `decodeAndroidAddressBackup` now skips null address entries defensively.
- `ShareListBackupController` now writes share-list backup files with `share_link_<timestamp>.json` instead of `upload_log_<timestamp>.json` to avoid future namespace pollution.

## Post-fix Verification
Post-fix run `/tmp/yun_lupdate_post_fix.txt`:
- Quark direct backup download returned `206`, so the refreshed Quark login state fixed the previous direct-link authorization failure.
- Restore skipped the first 6 polluted `upload_log_*.json` candidates that were not Android upload-history arrays.
- Restore then accepted the older Android-format upload log containing nullable entries after the decoder started skipping null/empty entries.
- line 961: `Backup restored provider=quark, log=upload_log_1766786709621.json, address=address_log_1794379298676.json`.

## Final Evidence Gate
- **Evidence Sources**: device `hilog`, `/tmp/yun_lupdate_pre_fix.txt`, `/tmp/yun_lupdate_no_valid_backup.txt`, `/tmp/yun_lupdate_post_fix.txt`
- **progress_status**: verified
- **Hypothesis Conclusions**: A=CONFIRMED, B=REJECTED, C=CONFIRMED, D=CONFIRMED, E=REJECTED
