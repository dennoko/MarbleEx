//----------------------------------------------------------------------------------------------------------------------
// MarbleEx - 動的マーブル / オーロラ / ボロノイ / カースティクス パターン
//
// 設計方針:
//   - シェーダーキーワードを増やさないため、全パターンを1本にコンパイルして
//     uniform 分岐（_CustomMarbleMode）で切り替える。実行時は1経路しか通らない。
//   - ノイズ関数の実体は custom_insert.hlsl 側に通常の関数として置く。
//     巨大なマクロを書くより可読性・デバッグ性が高い。
//   - 注入は BEFORE_SHADOW 1点のみ。理由は下記。

//----------------------------------------------------------------------------------------------------------------------
// Macro

// Custom variables
#define LIL_CUSTOM_PROPERTIES \
    float4  _CustomMarbleColor1;        \
    float4  _CustomMarbleColor2;        \
    float4  _CustomMarbleColor3;        \
    float4  _CustomMarbleMask_ST;       \
    float   _CustomMarbleMaskChannel;   \
    float   _CustomMarbleMaskInvert;    \
    float   _CustomMarbleEnable;        \
    float   _CustomMarbleMode;          \
    float   _CustomMarbleUVMode;        \
    float   _CustomMarbleScale;         \
    float   _CustomMarbleSpeed;         \
    float   _CustomMarbleDetail;        \
    float   _CustomMarbleBlend;         \
    float   _CustomMarbleEmission;      \
    float   _CustomMarbleWarp;          \
    float   _CustomMarbleVeinFreq;      \
    float   _CustomMarbleContrast;      \
    float   _CustomAuroraStretch;       \
    float   _CustomAuroraSharpness;     \
    float   _CustomVoronoiEdge;         \
    float   _CustomVoronoiBreath;       \
    float   _CustomVoronoiCellVariation;\
    float   _CustomCausticsSharpness;   \
    float   _CustomCausticsLayerScale;

// Custom textures
#define LIL_CUSTOM_TEXTURES \
    TEXTURE2D(_CustomMarbleMask);

// Add vertex shader input
//#define LIL_REQUIRE_APP_POSITION
//#define LIL_REQUIRE_APP_TEXCOORD0
//#define LIL_REQUIRE_APP_TEXCOORD1
//#define LIL_REQUIRE_APP_TEXCOORD2
//#define LIL_REQUIRE_APP_TEXCOORD3
//#define LIL_REQUIRE_APP_TEXCOORD4
//#define LIL_REQUIRE_APP_TEXCOORD5
//#define LIL_REQUIRE_APP_TEXCOORD6
//#define LIL_REQUIRE_APP_TEXCOORD7
//#define LIL_REQUIRE_APP_COLOR
//#define LIL_REQUIRE_APP_NORMAL
//#define LIL_REQUIRE_APP_TANGENT
//#define LIL_REQUIRE_APP_VERTEXID

// Add vertex shader output
// UV Mode の Object Space / World Space を成立させるために座標を v2f へ強制的に載せる。
// キーワードを増やせない以上、モード選択を実行時に切り替えるには常時必要。
//
//   POSITION_WS: forward_normal では無条件に載るが、forward_lite では
//                BRP のフォワードベースかつ LPPV 無しのとき載らないため強制が要る。
//   POSITION_OS: forward_normal は FORCE で載る。
//                forward_lite は positionOS を扱う経路自体が無いため載せられない。
//                → Lite 系バリアントでは UV Mode = Object Space が機能しない。
//                  CustomInspector 側で該当時に警告を出している。
//
// lilToon 2.3.4 に存在する FORCE マクロは
// TEXCOORD0 / NORMAL / TANGENT / POSITION_OS / POSITION_WS の5種のみ（TEXCOORD1 は無い）。
#define LIL_V2F_FORCE_POSITION_OS
#define LIL_V2F_FORCE_POSITION_WS
//#define LIL_V2F_FORCE_TEXCOORD0
//#define LIL_V2F_FORCE_NORMAL
//#define LIL_V2F_FORCE_TANGENT
//#define LIL_CUSTOM_V2F_MEMBER(id0,id1,id2,id3,id4,id5,id6,id7)

