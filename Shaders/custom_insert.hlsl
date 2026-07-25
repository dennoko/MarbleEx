// このファイルは Unity ライブラリと lil_common.hlsl の #include 直後に挿入される（lilSubShaderInsert）
// そのため LIL_CUSTOM_PROPERTIES で宣言した変数もここから直接参照できる。
//
// パスごとに以下のマクロが定義されているので #if defined(...) で分岐できる
//
//   LIL_PASS_FORWARD       : ForwardBase (BRP) / UniversalForward (URP) / Forward (HDRP)
//   LIL_PASS_FORWARDADD    : ForwardAdd (BRP のみ)
//   LIL_PASS_SHADOWCASTER  : ShadowCaster
//   LIL_PASS_DEPTHONLY     : DepthOnly (URP / HDRP のみ)
//   LIL_PASS_DEPTHNORMALS  : DepthNormals (URP のみ)
//   LIL_PASS_MOTIONVECTORS : MotionVectors (HDRP のみ)
//   LIL_PASS_META          : META (ライトマップベイク用)

#ifndef LIL_CUSTOM_MARBLEEX_INCLUDED
#define LIL_CUSTOM_MARBLEEX_INCLUDED

//----------------------------------------------------------------------------------------------------------------------
// パターン種別（_CustomMarbleMode の値と lilCustomShaderProperties.lilblock の [lilEnum] 順を一致させること）

#define LIL_MARBLEEX_MODE_MARBLE      0
#define LIL_MARBLEEX_MODE_AURORA      1
#define LIL_MARBLEEX_MODE_VORONOI     2
#define LIL_MARBLEEX_MODE_CAUSTICS    3

//----------------------------------------------------------------------------------------------------------------------
// 合成方法（_CustomMarbleBlendMode の値と lilCustomShaderProperties.lilblock の [lilEnum] 順を一致させること）

#define LIL_MARBLEEX_BLEND_REPLACE    0
#define LIL_MARBLEEX_BLEND_ADD        1
#define LIL_MARBLEEX_BLEND_SCREEN     2

//----------------------------------------------------------------------------------------------------------------------
// カースティクス専用の内部係数
//
// Scale / Speed は全モード共通のプロパティだが、カースティクスだけは
// 必要な密度と速度のレンジが他モードと大きく違う。スライダーを他モードと
// 同じ感覚で使えるようにするため、モード内部で倍率を掛けて辻褄を合わせる。
//
//   DENSITY: 網目として成立するには視界内に 8〜16 セル欲しい。
//            共有 Scale の実用域（4〜6）× 2.5 でその範囲に収まる。
//   TIME   : 見た目の速さを決めるのは母点の周回周期ではなく、
//            「光の線が自分の線幅ぶん動く頻度」= きらめきの周波数。
//            母点の周回角速度 ω = Speed × TIME、周回半径 0.5 セルなので
//            母点速度は 0.5ω セル/秒、境界線はその約半分の 0.25ω セル/秒で動く。
//            Sharpness 7 なら線幅 1/7 = 0.143 セルなので
//              きらめき周波数 = 0.25ω / 0.143 ≒ 1.75ω [Hz]
//            実際の水面は 1〜3 Hz なので、Speed 0.5 で中央の 1.75 Hz に
//            乗る × 2 を採用する（Speed 0.3〜0.9 で 1〜3 Hz をカバー）。

#define LIL_MARBLEEX_CAUSTICS_DENSITY 2.5
#define LIL_MARBLEEX_CAUSTICS_TIME    2.0

//----------------------------------------------------------------------------------------------------------------------
// ノイズ基本関数
//
// ハッシュは sin() を使わない Hoskins 系を採用している。
// Quest（Adreno）では frac(sin(x)*large) が精度不足で破綻することがあるため。

float2 lilCustomHash22(float2 p)
{
    float3 p3 = frac(p.xyx * float3(0.1031, 0.1030, 0.0973));
    p3 += dot(p3, p3.yzx + 33.33);
    return frac((p3.xx + p3.yz) * p3.zy);
}

