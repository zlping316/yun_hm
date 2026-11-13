export const T_MAIN_SAMPLE: string =
  '<a class="md0" href="/index.php/vod/role/id/116865.html">' +
  '<figure><img class="lazyload" data-src="https://img.test/a.jpg" ' +
  'alt="《古相思曲 古风营帐中的双女主命运纠葛》"></figure></a>' +
  '<a class="md0" href="/index.php/vod/role/id/116865.html"></a>' +
  '<a class="md0" href="/index.php/vod/role/id/116866.html"></a>';

export const T_ROLE_SAMPLE: string =
  '<h2>片名：《古相思曲 古风营帐中的双女主命运纠葛》</h2>' +
  '<button class="play-btn" onclick="window.location.href=\'/index.php/vod/detail/id/116865.html\'">点此立即观看①</button>' +
  '<button class="play-btn" onclick="window.location.href=\'/index.php/vod/detail/id/116865.html\'">点此立即观看②</button>';

export const T_PLAY_SAMPLE: string =
  '<title>《古相思曲 古风营帐中的双女主命运纠葛》-麻豆影院</title>' +
  '<mark id="bfz" data-user-name="第01集$https://c10.hs100.top/20261111/0813d6b502cd0e44/index.m3u8"></mark>';

export const A_MAIN_SAMPLE: string =
  '\\n\\u003Ca href=\\"/index.php/&amp;m=item-a\\" title= ' +
  '\\n\\u003Ca href=\\"/index.php/&amp;m=item-b\\" title=';

export const A_SUB_SAMPLE: string =
  '"link_next\\":\\"\\",\\"link_pre\\":\\"\\",\\"url\\":\\"stream-key\\",' +
  '\\"url_next\\":\\"\\",\\"from\\":\\"dplayer ' +
  'class=\\"content-title\\">A sample\\u003C/h1>';

export const A_DPLAYER_SAMPLE: string =
  'var urls = "https://media.test/a/master.m3u8";';

export const HUADU_MAIN_SAMPLE: string =
  'href=\\"/voddetailhd-a.html\\" href=\\"/voddetailhd-b.html\\"';

export const HUADU_SUB_SAMPLE: string =
  'title>正在播放 《HuaDu sample - 花都影视-花都资源》 ' +
  'player_aaaa={\\"url\\":\\"https:\\/\\/media.test\\/huadu\\/master.m3u8&amp;pic=https://img.test/a.jpg\\"}';

export const F404_MAIN_SAMPLE: string =
  'class=\\"content\\">\\n\\t\\t\\t\\t\\t\\t\\t\\u003Ca ' +
  'href=\\"/key-f/a/b/c/d\\" title=\\"F404 sample\\"';

export const F404_SUB_SAMPLE: string =
  '\\"link_pre\\":\\"\\",\\"url\\":\\"https:\\/\\/media.test\\/f404\\/master.m3u8\\",' +
  '\\"url_next id=\\"Video-Title\\">F404 sample\\u003C/h3>';

export const MADOU_MAIN_SAMPLE: string =
  'u003Carticle>\\n\\u003Ca href=\\"/posts/madou-a\\">\\n\\u003Cfigure>\\u003Cimg';

export const MADOU_SUB_SAMPLE: string =
  'data-user-name=\\"source$https:\\/\\/media.test\\/madou\\/master.m3u8\\">' +
  '\\u003C/mark>\\n\\u003Cscript> ' +
  'style=\\"text-align: center; color: #000000;font-weight: 600;\\">' +
  '标题：Madou sample\\u003C/cite>';

export interface UUListSampleItem {
  id: string;
}

export interface UUListSampleData {
  lists: UUListSampleItem[];
}

export interface UUListSampleResponse {
  data: UUListSampleData;
}

export interface UUVideoSample {
  videofile: string;
  title: string;
}

export interface UUVideoSampleData {
  video: UUVideoSample;
}

export interface UUVideoSampleResponse {
  data: UUVideoSampleData;
}

export const UU_LIST_SAMPLE: UUListSampleResponse = {
  data: {
    lists: [
      { id: '101' },
      { id: '102' },
      { id: '' }
    ]
  }
};

export const UU_VIDEO_SAMPLE: UUVideoSampleResponse = {
  data: {
    video: {
      videofile: 'https://media.test/uu/master.m3u8',
      title: 'UU sample'
    }
  }
};
