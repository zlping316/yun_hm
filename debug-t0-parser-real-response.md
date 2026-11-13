# Debug Session: t0-parser-real-response
- **Status**: [OPEN]
- **progress_status**: instrumenting
- **Issue**: Type `0` parse fails when selecting the first address and tapping `parse`.
- **Goal**: Capture the real WebView-loaded response for the selected type `0` address before deciding the final parsing strategy.
- **Evidence Source**: device `hilog`, project `LsLogger`.

## Hypotheses
| ID | Hypothesis | Evidence Point |
|----|------------|----------------|
| A | The main type `0` address returns JSON rather than HTML. | `body.innerText` starts with `{` or `[`. |
| B | WebView wraps a JSON response in an HTML/pre container. | `innerHTML` contains `<pre>` while `innerText` contains raw JSON. |
| C | The detail page response shape differs from the existing m3u8/title regex. | First detail page `innerHTML`/`innerText` lacks current markers. |
| D | The selected first address is still an HTML page and the current URL derivation is wrong. | Loaded URL/response mismatch expected host/path. |

## Instrumentation
- Add temporary `[DEBUG][t0-real-response]` logs in `SyncPage` WebView loading and capture flow.
- Capture URL, content lengths, and bounded excerpts for `innerHTML` and `body.innerText`.

## Evidence
- Device parse with derived URL loaded `https://api.mdyy65323788.957119.xyz/v/list?recommendType=NEW&page=0&pageSize=32`.
- Device `HttpClient` direct request to that derived API failed: `网络请求失败: [object Object]`.
- Mac direct request to the derived API failed TLS verification: certificate subject name does not match `api.mdyy65323788.957119.xyz`.
- Mac direct request to the selected original URL succeeded:
  - URL: `https://mdyy65323788.957119.xyz/index.php/vod/type/id/25.htm`
  - status: `HTTP/2 200`
  - content-type: `text/html; charset=utf-8`
  - title: `AI 色剧-第1页-麻豆影院`
- Real list item shape:
  - list item anchor: `<a class="md0" href="/index.php/vod/role/id/116865.html">`
  - image/title source: `<img class="lazyload" data-src="..." alt="《古相思曲 古风营帐中的双女主命运纠葛》">`
- Real role page shape:
  - title: `<h2>片名：《古相思曲 古风营帐中的双女主命运纠葛》</h2>`
  - play button target: `onclick="window.location.href='/index.php/vod/detail/id/116865.html'"`
- Real playback page shape:
  - m3u8 source: `<mark id="bfz" data-user-name="第01集$https://c10.hs100.top/20261111/0813d6b502cd0e44/index.m3u8"></mark>`

## Planned Parser Strategy
- Do not derive `api.<host>/v/list`; the actual selected address is an HTML list page and the derived API fails TLS/transport.
- Match type `2` style: direct HTML parsing with small regexes and no API dependency.
- Main page parse:
  - Extract item ids from anchors matching `/index.php/vod/role/id/(\d+).html`.
  - Extract optional names from adjacent `alt="《...》"` when needed.
  - Create intermediate pages as `${host}/index.php/vod/role/id/${id}.html`.
  - Use `/index.php/vod/role/id/${id}.html` or `id` as the stable uploaded key.
- Sub page parse:
  - If content is a role page, extract `/index.php/vod/detail/id/<id>.html` from `window.location.href=...`, then load that second page before extracting downloads. This requires type `0` to support a two-step detail load, unlike simple type `2`.
  - If content is already a playback page, extract `mark#bfz[data-user-name]`.
  - Parse m3u8 from the part after `$` in `data-user-name`, supporting multiple `$url` segments if they appear later.
  - Parse name from `<title>《...》-麻豆影院</title>` or `<h2>片名：...</h2>`.
- Controller adjustment:
  - Add an optional parser hook for nested detail pages, or let type `0` return role-page entries then have a dedicated second load path. Keep this scoped to type `0` so existing type `2` behavior stays unchanged.