//#define LIL_CUSTOM_VERT_COPY
//#define LIL_CUSTOM_VERTEX_OS
//#define LIL_CUSTOM_VERTEX_WS

//----------------------------------------------------------------------------------------------------------------------
// Pixel shader
//
// 注入点に BEFORE_SHADOW を選んだ理由:
//   - lil_pass_forward_normal.hlsl / lil_pass_forward_lite.hlsl の両方に存在する。
//     BEFORE_MAIN2ND は Lite パスに無いため Lite 系バリアントで効果が出ない。
//   - メインカラー・レイヤーカラー・アルファマスク・法線の確定後、ライティング適用前。
//     つまり fd.col.rgb がアルベドそのものであり、この後の陰影計算に自然に乗る。
//   - lil_common_frag_alpha.hlsl（ShadowCaster / DepthOnly）には存在しないため、
//     アルファしか要らないパスでノイズ計算が走らない。
//   - fd.emissionColor は lilInitFragData() で 0 に初期化され、以降は全て += で
//     加算されるため、ここで加算しても後段のエミッションと共存できる。

// マスクは常にメインUV基準（タイリング・オフセットは _CustomMarbleMask_ST で調整）。
// パターン座標が Object / World Space でもマスクはメッシュに貼り付いたままにしたいため、
// _mexUV とは独立してサンプリングしている。
#define BEFORE_SHADOW \
    if (_CustomMarbleEnable > 0.5) \
    { \
        float4 _mexMaskTex = LIL_SAMPLE_2D_ST(_CustomMarbleMask, lil_sampler_linear_repeat, fd.uvMain); \
        float _mexMask = lilCustomMaskChannel(_mexMaskTex, (int)_CustomMarbleMaskChannel); \
        _mexMask = lerp(_mexMask, 1.0 - _mexMask, _CustomMarbleMaskInvert); \
        float _mexAmount = _CustomMarbleBlend * _mexMask; \
        float2 _mexUV = lilCustomMarbleExCoord(fd.uvMain, fd.positionOS, fd.positionWS, (int)_CustomMarbleUVMode) * _CustomMarbleScale; \
        float _mexAA = lilCustomMarbleExAA(_mexUV); \
        if (_mexAmount > 0.0) \
        { \
            float _mexTime = LIL_TIME * _CustomMarbleSpeed; \
            float _mexIntensity; \
            float4 _mexPat = lilCustomMarbleExPattern(_mexUV, _mexTime, _mexAA, (int)_CustomMarbleMode, _mexIntensity); \
            fd.col.rgb = lerp(fd.col.rgb, _mexPat.rgb, _mexAmount * _mexPat.a); \
            fd.albedo = fd.col.rgb; \
            fd.emissionColor += _mexPat.rgb * (_mexIntensity * _CustomMarbleEmission * _mexMask); \
        } \
    }

//----------------------------------------------------------------------------------------------------------------------
// Information about variables
//----------------------------------------------------------------------------------------------------------------------

//----------------------------------------------------------------------------------------------------------------------
// Vertex shader inputs (appdata structure)
//
// Type     Name                    Description
// -------- ----------------------- --------------------------------------------------------------------
// float4   input.positionOS        POSITION
// float2   input.uv0               TEXCOORD0
// float2   input.uv1               TEXCOORD1
// float2   input.uv2               TEXCOORD2
// float2   input.uv3               TEXCOORD3
// float2   input.uv4               TEXCOORD4
// float2   input.uv5               TEXCOORD5
// float2   input.uv6               TEXCOORD6
// float2   input.uv7               TEXCOORD7
// float4   input.color             COLOR
// float3   input.normalOS          NORMAL
// float4   input.tangentOS         TANGENT
// uint     vertexID                SV_VertexID