float lilCustomHash21(float2 p)
{
    float3 p3 = frac(p.xyx * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return frac((p3.x + p3.y) * p3.z);
}

// 2D 勾配ノイズ（Perlin 相当）。戻り値は 0..1。
// 値ノイズより格子が目立たず、マーブルの滑らかな渦に向く。
float lilCustomGradNoise(float2 p)
{
    float2 i = floor(p);
    float2 f = frac(p);
    float2 u = f * f * (3.0 - 2.0 * f);

    float a = dot(lilCustomHash22(i + float2(0.0, 0.0)) * 2.0 - 1.0, f - float2(0.0, 0.0));
    float b = dot(lilCustomHash22(i + float2(1.0, 0.0)) * 2.0 - 1.0, f - float2(1.0, 0.0));
    float c = dot(lilCustomHash22(i + float2(0.0, 1.0)) * 2.0 - 1.0, f - float2(0.0, 1.0));
    float d = dot(lilCustomHash22(i + float2(1.0, 1.0)) * 2.0 - 1.0, f - float2(1.0, 1.0));

    return lerp(lerp(a, b, u.x), lerp(c, d, u.x), u.y) + 0.5;
}

// fBm 2オクターブ（ドメインワープ用の粗いノイズ）
float lilCustomFbm2(float2 p, float gain)
{
    float v = lilCustomGradNoise(p) - 0.5;
    v += (lilCustomGradNoise(p * 2.03 + 17.3) - 0.5) * gain;
    return v / (1.0 + gain) + 0.5;
}

// fBm 4オクターブ（最終ディテール用）
float lilCustomFbm4(float2 p, float gain)
{
    float amp = 1.0;
    float sum = 0.0;
    float norm = 0.0;

    sum += (lilCustomGradNoise(p) - 0.5) * amp;                     norm += amp; amp *= gain;
    sum += (lilCustomGradNoise(p * 2.03 + 17.3) - 0.5) * amp;       norm += amp; amp *= gain;
    sum += (lilCustomGradNoise(p * 4.01 + 43.7) - 0.5) * amp;       norm += amp; amp *= gain;
    sum += (lilCustomGradNoise(p * 8.05 + 91.1) - 0.5) * amp;       norm += amp;

    return sum / max(norm, 1e-4) + 0.5;
}

// ボロノイ。母点を時間で円運動させることで細胞が「呼吸」する。
// 戻り値: x = F1距離, y = F2距離, z = 最近傍セルの乱数(0..1)
float3 lilCustomVoronoi(float2 p, float t, float jitter)
{
    float2 n = floor(p);
    float2 f = frac(p);

    float f1 = 8.0;
    float f2 = 8.0;
    float cellRand = 0.0;

    [unroll]
    for (int j = -1; j <= 1; j++)
    {
        [unroll]
        for (int i = -1; i <= 1; i++)
        {
            float2 g = float2(i, j);
            float2 o = lilCustomHash22(n + g);
            // 母点を極座標的に周回させる（位相はセルごとにランダム）
            o = 0.5 + jitter * 0.5 * sin(t + LIL_PI * 2.0 * o);

            float2 r = g + o - f;
            float d = dot(r, r);

            if (d < f1)
            {
                f2 = f1;
                f1 = d;
                cellRand = lilCustomHash21(n + g);
            }
            else if (d < f2)
            {
                f2 = d;
            }
        }
    }
    return float3(sqrt(f1), sqrt(f2), cellRand);
}

//----------------------------------------------------------------------------------------------------------------------
// カラー合成ヘルパー

// 3色パレット。t=0→c1, 0.5→c2, 1→c3
float3 lilCustomPalette3(float t, float3 c1, float3 c2, float3 c3)
{
    t = saturate(t);
    return t < 0.5 ? lerp(c1, c2, t * 2.0)
                   : lerp(c2, c3, t * 2.0 - 1.0);
}

// マスクテクスチャから使用チャンネルを取り出す。0:R 1:G 2:B 3:A
float lilCustomMaskChannel(float4 tex, int ch)
{
    float4 sel = float4(ch == 0, ch == 1, ch == 2, ch == 3);
    return dot(tex, sel);
}

// 半透明マテリアルでアルファを持ち上げる際の重み（0..1）を返す。
// 「模様のうち目立たせたい成分」をどう定義するかをモードで選ぶ。
//   0: Off       … 常に 0（持ち上げなし）
//   1: Saturation… HSV の S 相当。鮮やかな部分ほど不透明になる。
//   2: Luminance … Rec.709 輝度。明るい部分ほど不透明になる。
//   3: Pattern   … パターン強度そのもの。脈・カーテン・輪郭に素直に追従する。
//
// mode はマテリアル定数なので分岐は実行時に1経路へ畳まれる。
float lilCustomAlphaDriver(float3 col, float intensity, int mode)
{
    float mx = max(col.r, max(col.g, col.b));
    float mn = min(col.r, min(col.g, col.b));
    // HDR カラーで mx が 1 を超えても S は 0..1 に収まる
    float sat = (mx - mn) / max(mx, 1e-4);

    // 輝度は HDR で 1 を超え得るため呼び出し側の saturate に任せる
    float lum = dot(col, float3(0.2126, 0.7152, 0.0722));

    float d = 0.0;

    [branch]
    if (mode == 1)      d = sat;
    else if (mode == 2) d = lum;
    else if (mode == 3) d = intensity;

    return saturate(d);
}

// パターン色をベースカラーへ合成する。
//   0: Replace … lerp でベースを置き換える。面全体を覆う模様（Marble / Voronoi）向け。
//   1: Add     … 加算。水面越しに投影された光（Caustics / Aurora）はこちらが正しい。
//                ベーステクスチャの質感を消さずに明るくなる。
//   2: Screen  … スクリーン合成。加算より白飛びしにくく、明るいベースでも階調が残る。
//
// mode はマテリアル定数なので分岐は実行時に1経路へ畳まれる。
float3 lilCustomBlendPattern(float3 base, float3 pat, float coverage, int mode)
{
    [branch]
    if (mode == LIL_MARBLEEX_BLEND_ADD)
    {
        return base + pat * coverage;
    }
    else if (mode == LIL_MARBLEEX_BLEND_SCREEN)
    {
        // ベースが HDR で 1 を超える場合は (1-base) が負になり結果も 1 を超えるが、
        // これは加算と同じ挙動なので意図通り。pat 側だけ saturate しておく。
        return 1.0 - (1.0 - base) * (1.0 - saturate(pat * coverage));
    }
    return lerp(base, pat, coverage);
}

//----------------------------------------------------------------------------------------------------------------------
// パターン本体
//
// いずれも uv（スケール適用済み）と t（速度適用済みの時間）を受け取り、
// float4(rgb = パターン色, a = 被覆率 0..1) を返す。さらに out intensity で発光強度を返す。
//
// 被覆率と発光強度を分けているのは、模様の性質が2種類あるため:
//   - マーブル / ボロノイ … 面全体を覆う模様。被覆率は 1.0 固定で、
//                            パレット色そのものが見た目を決める。
//   - オーロラ / カースティクス … 隙間のある発光模様。薄い部分ではベースカラーを
//                            透かせたいので被覆率に強度をそのまま使う。
// 両者を a 一本で兼ねるとマーブルの暗部がベースカラーに戻ってしまい、
// パレットの Color 1 が事実上使えなくなる。

// 1. ドメインワープ・マーブル
//    fBm で UV を二重に歪ませたうえで sin() の縞（vein）を通す古典的な大理石構成。
float4 lilCustomPatternMarble(float2 uv, float t, float warp, float veinFreq, float contrast, float gain,
                              float3 c1, float3 c2, float3 c3, out float intensity)
{
    // 1段目の歪み
    float2 q = float2(lilCustomFbm2(uv + float2(0.0, t * 0.25), gain),
                      lilCustomFbm2(uv + float2(5.2, 1.3) + float2(t * 0.2, 0.0), gain)) * 2.0 - 1.0;

    // 2段目の歪み（1段目の結果を入力に混ぜる = Domain Warping）
    float2 r = float2(lilCustomFbm2(uv + warp * q + float2(1.7, 9.2) + t * 0.15, gain),
                      lilCustomFbm2(uv + warp * q + float2(8.3, 2.8) - t * 0.12, gain)) * 2.0 - 1.0;

    float n = lilCustomFbm4(uv + warp * r, gain);

    // vein: 歪んだ座標に縞を通すと大理石の脈になる
    float vein = sin((uv.x + uv.y * 0.35 + n * 2.0) * veinFreq) * 0.5 + 0.5;
    float v = saturate(lerp(n, vein, 0.55));

    // コントラストで脈の締まりを調整
    v = saturate((v - 0.5) * contrast + 0.5);

    float3 col = lilCustomPalette3(v, c1, c2, c3);
    intensity = v;
    // 大理石は面全体を覆う模様なので被覆率は 1.0
    return float4(col, 1.0);
}

// 2. オーロラ・雲流
//    縦に引き伸ばした fBm を速度違いで多層スクロールさせる。
float4 lilCustomPatternAurora(float2 uv, float t, float stretch, float sharpness, float gain,
                              float3 c1, float3 c2, float3 c3, out float intensity)
{
    // 縦方向を潰す = 横に伸びたカーテン状のノイズになる
    float2 sv = float2(uv.x, uv.y / max(stretch, 0.01));

    float l1 = lilCustomFbm4(sv + float2(t * 0.35, t * 0.05), gain);
    float l2 = lilCustomFbm2(sv * 1.7 + float2(-t * 0.22, t * 0.11), gain);

    // 2層の積でカーテンの隙間を作り、pow で発光の芯を細くする
    float curtain = saturate(l1 * (0.5 + l2));
    curtain = pow(curtain, max(sharpness, 0.01));

    // 高さ方向のグラデーション（下ほど濃く、上ほど淡く）
    float h = saturate(uv.y * 0.5 + 0.5 + (l2 - 0.5) * 0.6);

    float3 col = lilCustomPalette3(h, c1, c2, c3);
    intensity = curtain;
    // カーテンの隙間ではベースカラーを透かせたいので被覆率＝強度
    return float4(col, curtain);
}

// 3. 細胞脈動・ボロノイブリージング
//    母点を周回させ、セル境界（F2-F1）を輪郭として抽出する。
// aa には呼び出し側で求めた UV の変化量を渡す。
// fwidth は分岐の外で評価しないと、分岐内では微分が不定になり得るため。
float4 lilCustomPatternVoronoi(float2 uv, float t, float aa, float edgeWidth, float breath, float cellVariation,
                               float3 c1, float3 c2, float3 c3, out float intensity)
{
    float3 v = lilCustomVoronoi(uv, t, breath);

    float border = v.y - v.x;
    // 縮小時のちらつきを抑えるアンチエイリアス幅
    float edge = 1.0 - smoothstep(edgeWidth - aa, edgeWidth + aa, border);

    // セルごとの色ゆらぎ。呼吸に同期して明滅させる
    float pulse = sin(t + v.z * LIL_PI * 2.0) * 0.5 + 0.5;
    float cellT = lerp(saturate(1.0 - v.x), v.z, cellVariation);
    cellT = saturate(cellT * lerp(1.0, pulse, cellVariation));

    float3 body = lilCustomPalette3(cellT, c1, c2, c3);
    float3 col  = lerp(body, c3, edge);

    // 発光は輪郭を強調したいので edge を強めに乗せる
    intensity = saturate(cellT * 0.5 + edge);
    // 細胞模様は面全体を覆う模様なので被覆率は 1.0
    return float4(col, 1.0);
}

// 4. 水底のカースティクス
//    セル境界（F2-F1）を光の網目として抽出し、逆方向にスクロールする2層を
//    加算して交差点を輝かせる。
//
//    F1（母点までの距離）を明るさに使うとセル中心が明るい円形になり、
//    網目ではなく水玉模様になってしまう。カースティクスの本質は光線が
//    折り畳まれた「線状の集光」なので、距離そのものではなく境界を取る。
//    また2層を乗算すると両層が同時に明るい交点しか残らず網目が途切れるため、
//    加算で重ねて交差部だけが白く飽和するようにしている。
//
//    座標を低周波 fBm でドメインワープすることで、ボロノイそのままの
//    直線的な多角形ではなく、水面のうねりに沿った有機的な網目になる。
//
// aa には呼び出し側で求めた UV の変化量を渡す。細い高輝度ラインは
// AA 無しだと VR の遠景・傾いた面で激しくちらつくため必須。
float4 lilCustomPatternCaustics(float2 uv, float t, float aa, float sharpness, float layerScale, float warp,
                                float3 c1, float3 c2, float3 c3, out float intensity)
{
    float2 p = uv * LIL_MARBLEEX_CAUSTICS_DENSITY;
    float paa = aa * LIL_MARBLEEX_CAUSTICS_DENSITY;
    t *= LIL_MARBLEEX_CAUSTICS_TIME;

    // 水面のうねり（低周波ドメインワープ）。warp は uniform なので実行時に畳まれる。
    float2 q = p;
    [branch]
    if (warp > 0.0)
    {
        float2 w = float2(lilCustomFbm2(p * 0.5 + float2(t * 0.05, 0.0), 0.5),
                          lilCustomFbm2(p * 0.5 + float2(5.2, 1.3) + float2(0.0, t * 0.04), 0.5)) * 2.0 - 1.0;
        q = p + warp * w;
    }

    // 水面のゆらぎは常に大きく動かしたいので母点の周回量は固定。
    // 2層目は位相をずらして（+2.1）同じ呼吸が重ならないようにする。
    float3 a = lilCustomVoronoi(q + float2(t * 0.10, t * 0.07), t, 1.0);
    float3 b = lilCustomVoronoi(q * layerScale - float2(t * 0.08, t * 0.13), t * 1.3 + 2.1, 1.0);

    // sharpness は「線の細さ」= 1/線幅（セル単位）。pow の指数にすると
    // 応答が指数関数になりスライダーの大半が死ぬため、幅として線形に扱う。
    //
    // 線幅が 1 ピクセルを下回るとエイリアスするので下限を aa で押さえ、
    // 広げた分だけ暗くしてエネルギーを保存する。これにより遠景では
    // 白飛びせずパターンの平均輝度へ収束する（ミップマップ相当の挙動）。
    //
    // 下限 2.0 はスライダーの下限と揃えてある。これは 0 除算避けだけでなく、
    // 旧バージョン（Sharpness が pow の指数で既定 1.0）で作られたマテリアルが
    // 線幅 1.0 セル = 全面白のまま表示されるのを防ぐ役割も持つ。
    float w0  = 1.0 / max(sharpness, 2.0);
    float wid = max(w0, paa * 1.5);
    float dim = w0 / wid;
    float inv = 1.0 / wid;

    float ea = saturate(1.0 - (a.y - a.x) * inv);
    float eb = saturate(1.0 - (b.y - b.x) * inv);

    // 二乗で芯を締め、加算で交差点を明るくする
    float caustics = saturate((ea * ea + eb * eb) * dim);

    float3 col = lilCustomPalette3(caustics, c1, c2, c3);
    intensity = caustics;
    // 網目の暗い部分では水底（ベースカラー）を透かせたいので被覆率＝強度
    return float4(col, caustics);
}

//----------------------------------------------------------------------------------------------------------------------
// ディスパッチ
//
// シェーダーキーワードを増やさない方針のため、全パターンを1本にコンパイルして
// uniform 分岐で切り替える。分岐条件がマテリアル定数なので実行時は1経路しか通らない。

// UV の変化量（アンチエイリアス幅）。
// fwidth は quad 内で一様な制御フロー上でしか正しく評価できないため、
// マスク値による分岐に入る前に呼び出し側で求めてもらう。
float lilCustomMarbleExAA(float2 uv)
{
    return max(length(fwidth(uv)) * 0.5, 1e-4);
}

// 戻り値: rgb = パターン色, a = 被覆率
// out intensity = 発光強度（エミッションの重み付けに使う）
float4 lilCustomMarbleExPattern(float2 uv, float t, float aa, int mode, out float intensity)
{
    float3 c1 = _CustomMarbleColor1.rgb;
    float3 c2 = _CustomMarbleColor2.rgb;
    float3 c3 = _CustomMarbleColor3.rgb;
    float gain = _CustomMarbleDetail;

    float4 result = float4(c1, 0.0);
    intensity = 0.0;

    [branch]
    if (mode == LIL_MARBLEEX_MODE_AURORA)
    {
        result = lilCustomPatternAurora(uv, t, _CustomAuroraStretch, _CustomAuroraSharpness, gain, c1, c2, c3, intensity);
    }
    else if (mode == LIL_MARBLEEX_MODE_VORONOI)
    {
        result = lilCustomPatternVoronoi(uv, t, aa, _CustomVoronoiEdge, _CustomVoronoiBreath, _CustomVoronoiCellVariation, c1, c2, c3, intensity);
    }
    else if (mode == LIL_MARBLEEX_MODE_CAUSTICS)
    {
        result = lilCustomPatternCaustics(uv, t, aa, _CustomCausticsSharpness, _CustomCausticsLayerScale, _CustomCausticsWarp, c1, c2, c3, intensity);
    }
    else
    {
        result = lilCustomPatternMarble(uv, t, _CustomMarbleWarp, _CustomMarbleVeinFreq, _CustomMarbleContrast, gain, c1, c2, c3, intensity);
    }

    return result;
}

// パターン用の座標を選択する。
// 0: メインUV / 1: オブジェクト空間 / 2: ワールド空間
//
// オブジェクト/ワールド空間は UV 継ぎ目の無いシームレスな模様になる。
// XZ 平面に Y を混ぜているのは、真上・真下から見たときに模様が潰れないようにするため。
//
// 制約:
//   - lilToon 2.3.4 に LIL_V2F_FORCE_TEXCOORD1 が無く uv1 の存在を保証できないため UV1 は用意していない。
//   - Lite 系バリアントは positionOS を v2f に載せる経路が無いため、
//     Object Space を選んでも fd.positionOS が 0 のままとなり模様が出ない。
float2 lilCustomMarbleExCoord(float2 uvMain, float3 positionOS, float3 positionWS, int uvMode)
{
    float2 uv = uvMain;

    [branch]
    if (uvMode == 1)
    {
        uv = positionOS.xz + positionOS.y * 0.5;
    }
    else if (uvMode == 2)
    {
        uv = positionWS.xz + positionWS.y * 0.5;
    }

    return uv;
}

#endif // LIL_CUSTOM_MARBLEEX_INCLUDED