//----------------------------------------------------------------------------------------------------------------------
// Vertex shader outputs or pixel shader inputs (v2f structure)
//
// The structure depends on the pass.
// Please check lil_pass_xx.hlsl for details.
//
// Type     Name                    Description
// -------- ----------------------- --------------------------------------------------------------------
// float4   output.positionCS       SV_POSITION
// float2   output.uv01             TEXCOORD0 TEXCOORD1
// float2   output.uv23             TEXCOORD2 TEXCOORD3
// float3   output.positionOS       object space position
// float3   output.positionWS       world space position
// float3   output.normalWS         world space normal
// float4   output.tangentWS        world space tangent

//----------------------------------------------------------------------------------------------------------------------
// Variables commonly used in the forward pass
//
// These are members of `lilFragData fd`
//
// Type     Name                    Description
// -------- ----------------------- --------------------------------------------------------------------
// float4   col                     lit color
// float3   albedo                  unlit color
// float3   emissionColor           color of emission
// -------- ----------------------- --------------------------------------------------------------------
// float3   lightColor              color of light
// float3   indLightColor           color of indirectional light
// float3   addLightColor           color of additional light
// float    attenuation             attenuation of light
// float3   invLighting             saturate((1.0 - lightColor) * sqrt(lightColor));
// -------- ----------------------- --------------------------------------------------------------------
// float2   uv0                     TEXCOORD0
// float2   uv1                     TEXCOORD1
// float2   uv2                     TEXCOORD2
// float2   uv3                     TEXCOORD3
// float2   uvMain                  Main UV
// float2   uvMat                   MatCap UV
// float2   uvRim                   Rim Light UV
// float2   uvPanorama              Panorama UV
// float2   uvScn                   Screen UV
// bool     isRightHand             input.tangentWS.w > 0.0;
// -------- ----------------------- --------------------------------------------------------------------
// float3   positionOS              object space position
// float3   positionWS              world space position
// float4   positionCS              clip space position
// float4   positionSS              screen space position
// float    depth                   distance from camera
// -------- ----------------------- --------------------------------------------------------------------
// float3x3 TBN                     tangent / bitangent / normal matrix
// float3   T                       tangent direction
// float3   B                       bitangent direction
// float3   N                       normal direction
// float3   V                       view direction
// float3   L                       light direction
// float3   origN                   normal direction without normal map
// float3   origL                   light direction without sh light
// float3   headV                   middle view direction of 2 cameras
// float3   reflectionN             normal direction for reflection
// float3   matcapN                 normal direction for reflection for MatCap
// float3   matcap2ndN              normal direction for reflection for MatCap 2nd
// float    facing                  VFACE
// -------- ----------------------- --------------------------------------------------------------------
// float    vl                      dot(viewDirection, lightDirection);
// float    hl                      dot(headDirection, lightDirection);
// float    ln                      dot(lightDirection, normalDirection);
// float    nv                      saturate(dot(normalDirection, viewDirection));
// float    nvabs                   abs(dot(normalDirection, viewDirection));
// -------- ----------------------- --------------------------------------------------------------------
// float4   triMask                 TriMask (for lite version)
// float3   parallaxViewDirection   mul(tbnWS, viewDirection);
// float2   parallaxOffset          parallaxViewDirection.xy / (parallaxViewDirection.z+0.5);
// float    anisotropy              strength of anisotropy
// float    smoothness              smoothness
// float    roughness               roughness
// float    perceptualRoughness     perceptual roughness
// float    shadowmix               this variable is 0 in the shadow area
// float    audioLinkValue          volume acquired by AudioLink
// -------- ----------------------- --------------------------------------------------------------------
// uint     renderingLayers         light layer of object (for URP / HDRP)
// uint     featureFlags            feature flags (for HDRP)
// uint2    tileIndex               tile index (for HDRP)
